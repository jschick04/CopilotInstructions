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
Import-Module (Join-Path $PSScriptRoot 'lib/panel-ledger-helpers.psm1') -Force
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

$validEffort = @('minimal', 'low', 'medium', 'high', 'xhigh', 'not-supported')
$validContext = @('default', 'long_context')
$validConsumerTags = @('default slate', 'triage', 'no default slate consumer')
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
    'triage'             = @('AGENTS.md', '.github/pr-quality-gate/panel-policy.md', '.github/pr-quality-gate/invoke-panel.ps1')
    }
$presenceScope = @('.github/playbooks', '.github/pr-quality-gate', 'AGENTS.md')

function Test-DelimiterRow {
    param([string] $Bare)
    # Class-legal but renders no table: '::---', '-:-', '--- || ---'. Renders one with no pipe at all: ':---'.
    # This class is a superset of the cell production below, so it is an early exit, not a gate.
    if ($Bare -notmatch '^[ \t\v\f:|-]+$') { return $false }
    $hasPipe = $Bare.Contains('|')
    $cells = @($Bare -split '\|')
    # Redundant with the dash-run test below; kept so the no-pipe case reads as its own path.
    if ($hasPipe) {
        # Outer pipes are not symmetric in GFM: '<VT>| --- |' renders no table at any header width, but
        # '| --- |<VT>' does, so only the trailing drop may treat VT / FF as droppable whitespace.
        if ($cells.Count -ge 1 -and $cells[0] -match '^[ \t]*$') { $cells = @($cells | Select-Object -Skip 1) }
        if ($cells.Count -ge 1 -and $cells[$cells.Count - 1].Trim() -eq '') { $cells = @($cells | Select-Object -SkipLast 1) }
    }
    # A lone '|' loses both of its cells to the outer-pipe drops, and a row with no cells is not a table.
    if ($cells.Count -eq 0) { return $false }
    foreach ($cell in $cells) {
        # '| - - - |' renders no table: GFM allows whitespace only around cell content, not inside the run.
        if ($cell -notmatch '^[ \t\v\f]*:?-+:?[ \t\v\f]*$') { return $false }
    }
    # A pipe-less dash run is a setext underline unless a colon or VT / FF breaks that reading: '<VT>---'
    # renders a table where '---' and a tab-padded '---' do not.
    if (-not $hasPipe -and $Bare -notmatch ':' -and $Bare -notmatch '[\v\f]') { return $false }
    return $true
}

function Get-SentinelRows {
    param([string[]] $Lines, [string] $Name, [string] $Header)
    # Markdown gives no decidable way to locate a table inside a document: every container class closed here
    # (fences, indented blocks, HTML comments, raw HTML, list items, setext) produced another one. Exact
    # sentinel lines sidestep the question - the checker never has to know what a section or container is.
    $begin = '<!-- registry:' + $Name + ':begin -->'
    $end = '<!-- registry:' + $Name + ':end -->'
    $beginAt = @()
    $endAt = @()
    $headerAt = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].TrimEnd() -ceq $begin) { $beginAt += $i }
        if ($Lines[$i].TrimEnd() -ceq $end) { $endAt += $i }
        if ($Lines[$i].TrimEnd() -ceq $Header) { $headerAt += $i }
    }
    if ($beginAt.Count -ne 1 -or $endAt.Count -ne 1) {
        return [PSCustomObject]@{ Error = "expected exactly one '$begin' and one '$end' in the registry (found $($beginAt.Count) and $($endAt.Count))"; Rows = @(); BeginAt = -1; EndAt = -1 }
    }
    if ($endAt[0] -le $beginAt[0]) {
        return [PSCustomObject]@{ Error = "'$end' must come after '$begin'"; Rows = @(); BeginAt = -1; EndAt = -1 }
    }
    # Locating a span decidably is not enough: a second copy of the table outside the sentinels renders as
    # authoritative to every reader while going unvalidated, and a sentinel PAIR moved inside a fence or a
    # comment substitutes the validated rows for a different rendered table. Both copies carry this header,
    # so requiring it exactly once, immediately after the begin sentinel, ties the validated span to the
    # rendered one without the checker knowing what a fence or a comment is.
    if ($headerAt.Count -ne 1) {
        return [PSCustomObject]@{ Error = "'$Header' must appear exactly once in the registry (found $($headerAt.Count)); a second copy of the table is not validated but still renders as authoritative"; Rows = @(); BeginAt = -1; EndAt = -1 }
    }
    if ($headerAt[0] -ne $beginAt[0] + 1) {
        return [PSCustomObject]@{ Error = "the line after '$begin' must be the table header '$Header'"; Rows = @(); BeginAt = -1; EndAt = -1 }
    }
    $rows = @()
    for ($i = $beginAt[0] + 1; $i -lt $endAt[0]; $i++) {
        $line = $Lines[$i]
        # A blank line ENDS a table in GFM, so rows after it render as paragraph text. Skipping blanks would
        # let the checker validate rows no reader sees, and make the sentinel span wider than the real table.
        if ($line.Trim() -eq '') {
            return [PSCustomObject]@{ Error = "line $($i + 1) between the $Name sentinels is blank; a blank line ends the table in GFM, so every line between the sentinels must be a row"; Rows = @(); BeginAt = -1; EndAt = -1 }
        }
        if ($line.TrimEnd() -notmatch '^\|.*\|$') {
            return [PSCustomObject]@{ Error = "line $($i + 1) between the $Name sentinels is not a table row: $($line.Trim())"; Rows = @(); BeginAt = -1; EndAt = -1 }
        }
        $rows += $line
    }
    return [PSCustomObject]@{ Error = ''; Rows = $rows; BeginAt = $beginAt[0]; EndAt = $endAt[0] }
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

