# Playbook: Pre-implementation phase
<!-- read-receipt-token: 06e31523 -->

## Purpose

Run diagnosis verification + approach-selection gate + safety-critical-skip evaluation + multi-model review panel before writing any code. This is the highest-leverage moment to catch design flaws - course-corrections here are the cheapest. Fires immediately when a code change is requested, before any implementation begins.

## Hard gates (mirrored in `AGENTS.md` so they survive playbook-fetch failure)

- **Step 1** - Diagnosis verified against source via the deepened procedure (reproduce → minimise → hypothesise → instrument → reproduction-locked). Treat any root-cause claim from a prior agent, plan, report, bug, or user prompt as a **hypothesis** to confirm before designing a fix.
- **Step 1** - Reproduction or benchmark exists when applicable (no fix without a number that moves).
- **Step 1.5 - G3 approach-selection gate** - for in-scope findings with both "fix the cause" and "document the symptom" options, default is fix-the-cause. **Out-of-scope findings stay on the cross-cutting `ask_user`-mandatory path. G3 does NOT grant scope expansion. NO file edits for out-of-scope findings.**
- **Step 2 entry - G5 safety-critical-skip evaluation** - when work touches individual safety-critical triggers (public API surface, folder/namespace restructure, test surface migration) OR ≥3 softer signals, skipping the multi-model panel becomes safety-critical and requires explicit re-confirmation per the User-skip policy. Augments (does not replace) the existing safety-critical category list.
- **Step 2 entry-2 - G6 Playbook offer evaluation** - scan the proposed change for the 7 cycle-3 playbook triggers (implementation-planning, library-restructure, design-exploration, performance-comparison, scope-planning, system-framing, project-vocabulary) and emit chat-visible `trigger-detected-<playbook>: yes|no` + `playbook-decision-<playbook>: <value>` lines per playbook. REQUIRED-class triggers (implementation-planning, library-restructure) and OFFERED-class triggers (rest) follow different decision-value semantics; G6 re-entry is mandatory when scope materially changes mid-implementation. Enforced by catalog rules 2, 3, 4, 6, 7, 8, 10, 11, 12, 13.
- **Step 2** - Multi-model reviewer panel via `multi-model-review.md` (target-type: `plan`) run with unanimous convergence; 0 unaddressed blocking; `subagent_ask_user_calls=0`. Panel runs unless explicitly skipped (with the safety-critical re-confirmation from step 2 entry applied).
- **Step 3** - Phase state recorded; out-of-scope findings routed via `ask_user`.

## Intake questions

Bundle in one prompt:

