#Requires -Version 5.1
# Pre-push publish-gate receipt gate (local-only; zero remote footprint). A push that publishes
# reviewable code (a refs/heads/* or refs/for/* update introducing a tip) must carry a FRESH
# worktree receipt authorizing THIS exact (remote, destination-ref, tip-commit) - written only
# after the branch-level publish gate ran (publish_gate_ready) or the user classified the push
# sandbox-only (sandbox_push_declared). Mirrors check-signoff.ps1: object-bound, identity-gated,
# honest (--no-verify / pwsh-absent bypass; the receipt is local so CI cannot reproduce it).
#
# Reads the pre-push ref-update list (`<local-ref> <local-sha> <remote-ref> <remote-sha>` lines)
# from stdin, or from -RefUpdateLines for tests. -RemoteUrl is the hook's $2 (the actual push
# URL) so a retargeted remote alias cannot reuse a receipt. Exit 0 = authorized / not-applicable,
# 1 = blocked. Identity-gated: a no-op on any repo that is not this instruction set's own.
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $RemoteName = 'origin',
    [string] $RemoteUrl = '',
    [string] $ReceiptPath = '.github/pr-quality-gate/audits/publish-gate-receipt',
    [string[]] $RefUpdateLines
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/audit-note-helpers.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/read-receipt-helpers.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitViolation = 1

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-publish-gate-prepush.ps1') -RequireGitWorkTree
}

# Identity gate FIRST (before reading stdin): on any repo that is not this instruction set's own, do nothing.
if (-not (Test-IsInstructionsRepo -RepoRoot $RepoRoot)) { exit $ExitOk }

if ($PSBoundParameters.ContainsKey('RefUpdateLines')) {
    $lines = @($RefUpdateLines)
} else {
    $stdin = [Console]::In.ReadToEnd()
    $lines = @($stdin -split "`n") | ForEach-Object { ([string]$_).TrimEnd("`r") } | Where-Object { $_.Trim() }
}

$zeroSha = '^0{40}$'
$fullSha = '^[0-9a-fA-F]{40}$'

$governed = @()
foreach ($line in $lines) {
    $t = ([string]$line).Trim()
    if (-not $t) { continue }
    $parts = @($t -split '\s+')
    if ($parts.Count -ne 4) {
        Write-Host "ERROR: malformed pre-push ref-update line (expected 4 fields): $t"
        exit $ExitViolation
    }
    $localSha = $parts[1]; $remoteRef = $parts[2]; $remoteSha = $parts[3]

    foreach ($oid in @($localSha, $remoteSha)) {
        if ($oid -notmatch $fullSha) {
            Write-Host "ERROR: pre-push ref-update line has a malformed object id '$oid': $t"
            exit $ExitViolation
        }
    }

    if ($localSha -match $zeroSha) { continue }

    # Governed = a branch (refs/heads/*) or a Gerrit review ref (refs/for/*), by the REMOTE ref
    # (the destination namespace). Tags (refs/tags/*), notes (refs/notes/*), and everything else are exempt.
    if ($remoteRef -cnotmatch '^refs/(heads|for)/') { continue }

    $governed += [pscustomobject]@{ RemoteRef = $remoteRef; LocalSha = $localSha }
}

if ($governed.Count -eq 0) { exit $ExitOk }

if ($governed.Count -gt 1) {
    Write-Host "ERROR: this push updates $($governed.Count) branch refs at once; the publish gate + panel attest ONE branch."
    Write-Host "       Push the branches separately so each carries its own publish-gate receipt."
    exit $ExitViolation
}

$update = $governed[0]

# Normalize the ACTUAL push destination (hook `$2` URL), not the alias, so a retargeted remote cannot reuse a receipt.
$remoteIdentity = if ($RemoteUrl) { Get-NormalizedRemoteIdentity -Url $RemoteUrl } else { $RemoteName }

$receiptFull = Join-Path $RepoRoot $ReceiptPath
if (-not (Test-Path -LiteralPath $receiptFull -PathType Leaf)) {
    Write-Host "ERROR: this push publishes '$($update.RemoteRef)' but no publish-gate receipt exists at '$ReceiptPath'."
    Write-Host "       Run the publish gate (pre-pr-creation-review.md) and write publish_gate_ready, OR record"
    Write-Host "       sandbox_push_declared at the pre-pr-push.md sandbox pre-check."
    Write-Host "       Schema: .github/pr-quality-gate/publish-gate-receipt.md"
    exit $ExitViolation
}

