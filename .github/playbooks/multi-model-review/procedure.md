# Multi-model review - Procedure

Procedure for `multi-model-review.md`. Consumes intake from `intake.md`; emits evidence-gate output per `evidence-gate-spec.md`; applies convergence per `convergence-models.md`.

## Parallel-launch protocol

1. **Launch all N reviewers in parallel** as background sub-agents. Do NOT serialize the launches - parallel diversity is the point.
2. **Sub-agent prompt template** (every reviewer gets this structure):

   ```
   ADVERSARIAL REVIEW: assume this **<target type>** contains defects; FIND and enumerate them, do NOT confirm the author, and accept no author claim without a falsification attempt. Actively attempt to falsify; report ONLY evidence-backed defects; a clean result is a valid verdict; do NOT invent findings.

   You are reviewing **<target type>** at **<path or reference>**.
   <Round context if iterating: round N of max M; prior-round findings shared per intake; v<N> incorporates amendments from round <N-1> - verify amendments address prior findings without introducing new issues.>

   **Key context files to read**:
   - <list of file paths the reviewer should view>

   **Author claims to DISPROVE** (attack each; a claim merely restated is NOT cleared; try to falsify each with a concrete counter-example citing file:line): <the author's load-bearing assumptions, or "none">

   **Critique focus** (vary per reviewer slot per intake - cross-family / technical-design / coding-discipline / rubber-duck design):
   **Standing structural-hygiene axis** (every `diff`-target panel, IN ADDITION to the change-specific focus): VERIFY the POST-CODE-CHANGE LEDGER's structural-hygiene fields against the actual diff - folder placement vs VSA (`vsa-audit`), member visibility + `InternalsVisibleTo` (`touched-file-LPA`), DI-fit (`dependency-injection-fit`), comment necessity + §3.1 quality (`comment-audit-§3.1` + `hygiene-cleanup`). Confirm each field's value matches what the diff shows; do NOT restate a parallel criteria set. The B1 floor only forces these fields present-with-a-justified-value (local, bypassable); the panel is what checks the value is APT.
   1. <focus point 1>
   2. <focus point 2>
   ...

   **Format for findings**: bullet list, max ~10-15 bullets. Each: a stable `F-<n>` id (so a `probing_evidence` outcome can reference `finding:<F-n>`) + one-line summary + severity (blocking | major | minor) + where (file / section / line) if applicable + proposed mitigation.

   **REQUIRED before the VERDICT**: a `probing_evidence` block per `evidence-gate-spec.md` §"Probing evidence" (distinct checks covering the target, each with location + `ruled-out:<why>` or `finding:<id>`). A success verdict WITHOUT it is advisory-only and does not count toward convergence.

   **REQUIRED: end your output with this single line**: `VERDICT: <success verdict | NEEDS_ANOTHER_ROUND>` - the success verdict is `DESIGN_READY` for a `plan`/`design`/`spec` target and `CODE_REVIEW_READY` for a `diff` target (match the target type stated above)

   **Tooling discipline**:
   - **Read-only inspection allowed**: `view`, `grep`, `glob`, and `powershell` for read-only git commands (`git --no-pager diff`, `git --no-pager show`, `git --no-pager log`, `git --no-pager status`) - reviewers reviewing a `diff` target MUST be able to inspect the diff independently.
   - Do NOT call `ask_user` or any other tool that prompts the user. Make reasonable assumptions, document them, continue.
   - Do NOT modify any files - this is a review pass.
   - Do NOT launch sub-agents.

   Return findings + verdict only.
   ```

3. **Differentiate reviewer slots** by varying the critique-focus angle per intake (cross-family fresh eyes / technical-design depth / coding-discipline / rubber-duck design critique). Each reviewer gets one differentiated focus emphasis on top of the shared focus areas.

### Target-type variation: `bug-investigation`

When `target-type=bug-investigation` (called by `cross-file-bug-investigation.md`), the sub-agent prompt template extends the base structure with:

