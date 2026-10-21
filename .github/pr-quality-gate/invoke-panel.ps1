# PR Quality Gate Panel Launcher (thin wrapper)
# Spec: ../README.md (PR Quality Gate v5 design doc) + panel-policy.md

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseSha,
    [Parameter(Mandatory)] [string] $HeadSha,
    [ValidateSet('full', 'triage', 'lint-only')] [string] $Mode = 'full',
    [string] $AskUserReceipt = '',
    [string] $AskUserCallRef = '',
    [string] $PrRef = '',
    [switch] $Staged,
    [string] $ParentSha = ''
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../../scripts/lib/yaml-emit-helpers.psm1') -Force

function Write-Err  { param([string] $Msg) [Console]::Error.WriteLine("[invoke-panel ERROR] $Msg") }
function Exit-Launcher { param([int] $Code, [string] $Reason) if ($Reason) { Write-Err $Reason }; exit $Code }

$clone = $env:COPILOT_INSTRUCTIONS_CLONE
if (-not $clone) { Exit-Launcher 3 'COPILOT_INSTRUCTIONS_CLONE env var not set.' }
$staleProfilePath = Join-Path $clone '.github/instructions/active-profile.instructions.md'
$staleProfileFile = Test-Path -LiteralPath $staleProfilePath

$targetRootOutput = @(& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $targetRootOutput.Count -ne 1 -or -not $targetRootOutput[0]) { Exit-Launcher 2 'cannot resolve review repository' }
$targetRoot = $targetRootOutput[0]
if (-not $Staged -and ($BaseSha -cnotmatch '^([0-9a-f]{40}|[0-9a-f]{64})$' -or $HeadSha -cnotmatch '^([0-9a-f]{40}|[0-9a-f]{64})$')) { Exit-Launcher 2 'range panels require full lowercase hex BaseSha and HeadSha (captured panelBaseSha/panelHeadSha), never symbolic refs' }
if ($ParentSha -and $ParentSha -cnotmatch '^(none|[0-9a-f]{40}|[0-9a-f]{64})$') { Exit-Launcher 2 '-ParentSha requires none or a full lowercase 40- or 64-hex SHA' }
if ($ParentSha -and -not $Staged) { Exit-Launcher 2 '-ParentSha is valid only for -Staged panels' }
Import-Module (Join-Path $clone 'scripts/lib/panel-ledger-helpers.psm1') -Force -DisableNameChecking
$requiresFull = if ($Staged) { Test-RequiresFullPanel -RepoRoot $targetRoot } else { Test-RequiresFullPanel -RepoRoot $targetRoot -CommitSha $HeadSha }
$artifactScript = Join-Path $clone 'scripts/Get-ReviewedArtifactId.ps1'
$artifactArguments = if ($Staged) { @('-Staged') } else { @('-Range', "$BaseSha..$HeadSha") }
if ($Staged -and $ParentSha) { $artifactArguments += @('-ParentSha', $ParentSha) }
$artifactOutput = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $targetRoot @artifactArguments)
if ($LASTEXITCODE -ne 0 -or $artifactOutput.Count -lt 1 -or $artifactOutput[0] -cnotmatch '^[0-9a-f]{64}$') { Exit-Launcher 2 'cannot resolve reviewed artifact' }
$reviewedArtifact = $artifactOutput[0]
$artifactCommand = if ($Staged) { "pwsh -NoProfile -File `"$artifactScript`" -RepoRoot `"$targetRoot`" -Staged" } else { "pwsh -NoProfile -File `"$artifactScript`" -RepoRoot `"$targetRoot`" -Range `"$BaseSha..$HeadSha`"" }
if ($Staged -and $ParentSha) { $artifactCommand += " -ParentSha $ParentSha" }
$expectedToken = if ($Mode -ne 'full' -and ($requiresFull -or $Mode -eq 'triage' -or $Mode -eq 'lint-only')) { "$Mode-acknowledged" } else { $null }
if ($requiresFull -and $Mode -ne 'full') { Exit-Launcher 2 "Mode '$Mode' is forbidden for this instruction-repo change; full panel required." }
if ($expectedToken) {
    if (-not $AskUserReceipt -or $AskUserReceipt -notmatch [regex]::Escape($expectedToken)) { Exit-Launcher 2 "Mode '$Mode' requires same-turn ask_user receipt containing '$expectedToken'." }
    if (-not $AskUserCallRef) { Exit-Launcher 2 "Mode '$Mode' requires -AskUserCallRef pointing to the same-turn ask_user invocation." }
}

# ===== Drift-safeguard: verify HIGH-TIER-SLUGS.md is in sync with pattern-catalog.md =====
# Must run in ALL modes including lint-only - placed BEFORE the lint-only short-circuit.
# Panel-time secondary defense (primary is the .githooks/pre-commit hook). Catches stale clones.
$syncScript = Join-Path $clone 'scripts/sync-critical-rules.ps1'
if (Test-Path -LiteralPath $syncScript) {
    & pwsh -NoProfile -File $syncScript -Verify `
        -CatalogPath (Join-Path $clone '.github/pr-quality-gate/pattern-catalog.md') `
        -OutputPath (Join-Path $clone '.github/pr-quality-gate/HIGH-TIER-SLUGS.md') 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Exit-Launcher 4 "HIGH-TIER-SLUGS.md is out of sync with pattern-catalog.md in clone '$clone'. Run: pwsh -File '$syncScript'"
    }
} else {
    [Console]::Error.WriteLine("[invoke-panel] sync-critical-rules.ps1 not found in clone; skipping ack-sync drift check.")
}

