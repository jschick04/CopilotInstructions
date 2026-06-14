---
name: cross-file-bug-investigation
description: >-
  Panel-driven cross-file bug investigation on user-pointed file sets in a (potentially
  large) codebase. Read-only by default; offers per-finding fix-transition to
  pre-implementation. Lane-specialized reviewers (9 lanes) selected at intake from symptom
  category. Different from codebase-architecture-audit (single-orchestrator 5-lens pass),
  least-privilege-audit (6-axis visibility), and code-review sub-agent (single-sub-agent
  diff review). See Purpose section for the full 6-line canonical discriminator block.
triggers:
  - "find bugs in"
  - "trace the bug across"
  - "hunt for bugs in"
  - "hunt for race conditions in"
  - "hunt for memory leaks in"
  - "look for race conditions in"
  - "look for state-mutation bugs in"
  - "investigate the interaction between"
  - "review the interaction between"
  - "audit the interaction between"
  - "review the flow between"
  - "audit the flow between"
  - "bug hunt across"
  - "bug-finding pass on"
  - "cross-file investigation of"
  - "interaction review of"
  - "interaction analysis of"
---

# Playbook: Cross-file bug investigation

## Purpose

Panel-driven cross-file bug investigation on **user-pointed unchanged code** in a (potentially large) codebase. Reuses the `multi-model-review.md` engine with a new `target-type=bug-investigation` that drives **lane-specialized reviewers** (9 lanes; auto-selected from symptom category at intake). Read-only by default; on user approval, offers per-finding fix-transition into `pre-implementation.md`.

### Canonical discriminator block (referenced by manifest.yaml)

```
cross-file-bug-investigation = multi-model PANEL with intake-selected LANES on USER-POINTED unchanged code.
codebase-architecture-audit  = single-orchestrator pass over 5 FIXED LENSES for ranked architectural debt.
least-privilege-audit        = 6-AXIS visibility/mutability sweep producing per-type matrix.
code-review (sub-agent)      = single sub-agent reviewing STAGED/UNSTAGED diff (recent changes).
multi-model-review diff      = panel reviewing a DIFF (change).
system-framing               = layered map for ORIENTATION (not bug-hunt).
```

This playbook is for investigating BUGS in **unchanged code** the user has pointed at. The mechanism difference vs sibling read-only audits is what makes it distinct: the panel runs N specialists in parallel with symptom-matched lane prompts; sibling audits use a single orchestrator pass over fixed lenses.

## Hard gates (execution order - intake → launch → investigation → synthesis → post-report)

**Intake-time:**

1. **Lane-symptom matching** - auto-selected lanes for the user's symptom (per `lanes-catalog.md` truth table) MUST be a subset of the user's final lane selection. User can ack-override explicitly (recorded in domain-state record).
2. **Reviewer count ≥ 3** (matches `multi-model-review.md` minimum). Default 4: `heavy-claude-xhigh` + `heavy-gpt-premium` + `heavy-gpt-codex` + `heavy-gemini-premium` (tier → model via `current-model-registry.md`).
3. **Scope-size ceiling** - scope ≥ 500 files requires explicit user override recorded as safety-critical-skip-equivalent per AGENTS *User-skip policy*.
4. **Single-file gate** - 1-file scope surfaces `ask_user` with options: expand-scope / route-to-code-review / override-and-proceed (recorded).
5. **Recent-changes gate** - pre-flight runs `git status --porcelain` AND `git diff --name-only <merge-base>...HEAD`. When matches exist, `ask_user` (route to `post-code-change` / continue investigation). **Default to continue** when scope is named in cross-file form (Bundle-A Q1 lists ≥2 files OR contains an interaction/flow noun like `between` / `flow` / `interaction`) - computable from intake without trigger-phrase memory.

**Launch-time:**

6. **Output ordering** - chat-first rendering of report; optional file save OR tracker entry only after user approval (matches `design-spec.md` pattern).

**Investigation-time:**

7. **Read-only between intake completion and report-shown** - no source/playbook file-writes; `<session-state>` + SQL bookkeeping writes permitted (state tracking, audit records, domain-state record at procedure step 5). Sub-agents inherit read-only from `multi-model-review/procedure.md`.
8. **Source-grounding** - every finding cites ≥1 `file:line` per participating file (cross-file claims). No-citation findings dropped at first synthesis (no rework attempt).

