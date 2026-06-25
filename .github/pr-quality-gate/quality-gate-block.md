# QUALITY GATE block - canonical composite schema

This file is the **single source of truth** for the `QUALITY GATE` block: the unified publish-gate artifact that consolidates the mechanical pattern floor (gate-runner) with the multi-model panel sign-off. It is the G6 forbidden-tools prerequisite for PR-creation / draft-state mutation, emitted in the same turn as the tool call. `pr-quality-gate/README.md` §1B and the `Publish gate` section of `review-workflow-gates-sweeps.md` (§2D anchor) POINT here; they do not redefine the schema.

## Honest ceiling (read first)

The block is a **composite artifact with two provenance regions**:

- The **mechanical region** is emitted by `gate-runner.ps1`/`.sh` from the rg-battery. It is **CI-reproducible**: the `quality-gate-check.yml` workflow re-runs gate-runner headless on every push and re-derives these fields exactly, so a fabricated mechanical value (e.g. a hand-typed `gate_status: READY` while live hits exist) is caught at merge (re-run -> BLOCKED -> mismatch). This region is the **merge-blocking remote backstop** - a mechanical floor, NOT "non-bypassable" (`--no-verify` bypasses the local run; the remote check is the backstop).
- The **agent-appended region** is filled by the agent/panel. It is **ASSERTED, NOT CI-verified**: CI does not re-derive the panel dispositions, the slate, the resolutions, the same-state recheck, or the publish-authorization. An agent that skips the panel can hand-type these fields and CI will not catch it. The detective backstops are the HIGH catalog slug `pr-creation-or-push-without-quality-gate-block` (per-commit `core_rules_acknowledged` enumeration) and the §0 publish SENTINEL + `ask_user`. `gh pr create` is genuinely unhookable - no client-side hook fires at PR creation - so the publish authorization can never be mechanically gated at create time. This mirrors the comment-audit ("SHA binds text, not approval") and identity ("modeled-only") ceilings.

**`gate_status: READY` is the MECHANICAL floor only; it is NOT publish authorization.** Publishing is authorized only when the full G6 AND-list passes (see Enforcement) - which includes the agent-asserted `pr_creation_status`, `panel.convergence_result`, `must_fix_unresolved: 0`, `commit_approval`, and `same_state_recheck`. Reading a green `gate_status` as "ship it" is the overclaim-by-juxtaposition this split exists to prevent.

## Block format

