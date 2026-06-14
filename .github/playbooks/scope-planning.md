---
name: scope-planning
description: Use when user wants to plan an idea, feature, or change before any code is written. Defines problem, users, success criteria, in-scope vs out-of-scope, and constraints. No codebase reading beyond scope validation; technical claims marked `assumed` unless verified later by downstream playbooks.
triggers:
  - "plan this idea"
  - "scope this out"
  - "what's the scope"
  - "scope planning for"
  - "let's plan before I start"
  - "before I start coding"
---

# Scope planning

## Purpose

Light planning **before any code is written**. Surfaces the problem, users, success criteria, scope boundaries, and constraints - the *what* of a change, not the *how*. Produces a structured Q&A summary the user can feed into downstream playbooks (`design-spec.md`, `ado-task-planning.md`, or directly into `implementation-planning.md` when the codebase-aware design step is needed). No codebase reading beyond scope validation; technical claims marked `assumed` unless and until verified by `implementation-planning.md` or the `pre-implementation` phase.

This is the **first** stage of the planning chain: `scope-planning` → `implementation-planning` → `pre-implementation` (phase). Each fires independently; chain only when the change warrants the depth.

## Hard gates

- **Output-write ordering**: structured Q&A summary rendered in chat first. No file write without explicit user request + destination approval.
- **Evidence-gate output**: scope audit produced as structured chat output before the Q&A summary (see *Procedure* step 4).
- **Marked assumptions**: any technical claim derived from the codebase (file path, type name, behavior) must be either citation-backed (`file:line`) or marked `[assumed]`.

## Phase enforcement

OFFERED class. Detected at `pre-implementation.md` G6 step when the scope statement is ambiguous (< 50 chars AND no scope-planning artifact citation in session - tightened from `< 100 chars OR missing` to reduce false-positive ledger noise). Enforced by ONE catalog rule:

- `pre-impl-skipped-scope-planning-when-scope-ambiguous` (MEDIUM, pre-impl) - fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.scope-planning` is missing OR `not-applicable` (silent-downgrade bypass). Valid values when detected: `invoked` / `offered-and-declined: "<user-quoted justification>"` / `required-but-skipped: "<reason>"`.

## Intake questions

Bundle all six questions in one `ask_user` prompt (independent; no conditional branching needed):

1. **Problem**: What problem are we solving? One sentence framing.
2. **Users**: Who are the users? (developers, end users, ops, internal stakeholders, external partners - be specific.)
3. **Success criteria**: How will we know it's done? Prefer measurable outcomes (latency below X ms, error rate below Y%, feature available to N users) over vague goals ("better UX").
4. **In-scope**: What's included in this change? Bullet list.
5. **Out-of-scope**: What's explicitly NOT included? Bullet list - naming exclusions prevents scope creep later.
6. **Constraints**: Technical (platforms, languages, frameworks), business (timeline relative to events not dates, compliance, budget), or organizational (team availability, dependencies on other teams).

Pre-fill from upfront input when the user opens with structured detail (`problem=..., users=...`). Confirm overloaded terms (*team*, *owner*, *scope*) before using them in the output.

## Procedure

1. **Intake** - ask the six questions; bundle independent ones in one prompt.
2. **Minimal scope-validation reading** (optional) - if a user-stated constraint or scope item references existing code (*"ensure this works with the existing X service"*), `view` or `grep` the named file/symbol just enough to confirm it exists. Do NOT explore beyond scope-validation purpose.
3. **Mark assumptions explicitly** - every technical claim in the output that was NOT verified gets `[assumed]` suffix. Examples:
   - *"Uses the existing LogService for emission"* → either `[verified: src/Logging/LogService.cs:14]` or `[assumed]`.
   - *"Will not affect the build pipeline"* → `[assumed]` unless the user states it as a confirmed constraint.
4. **Evidence-gate output** (chat-visible before the Q&A summary):

   ```
   Scope audit: scope=N/6 questions answered, V verified claims, A assumed claims.
   - problem: <one-sentence answer>
   - users: <answer>
   - success_criteria: <answer>
   - in_scope: <bulleted list>
   - out_of_scope: <bulleted list>
   - constraints: <bulleted list>
   - verified_claims: <list with file:line citations OR "none - zero-count justification: no technical claims required source verification">
   - assumed_claims: <list of unverified technical claims OR "none - zero-count justification: all claims source-verified above">
   ```

5. **Q&A summary in chat** - render the structured summary with the six named fields exactly. `implementation-planning.md` (B3) consumes by name per the B1 → B3 handoff contract; absent fields default to *"not specified"*.
6. **Offer next steps** - suggest concrete next playbooks based on the answers:
   - User wants a durable design artifact → `design-spec.md`.
   - User wants ADO work-item content → `ado-task-planning.md`.
   - User is ready to design the code change → `implementation-planning.md`.
   - None yet → output is the end state; user revisits when ready.

## Output

Chat-rendered structured Q&A summary with the six named fields (`problem`, `users`, `success_criteria`, `in_scope`, `out_of_scope`, `constraints`) plus the evidence-gate output. No file written by default. If the user wants the summary saved, ask for destination path and use `create` only after explicit destination + content approval.