**Synthesis-time:**

9. **Citation verification with ≤1 rework cap** - orchestrator `view`s each cited `file:line` and confirms the claim is supported BEFORE rendering the report. Outcomes per finding: `verified` / `verification-failed-dropped` / `verification-invalid-dropped` (citation file:line doesn't exist) / `verification-ambiguous-rework-1` (re-prompt originating reviewer once via `write_agent`) / `verification-twice-ambiguous-dropped` (after 1 rework, still ambiguous).
10. **Convergence applies to BLOCKING findings only** - reviewer's `VERDICT:` emission rule (specified in `multi-model-review/procedure.md`'s `bug-investigation` prompt template): emit `VERDICT: READY_TO_IMPLEMENT` when no BLOCKING-severity findings remain; emit `VERDICT: NEEDS_ANOTHER_ROUND` only when ≥1 BLOCKING finding requires another iteration. Non-blocking findings recorded as advisory; do NOT drive verdict. Model A's evaluation rule (unanimous READY + 0 unaddressed blocking) is unchanged.

**Post-report:**

11. **Fix-transition must be asked** - agent NEVER silently enters `pre-implementation.md` after report. C2 routing (step 11A) ALWAYS happens; fix-transition picker (step 11B) only when intake Q8 ≠ `none`.
12. **Mandatory persistence on fix-transition** - file is PRIMARY (`<session-state>/files/bug-investigation-<ts>.md` per persistence schema below); SQL session-todo OPTIONAL audit pointer. File write failure → re-ack → hard-stop per AGENTS recording chain. Other (non-fix-transition) use cases keep canonical SQL → file → re-ack → hard-stop chain.
13. **G3 / G5 / G6 inheritance on fix-transition** - resulting pre-impl cycle runs FULL phase. Investigation report does NOT bypass any pre-impl gate.

## Intake - 3 bundles (Bundle B split per dependency rules)

### Bundle A (asked first)

- **Q1: Scope** - file list (paths, basenames, symbols, globs). Whole-repo allowed but discouraged; ask for at least a starting file set.

### Pre-flight (between Bundle A and Bundle B1)

1. **Natural scope resolution** - basenames → absolute paths; ambiguity → `ask_user`; zero matches → `ask_user` (typo? not in scope?).
2. **+ 3. Combined recent-changes + single-file gate** - when BOTH would fire (1-file scope AND file is in recent changes), bundle into ONE `ask_user` with combined options: route-to-post-code-change / route-to-code-review / expand-scope / proceed-anyway-and-override. When only one fires, ask the matching single question. Default-to-continue when scope is named in cross-file form (per hard gate 5).
4. **Scope-size guard** - ≥ 10 files OR ≥ 10,000 LOC: offer `system-framing.md` first (non-blocking; one `ask_user`). ≥ 500 files: hard ceiling - require explicit user override recorded as safety-critical-skip-equivalent per User-skip policy.

### Bundle B1 (asked second)

- **Q2: Symptom** - one of `behavior-bug` / `crash` / `race-or-deadlock` / `memory-or-leak` / `security-or-trust` / `performance-degradation` / `unclear-behavior` / `other` (free-text).

### Bundle B2 (asked third - Q3 pre-filled with symptom-based defaults from B1)

