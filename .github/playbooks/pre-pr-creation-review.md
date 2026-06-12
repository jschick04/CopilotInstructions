# Playbook: Pre-PR-creation review (§2D)
<!-- read-receipt-token: b339bc16 -->

## Purpose

Mandatory multi-model code-review panel on the FULL branch diff (`<base>..HEAD`) before any PR is created or made review-visible. Mirrors the categories an LLM-based PR reviewer would surface - runs locally pre-push so findings are caught BEFORE reviewers see them. Sister to `post-code-change.md` §3 (per-commit panel, lightweight).

## Hard gates

### G1. Panel must run - not user-waivable

Cannot be skipped via `ask_user` quote. Only exit: convergence with must-fix=0.

### G2. Must-fix=0 - not user-waivable

Every reviewer-flagged `blocking` finding must be resolved via one of three G5 paths:

- `fixed` - applied as a change.
- `dismissed-source-grounded` - refuted by source evidence (file:line, doc URL, RFC, ADR, spec section) addressing the finding's claim. Hand-wave "out of scope" is invalid.
- `routed-deferred-with-tracker-and-ask_user` - see G4.

### G3. `PRE-PR REVIEW COVERAGE` block emitted in the PR-creation turn - not user-waivable

The block (format in Step 7) MUST appear in the same chat turn as the G6 PR-creation tool call.

Because the AGENTS `gh pr create` flow requires an intervening `ask_user` for title/body approval, the block is emitted twice:

1. **Initial** (turn N): at end of Step 7 with `pr-creation-status: READY-pending-user-approval`.
2. **Re-emitted** (turn N+1): in the PR-creation tool-call turn, after user-approval `ask_user` returns, with same-state re-check (`git rev-parse HEAD` matches `panelHeadSha`; `git merge-base --is-ancestor <panelHeadSha> HEAD` true; `git rev-parse <baseRef>` matches `panelBaseSha`). Any check fails: restart at Step 2. Status: `READY-re-emitted-after-user-approval`.

Absence of block in PR-creation turn -> all G6 tools forbidden. Block in earlier turn does NOT satisfy.

### G4. `routed-deferred-with-tracker-and-ask_user` requires both:

1. Actual external tracker issue (GitHub issue, ADO work item, Linear ticket) created same turn with citable URL - NOT a session-todo, NOT a `TODO`/`FIXME` code comment, NOT "tracked internally".
2. Explicit `ask_user` approval in same turn naming the URL and confirming deferral.

### G5. C2 disposition enum

Per finding: `fixed | dismissed-source-grounded | routed-deferred-with-tracker-and-ask_user | routed-now-via-ask_user`. Every finding has a status; no orphans.

### G6. Forbidden-tool enumeration (mirrors §1B)

Until BOTH of these are present in the current turn, the agent MUST NOT call any tool below:

1. The G3 block from Step 9 (the **re-emitted** `PRE-PR REVIEW COVERAGE` block) with `pr-creation-status: READY-re-emitted-after-user-approval`. The initial-emission status (`READY-pending-user-approval`) is NOT sufficient - user-approval + same-state re-check have not happened. `DRY-RUN-INFO-ONLY` is NEVER sufficient.
2. The `PATTERN PREFLIGHT` block (re-emitted in Step 9; computed in Step 2.5) against current `panelHeadSha` + current `catalogRevision`/`fpRegistryRevision`. MAY use documented skip statuses (`catalog: not-yet-built`, `catalog: empty-battery`, `catalog: skipped-bootstrap`, `catalog: skipped-no-production-diff`); block must be PRESENT regardless. Additionally, the re-emitted `PRE-PR REVIEW COVERAGE` block's `catalog-revision` / `fp-registry-revision` / `pattern-preflight-skip-status` fields MUST be populated; absence or `<unset>` fails the gate.

Forbidden tools:

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
- Equivalents on any forge not enumerated (Bitbucket, Gitea, Forgejo, Codeberg, Radicle, etc.)

Pattern: absence of block IS the enforcement. New pathways extend by intent, not literal name.

