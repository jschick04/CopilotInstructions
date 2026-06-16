#Requires -Version 5.1
# Pre-push audit-note gate (local-only; zero remote footprint). For every commit in the
# push range, validates that a panel-required commit carries a fresh valid PANEL note,
# and that a commit introducing new comment lines carries a covering COMMENT note. Reads
# the pre-push ref-update list (`<local-ref> <local-sha> <remote-ref> <remote-sha>` lines)
# from stdin, or from -RefUpdateLines for tests.
#
# Identity-gated (no-op on a consuming repo); asserts its own setup is wired (spec R4);
# refuses to publish the note refs; walks EVERY commit in range (first-parent diff for
# merges - no silent --no-merges skip, spec R4).
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $RemoteName = 'origin',
    [string[]] $RefUpdateLines
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/audit-note-helpers.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitViolation = 1

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-audit-notes-prepush.ps1') -RequireGitWorkTree
}

# Identity gate: on any repo that is not this instruction set's own, do nothing.
if (-not (Test-IsInstructionsRepo -RepoRoot $RepoRoot)) { exit $ExitOk }

if ($PSBoundParameters.ContainsKey('RefUpdateLines')) {
    $lines = @($RefUpdateLines)
} else {
    $stdin = [Console]::In.ReadToEnd()
    $lines = @($stdin -split "`n") | ForEach-Object { ([string]$_).TrimEnd("`r") } | Where-Object { $_.Trim() }
}

$zeroSha = '^0{40}$'
$commitSet = [ordered]@{}

foreach ($line in $lines) {
    $parts = @($line.Trim() -split '\s+')
    if ($parts.Count -lt 4) { continue }
    $localRef = $parts[0]; $localSha = $parts[1]; $remoteRef = $parts[2]; $remoteSha = $parts[3]

    # No-publish guard (R4): the note refs are local-only and must never be pushed.
    if ($localRef -match '^refs/notes/copilot-audit-' -or $remoteRef -match '^refs/notes/copilot-audit-') {
        Write-Host "ERROR: refusing to push the local audit note ref '$remoteRef'."
        Write-Host "       The copilot-audit notes are local-only (zero remote footprint); do not publish them."
        exit $ExitViolation
    }

    if ($localSha -match $zeroSha) { continue }   # branch deletion: nothing to validate

    if ($remoteSha -match $zeroSha) {
        $rl = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-list', $localSha, '--not', "--remotes=$RemoteName")
    } else {
        $rl = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-list', "$remoteSha..$localSha")
    }
    if ($rl.ExitCode -ne 0) {
        Write-Host "ERROR: 'git rev-list' could not compute the pushed range (exit $($rl.ExitCode)); the remote tip '$remoteSha' may not be present locally."
        Write-Host "       Run 'git fetch $RemoteName' so every pushed commit can be validated, then push again (failing closed rather than skipping validation)."
        exit $ExitViolation
    }
    foreach ($sha in $rl.Stdout) {
        $s = ([string]$sha).Trim()
        if ($s -and -not $commitSet.Contains($s)) { $commitSet[$s] = $true }
    }
}

if ($commitSet.Count -eq 0) {
    Write-Host "OK: no pushed commits to validate (delete/up-to-date push)."
    exit $ExitOk
}

# Setup assertion (R4): fail loud if the local note gate is not wired.
$setupErrors = Assert-AuditSetup -RepoRoot $RepoRoot
if ($setupErrors.Count -gt 0) {
    Write-Host "ERROR: the local audit-note gate is not wired up:"
    foreach ($e in $setupErrors) { Write-Host "  - $e" }
    exit $ExitViolation
}

$violations = @()
foreach ($sha in $commitSet.Keys) {
    $short = $sha.Substring(0, [Math]::Min(8, $sha.Length))
    $parent = Get-CommitParentSha -RepoRoot $RepoRoot -CommitSha $sha

    $dp = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('--no-pager', 'diff', '--name-only', '--no-renames', $parent, $sha)
    if ($dp.ExitCode -ne 0) {
        Write-Host "ERROR: 'git diff' for commit ${short} (parent ${parent}) failed (exit $($dp.ExitCode)); cannot determine whether the panel is required. Failing closed rather than skipping validation."
        exit $ExitViolation
    }
    $changedPaths = @($dp.Stdout) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }

    $panelReq = Get-PanelRequired -ChangedPaths $changedPaths
    if ($panelReq -or (Test-PanelNoteExists -RepoRoot $RepoRoot -CommitSha $sha)) {
        $pv = Read-PanelNoteValidated -RepoRoot $RepoRoot -CommitSha $sha -PanelRequired $panelReq
        if (-not $pv.Valid) { foreach ($e in $pv.Errors) { $violations += "commit ${short} (panel): $e" } }
    }

    $diffFull = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('--no-pager', 'diff', '--no-renames', $parent, $sha)
    if ($diffFull.ExitCode -ne 0) {
        Write-Host "ERROR: 'git diff' for commit ${short} (parent ${parent}) failed (exit $($diffFull.ExitCode)); cannot count new comment lines. Failing closed rather than skipping validation."
        exit $ExitViolation
    }
    $newCount = Get-NewCommentCount -DiffLines @($diffFull.Stdout)
    if ($newCount -gt 0) {
        $cv = Read-CommentNoteValidated -RepoRoot $RepoRoot -CommitSha $sha
        if (-not $cv.Valid) {
            foreach ($e in $cv.Errors) { $violations += "commit ${short} (comment): $e" }
        } else {
            $covered = Get-CoveredCommentCount -AuditResult $cv.Audit
            if ($covered -lt $newCount) {
                $violations += "commit ${short} (comment): $newCount new comment line(s) but the note covers only $covered"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Audit-note pre-push gate FAILED:"
    foreach ($v in $violations) { Write-Host "  - $v" }
    Write-Host ""
    Write-Host "Re-author the receipt(s) (.github/pr-quality-gate/audits/*.md) and run scripts/flush-audits.ps1,"
    Write-Host "or amend the commit and re-flush, then push again."
    exit $ExitViolation
}

Write-Host "OK: local audit notes are fresh and valid for all $($commitSet.Count) pushed commit(s)."
exit $ExitOk
