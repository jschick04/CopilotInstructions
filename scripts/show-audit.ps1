#Requires -Version 5.1
# Show the local audit notes (panel + comment + reads) attached to commits. Read-only display
# helper; the notes are local-only (never pushed). Default shows HEAD; pass -Range for a
# span (e.g. 'origin/main..HEAD' or 'HEAD~5..HEAD').
[CmdletBinding()]
param(
    [string] $Range = 'HEAD',
    [string] $RepoRoot = '',
    [switch] $Patch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/audit-note-helpers.psm1') -Force -DisableNameChecking

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/show-audit.ps1') -RequireGitWorkTree
}

$gitArgs = @(
    'log', $Range,
    "--notes=$(Get-PanelNoteRef)",
    "--notes=$(Get-CommentNoteRef)",
    "--notes=$(Get-ReadsNoteRef)",
    '--format=%C(yellow)%h%C(reset) %s%n%C(dim)%an, %ar%C(reset)'
)
if ($Patch) { $gitArgs += '--patch' }

& git -C $RepoRoot @gitArgs
exit $LASTEXITCODE
