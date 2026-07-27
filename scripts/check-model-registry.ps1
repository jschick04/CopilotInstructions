#Requires -Version 5.1
# Model-registry shape + value gate. Validates .github/playbooks/multi-model-review/current-model-registry.md:
# table shape, the effort / context_tier / consumers value sets, tier-id parity across both tables, the
# (model, effort, context_tier) uniqueness invariant that stops two tiers sharing one model from collapsing
# into a single reviewer configuration, and whether each consumers tag is backed by a reference in that tag's
# own selector surface.
# It CANNOT verify that a capability value is TRUE for a given model - there is no runtime oracle - so effort
# and context_tier accuracy stays a manual step in the registry's Update contract.

[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $RegistryPath = '.github/playbooks/multi-model-review/current-model-registry.md'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

function Write-Invocation { param([string] $Msg) Write-Host "::error::INVOCATION_FAILED:$Msg" }
function Write-Violation { param([string] $Msg) Write-Host "::error::VIOLATION:$Msg" }

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('.github/playbooks') -RequireGitWorkTree
} catch {
    Write-Invocation $_.Exception.Message
    exit $script:ExitInvocation
}

$registryFull = Join-Path $RepoRoot $RegistryPath
if (-not (Test-Path -LiteralPath $registryFull)) {
    Write-Invocation "registry not found: $RegistryPath"
    exit $script:ExitInvocation
}

$validEffort = @('minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'not-supported')
$validContext = @('default', 'long_context')
$validConsumerTags = @('default slate', 'lite slate', 'sub-agent default', 'no default slate consumer')
$tierIdPattern = '^[a-z][a-z0-9-]*$'
$tierHeader = '| Tier id | Description |'
$mapHeader = '| Tier id | Current model | effort | context_tier | consumers | Notes |'

# Shared across EVERY grep pass (presence and per-tag): the registry documents all tiers, so leaving it in
# scope makes every row self-match; the checker and its fixtures embed real tier ids for the same reason;
# and the panel-misses ledger is prose that names tiers in finding briefs.
$sharedExclusions = @(
    ":!$RegistryPath",
    ':!scripts/check-model-registry.ps1',
    ':!scripts/tests/check-model-registry.tests.ps1',
    ':!.github/pr-quality-gate/data'
)
$tagScopes = @{
    'default slate'      = @('.github/playbooks', '.github/pr-quality-gate/panel-policy.md')
    'lite slate'         = @('profiles/lite', '.github/pr-quality-gate/invoke-panel.ps1')
    'sub-agent default'  = @('AGENTS.md')
}
$presenceScope = @('.github/playbooks', '.github/pr-quality-gate', 'profiles', 'AGENTS.md')

function Get-TableRows {
    param([string[]] $Lines, [string] $Heading)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -ceq $Heading) { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $rows = @()
    $started = $false
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*$') { if ($started) { break } else { continue } }
        if ($line -match '^#') { break }
        # A non-pipe line inside a started table is malformed, not a terminator: silently stopping there
        # would drop every row after it from validation.
        if ($line -notmatch '^\|') {
            if ($started) { return @('MALFORMED', $line) }
            continue
        }
        $started = $true
        $rows += $line
    }
    return $rows
}

function Get-Cells {
    param([string] $Row)
    $trimmed = $Row.Trim()
    if (-not $trimmed.StartsWith('|') -or -not $trimmed.EndsWith('|')) { return $null }
    $inner = $trimmed.Substring(1, $trimmed.Length - 2)
    # Escaped pipes are the repo's markdown-table convention (see pattern-catalog); splitting on a bare
    # pipe would misread `a\|b` in a Notes cell as two columns and reject a valid row.
    return @($inner -split '(?<!\\)\|' | ForEach-Object { ($_ -replace '\\\|', '|').Trim() })
}

function Get-TierId {
    param([string] $Cell)
    if ($Cell -match '^`([^`]+)`$') { return $matches[1] }
    return $null
}

