#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester). Run: pwsh -File <this file>

$checkerPath = (Resolve-Path (Join-Path $PSScriptRoot '../check-diff-consistency.ps1')).Path
$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

$script:failures = 0
$script:passes = 0
function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    if ($Condition) { $script:passes++; Write-Host "  [PASS] $Description" }
    else { $script:failures++; Write-Host "  [FAIL] $Description" -ForegroundColor Red }
}
function Assert-Equal {
    param([Parameter(Mandatory)] $Expected, $Actual, [Parameter(Mandatory)] [string] $Description)
    if ($Expected -eq $Actual) { $script:passes++; Write-Host "  [PASS] $Description" }
    else { $script:failures++; Write-Host "  [FAIL] $Description (expected '$Expected', got '$Actual')" -ForegroundColor Red }
}

function New-FixtureRepo {
    param([hashtable] $Files)
    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("ddc-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo | Out-Null
    Push-Location $repo
    try {
        git init -q
        git config user.email 't@t'; git config user.name 't'
        git config commit.gpgsign false; git config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
        $anchorEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $repo 'scripts/check-diff-consistency.ps1'), "# anchor stub`n", $anchorEncoding)
        [System.IO.File]::WriteAllText((Join-Path $repo 'base.yml'), "name: base`n", (New-Object System.Text.UTF8Encoding($false)))
        git add -A | Out-Null; git commit -qm base | Out-Null
        git branch -m main | Out-Null; git checkout -q -b feature
        foreach ($rel in $Files.Keys) {
            $full = Join-Path $repo $rel
            $dir = Split-Path $full -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $content = ($Files[$rel] -replace "`r`n", "`n")
            [System.IO.File]::WriteAllText($full, $content, (New-Object System.Text.UTF8Encoding($false)))
        }
        git add -A | Out-Null; git commit -qm fixture | Out-Null
    } finally { Pop-Location }
    return $repo
}
function Invoke-Checker {
    param([string] $Repo, [string] $Base = 'main', [string] $Head = 'feature', [string[]] $Extra)
    $argList = @('-NoProfile', '-File', $checkerPath, '-RepoRoot', $Repo, '-HeadRef', $Head)
    if ($Base) { $argList += @('-BaseRef', $Base) }
    if ($Extra) { $argList += $Extra }
    $out = & $pwshExe @argList 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}
function Count-Slug { param([string] $Output, [string] $Slug) ([regex]::Matches($Output, [regex]::Escape($Slug))).Count }

Write-Host ""
Write-Host "=== line-local deterministic rules (fire + FP-suppression + regressions) ===" -ForegroundColor Cyan
$repo = New-FixtureRepo @{
    'b.sh'        = "#!/bin/sh`nsed -n '1p' f || cp default f`nsed -i 's/a/b/' f || { echo `"sed failed`"; exit 1; }`nsed -e 's/x/y/' f || echo `"this will fail later`"`n"
    'ci.yml'      = "name: ci`njobs:`n  a:`n    steps:`n      - run: cmd || true`n      - run: jq --arg msg `"line1\nline2`" '.x=`$msg' < in.json`n"
    'README.md'   = "# Docs`nExample ledger line: ``files-touched: 1`` (this is prose, must NOT hard-fail)`n"
}
$r = Invoke-Checker -Repo $repo
Assert-Equal 2 (Count-Slug $r.Output 'shell-sed-exit-zero-fallback-unreachable') 'sed||default + sed||echo"...fail..." both fire; sed||{...exit} excluded (forcing#5 regression)'
Assert-True  ((Count-Slug $r.Output 'ci-shell-or-true-swallows-real-failures') -ge 1) '|| true fires'
Assert-True  ((Count-Slug $r.Output 'ci-jq-arg-literal-backslash-n') -ge 1) 'jq --arg literal \n fires'
Assert-Equal 0 (Count-Slug $r.Output 'receipt-numeric-claim-drift') 'README prose "files-touched: 1" does NOT fire (forcing#4 regression; rule scoped to receipt artifact)'
Assert-Equal 0 $r.ExitCode 'all-advisory findings => exit 0 (non-gating)'
Remove-Item -Recurse -Force $repo

