# Playbook: Pre-implementation phase

## Purpose

Run the diagnosis verification + rubber-duck pass before writing any code. This is the highest-leverage moment to catch design flaws — course-corrections here are the cheapest. Fires immediately when a code change is requested, before any implementation begins.

## Hard gates (these stay always-loaded in `AGENTS.md` too — repeated here for procedural context)

- Diagnosis verified against source. Treat any root-cause claim from a prior agent, plan, report, bug, or user prompt as a **hypothesis** to confirm before designing a fix.
- Reproduction or benchmark exists when applicable (no fix without a number that moves).
- Rubber-duck pass run unless user explicitly skipped (with recorded warning per User-skip policy).

## Intake questions

Bundle these in one prompt:

1. What's the diagnosis you're acting on, and where did it come from? (your hypothesis / prior agent / bug report / user prompt)
2. Do you have a reproduction (functional bug) or benchmark (perf regression) already, or do I need to build one?
3. **Default to running the rubber-duck pass.** Skipping is the exception, not the default. If you believe a change is trivial enough to skip (e.g. single-line typo, single-property rename with no semantic change, single config-key value tweak), call that out explicitly so the user can confirm — and if confirmed, the skip is recorded as an explicit skip and reported in the final summary (see User-skip policy). If unsure, run the rubber-duck pass.
4. **Perf work only:** what specific number do you expect to move, and by how much? (If the proposed fix wouldn't move that number, the diagnosis is wrong — stop and re-investigate.)
5. **Bug fix only:** can the bug be reproduced reliably? (If not, the bug isn't understood yet — re-investigate before designing a fix.)

## Procedure

### 1. Verify the diagnosis

Read the implicated code and confirm the mechanism behaves as described **before** designing a fix.

- **Perf work:** identify (or write) a benchmark or test that measurably captures the regression. If that number wouldn't move after the proposed fix, the diagnosis is wrong — stop and re-investigate. No fix without a number that changes.
- **Bug fixes:** write a failing test that reproduces the bug first. If you can't reproduce it, the bug isn't understood yet.
- **Cleanup of ad-hoc benchmarks/tests:** any benchmark or test created **solely to validate a diagnosis or fix** must be removed before the change is reported complete, unless the user explicitly asks to keep it. Capture the resulting numbers in the task summary or commit body so the evidence is preserved without leaving throwaway code in the tree.

### 2. Rubber-duck the plan

Always include in the prompt to the rubber-duck agent: *"Is the named root cause actually true? Verify against the source before evaluating the fix."*

Request a critique covering:

- Correctness of the diagnosis (does the code actually behave as the diagnosis claims?).
- Soundness of the proposed approach.
- Edge cases the proposed fix would miss.
- Any cross-cutting concerns the user / prior agent didn't raise (state predicates, defer-mutations-until-success, recurring smells, etc. — see `AGENTS.md` §3).

Address findings or explicitly justify dismissal. Adopt findings that clearly prevent bugs or test failures; set aside findings that would significantly complicate the implementation without clear benefit.

### 3. Record state and proceed

After the rubber-duck pass:

- Record phase-state: phase entered, intake complete, rubber-duck run (or skipped with user warning).
- If the rubber-duck surfaced findings outside scope of the immediate task, route them via `ask_user` per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule in `AGENTS.md` §1 — never silently expand scope.
- Proceed to implementation. Next phase: `post-code-change.md`.

## When to skip the rubber-duck

The user may explicitly skip the rubber-duck pass for genuinely trivial changes (typo fix, single-line config tweak, obvious one-character bug). When they do:

1. Warn in one sentence: *"Skipping rubber-duck on this change means I cannot independently validate the diagnosis."*
2. Record the skip.
3. Mention in the final summary that rubber-duck was skipped at user's request.
4. **Safety-critical work** (concurrency, security, native interop, cryptography, shared state, payment / financial logic) — even "trivial" changes should NOT skip rubber-duck. Re-confirm with the user if they ask to skip in these areas.