# ===== Lint-only short-circuit (no panel) =====
if ($Mode -eq 'lint-only') {
    @"
CODE-REVIEW PANEL CONVERGED
  panel_invoked: false
  slate_mode: lint-only
  slate: lint-only - no panel
  convergence_model: n/a - no panel invoked
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
    Exit-Launcher 2 "panel-policy.md is missing the '## System-prompt-rule enforcement' section's `> ...` blockquote - cannot emit reviewer preamble. Verify policy file integrity."
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
            $antiRecidivismLines += "pr_ref: $(ConvertTo-YamlSingleQuotedScalar $PrRef)"
            $antiRecidivismLines += "prior_slugs:"
            foreach ($s in $priorSlugs) { $antiRecidivismLines += "  - $(ConvertTo-YamlSingleQuotedScalar $s)" }
            $antiRecidivismLines += "reviewer_action_required: 'For each prior_slug, emit verified-no-recurrence: <slug> with fix_evidence (commit_sha or diff_hunk).'"
        }
    }
}

# ===== Slate construction (delegated to orchestrator - script reports REQUIRED slate, doesn't launch agents itself) =====
# This script is a CONTRACT-emitter, not an agent launcher. The orchestrator (the main agent running this in
# a Copilot CLI session) reads the panel-policy.md, satisfies the slate-floor, launches the reviewer agents
# via the task tool, collects verdicts, and emits CODE-REVIEW PANEL CONVERGED itself. This script's job is to validate
# the receipt + extract review-pass-only prompts + emit a contract document the orchestrator must fulfill.