$lines = @(Get-Content -LiteralPath $registryFull)
$violations = @()

$tierRows = Get-TableRows -Lines $lines -Heading '## Capability tiers'
$mapRows = Get-TableRows -Lines $lines -Heading '## Current mapping'
foreach ($tableSpec in @(@('Capability tiers', $tierRows), @('Current mapping', $mapRows))) {
    if ($null -ne $tableSpec[1] -and @($tableSpec[1]).Count -ge 1 -and $tableSpec[1][0] -ceq 'MALFORMED') {
        Write-Violation "'## $($tableSpec[0])' table contains a non-table line before it ends: $($tableSpec[1][1].Trim())"
        exit $script:ExitViolation
    }
}
if ($null -eq $tierRows -or $tierRows.Count -lt 3) {
    Write-Violation "'## Capability tiers' table missing or empty in $RegistryPath"
    exit $script:ExitViolation
}
if ($null -eq $mapRows -or $mapRows.Count -lt 3) {
    Write-Violation "'## Current mapping' table missing or empty in $RegistryPath"
    exit $script:ExitViolation
}
if ($tierRows[0].Trim() -cne $tierHeader) { $violations += "capability-tiers header must be exactly '$tierHeader' (got '$($tierRows[0].Trim())')" }
if ($mapRows[0].Trim() -cne $mapHeader) { $violations += "current-mapping header must be exactly '$mapHeader' (got '$($mapRows[0].Trim())')" }

# The divider must be validated, not assumed: 'Skip 2' on a divider-less table silently drops the first data
# row, and a matching omission in both tables would keep tier-id parity while that tier escapes every check.
function Test-Divider {
    param([string] $Row, [int] $ExpectedCells)
    $cells = Get-Cells -Row $Row
    if ($null -eq $cells -or $cells.Count -ne $ExpectedCells) { return $false }
    foreach ($c in $cells) { if ($c -notmatch '^:?-{3,}:?$') { return $false } }
    return $true
}
if (-not (Test-Divider -Row $tierRows[1] -ExpectedCells 2)) { $violations += "capability-tiers table is missing its 2-cell divider row (got '$($tierRows[1].Trim())')" }
if (-not (Test-Divider -Row $mapRows[1] -ExpectedCells 6)) { $violations += "current-mapping table is missing its 6-cell divider row (got '$($mapRows[1].Trim())')" }
if ($violations.Count -gt 0) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

$tierIds = @()
foreach ($row in ($tierRows | Select-Object -Skip 2)) {
    $cells = Get-Cells -Row $row
    if ($null -eq $cells -or $cells.Count -ne 2) { $violations += "capability-tiers row must have exactly 2 cells: $($row.Trim())"; continue }
    $id = Get-TierId -Cell $cells[0]
    if (-not $id) { $violations += "capability-tiers tier id must be backticked: $($row.Trim())"; continue }
    if ($id -cnotmatch $tierIdPattern) { $violations += "tier id '$id' violates the id grammar $tierIdPattern" ; continue }
    if ($tierIds -ccontains $id) { $violations += "duplicate tier id '$id' in the capability-tiers table" ; continue }
    if ([string]::IsNullOrWhiteSpace($cells[1])) { $violations += "tier '$id' has an empty description" }
    $tierIds += $id
}

