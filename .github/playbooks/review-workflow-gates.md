---
name: review-workflow-gates
description: Mandatory review workflow gates covering the rubber-duck-then-panel two-stage process, PR review root-cause analysis, scope reduction sign-off, and panel convergence iteration. Referenced by pre-implementation and post-PR-review phases.
triggers: []
---

# Playbook: Review workflow gates

## Purpose

Codifies the mandatory review workflow that prevents wasted cycles — both in the pre-implementation panel process and in PR review loops. Every rule here is a hard gate; skipping any stage requires explicit user approval with documented justification.

This playbook is referenced by:
- `pre-implementation.md` — for the two-stage review before code changes
- `post-pr-review.md` — for PR comment root-cause analysis
- `AGENTS.md` cross-cutting rules — for scope reduction sign-off

---

## 1. Two-stage review: rubber-duck then panel

### Why two stages

A rubber-duck critique is cheap (one agent, fast turnaround) and catches blind spots before they compound across a full panel review. Feeding rubber-duck findings into the panel means the panel starts from a stronger baseline, reducing iteration rounds from ~4-5 to ~2-3.

### Procedure

1. **Stage 1 — Rubber-duck critique.** Launch a single rubber-duck agent with the plan/design/implementation. Receive findings.
2. **Triage rubber-duck findings.** Adopt findings that clearly prevent bugs or test failures. Set aside findings that would significantly complicate the implementation without clear benefit. Document the triage rationale.
3. **Incorporate adopted findings** into the plan/design before Stage 2.
4. **Stage 2 — Full multi-model panel.** Launch the panel per `multi-model-review.md` with the rubber-duck-improved plan. Iterate until unanimous convergence.

### When to apply

- **Always apply** for non-trivial changes: multiple files, architectural decisions, unfamiliar codebases, complex logic, new patterns, restructuring work, decomposition, DI changes, dependency graph changes.
- **May skip Stage 1 (rubber-duck) only** for genuinely trivial changes: single-file rename, typo fix, version bump, comment update. Even then, Stage 2 (panel) is still mandatory per the pre-implementation hard gate.

### Skip escalation

Skipping either stage requires **all three**:

1. Explicit user approval via `ask_user` — not implicit silence.
2. A documented justification stronger than "low risk" or "simple change." Acceptable justifications: "user explicitly directed immediate implementation," "change is a mechanical rename with no behavioral delta and automated refactoring tool output."
3. The skip recorded in the session state so future review can audit the decision.

---

## 2. PR review comment root-cause analysis

### The problem this solves

When a PR review comment (bot or human) identifies an issue, a surface-level fix that passes the immediate check but leaves the underlying pattern in place causes the same class of issue to be flagged again in subsequent reviews. This wastes reviewer time, developer time, and erodes confidence in the review process.

### Hard gate

Every PR review comment must be analyzed through this checklist before marking it resolved:

1. **Root cause identified.** What pattern, assumption, or gap caused the issue? Not "this line was wrong" but "this type of line is consistently missed because X."
2. **Fix addresses root cause.** The change prevents the issue from recurring, not just from appearing at this specific location.
3. **Similar patterns swept.** Search the rest of the diff (and ideally the rest of the changed files) for the same pattern. Fix all instances in one pass, not one at a time across review rounds.
4. **Instructions updated.** If the comment reveals a gap in the instruction set (a pattern the pre-implementation panel should have caught but didn't), propose an instruction-file delta:
   - A new sweep pattern in `post-code-change.md`
   - A new checklist item in the relevant playbook
   - A new hard gate if the issue class is severe enough
5. **Repeat-finding test.** Before re-requesting review, mentally simulate: "If the same reviewer runs the same review pass, will they find the same class of issue anywhere in the diff?" If yes, the fix is incomplete.

### Repeat findings are process failures

When the same class of issue is flagged across multiple review rounds:

1. Treat it as evidence that the pre-implementation panel missed something.
2. Identify why the panel missed it (was the pattern not in the sweep list? Was the reviewer angle too narrow? Was the rubber-duck stage skipped?).
3. Feed the learning back: update the instruction set, add a sweep pattern, or adjust panel reviewer angles.

---

## 3. Scope reduction sign-off

### Rule

When a panel, audit, or review identifies work items and the agent or sub-agents recommend deferring, dropping, or descoping any item — regardless of rationale — the recommendation **must** be presented to the user via `ask_user` with:

1. **The item** being deferred/dropped.
2. **The rationale** for deferral (YAGNI, low priority, compliance theater, borderline finding, etc.).
3. **Dissenting opinions** from any panel member who disagreed with the deferral.
4. **The consequence** of deferring (what risk does the user accept?).

### What is NOT acceptable

- Unilaterally dropping scope because a reviewer said "defer."
- Presenting a summary that omits deferred items.
- Marking items as "dropped" without user confirmation.
- Using labels like "out of scope," "pre-existing," "low severity" as justification without user sign-off.
- Deciding that an item is "compliance theater" without user agreement.

### The agent does NOT have authority to drop scope

Only the user can decide what is deferred vs. what is done. The agent's role is to present the options with context; the user's role is to decide. This applies to:

- Panel findings during pre-implementation review
- Audit remediation items
- PR scope decisions
- TODO list triage
- Any context where identified work is being deprioritized

---

## 4. Panel convergence iteration

### The iteration loop

1. **R1:** All reviewers review the initial artifact. Collect verdicts.
2. **Synthesize findings.** Group by theme, identify consensus vs disagreement.
3. **Apply fixes** for all items where the panel agrees.
4. **Present disagreements** to the user for decisions (per §3 scope reduction sign-off).
5. **R2:** All reviewers re-review the revised artifact. Repeat until convergence.

### Convergence criteria

- **Target: unanimous SOUND** from all panel members.
- **Acceptable: ≥4/5 SOUND** when the remaining NEEDS items are trivial fixes (link corrections, wording tweaks) that can be applied without another full round.
- **Not acceptable:** declaring convergence with any unresolved blocking or high-severity finding.

### Max iterations

If the panel has not converged after 5 rounds, escalate to the user:

1. Present the remaining disagreements.
2. Ask the user to decide each contested point.
3. Apply user decisions as final.
4. Run one last confirmation round to verify no regressions from the final edits.

### Cross-round learning

After convergence, review which issues survived to later rounds:

- Issues caught in R3+ that should have been caught in R1 indicate a reviewer-angle gap.
- Issues caught by one model family consistently indicate that model's strength should be assigned to that angle.
- Issues that required user escalation indicate the panel's scope for that artifact type needs refinement.

Document these learnings for future panel configurations.

---

## Appendix: relationship to other playbooks

- `pre-implementation.md` — invokes §1 (two-stage review) and §4 (panel convergence) during the plan review gate.
- `post-code-change.md` — invokes §4 (panel convergence) during the multi-model reviewer panel.
- `post-pr-review.md` — invokes §2 (root-cause analysis) when processing reviewer comments.
- `multi-model-review.md` — owns the panel mechanics (reviewer selection, verdict format, model assignments); this playbook owns the workflow gates around when/how panels run and what happens with their output.
- `AGENTS.md` cross-cutting rules — references §3 (scope reduction sign-off) as a hard gate.
