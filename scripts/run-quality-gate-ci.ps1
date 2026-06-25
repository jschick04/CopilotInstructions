<#
  run-quality-gate-ci.ps1 - CI/local wrapper that owns its own setup so the quality-gate-check workflow step is a single
  script invocation (no inline multi-command run: block). Resolves the base/head SHAs fail-closed, points
  COPILOT_INSTRUCTIONS_CLONE at the repo root (this repo IS the instructions clone), and runs gate-runner.ps1
  -Verify -Mode full (read-only: no findings.csv append, no lock) over the whole-branch BaseRef..HEAD diff. gate-runner
  exits 1 on a BLOCKED gate_status (mechanical rg-battery findings present), which fails the job. HONEST CEILING: this
  runs gate-runner HEADLESS - it verifies only the mechanical rg-floor, NOT the QUALITY GATE block, the multi-model
  panel, or the verdict (all agent-asserted).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseRef,
    [string] $RepoRoot = '',
    [switch] $CiMode
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
function Write-WrapErr { param([string] $Msg) if ($CiMode) { Write-Host "::error::$Msg" } else { Write-Host $Msg -ForegroundColor Red } }
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/run-quality-gate-ci.ps1') -RequireGitWorkTree
} catch {
    Write-WrapErr $_.Exception.Message
    exit 2
}

$base = (& git -C $RepoRoot merge-base $BaseRef HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $base) {
    Write-WrapErr "run-quality-gate-ci: cannot resolve the merge-base of '$BaseRef' and HEAD (gate-runner's base_sha contract) - refusing to run fail-open"
    exit 2
}
$head = (& git -C $RepoRoot rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $head) {
    Write-WrapErr "run-quality-gate-ci: cannot resolve HEAD SHA - refusing to run fail-open"
    exit 2
}
$base = $base.Trim()
$head = $head.Trim()

# gate-runner requires ripgrep (rg). It is NOT in the default GitHub-hosted ubuntu image, so install it on a Linux CI
# runner when absent (the coverage gate forbids a separate apt-get run: step, so setup lives in this mirrored script);
# everywhere else, fail closed rather than run fail-open without the rg-battery.
if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    if ($env:RUNNER_OS -eq 'Linux') {
        Write-Host 'run-quality-gate-ci: ripgrep (rg) not found on the runner; installing via apt-get...'
        & sudo apt-get update -qq 2>&1 | Out-Null
        & sudo apt-get install -y -qq ripgrep 2>&1 | Out-Null
    }
    if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
        Write-WrapErr 'run-quality-gate-ci: ripgrep (rg) is required by gate-runner but is not on PATH (and could not be auto-installed) - install ripgrep and retry'
        exit 2
    }
}

$env:COPILOT_INSTRUCTIONS_CLONE = $RepoRoot
$runner = Join-Path $RepoRoot '.github/pr-quality-gate/gate-runner.ps1'
$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
& $pwshExe -NoProfile -File $runner -BaseSha $base -HeadSha $head -Mode full -Verify -ProjectRoot $RepoRoot
exit $LASTEXITCODE