$tierBlock = Get-SentinelRows -Lines $lines -Name 'tiers' -Header $tierHeader
if ($tierBlock.Error -ne '') {
    Write-Violation "$RegistryPath capability-tiers table: $($tierBlock.Error)"
    exit $script:ExitViolation
}
$mapBlock = Get-SentinelRows -Lines $lines -Name 'mapping' -Header $mapHeader
if ($mapBlock.Error -ne '') {
    Write-Violation "$RegistryPath current-mapping table: $($mapBlock.Error)"
    exit $script:ExitViolation
}
# Header uniqueness only catches a byte-identical copy; a ghost table with renamed, re-cased, re-padded or
# pipe-less headers renders identically to a reader and evades it. Every GFM table needs a delimiter row, so
# banning delimiter rows outside the sentinel spans closes the markdown substitution class by construction
# instead of one text shape at a time - no notion of fences, comments or sections required. Two caveats the
# rule cannot infer: a blockquote prefix puts a '>' on the delimiter line, so it is stripped before the test;
# and an HTML table renders with no delimiter row at all, so HTML table markup is rejected separately.
$spanLines = @{}
foreach ($span in @($tierBlock, $mapBlock)) {
    for ($i = $span.BeginAt; $i -le $span.EndAt; $i++) { $spanLines[$i] = $true }
}
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    # Scope differs between the two tests on purpose. HTML table markup is never legitimate ANYWHERE in this
    # file, spans included: Notes and Description are free text no grammar validates, and inline HTML in a
    # cell renders a nested table every reader sees while the row around it validates clean.
    # The tag name must be followed by a real tag-name terminator, not just any word boundary: '@' is a word
    # boundary, so '\b' rejected the email autolink <table@example.com>, which renders a mailto link and no
    # table. End-of-line is a terminator too - '<table' alone on a line, with content after a blank line,
    # renders a real table element and is the only table markup in that file.
    if ($line -match '<\s*/?\s*(table|thead|tbody|tr|td|th)(?=[ \t\v\f/>]|$)') {
        Write-Violation "$RegistryPath line $($i + 1) contains raw HTML table markup ($($line.Trim())); an HTML table renders without a delimiter row, so it would publish unvalidated rows - inside a cell it renders nested in the validated table"
        exit $script:ExitViolation
    }
    # The delimiter test, by contrast, MUST skip the spans: the two real delimiter rows live there. The strip
    # handles space/tab only - GitHub does not accept vertical tab or form feed as blockquote-prefix
    # whitespace, so a VT before the marker renders a paragraph, not a blockquoted table (measured). VT and FF
    # ARE in the class below, where GitHub does accept them inside the row itself.
    if ($spanLines.ContainsKey($i)) { continue }
    $bare = $line -replace '^[ \t]*(>[ \t]*)+', ''
    if (Test-DelimiterRow $bare) {
        Write-Violation "$RegistryPath line $($i + 1) is a table delimiter row outside the sentinel spans ($($line.Trim())); a second table would render as authoritative without being validated, so this file may hold only the two sentinel-delimited tables"
        exit $script:ExitViolation
    }
}
$tierRows = $tierBlock.Rows
$mapRows = $mapBlock.Rows
if ($tierRows.Count -lt 3) {
    Write-Violation "capability-tiers table between its sentinels is missing or empty in $RegistryPath"
    exit $script:ExitViolation
}
if ($mapRows.Count -lt 3) {
    Write-Violation "current-mapping table between its sentinels is missing or empty in $RegistryPath"
    exit $script:ExitViolation
}

