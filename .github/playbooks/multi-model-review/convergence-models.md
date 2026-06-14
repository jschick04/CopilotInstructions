# Multi-model review - Convergence models

Three convergence models for `multi-model-review.md`. The user selects one at intake; the default is unanimous (strictest).

## Model A - Unanimous (default)

**Convergence condition**: ALL reviewers verdict `READY_TO_IMPLEMENT` AND 0 unaddressed blocking findings.

**When to use**: high-stakes artifacts (production code changes, security-sensitive specs, public API designs). Strictest - catches every concern; slowest to converge.

**Trade-off**: a single NEEDS verdict on a minor issue blocks convergence. Use the asymptotic-convergence pattern below to recognize when minor-issue holdouts should auto-route to `routed-deferred` rather than triggering another full round.

## Model B - Threshold (≥75% acceptance)

**Convergence condition**: ≥75% of reviewers verdict `READY_TO_IMPLEMENT` AND 0 unaddressed blocking findings.

**When to use**: medium-stakes artifacts where one reviewer's NEEDS verdict on precise polish shouldn't block; the threshold prevents a single outlier from forcing iteration on agreed-as-non-blocking concerns.

**Holdout treatment**: the NEEDS reviewer's findings still require explicit C2 routing - `routed-now` (apply the change), `routed-deferred` (address during implementation, with external-record citation), or `dismissed-source-grounded` (cite source refuting the finding). Threshold is NOT a way to overrule a blocking dissent; it's a way to avoid loop-tail thrash when the dissent is on minor / polish concerns.

## Model C - Confidence-weighted (≥80% average)

**Convergence condition**: weighted average confidence ≥80% AND 0 unaddressed blocking findings. Requires each reviewer to self-report a confidence score (0-100%) alongside their verdict.

**When to use**: artifacts where reviewer certainty varies meaningfully (e.g., one reviewer is expert in the domain; others are bringing fresh eyes). Confidence-weighting respects expertise without overruling it.

**Trade-off**: self-reported confidence can be miscalibrated. Use only when the user has reason to trust reviewer self-assessment.

## Asymptotic-convergence pattern (documented from real iteration evidence)

Across iteration runs in real use, the convergence trend is **asymptotic**: each round reduces findings by ~30-40% but never reaches zero - each round surfaces new precise tightenings that previous rounds didn't have enough specificity to identify.

**Implications**:

- **Max-loop exceedance is a normal outcome** when the trend is asymptotic. Continuing past max-loop has diminishing returns; round N+1 may reduce findings to 3-4 but is unlikely to produce unanimous READY.
- **Threshold convergence + C2 `routed-deferred` is acceptable** when:
  - ≥75% reviewers verdict READY AND 0 unaddressed blocking findings exist; AND
  - The sole-NEEDS reviewer's findings are precise polish (1-2 line fixes, no architectural concern); AND
  - The asymptotic-convergence intake control (`intake.md` item 10) is ON.
  Under those conditions, the precise-polish findings auto-route to `routed-deferred`. **Citation requirement** (per `evidence-gate-spec.md` C2 audit): the orchestrator MUST auto-create a session-todo with id `auto-deferred-<theme>-<yyyymmddHHMMSS>` and cite it in the C2 audit output entry - `routed-deferred` without external-record citation is NOT acceptable per the canonical C2 status definitions.
- **Architectural-concern dissent still blocks** regardless of convergence model. If the holdout reviewer's findings include architectural issues (design flaws, missing safety properties, contradictions with hard rules), do NOT auto-route - escalate.
- **Sole-NEEDS-reviewer dissent on precise polish is the asymptotic-convergence signal**, not a reason to keep iterating. Recognize it and stop.

## How to choose

| Stakes | Recommended model |
| --- | --- |
| Production code, security, public API | Unanimous |
| Plan / design / spec review | Threshold |
| Mixed-expertise reviewer pool | Confidence-weighted |
| Quick sanity check (rare) | Threshold with max-loop=2 |

## Output

Convergence outcome fed back to `procedure.md` step 10 (convergence check). After C2 routing (step 11), per-round evidence-gate emission (step 12) carries the outcome; CONVERGED → return per step 13. NOT CONVERGED → loop-vs-escalate per steps 14 / 15.
