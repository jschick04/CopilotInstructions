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
    Write-Invocation "no catalog source files found in $sourcesDir; cannot validate cede references. Failing closed."
    exit $script:ExitInvocation
}

# Params cell opens with '{' (header and separator rows lack it): anchors to real rule rows, excludes the header.
$ruleRowPattern = '^\|\s*([a-z][a-z0-9.-]+)\s*\|\s*[^|]+\|\s*\{'

$slugSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($file in $sourceFiles) {
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        if ($line -match $ruleRowPattern) { [void]$slugSet.Add($matches[1]) }
    }
}
if ($slugSet.Count -eq 0) {
    Write-Invocation "no catalog slugs parsed from the sources; cannot validate cede references. Failing closed."
    exit $script:ExitInvocation
}

# Bound the cede clause at '**Audit method' or the next unescaped cell pipe so later row cells are not scanned.
$violations = @()
foreach ($file in $sourceFiles) {
    $relPath = ($file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/')
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        $lineNo++
        $cedeIdx = $line.IndexOf('Cede to the owning rule', [System.StringComparison]::OrdinalIgnoreCase)
        if ($cedeIdx -lt 0) { continue }
        $cedeText = $line.Substring($cedeIdx)
        $boundIdx = $cedeText.IndexOf('**Audit method', [System.StringComparison]::OrdinalIgnoreCase)
        $cellPipe = [regex]::Match($cedeText, '(?<!\\)\|')
        if ($cellPipe.Success -and ($boundIdx -lt 0 -or $cellPipe.Index -lt $boundIdx)) { $boundIdx = $cellPipe.Index }
        if ($boundIdx -ge 0) { $cedeText = $cedeText.Substring(0, $boundIdx) }
        $citingSlug = if ($line -match $ruleRowPattern) { $matches[1] } else { '<unknown>' }
        foreach ($match in [regex]::Matches($cedeText, '`([a-z][a-z0-9.-]+)`\s+owns')) {
            $target = $match.Groups[1].Value
            if (-not $slugSet.Contains($target)) {
                $violations += "${relPath}:${lineNo}: rule '$citingSlug' cedes to '$target', which is not a catalog slug"
            }
        }
    }
}

if ($violations) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "All catalog cede references resolve. ($($slugSet.Count) slugs scanned across $($sourceFiles.Count) source file(s).)"
exit $script:ExitOk
