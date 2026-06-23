#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-duplication.ps1.
# Run: pwsh -File scripts/tests/check-duplication.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-duplication.ps1'
$script:Pass = 0; $script:Fail = 0

function New-Repo { New-TestGitRepository -Prefix 'dup' }
function Run { param($Dir)
    $out = & pwsh -NoProfile -File $checker -RepoRoot $Dir -MinLines 6 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

$BLOCK = @(
    'function Compute-Total($items) {'
    '    $sum = 0'
    '    foreach ($item in $items) {'
    '        $sum += $item.Price * $item.Quantity'
    '    }'
    '    return $sum'
    '}'
)

try {
    Write-Host "`n=== added block duplicating existing committed content ==="
    $d = New-Repo
    Set-Content (Join-Path $d 'orders.ps1') ($BLOCK + @('# orders'))
    git -C $d add -A 2>$null; git -C $d commit -q -m base
    Set-Content (Join-Path $d 'invoices.ps1') (@('# invoices') + $BLOCK)
    git -C $d add invoices.ps1 2>$null
    $r = Run $d
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicates existing committed content') 'added block duplicating HEAD content -> exit 1'

    Write-Host "`n=== non-duplicate added block ==="
    $d2 = New-Repo
    Set-Content (Join-Path $d2 'a.ps1') @('# seed'); git -C $d2 add -A 2>$null; git -C $d2 commit -q -m base
    Set-Content (Join-Path $d2 'b.ps1') (@(
        'function Get-UniqueThing($x) {'
        '    $result = $x * 2'
        '    $label = "value"'
        '    Write-Output $label'
        '    Write-Output $result'
        '    return $result'
        '}') )
    git -C $d2 add b.ps1 2>$null
    $r = Run $d2
    Assert-True ($r.ExitCode -eq 0) 'unique added block -> exit 0'

    Write-Host "`n=== duplicate within the same changeset ==="
    $d3 = New-Repo
    Set-Content (Join-Path $d3 'seed.ps1') @('# seed'); git -C $d3 add -A 2>$null; git -C $d3 commit -q -m base
    Set-Content (Join-Path $d3 'x.ps1') ($BLOCK)
    Set-Content (Join-Path $d3 'y.ps1') ($BLOCK)
    git -C $d3 add x.ps1 y.ps1 2>$null
    $r = Run $d3
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicates within this changeset') 'block duplicated across two new files -> exit 1'

    Write-Host "`n=== below threshold + boilerplate ==="
    $d4 = New-Repo
    Set-Content (Join-Path $d4 'seed.ps1') ($BLOCK); git -C $d4 add -A 2>$null; git -C $d4 commit -q -m base
    Set-Content (Join-Path $d4 'small.ps1') (@('$x = 1', '$y = 2'))
    git -C $d4 add small.ps1 2>$null
    $r = Run $d4
    Assert-True ($r.ExitCode -eq 0) 'added block below MinLines -> exit 0'
    # boilerplate-only block duplicating closing braces should NOT trip (low-signal skipped)
    Set-Content (Join-Path $d4 'braces.ps1') (@('}', '}', '}', '}', '}', '}', '}'))
    git -C $d4 add braces.ps1 2>$null
    $r = Run $d4
    Assert-True ($r.ExitCode -eq 0) 'boilerplate-only (all-trivial) added block -> exit 0 (low-signal skipped)'

    Write-Host "`n=== waiver (dry-audit disposition) suppresses a flagged dup ==="
    $d5 = New-Repo
    Set-Content (Join-Path $d5 'seed.ps1') @('# seed'); git -C $d5 add -A 2>$null; git -C $d5 commit -q -m base
    Set-Content (Join-Path $d5 'p.ps1') ($BLOCK)
    Set-Content (Join-Path $d5 'q.ps1') ($BLOCK)
    git -C $d5 add p.ps1 q.ps1 2>$null
    $r = Run $d5
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match '\[sig:[0-9a-f]{16}\]') 'unwaived dup prints a [sig:hash] -> exit 1'
    $sigs = @([regex]::Matches($r.Output, '\[sig:([0-9a-f]{16})\]') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    Set-Content -LiteralPath (Join-Path $d5 'waivers.txt') -Value ($sigs | ForEach-Object { "$_  intentional idiomatic block (test)" })
    $out = & pwsh -NoProfile -File $checker -RepoRoot $d5 -MinLines 6 -WaiverPath 'waivers.txt' 2>&1
    Assert-True ($LASTEXITCODE -eq 0) 'dup whose [sig] hashes are all in the waivers file -> exit 0 (waived)'

    Write-Host "`n=== git failure -> fail closed (not a silent pass) ==="
    $d6 = New-Repo
    Set-Content (Join-Path $d6 'seed.ps1') @('# seed'); git -C $d6 add -A 2>$null; git -C $d6 commit -q -m base
    $o6 = (& pwsh -NoProfile -File $checker -RepoRoot $d6 -MinLines 6 -BaseRef 'no-such-ref-xyz' 2>&1 | Out-String); $c6 = $LASTEXITCODE
    Assert-True ($c6 -ne 0 -and $o6 -match 'Failing closed') 'git diff failure (bad -BaseRef) -> non-zero exit (fail closed, not skip)'

    Write-Host "`n=== generated pattern-catalog.md is excluded (source<->generated mirror not flagged) ==="
    $d7 = New-Repo
    $gateDir = Join-Path $d7 '.github/pr-quality-gate/pattern-catalog.sources'
    New-Item -ItemType Directory -Force -Path $gateDir | Out-Null
    $genCatalog = Join-Path $d7 '.github/pr-quality-gate/pattern-catalog.md'
    $srcCatalog = Join-Path $d7 '.github/pr-quality-gate/pattern-catalog.sources/00-catalog.md'
    Set-Content $genCatalog @('# seed'); Set-Content $srcCatalog @('# seed')
    git -C $d7 add -A 2>$null; git -C $d7 commit -q -m base
    Set-Content $srcCatalog (@('# seed') + $BLOCK)
    Set-Content $genCatalog (@('# seed') + $BLOCK)
    git -C $d7 add -A 2>$null
    $r = Run $d7
    Assert-True ($r.ExitCode -eq 0) 'block mirrored in source + generated pattern-catalog.md -> exit 0 (generated mirror path-excluded; source block is unique)'

    Write-Host "`n=== source 00-catalog.md is still scanned (only the generated mirror is excluded) ==="
    $d8 = New-Repo
    $srcDir8 = Join-Path $d8 '.github/pr-quality-gate/pattern-catalog.sources'
    New-Item -ItemType Directory -Force -Path $srcDir8 | Out-Null
    $srcCatalog8 = Join-Path $d8 '.github/pr-quality-gate/pattern-catalog.sources/00-catalog.md'
    Set-Content $srcCatalog8 @('# seed'); git -C $d8 add -A 2>$null; git -C $d8 commit -q -m base
    Set-Content $srcCatalog8 (@('# seed') + $BLOCK)
    Set-Content (Join-Path $d8 'other.ps1') ($BLOCK)
    git -C $d8 add -A 2>$null
    $r = Run $d8
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicates within this changeset') 'block in source 00-catalog.md + another file -> still flagged (source not excluded)'

    Write-Host "`n=== near-miss path is NOT excluded (anchor is exact repo-root-relative) ==="
    $d9 = New-Repo
    New-Item -ItemType Directory -Force -Path (Join-Path $d9 'docs') | Out-Null
    Set-Content (Join-Path $d9 'seed.ps1') @('# seed'); git -C $d9 add -A 2>$null; git -C $d9 commit -q -m base
    Set-Content (Join-Path $d9 'docs/pattern-catalog.md') ($BLOCK)
    Set-Content (Join-Path $d9 'other.ps1') ($BLOCK)
    git -C $d9 add -A 2>$null
    $r = Run $d9
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicates within this changeset') 'decoy docs/pattern-catalog.md (same basename, different dir) is NOT excluded -> still flagged'
}
finally {
    Remove-TestTempDirectories
}

Complete-TestRun