- **Lane-to-slot mapping**: round-robin lane-to-slot assignment until every selected lane has ≥1 reviewer; when `lanes_selected > reviewers`, double-up per-slot per M8 default and add a per-reviewer lane-budget hint ("Focus first on your primary lane; expand to secondary lanes only as evidence requires. Document which lane each finding belongs to.").
- **Lane-specific critique-focus paragraphs** injected from `cross-file-bug-investigation/lanes-catalog.md` - for each lane assigned to the slot, the lane's "Reviewer prompt clause" (≤200 words per lane) is inserted into the prompt under the per-slot Critique focus section.
- **Required 7-field finding schema** - every finding the reviewer reports MUST include:
  1. `id`: `F-XXXX` placeholder (orchestrator assigns the final `F-NNNN`).
  2. `severity`: `blocking | major | minor`.
  3. `is_blocking`: `true | false` (mirrors `severity == 'blocking'` for greppability in the persistence schema).
  4. `lane`: one of the assigned lane slugs.
  5. `title`: one-line summary.
  6. `citations`: ≥1 `file:line` citation per participating file. For cross-file claims, EACH implicated file must be cited independently (e.g., a finding about field-X-missing-in-producer-2 needs citations to producer-1 setting it AND producer-2 not setting it AND the consumer branching on it).
  7. `body`: `{ description, why_bug, reproduction (or "Observational"), suggested_fix_class (advisory), confidence (high|medium|low) }`.
- **VERDICT-emission rule** (target-type-specific):
  - Emit `VERDICT: DESIGN_READY` when you have NO BLOCKING-severity findings remaining. Non-blocking findings (major / minor) are acceptable; they will be recorded as advisory C2 dispositions and do NOT require another round.
  - Emit `VERDICT: NEEDS_ANOTHER_ROUND` only when ≥1 BLOCKING-severity finding requires another iteration.
  - This rule is target-type-specific reviewer behavior; the orchestrator's convergence check (Model A unanimous: ALL reviewers DESIGN_READY + `unaddressed_blocking=0`) is UNCHANGED.
- **Tooling discipline** (re-emphasized): read-only inspection only (`view` / `grep` / `glob` / read-only git). NO `ask_user`. NO file modifications. NO sub-agent launches.

Full prompt template (added to the base prompt at step 2):

```
**Target-type: bug-investigation**

You are reviewing CROSS-FILE BEHAVIOR / BUGS on UNCHANGED code (NOT a diff).
The user has identified these files: <scope_file_list>.
You have been assigned lane(s): <slot_to_lane_mapping[your_slot]>.

**Lane-specific critique focus** (one paragraph per assigned lane, copied verbatim from
`cross-file-bug-investigation/lanes-catalog.md` "Reviewer prompt clause" sections):

<lane 1 prompt clause>

<lane 2 prompt clause, if doubled-up>

...

**Required 7-field finding schema** (per finding):
1. id: F-XXXX (orchestrator assigns final F-NNNN)
2. severity: blocking | major | minor
3. is_blocking: true | false (mirrors severity == 'blocking')
4. lane: <one of your assigned lanes>
5. title: <one line>
6. citations: ≥1 file:line per participating file (cross-file claims MUST cite each implicated file)
7. body: { description, why_bug, reproduction (or "Observational"), suggested_fix_class (advisory), confidence (high|medium|low) }

**VERDICT emission rule (TARGET-TYPE-SPECIFIC)**:
- Emit `VERDICT: DESIGN_READY` when you have NO BLOCKING-severity findings remaining.
  Non-blocking findings (major/minor) are acceptable and recorded as advisory.
- Emit `VERDICT: NEEDS_ANOTHER_ROUND` only when ≥1 BLOCKING finding requires another iteration.

**Tooling discipline**:
- Read-only inspection (view / grep / glob / read-only git). NO ask_user. NO file modifications. NO sub-agent launches.

Return findings + VERDICT line only.
```

## Completion-wait

