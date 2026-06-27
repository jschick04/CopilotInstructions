#Requires -Version 5.1
# Drift guard: the panel-misses `classification` enum must stay in sync across its mirrors.
# scripts/Add-PanelMissesRow.ps1 constrains -Classification with a hardcoded [ValidateSet] that manually
# mirrors the canonical enum in data/README.md (the SoT) and is re-listed in panel-policy.md. It drifted once
# (PR #39: a stale 3-of-7 ValidateSet rejected a value 30 committed rows already used). This test CI-VALIDATES
# the mirrors (helper ValidateSet == README enum; panel-policy Classify tokens == README enum) + that committed
# data is a subset of the enum; it does NOT enforce the enum at write time (the migrate script / manual /
# string-concat appends bypass the ValidateSet and are caught only post-hoc here).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-common.ps1')
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/repo-root.psm1') -Force

$script:Pass = 0
$script:Fail = 0

$repoRoot   = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('.github/pr-quality-gate')
$helperPath = Join-Path $repoRoot 'scripts/Add-PanelMissesRow.ps1'
$readmePath = Join-Path $repoRoot '.github/pr-quality-gate/data/README.md'
$policyPath = Join-Path $repoRoot '.github/pr-quality-gate/panel-policy.md'
$csvPath    = Join-Path $repoRoot '.github/pr-quality-gate/data/panel-misses.csv'

function Get-ValidateSetTokens {
    # Read only the top-level param() block (not a whole-tree FindAll) so a nested function with its own
    # Classification param cannot union extra tokens and mask drift; match the exact attribute leaf name so an
    # unrelated attribute whose name merely starts with ValidateSet is not treated as a ValidateSet.
    param([Parameter(Mandatory)] [string] $Text, [Parameter(Mandatory)] [string] $ParameterName)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    $result = New-Object System.Collections.Generic.List[string]
    if ($null -eq $ast.ParamBlock) { return $result.ToArray() }
    foreach ($param in $ast.ParamBlock.Parameters) {
        if ($param.Name.VariablePath.UserPath -ne $ParameterName) { continue }
        foreach ($attribute in $param.Attributes) {
            if ($attribute -is [System.Management.Automation.Language.AttributeAst] -and
                (($attribute.TypeName.FullName -split '\.')[-1] -in @('ValidateSet', 'ValidateSetAttribute'))) {
                foreach ($argument in $attribute.PositionalArguments) {
                    if ($argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        [void]$result.Add($argument.Value)
                    }
                }
            }
        }
    }
    return $result.ToArray()
}

function Get-ReadmeEnumTokens {
    # Section-anchor to "## panel-misses.csv" so the findings.csv `classification` enum row ABOVE it is skipped.
    param([Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Lines)
    $inSection = $false
    foreach ($line in $Lines) {
        if ($line -match '^##\s+panel-misses\.csv\s*$') { $inSection = $true; continue }
        if ($inSection -and $line -match '^##\s+' -and $line -notmatch '^##\s+panel-misses\.csv\s*$') { break }
        if ($inSection -and $line -match '^\|\s*`classification`' -and $line -match 'enum\s+`([^`]+)`') {
            return @(($matches[1] -replace '\\', '') -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }
    return @()
}

function Get-PolicyClassifySection {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Lines)
    $start = -1; $end = $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($start -lt 0 -and $Lines[$i] -match '^\s*1\.\s+\*\*Classify\*\*') { $start = $i; continue }
        if ($start -ge 0 -and $Lines[$i] -match '^\s*2\.\s+\*\*Apply') { $end = $i; break }
    }
    if ($start -lt 0) { return @() }
    return @($Lines[$start..($end - 1)])
}

function Get-PolicyTriageTokens {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Lines)
    $section = Get-PolicyClassifySection -Lines $Lines
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $section) {
        if ($line -match '^\s*-\s*`([a-z][a-z-]+)`\s*:') { [void]$result.Add($matches[1]) }
    }
    return $result.ToArray()
}

function Get-PolicyNonTriageTokens {
    # Non-triage tokens come from the intro prose before the first bullet; the shape filter ^[a-z][a-z-]+$
    # excludes the file-path backtick tokens on that line (data/panel-misses.csv, data/README.md).
    param([Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Lines)
    $section = Get-PolicyClassifySection -Lines $Lines
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $section) {
        if ($line -match '^\s*-\s') { break }
        foreach ($match in [regex]::Matches($line, '`([^`]+)`')) {
            $token = $match.Groups[1].Value
            if ($token -match '^[a-z][a-z-]+$') { [void]$result.Add($token) }
        }
    }
    return @($result | Select-Object -Unique)
}

function Test-SetEquals {
    param([string[]] $First, [string[]] $Second)
    $set = [System.Collections.Generic.HashSet[string]]::new([string[]]$First)
    return $set.SetEquals([string[]]$Second)
}

function Test-IsSubset {
    param([string[]] $Subset, [string[]] $Superset)
    $sub = [System.Collections.Generic.HashSet[string]]::new([string[]]$Subset)
    $super = [System.Collections.Generic.HashSet[string]]::new([string[]]$Superset)
    return $sub.IsSubsetOf($super)
}

$helperText  = Get-Content -Raw -LiteralPath $helperPath
$readmeLines = @(Get-Content -LiteralPath $readmePath)
$policyLines = @(Get-Content -LiteralPath $policyPath)

$helperSet      = @(Get-ValidateSetTokens -Text $helperText -ParameterName 'Classification')
$readmeSet      = @(Get-ReadmeEnumTokens -Lines $readmeLines)
$policyTriage   = @(Get-PolicyTriageTokens -Lines $policyLines)
$policyNonTriage = @(Get-PolicyNonTriageTokens -Lines $policyLines)
$csvSet         = @((Import-Csv -LiteralPath $csvPath).classification | Sort-Object -Unique)