$plus = New-FixtureRepo @{ 'plus.sh' = "#!/bin/sh`n++state || true`n" }
$rp = Invoke-Checker -Repo $plus
Assert-True ((Count-Slug $rp.Output 'ci-shell-or-true-swallows-real-failures') -ge 1) 'rule fires on a line whose content starts with ++ (diff line +++...); not dropped (forcing re-review #1)'
Remove-Item -Recurse -Force $plus

Write-Host ""
Write-Host "=== receipt numeric-claim drift (hard; receipt artifact only; audits/** excluded from denominator) ===" -ForegroundColor Cyan
$match = New-FixtureRepo @{
    'src/a.cs' = "class A {}`n"; 'src/b.cs' = "class B {}`n"
    '.github/pr-quality-gate/audits/post-code-change-last.md' = "POST-CODE-CHANGE LEDGER`n  files-touched: 2`n"
}
$rm = Invoke-Checker -Repo $match -Base '' -Extra @('-Mode', 'commit')
Assert-Equal 0 (Count-Slug $rm.Output 'receipt-numeric-claim-drift') 'files-touched:2 == 2 non-audit files => no drift'
Assert-Equal 0 $rm.ExitCode 'matching receipt => exit 0'
Remove-Item -Recurse -Force $match

$drift = New-FixtureRepo @{
    'src/a.cs' = "class A {}`n"; 'src/b.cs' = "class B {}`n"
    '.github/pr-quality-gate/audits/post-code-change-last.md' = "POST-CODE-CHANGE LEDGER`n  files-touched: 9`n"
}
$rd = Invoke-Checker -Repo $drift -Base '' -Extra @('-Mode', 'commit')
Assert-True ((Count-Slug $rd.Output 'receipt-numeric-claim-drift') -ge 1) 'files-touched:9 != 2 non-audit files => drift fires'
Assert-Equal 1 $rd.ExitCode 'drift is a HARD finding => exit 1'
Remove-Item -Recurse -Force $drift

$rangeReceipt = New-FixtureRepo @{ 'x.cs' = "class X {}`n"; '.github/pr-quality-gate/audits/post-code-change-last.md' = "LEDGER`n  files-touched: 99`n" }
$rr = Invoke-Checker -Repo $rangeReceipt
Assert-Equal 0 (Count-Slug $rr.Output 'receipt-numeric-claim-drift') 'receipt rule does NOT fire in range mode (commit-scoped; avoids multi-commit FP, forcing re-review #2)'
Remove-Item -Recurse -Force $rangeReceipt

Write-Host ""
Write-Host "=== -Mode ref contract + -Json output ===" -ForegroundColor Cyan
$mode = New-FixtureRepo @{ 'b.sh' = "#!/bin/sh`nsed -n '1p' f || cp default f`n" }
$rc = Invoke-Checker -Repo $mode -Base '' -Extra @('-Mode', 'commit')
Assert-True ((Count-Slug $rc.Output 'shell-sed-exit-zero-fallback-unreachable') -ge 1) '-Mode commit (parent..tip) finds the sed finding without explicit -BaseRef'
$rs = Invoke-Checker -Repo $mode -Base '' -Extra @('-Mode', 'pr-sweep')
Assert-True ((Count-Slug $rs.Output 'shell-sed-exit-zero-fallback-unreachable') -ge 1) '-Mode pr-sweep (merge-base..head) finds the sed finding'
$rj = Invoke-Checker -Repo $mode -Extra @('-Json')
$json = $rj.Output | ConvertFrom-Json
Assert-Equal 'pass' $json.status '-Json status=pass when no hard finding'
Assert-True (@($json.findings | Where-Object { $_.slug -eq 'shell-sed-exit-zero-fallback-unreachable' }).Count -ge 1) '-Json findings[] contains the sed slug'
Remove-Item -Recurse -Force $mode