$receiptLines = @([IO.File]::ReadAllLines($receiptFull))

$markerRegex = [regex] '^(?<kind>publish_gate_ready|sandbox_push_declared):\s+(?<turn>\S+)\s+remote:(?<remote>.+?)\s+dst:(?<dst>\S+)\s+sha:(?<sha>[0-9a-fA-F]{40})\s*$'
$matchingRows = @()
foreach ($rl in $receiptLines) {
    $m = $markerRegex.Match(([string]$rl).TrimEnd("`r"))
    if (-not $m.Success) { continue }
    # git refs + normalized remote identities are case-sensitive; only the sha hex is compared case-insensitively.
    if (-not $m.Groups['remote'].Value.Equals($remoteIdentity, [System.StringComparison]::Ordinal)) { continue }
    if (-not $m.Groups['dst'].Value.Equals($update.RemoteRef, [System.StringComparison]::Ordinal)) { continue }
    if (-not $m.Groups['sha'].Value.Equals($update.LocalSha, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    $matchingRows += [pscustomobject]@{ Kind = $m.Groups['kind'].Value }
}

if ($matchingRows.Count -eq 0) {
    Write-Host "ERROR: no fresh publish-gate receipt row authorizes this push."
    Write-Host "       Expected: <publish_gate_ready|sandbox_push_declared>: <turn> remote:$remoteIdentity dst:$($update.RemoteRef) sha:$($update.LocalSha)"
    Write-Host "       A receipt bound to a different remote / branch / commit is stale - re-run the gate for THIS state."
    exit $ExitViolation
}
if ($matchingRows.Count -gt 1) {
    Write-Host "ERROR: the receipt has $($matchingRows.Count) rows authorizing this push (ambiguous). Keep exactly one."
    exit $ExitViolation
}

$row = $matchingRows[0]

$requiredReads = if ($row.Kind -eq 'publish_gate_ready') {
    @('.github/playbooks/pre-pr-push.md', '.github/playbooks/pre-pr-creation-review.md')
} else {
    @('.github/playbooks/pre-pr-push.md')
}

# Strict reads parse: ordinal dictionary; a malformed `reads=` line or a duplicate file key is a violation
# (the shared Read-ReadsReceipt hashtable is case-insensitive and silently overwrites - not strict enough here).
$violations = @()
$readMap = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
foreach ($rl in $receiptLines) {
    $parsed = ConvertFrom-ReadsLine -Line ([string]$rl)
    if (-not $parsed.IsReadsLine) { continue }
    if (-not $parsed.Ok) { $violations += "malformed reads citation: $(([string]$rl).Trim())"; continue }
    if ($readMap.ContainsKey($parsed.File)) { $violations += "duplicate reads citation for '$($parsed.File)'"; continue }
    $readMap[$parsed.File] = $parsed.Token
}

foreach ($pb in $requiredReads) {
    $blob = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('show', "$($update.LocalSha):$pb")
    if ($blob.ExitCode -ne 0) {
        $violations += "cannot read '$pb' at the pushed tip $($update.LocalSha.Substring(0, 8)) (playbook missing there?)"
        continue
    }
    $content = ($blob.Stdout -join "`n")
    $token = if ($content) { Get-TokenFromContent -Content $content } else { $null }
    if (-not $token) {
        $violations += "'$pb' has no read-receipt-token at the pushed tip"
    } elseif (-not $readMap.ContainsKey($pb)) {
        $violations += "receipt is missing the read citation 'reads=$pb@$token'"
    } elseif (-not $readMap[$pb].Equals($token, [System.StringComparison]::OrdinalIgnoreCase)) {
        $violations += "stale read token for '$pb': receipt cites @$($readMap[$pb]) but the pushed tree is @$token"
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Publish-gate pre-push receipt FAILED for '$($update.RemoteRef)':"
    foreach ($v in $violations) { Write-Host "  - $v" }
    Write-Host ""
    Write-Host "Re-read the pre-PR playbook(s), re-run the publish gate for THIS commit, and re-write the receipt."
    Write-Host "Schema: .github/pr-quality-gate/publish-gate-receipt.md"
    exit $ExitViolation
}

Write-Host "OK: publish-gate receipt authorizes $($row.Kind) for $($update.RemoteRef) @ $($update.LocalSha.Substring(0, 8))."
exit $ExitOk