### G7. Bootstrap exemption - narrow scope

PR is BOOTSTRAP-EXEMPT from §2D only if ALL of:

1. PR introduces a NEW mandatory gate not on `origin/<base>` pre-PR (verifiable: `git show origin/<base>:.github/playbooks/<gate-file>.md` does not exist or lacks the gate definition).
2. PR body includes literal `BOOTSTRAP-EXEMPTION: <gate-name>`.
3. PR includes ALL companion edits for gate to be operative post-merge.

PRs that modify/tighten/loosen/refactor an existing gate are NOT bootstrap-exempt. If token removed from PR body before merge, exemption revoked; subsequent pushes trigger §2D normally.

## Waive matrix

| Item | Waivable? | Conditions / floor |
| --- | --- | --- |
| G1 (panel must run) | NO | - |
| G2 (must-fix=0) | NO | Individual findings may use G4; gate-level must-fix=0 stands. |
| G3 (block in PR-creation turn) | NO | - |
| G5 (disposition per finding) | NO | - |
| G6 (forbidden tools) | NO | - |
| G7 conditions | NO | Either all 3 met or exemption doesn't apply. |
| Convergence model (default `unanimous`) | YES | Floor: `threshold >=75%` or `confidence-weighted >=80%`. Recorded under `convergence-waive`. Must-fix=0 still applies. |
| Slate composition | YES | Floor: >=4 reviewers; >=1 Claude + >=2 GPT (one premium + one cross-version/codex) + >=1 Gemini; >=1 `rubber-duck` + >=2 `code-review`; >=1 heavy-tier. Recorded under `slate-waive`. Re-checked after every drop/replacement. |
| Individual finding via G4 | YES (with G4) | External tracker URL + same-turn `ask_user`. |

Items not in the matrix are NOT waivable.

## Reviewer slate (default heavy)

Tier -> current model via `multi-model-review/current-model-registry.md`.

| Slot | Tier id | Family | Role |
| --- | --- | --- | --- |
| 1 | `heavy-claude-xhigh` | Claude | `code-review` |
| 2 | `heavy-gpt-premium` | GPT | `code-review` |
| 3 | `heavy-gpt-codex` | GPT | `code-review` |
| 4 | `heavy-gpt-cross-version` | GPT | `code-review` |
| 5 | `heavy-gemini-premium` | Gemini | `code-review` |
| 6 | `heavy-claude-standard` | Claude | `rubber-duck` |

**Substitution**: unavailable model -> highest-capability successor from same family. Record `slate-substitutions: [{slot, requested, substituted, reason}]`. Floor re-checked after every substitution.

## Reviewer prompt

Use `multi-model-review/pr-creation-mirror-prompt.md` (shared 11-category Copilot-mirror template). Consumer-specific substitutions: `<baseSha>`, `<headSha>`, `<repo-path>`, round context, prior-commit panel dispositions, Intake Q4 context notes.

## Procedure

### Step 1. Determine invocation mode

