<#
  check-no-panel-artifacts.ps1 - enforce AGENTS.md 3.1: code comments and test strings must NOT
  embed internal review-process artifacts (model names, or panel / round / slot / blocking-finding
  labels). These are not durable documentation - a future maintainer cannot action a reference to a
  reviewer model or an iteration label. Keep the engineering rationale; drop the artifact label.

  Scans tracked PowerShell + shell sources (*.ps1 / *.psm1 / *.sh / .githooks); the playbooks and
  docs legitimately discuss the review process, so they are out of scope. This checker + its own
  test are excluded (they embed the tokens by necessity). The panel orchestrator
  (.github/pr-quality-gate/invoke-panel.ps1) is PARTIALLY allowed: it may NAME models (its job is
  to define the model slate) but must NOT carry iteration/finding labels. Zero-tolerance; fail-closed.

  Exit: 0 clean, 1 violation(s), 2 invocation error.
#>
[CmdletBinding()]
param([string] $RepoRoot = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
if ($RepoRoot) {
    try {
        $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    } catch {
        Write-Host "::error::INVOCATION_FAILED: -RepoRoot '$RepoRoot' does not resolve: $($_.Exception.Message)"
        exit 2
    }
} else {
    try {
        $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-no-panel-artifacts.ps1') -RequireGitWorkTree
    } catch {
        Write-Host "::error::$($_.Exception.Message)"
        exit 2
    }
}

$ExitOk = 0; $ExitViolation = 1; $ExitInvocation = 2

# Two token sets (PCRE -P, case-insensitive). Word boundaries (\b) on the word-like tokens so common
# words are NOT false-matched ("workaround 10", "background 2", "timeslot A", "ducked"). The generic
# domain words that ARE legitimate here (panel / review / finding / regression) are excluded. The
# finding tokens are also the ones still banned inside invoke-panel.ps1. Keep in sync with the test.
$modelTokens   = '\bgpt|\bgemini|\bclaude|\bcodex|\bduck\b|re-panel|rd-enforce'
$findingTokens = 'gap ?#|forcing ?#|forcing re-review|R[0-9]+-[A-Z]+|PR #[0-9]+ review|bot-flagged|bot caught|\bSlot [A-Z0-9]|\bRound [0-9]+'
$pattern = "($modelTokens|$findingTokens)"

# git grep over code sources, excluding the checker + its own test (they embed tokens by necessity).
# git grep exit: 0 = matches, 1 = no matches (clean), >1 = real error -> fail closed.
$hits = & git -C $RepoRoot grep -nPi "$pattern" -- '*.ps1' '*.psm1' '*.sh' '.githooks' ':!scripts/check-no-panel-artifacts.ps1' ':!scripts/tests/check-no-panel-artifacts.tests.ps1' 2>$null
$grepExit = $LASTEXITCODE
if ($grepExit -gt 1) {
    Write-Host "::error::INVOCATION_FAILED: git grep failed (exit $grepExit); cannot scan for review-process artifacts. Failing closed."
    exit $ExitInvocation
}

# invoke-panel.ps1 (the orchestrator) may NAME models but must not carry finding/iteration labels:
# keep an invoke-panel hit ONLY when it also matches a finding token (a bare model name is allowed).
$invokePanelLine = '\.github/pr-quality-gate/invoke-panel\.ps1:'
$hitList = @($hits | Where-Object { $_ } | Where-Object {
    if ($_ -match $invokePanelLine) { $_ -match "($findingTokens)" } else { $true }
})
if ($grepExit -eq 0 -and $hitList.Count -gt 0) {
    Write-Host "check-no-panel-artifacts: $($hitList.Count) line(s) embed a review-process artifact (AGENTS.md 3.1 - keep the rationale, remove the model/round/slot/finding label):" -ForegroundColor Red
    foreach ($h in $hitList) { Write-Host "  ::error::$h" }
    exit $ExitViolation
}

Write-Host "check-no-panel-artifacts: PASS - no review-process artifacts in tracked .ps1/.psm1/.sh/.githooks sources." -ForegroundColor Green
exit $ExitOk
