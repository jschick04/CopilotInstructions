# Playbook: Pre-PR-creation review (§2D)

## Purpose

Mandatory multi-model code-review panel on the FULL branch diff (`<base>..HEAD`) before any PR is created or made review-visible. Mirrors the categories an LLM-based PR reviewer (GitHub Copilot's PR-review feature and similar bot reviewers) would surface — runs locally pre-push so findings are caught and fixed BEFORE reviewers see them, not after.

Sister to `post-code-change.md` §3 (per-commit panel, lightweight). This is the branch-wide heavy pass once per PR-creation transition.

## Hard gates

### G1. Panel must run — not user-waivable

Cannot be skipped via `ask_user` quote. The only exit is convergence with must-fix=0.

### G2. Must-fix=0 — not user-waivable

Every reviewer-flagged `blocking` finding must be resolved via one of three G5 paths:

- `fixed` — applied as a change.
- `dismissed-source-grounded` — refuted by source evidence (file:line, doc URL, RFC, ADR, spec section) addressing the finding's claim. Hand-wave "out of scope" is invalid.
- `routed-deferred-with-tracker-and-ask_user` — see G4.

### G3. `PRE-PR REVIEW COVERAGE` block emitted in the PR-creation turn — not user-waivable

The block (format below) MUST appear in the same chat turn as the G6 PR-creation tool call.

Because the AGENTS `gh pr create` flow requires an intervening `ask_user` for title/body approval, the block is emitted twice:

1. **Initial** (turn N): at end of Step 7 with `pr-creation-status: READY-pending-user-approval`.
2. **Re-emitted** (turn N+1): in the PR-creation tool-call turn, after the user-approval `ask_user` returns, with same-state re-check (`git rev-parse HEAD` matches recorded `panelHeadSha`; `git merge-base --is-ancestor <panelHeadSha> HEAD` returns true; `git rev-parse <baseRef>` matches `panelBaseSha`). If any check fails, restart at Step 2. Block status: `READY-re-emitted-after-user-approval`.

Absence of the appropriate block in the PR-creation turn → all G6 tools are forbidden. Block being present only in an earlier turn does NOT satisfy this gate.

### G4. `routed-deferred-with-tracker-and-ask_user` requires both:

1. An actual external tracker issue (GitHub issue, ADO work item, Linear ticket, etc.) created in the same turn with a citable URL — NOT a session-todo, NOT a `TODO` / `FIXME` code comment, NOT a "tracked internally" hand-wave.
2. Explicit `ask_user` approval in the same turn naming the issue URL and confirming deferral.

### G5. C2 disposition enum

Per finding: `fixed | dismissed-source-grounded | routed-deferred-with-tracker-and-ask_user | routed-now-via-ask_user`. Every finding has a status; no orphans.

### G6. Forbidden-tool enumeration (mirrors §1B)

Until the G3 block from Step 9 (the **re-emitted** block in the PR-creation tool-call turn) is present in the current turn with `pr-creation-status: READY-re-emitted-after-user-approval`, the agent MUST NOT call any of the tools below. The initial-emission status (`READY-pending-user-approval` from Step 7) is NOT sufficient — it indicates the panel converged but the user-approval step + same-state re-check have not yet happened. The `DRY-RUN-INFO-ONLY` status from the direct-invocation path is NEVER sufficient.

- `gh pr create` (any flags incl. `--draft`)
- `gh pr ready`, `gh pr ready --undo`
- `gh api` POST/PATCH/PUT targeting `/repos/*/pulls`, `/repos/*/pullrequests`, or any PR-creation / draft-state-mutation endpoint
- `glab mr create`, `glab mr update --ready`/`--draft`
- `tea pr create`
- `az repos pr create`, `az repos pr update` (toggling draft)
- `git push` with `-o merge_request.create=*` / `-o pull_request.create=*` / `-o topic=*` auto-creating MR
- `git push <remote> HEAD:refs/for/*` (Gerrit)
- Any MCP-server tool whose intent is PR/MR creation or draft-state mutation on any forge
- Raw `curl`/`Invoke-WebRequest` to forge REST/GraphQL APIs posting PR-creation/draft-state endpoints
- Equivalents on any forge not enumerated above (Bitbucket, Gitea, Forgejo, Codeberg, Radicle, etc.)

Pattern: absence of the block IS the enforcement. New PR-creation pathways extend the list by intent, not literal name match.

### G7. Bootstrap exemption — narrow scope

A PR is BOOTSTRAP-EXEMPT from §2D only if ALL of:

1. The PR introduces a NEW mandatory gate that did not exist on `origin/<base>` pre-PR (verifiable: `git show origin/<base>:.github/playbooks/<gate-file>.md` does not exist or doesn't contain the gate definition).
2. The PR body includes the literal token `BOOTSTRAP-EXEMPTION: <gate-name>` (e.g., `BOOTSTRAP-EXEMPTION: §2D pre-PR-creation review gate`).
3. The PR includes ALL companion edits required for the new gate to be operative post-merge.

PRs that modify, tighten, loosen, or refactor an existing gate are NOT bootstrap-exempt — they go through the gate they're modifying. If the bootstrap token is removed from the PR body before merge, the exemption is revoked and subsequent pushes trigger §2D normally.

## Waive matrix

| Item | Waivable with `ask_user` quote? | Conditions / floor |
| --- | --- | --- |
| G1 (panel must run) | NO | — |
| G2 (must-fix=0) | NO | Individual findings may use G4 `routed-deferred-with-tracker-and-ask_user`; the gate-level must-fix=0 requirement stands. |
| G3 (block in PR-creation turn) | NO | — |
| G5 (disposition per finding) | NO | — |
| G6 (forbidden tools) | NO | — |
| G7 conditions | NO | Either all 3 conditions met or exemption doesn't apply. |
| Convergence model (default `unanimous`) | YES | Floor: `threshold ≥75%` or `confidence-weighted ≥80%`. Recorded under `convergence-waive`. Must-fix=0 still applies. |
| Slate composition | YES | Floor: ≥4 reviewers; ≥1 Claude family + ≥2 GPT family (one premium + one cross-version-or-codex); ≥1 `rubber-duck` role + ≥2 `code-review` role; ≥1 heavy-tier. Recorded under `slate-waive`. Re-checked after every drop/replacement. |
| Individual finding via G4 routed-deferred | YES (with G4) | External tracker URL + same-turn `ask_user` approval. |

Items not in the matrix are NOT waivable.

## Reviewer slate (default heavy)

| Slot | Model | Family | Role |
| --- | --- | --- | --- |
| 1 | `claude-opus-4.7-xhigh` | Claude | `code-review` |
| 2 | `gpt-5.5` | GPT | `code-review` |
| 3 | `gpt-5.3-codex` | GPT | `code-review` |
| 4 | `gpt-5.4` | GPT | `code-review` |
| 5 | `claude-opus-4.7` | Claude | `rubber-duck` |

**Substitution rule**: if a model is unavailable (deprecated, API down, removed from runtime), substitute the highest-capability successor from the same family. Record under `slate-substitutions: [{slot, requested, substituted, reason}]`. Slate-floor (from waive matrix) re-checked after every substitution.

Liberal expansion encouraged for risky / cross-cutting / unfamiliar-area branches.

## Reviewer prompt

Use `multi-model-review/pr-creation-mirror-prompt.md` (the shared 11-category Copilot-mirror template). Consumer-specific substitutions: `<baseSha>`, `<headSha>`, `<repo-path>`, round context (when iterating), prior-commit panel dispositions (from `post-code-change.md` §3 ledgers when present), Intake Q4 context notes.

## Procedure

### Step 1. Determine invocation mode

This gate does NOT classify whether the push is review-targeting — that's `pre-pr-push.md`'s job.

- **Normal path** — If `pre-pr-push.md` phase-state record present AND its Step 5 hook fires this gate → `invocationMode: via-pre-pr-push-step-5`; read `isFirstReviewExposurePush`, `remoteExposureExists`, `baseRef` from that record. Continue to Step 2.

- **Direct invocation path** (no `pre-pr-push.md` state present) → `invocationMode: direct-invocation-dry-run-only`. This path is for diagnostic / dry-run / education-mode use ONLY; it CANNOT emit a `READY-*` status and CANNOT unblock G6 PR-creation tools.

  Run a forge-specific open-PR check (so the dry-run is informative):
  - GitHub: `gh pr list --head <branch> --state open`
  - GitLab: `glab mr list --source-branch <branch> --state opened`
  - Gitea / Forgejo / Codeberg: `tea pr list --state open --head <branch>`
  - Azure DevOps: `az repos pr list --source-branch <branch> --status active`
  - Bitbucket / SourceHut / Radicle / other forges: equivalent command, or `ask_user` for forge-specific guidance.

  Then `ask_user` with three options:
  1. **STOP and run `pre-pr-push.md` first** (recommended) — this is the normal entry point. §2D fires from there via Step 5. This option exits §2D immediately so `pre-pr-push.md` can run its prerequisite gates (§4.2 push-credential verification, per-commit audit, branch-wide sweep, branch-wide LPA) before §2D is re-invoked.
  2. **Continue as DRY-RUN** — §2D runs the panel for informational purposes; emits a `PRE-PR REVIEW COVERAGE` block with `pr-creation-status: DRY-RUN-INFO-ONLY`. **This status does NOT unblock G6 tools.** The agent cannot proceed to `gh pr create` / `gh pr ready` / equivalents on this invocation. To actually create a PR, the agent must subsequently run `pre-pr-push.md` (which will re-fire §2D from Step 5).
  3. **Abort §2D** — exit without running the panel; this is the correct choice if the invocation was unintended.

  **`direct-invocation-dry-run-only` MUST NOT emit `READY-pending-user-approval` or `READY-re-emitted-after-user-approval`.** If the orchestrator attempts to emit one of those statuses while `invocationMode == direct-invocation-dry-run-only`, that is a workflow violation per §1B. This rule prevents the bypass where direct invocation circumvents `pre-pr-push.md`'s OTHER required gates.

  **Collect `baseRef` explicitly in this mode** (since there's no `pre-pr-push.md` state to read from): `ask_user` for `baseRef` (default `origin/main`, or the parent branch for stacked PRs) BEFORE proceeding to Step 2. Resolve the SHA via `git rev-parse <baseRef>` and record as `panelBaseSha`. If the SHA cannot be resolved, escalate via `ask_user` immediately.

Record `invocationMode` and `baseRef` in the phase-state record.

### Step 2. Re-run-trigger detection (ancestry-based)

When a prior §2D run exists on this branch, detect what changed since:

```powershell
$priorHeadSha = <prior-run panelHeadSha, or "none">
$baseRef = <prior-run panelBaseRef, or intake baseRef>
$priorBase = <prior-run panelBaseSha, or "none">
$priorCommitCount = <prior-run panelCommitCount, or 0>
$currentBase = git rev-parse $baseRef
$currentHead = git rev-parse HEAD
$currentCommitCount = (git rev-list --count "$currentBase..HEAD")

$triggers = @()
if ($priorHeadSha -eq "none") {
    $triggers += "first-run"
} else {
    git merge-base --is-ancestor $priorHeadSha HEAD 2>$null
    $isPriorAncestor = ($LASTEXITCODE -eq 0)
    if (-not $isPriorAncestor)                          { $triggers += "history-rewrite" }
    if ($priorBase -ne "none" -and $priorBase -ne $currentBase) { $triggers += "base-shift" }
    if ($priorCommitCount -gt 0 -and $currentCommitCount -lt $priorCommitCount) { $triggers += "commit-squash" }
    if ($priorHeadSha -ne $currentHead -and $isPriorAncestor)   { $triggers += "net-new-commits" }
}
```

`history-rewrite` covers force-push, `git commit --amend`, and interactive rebase that rewrites. `re-run-triggers` is a LIST (triggers can co-occur).

**Prior-commit-panel-dispositions carry-forward**: dispositions from a previous run carry forward IF AND ONLY IF `re-run-triggers == ["net-new-commits"]`. Any rewrite / squash / base shift invalidates prior dispositions.

Record `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `reRunTriggers` in the phase-state record.

### Step 3. Launch the panel in parallel

Per `multi-model-review/procedure.md` parallel-launch protocol. All reviewers launched in the same response (background mode), with the shared `pr-creation-mirror-prompt.md` template populated.

**Slate-floor checkpoint #1**: verify floor holds BEFORE launch. If a substitution broke floor, escalate via `ask_user`.

### Step 4. Wait for reviewers; handle drops

Per `multi-model-review.md` hard gates (notification-driven; no polling). Per-reviewer scheduled timeout: 10 minutes. On timeout: `write_agent` "status check"; +2 min grace; treat as dropped if still no response.

Cumulative drop events:

- 0 → proceed.
- 1 → launch replacement per substitution rule (same family, highest-capability successor).
- 2 → escalate via `ask_user`: wait additional 10 min / proceed degraded if slate-floor still holds / abort.
- ≥3 → hard escalate; cannot proceed without user explicitly authorizing degraded mode AND floor satisfied.

**Slate-floor checkpoint #2-N**: re-verify floor after every drop and every replacement. Floor break → escalate immediately regardless of drop-count row.

### Step 5. Synthesize + apply convergence + C2 routing

Per `multi-model-review/procedure.md` synthesis (dedup by theme, severity ranking, agreement count). Apply chosen convergence model. C2-route every finding per G5.

`routed-deferred-with-tracker-and-ask_user` requires G4 conditions in this turn. If not met, the finding is `fixed` or `dismissed-source-grounded` only.

### Step 6. Apply fixes for must-fix findings (with branch-level iteration tracking)

Every reviewer-flagged `blocking` finding resolved via G2's three paths.

For `fixed` findings: apply change in this turn, re-stage, re-run build + tests, emit `POST-CODE-CHANGE LEDGER` per `review-workflow-gates.md` §2B, then re-run the panel from Step 2.

**Before re-launching the panel from Step 2 after a `fixed` finding, increment `fixIterationCount` in the §2D phase-state record.** If `fixIterationCount > fixIterationCountCap` (default `3`), STOP and escalate via `ask_user` for one of:

1. Authorize an override of `fixIterationCountCap` to a higher value (record the new cap under `fix-iteration-count-cap` in the next LEDGER emission).
2. Route remaining must-fix findings via G4 `routed-deferred-with-tracker-and-ask_user` (one tracker + same-turn `ask_user` per finding).
3. Split the branch / reduce scope.
4. Abort the gate.

Do NOT re-enter Step 2 until the user has authorized one of these paths. Reset `fixIterationCount` to `0` only on `re-run-triggers: ["first-run"]` (fresh branch) or on successful gate completion (`READY-re-emitted-after-user-approval` final emission).

The round-level max-loop (5 per `multi-model-review/procedure.md`) covers within-panel cycling — that's a different counter from `fixIterationCount`, which tracks fix-then-re-panel CYCLES across panel invocations on the same branch. Full automated escalation handling is deferred to `pre-pr-creation-review/implementation-roadmap.md` priority 3; the count-tracking field + the prose escalation rule are implemented in v4 so the gate's bounded-iteration guarantee has backing state.

### Step 7. Emit `PRE-PR REVIEW COVERAGE` block (initial)

Mandatory before invoking the AGENTS user-approval flow. Format:

```
PRE-PR REVIEW COVERAGE
  emission-phase: initial-pending-user-approval
  invocation-mode: <via-pre-pr-push-step-5 | direct-invocation-dry-run-only>
  re-run-triggers: <[trigger, ...]>
  panel-base-ref: <baseRef>
  panel-base-sha: <40-char SHA>
  panel-head-sha: <40-char SHA>
  panel-commit-count: <N>
  diff-scope: <baseSha>..<headSha> (<N> files, +<X>/-<Y> lines)
  slate:
    - slot 1: <model> <family> <role> [substituted from <requested>: <reason>]
    - ...
  slate-substitutions: <[] or list>
  slate-waive: <"no waive" or user-quote>
  convergence-model: <unanimous | threshold-N% | confidence-weighted-N%>
  convergence-waive: <"no waive" or user-quote>
  rounds: <K>
  fix-iteration-count: <N — incremented per Step 6 fix-then-re-run cycle; 0 for first run>
  fix-iteration-count-cap: <3 default, or user-authorized override>
  dropped-reviewers: <[] or list>
  replacement-reviewers: <[] or list>
  prior-commit-panel-dispositions: <"none — <reason>" or compacted list>
  findings: <total raw>, dedupe'd to <M themes>
  resolution (every finding has a status):
    - [<category 1-11>] <severity> [<reviewer>]: <finding>: <status>: <citation>
    - ...
  must-fix-blocking-findings-resolved: <K of K>
  routed-deferred-with-tracker:
    - <finding> → <tracker URL> (ask_user: <call ref>)
    - ... (default: [])
  bootstrap-token-status: <not-applicable | present-in-body | removed-revokes-exemption>
  pr-creation-status: <READY-pending-user-approval | READY-re-emitted-after-user-approval | DRY-RUN-INFO-ONLY | BLOCKED — <reason>>
  subagent_ask_user_calls=0 (per AGENTS.md)
```

### Step 8. AGENTS user-approval

Per AGENTS.md `gh pr create` section: present PR title + body + base via `ask_user`. User approves / edits / rejects.

For non-GitHub forges, mirror the same user-approval flow before invoking the equivalent G6 tool.

### Step 9. Re-emit the block after approval

In the PR-creation tool-call turn (after Step 8 `ask_user` returns):

- Re-run Step 2's same-state checks. If any fails (new commits, force-push, base shift since initial emission), restart at Step 2.
- Re-emit block with `emission-phase: ready-re-emitted-after-user-approval`, `pr-creation-status: READY-re-emitted-after-user-approval`.

### Step 10. Invoke the G6 tool

Only after Step 9's re-emitted block in the same turn.

## State to record in canonical session todos

Per `AGENTS.md` *Phase-state tracking convention*:

`invocationMode`, `reRunTriggers`, `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `slateActuallyRun`, `slateSubstitutions`, `slateWaive`, `convergenceModelUsed`, `convergenceWaive`, `panelRounds`, `fixIterationCount`, `fixIterationCountCap`, `panelConvergence`, `droppedReviewers`, `replacementReviewers`, `priorCommitPanelDispositions`, `mustFixFindings`, `mustFixResolved`, `bootstrapTokenStatus`, `prCreationStatus`.

Read these back from canonical session todos when emitting `PRE-PR REVIEW COVERAGE`; never infer from memory.

## §2B carve-out forward-reference

When the future `review-workflow-gates.md` §2B edit lands (tightening `post-code-change-panel` from `ran | N/A — reason | user-waived` to `ran | N/A — reason`), preserve the existing N/A carve-out for pure-recommit / rebase with zero behavioral delta vs. previously-panelled artifact (~line 297). Removing `user-waived` is correct; removing the N/A carve-out would be a regression.

## Cross-cutting fit — companion edits required (G7 condition 3)

The introducing PR for §2D MUST include ALL of:

- This playbook (`pre-pr-creation-review.md`).
- `multi-model-review/pr-creation-mirror-prompt.md` — shared 11-category prompt.
- `pre-pr-creation-review/implementation-roadmap.md` — deferred-features document.
- `AGENTS.md` `gh pr create` section — extended to require G3 block emissions before user-approval.
- `AGENTS.md` cross-cutting hard-gate bullets — new bullet referencing §2D.
- `pre-pr-push.md` Step 5 — invokes this playbook for review-targeting pushes. Adds `preCreationReviewStatus` field to the state predicate.
- `review-workflow-gates.md` §2D — LEDGER row + G1-G7 enforcement summary.
- `.github/playbooks/manifest.yaml` — registers `pre-pr-creation-review`.

Missing any of these → §2D is non-operative post-merge → G7 bootstrap exemption invalid.

## Future enhancements (deferred)

See `pre-pr-creation-review/implementation-roadmap.md` for design notes on: capability-tier registry indirection (model-fragility insurance), context-budget circuit breaker (1M-context-cap protection), branch-level fix-iteration cap, compaction format with citation preservation, forge-agnostic state field, automated slate-floor re-check infrastructure, automated same-state re-check infrastructure.

Each ships in a follow-up PR triggered by first real-world failure or explicit prioritization.

## Why this gate exists

LLM-based PR reviewers consistently surface a known set of pattern categories on every PR. Patching the static-pattern catalog reactively after each PR is whack-a-mole — the deterministic patterns get caught faster but the LLM-judgment patterns (doc-impl divergence, comment-promises-behavior-code-doesn't-deliver, hardcoded ARIA, framework-binding stale-render, attach-without-detach, etc.) need an LLM in the loop to catch.

Running our own multi-model panel pre-PR with the same category coverage shifts those findings from "review comment after PR opens" to "blocking finding before PR opens". The work to fix is the same; the visibility cost (reviewer time, PR thread churn, CI cycles, force-push pollution) is dramatically lower.

When a Copilot-bot PR-review finding lands on a PR that PASSED §2D, treat it as evidence the 11-category prompt or the per-commit catalog has a gap. Follow `review-workflow-gates.md` §2 root-cause analysis and propose an addition to the §2.5 catalog or the prompt template in the next `post-pr-review.md` cycle. The §2D gate improves via this feedback loop.
