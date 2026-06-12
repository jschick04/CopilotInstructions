# Implementation roadmap - pre-PR-creation review gate

Deferred design decisions from the initial §2D introduction PR. Each ships in a follow-up PR triggered by the first real-world failure it addresses or explicit maintainer prioritization.

Deferred features (ranked by priority):

1. **Capability-tier registry indirection**: ship trigger: model deprecated/removed from runtime catalog, OR `slateSubstitutions` >= 2 in 30 days, OR new tier added.
2. **Context-budget circuit breaker**: ship trigger: §2D session > 700K context, OR panel aborted from exhaustion/OOM.
3. **Branch-level fix-iteration cap**: ship trigger: branch >= 3 fix-iterations, OR manual escalation bypassed.
4. **Compaction format with citation preservation**: ship trigger: heavy panel re-raises disposed theme (dedup loss), OR per-commit-panel output > 50K tokens.
5. **Forge-agnostic state field**: ship trigger: §2D invoked on non-GitHub forge AND inline commands fail, OR inline forge enumeration >= 5 entries.
6. **Slate-floor automated re-check**: ship trigger: slate-floor break detected at synthesis, OR READY emitted with uncaught violation.
7. **Same-state re-check infrastructure**: ship trigger: READY-re-emitted but actual branch state differs from `panelHeadSha`, OR Step 9 same-state check false-negative.

Ship triggers are not exhaustive; maintainer prioritization can promote any item.

---

# DEFERRED DESIGN - kept here for follow-up PRs

# Playbook: Pre-PR-creation review (heavy multi-model panel)

## Purpose

Mandatory multi-model code-review panel on the FULL branch diff (`<base>..HEAD`) before any PR is created or made review-visible. Mirrors the categories an LLM-based PR reviewer would surface - runs locally pre-push so findings are caught before reviewers see them. Sister to `post-code-change.md` §3 (per-commit panel): this is the branch-wide heavy panel that catches cross-commit emergent issues.

## Hard gates

### G1. Mandatory panel run - not user-waivable

The panel MUST run. No `ask_user` quote waives it. Only exit: convergence with all must-fix findings resolved.

### G2. Must-fix=0 to proceed - not user-waivable

Every `blocking` finding MUST be resolved via one of exactly three paths (G5 enum):

- **`fixed`** - applied as a change in the branch.
- **`dismissed-source-grounded`** - refuted by source evidence (file:line, doc URL, RFC, ADR, spec section) that addresses the finding's correctness; do NOT hand-wave to "out of scope".
- **`routed-deferred-with-tracker-and-ask_user`** - deferred per G4 conditions. Only valid deferral form for blocking findings.

No "ship it anyway" path. User can route individual findings via G4, but cannot waive G2 itself.

### G3. `PRE-PR REVIEW COVERAGE` block required in the actual PR-creation turn - not user-waivable

The mandatory output block (format in Step 10) MUST appear in the same chat turn as the G6 tool call.

**Two-turn flow with re-emission**:

1. **Initial emission** at Step 10 (turn N) with `READY-pending-user-approval`.
2. **Re-emission** in PR-creation turn (turn N+1, after user approval), with same-state re-check:
 - `git rev-parse HEAD` matches recorded `panelHeadSha`.
 - `git merge-base --is-ancestor <panelHeadSha> HEAD` returns true.
 - `git rev-parse <baseRef>` matches recorded `panelBaseSha`.
 - Any check fails: gate restarts at Step 2; prior block invalid.
3. **Re-emission status**: `READY-re-emitted-after-user-approval`. G6 tool call follows same turn.

**Enforcement**: absence of block in PR-creation turn -> all G6 tools forbidden. Block in earlier turn does NOT satisfy (mirrors §2B "waivers do not carry forward").

### G4. `routed-deferred-with-tracker-and-ask_user` requires both conditions

Every finding routed via this status requires BOTH:

1. Actual external tracker issue (GitHub issue, ADO work item, Linear ticket) created this turn with citable URL. NOT a session-todo, TODO comment, or "tracked internally" hand-wave.
2. Explicit `ask_user` approval in same turn naming the issue URL and confirming deferral.

### G5. C2 disposition enum (per finding)

`fixed | dismissed-source-grounded | routed-deferred-with-tracker-and-ask_user | routed-now-via-ask_user`. Every finding has a status; no orphans. `routed-now-via-ask_user` is for non-blocking findings surfaced for user decision; `routed-deferred-with-tracker-and-ask_user` is the only deferral form per G4.

