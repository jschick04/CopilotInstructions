# Generate pattern-catalog.md from sources.
#
# Phase P2 identity-preserving pipeline: reads source files from
# .github/pr-quality-gate/pattern-catalog.sources/ and emits the canonical
# flat .github/pr-quality-gate/pattern-catalog.md.
#
# For now (pre-split), the single source is 00-catalog.md which contains
# the full catalog verbatim. The generator concatenates all source files
# in sorted order. The committed flat catalog MUST remain byte-identical.
#
# Usage:
#   ./scripts/generate-pattern-catalog.ps1              # regenerate in place
#   ./scripts/generate-pattern-catalog.ps1 -Verify      # verify committed == generated
#   ./scripts/generate-pattern-catalog.ps1 -OutputPath X  # emit to custom path

[CmdletBinding()]
param(
    [string] $SourceDir = (Join-Path $PSScriptRoot '..\.github\pr-quality-gate\pattern-catalog.sources'),
    [string] $OutputPath = (Join-Path $PSScriptRoot '..\.github\pr-quality-gate\pattern-catalog.md'),
    [switch] $Verify
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -PathType Container -LiteralPath $SourceDir)) {
    throw "Source directory not found: $SourceDir"
}

# Gather source files in sorted order
$sourceFiles = Get-ChildItem -LiteralPath $SourceDir -Filter '*.md' | Sort-Object Name

if ($sourceFiles.Count -eq 0) {
    throw "No .md source files found in $SourceDir"
}

# Concatenate sources (identity pipeline: single file -> byte-identical output)
$generated = ''
foreach ($f in $sourceFiles) {
    $content = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    $generated += $content
}

if ($Verify) {
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        Write-Error "pattern-catalog.md not found at $OutputPath. Run generate-pattern-catalog.ps1 (no flags) to create."
        exit 1
    }
    $existing = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
    # Normalize line endings for comparison
    $existingNorm = $existing -replace "`r`n", "`n"
    $generatedNorm = $generated -replace "`r`n", "`n"
    if ($existingNorm -ne $generatedNorm) {
        Write-Error "pattern-catalog.md is OUT OF SYNC with sources in pattern-catalog.sources/. Run scripts/generate-pattern-catalog.ps1 to regenerate."
        exit 1
    }
    Write-Host "OK: pattern-catalog.md matches generated output from sources."
    exit 0
}

# Write generated output
Set-Content -LiteralPath $OutputPath -Value $generated -Encoding UTF8 -NoNewline
Write-Host "Generated pattern-catalog.md from $($sourceFiles.Count) source file(s)."
