---
name: implementation-planning
description: Use when user is ready to design a specific code change in detail. Reads the codebase, surfaces missed callers / undocumented decisions / jargon mismatches, produces an implementation plan that feeds the pre-implementation phase. Optional enrichment from scope-planning output and a project vocabulary doc.
triggers:
  - "plan this change in detail"
  - "deep planning for"
  - "ready to design the change"
  - "implementation plan for"
  - "design this change"
---

# Implementation planning

## Purpose

Deep planning for a specific code change, **codebase-aware**. Reads the modules being touched, surfaces missed callers, undocumented decisions, and jargon mismatches; produces an implementation plan that feeds the `pre-implementation` phase. The middle stage of the planning chain: `scope-planning` → **`implementation-planning`** → `pre-implementation` (phase).

**Inputs**: none required (the playbook runs standalone). Optional enrichment:

- `scope-planning.md` output (Q&A summary with named fields per the B1 → B3 handoff contract).
- Project vocabulary doc (any path; defaults to `project-vocabulary.md` at repo root). When missing, the playbook runs in **degraded mode** (see *Procedure* step 3).

**Output schema** (consumed by `intent-driven-testing.md` prospective trigger and `pre-implementation` phase): `implementation_plan`, `decision_records`, `behaviors_to_cover`, optional `vocab_updates`.

## Hard gates

- **Output-write ordering**: implementation plan + decision records rendered in chat first. Save to file only on explicit user request + destination approval.
- **Evidence-gate output**: implementation plan audit with scope, citations, zero-count justifications before the plan draft (see *Procedure* step 6).
- **Source-grounded claims**: every "X has N callers" / "Y depends on Z" claim cites `file:line`. Method (`grep`, `view`, call-graph tool) stated.
- **Greenfield short-circuit**: when there's no in-scope code, see *Procedure* step 1.
- **No fix code**: this playbook produces a PLAN, not implementation. Code edits are the next phase.

## Phase enforcement

REQUIRED-decision-recorded class. Detected at `pre-implementation.md` G6 step when the proposed change is non-trivial (closed-enumeration triviality: NOT in `{single-line typo, single-property/single-config-key tweak, comment-only edit, formatting-only edit}` AND has any other change in diff). Enforced by TWO catalog rules:

- `pre-impl-missed-implementation-planning-on-nontrivial-change` (HIGH, pre-impl) - fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.implementation-planning` is missing OR `not-applicable` / `offered-and-declined` / `not-required-trigger-not-detected`. Valid values: `invoked` OR `required-but-skipped: "<safety-critical re-confirmation per User-skip policy>"`.
- `implementation-planning-required-on-nontrivial-final-diff` (HIGH, post-impl) - companion that catches the scope-grew-during-implementation bypass: when `git diff <base>..HEAD` (final state) is non-trivial AND the ledger still says `not-required-trigger-not-detected`, fire. Satisfiability: the agent re-enters G6 per `pre-implementation.md` *G6 re-entry clause* and updates the LEDGER decision line.

## Intake questions

Bundle in one `ask_user` prompt:

1. **Change scope**: what code is changing? Modules / files / namespaces. Pre-fill from `scope-planning` output `in_scope` if available.
2. **Prior planning artifacts**: did `scope-planning` run first? If yes, paste the Q&A summary or path to it.
3. **Vocab doc**: path to project vocabulary doc, or "none" (triggers degraded mode and offers `project-vocabulary.md` as a follow-up).
4. **Decision record destination**: where do ADRs / decision records live? Common: `docs/adr/`, `docs/decisions/`, none (inline in plan).
5. **Behaviors to cover** (preview): list the testable behaviors the change must produce. Optional at intake; surfaced during step 5 if not provided.

## Procedure

1. **Greenfield pre-check** - if the user-stated change scope has no in-scope code yet, branch:
   - **Empty repo / no prior code**: output one-line not-applicable; offer `scope-planning.md` instead. Stop.
   - **New module in established repo**: continue, using sibling-module conventions (per AGENTS.md §3.6 *dominant or closest-in-purpose*) for the greenfield structure. Surface those conventions explicitly in the plan.
2. **Read change scope** - `view` / `grep` the named modules / files. Build a working list of:
   - Public API entry points.
   - Direct callers (cross-module / cross-project).
   - Tightly-coupled siblings (shared state, shared types, ordering dependencies).
   - Undocumented invariants discoverable from the code (state predicates, deferred mutations, framework-mandated visibility).
3. **Vocab gap pass**:
   - **Vocab doc exists** - read it; map every project-specific term in the change scope to a vocab entry; flag terms with no entry as "vocab gaps".
   - **Vocab doc missing (degraded mode)** - build an inline glossary of project-specific terms encountered in the change scope; mark each term as "unresolved - risk" so downstream readers know the meaning may drift. Offer `project-vocabulary.md` as a follow-up workflow.
4. **Decision surface** - identify decisions the change forces (naming, structural placement, breaking-change vs additive, public vs internal, sync vs async, error model). For each: choice + one-sentence rationale + alternatives considered. Source decisions in the plan; promote to ADRs (at the chosen destination) only on explicit user approval.
5. **Behaviors-to-cover** - enumerate testable behaviors the change must produce. This populates the `behaviors_to_cover` output field that triggers `intent-driven-testing.md` prospective mode. Each entry: behavior name + observable assertion + would-fail-if condition (per AGENTS.md §3.4 Direction A: *"what real regression would this catch?"*).
6. **Evidence-gate output** (chat-visible before the plan draft):

   ```
   Implementation plan audit: scope=<modules read, method=grep|view|callgraph>, C callers verified, D decisions surfaced, V vocab gaps, B behaviors-to-cover.
   - modules: <list with file:line>
   - callers: C verified (method: <X>) - <file:line citations OR "none - zero-count justification: scope has no cross-module consumers per <command>">
   - decisions: D items - <list with one-line rationale>
   - vocab gaps: V terms - <list with codebase citations OR "none - zero-count justification: every term in scope has vocab entry per <path>">
   - behaviors-to-cover: B behaviors - <list OR "none - zero-count justification: change is pure refactor with no observable behavior delta per <reason>">
   ```

7. **Plan draft** (chat-rendered) - four output-schema sections:

   ```
   ## implementation_plan
   <Step-by-step approach: code structure, sequencing, hand-offs.>

   ## decision_records
   - <decision>: <choice> | rationale: <one sentence> | alternatives: <list>

   ## behaviors_to_cover
   - <behavior>: <observable assertion> | would-fail-if: <condition>

   ## vocab_updates (optional)
   - <new term>: <one-sentence definition> (citation: <file:line>)
   ```

8. **User approval** - wait for explicit approval before any file write (ADRs, vocab updates).
9. **Handoff** - confirm the plan is ready to feed `pre-implementation` phase (B9 diagnose + G3 approach-selection + G5 safety-critical-skip evaluation + rubber-duck verification + benchmark/repro if applicable, per Decision #32 numbered ordering).

## Output

Chat-rendered implementation plan with four named sections plus the evidence-gate audit output. ADRs and vocab updates written to user-approved destinations only. The `behaviors_to_cover` section is the trigger source for `intent-driven-testing.md` prospective mode at step 2 entry of pre-implementation procedure.
