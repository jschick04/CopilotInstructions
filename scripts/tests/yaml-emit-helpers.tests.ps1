#Requires -Version 5.1
# Unit + pwsh<->bash parity tests for the YAML single-quote helpers (.psm1 + its .sh twin). One fixture battery pins
# both quoters so they cannot drift. The parity leg skips only when bash is genuinely unavailable locally; on GitHub
# Actions a failed probe FAILS the test, so a one-sided helper edit cannot pass green.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-common.ps1')
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/yaml-emit-helpers.psm1') -Force

$script:Pass = 0
$script:Fail = 0

# Shared fixtures: input -> expected scalar; all reachable across the bash boundary (no NUL).
$fixtures = @(
    @{ Name = 'colon-space';    In = 'csharp-smells: foo'; Out = "'csharp-smells: foo'" }
    @{ Name = 'embedded-quote'; In = "it's-a-slug";        Out = "'it''s-a-slug'" }
    @{ Name = 'plain-kebab';    In = 'foo-bar';            Out = "'foo-bar'" }
    @{ Name = 'empty';          In = '';                   Out = "''" }
    @{ Name = 'leading-dash';   In = '-dash';              Out = "'-dash'" }
    @{ Name = 'leading-hash';   In = '#hash';              Out = "'#hash'" }
    @{ Name = 'flow-bracket';   In = '[x]';                Out = "'[x]'" }
    @{ Name = 'tab';            In = "a`tb";               Out = "'a b'" }
    @{ Name = 'crlf';           In = "a`r`nb";             Out = "'a  b'" }
)

Write-Host "yaml-emit-helpers (pwsh unit):"
foreach ($fixture in $fixtures) {
    Assert-Equal $fixture.Out (ConvertTo-YamlSingleQuotedScalar $fixture.In) "pwsh: $($fixture.Name)" -CaseSensitive
}
Assert-Equal "''" (ConvertTo-YamlSingleQuotedScalar $null) 'pwsh: null -> empty quoted scalar' -CaseSensitive
Assert-Equal "'a b'" (ConvertTo-YamlSingleQuotedScalar ("a" + [char]0 + "b")) 'pwsh: NUL collapses to space (pwsh-only; bash cannot hold NUL)' -CaseSensitive

Assert-True ((ConvertTo-YamlSingleQuotedScalar 'x: y') -cmatch "^'x: y'$") 'colon-space renders as a single-quoted scalar'
Assert-False ((ConvertTo-YamlSingleQuotedScalar 'x: y') -cmatch '^[^'']*:\s') 'quoted form is NOT a bare mapping-shaped value'

# pwsh<->bash parity. Skip only when bash is genuinely unavailable locally; on GitHub Actions a failed probe is a real
# regression (a one-sided helper edit) and FAILS rather than skips, so the drift guard cannot be silently bypassed.
$bashPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'yaml-emit-helpers.sh') -replace '\\', '/'
$onGitHubActions = ($env:GITHUB_ACTIONS -eq 'true')
$bashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)
$probe = $null
$probeExit = -1
if ($bashAvailable) {
    try { $probe = & bash -c "source '$bashPath'; yaml_sq 'probe'" 2>$null; $probeExit = $LASTEXITCODE } catch { $probe = $null; $probeExit = -1 }
}
$baselineOk = ($bashAvailable -and $probeExit -eq 0 -and $probe -ceq "'probe'")

if ($baselineOk) {
    Write-Host "yaml-emit-helpers (pwsh<->bash parity):"
    foreach ($fixture in $fixtures) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$fixture.In)
        $octal = ($bytes | ForEach-Object { '\{0}' -f [Convert]::ToString([int]$_, 8).PadLeft(3, '0') }) -join ''
        $cmd = "source '$bashPath'; yaml_sq " + '"$(printf ' + "'$octal'" + ')"'
        $bashOut = & bash -c $cmd 2>$null
        Assert-Equal (ConvertTo-YamlSingleQuotedScalar $fixture.In) ([string]$bashOut) "parity: $($fixture.Name)" -CaseSensitive
    }
} elseif ($onGitHubActions) {
    Assert-True $false "pwsh<->bash parity baseline failed on CI (exit=$probeExit, probe='$probe'): the LF helper must source and yaml_sq 'probe' must equal a single-quoted probe"
} else {
    Write-Host "  [SKIP] pwsh<->bash parity (no working bash for the LF helper here; runs on CI)"
}

Write-Host ""
$summaryColor = if ($script:Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "yaml-emit-helpers.tests: $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $summaryColor
exit ([int]($script:Fail -gt 0))