This gate does NOT classify whether push is review-targeting (that is `pre-pr-push.md`'s job).

- **Normal path**: `pre-pr-push.md` state present AND Step 5 hook fires -> `invocationMode: via-pre-pr-push-step-5`. Read `isFirstReviewExposurePush`, `remoteExposureExists`, `baseRef` from that record. Continue to Step 2.

- **Direct invocation path** (no `pre-pr-push.md` state) -> `invocationMode: direct-invocation-dry-run-only`. For diagnostic/dry-run/education use ONLY; CANNOT emit `READY-*` status, CANNOT unblock G6.

  Forge-specific open-PR check (informational):
  - GitHub: `gh pr list --head <branch> --state open`
  - GitLab: `glab mr list --source-branch <branch> --state opened`
  - Gitea/Forgejo/Codeberg: `tea pr list --state open --head <branch>`
  - Azure DevOps: `az repos pr list --source-branch <branch> --status active`
  - Other forges: equivalent command or `ask_user` for guidance.

  Then `ask_user` with options:
  1. **STOP and run `pre-pr-push.md` first** (recommended) - normal entry point; exits §2D immediately.
  2. **Continue as DRY-RUN** - emits `pr-creation-status: DRY-RUN-INFO-ONLY`; does NOT unblock G6.
  3. **Abort §2D** - exit without panel.

  Attempting `READY-pending-user-approval` or `READY-re-emitted-after-user-approval` while `invocationMode == direct-invocation-dry-run-only` is a §1B violation.

  **Collect `baseRef` explicitly** (no pre-pr-push state to read from): `ask_user` for `baseRef` (default `origin/main`). Resolve SHA via `git rev-parse <baseRef>`; record as `panelBaseSha`.

Record `invocationMode` and `baseRef` in phase-state.

### Step 2. Re-run-trigger detection (ancestry-based)

When a prior §2D run exists, detect what changed:

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

`re-run-triggers` is a LIST (can co-occur). `history-rewrite` covers force-push, amend, interactive rebase.

**Carry-forward rule**: prior-commit-panel-dispositions carry forward IF AND ONLY IF `re-run-triggers == ["net-new-commits"]`. Any rewrite/squash/base-shift invalidates them.

Record `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `reRunTriggers` in phase-state.

### Step 2.5. Pattern preflight against catalog

Runs BEFORE Step 3 so `PATTERN PREFLIGHT` block is in reviewers' initial context. Deterministic sweep against `multi-model-review/pr-review-pattern-catalog.md` + FP registry at `multi-model-review/known-false-positives.md`.

**Procedure**:

1. **Resolve catalog revisions**:
   ```
   git -C <copilotinstructions-clone> log -1 --format=%H -- .github/playbooks/multi-model-review/pr-review-pattern-catalog.md
   git -C <copilotinstructions-clone> log -1 --format=%H -- .github/playbooks/multi-model-review/known-false-positives.md
   ```
   Record SHAs as `catalog_revision`, `fp_registry_revision`. Empty stdout = file absent in HEAD = `catalog: not-yet-built` (NOT a failure). Also run `git ls-tree HEAD -- <path>` to confirm; quote both outputs in the skip block. `fatal:` exit -> retry with `git fetch origin main`; still failing -> `ask_user` + STOP.

2. **Per high-frequency pattern** (those with executable `discovery_query`): run the query per its scope-mode:
   - **Diff-scoped**: `git diff --name-only -z <merge-base>..HEAD -- '<glob>' | xargs -0 -r rg --line-number --no-heading --color never <pattern>`. PowerShell: pipe through `ForEach-Object` + `rg -- $_`.
   - **Tree-scoped**: `rg --line-number --no-heading --color never <pattern> <source-tree>`.
   - **Hybrid**: emit ONE entry with `scope_mode: hybrid`, both `tree_query`/`diff_query` keys, combined `sites:` list, each site tagged `surfaced_via: tree | diff`.
   - **Review-only** (`discovery_query: <review-pass-only>`): no automated discovery; record `hits: review-required, sites: []`; the reviewer prompt surfaces these as instructions.
   - All `rg` invocations: `--line-number --no-heading --color never`. `rg` exit 1 = no-match (not error); other non-zero -> `ask_user`.

3. **Per match**, classify with Delta K enum (consistent with `review-workflow-gates-sweeps.md` §2B `delta-g-sweeps:` row):
   - `applied` - canonical fix in place. Requires `evidence: <file:line-range>`.
   - `already-applies` - site already correct at merge-base. Requires `evidence: <file:line-range>`.
   - `not-applicable` - site exempt. Requires `rationale: <one line>` citing (a) a code property verifiable from the cited file OR (b) a project-defined invariant. **Pure runtime-behavior assertions without code evidence are NOT valid rationale.**

4. **FP cross-check**: check each finding against `known-false-positives.md` by technical claim (semantic match, not phrasing match). Match -> dismiss with canonical template, record `classification = 'recurring-false-positive'`, exclude from panel. If `<project-root>/.github/data/pr-review-findings.csv` (or `.sqlite`) absent, follow `pr-review-findings-schema.md` §Initial seeding first.

5. **Emit `PATTERN PREFLIGHT` block** in the same response that launches Step 3 (precedes panel-launch tool calls):

```
PATTERN PREFLIGHT
  catalog_revision: <SHA from 2.5.1>
  fp_registry_revision: <SHA from 2.5.1>
  patterns_checked: <count>
  preflight_findings:
    - pattern: <slug from catalog>
      scope_mode: diff-scoped | tree-scoped | hybrid | review-pass-only
      discovery_query: <exact command run> | "<review-pass-only>"
      hits: <count> | review-required
      sites:
        - path: <project-relative>
          status: applied | already-applies | not-applicable
          surfaced_via: tree | diff       # hybrid only
          evidence: <file:line-range>     # applied + already-applies
          rationale: <one line>            # not-applicable
  fps_recognized:
    - fp: FP-N (slug)
      sites: [<paths>]
```

**Enforcement** (via G6, NOT §1B): the PATTERN PREFLIGHT block becomes a prerequisite for G6 tools alongside the PRE-PR REVIEW COVERAGE block. Both together gate PR creation. This does NOT extend §1B.

**Skip conditions** (each requires emitting `PATTERN PREFLIGHT` with the documented status + evidence):
- **`catalog: not-yet-built`**: catalog file absent in CopilotInstructions HEAD (empty stdout from both `git log -1` and `git ls-tree HEAD`). Quote both commands + outputs.
- **`catalog: empty-battery`**: file exists but "Patterns (high-frequency battery)" section has zero numbered entries. Quote catalog_revision SHA + count proof.
- **`catalog: skipped-bootstrap`**: PR is G7 bootstrap-exempt. Quote G7 token / `bootstrapTokenStatus: present-in-body`.
- **`catalog: skipped-no-production-diff`**: diff touches only non-production files (`.github/**`, `docs/**`, `*.md`, `*.txt`, fixtures, snapshots). Quote `git diff --name-only` output.

**Catalog drift detection**: if `catalog_revision` differs from prior run's recorded value, run FULL preflight regardless of `re-run-triggers`. Step 9 re-fetches catalog SHAs and restarts at Step 2.5 on drift.

### Step 3. Launch the panel in parallel

Per `multi-model-review/procedure.md` parallel-launch protocol. All reviewers launched same response (background mode) with `pr-creation-mirror-prompt.md` template. Prompts include reference to PATTERN PREFLIGHT block; reviewers verify `applied`/`already-applies` correctness, validate `not-applicable` rationale, and probe for catalog-uncovered patterns.

**Slate-floor checkpoint #1**: verify floor BEFORE launch. Substitution broke floor -> escalate.

### Step 4. Wait for reviewers; handle drops

Per `multi-model-review.md` hard gates (notification-driven; no polling). Per-reviewer timeout: 10 minutes. On timeout: `write_agent` "status check"; +2 min grace; no response -> dropped.

Cumulative drop events:

- 0 -> proceed.
- 1 -> launch replacement (same family, highest-capability successor).
- 2 -> escalate `ask_user`: wait 10 min / proceed degraded if floor holds / abort.
- >=3 -> hard escalate; cannot proceed without user + floor satisfied.

**Slate-floor checkpoint #2-N**: re-verify after every drop/replacement. Floor break -> escalate immediately.

### Step 5. Synthesize + apply convergence + C2 routing

Per `multi-model-review/procedure.md` synthesis (dedup by theme, severity, agreement). Apply convergence model. C2-route every finding per G5.

`routed-deferred-with-tracker-and-ask_user` requires G4 conditions in this turn. Not met -> must be `fixed` or `dismissed-source-grounded`.

### Step 6. Apply fixes for must-fix findings (with branch-level iteration tracking)

Every `blocking` finding resolved via G2's three paths.

For `fixed`: apply change, re-stage, re-run build+tests, emit `POST-CODE-CHANGE LEDGER` per `review-workflow-gates-sweeps.md` §2B, then re-run panel from Step 2.

**Before re-launching, increment `fixIterationCount`.** If `fixIterationCount > fixIterationCountCap` (default `3`), STOP and escalate via `ask_user`. The escalation MUST classify the iteration history:

- **cap-with-regressions** - a prior round's fix introduced a NEW finding (the same code re-iterated, possibly with the same pattern class). Indicates real instability of the fix process (the §2D cap is doing its job). Default recommendation: pause, split branch, or route via G4.
- **cap-with-new-clean-categories** - each fix verified correct in the next round; subsequent rounds caught genuinely NEW pattern categories (different anti-pattern shape, file area, or framework concern), NOT because the fixes are unstable. Indicates productive prompt-mining. Default recommendation: authorize one more iteration with explicit new cap; queue new patterns as instruction-file deltas.

Offer four options:
1. Override `fixIterationCountCap` to higher value (record in next LEDGER). For cap-with-new-clean-categories.
2. Route remaining via G4 (one tracker + `ask_user` per finding). For cap-with-regressions.
3. Split branch / reduce scope. For cap-with-regressions on large diffs.
4. Abort gate.

Do NOT re-enter Step 2 until user authorizes a path. Reset `fixIterationCount` to 0 only on `first-run` or successful `READY-re-emitted-after-user-approval`.

Round-level max-loop (5 per `multi-model-review/procedure.md`) is a DIFFERENT counter from `fixIterationCount` (cross-invocation fix cycles). Full automation deferred to `pre-pr-creation-review/implementation-roadmap.md` priority 3.

### Step 7. Emit `PRE-PR REVIEW COVERAGE` block (initial)

Mandatory before AGENTS user-approval. Format:

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
  fix-iteration-count: <N - incremented per Step 6; 0 for first run>
  fix-iteration-count-cap: <3 default, or user-authorized override>
  dropped-reviewers: <[] or list>
  replacement-reviewers: <[] or list>
  prior-commit-panel-dispositions: <"none - <reason>" or compacted list>
  findings: <total raw>, dedupe'd to <M themes>
  resolution (every finding has a status):
    - [<category 1-11>] <severity> [<reviewer>]: <finding>: <status>: <citation>
    - ...
  must-fix-blocking-findings-resolved: <K of K>
  routed-deferred-with-tracker:
    - <finding> -> <tracker URL> (ask_user: <call ref>)
    - ... (default: [])
  bootstrap-token-status: <not-applicable | present-in-body | removed-revokes-exemption>
  catalog-revision: <40-char SHA | not-yet-built>
  fp-registry-revision: <40-char SHA | not-yet-built>
  pattern-preflight-skip-status: <ran | catalog: not-yet-built | catalog: empty-battery | catalog: skipped-bootstrap | catalog: skipped-no-production-diff>
  pr-creation-status: <READY-pending-user-approval | READY-re-emitted-after-user-approval | DRY-RUN-INFO-ONLY | BLOCKED - <reason>>
  subagent_ask_user_calls=0 (per AGENTS.md)
```

The `catalog-revision`, `fp-registry-revision`, and `pattern-preflight-skip-status` fields are the state-echo for G6's PATTERN PREFLIGHT check - MUST be populated from phase-state on every emission. Use `not-yet-built` for SHA fields only when skip-status is `catalog: not-yet-built`; otherwise hold real SHAs.

### Step 8. AGENTS user-approval

Per AGENTS.md `gh pr create` section: present PR title + body + base via `ask_user`. User approves/edits/rejects. Non-GitHub forges: mirror same flow before G6 tool.

#### Step 8a. PR-description coherence check (mandatory before user-approval `ask_user`)

Before presenting PR description, re-read it against the diff. Verify every named type, interface, path, method, or behavioural claim actually appears in the diff with the attributed role. Common incoherences: renamed-but-not-updated symbols, capability misattributed to wrong interface, moved-but-stale paths, behavioural overclaims (feature scaffolded but not implemented), SHAs that won't survive rebase.

When incoherence found: fix description (or route back to panel as finding). Treat as blocking pre-PR-creation gate.

Record `prDescriptionCoherenceCheck`: `ran-clean` / `ran-fixed-description-before-create` / `ran-routed-back-to-panel-as-finding`.

### Step 9. Re-emit blocks after approval

In PR-creation tool-call turn (after Step 8 `ask_user` returns):

- Re-run Step 2's same-state checks. Any failure (new commits, force-push, base shift) -> restart at Step 2.
- Re-fetch `catalog_revision` + `fp_registry_revision` per Step 2.5.1. Either differs -> restart at Step 2.5.
- Re-emit `PRE-PR REVIEW COVERAGE` with `emission-phase: ready-re-emitted-after-user-approval`, `pr-creation-status: READY-re-emitted-after-user-approval`, catalog/registry fields from current phase-state.
- Re-emit `PATTERN PREFLIGHT`. If catalog/registry SHAs + `panelHeadSha` unchanged, carry-forward is a literal copy of Step 2.5's block. If changed, Step 2.5 re-run produces new block (panel already re-ran per restart above).

Both blocks precede the Step 10 tool call in the same response.

### Step 10. Invoke the G6 tool

Only after Step 9's re-emitted `PRE-PR REVIEW COVERAGE` + `PATTERN PREFLIGHT` both present in same response.

## State to record in canonical session todos

Per `AGENTS.md` *Phase-state tracking convention*:

`invocationMode`, `reRunTriggers`, `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `slateActuallyRun`, `slateSubstitutions`, `slateWaive`, `convergenceModelUsed`, `convergenceWaive`, `panelRounds`, `fixIterationCount`, `fixIterationCountCap`, `panelConvergence`, `droppedReviewers`, `replacementReviewers`, `priorCommitPanelDispositions`, `mustFixFindings`, `mustFixResolved`, `prDescriptionCoherenceCheck`, `bootstrapTokenStatus`, `prCreationStatus`, `catalogRevision`, `fpRegistryRevision`, `patternPreflightSkipStatus`.

Read from session todos when emitting blocks; never infer from memory.

## §2B carve-out forward-reference

When `review-workflow-gates-sweeps.md` §2B tightens `post-code-change-panel` from `ran | N/A - reason | user-waived` to `ran | N/A - reason`, preserve the existing N/A carve-out for pure-recommit/rebase with zero behavioral delta vs. previously-panelled artifact. Removing `user-waived` is correct; removing the N/A carve-out would be a regression.

## Cross-cutting fit - companion edits required (G7 condition 3)

The introducing PR for §2D MUST include ALL of:

- This playbook (`pre-pr-creation-review.md`).
- `multi-model-review/pr-creation-mirror-prompt.md` - shared 11-category prompt.
- `pre-pr-creation-review/implementation-roadmap.md` - deferred-features document.
- `AGENTS.md` `gh pr create` section - require G3 block emissions before user-approval.
- `AGENTS.md` cross-cutting hard-gate bullets - new bullet referencing §2D.
- `pre-pr-push.md` Step 5 - invokes this playbook. Adds `preCreationReviewStatus` to state predicate.
- `review-workflow-gates-sweeps.md` §2D - LEDGER row + G1-G7 enforcement summary.
- `.github/playbooks/manifest.yaml` - registers `pre-pr-creation-review`.

Missing any -> §2D non-operative post-merge -> G7 bootstrap exemption invalid.

## Future enhancements (deferred)

See `pre-pr-creation-review/implementation-roadmap.md` for: capability-tier registry indirection, context-budget circuit breaker, branch-level fix-iteration cap, compaction format, forge-agnostic state field, automated slate-floor re-check, same-state re-check infrastructure. Each ships on first real-world failure or explicit prioritization.

## Why this gate exists

LLM-based PR reviewers consistently surface known pattern categories. Running a multi-model panel pre-PR shifts findings from "comment after PR opens" to "blocking finding before PR opens"; same work, dramatically lower visibility cost. When a finding lands on a PR that PASSED §2D, follow `review-workflow-gates-sweeps.md` §2 root-cause analysis and propose a catalog/prompt addition. The gate improves via this feedback loop.
