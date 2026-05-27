# Migrate panel-misses.csv to RFC 4180 quoted format with new instrumentation columns.
#
# Existing format (legacy): 7 fields naively comma-separated. Some rows have
# unquoted commas inside finding_brief, causing Import-Csv to mis-parse.
# This script reconstructs malformed rows by treating the first 3 fields
# (timestamp, catalog_revision, pr_ref) and last 3 fields
# (classification, proposed_catalog_slug, status) as stable comma-free positions;
# everything between them is the finding_brief content.
#
# New schema (10 fields):
#   1. timestamp
#   2. catalog_revision
#   3. pr_ref
#   4. finding_brief            (RFC 4180 quoted when needed)
#   5. classification
#   6. proposed_catalog_slug
#   7. status
#   8. prior_acks_present       (NEW; default empty)
#   9. rule_in_base_instructions (NEW; default empty)
#  10. divergence_override_history (NEW; default empty)
#
# Idempotent: if the existing header already has the new columns, no-op exit 0.
# Atomic: writes to a temp file then renames over the source.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "panel-misses.csv not found at $Path" }

$lines = Get-Content -LiteralPath $Path -Encoding UTF8

if ($lines.Count -lt 1) { throw "panel-misses.csv is empty" }

$expectedLegacyHeader = 'timestamp,catalog_revision,pr_ref,finding_brief,classification,proposed_catalog_slug,status'
$expectedNewHeader = "$expectedLegacyHeader,prior_acks_present,rule_in_base_instructions,divergence_override_history"

if ($lines[0] -eq $expectedNewHeader) {
    Write-Host "panel-misses.csv already migrated; no-op."
    return
}

if ($lines[0] -ne $expectedLegacyHeader) {
    throw "Unexpected header. Expected legacy=`"$expectedLegacyHeader`" got=`"$($lines[0])`""
}

# Reassemble multi-line rows: data rows start with an ISO8601 UTC timestamp prefix.
# Any line not starting with that pattern is a continuation of the previous row.
$timestampPrefix = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z,'
$logicalRows = @()
$current = $null

for ($i = 1; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    if ($line -match $timestampPrefix) {
        if ($null -ne $current) { $logicalRows += $current }
        $current = $line
    }
    else {
        if ($null -eq $current) { throw "Continuation line at index $i has no preceding data row" }
        $current = "$current $line"
    }
}

if ($null -ne $current) { $logicalRows += $current }

$migratedRows = @()
$migratedRows += [pscustomobject]@{
    timestamp = 'timestamp'
    catalog_revision = 'catalog_revision'
    pr_ref = 'pr_ref'
    finding_brief = 'finding_brief'
    classification = 'classification'
    proposed_catalog_slug = 'proposed_catalog_slug'
    status = 'status'
    prior_acks_present = 'prior_acks_present'
    rule_in_base_instructions = 'rule_in_base_instructions'
    divergence_override_history = 'divergence_override_history'
}

$reconstructedRowCount = 0
$wellFormedRowCount = 0

foreach ($line in $logicalRows) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $fields = $line -split ','
    $count = $fields.Count

    if ($count -eq 7) {
        $row = [pscustomobject]@{
            timestamp = $fields[0]
            catalog_revision = $fields[1]
            pr_ref = $fields[2]
            finding_brief = $fields[3]
            classification = $fields[4]
            proposed_catalog_slug = $fields[5]
            status = $fields[6]
            prior_acks_present = ''
            rule_in_base_instructions = ''
            divergence_override_history = ''
        }
        $wellFormedRowCount++
    }
    elseif ($count -gt 7) {
        # Over-split: finding_brief (position 4 in 1-indexed) contained unquoted commas.
        # First 3 fields and last 3 fields are stable; middle (count - 6) fields recompose into finding_brief.
        $timestamp = $fields[0]
        $catalogRevision = $fields[1]
        $prRef = $fields[2]
        $status = $fields[$count - 1]
        $proposedSlug = $fields[$count - 2]
        $classification = $fields[$count - 3]
        $findingBriefFields = $fields[3..($count - 4)]
        $findingBrief = $findingBriefFields -join ','

        $row = [pscustomobject]@{
            timestamp = $timestamp
            catalog_revision = $catalogRevision
            pr_ref = $prRef
            finding_brief = $findingBrief
            classification = $classification
            proposed_catalog_slug = $proposedSlug
            status = $status
            prior_acks_present = ''
            rule_in_base_instructions = ''
            divergence_override_history = ''
        }
        $reconstructedRowCount++
    }
    else {
        throw "Row has only $count fields (need >=7): $line"
    }

    $migratedRows += $row
}

Write-Host "Well-formed rows: $wellFormedRowCount"
Write-Host "Reconstructed rows: $reconstructedRowCount"
Write-Host "Total data rows: $($wellFormedRowCount + $reconstructedRowCount)"

# Atomic write: temp file then rename
$tempPath = "$Path.tmp"
$migratedRows | Select-Object -Skip 1 | Export-Csv -Path $tempPath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded

if (-not (Test-Path -LiteralPath $tempPath)) { throw "Migration failed: temp file not created" }

# Sanity check: re-read with Import-Csv to verify column-count consistency
$verifyRows = Import-Csv -LiteralPath $tempPath -Encoding UTF8
$expectedRowCount = $wellFormedRowCount + $reconstructedRowCount
if ($verifyRows.Count -ne $expectedRowCount) {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    throw "Verify failed: expected $expectedRowCount rows, Import-Csv read $($verifyRows.Count)"
}

# Atomic rename
Move-Item -LiteralPath $tempPath -Destination $Path -Force

Write-Host "Migration successful: $Path"
