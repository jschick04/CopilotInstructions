<#
  check-md-size.ps1 - extracted from instructions-size-check.yml so the size budgets live in ONE script that both the
  workflow and run-local-ci.ps1 invoke (single source of truth; no inline check logic in the workflow). Enforces every
  markdown size budget: AGENTS.md <= 28 KB; .github/**/*.md <= 30 KB (allowlisted exceptions warn, not fail; the
  generator SOURCE dir is skipped); profiles/**/*.md <= 4 KB. Sizes are measured LF-normalized so a Windows CRLF working
  tree reports the SAME byte count CI sees after an LF checkout. Fail-closed: any over-budget non-exempt file -> exit 1.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('AGENTS.md')
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

# LF-normalized byte count: matches the size an ubuntu CI runner sees after an LF checkout, regardless of local CRLF.
function Get-LfByteCount {
    param([string] $Path)
    $raw = [System.IO.File]::ReadAllText($Path)
    $lf = $raw -replace "`r`n", "`n"
    return [System.Text.Encoding]::UTF8.GetByteCount($lf)
}

function ConvertTo-RelPath {
    param([string] $FullPath)
    $prefix = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return ($FullPath -replace [regex]::Escape($prefix), '') -replace '\\', '/'
}

$budgets = @(
    [pscustomobject]@{
        Name      = 'AGENTS.md (always-loaded core)'
        Root      = 'AGENTS.md'
        Recurse   = $false
        Limit     = 28672
        Allowlist = @()
        SkipGlob  = @()
    },
    [pscustomobject]@{
        Name      = '.github/**/*.md'
        Root      = '.github'
        Recurse   = $true
        Limit     = 30720
        Allowlist = @('.github/pr-quality-gate/pattern-catalog.md')   # P3 split target - warn, do not fail
        SkipGlob  = @('.github/pr-quality-gate/pattern-catalog.sources/*')   # generator inputs, not instruction files
    },
    [pscustomobject]@{
        Name      = 'profiles/**/*.md'
        Root      = 'profiles'
        Recurse   = $true
        Limit     = 4096
        Allowlist = @()
        SkipGlob  = @()
    }
)

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($budget in $budgets) {
    $rootPath = Join-Path $RepoRoot $budget.Root
    $files = @()
    if ($budget.Recurse) {
        if (Test-Path -LiteralPath $rootPath) {
            $files = Get-ChildItem -Recurse -LiteralPath $rootPath -Filter '*.md' -File -ErrorAction SilentlyContinue
        }
    }
    elseif (Test-Path -LiteralPath $rootPath) {
        $files = @(Get-Item -LiteralPath $rootPath)
    }
    foreach ($file in $files) {
        $rel = ConvertTo-RelPath $file.FullName
        $skip = $false
        foreach ($glob in $budget.SkipGlob) { if ($rel -like $glob) { $skip = $true; break } }
        if ($skip) { continue }
        $checked++
        $size = Get-LfByteCount $file.FullName
        if ($size -gt $budget.Limit) {
            if ($budget.Allowlist -contains $rel) {
                $warnings.Add("$rel ($size bytes) - EXEMPT (allowlisted, over the $($budget.Limit)-byte budget)")
            }
            else {
                $failures.Add("$rel ($size bytes) exceeds the $($budget.Limit)-byte budget for $($budget.Name)")
            }
        }
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "WARNINGS (allowlisted, over budget):"
    $warnings | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
if ($failures.Count -gt 0) {
    Write-Host "check-md-size: $($failures.Count) file(s) over budget:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  ::error::$_" }
    exit 1
}
if ($checked -eq 0) {
    Write-Host "::error::INVOCATION_FAILED: scanned 0 markdown files under '$RepoRoot' (wrong root? anti-vacuous floor)"
    exit 2
}
Write-Host "check-md-size: PASS - $checked markdown file(s) within budget." -ForegroundColor Green
exit 0
