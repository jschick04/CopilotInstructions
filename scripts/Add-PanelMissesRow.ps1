# Append a row to panel-misses.csv with proper RFC 4180 quoting.
#
# Use this helper instead of string-concatenation appends. RFC 4180 quoting
# protects against unquoted commas, embedded quotes, and embedded newlines
# in any field.
#
# Schema (10 fields):
#   timestamp, catalog_revision, pr_ref, finding_brief, classification,
#   proposed_catalog_slug, status, prior_acks_present, rule_in_base_instructions,
#   divergence_override_history

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $CsvPath,
    [Parameter(Mandatory)] [string] $Timestamp,
    [Parameter(Mandatory)] [string] $CatalogRevision,
    [Parameter(Mandatory)] [string] $PrRef,
    [Parameter(Mandatory)] [string] $FindingBrief,
    [Parameter(Mandatory)] [ValidateSet('panel-miss','process-violation','false-positive')] [string] $Classification,
    [Parameter(Mandatory)] [string] $ProposedCatalogSlug,
    [Parameter(Mandatory)] [string] $Status,
    [string] $PriorAcksPresent = '',
    [string] $RuleInBaseInstructions = '',
    [string] $DivergenceOverrideHistory = ''
)

$ErrorActionPreference = 'Stop'

# panel-misses.csv requires ISO-8601 UTC timestamps (ending in Z); reject a local-offset timestamp so tooling that
# assumes UTC does not break. Fractional seconds are allowed; the canonical generator is
# (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') (seconds precision).
if ($Timestamp -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$') {
    throw "Timestamp must be ISO-8601 UTC ending in Z (e.g. 2026-06-14T04:34:47Z or 2026-06-14T04:34:47.123Z); got '$Timestamp'."
}

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "panel-misses.csv not found at $CsvPath" }

# Append as a PSCustomObject so Export-Csv handles RFC 4180 quoting.
$row = [pscustomobject]@{
    timestamp = $Timestamp
    catalog_revision = $CatalogRevision
    pr_ref = $PrRef
    finding_brief = $FindingBrief
    classification = $Classification
    proposed_catalog_slug = $ProposedCatalogSlug
    status = $Status
    prior_acks_present = $PriorAcksPresent
    rule_in_base_instructions = $RuleInBaseInstructions
    divergence_override_history = $DivergenceOverrideHistory
}

# Export-Csv -Append with -UseQuotes AsNeeded produces compliant RFC 4180 output.
# This writes only the data row (no header) because the file already has a header.
$row | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded -Append

Write-Host "Appended row for $PrRef / $ProposedCatalogSlug"
