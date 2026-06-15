#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester). Run: pwsh -File <this file>

$modulePath = Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1'
Import-Module $modulePath -Force
$checkerPath = Join-Path $PSScriptRoot '../check-post-code-change.ps1'

$script:failures = 0
$script:passes = 0

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    if ($Condition) { $script:passes++; Write-Host "  [PASS] $Description" }
    else { $script:failures++; Write-Host "  [FAIL] $Description" -ForegroundColor Red }
}
function Assert-False {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    Assert-True -Condition (-not $Condition) -Description $Description
}
function Assert-Equal {
    param([Parameter(Mandatory)] $Expected, [Parameter(Mandatory)] $Actual, [Parameter(Mandatory)] [string] $Description)
    if ($Expected -eq $Actual) { $script:passes++; Write-Host "  [PASS] $Description" }
    else {
        $script:failures++; Write-Host "  [FAIL] $Description" -ForegroundColor Red
        Write-Host "         Expected: $Expected"; Write-Host "         Actual:   $Actual"
    }
}

Write-Host ""
Write-Host "=== Test-PathPanelRequired ===" -ForegroundColor Cyan
Assert-True  (Test-PathPanelRequired -Path 'src/Foo.cs')                                  'C# source is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'scripts/check-post-code-change.ps1')          'scripts/ ps1 is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'AGENTS.md')                                   'AGENTS.md is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path '.github/playbooks/post-code-change.md')       'playbook .md is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path 'profiles/full/profile.template.md')           'profiles/ template is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path 'setup.sh')                                     'setup.sh is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'sub/dir/app.ts')                               'nested TS is panel-required'
Assert-False (Test-PathPanelRequired -Path 'README.md')                                    'README.md is NOT panel-required (pure docs)'
Assert-False (Test-PathPanelRequired -Path 'docs/guide.md')                                'docs/ .md is NOT panel-required'
Assert-False (Test-PathPanelRequired -Path 'notes.txt')                                    'plain .txt is NOT panel-required'
Assert-False (Test-PathPanelRequired -Path '.github/pr-quality-gate/audits/post-code-change-last.md') 'the receipt itself is EXCLUDED (no self-trip)'
Assert-False (Test-PathPanelRequired -Path '.github/pr-quality-gate/audits/last.md')       'comment-audit receipt is EXCLUDED too'
Assert-True  (Test-PathPanelRequired -Path '.github\workflows\ci.yml')                      'backslash path normalized + governed'
Assert-True  (Test-PathPanelRequired -Path '.githooks/pre-commit')                          '.githooks/ enforcement hook is panel-required (governance; cannot self-bypass)'
Assert-True  (Test-PathPanelRequired -Path 'src/App.csproj')                                'csproj build/project file is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'Directory.Packages.props')                      'MSBuild .props is panel-required'
Assert-True  (Test-PathPanelRequired -Path '.gitattributes')                                '.gitattributes is governance/panel-required'
Assert-True  (Test-PathPanelRequired -Path '.gitignore')                                    '.gitignore is governance/panel-required'
Assert-True  (Test-PathPanelRequired -Path '.github/copilot-instructions.md')               'consumer copilot-instructions.md is governance/panel-required'

Write-Host ""
Write-Host "=== Get-PanelRequired (any-path) ===" -ForegroundColor Cyan
Assert-True  (Get-PanelRequired -ChangedPaths @('README.md','src/Foo.cs'))                 'mixed docs+code -> required'
Assert-False (Get-PanelRequired -ChangedPaths @('README.md','docs/x.md'))                  'docs-only -> not required'
Assert-False (Get-PanelRequired -ChangedPaths @('.github/pr-quality-gate/audits/post-code-change-last.md')) 'receipt-only -> not required (self-trip guard)'
Assert-False (Get-PanelRequired -ChangedPaths @())                                          'empty changeset -> not required'

