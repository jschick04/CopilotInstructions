# PR Quality Gate Panel Launcher (thin wrapper)
# Spec: ../README.md (PR Quality Gate v5 design doc) + panel-policy.md

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseSha,
    [Parameter(Mandatory)] [string] $HeadSha,
    [ValidateSet('full', 'triage', 'lint-only')] [string] $Mode = 'full',
    [string] $AskUserReceipt = '',                                   # quoted user response containing mode token; from orchestrator
    [string] $AskUserCallRef = '',
    [string] $PrRef = ''
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

# ===== Build review-pass-only prompts to forward to reviewers (tier-filtered by mode) =====
$tierForMode = switch ($Mode) {
    'full'      { @('HIGH','MEDIUM','LOW') }
    'triage'    { @('HIGH','MEDIUM') }
    'lint-only' { @('HIGH') }
}
$reviewPassPrompts = @()
$requiredRuleAckSlugs = @()
if (Test-Path -LiteralPath $catalogPath) {
    $lines = Get-Content -LiteralPath $catalogPath
    foreach ($line in $lines) {
        if ($line -notmatch '^\|') { continue }
        if ($line -match '^\|\s*slug\s*\|' -or $line -match '^\|\s*-+') { continue }
        $cellsRaw = ($line -split '(?<!\\)\|')
        if ($cellsRaw.Count -lt 2) { continue }
        $cells = $cellsRaw[1..($cellsRaw.Count - 2)] | ForEach-Object { $_.Trim() }
        if ($cells.Count -lt 4 -or $cells[1] -ne 'review-pass-only') { continue }
        $slug = $cells[0]
        $prompt = $cells[3]
        # 6th cell is tier (optional; legacy 5-cell defaults to MEDIUM).
        $tier = if ($cells.Count -ge 6 -and $cells[5]) { $cells[5] } else { 'MEDIUM' }
        if ($tier -notin $tierForMode) { continue }
        $reviewPassPrompts += "- **${slug}** [tier=${tier}]: $prompt"
        $requiredRuleAckSlugs += $slug
    }
}

# ===== Build anti-recidivism preamble (when -PrRef supplied) =====
$antiRecidivismLines = @()
if ($PrRef) {
    $panelMissesCsvPath = Join-Path $clone '.github/pr-quality-gate/data/panel-misses.csv'
    if (Test-Path -LiteralPath $panelMissesCsvPath) {
        $priorRows = Import-Csv -LiteralPath $panelMissesCsvPath -Encoding UTF8 | Where-Object { $_.pr_ref -eq $PrRef }
        $priorSlugs = @($priorRows | ForEach-Object { $_.proposed_catalog_slug } | Sort-Object -Unique | Where-Object { $_ })
        if ($priorSlugs.Count -gt 0) {
            $antiRecidivismLines += "pr_ref: $PrRef"
            $antiRecidivismLines += "prior_slugs:"
            foreach ($s in $priorSlugs) { $antiRecidivismLines += "  - $s" }
            $antiRecidivismLines += "reviewer_action_required: 'For each prior_slug, emit verified-no-recurrence: <slug> with fix_evidence (commit_sha or diff_hunk).'"
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
  pr_ref: $PrRef
  required_rule_ack: [$(($requiredRuleAckSlugs) -join ', ')]
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
    if ($antiRecidivismLines.Count -gt 0) {
        "    anti_recidivism_preamble:"
        foreach ($l in $antiRecidivismLines) { "      $l" }
    }
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
    3. Forward the anti_recidivism_preamble above (if present) — reviewer MUST emit verified-no-recurrence per slug
    4. Forward the same_state_recheck_preamble above
    5. Forward the system_prompt_rule_preamble above
    6. Collect the verdict (must include core_rules_acknowledged per panel-policy.md §Per-rule acknowledgement)
    7. Emit PANEL CONVERGED block with convergence_model: single-reviewer, convergence_result: <reviewer's verdict>, core_rules_acknowledged, rule_coverage_passed, anti_recidivism_acknowledged
"@
    exit 0
}

# Full mode
@"
PANEL LAUNCH CONTRACT (full)
  panel_mode: full
  pr_ref: $PrRef
  required_rule_ack: [$(($requiredRuleAckSlugs) -join ', ')]
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
if ($antiRecidivismLines.Count -gt 0) {
    "    anti_recidivism_preamble:"
    foreach ($l in $antiRecidivismLines) { "      $l" }
}
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
    3. Forward the anti_recidivism_preamble to each reviewer (if present) — each reviewer MUST emit verified-no-recurrence per slug
    4. Forward the same_state_recheck_preamble to each reviewer
    5. Forward the system_prompt_rule_preamble to each reviewer
    6. Handle drops per panel-policy.md (0→proceed; 1→replace; 2→ask_user; ≥3→hard escalate)
    7. Iterate fix-then-re-panel up to fix_iteration_count_cap (default 3)
    8. Each reviewer verdict MUST include core_rules_acknowledged per panel-policy.md §Per-rule acknowledgement
    9. On convergence: emit PANEL CONVERGED block with slate, convergence_model, convergence_result, dropped_reviewers, panel_rounds, fix_iteration_count, must_fix_unresolved, core_rules_acknowledged (union per slug), rule_coverage_passed, anti_recidivism_acknowledged
"@
exit 0