Write-Host ""
Write-Host "=== StrictMode empty-diff + fail-closed ===" -ForegroundColor Cyan
$empty = New-FixtureRepo @{ 'src/a.cs' = "class A {}`n" }
$re = Invoke-Checker -Repo $empty -Base 'main' -Head 'main'
Assert-Equal 0 $re.ExitCode 'empty diff (main..main) => exit 0, no StrictMode crash'
Assert-True ($re.Output -match 'no findings|PASS') 'empty diff reports a clean pass'
$rf = Invoke-Checker -Repo $empty -Base 'does-not-exist' -Head 'feature'
Assert-True ($rf.ExitCode -ne 0) 'bogus base ref => fail-closed (non-zero exit), not a false pass'
Remove-Item -Recurse -Force $empty

$rootRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("ddc-root-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $rootRepo '.github/pr-quality-gate/audits') -Force | Out-Null
$enc2 = New-Object System.Text.UTF8Encoding($false)
Push-Location $rootRepo
git init -q; git config user.email 't@t'; git config user.name 't'; git config commit.gpgsign false; git config core.autocrlf false
New-Item -ItemType Directory -Path (Join-Path $rootRepo 'scripts') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $rootRepo 'scripts/check-diff-consistency.ps1'), "# anchor stub`n", $enc2)
[System.IO.File]::WriteAllText((Join-Path $rootRepo 'a.cs'), "class A {}`n", $enc2)
[System.IO.File]::WriteAllText((Join-Path $rootRepo 'b.cs'), "class B {}`n", $enc2)
[System.IO.File]::WriteAllText((Join-Path $rootRepo '.github/pr-quality-gate/audits/post-code-change-last.md'), "LEDGER`n  files-touched: 3`n", $enc2)
git add -A | Out-Null; git commit -qm root | Out-Null
Pop-Location
$rr = Invoke-Checker -Repo $rootRepo -Base '' -Head 'HEAD' -Extra @('-Mode', 'commit')
Assert-True ($rr.ExitCode -eq 0) 'root commit + -Mode commit: no crash (empty-tree base) AND receipt files-touched:3 == 3 non-audit (--root denominator)'
Remove-Item -Recurse -Force $rootRepo

$ren = Join-Path ([System.IO.Path]::GetTempPath()) ("ddc-ren-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $ren '.github/pr-quality-gate/audits') -Force | Out-Null
$enc3 = New-Object System.Text.UTF8Encoding($false)
Push-Location $ren
git init -q; git config user.email 't@t'; git config user.name 't'; git config commit.gpgsign false; git config core.autocrlf false
New-Item -ItemType Directory -Path (Join-Path $ren 'scripts') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $ren 'scripts/check-diff-consistency.ps1'), "# anchor stub`n", $enc3)
[System.IO.File]::WriteAllText((Join-Path $ren 'old.cs'), "class Old {}`n", $enc3)
git add -A | Out-Null; git commit -qm base | Out-Null; git branch -m main | Out-Null; git checkout -q -b feature
git mv old.cs new.cs
[System.IO.File]::WriteAllText((Join-Path $ren '.github/pr-quality-gate/audits/post-code-change-last.md'), "LEDGER`n  files-touched: 2`n", $enc3)
git add -A | Out-Null; git commit -qm rename | Out-Null
Pop-Location
$rrn = Invoke-Checker -Repo $ren -Base '' -Head 'HEAD' -Extra @('-Mode', 'commit')
Assert-Equal 0 (Count-Slug $rrn.Output 'receipt-numeric-claim-drift') 'rename (old+new = 2 paths blind) vs files-touched:2 => no drift (rename-blind, matches panel-ledger; -M would wrongly count 1)'
Assert-Equal 0 $rrn.ExitCode 'rename receipt matches rename-blind count => exit 0'
Remove-Item -Recurse -Force $ren

Write-Host ""
if ($script:failures -eq 0) { Write-Host "ALL PASS ($script:passes assertions)" -ForegroundColor Green; exit 0 }
else { Write-Host "$script:failures FAILED, $script:passes passed" -ForegroundColor Red; exit 1 }
