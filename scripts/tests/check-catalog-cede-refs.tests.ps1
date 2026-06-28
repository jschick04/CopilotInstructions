#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-catalog-cede-refs.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-catalog-cede-refs.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-catalog-cede-refs.ps1'
$script:Pass = 0; $script:Fail = 0

function New-CatalogRepo {
    $dir = New-TestGitRepository -Prefix 'cederef'
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
# A minimal valid rule row whose 3rd (params) cell opens with '{'.
function Rule { param([string] $Slug, [string] $Body) "| $Slug | review-pass-only | {} | $Body | | LOW |" }

try {
    Write-Host "`n=== a cede reference to an EXISTING slug resolves ==="
    $d = New-CatalogRepo
    Add-CatalogFile $d '00-catalog.md' @(
        (Rule 'owner-slug' 'Owns a thing. **Audit method**: check it.'),
        (Rule 'citing-slug' 'Does a thing. **Cede to the owning rule**: `owner-slug` owns the broad thing; this rule owns the narrow thing. **Audit method**: check it.')
    )
    git -C $d add -A 2>$null; git -C $d commit -q -m init
    $r = Run $d
    Assert-True ($r.ExitCode -eq 0) 'cede to an existing slug -> exit 0'

    Write-Host "`n=== a cede reference to a MISSING slug is caught ==="
    $d2 = New-CatalogRepo
    Add-CatalogFile $d2 '00-catalog.md' @(
        (Rule 'citing-slug' 'Does a thing. **Cede to the owning rule**: `ghost-owner-slug` owns the broad thing; this rule owns the narrow thing. **Audit method**: check it.')
    )
    git -C $d2 add -A 2>$null; git -C $d2 commit -q -m init
    $r = Run $d2
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'ghost-owner-slug') 'cede to a MISSING slug -> exit 1 (caught)'

    Write-Host "`n=== fail closed when the sources folder is absent ==="
    $d3 = New-TestGitRepository -Prefix 'cederef-none'
    Set-Content -LiteralPath (Join-Path $d3 'README.md') -Value '# no catalog sources' -Encoding utf8
    git -C $d3 add -A 2>$null; git -C $d3 commit -q -m init
    $r = Run $d3
    Assert-True ($r.ExitCode -eq 2) 'no pattern-catalog.sources folder -> exit 2 (fail closed)'

    Write-Host "`n=== a backtick token OUTSIDE a cede clause is NOT treated as a cede target ==="
    $d4 = New-CatalogRepo
    Add-CatalogFile $d4 '00-catalog.md' @(
        (Rule 'owner-slug' 'Owns a thing. **Audit method**: check it.'),
        (Rule 'citing-slug' 'Acceptable: the `caller-thing` owns the lock so it is fine. **Cede to the owning rule**: `owner-slug` owns the broad thing; this rule owns the narrow thing. **Audit method**: the `loop-helper` owns nothing here.')
    )
    git -C $d4 add -A 2>$null; git -C $d4 commit -q -m init
    $r = Run $d4
    Assert-True ($r.ExitCode -eq 0) 'backtick `owns` outside the cede clause (in Acceptable / Audit) -> exit 0 (not a cede target)'

    Write-Host "`n=== a cede reference to a slug in ANOTHER source file resolves ==="
    $d5 = New-CatalogRepo
    Add-CatalogFile $d5 '00-catalog.md' @( (Rule 'owner-in-other-file' 'Owns a thing. **Audit method**: check it.') )
    Add-CatalogFile $d5 '10-more.md' @( (Rule 'citing-slug' 'Does a thing. **Cede to the owning rule**: `owner-in-other-file` owns the broad thing; this rule owns the narrow thing. **Audit method**: check it.') )
    git -C $d5 add -A 2>$null; git -C $d5 commit -q -m init
    $r = Run $d5
    Assert-True ($r.ExitCode -eq 0) 'cede to a slug defined in another source file -> exit 0 (combined slug set)'

    Write-Host "`n=== a line with BOTH a resolving and a dangling cede target flags only the dangling ==="
    $d6 = New-CatalogRepo
    Add-CatalogFile $d6 '00-catalog.md' @(
        (Rule 'owner-slug' 'Owns a thing. **Audit method**: check it.'),
        (Rule 'citing-slug' 'Does a thing. **Cede to the owning rule**: `owner-slug` owns the broad thing; `ghost-two` owns the other thing; this rule owns the narrow thing. **Audit method**: check it.')
    )
    git -C $d6 add -A 2>$null; git -C $d6 commit -q -m init
    $r = Run $d6
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'ghost-two' -and $r.Output -notmatch "'owner-slug', which is not") 'mixed cede line -> exit 1, flags only the dangling ghost-two'

    Write-Host "`n=== fail closed when no slugs parse (anti-vacuous floor) ==="
    $d7 = New-CatalogRepo
    Add-CatalogFile $d7 '00-catalog.md' @('# Catalog prose with no rule rows', 'A note. **Cede to the owning rule**: `ghost` owns x. **Audit method**: none.')
    git -C $d7 add -A 2>$null; git -C $d7 commit -q -m init
    $r = Run $d7
    Assert-True ($r.ExitCode -eq 2) 'sources present but no rule rows parse -> exit 2 (anti-vacuous fail closed)'

    Write-Host "`n=== a slug containing a dot is parsed and resolvable as a cede target ==="
    $d8 = New-CatalogRepo
    Add-CatalogFile $d8 '00-catalog.md' @(
        (Rule 'ps-iswindows-undefined-under-strictmode-5.1' 'Owns a thing. **Audit method**: check it.'),
        (Rule 'citing-slug' 'Does a thing. **Cede to the owning rule**: `ps-iswindows-undefined-under-strictmode-5.1` owns the dotted thing; this rule owns the narrow thing. **Audit method**: check it.')
    )
    git -C $d8 add -A 2>$null; git -C $d8 commit -q -m init
    $r = Run $d8
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -match '2 slugs scanned') 'a dotted slug parses into the set (2 slugs scanned) and a cede to it resolves -> exit 0'

    Write-Host "`n=== a lower-case 'cede to the owning rule' marker is still scanned (case-insensitive) ==="
    $d9 = New-CatalogRepo
    Add-CatalogFile $d9 '00-catalog.md' @(
        (Rule 'citing-slug' 'Does a thing. cede to the owning rule: `ghost-lower` owns the broad thing; this rule owns the narrow thing. **audit method**: check it.')
    )
    git -C $d9 add -A 2>$null; git -C $d9 commit -q -m init
    $r = Run $d9
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'ghost-lower') 'lower-case cede marker still validated -> exit 1 (dangling caught, no fail-open)'

    Write-Host "`n=== a cede clause with no trailing audit-method does not scan later row cells (cell-pipe bound) ==="
    $d10 = New-CatalogRepo
    Add-CatalogFile $d10 '00-catalog.md' @(
        (Rule 'owner-slug' 'Owns a thing. **Audit method**: check it.'),
        '| citing-slug | review-pass-only | {} | Does a thing. **Cede to the owning rule**: `owner-slug` owns the thing. | `ghost-fp` owns x | LOW |'
    )
    git -C $d10 add -A 2>$null; git -C $d10 commit -q -m init
    $r = Run $d10
    Assert-True ($r.ExitCode -eq 0) 'cede clause without audit-method is bounded at the cell pipe; a later-cell owns token is not scanned -> exit 0'

    Write-Host "`n=== a cede to a DANGLING dotted slug is caught (guards the extractor char class) ==="
    $d11 = New-CatalogRepo
    Add-CatalogFile $d11 '00-catalog.md' @(
        (Rule 'citing-slug' 'Does a thing. **Cede to the owning rule**: `ghost-dotted-9.9` owns the dotted thing; this rule owns the narrow thing. **Audit method**: check it.')
    )
    git -C $d11 add -A 2>$null; git -C $d11 commit -q -m init
    $r = Run $d11
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'ghost-dotted-9\.9') 'cede to a dangling dotted slug -> exit 1 + names ghost-dotted-9.9 (extractor must capture the dot)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