```
QUALITY GATE
  # --- gate-runner mechanical, CI-reproducible (CI re-derives these EXACTLY at `-Mode full` [the CI-pinned superset]; a fabricated value is caught at merge) ---
  catalog_revision: <SHA of pattern-catalog.md at HEAD of CopilotInstructions clone>
  prefs_revision: <SHA of coding-preferences.md at HEAD of clone>
  runner_version: <gate-runner self-reported version>
  base_sha: <40-char SHA of merge-base origin/<base>..HEAD>
  head_sha: <40-char SHA of current HEAD>
  diff_scope: <N files, +<X>/-<Y> lines>
  patterns_run: <N>                            # 0 mechanically signals empty-battery
  required_rule_ack: [<HIGH-tier review-pass-only slugs that require acknowledgement>]   # gate-runner emits the LIST (mechanical); the per-slug ack (core_rules_acknowledged) is agent-asserted
  rg_flagged_sites:                            # present ONLY when rg matched sites
    <slug>: [<file:line>, ...]
  findings:
    - pattern: <slug>
      scope_mode: diff-scoped | tree-scoped | hybrid | review-pass-only | checker-scoped
      tier: HIGH | MEDIUM | LOW
      hits: <count> | review-required
      sites: [<file:line> - <1-line signature>, ...]
  # --- gate-runner-echoed agent inputs / -PrRef-gated (NOT CI-verified: the CI workflow runs `-Mode full` with no `-PrRef`, so these are not re-derived) ---
  panel_mode: full | triage | lint-only
  pr_ref: <PR ref | empty>
  anti_recidivism_preamble:                    # -PrRef-gated; present ONLY when prior panel-miss slugs apply for the PR ref (the §1A.2 anti-recidivism forcing function)
    pr_ref: <ref>
    prior_slugs: [<slug>, ...]
  # --- agent-appended panel dispositions (ASSERTED, NOT CI-verified) ---
  emission_phase: initial-pending-user-approval | ready-re-emitted-after-user-approval
  invocation_mode: via-publish-gate | direct-invocation-dry-run-only
  re_run_triggers: <[trigger, ...]>
  pattern_preflight_skip_status: ran | catalog: not-yet-built | catalog: empty-battery | catalog: skipped-bootstrap | catalog: skipped-no-production-diff
  findings_disposition:                        # one per mechanical findings/sites hit; no entry for a non-hit site
    - pattern: <slug>
      site: <file:line>
      classification: pending | applied | already-applies | not-applicable | dismissed-source-grounded | routed-deferred
      evidence_or_rationale: <file:line-range> for applied; rationale for not-applicable per Delta K rubric
  preferences_compliance:
    - <slug>: ok | violated (<file:line>)
  panel_mode_receipt: <ask_user call-ref + quoted user-response substring>   # required for triage|lint-only; absent for full
  slate:                                       # absent for lint-only; STAYS enumerated (proves the floor)
    - slot 1: <model> <family> <role> [substituted from <requested>: <reason>]
  slate_substitutions: <[] or list>
  slate_waive: <"no waive" or user-quote>
  convergence_model: unanimous | threshold-N% | confidence-weighted-N% | single-reviewer   # single-reviewer required under triage
  convergence_waive: <"no waive" or user-quote>
  convergence_result: passed | failed
  panel_rounds: <N>
  fix_iteration_count: <N>
  fix_iteration_count_cap: <3 default, or user-authorized override>
  dropped_reviewers: <[] or list>
  replacement_reviewers: <[] or list>
  prior_commit_panel_dispositions: <"none - <reason>" or compacted list>   # anti-anchoring: the audit echo of priors
  panel_coverage:                              # STAYS enumerated (coverage-mode is fakeable as a bare scalar)
    - mode: full-whole-branch | carry-forward-authorized  scope: <baseSha>..<headSha>  commits: <N>  carry-forward-ref: <ask_user ref | n/a>  carried: <range | n/a>
  resolution:                                  # every finding has a status; STAYS enumerated
    - [<category 1-11>] <severity> [<reviewer>]: <finding>: <status>: <citation>
  must_fix_unresolved: <count>
  routed_deferred_with_tracker:                # C2 deferral proof; STAYS enumerated
    - <finding> -> <tracker URL> (ask_user: <call ref>)
    - ... (default: [])
  bootstrap_token_status: <not-applicable | present-in-body | removed-revokes-exemption>
  pr_text_scan: <clean | tier1-fail: <surface:marker,...> | tier2-warn: <surface:marker,...>>
  commit_approval: present
  same_state_recheck: passed | not-yet-rechecked
  subagent_ask_user_calls: 0
  pr_creation_status: READY-pending-user-approval | READY-re-emitted-after-user-approval | DRY-RUN-INFO-ONLY | BLOCKED - <reason>
  # --- mechanical floor verdict (gate-runner) ---
  gate_status: READY | BLOCKED - <reason>
```

**Why the enumerations stay enumerated** (not collapsed to bare scalars): `slate`, `resolution`, `routed_deferred_with_tracker`, and `panel_coverage` are the four forcing functions - counts AND coverage-mode are fakeable as bare scalars, so the per-item keys are the forcing function that makes a skipped step visible. The canonical form above is what the orchestrator computes; the caveman chat form (below) keeps these four enumerated even when scalars are pipe-collapsed.

**`gate_status` is binary and mechanical**: gate-runner sets `BLOCKED - <reason>` iff any pattern has `hits > 0`, else `READY` - based on raw rg hits only, never on the agent's classification/resolution. A legitimately `not-applicable` / `routed-deferred` finding still yields mechanical `BLOCKED` + a non-zero gate-runner exit; the agent's `findings_disposition` + `must_fix_unresolved` is the resolved verdict. The CI workflow treats mechanical `BLOCKED` as a hard fail (merge-blocking floor); a disposition that resolves a raw hit is recorded in the agent-appended region, which CI does not read - so disposition reconciliation is an agent + human-review responsibility, and CI is deliberately the stricter mechanical floor.

## BLOCKED-* taxonomy (`pr_creation_status`)

The agent-asserted `pr_creation_status` is the publish-readiness signal (distinct from the mechanical `gate_status`):

- `READY-pending-user-approval` - initial emission, end of synthesis turn.
- `READY-re-emitted-after-user-approval` - PR-creation tool-call turn, after the §0 user-approval `ask_user` returns + same-state re-check passes.
- `DRY-RUN-INFO-ONLY` - direct invocation outside the publish flow; never sufficient to publish.
- `BLOCKED - <N> must-fix unresolved` - must-fix findings still pending.
- `BLOCKED - slate-floor violated` - slate composition fell below the waive-matrix floor.
- `BLOCKED - bootstrap-token-removed` - the bootstrap token was removed from the PR body after initial emission.
- `BLOCKED - same-state-check-failed` - HEAD / base / commit-count drifted between initial and re-emission.

## Same-state re-check transition procedure

