#Requires -Version 5.1
# Code-topic read-receipt gate. Pre-commit usage: -StagedMode -WorktreeReceipt. For every gated
# code-topic instruction file (.github/instructions/*.instructions.md with a NON-**/* applyTo) whose glob
# matches a STAGED changed path, the gitignored receipt audits/read-receipts-last.md MUST carry a
# reads=<file>@<token> citation whose token equals the file's CURRENT staged header token. Missing
# citation, stale token, or a gated file lacking a valid token -> FAIL (fail-closed). Honest ceiling:
# forces a current-token citation on the commit (defeats FORGET/silent-skip); does NOT prove the file was
# read. Commit-time, not edit-time; post-commit flush + pre-push re-validation give push-time parity.
# Exit: 0 clean (or clean-skip), 1 violation, 2 invocation error.
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [switch] $StagedMode,
    [switch] $WorktreeReceipt
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib/read-receipt-helpers.psm1') -Force

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

function Write-Invocation { param([string] $Message) Write-Host "check-read-receipts: $Message" }

try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('.github/instructions')
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit $script:ExitInvocation
}

if (-not $StagedMode) {
    Write-Invocation "only -StagedMode is supported (pre-commit hook); CI cannot read the gitignored receipt."
    exit $script:ExitInvocation
}

$receiptPath = Join-Path $RepoRoot '.github/pr-quality-gate/audits/read-receipts-last.md'
$gitC = @('-C', $RepoRoot, '-c', 'core.quotePath=false')
$gitInvoke = { param($a) & git @gitC @a }

try {
    $gatedSet = @(Get-GatedTopicFiles -RepoRoot $RepoRoot)
} catch {
    Write-Invocation "FAIL: could not resolve the gated topic set: $($_.Exception.Message)"
    exit $script:ExitInvocation
}
if ($gatedSet.Count -eq 0) {
    Write-Invocation "no gated topic files found (.github/instructions with non-**/* applyTo) - nothing to enforce."
    exit $script:ExitOk
}

$tokenless = @($gatedSet | Where-Object { -not $_.Token })
if ($tokenless.Count -gt 0) {
    Write-Invocation "FAIL: gated topic file(s) lack a valid read-receipt-token header (fail-closed config):"
    $tokenless | ForEach-Object { Write-Host "    - $($_.Path)" }
    exit $script:ExitViolation
}

$diffArgs = @('diff', '--cached', '--name-only', '--diff-filter=ACMRT')
try {
    $matched = @(Get-MatchedGatedFiles -GatedSet $gatedSet -DiffArgs $diffArgs -GitInvoke $gitInvoke)
} catch {
    Write-Invocation "FAIL: staged-diff glob matching failed: $($_.Exception.Message)"
    exit $script:ExitInvocation
}
if ($matched.Count -eq 0) {
    Write-Invocation "OK: no staged file matches a gated code-topic glob - no read receipt required."
    exit $script:ExitOk
}

if (-not $WorktreeReceipt) {
    Write-Invocation "-WorktreeReceipt is required in -StagedMode (the receipt is git-excluded; read from disk)."
    exit $script:ExitInvocation
}
if (-not (Test-Path -LiteralPath $receiptPath)) {
    Write-Invocation "FAIL: a staged code-topic edit requires read receipts, but the receipt is missing:"
    Write-Host "    $receiptPath"
    Write-Host "    Author it with parent_sha: <HEAD> and a 'reads=<file>@<token>' line per matched topic file:"
    $matched | ForEach-Object { Write-Host "      reads=$($_.Path)@$($_.Token)" }
    exit $script:ExitViolation
}

$receipt = Read-ReadsReceipt -Lines (Get-Content -LiteralPath $receiptPath)

$head = (& git @gitC rev-parse HEAD 2>$null)
$acceptable = @($head) | Where-Object { $_ }
if ($env:PANEL_GATE_AMEND -eq '1') {
    $headParent = (& git @gitC rev-parse HEAD^ 2>$null)
    if ($headParent) { $acceptable += $headParent }
}
if (-not $receipt.ParentSha) {
    Write-Invocation "FAIL: receipt has no parent_sha line."
    exit $script:ExitViolation
}
$matchParent = $acceptable | Where-Object { $_.StartsWith($receipt.ParentSha) -or $receipt.ParentSha.StartsWith($_) -or $_ -eq $receipt.ParentSha }
if (-not $matchParent) {
    Write-Invocation "FAIL: receipt parent_sha '$($receipt.ParentSha)' does not match HEAD ($($head)) - re-author the receipt for the current commit (set PANEL_GATE_AMEND=1 to also accept HEAD^)."
    exit $script:ExitViolation
}

$violations = New-Object System.Collections.Generic.List[string]
foreach ($gf in $matched) {
    $stagedContent = (& git @gitC show ":$($gf.Path)" 2>$null) -join "`n"
    $currentToken = if ($stagedContent) { Get-TokenFromContent -Content $stagedContent } else { $gf.Token }
    if (-not $currentToken) {
        $violations.Add("gated file '$($gf.Path)' has no valid staged token (fail-closed)")
        continue
    }
    if (-not $receipt.Reads.ContainsKey($gf.Path)) {
        $violations.Add("missing read receipt for '$($gf.Path)' (expected: reads=$($gf.Path)@$currentToken)")
    } elseif ($receipt.Reads[$gf.Path] -ne $currentToken) {
        $violations.Add("stale token for '$($gf.Path)': receipt cites @$($receipt.Reads[$gf.Path]) but current is @$currentToken")
    }
}

if ($violations.Count -gt 0) {
    Write-Invocation "FAIL: staged code-topic edit(s) require read receipts that are missing or stale:"
    $violations | ForEach-Object { Write-Host "    - $_" }
    Write-Host "    Read each topic file, then write its 'reads=<file>@<token>' line into $receiptPath (parent_sha = HEAD)."
    exit $script:ExitViolation
}

Write-Invocation "OK: all $($matched.Count) matched code-topic file(s) have fresh read receipts."
exit $script:ExitOk
