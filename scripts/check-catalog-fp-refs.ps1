[CmdletBinding()]
param(
    [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('.github/pr-quality-gate/pattern-catalog.sources') -RequireGitWorkTree
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

$script:ExitInvocation = 2
$script:ExitViolation = 1
$script:ExitOk = 0

function Write-Invocation { param([string] $Msg) Write-Host "::error::INVOCATION_FAILED:$Msg" }
function Write-Violation { param([string] $Msg) Write-Host "::error::VIOLATION:$Msg" }


$sourcesDir = Join-Path $RepoRoot '.github/pr-quality-gate/pattern-catalog.sources'
if (-not (Test-Path -LiteralPath $sourcesDir)) {
    Write-Invocation "catalog sources folder not found: $sourcesDir"
    exit $script:ExitInvocation
}

$sourceFiles = @(Get-ChildItem -Path $sourcesDir -Filter '*.md' -File)
if ($sourceFiles.Count -eq 0) {
    Write-Invocation "no catalog source files found in $sourcesDir; cannot validate fp references. Failing closed."
    exit $script:ExitInvocation
}

# Params cell opens with '{' (header and separator rows lack it): anchors to real rule rows, excludes the header.
$ruleRowPattern = '^\|\s*([a-z][a-z0-9.-]+)\s*\|\s*[^|]+\|\s*\{'

$ruleRowCount = 0
$violations = @()
$referencedFp = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$sectionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$sectionLoc = @{}
$fpRefs = @()
foreach ($file in $sourceFiles) {
    $relPath = ($file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/')
    $lineNo = 0
    $inFence = $false
    $fenceOpenLine = 0
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        $lineNo++
        # A fenced code block (FP sections may contain one) can hold heading- or table-shaped lines; do not scan inside it.
        if ($line -match '^\s*```') {
            if (-not $inFence) { $fenceOpenLine = $lineNo }
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }
        $sectionMatch = [regex]::Match($line, '^##\s+(FP-\S+?):')
        if ($sectionMatch.Success) {
            $id = $sectionMatch.Groups[1].Value.ToUpperInvariant()
            [void]$sectionIds.Add($id)
            if (-not $sectionLoc.ContainsKey($id)) { $sectionLoc[$id] = "${relPath}:${lineNo}" }
            continue
        }
        if ($line -notmatch $ruleRowPattern) { continue }
        $ruleRowCount++
        $slug = $matches[1]
        # Well-formed rows have 5 (legacy, no tier) or 6 cells; any other count means an unescaped '|' that would shift fp_slug out of cell 5.
        $rowBody = $line.Trim()
        if ($rowBody.StartsWith('|')) { $rowBody = $rowBody.Substring(1) }
        if ($rowBody.EndsWith('|')) { $rowBody = $rowBody.Substring(0, $rowBody.Length - 1) }
        $inner = @($rowBody -split '(?<!\\)\|' | ForEach-Object { $_.Trim() })
        if ($inner.Count -lt 5 -or $inner.Count -gt 6) {
            $violations += "${relPath}:${lineNo}: rule '$slug' has $($inner.Count) cells (expected 5 or 6); an unescaped or missing '|' corrupts fp_slug parsing - escape inner pipes as '\|' and keep the row delimiters"
            continue
        }
        # A 6-cell row ends in the tier; a non-empty non-tier token there (an empty cell is the legacy form) means a 5-cell row gained a stray pipe, shifting fp_slug off cell 5.
        if ($inner.Count -eq 6 -and $inner[5] -and $inner[5] -notin @('HIGH', 'MEDIUM', 'LOW')) {
            $violations += "${relPath}:${lineNo}: rule '$slug' has 6 cells but the tier cell is '$($inner[5])' (expected HIGH/MEDIUM/LOW or empty); an unescaped '|' likely shifted fp_slug - escape inner pipes as '\|'"
            continue
        }
        $fp = $inner[4]
        if (-not $fp) { continue }
        $token = $fp.ToUpperInvariant()
        [void]$referencedFp.Add($token)
        # fp_slug is canonically fp-<N> (numeric); a non-canonical token would otherwise resolve against an equally mistyped heading.
        if ($fp -notmatch '^fp-[0-9]+$') {
            $violations += "${relPath}:${lineNo}: rule '$slug' has a non-canonical fp_slug '$fp' (expected fp-<N>, e.g. fp-1)"
            continue
        }
        $fpRefs += [PSCustomObject]@{ Slug = $slug; Token = $token; Raw = $fp; Loc = "${relPath}:${lineNo}" }
    }
    if ($inFence) {
        $violations += "${relPath}:${fenceOpenLine}: unclosed code fence; the rest of the file was not scanned for fp references - close the ``` fence"
    }
}

if ($ruleRowCount -eq 0) {
    Write-Invocation "no catalog rule rows parsed from the sources; cannot validate fp references. Failing closed."
    exit $script:ExitInvocation
}

foreach ($ref in $fpRefs) {
    if (-not $sectionIds.Contains($ref.Token)) {
        $violations += "$($ref.Loc): rule '$($ref.Slug)' references fp_slug '$($ref.Raw)' but no '## $($ref.Token):' section exists"
    }
}
foreach ($id in $sectionIds) {
    if (-not $referencedFp.Contains($id)) {
        $violations += "$($sectionLoc[$id]): FP section '$id' is not referenced by any rule's fp_slug (orphan section)"
    }
}

if ($violations) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "All catalog fp_slug references resolve. ($($fpRefs.Count) reference(s) <-> $($sectionIds.Count) FP section(s) across $($sourceFiles.Count) source file(s).)"
exit $script:ExitOk