### G6. Forbidden-tool enumeration (mirrors §1B)

Until `PRE-PR REVIEW COVERAGE` block emitted in current turn AND `pr-creation-status` reads `READY-pending-user-approval` or `READY-re-emitted-after-user-approval`, the agent MUST NOT call:

- `gh pr create` (any flags including `--draft`)
- `gh pr ready` / `gh pr ready --undo`
- `gh api` POST/PATCH/PUT targeting PR-creation/state-change endpoints
- `glab mr create`, `glab mr update --ready/--draft`
- `tea pr create`
- `az repos pr create`, `az repos pr update` (draft toggle)
- `git push` with merge-request/pull-request push options (`-o merge_request.create=*`, etc.)
- `git push <remote> HEAD:refs/for/*` (Gerrit)
- Any MCP-server tool whose intent is PR/MR creation or draft-state mutation
- Raw `curl`/`Invoke-WebRequest` to forge PR-creation/draft-state endpoints
- Any equivalent on any forge (Bitbucket, Gitea, SourceHut, Forgejo, Codeberg, Radicle)

Pattern: absence of block IS the enforcement. New PR-creation pathways extend by INTENT, not literal name. Flag gaps and propose additions.

### G7. Bootstrap exemption - narrow scope

PR is BOOTSTRAP-EXEMPT from §2D only if ALL of:

1. PR introduces a NEW mandatory gate not on `origin/<base>` pre-PR (verifiable via `git show`).
2. PR body includes literal `BOOTSTRAP-EXEMPTION: <gate-name>`.
3. PR includes ALL companion edits for gate to be operative post-merge.

**Modifications to existing gates are NOT bootstrap-exempt.** Only the introducing PR of a NEW gate qualifies.

**Token re-validation**: token MUST remain in PR body until merge. Removal (`gh pr edit --body`) revokes exemption; subsequent push triggers §2D normally. Track via `bootstrapTokenStatus` field (`not-applicable | present-in-body | removed-revokes-exemption`).

**All other gates still apply**: §1A, §1B, §2A, §2B, §2C. G7 exempts ONLY from §2D.

## What is user-waivable at this gate (and what isn't)

| Item | Waivable? | Conditions / floor |
| --- | --- | --- |
| Panel must run (G1) | **NO** | - |
| Must-fix=0 (G2) | **NO** | Individual findings may use G4; gate-level must-fix=0 stands. |
| Block emitted in PR-turn (G3) | **NO** | - |
| C2 disposition per finding (G5) | **NO** | - |
| Forbidden-tool list (G6) | **NO** | - |
| Bootstrap exemption (G7) | **NO** | Conditions either met or not. |
| Convergence model | **YES** | Floor: `threshold >= 75%`. `confidence-weighted >= 80%` also allowed. Record under `convergence-waive`. |
| Reviewer slate composition | **YES** | Floor (all simultaneous): >= 4 reviewers; >= 1 Claude + >= 2 GPT (>= 1 premium + >= 1 cross-version/codex) + >= 1 Gemini; >= 1 `rubber-duck` + >= 2 `code-review`; >= 1 heavy-tier. Record under `slate-waive`. Floor re-checked after every drop/replacement. |
| `routed-deferred` per finding | **YES with G4** | External tracker URL + same-turn `ask_user`. |

Items not in matrix: NOT waivable. If uncertain, treat as NOT waivable; escalate via `ask_user`.

## Intake questions

Bundle in one prompt before launching:

1. **Confirm base ref.** Default `origin/main` (or parent for stacked PRs). Resolve to SHA; record as `panelBaseSha`.
2. **Convergence model.** Default `unanimous`. User MAY downgrade per waive matrix.
3. **Reviewer slate confirmation.** Default = the active profile's slate (full = heavy slate below; lite = 3 cross-family light-tier per `active-profile.instructions.md`). User MAY adjust within floor.
4. **Pre-existing-issue context** (CONTEXT-ONLY, does NOT preempt findings). User may surface branch context notes. Reviewers receive as CONTEXT NOTES; prompt instructs: "if you still find the pattern, raise it; orchestrator routes via G5 flow." Prevents user-muting failure mode.

## Reviewer slate - capability-tier definition

Slate defined by capability tier + family + role, NOT hardcoded model name. Tier -> model mapping in `multi-model-review/current-model-registry.md`. Missing tier: fall back to highest-capability successor from same family; log under `slate-substitutions`.

