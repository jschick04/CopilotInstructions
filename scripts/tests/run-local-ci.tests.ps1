#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone self-test for run-local-ci.ps1's coverage gate. Dot-sources it (neither mode runs) and exercises
# Test-ScriptInvocation + Test-MirrorCoverage directly. Run: pwsh -File scripts/tests/run-local-ci.tests.ps1

. (Resolve-Path (Join-Path $PSScriptRoot '../run-local-ci.ps1')).Path

$script:failures = 0
$script:passes = 0
function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    if ($Condition) { $script:passes++; Write-Host "  [PASS] $Description" }
    else { $script:failures++; Write-Host "  [FAIL] $Description" -ForegroundColor Red }
}

$scaffold = @('^actions/checkout@', '^actions/setup-[a-z0-9-]+@')

function Invoke-Coverage {
    param([hashtable] $Files, [hashtable] $Composite = @{}, [string[]] $Mirror, [int] $MinW = 1, [int] $MinS = 1, [int] $MinI = 1)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("rlc-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $wfDir = Join-Path $root '.github/workflows'
    New-Item -ItemType Directory -Path $wfDir -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($name in $Files.Keys) { [System.IO.File]::WriteAllText((Join-Path $wfDir $name), ($Files[$name] -replace "`r`n", "`n"), $utf8) }
    $compFiles = @()
    foreach ($rel in $Composite.Keys) {
        $full = Join-Path $root $rel
        New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($full, ($Composite[$rel] -replace "`r`n", "`n"), $utf8)
        $compFiles += Get-Item -LiteralPath $full
    }
    $wf = @(Get-ChildItem -LiteralPath $wfDir -File)
    try {
        return (Test-MirrorCoverage -WorkflowFiles $wf -CompositeFiles $compFiles -MirrorScripts $Mirror -HarnessSelf 'scripts/run-local-ci.ps1' -ScaffoldPatterns $scaffold -RootForRel $root -MinWorkflows $MinW -MinSteps $MinS -MinInvocations $MinI)
    } finally { Remove-Item -Recurse -Force -LiteralPath $root -ErrorAction SilentlyContinue }
}

$goodWf = @'
name: fixture
on:
  pull_request:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@abc123
      - shell: pwsh
        run: ./scripts/foo.ps1
'@

Write-Host ""
Write-Host "=== Test-ScriptInvocation (adversarial matcher) ===" -ForegroundColor Cyan
Assert-True ((Test-ScriptInvocation './scripts/check-md-size.ps1') -eq 'scripts/check-md-size.ps1') "bare ./scripts invocation resolves"
Assert-True ((Test-ScriptInvocation 'pwsh -File scripts/check-md-size.ps1') -eq 'scripts/check-md-size.ps1') "pwsh -File invocation resolves"
Assert-True ((Test-ScriptInvocation 'bash ./scripts/sync-critical-rules.sh') -eq 'scripts/sync-critical-rules.sh') "bash .sh invocation resolves"
Assert-True ((Test-ScriptInvocation './scripts/x.ps1 -BaseRef "origin/main"') -eq 'scripts/x.ps1') "invocation with args resolves"
Assert-True ($null -eq (Test-ScriptInvocation 'pwsh -File $VAR')) "variable-indirection path is rejected"
Assert-True ($null -eq (Test-ScriptInvocation './scripts/x.ps1 && git diff --exit-code')) "&&-chained extra logic is rejected"
Assert-True ($null -eq (Test-ScriptInvocation './scripts/x.ps1 | grep foo')) "piped extra logic is rejected"
Assert-True ($null -eq (Test-ScriptInvocation 'echo hello')) "non-script command is rejected"
Assert-True ($null -eq (Test-ScriptInvocation 'git diff --exit-code')) "inline git check is rejected"
Assert-True ($null -eq (Test-ScriptInvocation 'echo scripts/foo.ps1')) "a script path only as an argument (echo bypass) is rejected"
Assert-True ($null -eq (Test-ScriptInvocation 'cat scripts/foo.sh')) "a script path passed to cat (not executed) is rejected"
Assert-True ((Test-ScriptInvocation 'pwsh -NoProfile -File scripts/foo.ps1') -eq 'scripts/foo.ps1') "pwsh with multiple flags before -File still resolves"
Assert-True ($null -eq (Test-ScriptInvocation './scripts/../foo.ps1')) "path traversal (scripts/../foo.ps1 escapes scripts/) is rejected"
Assert-True ($null -eq (Test-ScriptInvocation 'pwsh -File scripts/sub/../../etc/foo.ps1')) "deeper traversal out of scripts/ is rejected"

Write-Host ""
Write-Host "=== Test-MirrorCoverage (PASS baseline) ===" -ForegroundColor Cyan
$r = Invoke-Coverage -Files @{ 'a.yml' = $goodWf } -Mirror @('scripts/foo.ps1')
Assert-True ($r.Failures.Count -eq 0) "clean fixture (mirrored script + scaffolding checkout) passes"
Assert-True ($r.Counts.script_invocations -eq 1 -and $r.Counts.scaffolding_uses -eq 1) "manifest counts the invocation + scaffolding"

Write-Host ""
Write-Host "=== Test-MirrorCoverage (must FAIL on each violation) ===" -ForegroundColor Cyan

$r = Invoke-Coverage -Files @{ 'a.yml' = $goodWf } -Mirror @('scripts/other.ps1')
Assert-True (($r.Failures -join '|') -match 'does NOT mirror') "workflow invoking an un-mirrored script fails"

$r = Invoke-Coverage -Files @{ 'a.yml' = $goodWf } -Mirror @('scripts/foo.ps1', 'scripts/dead.ps1')
Assert-True (($r.Failures -join '|') -match 'dead mirror entry|not invoked by any workflow') "dead mirror row fails"

$multi = @'
name: f
on: { pull_request: { branches: [main] } }
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@abc
      - shell: pwsh
        run: |
          ./scripts/foo.ps1
          git diff --exit-code
'@
$r = Invoke-Coverage -Files @{ 'a.yml' = $multi } -Mirror @('scripts/foo.ps1')
Assert-True (($r.Failures -join '|') -match 'non-script executable line') "inline multi-command run: block fails"

$thirdparty = @'
name: f
on: { pull_request: { branches: [main] } }
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@abc
      - uses: super-linter/super-linter@v5
'@
$r = Invoke-Coverage -Files @{ 'a.yml' = $thirdparty } -Mirror @()
Assert-True (($r.Failures -join '|') -match 'scaffolding allowlist') "non-scaffolding third-party uses: fails"

$localaction = @'
name: f
on: { pull_request: { branches: [main] } }
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@abc
      - uses: ./.github/actions/setup-linter
'@
$r = Invoke-Coverage -Files @{ 'a.yml' = $localaction } -Mirror @()
Assert-True (($r.Failures -join '|') -match 'scaffolding allowlist') "local composite action masquerading as scaffolding fails"

$reusable = @'
name: f
on: { pull_request: { branches: [main] } }
jobs:
  a:
    uses: ./.github/workflows/other.yml
'@
$r = Invoke-Coverage -Files @{ 'a.yml' = $reusable } -Mirror @()
Assert-True (($r.Failures -join '|') -match 'un-enumerated use|reusable workflow') "job-level reusable workflow fails (reconciliation)"

$envmask = @'
name: f
on: { pull_request: { branches: [main] } }
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@abc
      - shell: pwsh
        env:
          X: scripts/foo.ps1
        run: exit 0
'@
$r = Invoke-Coverage -Files @{ 'a.yml' = $envmask } -Mirror @('scripts/foo.ps1')
Assert-True (($r.Failures -join '|') -match 'non-script executable line') "scripts/ in env: does not mask a non-script run: (structure-aware)"

$r = Invoke-Coverage -Files @{} -Mirror @()
Assert-True (($r.Failures -join '|') -match 'glob matched nothing|no workflow files') "zero workflow files fails closed"

$r = Invoke-Coverage -Files @{ 'a.yml' = $goodWf } -Mirror @('scripts/foo.ps1') -MinW 4 -MinS 8 -MinI 6
Assert-True (($r.Failures -join '|') -match 'suspicious, fail-closed') "anti-vacuous floors fail a too-small set"

$badComposite = @'
name: x
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        echo checking
        git diff --exit-code
'@
$r = Invoke-Coverage -Files @{ 'a.yml' = $goodWf } -Composite @{ '.github/actions/x/action.yml' = $badComposite } -Mirror @('scripts/foo.ps1')
Assert-True (($r.Failures -join '|') -match 'non-script executable line') "composite action with inline check logic is scanned + rejected"

Write-Host ""
$summaryColor = if ($script:failures -eq 0) { 'Green' } else { 'Red' }
Write-Host "run-local-ci.tests: $($script:passes) passed, $($script:failures) failed" -ForegroundColor $summaryColor
exit ([int]($script:failures -gt 0))
