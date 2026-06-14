<#
  check-checker-registry.ps1 - fail-loud parity gate for the sparse deterministic checker-registry (D2).
  Enforces (per the converged spec): every registered slug has an EXISTING checker_script + fixtures and a valid
  maturity, AND the slugs check-diff-consistency.ps1 actually emits are exactly the slugs registered to it (no
  drift in either direction). A hard-fail slug with no wired checker is the specific failure this prevents.
  SIZE-FREE: a script; consumes zero LLM context. Exit 1 on any violation, 0 on parity.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $RegistryPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('.github/pr-quality-gate')
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

if (-not $RegistryPath) { $RegistryPath = Join-Path $RepoRoot '.github/pr-quality-gate/data/checker-registry.tsv' }
if (-not (Test-Path -LiteralPath $RegistryPath)) { Write-Host "checker-registry parity: FAIL - registry not found: $RegistryPath" -ForegroundColor Red; exit 1 }

$errors = New-Object System.Collections.Generic.List[string]
$validMaturity = @('hard-fail', 'advisory')

$rows = New-Object System.Collections.Generic.List[object]
$seenSlugs = New-Object System.Collections.Generic.HashSet[string]
$lineNo = 0
foreach ($line in (Get-Content -LiteralPath $RegistryPath)) {
    $lineNo++
    if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
    $cells = $line -split "`t"
    if ($cells[0] -eq 'slug') { continue }
    if ($cells.Count -ne 5) { $errors.Add("line ${lineNo}: expected 5 tab-separated cells, got $($cells.Count)"); continue }
    if (-not $seenSlugs.Add($cells[0])) { $errors.Add("line ${lineNo}: duplicate slug '$($cells[0])'"); continue }
    $rows.Add([pscustomobject]@{ Slug = $cells[0]; CheckerId = $cells[1]; Script = $cells[2]; Fixtures = $cells[3]; Maturity = $cells[4] })
}

foreach ($r in $rows) {
    if ($validMaturity -notcontains $r.Maturity) { $errors.Add("slug '$($r.Slug)': invalid maturity '$($r.Maturity)' (expected hard-fail|advisory)") }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $r.Script)))   { $errors.Add("slug '$($r.Slug)': checker_script missing: $($r.Script)") }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $r.Fixtures))) { $errors.Add("slug '$($r.Slug)': fixtures missing: $($r.Fixtures)") }
}

$ddcScript = Join-Path $RepoRoot 'scripts/check-diff-consistency.ps1'
if (Test-Path -LiteralPath $ddcScript) {
    $emitted = @([regex]::Matches((Get-Content -LiteralPath $ddcScript -Raw), "Add-Finding\s+'([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $registered = @($rows | Where-Object { $_.CheckerId -eq 'check-diff-consistency' } | ForEach-Object { $_.Slug } | Sort-Object -Unique)
    foreach ($s in $emitted) { if ($registered -notcontains $s) { $errors.Add("check-diff-consistency emits slug '$s' but it is NOT registered (drift)") } }
    foreach ($s in $registered) { if ($emitted -notcontains $s) { $errors.Add("registry lists '$s' for check-diff-consistency but the script never emits it (drift)") } }
}

$catalogPath = Join-Path $RepoRoot '.github/pr-quality-gate/pattern-catalog.md'
if (-not (Test-Path -LiteralPath $catalogPath)) {
    $errors.Add("pattern-catalog.md not found at $catalogPath (cannot verify catalog<->registry parity)")
}
else {
    $catalogCheckerMap = @{}
    foreach ($line in (Get-Content -LiteralPath $catalogPath)) {
        if ($line -notmatch '^\|') { continue }
        $cells = ($line -split '(?<!\\)\|')
        if ($cells.Count -lt 4) { continue }
        $trimmed = @($cells[1..($cells.Count - 2)] | ForEach-Object { $_.Trim() })
        if ($trimmed.Count -ge 3 -and $trimmed[1] -eq 'checker-scoped') {
            $cid = ''
            try { $cid = ($trimmed[2] -replace '\\\|', '|' | ConvertFrom-Json).checker_id } catch { $cid = '' }
            $catalogCheckerMap[$trimmed[0]] = $cid
        }
    }
    $regMap = @{}; foreach ($r in $rows) { $regMap[$r.Slug] = $r.CheckerId }
    $regSlugs = @($regMap.Keys | Sort-Object)
    $catSlugs = @($catalogCheckerMap.Keys | Sort-Object)
    foreach ($s in $regSlugs) { if ($catSlugs -notcontains $s) { $errors.Add("registry slug '$s' has NO checker-scoped row in pattern-catalog.md") } }
    foreach ($s in $catSlugs) { if ($regSlugs -notcontains $s) { $errors.Add("catalog checker-scoped slug '$s' is NOT in the checker-registry") } }
    foreach ($s in $regSlugs) { if (($catSlugs -contains $s) -and ($catalogCheckerMap[$s] -ne $regMap[$s])) { $errors.Add("slug '$s': catalog checker_id '$($catalogCheckerMap[$s])' does not match registry checker_id '$($regMap[$s])'") } }
}

if ($errors.Count -gt 0) {
    Write-Host "checker-registry parity: FAIL ($($errors.Count) error(s))" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "checker-registry parity: PASS ($($rows.Count) registered slug(s))" -ForegroundColor Green
exit 0
