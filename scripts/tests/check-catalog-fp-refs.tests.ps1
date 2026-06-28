#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-catalog-fp-refs.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-catalog-fp-refs.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-catalog-fp-refs.ps1'
$script:Pass = 0; $script:Fail = 0

function New-CatalogRepo {
    $dir = New-TestGitRepository -Prefix 'fpref'
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/pr-quality-gate/pattern-catalog.sources') -Force | Out-Null
    return $dir
}
function Add-CatalogFile {
    param([string] $Dir, [string] $Name, [string[]] $Lines)
    $full = Join-Path $Dir ".github/pr-quality-gate/pattern-catalog.sources/$Name"
    Set-Content -LiteralPath $full -Value $Lines -Encoding utf8
}
function Run {
    param([string] $Dir)
    $out = & pwsh -NoProfile -File $checker -RepoRoot $Dir 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}
# A review-pass-only rule row whose 3rd (params) cell opens with '{'; $Fp is the 5th (fp_slug) cell.
function Rule { param([string] $Slug, [string] $Body, [string] $Fp = '') "| $Slug | review-pass-only | {} | $Body | $Fp | LOW |" }

try {
    Write-Host "`n=== a lower-case fp_slug resolves to its upper-case FP section ==="
    $d = New-CatalogRepo
    Add-CatalogFile $d '00-catalog.md' @(
        (Rule 'citing-slug' 'Does a thing.' 'fp-1'),
        '',
        '## FP-1: some-false-positive',
        'Body of the FP entry.'
    )
    git -C $d add -A 2>$null; git -C $d commit -q -m init
    $r = Run $d
    Assert-True ($r.ExitCode -eq 0) 'fp-1 reference resolves to ## FP-1: section (case-normalized) -> exit 0'

    Write-Host "`n=== a fp_slug with no matching FP section is caught ==="
    $d2 = New-CatalogRepo
    Add-CatalogFile $d2 '00-catalog.md' @(
        (Rule 'citing-slug' 'Does a thing.' 'fp-9'),
        '',
        '## FP-1: some-false-positive',
        'Body.'
    )
    git -C $d2 add -A 2>$null; git -C $d2 commit -q -m init
    $r = Run $d2
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'fp-9') 'dangling fp_slug fp-9 -> exit 1 (caught, names it)'

    Write-Host "`n=== an FP section referenced by no fp_slug is caught (reverse orphan) ==="
    $d3 = New-CatalogRepo
    Add-CatalogFile $d3 '00-catalog.md' @(
        (Rule 'citing-slug' 'Does a thing.' 'fp-1'),
        '',
        '## FP-1: referenced',
        'Body.',
        '',
        '## FP-2: orphan-never-referenced',
        'Body.'
    )
    git -C $d3 add -A 2>$null; git -C $d3 commit -q -m init
    $r = Run $d3
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'FP-2' -and $r.Output -match 'orphan') 'unreferenced ## FP-2: section -> exit 1 (reverse orphan)'

    Write-Host "`n=== a rule row with an unescaped pipe (cell-count drift) is caught ==="
    $d4 = New-CatalogRepo
    Add-CatalogFile $d4 '00-catalog.md' @(
        '| citing-slug | review-pass-only | {} | prompt with a | raw pipe inside it |  | LOW |'
    )
    git -C $d4 add -A 2>$null; git -C $d4 commit -q -m init
    $r = Run $d4
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'cells') 'unescaped pipe -> 7 cells -> exit 1 (malformed row, escape hint)'

    Write-Host "`n=== rows with empty fp_slug and no FP sections validate clean ==="
    $d5 = New-CatalogRepo
    Add-CatalogFile $d5 '00-catalog.md' @(
        (Rule 'rule-a' 'No fp.' ''),
        (Rule 'rule-b' 'Also no fp.' '')
    )
    git -C $d5 add -A 2>$null; git -C $d5 commit -q -m init
    $r = Run $d5
    Assert-True ($r.ExitCode -eq 0) 'empty fp_slug rows, no FP sections -> exit 0 (nothing to validate)'

    Write-Host "`n=== fail closed when the sources folder is absent ==="
    $d6 = New-TestGitRepository -Prefix 'fpref-none'
    Set-Content -LiteralPath (Join-Path $d6 'README.md') -Value '# no catalog sources' -Encoding utf8
    git -C $d6 add -A 2>$null; git -C $d6 commit -q -m init
    $r = Run $d6
    Assert-True ($r.ExitCode -eq 2) 'no pattern-catalog.sources folder -> exit 2 (fail closed)'

    Write-Host "`n=== fail closed when no rule rows parse (anti-vacuous floor) ==="
    $d7 = New-CatalogRepo
    Add-CatalogFile $d7 '00-catalog.md' @('# Catalog prose with no rule rows', '## FP-1: a-section', 'Body.')
    git -C $d7 add -A 2>$null; git -C $d7 commit -q -m init
    $r = Run $d7
    Assert-True ($r.ExitCode -eq 2) 'sources present but no rule rows parse -> exit 2 (anti-vacuous fail closed)'

    Write-Host "`n=== multiple fp references across files resolve bidirectionally ==="
    $d8 = New-CatalogRepo
    Add-CatalogFile $d8 '00-catalog.md' @(
        (Rule 'rule-a' 'A.' 'fp-1'),
        '',
        '## FP-1: first'
    )
    Add-CatalogFile $d8 '10-more.md' @(
        (Rule 'rule-b' 'B.' 'fp-2'),
        '',
        '## FP-2: second'
    )
    git -C $d8 add -A 2>$null; git -C $d8 commit -q -m init
    $r = Run $d8
    Assert-True ($r.ExitCode -eq 0) 'fp refs and FP sections split across files all resolve -> exit 0'

    Write-Host "`n=== a legacy 5-cell row that gains a stray pipe (shifts fp_slug off cell 5) is caught ==="
    $d9 = New-CatalogRepo
    Add-CatalogFile $d9 '00-catalog.md' @(
        '| citing-slug | tree-scoped | {} | prompt with a | stray pipe | fp-1 |'
    )
    git -C $d9 add -A 2>$null; git -C $d9 commit -q -m init
    $r = Run $d9
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'tier cell') 'a 5-cell row + stray pipe -> 6 cells with a non-tier last cell -> exit 1 (shift caught)'

    Write-Host "`n=== heading- and table-shaped lines inside a fenced code block are not scanned ==="
    $d10 = New-CatalogRepo
    Add-CatalogFile $d10 '00-catalog.md' @(
        (Rule 'citing-slug' 'A.' 'fp-1'),
        '',
        '## FP-1: real-section',
        'Body with an example:',
        '```markdown',
        '## FP-9: fake-heading-in-fence',
        '| fake-rule | review-pass-only | {} | x | fp-8 | LOW |',
        '```'
    )
    git -C $d10 add -A 2>$null; git -C $d10 commit -q -m init
    $r = Run $d10
    Assert-True ($r.ExitCode -eq 0) 'fenced ## FP-9: heading and fake rule row are skipped -> exit 0 (no false orphan or dangling)'

    Write-Host "`n=== a 6-cell row with an empty trailing tier cell (legacy form) is accepted ==="
    $d11 = New-CatalogRepo
    Add-CatalogFile $d11 '00-catalog.md' @(
        '| citing-slug | review-pass-only | {} | A prompt. | fp-1 |  |',
        '',
        '## FP-1: a-section'
    )
    git -C $d11 add -A 2>$null; git -C $d11 commit -q -m init
    $r = Run $d11
    Assert-True ($r.ExitCode -eq 0) '6 cells with an empty tier cell -> exit 0 (legacy form, fp_slug still read from cell 5)'

    Write-Host "`n=== an unclosed code fence fails closed (does not silently skip the file tail) ==="
    $d12 = New-CatalogRepo
    Add-CatalogFile $d12 '00-catalog.md' @(
        (Rule 'citing-slug' 'A.' 'fp-1'),
        '',
        '## FP-1: real-section',
        'Example:',
        '```markdown',
        '| hidden-bad | review-pass-only | {} | x | fp-9 | LOW |'
    )
    git -C $d12 add -A 2>$null; git -C $d12 commit -q -m init
    $r = Run $d12
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'unclosed') 'unclosed code fence -> exit 1 (fail closed, names the open fence)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
