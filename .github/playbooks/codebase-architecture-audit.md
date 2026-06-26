---
name: codebase-architecture-audit
description: Use when user wants a read-only audit of an existing codebase against established practices. Produces a ranked list of improvement opportunities with file:line citations, NOT a durable design doc (use design-spec for that). Default scope is all 5 lenses (state predicates, deferred mutations, recurring smells, project layout, vertical slice + clean-architecture overlay).
triggers:
  - "architecture audit for"
  - "audit my architecture"
  - "codebase architecture review"
  - "where is this codebase weak"
  - "ball-of-mud check"
  - "find architectural debt"
---

# Codebase architecture audit

## Purpose

Read-only audit of an existing codebase (or one project / subsystem) against established practices: state predicates (§3.7), deferred state mutations (§3.8), recurring code smells (§3.10), project layout conventions (§3.11), and vertical-slice + clean-architecture overlay (§3.12). Produces a **ranked list of improvement opportunities** with `file:line` citations. The user picks proposals to act on; each picked proposal becomes a normal change going through the standard phase playbook chain.

**Does NOT produce a durable design doc** - that's `design-spec.md`. Strong-trigger discriminator: *"audit"* / *"review"* / *"find debt"* / *"where is X weak"* → here; *"design spec for"* / *"document current architecture of"* / *"architect review of"* → `design-spec.md`.

## Hard gates

- **Read-only**: no code edits during the audit. Each finding is a proposal; the user accepts, defers, or rejects. Accepted proposals become separate code changes through the full phase playbook chain.
- **Intent-clarity justification**: every proposal includes a one-line statement of how the change clarifies intent for a future reviewer (per §3.10 "clear intent for anyone reviewing").
- **Aggregated evidence-gate output**: per-lens audit summaries aggregated as structured chat output before the ranked findings list (see *Procedure* step 4).
- **All 5 lenses by default**: full audits apply all 5 lenses unless intake explicitly narrows. Single-lens fetches allowed when the user names a specific lens.
- **Greenfield short-circuit**: if no in-scope code exists, output one-line not-applicable; offer `scope-planning.md` / `implementation-planning.md`.

## Phase enforcement

OFFERED (informational) - NOT catalog-enforced in cycle-3. The originally-planned `pre-impl-skipped-codebase-architecture-audit-on-unfamiliar-code` rule was DROPPED because the proposed detection mechanism (`session_files` SQL cross-check) was unreliable: `session_files` records only edit/create operations, lives in the DuckDB cloud session store, and is empty post-compact. `pre-implementation.md` G6 may informally surface a codebase-architecture-audit offer when the plan touches unfamiliar code areas, but no `trigger-detected-codebase-architecture-audit` / `playbook-decision-codebase-architecture-audit` LEDGER line is required and no catalog rule fires on its absence.

## Intake questions

Bundle in one `ask_user` prompt:

1. **Scope**: whole solution / one project / one subsystem / one folder. Required.
2. **Lens selection**: all 5 (default) OR a subset. Lens names: `state-predicates`, `deferred-mutations`, `recurring-smells`, `project-layout`, `vertical-slice-clean-arch`.
3. **Risk tolerance**: surface-all (every finding ranked, including style-adjacent) OR substantive-only (default - bugs, leaks, intent-obscuring naming, structural debt).
4. **Output destination**: chat-only (default) or save to a doc (ask for destination if save).

## Scoped invocation as a commit gate (the `vsa-audit` ledger row)

The post-code-change and pre-pr-push phases (AGENTS.md) invoke this audit in a NARROWED, non-interactive form as the `vsa-audit` hard gate. There is NO intake prompt: the scope is fixed by the diff and the lens is fixed to `vertical-slice-clean-arch` only.

