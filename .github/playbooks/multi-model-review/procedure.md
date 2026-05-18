# Multi-model review — Procedure

Procedure for `multi-model-review.md`. Consumes intake from `intake.md`; emits evidence-gate output per `evidence-gate-spec.md`; applies convergence per `convergence-models.md`.

## Parallel-launch protocol

1. **Launch all N reviewers in parallel** as background sub-agents. Do NOT serialize the launches — parallel diversity is the point.
2. **Sub-agent prompt template** (every reviewer gets this structure):

   ```
   You are reviewing **<target type>** at **<path or reference>**.
   <Round context if iterating: round N of max M; prior-round findings shared per intake; v<N> incorporates amendments from round <N-1> — verify amendments address prior findings without introducing new issues.>

   **Key context files to read**:
   - <list of file paths the reviewer should view>

   **Critique focus** (vary per reviewer slot per intake — cross-family / technical-design / coding-discipline / rubber-duck design):
   1. <focus point 1>
   2. <focus point 2>
   ...

   **Format for findings**: bullet list, max ~10–15 bullets. Each: one-line summary + severity (blocking | major | minor) + where (file / section / line) if applicable + proposed mitigation.

   **REQUIRED: end your output with this single line**: `VERDICT: <READY_TO_IMPLEMENT | NEEDS_ANOTHER_ROUND>`

   **Tooling discipline**:
   - **Read-only inspection allowed**: `view`, `grep`, `glob`, and `powershell` for read-only git commands (`git --no-pager diff`, `git --no-pager show`, `git --no-pager log`, `git --no-pager status`) — reviewers reviewing a `diff` target MUST be able to inspect the diff independently.
   - Do NOT call `ask_user` or any other tool that prompts the user. Make reasonable assumptions, document them, continue.
   - Do NOT modify any files — this is a review pass.
   - Do NOT launch sub-agents.

   Return findings + verdict only.
   ```

3. **Differentiate reviewer slots** by varying the critique-focus angle per intake (cross-family fresh eyes / technical-design depth / coding-discipline / rubber-duck design critique). Each reviewer gets one differentiated focus emphasis on top of the shared focus areas.

## Completion-wait

4. **Wait for runtime notifications** ("Agent finished") rather than polling. The orchestrator should NOT call `read_agent` in a tight loop. When all N notifications arrive (or a timeout fires for missing ones), proceed to synthesis.
5. **Missing-verdict handling** — if a reviewer's output lacks the `VERDICT:` line, re-prompt with `write_agent` once for the verdict. If still missing, drop that reviewer's input and launch a replacement reviewer (same intake; adjusted prompt if the issue is identifiable). Record the missing-verdict event + replacement in the evidence-gate output.

## Synthesis

6. **Read each reviewer's output** via `read_agent` once per reviewer (idempotent — agents are idle post-completion).
7. **Dedup findings by theme** — multiple reviewers often surface the same finding from different angles. Group by root cause.
8. **Rank severity** — within each theme, the highest-severity classification across reviewers wins (if any reviewer flagged blocking, the theme is blocking).
9. **Agreement count** — record how many of the N reviewers flagged each finding (signals convergence-strength + helps prioritize routing).

## Convergence check

10. **Apply chosen convergence model** per `convergence-models.md`:
    - `unanimous` — all reviewers `READY_TO_IMPLEMENT` AND 0 unaddressed blocking → CONVERGED.
    - `threshold` — ≥75% `READY_TO_IMPLEMENT` AND 0 unaddressed blocking → CONVERGED.
    - `confidence-weighted` — avg confidence ≥80% AND 0 unaddressed blocking → CONVERGED.

## C2 routing (ALWAYS — converged rounds may still have non-blocking findings)

11. **Route each finding via the C2 status enum** (`fixed | routed-now | routed-deferred | dismissed-source-grounded`):
    - `fixed` — apply the change now (citation: file:line).
    - `routed-now` — route via `ask_user`; user decides this turn (citation: `ask_user` call ref).
    - `routed-deferred` — defer with external-record citation (session todo / issue / tracker URL). Asymptotic-convergence per `convergence-models.md` may auto-route precise polish here with an auto-created session-todo citation.
    - `dismissed-source-grounded` — refuted by explicit source citation.
    Default to `ask_user` for ambiguous routing. Converged rounds with 0 unaddressed blocking but ≥1 non-blocking finding still need C2 routing of those findings.

## Per-round evidence emission (ALWAYS — converged OR not, with complete fields populated)

12. **Emit per-round evidence-gate output** per `evidence-gate-spec.md` AFTER convergence check + C2 routing — by this point all template fields (verdicts, findings, agreement counts, **Convergence outcome**, **C2 dispositions this round**, **Next directive**) are knowable. This output is the canonical per-round audit trail; skipping emission on any round (converged or not) is a workflow violation.

## Loop-vs-escalate decision

13. **If CONVERGED** → append the round's evidence-gate output to the cumulative log; return to caller (Next directive: `DONE`).
14. **If NOT CONVERGED AND current_round < max_loop** (Next directive: `LOOP_AGAIN_ROUND_<N+1>`):
    - Increment round counter (accepted `fixed` findings already applied at step 11; do NOT re-apply here).
    - Go to step 1 with the updated target and prior-round findings as context.
15. **If NOT CONVERGED AND current_round = max_loop** — **escalate** (Next directive: `ESCALATE_TO_USER`):
    - Surface remaining dissent to the user via `ask_user`: *"max-loop reached at N rounds. Remaining dissent: <reviewer> says NEEDS because <findings summary>. Options: (a) apply final tightenings and run round N+1 (user-authorized exceedance), (b) accept threshold convergence with documented C2 dispositions, (c) document remaining findings as `routed-deferred` and proceed, (d) stop and reconsider plan."*
    - Do NOT silently loop past max-loop.

## Output

Returns to caller with: convergence outcome (CONVERGED / ESCALATED), final round number, per-reviewer verdicts, dedup'd findings list with severities and dispositions. Evidence-gate output emitted per `evidence-gate-spec.md`.
