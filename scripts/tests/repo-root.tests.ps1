#Requires -Version 5.1
# Standalone pwsh self-test for scripts/lib/repo-root.psm1 (Assert-* helpers, NOT Pester).
# Run: pwsh -File scripts/tests/repo-root.tests.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/repo-root.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'test-common.ps1')

$script:Pass = 0
$script:Fail = 0
$script:repos = New-Object System.Collections.Generic.List[string]
$script:worktrees = New-Object System.Collections.Generic.List[string]
$utf8 = New-Object System.Text.UTF8Encoding($false)

function New-FixtureRoot {
    param([switch] $Git, [switch] $Anchor)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("repo-root-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
    if ($Anchor) {
        [System.IO.File]::WriteAllText((Join-Path $dir 'AGENTS.md'), "fixture`n", $utf8)
    }
    if ($Git) {
        Push-Location $dir
        try {
            git init -q
            git config user.email 't@t'
            git config user.name 't'
            git config commit.gpgsign false
            git config core.autocrlf false
            [System.IO.File]::WriteAllText((Join-Path $dir 'base.txt'), "base`n", $utf8)
            git add -A | Out-Null
            git commit -qm init | Out-Null
        } finally { Pop-Location }
    }
    $script:repos.Add($dir)
    return $dir
}

Write-Host "=== repo-root resolver ===" -ForegroundColor Cyan

$root = New-FixtureRoot -Git -Anchor
$scriptRoot = Join-Path $root 'scripts'
$resolved = Resolve-RepoRoot -Explicit $root -ScriptRoot $scriptRoot -Anchors @('AGENTS.md')
Assert-True ($resolved -eq (Resolve-Path -LiteralPath $root).Path.TrimEnd('\', '/')) 'explicit valid root returns normalized path'

$missingAnchor = New-FixtureRoot -Git
Assert-ThrowsLike { Resolve-RepoRoot -Explicit $missingAnchor -ScriptRoot (Join-Path $missingAnchor 'scripts') -Anchors @('AGENTS.md') } 'INVOCATION_FAILED|missing anchor' 'explicit invalid root missing anchor throws'

$subdirRoot = New-FixtureRoot -Git -Anchor
$subdir = Join-Path (Join-Path $subdirRoot 'nested') 'child'
New-Item -ItemType Directory -Path $subdir -Force | Out-Null
Push-Location $subdir
try {
    $resolvedFromSubdir = Resolve-RepoRoot -Explicit '' -ScriptRoot (Join-Path $subdirRoot 'scripts') -Anchors @('AGENTS.md')
} finally { Pop-Location }
Assert-True ($resolvedFromSubdir -eq (Resolve-Path -LiteralPath $subdirRoot).Path.TrimEnd('\', '/')) 'empty explicit resolves git root from subdirectory cwd'

$nonGitRoot = New-FixtureRoot -Anchor
Assert-ThrowsLike { Resolve-RepoRoot -Explicit $nonGitRoot -ScriptRoot (Join-Path $nonGitRoot 'scripts') -Anchors @('AGENTS.md') -RequireGitWorkTree } 'INVOCATION_FAILED|git work tree' 'RequireGitWorkTree rejects a non-git directory'

$noAnchorGit = New-FixtureRoot -Git
$noAnchorSubdir = Join-Path $noAnchorGit 'nested'
New-Item -ItemType Directory -Path $noAnchorSubdir -Force | Out-Null
Push-Location $noAnchorSubdir
try {
    Assert-ThrowsLike { Resolve-RepoRoot -Explicit '' -ScriptRoot (Join-Path $noAnchorGit 'scripts') -Anchors @('AGENTS.md') } 'INVOCATION_FAILED' 'anchor-missing empty explicit throws INVOCATION_FAILED'
} finally { Pop-Location }
$wrongGitRoot = New-FixtureRoot -Git
$wrongGitSubdir = Join-Path $wrongGitRoot 'nested'
New-Item -ItemType Directory -Path $wrongGitSubdir -Force | Out-Null
$actualRepoRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
$actualScriptRoot = Join-Path $actualRepoRoot 'scripts'
Push-Location $wrongGitSubdir
try {
    $resolvedFromSuiteParent = Resolve-RepoRoot -Explicit '' -ScriptRoot $actualScriptRoot -Anchors @('AGENTS.md')
} finally { Pop-Location }
Assert-True (($resolvedFromSuiteParent -eq (Resolve-Path -LiteralPath $actualRepoRoot).Path.TrimEnd('\', '/')) -and ($resolvedFromSuiteParent -ne (Resolve-Path -LiteralPath $wrongGitRoot).Path.TrimEnd('\', '/'))) 'git-toplevel missing anchor falls through to suite parent'

$mainRepo = New-FixtureRoot -Git -Anchor
$worktree = Join-Path ([System.IO.Path]::GetTempPath()) ("repo-root-wt-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:worktrees.Add($worktree)
Push-Location $mainRepo
try {
    git worktree add -q $worktree -b wt-test | Out-Null
} finally { Pop-Location }
$gitMarker = Join-Path $worktree '.git'
$resolvedWorktree = Resolve-RepoRoot -Explicit $worktree -ScriptRoot (Join-Path $worktree 'scripts') -Anchors @('AGENTS.md') -RequireGitWorkTree
Assert-True ((Test-Path -LiteralPath $gitMarker -PathType Leaf) -and $resolvedWorktree -eq (Resolve-Path -LiteralPath $worktree).Path.TrimEnd('\', '/')) 'git worktree with .git file is accepted by RequireGitWorkTree'

$emptyAnchorNonGit = New-FixtureRoot
$emptyAnchorErr = ''
try { Resolve-RepoRoot -Explicit $emptyAnchorNonGit -ScriptRoot (Join-Path $emptyAnchorNonGit 'scripts') -RequireGitWorkTree } catch { $emptyAnchorErr = $_.Exception.Message }
Assert-True ($emptyAnchorErr -match 'git work tree' -and $emptyAnchorErr -notmatch 'anchor\(s\):') 'empty -Anchors error message omits the anchors clause'

$gitlessRoot = New-FixtureRoot -Git -Anchor
$savedPath = $env:PATH
$resolvedGitless = $null
try {
    $env:PATH = [System.IO.Path]::GetTempPath()
    Push-Location $gitlessRoot
    try { $resolvedGitless = Resolve-RepoRoot -Explicit '' -ScriptRoot (Join-Path $gitlessRoot 'scripts') -Anchors @('AGENTS.md') }
    finally { Pop-Location }
} finally { $env:PATH = $savedPath }
Assert-True ($resolvedGitless -eq (Resolve-Path -LiteralPath $gitlessRoot).Path.TrimEnd('\', '/')) 'git unavailable (empty PATH) falls through to script-parent without throwing'

foreach ($worktreePath in $script:worktrees) {
    if (Test-Path -LiteralPath $worktreePath) {
        try { git -C $mainRepo worktree remove --force $worktreePath 2>$null | Out-Null } catch { Write-Verbose "worktree cleanup ignored: $($_.Exception.Message)" }
        Remove-Item -Recurse -Force -LiteralPath $worktreePath -ErrorAction SilentlyContinue
    }
}
foreach ($repoPath in $script:repos) {
    if (Test-Path -LiteralPath $repoPath) { Remove-Item -Recurse -Force -LiteralPath $repoPath -ErrorAction SilentlyContinue }
}

Write-Host ""
$summaryColor = if ($script:Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "repo-root.tests: $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $summaryColor
exit ([int]($script:Fail -gt 0))