**Default heavy slate (full profile: 6 reviewers, >= 3 families, satisfies floor; lite profile uses 3 cross-family light-tier instead)**:

| Slot | Tier id | Family | Role | Purpose |
| --- | --- | --- | --- | --- |
| 1 | `heavy-claude-xhigh` | Claude | `code-review` | Anchor; deep reasoning; cross-family diversity. |
| 2 | `heavy-gpt-premium` | GPT | `code-review` | Cross-family fresh eyes. |
| 3 | `heavy-gpt-codex` | GPT | `code-review` | Code-specialized angle. |
| 4 | `heavy-gpt-cross-version` | GPT | `code-review` | Within-family version triangulation. |
| 5 | `heavy-gemini-premium` | Gemini | `code-review` | Third-vendor diversity. |
| 6 | `heavy-claude-standard` | Claude | `rubber-duck` | Design/blind-spot critique. |

**Substitution**: unavailable tier -> highest-capability successor from same family per registry. Record `slateSubstitutions`.

**Slate-floor enforcement**: floor checked at every checkpoint (launch, after drop, after replacement, at synthesis). Break -> escalate via `ask_user` before proceeding.

## Reviewer prompt template (11-category Copilot-mirror)

Canonical template lives in `multi-model-review/pr-creation-mirror-prompt.md`. Every reviewer receives that template populated with: diff range, prior-commit-panel-dispositions (per Step 3a format), pre-existing-issue context from Intake Q4.

Categories (summary): 1. Bugs/logic errors, 2. Security, 3. Argument/input validation, 4. Resource lifecycle, 5. Documentation accuracy, 6. Accessibility, 7. UI framework binding pitfalls, 8. Performance, 9. Deprecated patterns, 10. Best practices/idiomaticness, 11. Copy-paste/refactor artifacts.

**Finding format**: `[severity: blocking | major | minor] <summary> - <file:line> - <mitigation>`

**Tooling discipline**: read-only inspection only. No `ask_user`, no file modifications, no sub-agents.

**REQUIRED final line**: `VERDICT: <READY_TO_IMPLEMENT | NEEDS_ANOTHER_ROUND>`

## Procedure

### Step 1. Determine invocation mode

Read canonical phase-state record:

```
invocation-mode:
  if pre-pr-push.md phase-state record present AND Step 5 hook fires this gate:
    -> "via-pre-pr-push-step-5"
    read isFirstReviewExposurePush, remoteExposureExists, baseRef from that record
  else (self-fire fallback):
    -> "self-fire-fallback"
    run inline open-PR check:
 - GitHub: gh pr list --head <branch> --state open --json number,isDraft
 - GitLab: glab mr list --source-branch <branch> --state opened
 - Gitea/Forgejo: tea pr list --state open --head <branch>
 - ADO: az repos pr list --source-branch <branch> --status active
 - other: equivalent command
    AND ask_user: "Is this push intended for PR review on <forge>?"
    no open PR AND user says no-review -> exit gate
    yes -> continue self-fire mode
```

Record `invocationMode` in LEDGER. `self-fire-fallback` is the safety net for missing `pre-pr-push.md` Step 5 hook.

### Step 2. Re-run-trigger detection (ancestry-based)

Compare current branch state against prior §2D run. Detect re-run triggers via ancestry semantics (NOT reflog):

```powershell
$priorHeadSha = <recorded prior-run headSha, or "none" for first run>
$currentHead = git rev-parse HEAD
$baseRef = <recorded prior-run baseRef, or current intake baseRef>
$currentBase = git rev-parse $baseRef
$priorBase = <recorded prior-run panelBaseSha, or "none">
$priorCommitCount = <recorded prior-run commit count, or 0>
$currentCommitCount = (git rev-list --count "$currentBase..HEAD")

$triggers = @()
if ($priorHeadSha -eq "none") {
    $triggers += "first-run"
} else {
    $isPriorAncestor = (git merge-base --is-ancestor $priorHeadSha HEAD 2>$null; $LASTEXITCODE -eq 0)
    if (-not $isPriorAncestor) { $triggers += "history-rewrite" }
    if ($priorBase -ne "none" -and $priorBase -ne $currentBase) { $triggers += "base-shift" }
    if ($priorCommitCount -gt 0 -and $currentCommitCount -lt $priorCommitCount) { $triggers += "commit-squash" }
    if ($priorHeadSha -ne $currentHead -and $isPriorAncestor) { $triggers += "net-new-commits" }
}
```

