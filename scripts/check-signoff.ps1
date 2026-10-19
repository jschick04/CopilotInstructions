#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('amend', 'force-push')] [string] $Mode,
    [string] $RepoRoot = '',
    [string] $Tree = '',          # force-push: the pushed tip's tree sha. amend: derived from the index.
    [string] $CommitSha = '',
    [string] $RemoteSha = '',
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

if ($Mode -eq 'amend') {
    if (-not (Test-RequiresFullPanel -RepoRoot $RepoRoot)) { exit $ExitOk }
} else {
    if ($CommitSha -notmatch '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { Write-Host "check-signoff: -CommitSha (full hex SHA of the force-pushed tip) is required in force-push mode."; exit $ExitBlock }
    $tipTree = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', "$CommitSha^{tree}")
    if ($tipTree.ExitCode -ne 0 -or $tipTree.Stdout.Count -ne 1) { Write-Host "check-signoff: cannot resolve the tree of force-pushed tip '$CommitSha'."; exit $ExitBlock }
    $derivedTree = ([string]$tipTree.Stdout[0]).Trim()
    if ($Tree -and -not $Tree.Trim().Equals($derivedTree, [System.StringComparison]::OrdinalIgnoreCase)) { Write-Host "check-signoff: -Tree '$Tree' does not match the tree '$derivedTree' of force-pushed tip '$CommitSha'."; exit $ExitBlock }
    $Tree = $derivedTree
    if ($RemoteSha -notmatch '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { Write-Host "check-signoff: -RemoteSha (full hex SHA of the overwritten remote tip) is required in force-push mode."; exit $ExitBlock }
    $remoteObject = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('cat-file', '-e', "$RemoteSha^{commit}")
    if ($remoteObject.ExitCode -ne 0) { Write-Host "check-signoff: overwritten remote tip '$RemoteSha' is not available locally; run 'git fetch' and retry the push (failing closed)."; exit $ExitBlock }
    $overwritten = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-list', $RemoteSha, '--not', $CommitSha)
    if ($overwritten.ExitCode -ne 0) { Write-Host "check-signoff: cannot enumerate commits overwritten by this force-push (git rev-list $RemoteSha --not $CommitSha failed)."; exit $ExitBlock }
    if (-not (Test-RewriteRequiresFullPanel -RepoRoot $RepoRoot -TipSha $CommitSha -RemoteSha $RemoteSha -OverwrittenShas @($overwritten.Stdout))) { exit $ExitOk }
}

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

if ($signedTree -notmatch '^([a-fA-F0-9]{40}|[a-fA-F0-9]{64})$') {
    Write-Host "ERROR: the '$marker' marker's tree binding must be a full 40- or 64-char hex SHA (got '$signedTree'). Re-record with the full tree SHA."
    exit $ExitBlock
}

if (-not $actualTree.Equals($signedTree, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "ERROR: the '$marker' sign-off authorizes tree '$signedTree' but this $Mode publishes tree '$actualTree'."
    Write-Host "       The content changed since sign-off; re-confirm with the user (ask_user) and re-record the marker."
    exit $ExitBlock
}

Write-Host "check-signoff: $Mode authorized by a fresh tree-bound sign-off marker."
exit $ExitOk
