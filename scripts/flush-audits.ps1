#Requires -Version 5.1
# Move the gitignored worktree audit receipts into local git notes on a commit, then
# clear them. Called by the post-commit hook (after each commit) and directly by the
# agent after a rebase/squash (where post-commit does NOT fire for the rewritten tips).
#
# Identity-gated (spec R5): writes NOTHING unless the repo IS this instruction set's own
# repo, so the loaded instructions never modify a consuming project's .git.
#
# Freshness: each note is stamped with the commit's tree (audited_tree). Because that
# binds the WHOLE tree, ANY amend/rebase makes carried notes stale -> re-author the
# receipts and re-run this script. The three refs (panel + comment + reads) are independent
# so a single-receipt re-flush never destroys the other refs' notes (spec R1).
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $CommitSha = 'HEAD',
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/audit-note-helpers.psm1') -Force -DisableNameChecking

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/flush-audits.ps1') -RequireGitWorkTree
}

function Write-Info { param([string] $Message) if (-not $Quiet) { Write-Host $Message } }

# Identity gate: on any repo that is not this instruction set's own, do ABSOLUTELY nothing.
if (-not (Test-IsInstructionsRepo -RepoRoot $RepoRoot)) {
    Write-Info "flush-audits: repo is not this instruction set's own (identity gate); no notes written."
    exit 0
}

$resolved = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', $CommitSha)
$commit = if ($resolved.Stdout.Count -gt 0) { ([string]$resolved.Stdout[0]).Trim() } else { '' }
if ($resolved.ExitCode -ne 0 -or -not $commit) {
    Write-Info "flush-audits: cannot resolve commit '$CommitSha'."
    exit 0
}

$receipts = @(
    [PSCustomObject]@{ Kind = 'panel';   Ref = (Get-PanelNoteRef);   Path = '.github/pr-quality-gate/audits/post-code-change-last.md' }
    [PSCustomObject]@{ Kind = 'comment'; Ref = (Get-CommentNoteRef); Path = '.github/pr-quality-gate/audits/last.md' }
    [PSCustomObject]@{ Kind = 'reads';   Ref = (Get-ReadsNoteRef);   Path = '.github/pr-quality-gate/audits/read-receipts-last.md' }
    [PSCustomObject]@{ Kind = 'precommit'; Ref = (Get-PreCommitNoteRef); Path = '.github/pr-quality-gate/audits/pre-commit-gate-last.md' }
)

$flushed = @()
foreach ($receipt in $receipts) {
    $full = Join-Path $RepoRoot $receipt.Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $body = @(Get-Content -LiteralPath $full)
    Write-AuditNote -RepoRoot $RepoRoot -NoteRef $receipt.Ref -CommitSha $commit -BodyLines $body
    Remove-Item -LiteralPath $full -Force
    $flushed += $receipt.Kind
}

if ($flushed.Count -gt 0) {
    $short = $commit.Substring(0, [Math]::Min(8, $commit.Length))
    Write-Info "flush-audits: wrote note(s) [$($flushed -join ', ')] on $short and cleared the receipt(s)."
} else {
    Write-Info "flush-audits: no receipts on disk to flush."
}
exit 0