`same_state_recheck` and `pr_creation_status: READY-re-emitted-after-user-approval` are AGENT-ASSERTED (CI does not re-derive them). gate-runner pre-seeds `same_state_recheck: not-yet-rechecked` in its raw output, but the field sits in the agent-appended region because its meaningful value (`passed`) is set by the agent; the agent overwrites the pre-seed when it assembles the canonical block. Before invoking any G6 tool, the agent MUST re-run ALL THREE and compare to the prior emission:

1. `git rev-parse HEAD` -> must match `head_sha`
2. `git -C <clone> log -1 --format=%H -- .github/pr-quality-gate/pattern-catalog.md` -> must match `catalog_revision`
3. `git -C <clone> log -1 --format=%H -- .github/pr-quality-gate/coding-preferences.md` -> must match `prefs_revision`

If ALL three match, re-emit with `same_state_recheck: passed` + `pr_creation_status: READY-re-emitted-after-user-approval` + `emission_phase: ready-re-emitted-after-user-approval` in the same response as the tool call (literal carry-forward; no recomputation). If ANY drifted, re-run `gate-runner` from scratch and re-emit with fresh values.

## Enforcement (G6 - fail-open guard)

G6 forbidden tools (`gh pr create`, `gh pr ready`, `gh api .../pulls`, and the full §1B enumeration preserved verbatim) are blocked unless a QUALITY GATE block is present in the current turn with **ALL** of the following. The publish authorization is the FULL AND-list, NOT the bare mechanical `gate_status` (collapsing G6 to `gate_status: READY` would authorize publish on zero rg-hits without the panel/user-approval - a fail-open):

- `gate_status: READY` (mechanical floor passed) **AND**
- `pr_creation_status: READY-re-emitted-after-user-approval` (the publish authorization)
- `head_sha` matches `git rev-parse HEAD` at tool-call time (same-state)
- `catalog_revision` matches the current catalog SHA at tool-call time (currentness)
- `prefs_revision` matches the current prefs SHA at tool-call time (currentness)
- `same_state_recheck: passed` (per the transition procedure)
- `must_fix_unresolved: 0` (or all such findings have `routed_deferred_with_tracker` with `ask_user` evidence)
- For `panel_mode: full|triage`: `convergence_result: passed` AND `dropped_reviewers: []` (or replacements present)
- For `panel_mode: triage|lint-only`: `panel_mode_receipt` present, with `ask_user` call-ref + quoted user-response containing the literal mode-acknowledgment token
- For `panel_mode: lint-only`: the slate / panel disposition fields absent (no-panel carve-out)
- `pr_text_scan: clean` (`tier1-fail` BLOCKS creation until markers are stripped + re-emitted clean; `tier2-warn` is surfaced, not blocking; honest ceiling: the scan catches MODELED markers only - a floor-raise, the `pr-text-check.yml` CI job is the merge-blocking backstop)
- `preferences_compliance` has no `violated` entries with `severity: blocking` (waived via `ask_user` if needed)
- **`commit_approval: present` is REQUIRED in ALL repos** - the §0 commit-approval gate applies everywhere; only the extra §1B diff-review is waived for panel-certified instruction-repo edits

## Disclosed narrowings vs the retired multi-model-review (§2D) system

This unified gate replaces the older `multi-model-review` PATTERN PREFLIGHT + PRE-PR REVIEW COVERAGE blocks. Two coverage deltas are disclosed honestly (neither is a silent loss):

1. **Catalog narrowing.** `pattern-catalog.md` (generated from `pattern-catalog.sources/`) is a leaner CROSS-PROJECT battery, NOT a 1:1 carry of the deleted project-specific seed (`pr-review-pattern-catalog*.md`). Project-specific patterns belong in the *consuming project's own* catalog, not CopilotInstructions.
2. **FP-registry narrowing (distinct from #1).** The retired `known-false-positives.md` held SITE-LEVEL FP memory (`fps_recognized: FP-N -> paths`) so known-good sites were not re-flagged run-over-run. gate-runner's FP mechanism is a PER-PATTERN `fp_slug` catalog column, NOT a site-level registry. So deleting the registry drops durable site-level FP memory: the panel now re-dismisses known-good sites per-run against the catalog's inline `FP-N` entries (agent-asserted). This is a separate, disclosed delta.

## Chat-emission form (caveman)

Chat emits `QUALITY GATE` with scalars collapsed to pipe-KV; the FOUR enumerations - `slate` (proves the floor), `resolution` (per-finding status+citation), `routed_deferred_with_tracker` (C2 deferral proof), and `panel_coverage` (cited `full-whole-branch` vs `carry-forward-authorized` + `ask_user` ref) - STAY enumerated (counts and coverage-mode are fakeable as bare scalars). The canonical form above is the form the orchestrator computes; the keys are the forcing function. On re-emission, the compressed form is sufficient if the SHAs are unchanged.
