# YAML single-quote scalar helper for the panel/gate prompt builders (invoke-panel.ps1, gate-runner.ps1/.sh).
# Renders a free-text CSV value (pr_ref, prior_slugs) as a single-line scalar so a colon-space or leading indicator
# cannot reshape the LLM-consumed contract block into a mapping. Structural disambiguation for the reader only --
# no strict YAML parser is downstream, so this is not strict-parse or injection safety.
# Byte-identical bash twin: scripts/yaml-emit-helpers.sh; parity pinned by scripts/tests/yaml-emit-helpers.tests.ps1.

Set-StrictMode -Version Latest

function ConvertTo-YamlSingleQuotedScalar {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Value)
    $flattened = ([string]$Value) -replace '[\x00-\x1f\x7f]', ' '
    return "'" + ($flattened -replace "'", "''") + "'"
}

Export-ModuleMember -Function ConvertTo-YamlSingleQuotedScalar