Record `reRunTriggers: [...]` in LEDGER (list; triggers CAN co-occur).

**Prior-commit-panel-dispositions carry-forward**: dispositions carry forward IF AND ONLY IF trigger set is exactly `["net-new-commits"]`. Any rewrite/squash/base-shift invalidates prior dispositions -> `"none - prior run invalidated by <trigger list>"`.

### Step 3. Context-budget circuit breaker

Estimate total session context before launch. Thresholds as % of orchestrator's runtime context window (default conservative 200K if unavailable):

```
window      = orchestrator max context window
sessionUsed = current context usage (all turns, not just panel output)
projected   = sessionUsed + 75K (panel estimate)
triggerPct  = projected / window
```

- **`triggerPct >= 0.60`** -> Step 3a compaction.
- **`triggerPct >= 0.85`** -> Step 3b escalation.
- **Mid-loop re-check**: re-compute between rounds. Crossing 0.85 mid-loop -> escalate immediately.

#### Step 3a. Compaction

Summarize per-commit panel outputs into `<session-state-folder>/panel-history-<branchName>.md`:

- Format: `theme | severity | status | citation-summary` (one line per finding)
- Example: `null-check-param-X | major | dismissed-source-grounded | "IFoo.cs documents non-null"`
- `citation-summary` truncated to ~80 chars but MUST be present (dedup depends on it).
- Replace full per-commit outputs in context with compacted summary.
- Pass as `prior-commit-panel-dispositions` in reviewer prompt.
- Record `compactionApplied: true`, `compactionArtifactPath`, `compactionFindingCount` in LEDGER.

#### Step 3b. Escalation

Post-compaction `triggerPct >= 0.85` -> escalate via `ask_user`:

1. Abort gate; start fresh session (recommended for large branches).
2. Accept degraded panel: drop to slate-floor minimum (4 reviewers). Record `degradedDueToContext: true`.
3. Split branch into smaller stacked PR.

### Step 4. Resolve and record sweep SHAs

```powershell
$BaseRef = <from Step 1>
$BaseSha = git rev-parse $BaseRef
$HeadSha = git rev-parse HEAD
$CommitCount = (git rev-list --count "$BaseSha..HEAD")
```

Record `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount` in §2D phase-state. Read by Step 2 on subsequent invocations.

### Step 5. Launch the panel in parallel

Per `multi-model-review/procedure.md` parallel-launch protocol. All N reviewers launched same response (background mode) with the 11-category prompt populated with: diff range, prior-commit-panel-dispositions, context notes from Intake Q4.

Slate from `current-model-registry.md` per floor + substitution rule. Record `slateActuallyRun`, `slateSubstitutions`.

**Slate-floor checkpoint #1**: BEFORE launching, verify floor. Substitution broke floor -> escalate via `ask_user`.

### Step 6. Wait for reviewers (with per-reviewer scheduled timeout)

Per-reviewer timeout: **10 minutes** from launch (scheduled check, NOT polling).

If no response by launch+10min:
1. Send `write_agent` "Status check - emit findings and VERDICT now".
2. Wait 2 more minutes (single check at launch+12min).
3. Still no response: treat as dropped (Step 7).

### Step 7. Reviewer-failure handling (cumulative-drops semantics)

Dropped count is CUMULATIVE events (including replaced), not unfilled slots.

| Cumulative drops | Action |
| --- | --- |
| 0 | Proceed to synthesis. |
| 1 | Launch replacement (highest-capability successor, same family+tier). Replacement also drops -> 2-drop. |
| 2 | Escalate `ask_user`: (a) wait 10 min, (b) proceed degraded if floor holds, (c) abort. |
| >= 3 | Hard escalate; cannot proceed without user + floor satisfied. |

**Slate-floor checkpoint #2-N**: re-verify after every drop and replacement. Floor breaks -> escalate immediately.

If substitution cannot find successor (family+tier exhausted) -> escalate via `ask_user` BEFORE retrying.

Record `droppedReviewers`, `replacementReviewers`, `slateFloorRechecks` in LEDGER.

### Step 8. Synthesize + apply convergence + C2 routing

Per `multi-model-review/procedure.md` synthesis (dedup by theme, rank severity, agreement count). Apply convergence model. C2-route every finding per G5 enum.

`routed-deferred-with-tracker-and-ask_user` requires G4 conditions IN THIS TURN. G4 not met -> finding must be `fixed` or `dismissed-source-grounded`.