4. **Wait for runtime notifications** ("Agent finished") rather than polling. The orchestrator should NOT call `read_agent` in a tight loop. When all N notifications arrive (or a timeout fires for missing ones), proceed to synthesis.
5. **Missing-verdict handling** - if a reviewer's output lacks the `VERDICT:` line, re-prompt with `write_agent` once for the verdict. If still missing, drop that reviewer's input and launch a replacement reviewer (same intake; adjusted prompt if the issue is identifiable). Record the missing-verdict event + replacement in the evidence-gate output.

## Synthesis

6. **Read each reviewer's output** via `read_agent` once per reviewer (idempotent - agents are idle post-completion).
7. **Dedup findings by theme** - multiple reviewers often surface the same finding from different angles. Group by root cause.
8. **Rank severity** - within each theme, the highest-severity classification across reviewers wins (if any reviewer flagged blocking, the theme is blocking).
9. **Agreement count** - record how many of the N reviewers flagged each finding (signals convergence-strength + helps prioritize routing).

## Convergence check

10. **Apply chosen convergence model** per `convergence-models.md`:
    - `unanimous` - all reviewers emit their success verdict AND 0 unaddressed blocking → CONVERGED.
    - `threshold` - ≥75% emit their success verdict AND 0 unaddressed blocking → CONVERGED.
    - `confidence-weighted` - avg confidence ≥80% AND 0 unaddressed blocking → CONVERGED.

## C2 routing (ALWAYS - converged rounds may still have non-blocking findings)

11. **Route each finding via the C2 status enum** (`fixed | routed-now | routed-deferred | dismissed-source-grounded`):
    - `fixed` - apply the change now (citation: file:line).
    - `routed-now` - route via `ask_user`; user decides this turn (citation: `ask_user` call ref).
    - `routed-deferred` - defer with external-record citation (session todo / issue / tracker URL). Asymptotic-convergence per `convergence-models.md` may auto-route precise polish here with an auto-created session-todo citation.
    - `dismissed-source-grounded` - refuted by explicit source citation.
    Default to `ask_user` for ambiguous routing. Converged rounds with 0 unaddressed blocking but ≥1 non-blocking finding still need C2 routing of those findings.

    **Target-type variation: `bug-investigation` - C2 routing DEFERRED to caller.** When `target-type=bug-investigation` (called by `cross-file-bug-investigation.md`), step 11 C2 routing is DEFERRED to the caller's Step 11A (which happens AFTER user report approval per the caller's fix-transition protocol). The engine here records `C2 dispositions this round: deferred-to-caller-step-11A` in step 12's evidence emission instead of resolving individual finding statuses. The caller owns C2 resolution end-to-end for bug-investigation rounds; the engine's responsibility narrows to citation-verification + VERDICT collection + per-round agreement counting. Asymptotic-convergence auto-routing is DISABLED for this target-type (the caller handles all finding dispositions including precise polish).

## Per-round evidence emission (ALWAYS - converged OR not, with complete fields populated)

