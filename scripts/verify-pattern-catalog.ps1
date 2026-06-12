# Verify pattern-catalog.md matches generated output from sources.
# Thin wrapper around generate-pattern-catalog.ps1 -Verify for CI convenience.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
& (Join-Path $scriptDir 'generate-pattern-catalog.ps1') -Verify
exit $LASTEXITCODE