Write-Host "panel-misses-classification-sync:"

# Anti-vacuous floors: a 0/garbled parse must fail here, not pass silently.
Assert-True ($helperSet.Count -gt 0) 'helper ValidateSet parsed non-empty'
Assert-True ($readmeSet.Count -gt 0) 'README enum parsed non-empty'
Assert-True ($readmeSet -contains 'panel-execution-failure') 'README enum contains positive anchor panel-execution-failure (proves the panel-misses-section row was grabbed, not findings.csv)'
Assert-True ($policyTriage.Count -gt 0) 'panel-policy triage tokens parsed non-empty'
Assert-True ($policyTriage -contains 'panel-miss') 'panel-policy triage sentinel present (panel-miss)'
Assert-True ($policyNonTriage.Count -gt 0) 'panel-policy non-triage tokens parsed non-empty'
Assert-True ($policyNonTriage -contains 'process-violation') 'panel-policy non-triage sentinel present (process-violation)'
Assert-True ($csvSet.Count -gt 0) 'committed CSV classifications non-empty'

Assert-True (Test-SetEquals $helperSet $readmeSet) 'helper ValidateSet == README enum (bidirectional set-equality)'

Assert-True (Test-SetEquals (@($policyTriage) + @($policyNonTriage)) $readmeSet) 'panel-policy Classify tokens (triage bullets + non-triage prose) == README enum'

Assert-True (Test-IsSubset $csvSet $helperSet) 'committed CSV classifications subset-of helper ValidateSet (PR #39 regression pin)'

# Negative probes: prove each parser and comparison bites, using inline fixtures.
$fixtureParam = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('alpha','beta','gamma')] [string] $Classification,
    [string] $Other
)
'@
Assert-True (Test-SetEquals (Get-ValidateSetTokens -Text $fixtureParam -ParameterName 'Classification') @('alpha', 'beta', 'gamma')) 'AST extractor returns exactly the fixture ValidateSet'

$fixtureNestedParam = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('top1','top2')] [string] $Classification
)
function Invoke-Inner {
    param([ValidateSet('nested-only')] [string] $Classification)
}
'@
Assert-True (Test-SetEquals (Get-ValidateSetTokens -Text $fixtureNestedParam -ParameterName 'Classification') @('top1', 'top2')) 'AST extractor reads ONLY the top-level param block, not a nested function param (no drift masking)'

$fixtureWrongAttr = @'
[CmdletBinding()]
param(
    [ValidateSetExtra('rogue')] [string] $Classification
)
'@
Assert-True (@(Get-ValidateSetTokens -Text $fixtureWrongAttr -ParameterName 'Classification').Count -eq 0) 'AST extractor ignores a non-ValidateSet attribute whose name merely starts with ValidateSet'

$fixtureTwinReadme = @(
    '## findings.csv',
    '| `classification` | enum `real \| pending` | desc |',
    '',
    '## panel-misses.csv',
    '### Schema',
    '| `classification` | enum `panel-miss \| rejected \| panel-execution-failure` | desc |'
)
Assert-True (Test-SetEquals (Get-ReadmeEnumTokens -Lines $fixtureTwinReadme) @('panel-miss', 'rejected', 'panel-execution-failure')) 'README extractor picks ONLY the panel-misses-section row (twin-row trap)'

$fixturePolicy = @(
    '1. **Classify** the finding (per `data/panel-misses.csv` and `data/README.md`; `process-confirmation`/`process-violation` are non-triage):',
    '   - `panel-miss`: rule absent. Append (`pending`).',
    '   - `false-positive`: spurious. (`catalog-existing`)',
    '2. **Apply** the fix:'
)
Assert-True (Test-SetEquals (Get-PolicyTriageTokens -Lines $fixturePolicy) @('panel-miss', 'false-positive')) 'policy triage extractor returns only bullet-key tokens (not bullet-body status tokens like pending/catalog-existing)'
Assert-True (Test-SetEquals (Get-PolicyNonTriageTokens -Lines $fixturePolicy) @('process-confirmation', 'process-violation')) 'policy non-triage extractor returns only shape-matching prose tokens (not data/ file paths)'

$fixturePolicyUnderExtract = @(
    '1. **Classify** (`process-confirmation`/`process-violation` are non-triage):',
    '   - panel-miss: rule absent (lost its backticks in a reformat - not matched).',
    '   - `false-positive`: spurious.',
    '2. **Apply** the fix:'
)
$underTriage = Get-PolicyTriageTokens -Lines $fixturePolicyUnderExtract
$underNonTriage = Get-PolicyNonTriageTokens -Lines $fixturePolicyUnderExtract
Assert-False (Test-SetEquals (@($underTriage) + @($underNonTriage)) @('panel-miss', 'false-positive', 'process-confirmation', 'process-violation')) 'union set-equality FAILS when a bullet under-extracts (panel-miss lost its backticks)'

Assert-False (Test-SetEquals @('a', 'b') @('a', 'b', 'c')) 'SetEquals returns false on a divergent pair (guard bites)'
Assert-False (Test-IsSubset @('x') @('a', 'b')) 'IsSubset returns false when an element is missing (guard bites)'
Assert-False (Test-IsSubset @('panel-miss', 'rogue') @('panel-miss')) 'IsSubset returns false for an extra out-of-enum token'

Write-Host ""
$summaryColor = if ($script:Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "panel-misses-classification-sync.tests: $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $summaryColor
exit ([int]($script:Fail -gt 0))