Write-Host ""
Write-Host "=== Test-PanelLedger ===" -ForegroundColor Cyan
function New-Ledger {
    param([string] $ParentSha = 'abc1234', [string] $Subject = 'do a thing',
          [string] $Panel = 'ran, unanimous', [string] $Build = 'passed', [string] $Tests = 'passed, 10/10')
    return @(
        "parent_sha: $ParentSha",
        "commit_subject: $Subject",
        'POST-CODE-CHANGE LEDGER',
        '  gates:',
        "    post-code-change-panel: $Panel",
        "    build: $Build",
        "    tests: $Tests"
    )
}

$r = Test-PanelLedger -LedgerLines (New-Ledger) -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-True $r.Valid 'panel-required + ran,unanimous + fresh parent -> valid'

$bomLedger = @(New-Ledger); $bomLedger[0] = [char]0xFEFF + $bomLedger[0]
$r = Test-PanelLedger -LedgerLines $bomLedger -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-True $r.Valid 'leading UTF-8 BOM on the first ledger line is tolerated (parent_sha still matches)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A: docs-only') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'panel-required + N/A -> INVALID (the non-bypassable rule)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A: no code change') -ExpectedParentSha 'abc1234' -PanelRequired $false
Assert-True $r.Valid 'NOT panel-required + N/A -> valid'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A') -ExpectedParentSha 'abc1234' -PanelRequired $false
Assert-False $r.Valid 'NOT panel-required + bare N/A (no reason) -> INVALID (requires N/A: <reason>)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha 'deadbee') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'mismatched parent_sha -> INVALID (stale)'

$fullSha = 'a1b2c3d4e5f60718293041526374859607a8b9c0'
$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha $fullSha.Substring(0,7)) -ExpectedParentSha $fullSha -PanelRequired $true
Assert-True $r.Valid '7-char ledger parent_sha is a prefix of full 40-char expected -> valid (asymmetric-length match)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha 'deadbee') -ExpectedParentSha $fullSha -PanelRequired $true
Assert-False $r.Valid '7-char of a DIFFERENT sha vs full expected -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'ran, unanimous' -Build 'failed: CS1002') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'build failed -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'Failed: CS1002') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'build Failed (capitalized) -> INVALID (case-insensitive failure detection)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'ran, unanimous extra') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'panel value with trailing text -> INVALID (end-anchored)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Tests 'failed: 2/10') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'tests failed -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'skipped') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'build unknown value (skipped) -> INVALID (fail-closed allowlist)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'passsed') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'build typo (passsed) -> INVALID (fail-closed allowlist)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'N/A: no compile step') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-True $r.Valid 'build N/A: <reason> -> valid'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Tests 'skipped') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'tests unknown value (skipped) -> INVALID (fail-closed allowlist)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Tests 'N/A: no test suite') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-True $r.Valid 'tests N/A: <reason> -> valid'

Assert-Equal (Get-GitEmptyTreeSha) '4b825dc642cb6eb9a060e54bf8d69288fbee4904' 'Get-GitEmptyTreeSha returns the canonical empty-tree SHA (single source, no script duplicate)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "skip it"') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-True $r.Valid 'panel-required + user-waived (quoted) -> valid'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "no close') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'panel-required + user-waived missing closing quote -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel '<ran, unanimous | N/A>') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'unsubstituted placeholder panel value -> INVALID'

$missingPanel = @('parent_sha: abc1234','commit_subject: x','  build: passed','  tests: passed, 1/1')
$r = Test-PanelLedger -LedgerLines $missingPanel -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'missing post-code-change-panel row -> INVALID'

$r = Test-PanelLedger -LedgerLines @('commit_subject: x','  post-code-change-panel: ran, unanimous','  build: passed','  tests: passed, 1/1') -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-False $r.Valid 'missing parent_sha -> INVALID'

$withExtras = @(
    'parent_sha: abc1234','commit_subject: x','POST-CODE-CHANGE LEDGER','  gates:',
    '    hygiene-cleanup: ran','    emdash-scan: ran, clean','    some-future-row: whatever',
    '    post-code-change-panel: ran, unanimous','    build: passed','    tests: passed, 9/9'
)
$r = Test-PanelLedger -LedgerLines $withExtras -ExpectedParentSha 'abc1234' -PanelRequired $true
Assert-True $r.Valid 'unknown/extra §2B rows are ignored (parser is structurally opaque)'