if ($Mode -eq 'triage') {
    @"
PANEL LAUNCH CONTRACT (triage)
  panel_mode: triage
  stale_profile_file: $(if ($staleProfileFile) { 'present - delete .github/instructions/active-profile.instructions.md or re-run setup' } else { 'absent' })
  pr_ref: $(ConvertTo-YamlSingleQuotedScalar $PrRef)
  required_rule_ack: [$(($requiredRuleAckSlugs) -join ', ')]
  slate_floor_required:
    reviewer_count: 2
    role: code-review
    convergence_model: unanimous
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
      At review start and before verdict, run $artifactCommand in the reviewed repository.
      Compare its first stdout line to $reviewedArtifact. If it differs or resolution fails,
      ABORT with NEEDS_REWORK citing the stale reviewed artifact; do not substitute a HEAD-only check.
    system_prompt_rule_preamble: |
"@
    foreach ($l in $systemPromptPreambleLines) { "      $l" }
    @"
  base_sha: $BaseSha
  head_sha: $HeadSha
  ORCHESTRATOR_ACTIONS_REQUIRED:
    1. Launch exactly 2 light code-review reviewers with distinct models from distinct families: light-claude-balanced + light-gpt by default; light-gemini replaces an unavailable family per panel-policy.md
    2. Forward all review_pass_only_prompts above to BOTH reviewers
    3. Forward the anti_recidivism_preamble above (if present) to both - each reviewer MUST emit verified-no-recurrence per slug
    4. Forward the same_state_recheck_preamble above to both
    5. Forward the system_prompt_rule_preamble above to both
    6. Collect BOTH verdicts (each must include core_rules_acknowledged per panel-policy.md §Per-rule acknowledgement); convergence passes only when both return CODE_REVIEW_READY
    7. Handle drops per panel-policy.md with a light replacement that keeps two distinct families; never converge on one verdict
    8. Repeat fix-then-re-panel with the same reviewers without a round cap until unanimous convergence
    9. On convergence: emit CODE-REVIEW PANEL CONVERGED block in caveman KV form (scalars as pipe-KV; slate + core_rules_acknowledged enumerations preserved) with profile=$Mode, slate, convergence_model: unanimous, convergence_result, dropped_reviewers (each with its replacement), panel_rounds, must_fix_unresolved, core_rules_acknowledged (union per slug), rule_coverage_passed, anti_recidivism_acknowledged
"@
    exit 0
}

# Full mode
@"
PANEL LAUNCH CONTRACT (full)
  panel_mode: full
  stale_profile_file: $(if ($staleProfileFile) { 'present - delete .github/instructions/active-profile.instructions.md or re-run setup' } else { 'absent' })
  pr_ref: $(ConvertTo-YamlSingleQuotedScalar $PrRef)
  required_rule_ack: [$(($requiredRuleAckSlugs) -join ', ')]
  slate_floor_required:
    reviewer_count: 4 or more; default slate has 4
    family_floor:
      claude_family: ">=1"
      gpt_family: ">=1"
      gpt_or_grok_combined: ">=2"
      gemini_family: ">=1"
    role_floor:
      rubber_duck: ">=1"
      code_review: ">=2"
    tier_floor:
      heavy_tier: all reviewers
    convergence_model: unanimous (all reviewers must return the success verdict)
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
      At review start and before verdict, run $artifactCommand in the reviewed repository.
      Compare its first stdout line to $reviewedArtifact. If it differs or resolution fails,
      ABORT with NEEDS_REWORK citing the stale reviewed artifact; do not substitute a HEAD-only check.
    system_prompt_rule_preamble: |
"@
foreach ($l in $systemPromptPreambleLines) { "      $l" }
@"
  base_sha: $BaseSha
  head_sha: $HeadSha
  ORCHESTRATOR_ACTIONS_REQUIRED:
    1. Launch reviewer agents via the task tool satisfying the slate_floor (4 distinct heavy reviewers, optional fifth)
    2. Forward all review_pass_only_prompts to each reviewer
    3. Forward the anti_recidivism_preamble to each reviewer (if present) - each reviewer MUST emit verified-no-recurrence per slug
    4. Forward the same_state_recheck_preamble to each reviewer
    5. Forward the system_prompt_rule_preamble to each reviewer
    6. Handle drops per panel-policy.md; preserve the full slate floor
    7. Repeat fix-then-re-panel without a round cap until unanimous convergence
    8. Each reviewer verdict MUST include core_rules_acknowledged per panel-policy.md §Per-rule acknowledgement
    9. On convergence: emit CODE-REVIEW PANEL CONVERGED block in caveman KV form (scalars as pipe-KV; slate + core_rules_acknowledged enumerations preserved) with profile=$Mode, slate, convergence_model, convergence_result, dropped_reviewers, panel_rounds, must_fix_unresolved, core_rules_acknowledged (union per slug), rule_coverage_passed, anti_recidivism_acknowledged
"@
exit 0
