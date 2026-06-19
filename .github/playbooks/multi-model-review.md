---
name: multi-model-review
description: Use when user wants to review a plan, design, spec, or non-trivial diff via a panel of multiple reviewer models. Codifies the iteration-loop convergence pattern (≥3 reviewers across model families, mandatory VERDICT line per reviewer, three convergence models, max-loop escalation). Also called by post-code-change.md's multi-model panel hard gate.
triggers:
  - "multi-model review for"
  - "review panel on"
  - "panel review of"
  - "run the reviewer panel"
  - "convergence review"
  - "cross-model critique"
---

# Multi-model review loop
<!-- read-receipt-token: a0ae506f -->

## Purpose

Codifies the panel-of-reviewers convergence pattern. Used as:

- **Trigger-fired domain playbook** for plan / design / spec / non-trivial-diff reviews when the user explicitly invokes it.
- **Utility-called by `post-code-change.md`** as the multi-model reviewer panel hard gate for every non-trivial change.
- **Utility-called by `cross-file-bug-investigation.md`** with `target-type=bug-investigation` for lane-specialized cross-file bug hunting on user-pointed unchanged code (lanes from `cross-file-bug-investigation/lanes-catalog.md`; target-type-specific 7-field finding schema + VERDICT-emission rule defined in `procedure.md`).

Procedure runs ≥3 reviewers in parallel across different model families, requires each to emit a `VERDICT: <success verdict | NEEDS_ANOTHER_ROUND>` line at output end (the success verdict is the target's phase token: `DESIGN_READY` for design-class targets, `CODE_REVIEW_READY` for a `diff` target), and iterates until convergence (or max-loop escalation). Sub-agents are sandboxed: tooling discipline forbids `ask_user`, file modifications, and recursive sub-agent launches.

## Hard gates

- **≥3 reviewers minimum** across different model families (e.g., one Claude family + one GPT family + one Gemini family) - single-model panels miss the cross-family diversity that surfaces blind spots.
- **Each reviewer emits a `VERDICT:` line** at output end. Reviewers that omit the verdict line are re-prompted once for the verdict; if still missing, their input is dropped and a replacement reviewer is launched.
- **Sub-agent prompts include**: comprehensive context (file paths, not inline content); critique focus areas; the required `VERDICT:` directive; tooling discipline (NO `ask_user`, NO file modifications, NO sub-agent launches).
- **Completion-wait via notifications**, NOT polling. Use the runtime's "agent finished" notifications to drive synthesis; do not call `read_agent` in a tight loop.
- **Convergence per chosen model** before declaring done (see `multi-model-review/convergence-models.md`).
- **C2 findings disposition required** between rounds - every reviewer finding is routed via the C2 status enum (`fixed | routed-now | routed-deferred | dismissed-source-grounded`) before the next round launches. **Target-type exception**: for `target-type=bug-investigation` (called by `cross-file-bug-investigation.md`), C2 routing is DEFERRED to the caller's Step 11A (after user report approval); the engine records `C2 dispositions this round: deferred-to-caller-step-11A` sentinel in evidence emission. See `multi-model-review/procedure.md` step 11 target-type variation for full semantics.
- **Max-loop escalation**: when the configured max-loop count is reached without convergence, surface remaining dissent to the user via `ask_user`. Do NOT silently loop past max-loop.
- **Evidence-gate output per round** (see `multi-model-review/evidence-gate-spec.md`).

## Intake

See `multi-model-review/intake.md` for the intake questions and pre-fill rules.

## Procedure

See `multi-model-review/procedure.md` for the parallel-launch protocol, sub-agent prompt template, synthesis flow, and loop-vs-escalate decision tree.

## Convergence models

See `multi-model-review/convergence-models.md` for the three selectable models (unanimous default / threshold ≥75% / confidence-weighted ≥80%) plus the asymptotic-convergence pattern documented from real iteration evidence.

## Evidence-gate spec

See `multi-model-review/evidence-gate-spec.md` for the per-round logging format, C2 findings audit format (per AGENTS.md cross-cutting findings audit), and `subagent_ask_user_calls=0` verification requirement.

## Output

Final synthesis + cumulative evidence-gate log + C2 dispositions + convergence verdict. When invoked by `post-code-change.md` as a hard gate, returns "panel passed" or "panel did not converge - escalation required" to the calling phase.

**Recording convergence in the LEDGER (this instructions repo).** When this panel backs a `post-code-change-panel: ran, unanimous` row, record each reviewer as one line of the `panel-transcript:` block in the `POST-CODE-CHANGE LEDGER` (`review-workflow-gates-sweeps.md` §2B): `- slot:<id> model:<id> family:<claude|gpt|gemini> role:<rubber-duck|code-review> tier:<heavy|light> verdict:<CODE_REVIEW_READY|NEEDS_REWORK> rounds:<n>`, plus exactly one `- findings:<one-line>` line per block recording what the panel caught and how it was resolved (a disclosure field, not proof; whole-value `<...>` placeholder fails closed). The transcript `verdict:CODE_REVIEW_READY` is the reviewer's final `VERDICT: CODE_REVIEW_READY` (a `diff`-target review emits the code-review success verdict; a reviewer's `NEEDS_ANOTHER_ROUND` is recorded as the ledger's `NEEDS_REWORK`); `rounds` is how many rounds that reviewer took to converge. `Test-PanelLedger` validates the slate against the full floor (always full in this repo, per `panel-policy.md` §"Mechanical enforcement"); a `slot` is the unique reviewer identity (distinct-by-slot). This is honest-ceiling: it records the converged composition, not proof the sub-agents ran.