Write-Host ""
Write-Host "=== End-to-end checker (temp git repo) ===" -ForegroundColor Cyan

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$AUDIT = '.github/pr-quality-gate/audits/post-code-change-last.md'

function TG {
    & git -C $tmp @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed" }
}
function Write-RepoFile { param([string] $Rel, [string[]] $Lines)
    $full = Join-Path $tmp $Rel
    New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $Lines -Encoding UTF8 }
function Head { ((& git -C $tmp rev-parse HEAD) | Out-String).Trim() }
function Write-Receipt { param([string] $ParentSha, [string] $Subject = 'change', [string] $Panel = 'ran, unanimous')
    Write-RepoFile -Rel $AUDIT -Lines (New-Ledger -ParentSha $ParentSha -Subject $Subject -Panel $Panel) }
function Run-Checker { param([string[]] $ScriptArgs)
    & pwsh -NoProfile -File $checkerPath @ScriptArgs *> $null; return $LASTEXITCODE }

try {
    TG init
    TG config user.email 'test@example.com'
    TG config user.name 'Test'
    TG config commit.gpgsign false
    TG config core.autocrlf false

    Write-RepoFile -Rel 'README.md' -Lines @('# repo')
    Write-RepoFile -Rel 'scripts/check-post-code-change.ps1' -Lines @('# anchor stub')
    TG add -A; TG commit -m 'init'
    $base = Head

    $p1 = Head
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A {}')
    Write-Receipt -ParentSha $p1 -Subject 'add app'
    TG add -A; TG commit -m 'add app'

    $code = Run-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'history walk: first-add commit with a fresh valid receipt is VALIDATED (no bootstrap skip) -> OK'

    $p2 = Head
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int X; }')
    Write-Receipt -ParentSha $p2 -Subject 'edit app'
    TG add -A; TG commit -m 'edit app'
    $code = Run-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'history walk: panel-required commit with fresh valid receipt -> OK'

    Write-RepoFile -Rel 'README.md' -Lines @('# repo', 'more docs')
    TG add -A; TG commit -m 'docs'
    $code = Run-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'history walk: docs-only commit needs no receipt -> OK'

    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int X; int Y; }')
    Write-Receipt -ParentSha $p2 -Subject 'stale'
    TG add -A; TG commit -m 'stale receipt'
    $code = Run-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'history walk: panel-required commit with STALE receipt -> violation'

    TG reset --hard HEAD
    $h = Head

    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int Z; }')
    TG add src/app.cs
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged: code change without fresh receipt -> violation'

    Write-Receipt -ParentSha $h -Subject 'staged ok'
    TG add $AUDIT
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'staged: code change WITH fresh valid receipt -> OK'

    TG reset --hard HEAD
    Write-RepoFile -Rel 'README.md' -Lines @('# repo', 'docs only staged')
    TG add README.md
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'staged: docs-only change needs no receipt -> OK'

    TG reset --hard HEAD
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int W; }')
    Write-Receipt -ParentSha $h -Subject 'sneaky' -Panel 'N/A: no code change'
    TG add -A
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged: na:CODE on a code change -> violation'

    TG reset --hard HEAD
    $hParent = ((& git -C $tmp rev-parse HEAD^) | Out-String).Trim()
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int Q; }')
    Write-Receipt -ParentSha $hParent -Subject 'amend'
    TG add -A
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged fresh commit: stale HEAD^ receipt rejected (freshness preserved)'
    $env:PANEL_GATE_AMEND = '1'
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Remove-Item Env:PANEL_GATE_AMEND
    Assert-Equal 0 $code 'staged amend (PANEL_GATE_AMEND=1): HEAD^ accepted'

    $tmp2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t2-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp2 -Force | Out-Null
    function TG2 { & git -C $tmp2 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git2 failed: $($args -join ' ')" } }
    function Head2 { ((& git -C $tmp2 rev-parse HEAD) | Out-String).Trim() }
    try {
        TG2 init; TG2 config user.email 't@e.com'; TG2 config user.name 'T'; TG2 config commit.gpgsign false; TG2 config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $tmp2 '.github/pr-quality-gate/audits') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp2 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp2 'scripts') -Force | Out-Null
        Set-Content (Join-Path $tmp2 'scripts/check-post-code-change.ps1') '# anchor stub'
        Set-Content (Join-Path $tmp2 'README.md') '# r'; TG2 add -A; TG2 commit -m 'init'
        $e0 = Head2
        $mainB = ((& git -C $tmp2 rev-parse --abbrev-ref HEAD) | Out-String).Trim()
        Set-Content (Join-Path $tmp2 'src/a.cs') 'class A{}'
        Set-Content (Join-Path $tmp2 $AUDIT) (New-Ledger -ParentSha $e0 -Subject 'add a')
        TG2 add -A; TG2 commit -m 'add a'
        $pBase = Head2

        $code = Run-Checker -ScriptArgs @('-BaseRef', (Head2), '-RepoRoot', $tmp2)
        Assert-Equal 0 $code 'history walk: empty range (base==head) -> OK'

        TG2 checkout -b feature
        $pf = Head2
        Set-Content (Join-Path $tmp2 'src/f.cs') 'class F{}'
        Set-Content (Join-Path $tmp2 $AUDIT) (New-Ledger -ParentSha $pf -Subject 'feat')
        TG2 add -A; TG2 commit -m 'feature'
        TG2 checkout $mainB
        TG2 merge --no-ff -m 'merge feature' feature
        $code = Run-Checker -ScriptArgs @('-BaseRef', $pBase, '-RepoRoot', $tmp2)
        Assert-Equal 0 $code 'history walk: merge commit skipped (--no-merges), feature commit valid -> OK'
    }
    finally {
        Set-Location $PSScriptRoot
        Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue
    }

    $tmp3 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t3-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp3 -Force | Out-Null
    function TG3 { & git -C $tmp3 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git3 failed: $($args -join ' ')" } }
    try {
        TG3 init; TG3 config user.email 't@e.com'; TG3 config user.name 'T'; TG3 config commit.gpgsign false; TG3 config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $tmp3 '.github/pr-quality-gate/audits') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp3 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp3 'scripts') -Force | Out-Null
        Set-Content (Join-Path $tmp3 'scripts/check-post-code-change.ps1') '# anchor stub'
        Set-Content (Join-Path $tmp3 'src/x.cs') 'class X{}'
        Set-Content (Join-Path $tmp3 $AUDIT) (New-Ledger -ParentSha 'EMPTY_TREE' -Subject 'initial')
        TG3 add -A
        $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp3)
        Assert-Equal 0 $code 'staged on a repo with NO HEAD (initial commit): empty-tree path -> OK'
    }
    finally {
        Set-Location $PSScriptRoot
        Remove-Item -LiteralPath $tmp3 -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp4 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t4-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp4 -Force | Out-Null
function TG4 { & git -C $tmp4 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git4 failed: $($args -join ' ')" } }
function Head4 { ((& git -C $tmp4 rev-parse HEAD) | Out-String).Trim() }
try {
    TG4 init; TG4 config user.email 't@e.com'; TG4 config user.name 'T'; TG4 config commit.gpgsign false; TG4 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp4 '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp4 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp4 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp4 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp4 'README.md') '# r'; TG4 add -A; TG4 commit -m 'init'
    $h4 = Head4
    Set-Content (Join-Path $tmp4 'src/x.cs') 'class X{}'
    TG4 add src/x.cs
    Set-Content (Join-Path $tmp4 $AUDIT) (New-Ledger -ParentSha $h4 -Subject 'worktree-receipt')
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-WorktreeReceipt', '-RepoRoot', $tmp4)
    Assert-Equal 0 $code '-WorktreeReceipt: panel-required staged change + valid receipt on disk (unstaged) -> OK'
    Remove-Item -LiteralPath (Join-Path $tmp4 $AUDIT) -Force
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-WorktreeReceipt', '-RepoRoot', $tmp4)
    Assert-Equal 1 $code '-WorktreeReceipt: panel-required but receipt missing on disk -> VIOLATION (fail-closed local-only path)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp4 -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp5 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t5-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp5 -Force | Out-Null
function TG5 { & git -C $tmp5 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git5 failed: $($args -join ' ')" } }
function Head5 { ((& git -C $tmp5 rev-parse HEAD) | Out-String).Trim() }
try {
    TG5 init; TG5 config user.email 't@e.com'; TG5 config user.name 'T'; TG5 config commit.gpgsign false; TG5 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp5 '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp5 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp5 'docs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp5 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp5 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp5 'README.md') '# r'; TG5 add -A; TG5 commit -m 'init'
    $e0 = Head5
    Set-Content (Join-Path $tmp5 'src/app.cs') 'class A{}'
    Set-Content (Join-Path $tmp5 $AUDIT) (New-Ledger -ParentSha $e0 -Subject 'add code')
    TG5 add -A; TG5 commit -m 'add code'
    TG5 mv src/app.cs docs/app.md
    Set-Content (Join-Path $tmp5 $AUDIT) (New-Ledger -ParentSha 'badf00d' -Subject 'rename')
    TG5 add -A
    $code = Run-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp5)
    Assert-Equal 1 $code 'code->docs rename stays panel-required via --no-renames; wrong parent_sha -> VIOLATION (exit 0 would mean the rename bypassed classification)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp5 -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp6 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t6-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp6 -Force | Out-Null
function TG6 { & git -C $tmp6 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git6 failed: $($args -join ' ')" } }
function Head6 { ((& git -C $tmp6 rev-parse HEAD) | Out-String).Trim() }
try {
    TG6 init; TG6 config user.email 't@e.com'; TG6 config user.name 'T'; TG6 config commit.gpgsign false; TG6 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp6 '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp6 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp6 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp6 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp6 'README.md') '# r'; TG6 add -A; TG6 commit -m 'init'
    $e0 = Head6
    Set-Content (Join-Path $tmp6 'src/code.cs') 'class C{}'
    Set-Content (Join-Path $tmp6 $AUDIT) (New-Ledger -ParentSha 'badf00d' -Subject 'first-add bootstrap')
    TG6 add -A; TG6 commit -m 'add gate + code'
    $code = Run-Checker -ScriptArgs @('-BaseRef', $e0, '-RepoRoot', $tmp6)
    Assert-Equal 1 $code 'history walk: first-add commit with an INVALID receipt is CAUGHT (fail-closed; no bootstrap skip)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp6 -Recurse -Force -ErrorAction SilentlyContinue
}

# Hardened (no bootstrap/never-existed skip): a panel-required commit whose tree carries NO audit
# file anywhere in history is a VIOLATION, not a silent skip (fail-closed CI - duck-logic panel finding).
$tmp7 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t7-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp7 -Force | Out-Null
function TG7 { & git -C $tmp7 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git7 failed: $($args -join ' ')" } }
function Head7 { ((& git -C $tmp7 rev-parse HEAD) | Out-String).Trim() }
try {
    TG7 init; TG7 config user.email 't@e.com'; TG7 config user.name 'T'; TG7 config commit.gpgsign false; TG7 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp7 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp7 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp7 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp7 'README.md') '# r'; TG7 add -A; TG7 commit -m 'init'
    $f0 = Head7
    Set-Content (Join-Path $tmp7 'src/code.cs') 'class C{}'
    TG7 add -A; TG7 commit -m 'panel-required, no receipt ever'
    $code = Run-Checker -ScriptArgs @('-BaseRef', $f0, '-RepoRoot', $tmp7)
    Assert-Equal 1 $code 'history walk: panel-required commit with NO audit file in history -> VIOLATION (fail-closed; no never-existed skip)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp7 -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "PASS: $script:passes   FAIL: $script:failures" -ForegroundColor $(if ($script:failures -gt 0) { 'Red' } else { 'Green' })
if ($script:failures -gt 0) { exit 1 } else { exit 0 }