- **Q3: Lanes** - multi-select from 9 lanes (per `lanes-catalog.md`); pre-filled with auto-defaults for the symptom; user can override.
- **Q4: Reviewer count** - default 4. Minimum 3.
- **Q5: Convergence model** - default `unanimous` (Model A). See `multi-model-review/convergence-models.md`.
- **Q6: Max-loop count** - default 3 (lower than `multi-model-review.md`'s 5; investigation panels usually converge fast).
- **Q7: Output destination** - `chat-only` / `chat + session-state file` / `chat + GitHub issue` (default `chat-only`). Q7 governs durability when Q8 = `none` (since fix-transition handoff is skipped).
- **Q8: Fix-transition mode** - `offer-per-finding` (default) / `offer-all-at-once` / `none`. `none` is a per-investigation user opt-out from fix-transition entry; the locked system-capability `offer_pre_impl` (cycle-4 scope) is unchanged - the system always SUPPORTS fix-transition; this Q controls whether THIS investigation USES it.
- **Q9: Session suppression** - `session-only` (default; decline-then-no-retry per AGENTS) / `until-explicit-invoke` (suppress auto-offer for this session; user must explicitly name the playbook) / `always-offer` (auto-offer every session). Recorded on the domain-state record.

## Procedure

1. **Bundle A intake** (Q1 scope).
2. **Pre-flight** (natural scope resolution → combined recent-changes + single-file gate → scope-size guard).
3. **Bundle B1 intake** (Q2 symptom).
4. **Bundle B2 intake** (Q3-Q9; Q3 pre-filled from B1's symptom).
5. **Domain-state record** - write `domain-state-cross-file-bug-investigation-<ts>` to the canonical session-todos location (SQL preferred per AGENTS chain; `<session-state>` file fallback). Fields: `phase: cross-file-bug-investigation`, `time_entered`, `playbook_viewed`, `intake_status`, `user_approved_skips`, `scope_files`, `symptom`, `selected_lanes`, `reviewer_count`, `convergence_model`, `max_loops`, `output_destination`, `fix_transition_mode`, `suppression_mode`. Allowed inside hard gate 7's read-only window per its session-state carve-out.
6. **Panel launch** - invoke `multi-model-review.md` (utility-call) with `target-type=bug-investigation`; lane-specialized critique focus per slot; **round-robin lane-to-slot mapping; when `lanes_selected > reviewers`, double-up per-slot per M8 default** with per-reviewer lane-budget hint added to prompt; VERDICT-emission rule applied per hard gate 10.
7. **Synthesis** - dedup findings by theme; rank severity (`blocking` / `major` / `minor`); assign `F-NNNN` ids.
8. **Citation verification** (≤1 rework cap; per hard gate 9). Outcomes recorded per finding.
9. **Report rendering** (chat-first; findings shown WITHOUT C2 status - C2 resolves in step 11A):

   ```
   # Bug investigation report - <scope summary>

   - **Scope**: <file list> (<N> files, <LOC> approx)
   - **Symptom**: <category>
   - **Lanes**: <list>
   - **Reviewers**: <model IDs> (<N> slots; lane mapping: <slot → lane(s)>)
   - **Convergence**: <yes|no> after <R> round(s)
   - **Findings**: verified=<V>, dropped=<D>, rework=<R>, total=<N> (blocking=<B>, major=<M>, minor=<N>)

   ## Findings

   ### F-0001: <Title>  [severity=<blocking|major|minor>] [is_blocking=<true|false>] [lane=<lane>] [confidence=<high|medium|low>] [agreement=<K of N>] [verified]
   - **Files**: <file:line>, <file:line>, ...
   - **What it is**: <one-paragraph description>
   - **Why it's a bug**: <impact + worst-case>
   - **Reproduction**: <how to trigger> OR "Observational - no deterministic repro identified"
   - **Suggested fix class** (advisory; reviewers may disagree): <fix category>
   - **Citation verification**: <verified | dropped:<reason> | rework:<reason>>

   ### F-0002: ...

   ## Cross-file interaction notes (optional)
   <free-form when ≥2 files coupled>

   ## Evidence-gate
   <per-round output from multi-model-review.md>
   ```

10. **User approval of report** - `ask_user` (approve / edit / reject).

11. **Step 11A - C2 routing per finding (ALWAYS happens after report approval)** - `ask_user` with per-finding picker. User MUST dispose of every verified finding via one of:
    - `routed-now` - finding queued for fix-transition step 11B (if Q8 ≠ `none`); else stays as "user-acknowledged-but-no-fix-this-session" (still valid C2 = `routed-now`; user might fix later)
    - `routed-deferred` - tracker entry created if Q7 = GitHub issue; else session-todo path. EVERY `routed-deferred` requires external-record citation per `multi-model-review/evidence-gate-spec.md`
    - `dismissed-source-grounded` - user provides counter-citation (REQUIRED; bare "dismiss" without citation rejected)
    - `fixed` - invariant `fixed=0` until post-impl cycle resolves it; not selectable in this step

    For large reports (≥10 findings), the picker may offer a "default-all-to-`routed-deferred` + override per finding" bulk shortcut; this is a UI affordance, not a contract change (the user still disposes of every finding).

12. **Step 11B - Fix-transition picker (ONLY when Q8 ≠ `none`)** - for findings the user picked `routed-now` in step 11A, `ask_user` with options:
    - `skip-this-session` - no pre-impl entry; `routed-now` findings persist for later
    - `fix-one F-NNNN`
    - `fix-multiple F-N1 + F-N2 + ...`
    - `fix-all-blocking` (all `routed-now` findings with `is_blocking=true`)

    When Q8 = `none`, step 11B is SKIPPED entirely; `routed-now` findings stay user-acknowledged-no-fix-this-session and rely on the chat transcript (ask_user call ref) for their external record - durability comes from Q7 selection.

13. **Output save (optional per Q7)** - if `chat + session-state file`: write report to `<session-state>/files/bug-investigation-report-<ts>.md`. If `chat + GitHub issue`: invoke `gh issue create` with finding YAML+markdown body + labels `bug-investigation` + `severity-<level>`. Fallback when `gh` unavailable: session-state file. Both happen AFTER step 10 user approval.

14. **Mandatory persistence on fix-transition** - file is PRIMARY. Write `<session-state>/files/bug-investigation-<ts>.md` with this schema:

    ```yaml
    ---
    schema_version: 1
    source_report_hash: <SHA-256 of the rendered report text>
    source_report_path: <path to the saved report if Q7 saved one; else 'chat-only'>
    scope_files: [path1, path2, ...]
    selected_lanes: [lane1, lane2, ...]
    selection_mode: "per-finding" | "multiple" | "all-blocking"
    single_commit: true
    findings:
      - id: F-0001
        severity: blocking|major|minor
        is_blocking: true|false
        lane: <lane slug>
        agreement: "K of N"
        citations: [path:line, path:line, ...]
        reproduction: <text or "observational">
        suggested_fix_class: <text>
        c2_status: routed-now|routed-deferred|dismissed-source-grounded
        citation_verification_status: verified|verification-failed-dropped|...
      - id: F-0002
        ...
    ---

    # Selected findings for fix-transition (markdown rendering of each finding)

    ## F-0001: <Title>
    <body>

    ## F-0002: ...
    ```

    SQL session-todo (optional audit pointer): `bug-investigation-handoff-<ts>` with `description` = `file=<path>; selection_mode=<mode>; finding_count=<N>; summary=<≤200 chars>`. File write failure → re-ack on each subsequent turn until evidence recorded → hard-stop per AGENTS recording chain.

15. **Pre-impl handoff** - enter `pre-implementation.md` NORMALLY with persisted file path as Q1 diagnosis source. Pre-impl's Entry points subsection documents reading the YAML frontmatter (schema_version: 1) + per-finding diagnose-loop iteration.

16. **N-bug pre-impl semantics** - ONE aggregate pre-impl cycle for the selected findings:
    - Diagnose step (Step 1) iterates per-finding (each gets its own reproduce → minimise → hypothesise → instrument → reproduction-locked).
    - ONE aggregate G3 approach-selection covering all selected findings.
    - ONE plan; ONE multi-model panel (reviewers emit ONE verdict per plan-as-whole - consistent with existing pre-impl panel behavior for single-fix plans).
    - ONE commit (`single_commit=true` invariant preserved).
    - When findings are independent AND approaches diverge: `ask_user` to split into N pre-impl cycles (each its own commit).

17. **Observational finding loop-back** - when pre-impl Step 1's reproduce sub-step cannot build a repro for an observational finding:
    - Repro built successfully → continue normal pre-impl.
    - Repro builds but reproduces intermittently (flaky) → record flaky-repro status; continue pre-impl with hardening focus (more instrumentation, longer test runs, stress mode).
    - Repro cannot be built; high agreement (K=N) → `ask_user` with safety-critical re-confirmation per User-skip policy: defer-with-tracker / proceed-with-warning-and-extra-instrumentation / re-investigate.
    - Repro cannot be built; mid agreement (N/2 ≤ K < N) → `ask_user` default = defer-with-tracker / re-investigate.
    - Repro cannot be built; low agreement (K < N/2) → `ask_user` default = re-investigate (likely not a real bug).

## Reference UX walkthrough

Canonical scenario: user says `"find bugs in AuthMiddleware.cs, TokenService.cs, UserRepository.cs"`.

| Turn | Side | Action |
|---|---|---|
| 1 | User | "find bugs in AuthMiddleware.cs, TokenService.cs, UserRepository.cs" |
| 1 | Agent | Detects strong trigger; offer `ask_user`: "this looks like a `cross-file-bug-investigation` ask - want me to run that playbook?" |
| 2 | User | Approves |
| 2 | Agent | Bundle A `ask_user`: "Confirm scope (paths/basenames I'll resolve): AuthMiddleware.cs, TokenService.cs, UserRepository.cs" |
| 3 | User | Confirms |
| 3 | Agent | Pre-flight: resolves basenames → absolute paths; recent-changes check passes (clean tree); scope-size = 3 files (no `system-framing` offer); single-file gate doesn't fire (3 files) |
| 3 | Agent | Bundle B1 `ask_user`: "What's the symptom you're chasing?" (8 options) |
| 4 | User | Picks `unclear-behavior` |
| 4 | Agent | Bundle B2 `ask_user` with Q3 pre-filled (`cross-file-data-flow` + `contracts-and-state` for `unclear-behavior`) + Q4-Q9 |
| 5 | User | Accepts defaults EXCEPT Q7=`chat + GitHub issue` (so deferred findings get filed) |
| 5 | Agent | Writes `domain-state-cross-file-bug-investigation-<ts>`; launches 4 reviewers in parallel |
| ~5 min | Agent | All 4 reviewers complete; orchestrator dedups + ranks + citation-verifies |
| 6 | Agent | Renders report chat-first (findings without C2 status); `ask_user`: "Approve report?" |
| 7 | User | Approves |
| 7 | Agent | Step 11A - C2 routing `ask_user` with per-finding picker (route-fix-now / defer / dismiss) |
| 8 | User | Picks "fix-now F-0001 + F-0003; defer F-0002; dismiss F-0004 with counter-citation"; rest = defer |
| 8 | Agent | C2 resolved per finding; routed-deferred findings recorded to GitHub issues (per Q7 choice above; default `chat-only` would instead record as session todos); dismissed finding recorded with citation |
| 8 | Agent | Step 11B - Fix-transition picker `ask_user` (only for routed-now findings F-0001 + F-0003): skip / fix-one / fix-multiple / fix-all-blocking |
| 9 | User | Picks "fix-multiple F-0001 + F-0003" |
| 9 | Agent | Writes persistence file with selected findings; enters `pre-implementation.md` with file path as Q1 source |

Total user turns to report: ~5-6 `ask_user` prompts. Total user turns to fix-transition: ~8-9 (one extra turn for the C2-routing split per GPT-5.5 R3 finding).

## Truth tables

### Fix-transition gating

**Step 11A - C2 routing (ALWAYS happens after report approval):**

| User picks per finding | C2 status | External-record requirement |
|---|---|---|
| `route-to-fix-now` | `routed-now` | call-ref (this turn) |
| `route-deferred` | `routed-deferred` | tracker entry (Q7=GitHub issue) OR session-todo path |
| `dismiss` | `dismissed-source-grounded` | user-supplied counter-citation (REQUIRED) |

**Step 11B - Fix-transition picker (ONLY when Q8 ≠ `none`, only for `routed-now` findings):**

| State | Action |
|---|---|
| Q8 = `none` | Step 11B SKIPPED; `routed-now` findings stay user-acknowledged-no-fix-this-session |
| User picks `skip-this-session` | No pre-impl entry; `routed-now` findings persist for later |
| User picks `fix-one F-0001` | Persist F-0001 + enter pre-impl |
| User picks `fix-multiple F-0001 + F-0003` | Persist selected + enter pre-impl with aggregate scope |
| User picks `fix-all-blocking` | Persist all `routed-now && is_blocking=true` + enter pre-impl |
| Agent enters pre-impl without `ask_user` in 11B | VIOLATION |
| Agent enters pre-impl without file persistence | VIOLATION |
| User picked `skip-this-session` earlier, requests fix N turns later | Re-invoke 11B picker (or re-run investigation if report stale) |

### Citation verification

| Reviewer state | Action | Logged |
|---|---|---|
| ≥1 `file:line`; view confirms claim | `verified` → included | - |
| ≥1 `file:line`; view shows code differs | `verification-failed-dropped` | yes |
| ≥1 `file:line`; cited line doesn't exist (file missing OR line out of range) | `verification-invalid-dropped` | yes |
| ≥1 `file:line`; view ambiguous | `verification-ambiguous-rework-1` → re-prompt reviewer once via `write_agent` | - |
| After 1 rework, still ambiguous | `verification-twice-ambiguous-dropped` | yes |
| No `file:line` | DROPPED at first synthesis (no rework) | yes |

### Observational loop-back (pre-impl reproduce step)

| Pre-impl reproduce outcome | Routing |
|---|---|
| Repro built successfully | Continue normal pre-impl |
| Repro builds but reproduces intermittently (flaky) | Record flaky-repro status; continue pre-impl with hardening focus |
| Repro can't be built; K=N agreement | `ask_user` with safety-critical re-confirmation: defer-with-tracker / proceed-with-warning-and-instrumentation / re-investigate |
| Repro can't be built; N/2 ≤ K < N | `ask_user` (default = defer-with-tracker) |
| Repro can't be built; K < N/2 | `ask_user` (default = re-investigate; likely not a real bug) |

## Output

Chat-rendered bug-investigation report grouped by finding-id + cumulative evidence-gate log from `multi-model-review.md` + per-finding C2 disposition from step 11A.

Selected fix-transition findings (when Q8 ≠ `none` AND user picks fix) persisted to `<session-state>/files/bug-investigation-<ts>.md` (schema_version: 1) and handed off to `pre-implementation.md`.

Optional outputs per Q7:
- `chat + session-state file`: bug-investigation report file at `<session-state>/files/bug-investigation-report-<ts>.md`.
- `chat + GitHub issue`: one issue per `routed-deferred` finding (and optionally per `routed-now` finding for tracking) with finding YAML+markdown body + labels `bug-investigation` + `severity-<level>`.

## Phase enforcement

DOMAIN playbook (strong-trigger; user-invoked). Not a phase playbook.

- **Pre-implementation phase**: when investigation produces a fix-transition (step 12 → step 15), that fix enters pre-impl normally. G3 approach-selection / G5 safety-critical-skip / G6 playbook-offer evaluation all apply. The investigation report's "Suggested fix class" is ONE candidate approach for G3 - the user / pre-impl panel may choose differently.
- **Post-code-change phase**: not directly triggered by investigation (investigation is read-only). When the fix-transition lands code edits, post-code-change runs normally including the multi-model panel hard gate.
- **Pre-PR-creation review**: not directly triggered by investigation. When the fix-transition's PR is opened, §2D heavy panel runs normally.
- **POST-CODE-CHANGE LEDGER**: investigation does NOT add to ledger sub-blocks (it's a domain playbook fired on user trigger; the orchestrator hard gates above are runtime-enforced, NOT panel-time review-pass checks at commit time).
- **Decline-then-no-retry + session suppression**: per AGENTS rule, decline of the strong-trigger offer doesn't re-offer in the same thread. Q9 (`session_suppression`) extends this with `until-explicit-invoke` (suppress for whole session; user must explicitly name the playbook) and `always-offer` (re-offer every session). Documented in intake; recorded on domain-state record.

## Cross-references

- `multi-model-review.md` + `multi-model-review/intake.md` + `multi-model-review/procedure.md` + `multi-model-review/evidence-gate-spec.md` - utility engine; `target-type=bug-investigation` defined there with lane-specialized prompt template + VERDICT-emission rule.
- `cross-file-bug-investigation/lanes-catalog.md` - 9 lane definitions referenced by intake Q3.
- `pre-implementation.md` - fix-transition destination; reads persisted findings file from step 14 via its "Entry points" subsection.
- `codebase-architecture-audit.md` - sibling read-only audit (5-lens architectural debt); distinct mechanism + scope.
- `least-privilege-audit.md` - sibling read-only audit (6-axis visibility); cross-ref from `security-and-surface` lane.
- `code-review` sub-agent (built-in) - for single-file diff review when this playbook's single-file gate routes there.
- `system-framing.md` - sibling for ORIENTATION; offered at scope-size guard when ≥10 files.
- `performance-comparison.md` - alternative route for `performance-degradation` symptom (benchmark-prototype work).

AGENTS sections drawn from: §3.1 (comment audit - for findings about stale comments), §3.6 (parameter consistency), §3.7 (state predicates / match-equality uniqueness), §3.8 (defer state mutations / idempotency-first ref handoff), §3.10 (recurring code smells from past PR reviews), User-skip policy (safety-critical re-confirmation), Phase-state tracking convention (domain-state-* id family is parallel to phase-state-* - NOT a phase record).
