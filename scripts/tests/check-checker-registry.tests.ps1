#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test for the checker-registry parity gate. Run: pwsh -File <this file>

$parityScript = (Resolve-Path (Join-Path $PSScriptRoot '../check-checker-registry.ps1')).Path
. (Join-Path $PSScriptRoot 'test-common.ps1')
$pwshExe = Get-TestPwshExe
$repoRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel).Trim()

$script:Fail = 0
$script:Pass = 0
function Invoke-Parity { param([string] $RegistryPath, [string] $Root = $repoRoot)
    $a = @('-NoProfile', '-File', $parityScript, '-RepoRoot', $Root)
    if ($RegistryPath) { $a += @('-RegistryPath', $RegistryPath) }
    $out = & $pwshExe @a 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}
function New-TempRegistry { param([string] $Body)
    $p = Join-Path ([System.IO.Path]::GetTempPath()) ("reg-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tsv')
    [System.IO.File]::WriteAllText($p, ($Body -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $p
}
function New-RegistryAnchorRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("reg-anchor-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $dataDir = Join-Path $root '.github/pr-quality-gate/data'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dataDir 'checker-registry.tsv'), "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`n", (New-Object System.Text.UTF8Encoding($false)))
    return $root
}

Write-Host ""
Write-Host "=== checker-registry parity ===" -ForegroundColor Cyan

$r1 = Invoke-Parity -RegistryPath $null
Assert-True ($r1.ExitCode -eq 0) 'real registry => PASS (exit 0)'
Assert-True ($r1.Output -match 'PASS') 'real registry => prints PASS'

$broken = New-TempRegistry "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`nbogus-slug`tbogus`tscripts/does-not-exist.ps1`tscripts/tests/nope.ps1`thard-fail`n"
$anchorRoot = New-RegistryAnchorRoot
$r2 = Invoke-Parity -RegistryPath $broken -Root $anchorRoot
Assert-True ($r2.ExitCode -eq 1) 'missing checker/fixtures => FAIL (exit 1)'
Assert-True ($r2.Output -match 'missing') 'missing checker => reports "missing"'
Remove-Item -Force $broken
Remove-Item -Recurse -Force $anchorRoot

$drift = New-TempRegistry "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`nreceipt-numeric-claim-drift`tcheck-diff-consistency`tscripts/check-diff-consistency.ps1`tscripts/tests/check-diff-consistency.tests.ps1`thard-fail`n"
$r3 = Invoke-Parity -RegistryPath $drift
Assert-True ($r3.ExitCode -eq 1) 'registry omitting emitted slugs => FAIL (drift, exit 1)'
Assert-True ($r3.Output -match 'drift') 'drift => reports "drift"'
Remove-Item -Force $drift

Write-Host ""
Write-Host "=== catalog<->registry parity ===" -ForegroundColor Cyan
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("regroot-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmpRoot 'scripts/tests') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpRoot '.github/pr-quality-gate/data') -Force | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot '.github/pr-quality-gate/data/checker-registry.tsv'), "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot 'scripts/check-diff-consistency.ps1'), "Add-Finding 'slug-a' x`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot 'scripts/tests/fix.ps1'), "# fixtures`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot '.github/pr-quality-gate/pattern-catalog.md'), "| slug-a | checker-scoped | {""checker_id"":""check-diff-consistency""} |  |  | LOW |`n", $enc)
$reg = New-TempRegistry "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`nslug-a`tcheck-diff-consistency`tscripts/check-diff-consistency.ps1`tscripts/tests/fix.ps1`tadvisory`nslug-b`tother-checker`tscripts/check-diff-consistency.ps1`tscripts/tests/fix.ps1`tadvisory`n"
$rc = Invoke-Parity -RegistryPath $reg -Root $tmpRoot
Assert-True ($rc.ExitCode -eq 1) 'registry slug with no checker-scoped catalog row => FAIL (catalog<->registry parity)'
Assert-True ($rc.Output -match 'NO checker-scoped row') 'reports the missing catalog row'
Remove-Item -Force $reg; Remove-Item -Recurse -Force $tmpRoot

$dup = New-TempRegistry "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`ndup-x`tc`ts.ps1`tf.ps1`tadvisory`ndup-x`tc`ts.ps1`tf.ps1`tadvisory`n"
$dupAnchorRoot = New-RegistryAnchorRoot
$rdup = Invoke-Parity -RegistryPath $dup -Root $dupAnchorRoot
Assert-True ($rdup.Output -match 'duplicate slug') 'duplicate slug row in registry => FAIL loud'
Assert-True ($rdup.ExitCode -eq 1) 'duplicate slug => exit 1'
Remove-Item -Force $dup
Remove-Item -Recurse -Force $dupAnchorRoot

$tmpRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ("regroot2-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmpRoot2 'scripts/tests') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpRoot2 '.github/pr-quality-gate/data') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $tmpRoot2 '.github/pr-quality-gate/data/checker-registry.tsv'), "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot2 'scripts/check-diff-consistency.ps1'), "x`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot2 'scripts/tests/fix.ps1'), "x`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $tmpRoot2 '.github/pr-quality-gate/pattern-catalog.md'), "| slug-a | checker-scoped | {""checker_id"":""AAA""} |  |  | LOW |`n", $enc)
$reg2 = New-TempRegistry "slug`tchecker_id`tchecker_script`tfixtures`tmaturity`nslug-a`tBBB`tscripts/check-diff-consistency.ps1`tscripts/tests/fix.ps1`tadvisory`n"
$rcid = Invoke-Parity -RegistryPath $reg2 -Root $tmpRoot2
Assert-True ($rcid.Output -match 'does not match registry checker_id') 'catalog checker_id != registry checker_id => FAIL'
Assert-True ($rcid.ExitCode -eq 1) 'checker_id mismatch => exit 1'
Remove-Item -Force $reg2; Remove-Item -Recurse -Force $tmpRoot2

Write-Host ""
if ($script:Fail -eq 0) { Write-Host "ALL PASS ($script:Pass assertions)" -ForegroundColor Green; exit 0 }
else { Write-Host "$script:Fail FAILED, $script:Pass passed" -ForegroundColor Red; exit 1 }