$mapIds = @()
$modelEffortPairs = @{}
$rowsForConsumers = @()
foreach ($row in ($mapRows | Select-Object -Skip 2)) {
    $cells = Get-Cells -Row $row
    if ($null -eq $cells -or $cells.Count -ne 6) { $violations += "current-mapping row must have exactly 6 cells: $($row.Trim())"; continue }
    $id = Get-TierId -Cell $cells[0]
    if (-not $id) { $violations += "current-mapping tier id must be backticked: $($row.Trim())"; continue }
    if ($id -cnotmatch $tierIdPattern) { $violations += "tier id '$id' violates the id grammar $tierIdPattern"; continue }
    if ($mapIds -ccontains $id) { $violations += "duplicate tier id '$id' in the current-mapping table"; continue }
    $mapIds += $id

    $model = Get-TierId -Cell $cells[1]
    if (-not $model) { $violations += "tier '$id' model must be backticked and non-empty"; continue }
    $effort = $cells[2]
    $context = $cells[3]
    $consumers = $cells[4]
    if ($validEffort -cnotcontains $effort) { $violations += "tier '$id' effort '$effort' is not one of: $($validEffort -join ', ')" }
    if ($validContext -cnotcontains $context) { $violations += "tier '$id' context_tier '$context' is not one of: $($validContext -join ', ')" }
    if ([string]::IsNullOrWhiteSpace($consumers)) { $violations += "tier '$id' has an empty consumers cell"; continue }

    $tags = @($consumers -split ',' | ForEach-Object { $_.Trim() })
    foreach ($tag in $tags) {
        if ($validConsumerTags -cnotcontains $tag) { $violations += "tier '$id' consumers tag '$tag' is not one of: $($validConsumerTags -join ', ')" }
    }
    if ($tags -ccontains 'no default slate consumer' -and $tags.Count -ne 1) {
        $violations += "tier '$id' cannot combine 'no default slate consumer' with another tag"
    }
    $rowsForConsumers += [PSCustomObject]@{ Id = $id; Tags = $tags }

    # The invariant the effort column exists to protect: two tiers on the same model must differ in effort or
    # context tier, or they are the same reviewer configuration wearing two names.
    $configKey = "$model|$effort|$context"
    if ($modelEffortPairs.ContainsKey($configKey)) {
        $violations += "tiers '$($modelEffortPairs[$configKey])' and '$id' share model '$model' at effort '$effort' and context_tier '$context'; they must differ in effort or context_tier or they are the same slot"
    } else {
        $modelEffortPairs[$configKey] = $id
    }
}

foreach ($id in $tierIds) { if ($mapIds -cnotcontains $id) { $violations += "tier '$id' is described but has no current-mapping row" } }
foreach ($id in $mapIds) { if ($tierIds -cnotcontains $id) { $violations += "tier '$id' is mapped but has no capability-tiers description" } }

function Get-RefCount {
    param([string] $Tier, [string[]] $Scope)
    $pattern = '(?<![a-z0-9_-])' + [regex]::Escape($Tier) + '(?![a-z0-9_-])'
    $args = @('-c', 'core.quotePath=false', 'grep', '-lP', $pattern, '--') + $Scope + $sharedExclusions
    $hits = & git -C $RepoRoot @args 2>$null
    if ($LASTEXITCODE -gt 1) {
        Write-Invocation "git grep for tier '$Tier' failed (exit $LASTEXITCODE); cannot validate consumers. Failing closed."
        exit $script:ExitInvocation
    }
    return @($hits | Where-Object { $_ }).Count
}

if ($violations.Count -eq 0) {
    foreach ($entry in $rowsForConsumers) {
        if ($entry.Tags -ccontains 'no default slate consumer') {
            $n = Get-RefCount -Tier $entry.Id -Scope $presenceScope
            if ($n -gt 0) { $violations += "tier '$($entry.Id)' is tagged 'no default slate consumer' but is referenced in $n selector file(s)" }
            continue
        }
        foreach ($tag in $entry.Tags) {
            $scope = $tagScopes[$tag]
            $n = Get-RefCount -Tier $entry.Id -Scope $scope
            if ($n -lt 1) { $violations += "tier '$($entry.Id)' is tagged '$tag' but has no reference in $($scope -join ' / ')" }
        }
    }
}

if ($violations.Count -gt 0) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "check-model-registry: OK - $($mapIds.Count) tiers, shape + value sets + (model, effort, context_tier) uniqueness + consumers tags verified. Capability truth (effort / context_tier per model) is NOT machine-verifiable; re-check it by hand against the runtime catalog."
exit $script:ExitOk
