# PR Quality Gate Panel Launcher (thin wrapper)
# Spec: ../README.md (PR Quality Gate v5 design doc) + panel-policy.md

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseSha,
    [Parameter(Mandatory)] [string] $HeadSha,
    [ValidateSet('full', 'triage', 'lint-only')] [string] $Mode = 'full',
    [string] $AskUserReceipt = '',                                   # quoted user response containing mode token; from orchestrator
    [string] $AskUserCallRef = ''
)

$ErrorActionPreference = 'Stop'

function Write-Err  { param([string] $Msg) [Console]::Error.WriteLine("[invoke-panel ERROR] $Msg") }
function Exit-Launcher { param([int] $Code, [string] $Reason) if ($Reason) { Write-Err $Reason }; exit $Code }

# ===== Mode-receipt validation =====
$expectedToken = switch ($Mode) {
    'triage'    { 'triage-acknowledged' }
    'lint-only' { 'lint-only-acknowledged' }
    'full'      { $null }
}

if ($expectedToken) {
    if (-not $AskUserReceipt) {
        Exit-Launcher 2 "Mode '$Mode' requires same-turn ask_user receipt (-AskUserReceipt) containing literal token '$expectedToken'. See README.md `"Mode activation`"."
    }
    if ($AskUserReceipt -notmatch [regex]::Escape($expectedToken)) {
        Exit-Launcher 2 "Receipt '$AskUserReceipt' does not contain required token '$expectedToken' for mode '$Mode'."
    }
    if (-not $AskUserCallRef) {
        Exit-Launcher 2 "Mode '$Mode' requires -AskUserCallRef pointing to the same-turn ask_user invocation."
    }
}

# ===== Lint-only short-circuit (no panel) =====
if ($Mode -eq 'lint-only') {
    @"
PANEL CONVERGED
  panel_invoked: false
  slate_mode: lint-only
  slate: lint-only — no panel
  convergence_model: n/a — no panel invoked
  convergence_result: n/a
  panel_mode_receipt:
    ask_user_call_ref: $AskUserCallRef
    quoted_response_contains: lint-only-acknowledged
  base_sha: $BaseSha
  head_sha: $HeadSha
"@
    exit 0
}

# ===== Read panel-policy.md =====
$clone = $env:COPILOT_INSTRUCTIONS_CLONE
if (-not $clone) { Exit-Launcher 3 'COPILOT_INSTRUCTIONS_CLONE env var not set.' }
$policyPath = Join-Path $clone '.github/pr-quality-gate/panel-policy.md'
if (-not (Test-Path -LiteralPath $policyPath)) { Exit-Launcher 2 "panel-policy.md not found: $policyPath" }
$catalogPath = Join-Path $clone '.github/pr-quality-gate/pattern-catalog.md'

# ===== Extract system-prompt-rule enforcement preamble from panel-policy.md =====
function Get-PolicyBlockquote {
    param([string] $Path, [string] $SectionHeading)
    $headingPattern = '^\s{0,3}##\s+' + [regex]::Escape($SectionHeading) + '\s*(\(|$)'
    $h2Pattern = '^\s{0,3}##\s+'
    $lines = Get-Content -LiteralPath $Path
    $inSection = $false
    $collected = @()
    foreach ($line in $lines) {
        if ($line -match $h2Pattern) {
            if ($line -match $headingPattern) { $inSection = $true; continue }
            elseif ($inSection) { break }
            else { continue }
        }
        if ($inSection -and $line -match '^>\s?(.*)$') { $collected += $matches[1] }
    }
    return ,$collected
}
$systemPromptPreambleLines = Get-PolicyBlockquote -Path $policyPath -SectionHeading 'System-prompt-rule enforcement'
if (-not $systemPromptPreambleLines -or $systemPromptPreambleLines.Count -eq 0) {
    Exit-Launcher 2 "panel-policy.md is missing the '## System-prompt-rule enforcement' section's `> ...` blockquote — cannot emit reviewer preamble. Verify policy file integrity."
}

# ===== Build review-pass-only prompts to forward to reviewers =====
$reviewPassPrompts = @()
if (Test-Path -LiteralPath $catalogPath) {
    $lines = Get-Content -LiteralPath $catalogPath
    foreach ($line in $lines) {
        if ($line -notmatch '^\|') { continue }
        if ($line -match '^\|\s*slug\s*\|' -or $line -match '^\|\s*-+') { continue }
        $cells = ($line -split '(?<!\\)\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        if ($cells.Count -ge 4 -and $cells[1] -eq 'review-pass-only') {
            $reviewPassPrompts += "- **$($cells[0])**: $($cells[3])"
        }
    }
}

# ===== Slate construction (delegated to orchestrator — script reports REQUIRED slate, doesn't launch agents itself) =====
# This script is a CONTRACT-emitter, not an agent launcher. The orchestrator (the main agent running this in
# a Copilot CLI session) reads the panel-policy.md, satisfies the slate-floor, launches the reviewer agents
# via the task tool, collects verdicts, and emits PANEL CONVERGED itself. This script's job is to validate
# the receipt + extract review-pass-only prompts + emit a contract document the orchestrator must fulfill.

if ($Mode -eq 'triage') {
    @"
PANEL LAUNCH CONTRACT (triage)
  panel_mode: triage
  slate_floor_required:
    reviewer_count: 1
    role: code-review
    convergence_model: single-reviewer
  panel_mode_receipt:
    ask_user_call_ref: $AskUserCallRef
    quoted_response_contains: triage-acknowledged
  reviewer_prompt_must_include:
    review_pass_only_prompts:
"@
    foreach ($p in $reviewPassPrompts) { "    $p" }
    @"
    same_state_recheck_preamble: |
      Before producing your verdict, re-fetch git rev-parse HEAD in the consuming-project worktree.
      The expected SHA is $HeadSha recorded at launch time. If your HEAD does NOT match, ABORT with
      a NEEDS_REWORK verdict citing "stale launch SHA: launched against $HeadSha, current HEAD is <currentSha>".
    system_prompt_rule_preamble: |
"@
    foreach ($l in $systemPromptPreambleLines) { "      $l" }
    @"
  base_sha: $BaseSha
  head_sha: $HeadSha
  ORCHESTRATOR_ACTIONS_REQUIRED:
    1. Launch 1 code-review-role reviewer agent via the task tool (cheap model OK; output cap NOT enforced)
    2. Forward all review_pass_only_prompts above to the reviewer
    3. Forward the same_state_recheck_preamble above
    4. Forward the system_prompt_rule_preamble above
    5. Collect the verdict
    6. Emit PANEL CONVERGED block with convergence_model: single-reviewer, convergence_result: <reviewer's verdict>
"@
    exit 0
}

# Full mode
@"
PANEL LAUNCH CONTRACT (full)
  panel_mode: full
  slate_floor_required:
    reviewer_count: 4-5
    family_floor:
      claude_family: ">=1"
      gpt_family: ">=2"
    role_floor:
      rubber_duck: ">=1"
      code_review: ">=2"
    tier_floor:
      heavy_tier: ">=1"
    convergence_model: unanimous (default; waivable via ask_user to threshold-75% or confidence-weighted-80%)
  reviewer_prompt_must_include:
    review_pass_only_prompts:
"@
foreach ($p in $reviewPassPrompts) { "    $p" }
@"
    same_state_recheck_preamble: |
      Before producing your verdict, re-fetch git rev-parse HEAD in the consuming-project worktree.
      The expected SHA is $HeadSha recorded at launch time. If your HEAD does NOT match, ABORT with
      a NEEDS_REWORK verdict citing "stale launch SHA: launched against $HeadSha, current HEAD is <currentSha>".
    system_prompt_rule_preamble: |
"@
foreach ($l in $systemPromptPreambleLines) { "      $l" }
@"
  base_sha: $BaseSha
  head_sha: $HeadSha
  ORCHESTRATOR_ACTIONS_REQUIRED:
    1. Launch reviewer agents via the task tool satisfying the slate_floor (typically 4-5 agents in parallel)
    2. Forward all review_pass_only_prompts to each reviewer
    3. Forward the same_state_recheck_preamble to each reviewer
    4. Forward the system_prompt_rule_preamble to each reviewer
    5. Handle drops per panel-policy.md (0→proceed; 1→replace; 2→ask_user; ≥3→hard escalate)
    6. Iterate fix-then-re-panel up to fix_iteration_count_cap (default 3)
    7. On convergence: emit PANEL CONVERGED block with slate, convergence_model, convergence_result, dropped_reviewers, panel_rounds, fix_iteration_count, must_fix_unresolved
"@
exit 0
