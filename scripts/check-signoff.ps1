#Requires -Version 5.1
# Amend / force-push sign-off gate (spec "v3 addendum"). A history rewrite (git commit
# --amend, or any force-push) must carry a FRESH, TREE-BOUND user sign-off marker written
# only AFTER the user approved via ask_user. The pre-commit hook calls -Mode amend (when
# PANEL_GATE_AMEND=1); the pre-push hook calls -Mode force-push -Tree <pushed-tip-tree>.
#
# The marker lives in a gitignored worktree receipt; it records the index/commit tree it
# authorizes, so a stale sign-off cannot authorize a different rewrite. Identity-gated;
# no-op on any repo that is not this instruction set's own. Honest: --no-verify bypasses.
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('amend', 'force-push')] [string] $Mode,
    [string] $RepoRoot = '',
    [string] $Tree = '',          # force-push: the pushed tip's tree sha. amend: derived from the index.
    [string] $ReceiptPath = '.github/pr-quality-gate/audits/signoff-receipt'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/audit-note-helpers.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitBlock = 1

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-signoff.ps1') -RequireGitWorkTree
}

# Identity gate: the sign-off gate guards THIS repo's own history rewrites only.
if (-not (Test-IsInstructionsRepo -RepoRoot $RepoRoot)) { exit $ExitOk }

$marker = if ($Mode -eq 'amend') { 'amend_approved' } else { 'force_push_approved' }

if ($Mode -eq 'amend') {
    $wt = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('write-tree')
    $actualTree = if ($wt.ExitCode -eq 0 -and $wt.Stdout.Count -gt 0) { ([string]$wt.Stdout[0]).Trim() } else { '' }
    if (-not $actualTree) { Write-Host "check-signoff: cannot compute the index tree (git write-tree failed)."; exit $ExitBlock }
} else {
    if (-not $Tree) { Write-Host "check-signoff: -Tree is required in force-push mode."; exit $ExitBlock }
    $actualTree = $Tree.Trim()
}

$receiptFull = Join-Path $RepoRoot $ReceiptPath
if (-not (Test-Path -LiteralPath $receiptFull -PathType Leaf)) {
    Write-Host "ERROR: this $Mode rewrites history but no sign-off receipt exists at '$ReceiptPath'."
    Write-Host "       Get explicit user sign-off (ask_user), then record: $marker`: <turn-ref> tree:$actualTree"
    exit $ExitBlock
}

$lines = @([IO.File]::ReadAllLines($receiptFull))
$row = $lines | Where-Object { $_ -cmatch "^\s*$marker`:\s*\S" } | Select-Object -First 1
if (-not $row) {
    Write-Host "ERROR: the sign-off receipt has no '$marker' marker for this $Mode."
    Write-Host "       Get explicit user sign-off (ask_user), then record: $marker`: <turn-ref> tree:$actualTree"
    exit $ExitBlock
}

if ($row -cmatch 'tree:\s*(\S+)') {
    $signedTree = $matches[1]
} else {
    Write-Host "ERROR: the '$marker' marker is missing its 'tree:<sha>' binding (got: $($row.Trim()))."
    exit $ExitBlock
}

if ($signedTree -notmatch '^[a-fA-F0-9]{40}$') {
    Write-Host "ERROR: the '$marker' marker's tree binding must be a full 40-char hex SHA (got '$signedTree'). Re-record with the full tree SHA."
    exit $ExitBlock
}

if (-not $actualTree.Equals($signedTree, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "ERROR: the '$marker' sign-off authorizes tree '$signedTree' but this $Mode publishes tree '$actualTree'."
    Write-Host "       The content changed since sign-off; re-confirm with the user (ask_user) and re-record the marker."
    exit $ExitBlock
}

Write-Host "check-signoff: $Mode authorized by a fresh tree-bound sign-off marker."
exit $ExitOk
