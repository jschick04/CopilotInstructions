# Multi-model review — Evidence-gate spec

Per-round logging format + C2 findings audit format for `multi-model-review.md`. Emitted after every round (AFTER convergence check + C2 routing, per `procedure.md` step 12); cumulative log returned to caller on convergence or escalation.

## Per-round evidence-gate output

Emit this structured chat output AFTER the round's synthesis, convergence check, AND C2 routing — by this point all template fields below (Convergence, C2 dispositions, Next directive) are knowable:

```
Multi-model review loop: round=<N>, reviewers=<list with model IDs>, convergence_model=<unanimous|threshold|confidence-weighted>, max_loops=<M>.
- <reviewer slot>: VERDICT=<READY_TO_IMPLEMENT|NEEDS_ANOTHER_ROUND>, confidence=<X%> (when applicable), findings=<count> (blocking=<B>, major=<M>, minor=<N>).
- ... (one bullet per reviewer)
- Dedup'd findings (by theme): <T> themes, <F> total.
- Agreement counts: <theme>: <K of N reviewers flagged>
- Severity ranking: <top-severity per theme>
- Convergence: <yes | no, blocking dissent from <reviewer>: <finding summary>>
- C2 dispositions this round: <Fx> fixed, <Rn> routed-now (call refs), <Rd> routed-deferred (external record citations), <Dg> dismissed-source-grounded (source citations).
- subagent_ask_user_calls=0 (orchestrator-only routing verified).
- Next: <DONE | LOOP_AGAIN_ROUND_<N+1> | ESCALATE_TO_USER>.
```

**Required fields**:

- `round`, `reviewers`, `convergence_model`, `max_loops` — invocation parameters.
- `VERDICT` per reviewer — directly from the reviewer's output's `VERDICT:` line.
- `confidence` per reviewer — required when `convergence_model = confidence-weighted`; optional otherwise.
- `findings` counts — total per reviewer + severity breakdown.
- Dedup'd themes — root-cause grouping.
- Agreement counts — convergence strength signal.
- C2 dispositions with **status enum** + **citation** (see C2 audit format below).
- `subagent_ask_user_calls=0` — orchestrator-only routing proof per AGENTS.md cross-cutting rule (sub-agents must NEVER prompt the user).
- `Next` directive — explicit outcome for the next step.

## C2 findings audit format (cross-cutting hard rule)

The C2 status enum is used both inside this playbook (per-round disposition) AND by AGENTS.md cross-cutting findings audit (whenever any sub-agent surfaces a finding the orchestrator must dispose of). Format:

```
Findings audit: <N> sub-agent findings this task / round.
- <source agent + run/call id>: <finding id / summary>: status=<fixed | routed-now | routed-deferred | dismissed-source-grounded>: <citation per status>.
- ... (one bullet per finding)
- subagent_ask_user_calls=0 (orchestrator-only routing verified).
```

**Zero-count form** — when N=0, emit a single line instead of an empty bullet list:

```
Findings audit: 0 findings — all sub-agent outputs re-read; no findings found. subagent_ask_user_calls=0.
```

**Status definitions**:

- `fixed` — finding addressed by an edit in the diff / artifact. **Citation**: `file:line` of the change.
- `routed-now` — finding routed via `ask_user`; user decided in this turn. **Citation**: `ask_user` call ref + user decision summary.
- `routed-deferred` — finding deferred to a future session / external work item. **Citation**: issue tracker URL / session note path / external record id. **NOT acceptable**: deferral with no external record.
- `dismissed-source-grounded` — finding refuted by evidence from source. **Citation**: source location (`file:line`, doc URL, RFC, ADR) that refutes the finding. **NOT acceptable**: *"out of scope per reviewer"* without source grounding.

## Cumulative log

On convergence or escalation, return to caller:

- All per-round evidence-gate outputs (chronologically).
- Final round's dedup'd findings list with statuses.
- Convergence outcome (CONVERGED / ESCALATED-AT-MAX-LOOP).
- Any user-authorized max-loop exceedance + rationale.

## Verification

When the panel is utility-called by `post-code-change.md` (multi-model panel hard gate), the calling phase verifies:

- The cumulative log contains at least 1 round.
- The final round emitted convergence outcome.
- 0 unaddressed blocking findings (per the convergence model's blocking-clause).
- `subagent_ask_user_calls=0` on every round.

If any verification fails, the calling phase does NOT certify the multi-model panel as passed.
