---
name: multi-model-review
description: Use when user wants to review a plan, design, spec, or non-trivial diff via a panel of multiple reviewer models. Codifies risk-tiered panels: full uses four distinct heavy reviewers; triage uses two distinct-family light reviewers with unanimous verdicts; rounds are uncapped. Also called by post-code-change.md's multi-model panel hard gate.
triggers:
  - "multi-model review for"
  - "review panel on"
  - "panel review of"
  - "run the reviewer panel"
  - "convergence review"
  - "cross-model critique"
---

# Multi-model review loop
<!-- read-receipt-token: f53a3039 -->

## Purpose

Codifies the panel-of-reviewers convergence pattern. Used as:

- **Trigger-fired domain playbook** for plan / design / spec / non-trivial-diff reviews when the user explicitly invokes it.
- **Utility-called by `post-code-change.md`** as the multi-model reviewer panel hard gate for every non-trivial change.
- **Utility-called by `cross-file-bug-investigation.md`** with `target-type=bug-investigation` for lane-specialized cross-file bug hunting on user-pointed unchanged code (lanes from `cross-file-bug-investigation/lanes-catalog.md`; target-type-specific 7-field finding schema + VERDICT-emission rule defined in `procedure.md`).

Procedure runs the mode-specific slate in parallel across different model families, requires each to emit a `VERDICT: <success verdict | NEEDS_ANOTHER_ROUND>` line at output end (the success verdict is the target's phase token: `DESIGN_READY` for design-class targets, `CODE_REVIEW_READY` for a `diff` target), and iterates until unanimous convergence. Sub-agents are sandboxed: tooling discipline forbids `ask_user`, file modifications, and recursive sub-agent launches.

## Hard gates

- Full mode uses at least 4 distinct heavy reviewers; triage uses exactly 2 distinct-family light code-reviewers with a same-turn receipt. All modes are unanimous.
- **Each reviewer emits a `VERDICT:` line** at output end. Reviewers that omit the verdict line are re-prompted once for the verdict; if still missing, their input is dropped and a replacement reviewer is launched.
- **Sub-agent prompts include**: comprehensive context (file paths, not inline content); critique focus areas; the required `VERDICT:` directive; tooling discipline (NO `ask_user`, NO file modifications, NO sub-agent launches).
- **Completion-wait via notifications**, NOT polling. Use the runtime's "agent finished" notifications to drive synthesis; do not call `read_agent` in a tight loop.
- **Convergence per chosen model** before declaring done (see `multi-model-review/convergence-models.md`).
- **C2 findings disposition required** between rounds - every reviewer finding is routed via the C2 status enum (`fixed | routed-now | routed-deferred | dismissed-source-grounded`) before the next round launches. **Target-type exception**: for `target-type=bug-investigation` (called by `cross-file-bug-investigation.md`), C2 routing is DEFERRED to the caller's Step 11A (after user report approval); the engine records `C2 dispositions this round: deferred-to-caller-step-11A` sentinel in evidence emission. See `multi-model-review/procedure.md` step 11 target-type variation for full semantics.
- **Convergence**: continue rounds until all required reviewers converge unanimously. Resolve availability and blocking findings through their defined gates; there is no round cap.
- **Evidence-gate output per round** (see `multi-model-review/evidence-gate-spec.md`).

## Methodology disclosures (honest ceiling)

These are reviewer-methodology practices + re-derivable disclosure receipts, NOT fail-closed gates in this increment (mechanical validation is future work):

- **Adversarial prompt framing** - orchestrator framing MUST be adversarial ("assume defects; find them") and MUST NOT pre-state the author's conclusion; any such claim is relocated to an `Author claims to DISPROVE` section reviewers attack, and a pre-dispatch `prompt-hygiene-scan:` disclosure is emitted. See `multi-model-review/procedure.md` §"Prompt hygiene (adversarial framing)".
- **Adversarial red-team reviewer** - on full-mode `diff`-target panels, >= 1 `code-review`-role reviewer red-teams the panel's own target diff with NO author narrative (small diffs not exempt). See `multi-model-review/procedure.md` §"Adversarial red-team reviewer".
- **Probing evidence for a countable verdict** - a success verdict counts toward convergence only with floor-meeting probing evidence (a `probing_evidence` block or its `probe:` chat lines); a bare confirmation is advisory-only. See `multi-model-review/evidence-gate-spec.md` §"Probing evidence".

## Intake

See `multi-model-review/intake.md` for the intake questions and pre-fill rules.

## Procedure

See `multi-model-review/procedure.md` for the parallel-launch protocol, sub-agent prompt template, synthesis flow, and loop-vs-escalate decision tree.

## Convergence models

See `multi-model-review/convergence-models.md` for the unanimous convergence rule and artifact-bound re-review protocol.

## Evidence-gate spec

See `multi-model-review/evidence-gate-spec.md` for the per-round logging format, C2 findings audit format (per AGENTS.md cross-cutting findings audit), and `subagent_ask_user_calls=0` verification requirement.

## Output

Final synthesis + cumulative evidence-gate log + C2 dispositions + convergence verdict. When invoked by `post-code-change.md` as a hard gate, returns "panel passed" or "panel did not converge - escalation required" to the calling phase.

**Recording convergence in the LEDGER (this instructions repo).** When this panel backs a `post-code-change-panel: ran, unanimous` row, record each reviewer as one line of the `panel-transcript:` block in the `POST-CODE-CHANGE LEDGER` (`review-workflow-gates-sweeps.md` §2B): `- slot:<id> model:<id> family:<claude|gpt|gemini|grok> role:<rubber-duck|code-review> tier:<heavy|light> verdict:<CODE_REVIEW_READY|NEEDS_REWORK> rounds:<n> artifact:<sha256>`, plus `evidence-tree: worktree-clean` or `evidence-tree: index-export tree:<full-tree-sha>` for staged-bound panels, the column-0 `profile:` and conditional `checker-edit:` / `triage-ack:` / `slate-substitution:` / `registry-rotation:` rows (exact forms: `panel-policy.md` §Checker-enforced ledger rows), and exactly one `- findings:<one-line>` line per block recording what the panel caught and how it was resolved (a disclosure field, not proof; whole-value `<...>` placeholder fails closed). The transcript `verdict:CODE_REVIEW_READY` is the reviewer's final `VERDICT: CODE_REVIEW_READY` (a `diff`-target review emits the code-review success verdict; a reviewer's `NEEDS_ANOTHER_ROUND` is recorded as the ledger's `NEEDS_REWORK`); `rounds` is how many rounds that reviewer took to converge. `Test-PanelLedger` validates the slate against the full floor (full-required in the instruction repo, per `panel-policy.md`); a `slot` is the unique reviewer identity (distinct-by-slot). This is honest-ceiling: it records the converged composition, not proof the sub-agents ran.