- **Touched-file scope** (post-code-change): run the vertical-slice lens over the files the diff ADDS / MOVES / RENAMES, plus any EXISTING file the diff modifies to add a top-level type, become multi-type, or change a root-level placement, plus the assembly each lands in. Fire only when the diff adds a new type or file, moves or renames a file, adds a root-level file to a folder-organized assembly, adds a new top-level type to an existing file, or introduces a multi-type file.
- **Branch-wide scope** (pre-pr-push): run the lens over every file added / moved / renamed across `git diff <base>..HEAD`, plus any existing file the branch modifies to add a top-level type, become multi-type, or change a root-level placement, re-grepped against the final branch state.

Checks (the lens criteria, applied to the scoped files):

1. Each new / moved type lands in the correct slice (feature / domain folder), or in `Common/<Domain>/` only for a genuine cross-slice / cross-asm type (never flat `Common/`, never a KIND-bucket `Models/` / `Helpers/` / `Utils/`).
2. One top-level type per file; split multi-type files.
3. No root-level outlier in an assembly that otherwise organizes by feature folders.
4. A uniformly-flat small assembly with NO existing folders is NOT an outlier; do NOT folderize it just to add structure (gold-plating per §3.13). Uniformly-flat means no production source subfolders (generated / `bin` / `obj` excluded) AND you cannot name 2+ coherent future slices or domains for it per §3.13; the carve-out expires once a second slice or domain clearly emerges, after which the normal slice-placement rule applies. A documented prior CLEAN verdict for such an assembly stands unless the user explicitly overrides it.

Output is the `vsa-audit` ledger row (review-workflow-gates-sweeps.md §2B): `ran (N placements checked, K misplaced)` or a cited `N/A - <playbook>:<line>` (cite this section's fire conditions when none are met - no added/moved/renamed file, no new top-level type in an existing file, no multi-type file introduced, no root-level placement change). Fresh grep beats any cached survey or prior audit verdict; when a scoped finding contradicts a prior audit, record the contradiction so the prior audit can be corrected.

## Procedure

1. **Greenfield pre-check** - `grep` / `view` to confirm in-scope code exists. If empty, surface and stop.
2. **Lens dispatch** - for each selected lens, fetch the corresponding `codebase-architecture-audit/lens-*.md` sub-file and run its procedure. Each sub-file emits a per-lens evidence-gate output (findings count + citations + zero-count justification).
3. **Aggregate findings** - collect findings from each lens; flag cross-lens overlaps (a single `file:line` flagged by multiple lenses); rank by severity (blocker > major > minor) within each lens.
4. **Aggregated evidence-gate output** (chat-visible before the ranked list):

   ```
   Architecture audit: scope=<project/solution path>, lenses=<list applied>, L lenses checked, F findings total.
   - <lens>: N findings (severity: B blocking / M major / N minor) - top citations: <file:line list>
   - <lens>: N findings - (zero-count justification when 0: "0 findings - scope <X> scanned by <command>, no §3.Y violations")
   - cross-lens overlaps: D - <list of file:line flagged by multiple lenses>
   ```

5. **Ranked findings list** (chat-rendered) - one section per lens, findings ordered severity-descending. Each finding:

   ```
   - **<finding title>** (severity: <B/M/N>)
     - Location: <file:line>
     - Issue: <one-paragraph description>
     - Proposal: <one-sentence change>
     - Intent-clarity justification: <how the change clarifies intent for future reviewers>
     - Related: <other findings if any>
   ```

6. **User selection** - user picks which proposals to act on. Picked proposals become NEW changes through the phase playbook chain; deferred proposals routed via `ask_user` per the cross-cutting *Pre-existing issues* rule (fix now / defer to issue / dismiss with source-grounded rationale).
7. **Save (optional)** - if user wants the report saved, ask for destination; `create` only after explicit approval.

## Output

Chat-rendered ranked findings list grouped by lens + aggregated evidence-gate audit output. Picked proposals become separate code changes; deferred proposals routed per Pre-existing issues rule. Optional file save to user-approved destination.