### Step 9. Apply fixes for must-fix findings (with branch-level iteration cap)

Every `blocking` finding resolved per G2's three paths.

For `fixed`: apply change, re-stage, re-run build+tests, re-emit `POST-CODE-CHANGE LEDGER` per `review-workflow-gates-sweeps.md` §2B. After fix commit, re-run panel from Step 2.

**Branch-level iteration cap**: track `fixIterationCount` in §2D phase-state.

| `fixIterationCount` | Action |
| --- | --- |
| <= 3 | Proceed with re-run. |
| 4+ | Hard escalate `ask_user`: (a) authorize N more iterations, (b) accept remaining as G4-compliant `routed-deferred-with-tracker-and-ask_user`, (c) split branch. |

Prevents unbounded fix-introduces-finding cycling. Round-level max-loop (5 per `multi-model-review/procedure.md`) covers within-invocation; `fixIterationCount` covers across-invocation.

### Step 10. Emit the `PRE-PR REVIEW COVERAGE` block (initial emission)

Mandatory at end of synthesis, BEFORE AGENTS `gh pr create` user-approval. Format:

```
PRE-PR REVIEW COVERAGE
  emission-phase: initial-pending-user-approval
  invocation-mode: <via-pre-pr-push-step-5 | self-fire-fallback>
  re-run-triggers: <[trigger, ...] - [default: ["first-run"]]>
  panel-base-ref: <baseRef>
  panel-base-sha: <40-char SHA>
  panel-head-sha: <40-char SHA>
  panel-commit-count: <N>
  diff-scope: <baseSha>..<headSha> (<N> files, +<X>/-<Y> lines)
  slate:
 - slot 1: <tier-id> <family> <role>: <model> [substituted from <requested-model>: <reason>] OR [no substitution]
 - ...
  slate-substitutions: <[] - [default: []]>
  slate-floor-rechecks: <[{checkpoint, satisfied, ...}] - [default: [{launch, true}, {synthesis, true}]]>
  slate-waive: <"no waive" - [default: "no waive"]>
  convergence-model: <unanimous | threshold-N% | confidence-weighted-N%>
  convergence-waive: <"no waive" - [default: "no waive"]>
  rounds: <K>
  dropped-reviewers: <[] - [default: []]>
  replacement-reviewers: <[] - [default: []]>
  degraded-due-to-reviewer-loss: <true | false - [default: false]>
  degraded-due-to-context: <true | false - [default: false]>
  context-budget:
    window-size: <orchestrator window in tokens>
    session-used-at-panel-launch: <tokens>
    trigger-pct-at-launch: <0.0-1.0>
    compaction-applied: <true | false>
    compaction-artifact-path: <path or "n/a">
    mid-loop-rechecks: <[{round, trigger-pct}] - [default: []]>
  prior-commit-panel-dispositions: <"none - <reason>" or compacted list>
  fix-iteration-count: <N - [default: 0]>
  fix-iteration-cap: <3 or user-authorized override>
  findings: <total raw>, dedupe'd to <M unique themes>
  resolution (every finding has a status):
 - [<category 1-11>] <severity> [<reviewer model>]: <finding summary>: <status>: <citation>
 - ...
  must-fix-blocking-findings-resolved: <K of K>
  routed-deferred-with-tracker-and-ask_user:
 - <finding> -> <tracker URL> (ask_user approval: <call ref>)
 - ... - [default: []]
  bootstrap-token-status: <not-applicable | present-in-body | removed-revokes-exemption - [default: not-applicable]>
  pr-creation-status: <READY-pending-user-approval | BLOCKED - <N> must-fix unresolved | BLOCKED - slate-floor violated | BLOCKED - context-budget exceeded>
  subagent_ask_user_calls=0 (orchestrator-only routing verified per AGENTS.md cross-cutting rule)
```

`pr-creation-status: READY-pending-user-approval` required to proceed to Step 11.

### Step 11. AGENTS `gh pr create` user-approval flow

Per `AGENTS.md` `gh pr create` section: present PR title + body + target branch via `ask_user`. User approves/edits/rejects. For non-GitHub forges, mirror same flow before G6 tool.

### Step 12. Re-emit the `PRE-PR REVIEW COVERAGE` block in the PR-creation turn

After user approval, BEFORE G6 tool, re-emit with:

- `emission-phase: ready-re-emitted-after-user-approval`
- Same-state re-check:
 - Step 2 trigger detection: if triggers differ from prior-run -> restart at Step 2.
 - `git rev-parse HEAD` still matches `panelHeadSha`.
 - `git rev-parse <baseRef>` still matches `panelBaseSha`.