12. **Emit per-round evidence-gate output** per `evidence-gate-spec.md` AFTER convergence check + C2 routing - by this point all template fields (verdicts, findings, agreement counts, **Convergence outcome**, **C2 dispositions this round**, **Next directive**) are knowable. This output is the canonical per-round audit trail; skipping emission on any round (converged or not) is a workflow violation. **For `target-type=bug-investigation`**, the `C2 dispositions this round` field carries the sentinel value `deferred-to-caller-step-11A` (per step 11's target-type variation above); all other fields are populated normally.

## Loop-vs-escalate decision

13. **If CONVERGED** → append the round's evidence-gate output to the cumulative log; return to caller (Next directive: `DONE`).
14. **If NOT CONVERGED AND current_round < max_loop** (Next directive: `LOOP_AGAIN_ROUND_<N+1>`):
    - Increment round counter (accepted `fixed` findings already applied at step 11; do NOT re-apply here).
    - Go to step 1 with the updated target and prior-round findings as context.
15. **If NOT CONVERGED AND current_round = max_loop** - **escalate** (Next directive: `ESCALATE_TO_USER`):
    - Surface remaining dissent to the user via `ask_user`: *"max-loop reached at N rounds. Remaining dissent: <reviewer> says NEEDS because <findings summary>. Options: (a) apply final tightenings and run round N+1 (user-authorized exceedance), (b) accept threshold convergence with documented C2 dispositions, (c) document remaining findings as `routed-deferred` and proceed, (d) stop and reconsider plan."*
    - Do NOT silently loop past max-loop.

## Output

Returns to caller with: convergence outcome (CONVERGED / ESCALATED), final round number, per-reviewer verdicts, dedup'd findings list with severities and dispositions. Evidence-gate output emitted per `evidence-gate-spec.md`.

## Prompt hygiene (adversarial framing) - methodology

The orchestrator authors the per-panel task framing. Because the same agent often authored the artifact under review, author-written framing tends to be CONFIRMATORY (it lists conclusions and asks reviewers to agree) - the documented cause of a panel returning unanimous approval on a defect an external reviewer then caught. Every panel's orchestrator-authored framing (design- AND diff-target) MUST be adversarial. This is reviewer-methodology guidance and a re-derivable disclosure receipt, NOT a fail-closed gate (mechanical enforcement is future work).

1. **Adversarial stance, not confirmatory.** Frame the task as "assume the artifact contains defects; find and enumerate them", never "confirm that X, Y, Z are fine". Do not use confirm-the-author verbs (`confirm that`, `verify ... is correct`, `check that ... still holds`) as yes-invitations in the framing.
2. **No pre-stated conclusions in the framing.** Do NOT assert the author's desired conclusion or verdict (`is genuinely unreachable`, `is correct`, `is safe`, `cannot throw`, `is guaranteed`, equivalents). Relocate any such claim to the `Author claims to DISPROVE` section as a target to attack.
3. **`Author claims to DISPROVE` section** (in the step-2 template): list each load-bearing author assumption and instruct reviewers to try to FALSIFY each with a concrete counter-example (input, race, edge state) citing `file:line`. A claim merely restated is NOT cleared.

Scope of this rule = only the task-framing the orchestrator writes; it does NOT restrict launcher-forwarded catalog rules or the standing template text (those legitimately contain words like "correct").

### Pre-dispatch prompt-hygiene disclosure

Before launching a panel, the orchestrator scans the WHOLE assembled mutable prompt (preamble + critique focus + round context + prior dispositions + context notes), EXCLUDING byte-identical launcher-canonical blocks AND the `Author claims to DISPROVE` block (conclusion-shaped claims there are `relocated` by design, not residual), then emits a re-derivable chat receipt:

`prompt-hygiene-scan: scanned=<assembled-prompt-ref> relocated=<n> residual_hits=0`

where `<assembled-prompt-ref>` resolves to the exact inspectable prompt text so a diff-panel reviewer can re-run the scan. `residual_hits` counts pre-stated-conclusion / confirm-the-author language found OUTSIDE the DISPROVE block only; it should be 0 before dispatch. This is an honest-ceiling disclosure (self-reported + re-derivable), not a mechanically fail-closed gate.

## Adversarial red-team reviewer - methodology

On full-mode `diff`-target panels, AT LEAST ONE `code-review`-role reviewer slot is designated the red-team: it receives the panel's OWN target diff (a per-commit post-code panel = the commit diff; the pre-PR review-exposure gate = the whole branch `<base>..HEAD`) plus all standing reviewer controls (read-only inspection, tooling discipline, forwarded catalog rules, the required VERDICT), but WITHOUT the author's design narrative, plan summary, or `Author claims to DISPROVE` list - it reconstructs intent from the code alone and is told "assume defects exist; enumerate every defect (correctness, concurrency, ordering, resource, contract, error-handling); do not invent findings; an empty result is a clean verdict". This is the author-framing-free pass whose absence let a confirmatory panel converge on a real defect. Small diffs are NOT exempt. On lite mode the red-team angle is assigned when the 3-slot slate allows; governance / safety-critical changes (always full) always carry it. This is reviewer-methodology guidance; a mechanically-validated red-team slate property is future work.
