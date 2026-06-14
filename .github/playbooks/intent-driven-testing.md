---
name: intent-driven-testing
description: Phase-sub-step that operationalizes AGENTS.md §3.4 (intent over coverage; gap audit in both directions). Two firing behaviors - prospective (one-test-then-implement loop in pre-implementation when implementation-planning.md emits non-empty behaviors_to_cover) and retrospective (audit whether the loop was followed in the post-code-change diff). Does NOT duplicate §3.4 - inherits its checklist verbatim.
triggers:
  - "use TDD"
  - "intent-driven testing"
  - "red-green-refactor"
  - "test-first loop"
  - "let's write tests first"
  - "tracer bullet"
---

# Intent-driven testing

## Purpose

Phase-sub-step that operationalizes AGENTS.md §3.4 (intent over coverage; gap audit in both directions) as a workflow with two firing behaviors:

- **Prospective** - *detection* in `pre-implementation.md` (when `implementation-planning.md`'s output schema contains a non-empty `behaviors_to_cover` section), *execution* IS the implementation phase (between pre-implementation and post-code-change). Pre-implementation records the per-behavior RED-test plan + regression-pin rationale; the actual RED → GREEN cycles run during implementation, NOT inside pre-implementation. Enforces one-test-then-implement loop; refuses horizontal slicing.
- **Retrospective** (in `post-code-change.md`): fires when the diff contains new test files OR a production SUT branch / public API delta vs the prior commit. Audits whether the loop was followed and surfaces gaps; does NOT pretend to enforce sequencing retroactively.

**Inherits AGENTS.md §3.4 checklist verbatim** - no parallel test doctrine. §3.4 is the always-applied universal standard; this playbook is the opt-in / auto-fired workflow that operationalizes it. AGENTS.md §3.4 carries a 1-line cross-reference pointing at this playbook for the workflow procedure.

## Hard gates

- **Inherits §3.4 hard prohibitions** - no tautological tests, no mock-only tests, no framework-testing tests, no tests that pin auto-property getters or other zero-behavior code.
- **Prospective mode - one test at a time**: each cycle is RED → GREEN → next cycle. NO horizontal slicing (write all tests then all code).
- **Per-test regression-pin justification (§3.4 Direction A)**: each test must answer *"what real bug would make this test fail?"* - recorded in the per-cycle evidence-gate output.
- **Behavior coverage audit (§3.4 Direction B)**: terminal evidence-gate output enumerates the SUT's in-scope behaviors and confirms each has a test, OR records the gap as a follow-up.
- **Retrospective mode - auditor, not enforcer**: post-code-change cannot enforce sequencing retroactively. Audit + surface gaps; do NOT fail the phase just because the loop wasn't visible in the diff.
- **Evidence-gate output** at three points (see *Procedure*): per-cycle (prospective), terminal completion (prospective), retrospective audit (retrospective).
- **Catalog rule cross-references**: this playbook's "playbook ran when test or SUT delta in diff" invariant is enforced by catalog rule `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH, review-pass-only). The rule fires when a commit's diff contains EITHER (a) NEW or modified test files OR (b) ANY production-source modification that changes the SUT surface - new exported member, signature change, new conditional branch (if/switch/?:/when), new state-mutating statement, new method declaration (public OR private), new error-handling branch, or new state-transition - AND the POST-CODE-CHANGE LEDGER `intent-driven-testing-audit` field is absent or has a bare `N/A` value without a documented carve-out. **Private-only SUT branch deltas DO trigger the rule** (private branches can implement new behavior; §3.4 Direction B requires coverage). Additionally, the per-test §3.4 Direction A check is enforced by catalog rule `test-without-direction-A-regression-pin` (MEDIUM, review-pass-only) - flags tests whose body pins no real regression. Both rules carve out: this playbook's retrospective audit is the AUTHORITATIVE source for `test-without-direction-A` findings; do NOT duplicate-flag in catalog if the retrospective audit already surfaced the test. See `pr-quality-gate/pattern-catalog.md` rows for full audit methods.

## Phase enforcement

NO cycle-3 catalog rule. Already enforced continuously by the cycle-2 catalog rule `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH, post-code-change) - fires when the diff contains test-file changes OR production-source modifications that change the SUT surface (new exported member, signature change, NEW conditional branch, new state-mutating statement, new method declaration, new error-handling branch) AND the POST-CODE-CHANGE LEDGER `gates.intent-driven-testing-audit` field is absent OR has bare `N/A` without carve-out citation. The design-phase enforcement piggybacks on `implementation-planning.md`'s REQUIRED-decision-recorded class (when the planning playbook runs and emits non-empty `behaviors_to_cover`, ITD-prospective fires automatically during implementation per `pre-implementation.md` Step 3).

## Intake

Inherits from the calling phase. No separate intake - fires automatically based on detection rules below.

### Prospective trigger detection

Fires when:

- `implementation-planning.md` ran in this session, AND its output schema contains a non-empty `behaviors_to_cover` section.

When detected, the agent informs the user: *"Detected N behaviors-to-cover from implementation-planning output. Engaging intent-driven testing prospective mode."* Then records the RED-test plan; the RED → GREEN cycles run during the implementation phase (NOT inside pre-implementation).

### Retrospective trigger detection

Fires when **any** of:

- The diff contains new test files (paths matching `**/*Tests.*`, `**/test_*`, `**/*.spec.*`, `**/__tests__/**`, or framework-specific patterns).
- The diff modifies a SUT branch or public API surface (visibility widening, new exported member, signature change) per `git diff` analysis.

When detected, the agent informs the user: *"Detected test surface change in diff. Engaging intent-driven testing retrospective audit."* Then runs the retrospective audit.

## Procedure

### Prospective mode

**Detection + plan recording happens in pre-implementation; the RED → GREEN cycles execute as the implementation phase** (between pre-implementation and post-code-change). Pre-implementation does NOT write production code - it records the per-behavior plan + Direction-A rationale.

#### Plan recording (in pre-implementation)

For each behavior in `behaviors_to_cover`, record (do not yet write code): the test name, the regression it pins (§3.4 Direction A), the assertion target (file path + observable behavior). This becomes the RED-test plan executed during implementation.

#### Execution loop (implementation phase, AFTER pre-implementation completes)

For each behavior, in plan order:

1. **RED** - write ONE failing test that pins the behavior. The test asserts the observable behavior (not internal implementation). Verify the test fails by running it; if it passes already, the test isn't actually testing the new behavior.
2. **GREEN** - write minimal code to make the test pass. No more code than necessary; no anticipating future tests.
3. **Per-cycle evidence-gate output**:

   ```
   Cycle N - <test name>:
   - regression pinned: <real bug that would make this test fail, traceable to §3.4 Direction A - "what real regression catches?">
   - asserts behavior (not implementation): yes (citation: assertion at file:line in test)
   - code minimal for this test: yes (citation: code added at file:line)
   ```

4. **Next cycle** - repeat for the next behavior. Do NOT batch tests; do NOT refactor while RED. Refactor only after GREEN.

When all behaviors covered (or the user explicitly stops mid-loop):

5. **Terminal completion evidence-gate output**:

   ```
   Test loop summary: N cycles completed.
   - all behaviors from §3.4 Direction B gap audit covered: <yes | user-stopped at <reason>>
   - mechanical-port commit exception (§3.4): <yes - gap list still required as follow-up | no>
   - Direction B gap list (when exception applies): <enumerated behaviors without coverage> (citations: file:line of SUT branches)
   ```

### Retrospective mode (in post-code-change)

The diff is already final; this is an audit, not enforcement.

1. **Enumerate the diff's test surface changes** - new test files, modified tests, deleted tests.
2. **Enumerate the diff's SUT branch / API changes** - visibility widening, new exported members, signature changes, new conditional branches.
3. **Cross-reference** - for each SUT change, is there a corresponding test? For each test change, is there a corresponding SUT change OR a Direction-A regression-pinning rationale?
4. **Retrospective audit evidence-gate output**:

   ```
   Test loop audit (retrospective): N new test files in diff, M production-SUT-deltas, G gaps identified.
   - gaps (SUT-delta without corresponding test): <SUT delta site → suggested test> (citations: file:line of each SUT delta) OR "none - zero-count justification: every SUT delta in scope has a corresponding test per cross-reference"
   - tests without §3.4 Direction A regression-pinning: <test name → recommended deletion / strengthening> (citations: file:line) OR "none - zero-count justification: every test in scope passes §3.4 Direction A check"
   - mechanical-port exception applies: <yes | no> (rationale: <one-line - if yes, gap list still required as follow-up commit>)
   ```

5. **Surface as follow-up candidates** - gaps and Direction-A-failing tests do NOT fail the post-code-change phase; they're surfaced for user disposition (fix-now / defer / dismiss) per the cross-cutting *Pre-existing issues / `ask_user` is mandatory* rule, using the C2 status enum (`fixed | routed-now | routed-deferred | dismissed-source-grounded`).

## Output

Three evidence-gate outputs (per-cycle, terminal, retrospective audit) depending on which mode fired. Tests + minimal implementation (prospective mode). Gap list + Direction-A audit (retrospective mode). All findings routed via C2 status enum if surfaced for user decision.