1. What's the diagnosis you're acting on, and where did it come from? (your hypothesis / prior agent / bug report / user prompt / **previous bug-investigation report file** - when the change is a fix-transition handoff from `cross-file-bug-investigation.md`, supply the path to the persisted findings file at `<session-state>/files/bug-investigation-<ts>.md`)
2. Do you have a reproduction (functional bug) or benchmark (perf regression) already, or do I need to build one?
3. **Reproduction artifact type** (when building a repro): (a) **throwaway diagnosis harness** - removed before completion per existing cleanup rule; (b) **durable regression test** - locked in; survives as a permanent test; (c) **decide later** - defer the choice until reproduction is achieved (default behavior: treat as throwaway unless promoted before completion).
4. **Default to running the multi-model panel.** Skipping is the exception, not the default. If you believe a change is trivial enough to skip (single-line typo, single-property rename with no semantic change, single config-key value tweak), call that out explicitly. Triviality is overridden by G5 safety-critical triggers (see *Procedure* step 2 entry).
5. **Perf work only:** what specific number do you expect to move, and by how much? (If the proposed fix wouldn't move that number, the diagnosis is wrong - stop and re-investigate.)
6. **Bug fix only:** can the bug be reproduced reliably? (If not, the bug isn't understood yet - re-investigate before designing a fix.)

## Procedure

### Entry points

The pre-implementation phase has two documented entry paths. Both run the full Procedure below (Steps 1 → 3). Hard gates (G3 / G5 / G6) and the multi-model panel apply to BOTH paths.

1. **Normal user-requested code change** - the user asks for a code change directly. Diagnose-step input comes from the user's prompt and intake Q1 (hypothesis / prior agent / bug report). Default entry.

2. **Fix-transition handoff from `cross-file-bug-investigation.md`** - when the user picks fix in step 11B of the investigation playbook, the orchestrator persists selected findings to `<session-state>/files/bug-investigation-<ts>.md` and enters this phase with that path supplied as the Q1 diagnosis source. Pre-impl then:
   - Reads the YAML frontmatter (`schema_version: 1` is pinned; both writer and reader agree on this version).
   - Iterates each `findings:` entry as a separate diagnose-loop hypothesis in Step 1 (per-finding reproduce → minimise → hypothesise → instrument → reproduction-locked).
   - Runs ONE aggregate G3 approach-selection covering all selected findings.
   - Runs ONE plan; ONE multi-model panel (reviewers emit ONE verdict per plan-as-whole - consistent with single-fix plan behavior).
   - Produces ONE commit (`single_commit=true` invariant preserved).
   - When findings are independent AND approaches diverge: `ask_user` to split into N pre-impl cycles (each its own commit).

   **Fallback behavior on missing or unparseable persistence file:**
   - File missing → `ask_user` to re-supply the path OR abandon the fix-transition handoff and re-run `cross-file-bug-investigation.md`.
   - YAML parse fail OR `schema_version > 1` (forward-compat) → warn in chat; fall back to free-form-text reading of the file body; treat each `## F-NNNN:` heading block as ONE diagnosis hypothesis (matches the writer's H2-per-finding output in `cross-file-bug-investigation.md` persistence schema). `schema_version` mismatches are non-blocking but degrade structured parsing.

### Step 1 - Verify the diagnosis (deepened procedure)

Read the implicated code and confirm the mechanism behaves as described **before** designing a fix.

1. **Reproduce** - write a failing test (durable regression test artifact) OR throwaway diagnosis harness OR `repro.<lang>` script that triggers the observed behavior. Per the intake artifact-type question, the user chooses; default is throwaway when undecided.
2. **Minimise** - shrink the reproduction to the smallest input / scenario / fixture that still triggers. Smaller repros make the next steps cheaper.
3. **Hypothesise** - write a one-sentence hypothesis about the root cause. The hypothesis is the thing the next step instruments.
4. **Instrument** - add tracing / logging / probes to confirm the hypothesis. Run the minimised reproduction with instrumentation; verify the hypothesis matches observed behavior. If the hypothesis is wrong, return to step 2 with the new observations.
5. **Reproduction locked** - the failing test or harness is in place; the hypothesis is confirmed by instrumentation. **Procedure ends here.** The fix itself is implementation-phase work - NOT pre-implementation. Post-fix verification (re-run the test / benchmark and confirm it passes / improves) belongs in `post-code-change.md`'s existing diagnosis-verifying gate.

**Cleanup of ad-hoc diagnosis harnesses:** any harness or test created **solely to validate a diagnosis** is removed before the change is reported complete, **unless** the intake artifact-type choice was "durable regression test" (in which case it stays as a permanent test). The throwaway-harness vs durable-test distinction is set at intake; do not promote to durable without explicit user approval.

**Perf work:** identify (or write) a benchmark that measurably captures the regression. If that number wouldn't move after the proposed fix, the diagnosis is wrong - stop and re-investigate. No fix without a number that changes.

### Step 1.5 - G3 approach-selection gate (in-scope findings only)

For each finding surfaced during diagnosis, classify scope using the 4-row truth table (`AND`-clause):

| Touches files in current change working set | Tightly-coupled bug the change directly causes | Classification |
| --- | --- | --- |
| yes | yes | **IN-SCOPE** (fix-cause default) |
| yes | no | **IN-SCOPE** (fix-cause default; finding lives in touched files) |
| no | yes | **IN-SCOPE** (tightly-coupled root cause justifies expansion) |
| no | no | **OUT-OF-SCOPE** (route via `ask_user`; NO file edits) |

**Working set** = files already touched or staged for this change: `git diff --name-only HEAD` ∪ `git diff --cached --name-only` (staged) ∪ untracked working-tree files added for this change.

**For in-scope findings** with both fix-cause and document-symptom options, default to **fix-the-cause**. Document the symptom only when the cause is genuinely out of scope per the truth table OR when the cause requires its own independent design review (a separate intake / scope-planning workflow). Document-the-symptom defaults are recorded with rationale.

**G3 does NOT grant**: (a) scope expansion - out-of-scope findings always route via `ask_user`; (b) permission to implement before step 1 reproduction is locked - the fix is implementation-phase, not pre-implementation.

### Step 2 entry - G5 safety-critical-skip evaluation

Before the multi-model panel, evaluate whether the user's intent to skip (if any) should be classified safety-critical per the augmented set.

**Effective safety-critical set** = the existing User-skip policy list (multi-model panel, branch-wide sweep, verification-of-fix, pre-implementation multi-model panel on concurrency / security / cryptography / native interop / payment or financial logic / authentication / authorization / shared global state) **∪ G5 triggers below**.

**G5 individual triggers** (each safety-critical above trivial scope):

- **Public API surface** - any visibility widening, new exported type, or change to a signed / packaged API surface.
- **Folder / namespace restructure** - any move or rename of a folder or namespace.
- **Test surface migration** - ≥1 test project has files moved, renamed, or re-targeted to a different SUT assembly.

**G5 softer signals** (count toward ≥3-of-N escalation):

- Multiple projects touched.
- Bulk renames: **≥5 distinct symbols** OR cross-file / cross-project OR public-API / test / interface-chain boundary crossing.

**Symbol definition** (for bulk-rename counting): each independently-named identifier counts as 1. Method overloads sharing a name = 1 symbol. A class and its members = N+1 symbols (the class plus each member).

**When safety-critical fires**: explicit re-confirmation required per the existing User-skip policy. The skip is NOT silently accepted; the user must explicitly acknowledge the safety-critical nature in the chat transcript.

### Step 2 entry-2 - G6 Playbook offer evaluation

Sibling step to G5 (G5 handles binary safety-critical-skip; G6 handles playbook trigger detection). Same scan-source, separate outputs. Runs BEFORE the multi-model panel.

Scan the proposed change against the 7 cycle-3 playbook triggers below. For each, emit TWO chat-visible greppable lines:

1. `trigger-detected-<playbook>: yes|no`
2. `playbook-decision-<playbook>: <value-per-decision-class>`

**Detection table:**

| Trigger (crisp definition) | Playbook | Decision class | Source |
|---|---|---|---|
| Change is **non-trivial** - does NOT match `{single-line typo, single-property/single-config-key tweak, comment-only edit, formatting-only edit}` AND has any other change in diff | implementation-planning | REQUIRED-decision-recorded | Closed enumeration |
| Plan touches folder topology - **any move or rename of a folder or namespace** (verbatim G5 trigger scope) | library-restructure | REQUIRED-decision-recorded | Verbatim G5 reuse |
| Plan has ≥2 viable competing approaches (plan text contains "option A vs B", "either approach", "compare", "trade-off", OR user asked "which X is better") | design-exploration | OFFERED | Plan-text indicators |
| Plan has quantitative perf goal (numeric throughput / latency / memory target; user-stated) | performance-comparison | OFFERED | User-stated; easy detection |
| Scope statement is < 50 chars AND no scope-planning artifact citation in session | scope-planning | OFFERED | Tightened to reduce false-positive ledger noise |
| Plan crosses module / project / assembly boundaries (new cross-asm reference or new project added) | system-framing | OFFERED | Plan mentions new project / cross-asm reference |
| Plan introduces ≥3 new domain terms (types / methods / concepts) NOT in project-vocabulary.md | project-vocabulary | OFFERED | Count new domain nouns; check vocab doc |

**Decision values per class:**

- **REQUIRED-decision-recorded class** (implementation-planning, library-restructure):
  - VALID when `trigger-detected: yes`: `invoked` OR `required-but-skipped: "<safety-critical re-confirmation per User-skip policy>"`
  - VALID when `trigger-detected: no`: `not-required-trigger-not-detected` (sentinel - preserves fixed cardinality without omission)
  - INVALID: `offered-and-declined`, `not-applicable` (silent-bypass; catalog rules 2/3/12/13 fire)

- **OFFERED class** (design-exploration, performance-comparison, scope-planning, system-framing, project-vocabulary):
  - VALID when `trigger-detected: yes`: `invoked` / `offered-and-declined: "<user-quote-justifying-decline>"` / `required-but-skipped: "<reason>"`
  - VALID when `trigger-detected: no`: `not-applicable`
  - INVALID when `trigger-detected: yes`: `not-applicable` (silent-downgrade bypass; catalog rules 6/7/8/10/11 fire)

**Chat output example (trivial single-property tweak with no other change):**

```
trigger-detected-implementation-planning: no
trigger-detected-library-restructure: no
trigger-detected-design-exploration: no
trigger-detected-performance-comparison: no
trigger-detected-scope-planning: no
trigger-detected-system-framing: no
trigger-detected-project-vocabulary: no
playbook-decision-implementation-planning: not-required-trigger-not-detected
playbook-decision-library-restructure: not-required-trigger-not-detected
playbook-decision-design-exploration: not-applicable
playbook-decision-performance-comparison: not-applicable
playbook-decision-scope-planning: not-applicable
playbook-decision-system-framing: not-applicable
playbook-decision-project-vocabulary: not-applicable
```

**G6 re-entry on mid-implementation scope change:** if scope materially changes during implementation (e.g., the diff grows beyond the closed-enumeration triviality set after G6 originally emitted `trigger-detected-implementation-planning: no` + `playbook-decision-implementation-planning: not-required-trigger-not-detected`), the agent MUST re-enter G6, re-evaluate triggers against the new scope, and UPDATE the chat-visible decision lines (which feed the POST-CODE-CHANGE LEDGER sub-blocks per `review-workflow-gates-sweeps.md` §2B and the pre-impl phase-state per AGENTS.md *Per-phase additional fields*) to reflect the new state. The LEDGER reflects the FINAL G6 state - not the initial G6 snapshot. Post-impl rules 12 (library-restructure) and 13 (implementation-planning) catch the missed-re-entry case: when the final diff is non-trivial (or contains folder/namespace moves) AND the ledger still records the sentinel, the post-impl rule fires. Once re-entry happens correctly, the LEDGER decision becomes `invoked` or `required-but-skipped` and the post-impl rule does not fire.

**Post-compaction re-grounding (proof-loss, not scope-change):** a context compaction or summary-resume during an in-flight code/governance change drops the *proof* that the pre-edit gate was cleared, not necessarily the scope. On resume from a summary, BEFORE `next_action=edit`: (1) context-recovery re-fetch this file per `.github/playbooks/README.md`; (2) re-establish `PANEL CONVERGED` / the `PRE-EDIT SENTINEL` in the live context - a block visible only in the summary does NOT satisfy `pre_impl_panel=ran:unanimous`. Back it with DURABLE re-readable evidence (the §2B ledger + phase-state on disk), judging scope-coverage against the scope the durable artifact RECORDS (the G6 sub-blocks + `diagnosis-repro-ref` + the transcript's stated scope), NOT your post-compaction memory. If durable evidence exists AND covers the current scope, re-cite it; if it is absent OR the scope changed, re-run via the G6 re-entry / revised-plan path above. Honest ceiling: re-establishing the sentinel post-compaction is behavioral (no edit-time hook); the §2B git gate still mechanically enforces ledger structure + unanimity + parent-freshness, but the re-cited transcript is not proof the panel ran, ran first, or covered this diff.

**Codebase-architecture-audit (informational only):** G6 may informally surface a codebase-architecture-audit offer when the plan touches unfamiliar code areas, but there is NO catalog enforcement for it (rule 9 was dropped because the underlying detection mechanism was unreliable). No `trigger-detected-codebase-architecture-audit` or `playbook-decision-codebase-architecture-audit` line is required.

### Step 2 - Multi-model review panel on the plan

Run the multi-model reviewer panel via `multi-model-review.md` with target-type `plan`. The review target is the proposed approach / plan produced during Step 1 diagnosis verification.

**Default critique focus areas** (passed to each reviewer alongside any user-supplied focus):

- *"Is the named root cause actually true? Verify against the source before evaluating the fix."*
- Correctness of the diagnosis (does the code actually behave as the diagnosis claims?).
- Soundness of the proposed approach.
- Edge cases the proposed fix would miss.
- Any cross-cutting concerns the user / prior agent didn't raise (state predicates, defer-mutations-until-success, recurring smells - see AGENTS.md §3).

The panel must reach **unanimous convergence** (all reviewers verdict `READY_TO_IMPLEMENT`) before implementation proceeds. Address findings or explicitly justify dismissal per C2 routing. Adopt findings that clearly prevent bugs or test failures; set aside findings that significantly complicate the implementation without clear benefit.

### Step 3 - Record state and proceed

After the multi-model panel:

- Record phase-state: phase entered, intake complete, diagnose artifact-type chosen, G3 in-scope findings handled, G5 evaluation outcome (not-applicable / safety-critical-confirmed-skip / panel-ran), G6 trigger-detection + decision lines (14 lines per pre-impl record: 7 `trigger-detected-<playbook>:` + 7 `playbook-decision-<playbook>:`), multi-model panel run / skipped.
- **Mechanical enforcement (this instructions repo only):** the pre-implementation panel + phase-state are recorded into the `POST-CODE-CHANGE LEDGER` (`review-workflow-gates-sweeps.md` §2B) as `pre-code-change-panel:` + a `pre-panel-transcript:` (verdict `READY_TO_IMPLEMENT`, full slate, + a `- findings:` disclosure line) plus `diagnosis-repro-ref:` / `approach-selection-G3:` / `safety-critical-eval-G5:` / the G6 sub-blocks. `Test-PanelLedger` validates these at commit/push for any panel-required change (`Get-PathGovernanceTier >= 1`); a path-detectable safety-critical change (tier 2) **cannot** waive the pre panel (`ran, unanimous` mandatory). This converts a silently-skipped pre-panel into a commit-blocking violation (honest-ceiling: it proves the disclosure exists + the slate converged, not that the panel literally ran before the code, ran first, or covered THIS diff - a post-compaction agent that re-cites a converged-but-stale-scope transcript into a fresh-parent ledger still passes, because `parent_sha` defeats reusing a stale ledger, not re-citing the same transcript in a new one).
- Findings surfaced outside the immediate task's scope per G3's truth table - route via `ask_user` per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule. Never silently expand scope.
- **Intent-driven testing dispatch**: if `implementation-planning.md` ran in this session AND its output schema contains a non-empty `behaviors_to_cover` section, `intent-driven-testing.md` (prospective mode) fires for the implementation phase - pre-implementation only records the RED-test plan; the RED → GREEN cycles execute as the implementation phase, NOT inside pre-implementation.
- Proceed to implementation. Next phase: `post-code-change.md` (which runs its existing diagnosis-verifying gate as the post-fix verification step).

## When to skip the multi-model panel

The user may explicitly skip the multi-model panel for genuinely trivial changes (typo fix, single-line config tweak, obvious one-character bug). When they do:

1. **G5 evaluation first** - check whether the change touches any individual G5 trigger or ≥3 softer signals. If yes, the skip is safety-critical; re-confirm explicitly with the user (the existing User-skip policy *Safety-critical skips* clause applies augmented per the effective set above).
2. Warn in one sentence: *"Skipping the pre-implementation multi-model panel on this change means I cannot independently validate the diagnosis or approach."*
3. Record the skip.
4. Mention in the final summary that the multi-model panel was skipped at user's request, and that G5 evaluation determined the skip was / was not safety-critical.

## Output / handoff

Phase-state recorded. Diagnosis verified per the deepened procedure (step 1 reproduction-locked). G3 approach-selection applied (step 1.5; out-of-scope findings routed via `ask_user`). G5 safety-critical-skip evaluation performed (step 2 entry). Multi-model panel run with unanimous convergence (or safety-critical-confirmed skip). Implementation phase begins next; `post-code-change.md` runs its existing diagnosis-verifying gate as the post-fix verification step.