- `pr-creation-status: READY-re-emitted-after-user-approval`

Any same-state check fails -> restart at Step 2.

### Step 13. Invoke the G6 tool

Only after Step 12 emits `READY-re-emitted-after-user-approval` in same turn.

## State to record in canonical session todos

Per `AGENTS.md` *Phase-state tracking convention*:

- `invocationMode` - Step 1.
- `reRunTriggers` - list, Step 2.
- `panelBaseRef` / `panelBaseSha` / `panelHeadSha` / `panelCommitCount` - Step 4.
- `slateActuallyRun` - `[{slot, tier-id, family, role, model}]`.
- `slateSubstitutions` - `[{slot, requested-tier, requested-model, substituted-model, reason}]`.
- `slateFloorRechecks` - `[{checkpoint, satisfied, ...}]`.
- `slateWaive` / `convergenceWaive` - `"no waive"` or user-quote.
- `convergenceModelUsed` - `unanimous | threshold-N | confidence-weighted-N`.
- `panelRounds` - rounds before convergence.
- `panelConvergence` - `converged-unanimous | converged-threshold | converged-confidence-weighted | escalated-to-user-after-max-loop`.
- `droppedReviewers` / `replacementReviewers` - Step 7.
- `degradedDueToReviewerLoss` / `degradedDueToContext` - booleans.
- `contextBudget` - `{windowSize, sessionUsedAtPanelLaunch, triggerPctAtLaunch, compactionApplied, compactionArtifactPath, midLoopRechecks}`.
- `priorCommitPanelDispositions` - compacted string or `"none - <reason>"`.
- `fixIterationCount` / `fixIterationCountCap` - Step 9.
- `mustFixFindings` / `mustFixResolved` - must be equal for READY status.
- `bootstrapTokenStatus` - `not-applicable | present-in-body | removed-revokes-exemption`.
- `prCreationStatus` - `READY-pending-user-approval | READY-re-emitted-after-user-approval | BLOCKED-*`.

Read from session todos when emitting block; never infer from memory.

## §2B carve-out forward-reference

When the future `review-workflow-gates-sweeps.md` §2B edit lands (tightening `post-code-change-panel` from `ran | N/A - reason | user-waived` to `ran | N/A - reason`), preserve the existing N/A carve-out for pure-recommit / rebase with zero behavioral delta vs. previously-panelled artifact (existing carve-out at `review-workflow-gates-sweeps.md` ~line 297). Removing `user-waived` is correct; removing the N/A carve-out would be a regression.

## Cross-cutting fit - companion edits required for §2D to be operative

Per G7's "ALL companion edits required" rule, the introducing PR MUST include ALL of:

- **`AGENTS.md` `gh pr create` section** - require `PRE-PR REVIEW COVERAGE` block per G3.
- **`AGENTS.md` cross-cutting hard-gate bullets** - new bullet referencing §2D.
- **`pre-pr-push.md` Step 5** - invokes this playbook. Adds `preCreationReviewStatus` to state predicate.
- **`review-workflow-gates-sweeps.md` §2D** - hard-gate spec (LEDGER row, G1-G7 summary).
- **`multi-model-review/current-model-registry.md`** - capability-tier mappings.
- **This playbook** (`pre-pr-creation-review.md`).

Missing any -> §2D non-operative post-merge -> G7 bootstrap-exemption invalid.

## Cross-cutting fit - gates §2D plugs alongside

- **`multi-model-review.md` + sub-files** - panel mechanics; `current-model-registry.md` decouples tier ids from model names.
- **`post-code-change.md` §3** - per-commit sister gate (lighter). This gate is branch-wide heavy pass; consumes per-commit dispositions via Step 3a compaction.

## Why this gate exists

LLM-based PR reviewers consistently surface known pattern categories. Running our own multi-model panel pre-PR shifts findings from "review comment after PR opens" to "blocking finding before PR opens"; same work, dramatically lower visibility cost.

When a Copilot-bot finding lands on a PR that PASSED §2D, follow `review-workflow-gates-sweeps.md` §2 root-cause analysis and propose a catalog/prompt addition in the next `post-pr-review.md` cycle. The gate improves via this feedback loop.

Cost: >= 4 reviewers x ~10-15K tokens each (40-75K per run). Step 3 circuit-breaker prevents context exhaustion on large branches.
