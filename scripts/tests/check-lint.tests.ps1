#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-lint.ps1 (the PSScriptAnalyzer gate).
# NOT Pester. Run: pwsh -File scripts/tests/check-lint.tests.ps1
#
# Fixtures are written to TEMP dirs (never tracked) - a tracked "deliberately dirty" fixture would
# be caught by the whole-repo lint of the gate itself. Each test drives check-lint via -Path.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-lint.ps1'
$script:Pass = 0; $script:Fail = 0

function New-Fixture {
    param([string[]] $Lines)
    $dir = New-TestTempDirectory -Prefix 'lint'
    $f = Join-Path $dir 'fixture.ps1'
    Set-Content -LiteralPath $f -Value $Lines -Encoding utf8
    return $f
}
function Run {
    param([string] $Path)
    $out = & pwsh -NoProfile -File $checker -Path $Path 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

try {
    Write-Host "`n=== clean file -> pass ==="
    $clean = New-Fixture @('$total = 2 + 3', 'Write-Output $total')
    $r = Run $clean
    Assert-True ($r.ExitCode -eq 0) 'a clean PowerShell file -> exit 0'

    Write-Host "`n=== finding (unused variable) -> fail ==="
    $dirty = New-Fixture @('$leftover = 99', 'Write-Output "done"')
    $r = Run $dirty
    Assert-True ($r.ExitCode -eq 1) 'unused variable -> exit 1 (the gate catches dead code, not a human reviewer)'
    Assert-True ($r.Output -match 'PSUseDeclaredVarsMoreThanAssignments') 'reports the offending rule name'

    Write-Host "`n=== a syntactically broken file -> fail (PSSA alone returns 0 findings for it) ==="
    $broken = New-Fixture @('function Oops {', '    if (')
    $r = Run $broken
    Assert-True ($r.ExitCode -eq 1) 'unparseable file -> exit 1 (parse pre-pass catches what PSSA does not)'
    Assert-True ($r.Output -match 'PSParseError') 'reports a parse error'

    Write-Host "`n=== a deliberately-excluded rule does NOT fire ==="
    # Write-Host is correct for gate/installer scripts, so PSAvoidUsingWriteHost is in `$excludeRules.
    $excluded = New-Fixture @('Write-Host "informational console output"')
    $r = Run $excluded
    Assert-True ($r.ExitCode -eq 0) 'Write-Host alone (PSAvoidUsingWriteHost is excluded) -> exit 0 (exclusion honored)'

    Write-Host "`n=== git/enumeration yields no files -> fail closed (anti-vacuous) ==="
    $emptyDir = New-TestTempDirectory -Prefix 'lint-empty'
    $r = Run (Join-Path $emptyDir 'does-not-exist.ps1')
    Assert-True ($r.ExitCode -eq 2) 'a -Path that resolves to 0 files -> exit 2 (fail closed, not a silent pass)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
