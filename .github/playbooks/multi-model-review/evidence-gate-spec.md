# Multi-model review - Evidence-gate spec

Per-round logging format + C2 findings audit format for `multi-model-review.md`. Emitted after every round (AFTER convergence check + C2 routing, per `procedure.md` step 12); cumulative log returned to caller on convergence or escalation.

## Per-round evidence-gate output

Emit this structured chat output AFTER the round's synthesis, convergence check, AND C2 routing - by this point all template fields below (Convergence, C2 dispositions, Next directive) are knowable:

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

- `round`, `reviewers`, `convergence_model`, `max_loops` - invocation parameters.
- `VERDICT` per reviewer - directly from the reviewer's output's `VERDICT:` line.
- `confidence` per reviewer - required when `convergence_model = confidence-weighted`; optional otherwise.
- `findings` counts - total per reviewer + severity breakdown.
- Dedup'd themes - root-cause grouping.
- Agreement counts - convergence strength signal.
- C2 dispositions with **status enum** + **citation** (see C2 audit format below).
- `subagent_ask_user_calls=0` - orchestrator-only routing proof per AGENTS.md cross-cutting rule (sub-agents must NEVER prompt the user).
- `Next` directive - explicit outcome for the next step.

**Additional fields for `target-type=bug-investigation` rounds**:

- `slot=<reviewer slot>: lane=<lane slug(s)>` - one line per reviewer slot recording the lane(s) assigned for the round (round-robin mapping per `procedure.md`'s `bug-investigation` template). Required for `bug-investigation`; absent for other target-types.
- `citation-verification: <V verified, D verification-failed-dropped, I verification-invalid-dropped, R rework-1, T verification-twice-ambiguous-dropped, N no-citation-dropped>` - synthesis-time outcomes per finding from the orchestrator's citation-verification sub-step (`cross-file-bug-investigation.md` hard gate 9). Required for `bug-investigation`; absent for other target-types.
- `C2 dispositions this round: deferred-to-caller-step-11A` - for `target-type=bug-investigation`, C2 routing is DEFERRED to the caller's Step 11A (which happens after user report approval per the caller's fix-transition protocol). The standard C2 dispositions row carries this sentinel value instead of resolving individual finding statuses. See `procedure.md` step 11 target-type variation.

### Per-round - chat-emission form (caveman)

Chat emits each round in this compressed grammar; the structured template above is the canonical/cumulative-log form. One KV line per reviewer; the dedup'd-themes + agreement enumeration STAYS (it proves synthesis - a bare count is fakeable).

```
round=<N> reviewers=<count> convergence=<unanimous|threshold|confidence-weighted> max_loops=<M>
- slot=<slot> model=<id> verdict=<READY|NEEDS> conf=<X%|na> find=<B>/<M>/<N>
- ... (one line per reviewer)
themes=[<slug-theme>:<K/N>, ...]   # dedup'd by root cause; K of N reviewers flagged
convergence=<yes | no:dissent-from-<slot>:"<finding>"> c2=<Fx>fx/<Rn>rn/<Rd>rd/<Dg>dg subagent_ask_user_calls=0
next=<DONE | LOOP_R<N+1> | ESCALATE>
```

`bug-investigation` target-type appends, in KV: `- slot=<slot> lane=<lane>` per reviewer; `citation-verification=<V>/<D>/<I>/<R>/<T>/<N>`; and the `c2` field carries the literal `deferred-to-caller-step-11A` sentinel.

## C2 findings audit format (cross-cutting hard rule)

The C2 status enum is used both inside this playbook (per-round disposition) AND by AGENTS.md cross-cutting findings audit (whenever any sub-agent surfaces a finding the orchestrator must dispose of). Format:

```
Findings audit: <N> sub-agent findings this task / round.
- <source agent + run/call id>: <finding id / summary>: status=<fixed | routed-now | routed-deferred | dismissed-source-grounded>: <citation per status>.
- ... (one bullet per finding)
- subagent_ask_user_calls=0 (orchestrator-only routing verified).
```

**Zero-count form** - when N=0, emit a single line instead of an empty bullet list:

```
Findings audit: 0 findings - all sub-agent outputs re-read; no findings found. subagent_ask_user_calls=0.
```

**Status definitions**:

- `fixed` - finding addressed by an edit in the diff / artifact. **Citation**: `file:line` of the change.
- `routed-now` - finding routed via `ask_user`; user decided in this turn. **Citation**: `ask_user` call ref + user decision summary.
- `routed-deferred` - finding deferred to a future session / external work item. **Citation**: issue tracker URL / session note path / external record id. **NOT acceptable**: deferral with no external record.
- `dismissed-source-grounded` - finding refuted by evidence from source. **Citation**: source location (`file:line`, doc URL, RFC, ADR) that refutes the finding. **NOT acceptable**: *"out of scope per reviewer"* without source grounding.

### C2 audit - chat-emission form (caveman)

Chat emits the C2 findings audit inline; the per-finding status + citation STAY (the enumeration is the proof, not a count).

```
Findings audit: <N> sub-agent findings. [<agent>:<finding-slug>=<status>:"<citation>"], ... subagent_ask_user_calls=0
```

Zero-count form: `Findings audit: 0 - all sub-agent outputs re-read; none found. subagent_ask_user_calls=0`. `<status>` in {fixed, routed-now, routed-deferred, dismissed-source-grounded}; `<citation>` per the status definitions above (file:line | ask_user-ref | tracker-id/URL | source-loc), quoted.

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