# The divider must be validated, not assumed: 'Skip 2' on a divider-less table silently drops the first data
# row, and a matching omission in both tables would keep tier-id parity while that tier escapes every check.
function Test-Divider {
    param([string] $Row, [int] $ExpectedCells)
    $cells = @(Get-Cells -Row $Row)
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
    $cells = @(Get-Cells -Row $row)
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
$modelAssignments = @{}
& git --no-optional-locks -C $RepoRoot ls-files --stage 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'Failing closed: cannot read governing index'; exit $script:ExitInvocation }
$heavyPolicy = Get-HeavyModelPolicy -RepoRoot $RepoRoot -StagedMode -MembershipOnly
if ($heavyPolicy.Errors.Count -gt 0) { foreach ($errorText in $heavyPolicy.Errors) { $violations += $errorText } }
$heavyModels = $heavyPolicy.Models

foreach ($row in ($mapRows | Select-Object -Skip 2)) {
    $cells = @(Get-Cells -Row $row)
    if ($null -eq $cells -or $cells.Count -ne 6) { $violations += "current-mapping row must have exactly 6 cells: $($row.Trim())"; continue }
    $id = Get-TierId -Cell $cells[0]
    if (-not $id) { $violations += "current-mapping tier id must be backticked: $($row.Trim())"; continue }
    if ($id -cnotmatch $tierIdPattern) { $violations += "tier id '$id' violates the id grammar $tierIdPattern"; continue }
    if ($mapIds -ccontains $id) { $violations += "duplicate tier id '$id' in the current-mapping table"; continue }
    $mapIds += $id

    # Padding is never a model distinction: CommonMark renders ` x ` identically to `x`, and one-sided
    # padding leaves a stray space no runtime resolves to a different model. Not inside Get-TierId - a
    # padded tier id must stay a loud grammar violation rather than be normalised away.
    $model = Get-TierId -Cell $cells[1]
    if ($model) { $model = $model.Trim() }
    if (-not $model) { $violations += "tier '$id' model must be backticked and non-empty"; continue }
    $effort = $cells[2]
    $context = $cells[3]
    $consumers = $cells[4]
    if ($validEffort -cnotcontains $effort) { $violations += "tier '$id' effort '$effort' is not one of: $($validEffort -join ', ')" }
    if ($validContext -cnotcontains $context) { $violations += "tier '$id' context_tier '$context' is not one of: $($validContext -join ', ')" }
    if ([string]::IsNullOrWhiteSpace($consumers)) { $violations += "tier '$id' has an empty consumers cell"; continue }

    $tags = @($consumers -split ',' | ForEach-Object { $_.Trim() })
    foreach ($tag in $tags) {
        # Case-sensitive on purpose, and it is the only line enforcing canonical tag text: the $tagScopes
        # lookup below is a hashtable, so its keys match case-INsensitively and 'Default Slate' would
        # otherwise be silently normalised at exit 0. It is also what makes the two -ccontains comparisons
        # on 'no default slate consumer' unreachable for a case variant.
        if ($validConsumerTags -cnotcontains $tag) { $violations += "tier '$id' consumers tag '$tag' is not one of: $($validConsumerTags -join ', ')" }
    }
    if ($tags -ccontains 'no default slate consumer' -and $tags.Count -ne 1) {
        $violations += "tier '$id' cannot combine 'no default slate consumer' with another tag"
    }
    $rowsForConsumers += [PSCustomObject]@{ Id = $id; Model = $model; Tags = $tags }
    if ($id -match '^(heavy|light)-(claude|gpt|gemini|grok)\b') {
        $tierClass = $matches[1]
        $expectedVendor = $matches[2]
        if ($modelAssignments.ContainsKey($model) -and $modelAssignments[$model] -ne "$tierClass|$expectedVendor") { $violations += "model '$model' appears in multiple tier classes or families" } else { $modelAssignments[$model] = "$tierClass|$expectedVendor" }
        if ($model -notmatch ('^' + [regex]::Escape($expectedVendor) + '-')) { $violations += "tier '$id' family '$expectedVendor' does not match model vendor '$model'" }
    }
    if ($id -match '^heavy-') {
        if ($heavyModels -cnotcontains $model) { $violations += "heavy tier '$id' model '$model' is absent from the heavy-model allowlist" }
    }

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
    $gitArgs = @('-c', 'core.quotePath=false', 'grep', '-lP', $pattern, '--') + $Scope + $sharedExclusions
    $hits = & git -C $RepoRoot @gitArgs 2>$null
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
