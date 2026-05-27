# PR Quality Gate — Panel Policy

Multi-reviewer panel governance for the `full` and `triage` modes. Read by the orchestrator before invoking `invoke-panel.ps1`. The script is a thin launcher; policy lives here so it's reviewable + amendable independently of the launcher code.

## When the panel runs (timing requirement — MANDATORY)

There are TWO panel invocation points per task, both required for non-trivial work:

1. **Pre-implementation panel** — AFTER the agent drafts a plan and (when applicable) has it critiqued by `rubber-duck`, but BEFORE writing any production code. Reviewers see: (a) the issue / user request, (b) the plan, (c) the rubber-duck critique and the agent's response to each finding, (d) the relevant current code surfaces. Required verdict: `unanimous READY` (or matched waive per Convergence-model below) before code is written. Catches design flaws while course-correction is still cheap.
2. **Pre-PR-creation panel** — AFTER code + tests are written and the build is green, BEFORE `gh pr create` or `git push`. This is the panel slot enforced by `gate-runner.ps1` / `gate-runner.sh` (G6 forbidden-tool gate). Reviewers see the actual diff + the QUALITY GATE block. Required verdict: `unanimous READY`.

"Non-trivial" means any of: ≥3 files changed, new interface members, new state, behavioral changes to existing public APIs, security/concurrency code, or anything the user describes with words like "feature", "refactor", "add", "implement". A small isolated single-file bugfix (e.g., a 1-line typo) MAY skip pre-implementation panel if the agent justifies the skip in the same-turn `ask_user` quote.

Skipping pre-implementation panel for non-trivial work is a process violation. The agent MUST surface the skip via `ask_user` so the user can authorize before code is written.

## Mode definitions

| mode | reviewers | output cap | rg battery | `§1A` slate carve-out | Activation |
|---|---|---|---|---|---|
| `full` | 4-5 (slate-floor below) | none | yes | none — full slate-floor applies | default; no `ask_user` receipt required |
| `triage` | 1 code-review-role, any model | none | yes | `slate-mode: triage; slate-size=1; role=code-review`; `convergence_model: single-reviewer` MANDATORY | `invoke-panel.ps1 -Mode triage`; same-turn `ask_user` receipt with `triage-acknowledged` token required per PR |
| `lint-only` | 0 (no panel invocation) | n/a | yes | `slate-mode: lint-only; no panel invoked → slate-composition NOT applicable` | `invoke-panel.ps1 -Mode lint-only` (effectively skips panel); same-turn `ask_user` receipt with `lint-only-acknowledged` token required per PR |

CLI flag is the ONLY robust activation mechanism. Env vars and `plan.md` flags are explicitly NOT honored (too persistent, bypass-prone).

## Slate composition floor (`full` mode)

- ≥ 4 reviewers
- ≥ 1 Claude family AND ≥ 2 GPT family
- ≥ 1 `rubber-duck` role AND ≥ 2 `code-review` role
- ≥ 1 heavy-tier model (claude-opus-*-xhigh, gpt-5.5, gpt-5-preview, or equivalent)
- Slot composition is recorded in the `PANEL CONVERGED` block's `slate` field for audit

Floor is verifiable from the slate enumeration. Substitutions are allowed mid-launch ONLY if the substitute matches the same family + role + tier; documented in the `slate_substitutions` field of the `PANEL CONVERGED` block.

## Convergence model

| convergence_model | rule | use |
|---|---|---|
| `unanimous` (DEFAULT for `full`) | all reviewers must return `READY` (or all `NEEDS_REWORK`) | strict — no findings ship without all-reviewer agreement |
| `threshold-N%` (waive floor) | ≥ N% of reviewers must converge on verdict; floor `N=75` | acceptable when ≥75% agree on READY |
| `confidence-weighted-N%` (waive floor) | ≥ N% confidence-weighted sum; floor `N=80` | accounts for reviewer confidence per finding |
| `single-reviewer` (MANDATORY for `triage`) | single reviewer's verdict is the panel verdict | distinguishes from `unanimous` in audit trail (Slot 1 NB-V2 / Slot 4 D) |

Waiving the default `unanimous` for `full` requires same-turn `ask_user` quote in the `PANEL CONVERGED` block's `convergence-waive` field. `triage` MUST use `single-reviewer` — no waive needed (it's structural).

## Drop handling (`full` mode only)

`triage` and `lint-only` have no drops by construction (1 reviewer or 0 reviewers).

| dropped_count | action |
|---|---|
| 0 | proceed |
| 1 | launch replacement (same family + role + tier; record in `replacement_reviewers` field) |
| 2 | `ask_user` quoting both drops; user decides proceed-with-2-replacements OR abort |
| ≥ 3 | hard escalate — abort panel; emit `ask_user` with all drops listed; require user to authorize remediation (e.g., switch to `triage` mode, retry later, etc.) |

Each drop is recorded in `dropped_reviewers` field with timestamp + reason (timeout, error, drop-explicit).

## Post-PR-review feedback loop (MANDATORY)

External reviewer findings (e.g., GitHub Copilot pull request reviewer, human reviewers in the PR conversation, security review post-merge) are the OBSERVED ground truth for what the pre-PR panel did NOT catch. Treating these as one-off fixes without classification means the next PR likely has the same blind spot. The feedback loop is mandatory.

For EACH external-reviewer finding on a PR with a converged pre-PR panel:

1. **Classify** the finding as one of:
   - `panel-miss`: the pre-PR panel could/should have caught this with the existing rule slate (the slate's blind spot, or a gap in the catalog). → Append to `data/panel-misses.csv`. Propose a new `pattern-catalog.md` entry OR refinement to an existing one that would catch this class of issue in future PRs.
   - `valid-deferred`: the pre-PR panel reasonably skipped this (out-of-scope by design, e.g., post-merge follow-up work, separate-PR scope, infrastructure change). → Document briefly in the PR conversation; no catalog change.
   - `rejected`: agent disagrees with the finding; provides source-grounded rationale on the PR. → No catalog change; user may escalate.

2. **Apply the fix** (amend or follow-up commit) AND update tracking in the SAME session:
   - For each `panel-miss`: append a row to `data/panel-misses.csv`.
   - For each new/refined catalog rule proposed: append to `pattern-catalog.md` and run a panel on the change (full iteration discipline applies — no rule lands without convergence).
   - The agent MUST NOT close the PR loop without updating tracking. If tracking is deferred (e.g., user authorizes "fix-now-track-later"), the agent MUST surface this via same-turn `ask_user` with literal token `panel-miss-deferred`.

3. **`data/panel-misses.csv` schema**:

   ```
   timestamp,catalog_revision,pr_ref,finding_brief,classification,proposed_catalog_slug,status
   ```
   - `timestamp`: ISO-8601 UTC
   - `catalog_revision`: 40-char CopilotInstructions SHA at the time the pre-PR panel ran (which catalog slate had the blind spot)
   - `pr_ref`: opaque project-specific reference (consuming project chooses format; rows in this seed file use opaque labels with no project leakage)
   - `finding_brief`: 1-line generic phrasing (e.g., "Volatile write ordering inside lock"; NOT "ModalService.Show write order" — no project leakage)
   - `classification`: one of `panel-miss`, `valid-deferred`, `rejected`
   - `proposed_catalog_slug`: the slug of the new/refined rule (empty if `valid-deferred`/`rejected` or no proposal yet)
   - `status`: one of `pending`, `catalog-updated`, `catalog-rejected`, `superseded`

   See `data/README.md` §"panel-misses.csv" for the authoritative schema and append discipline.

**Why this loop matters**: the pre-PR panel is the agent's quality gate. When an external reviewer finds something the panel missed, that's evidence of a blind spot. Without converting blind spots into catalog rules, the next PR has the same blind spot — observed in practice (the comment-rule regression, the publication-barrier discipline gap, the test-subscription-ordering gap all started as panel-misses).

**How to detect a process violation**: if a PR has external-reviewer findings AND the agent has amended/follow-up-committed AND there is NO corresponding entry in `data/panel-misses.csv`, the loop was bypassed. The user can call this out at any point and the agent MUST classify + record before further work.

## Iteration discipline (panel re-convergence) — MANDATORY

When a panel returns any verdict other than `unanimous READY`, the agent MUST iterate:

1. **Revise the plan / code** addressing every finding (or explicitly document why a finding is set aside with rationale).
2. **Re-launch the SAME panel slate** (same composition; substitutions allowed per the floor rules) on the revised work.
3. **Repeat until `unanimous READY`** (or until the `fix_iteration_count` cap is reached — see below).

The agent MUST NOT:

- **Substitute user approval for panel re-convergence.** If a panel returns `NEEDS_REWORK`, presenting a synthesized revised plan to the user as a "please approve so I can implement" step is a process violation. User approval is necessary but NOT sufficient — the panel is the independent-validation mechanism, and only the panel can clear its own findings. This is the most common regression vector observed in practice.
- **Treat "I addressed the findings" as equivalent to "the panel cleared the findings".** The panel must see the revised work and re-verify.
- **Silently skip iteration** by collapsing multiple rounds into "we'll fix it in implementation". Findings are the panel's word; only the panel can retract them.

The agent MAY:

- **Surface the iteration status to the user** between rounds (e.g., "Round 1 returned 4/4 NEEDS_REWORK with convergent findings X, Y, Z — applying fixes and re-launching panel"). This is informational, not approval-seeking.
- **Request user override of the iteration requirement** via same-turn `ask_user` quote with literal token `iteration-waive-acknowledged` — rare cases where the user explicitly decides to bypass (e.g., panel-found findings are deferred to follow-up work tracked elsewhere). The waive MUST be recorded in the `PANEL CONVERGED` block's `iteration_waive` field. Default is iterate.

**How to detect a process violation in practice**: if the agent has emitted a synthesis of panel findings + a "approve this revised plan?" `ask_user` without a fresh panel slate launch between the two, the iteration discipline was bypassed. The user can call this out at any point and the agent MUST re-launch the panel before any further implementation work.

## User diff-approval after panel READY — MANDATORY

The pre-PR-creation panel (and any pre-implementation panel run on uncommitted working-tree changes) certifies the code from a multi-model technical-review perspective. **On project (non-instruction) repositories**, this does NOT substitute for the user's diff-approval gate in `pre-commit.md`.

When a panel returns `unanimous READY` on uncommitted project-repo work, the agent MUST NOT:

- **Substitute panel READY for the `pre-commit.md` diff-approval gate.** Panel verdict is necessary but NOT sufficient. The `pre-commit.md` flow (show diff, `ask_user` for approval, emit `PRE-COMMIT GATE PASSED` block) MUST still fire before any commit-producing tool call (`git commit`, `git commit --amend`, `git cherry-pick`, `git rebase`-driven replay, `git am`, or any other tool call that produces a new commit object), `git push`, or PR-creation tool call. The narrow `pre-commit.md` §"Skip conditions" remain available where their stated conditions apply — they govern when the `PRE-COMMIT GATE PASSED` block may be omitted (e.g., mechanical `--amend --no-edit` after a clean rebase) and are NOT a generic "panel READY covers diff-approval" waiver.
- **Chain panel READY into commit-producing tool calls, `git push`, or `gh pr create`.** This skips two independent gates (user diff-approval AND the `PRE-COMMIT GATE PASSED` block) by treating the panel as both technical-review and user-review. The two are independent: the panel reviews technical correctness; the user reviews scope, intent, and approves the resulting commit.
- **Treat a panel run on uncommitted changes as "post-commit review".** A panel on the working tree is a *pre-commit* technical review; commit gates still apply afterward.

The agent MAY:

- Surface panel READY to the user as informational status (e.g., "4/4 panel READY; ready to show diff for your approval").
- Show the diff via `git --no-pager diff` (or equivalent) immediately after panel convergence to enable the user-review step.

**Instruction-repo scope**: this rule does not modify the existing `review-workflow-gates.md` §"Pushing changes to project (non-instruction) repos requires explicit user diff approval BEFORE staging" asymmetry. Edits to instruction repositories (e.g., `CopilotInstructions/main`, the lightweight-gate-v5 branch) continue to follow the existing instruction-repo rules in `review-workflow-gates.md` §1B — the project-repo prohibitions above do not extend to them. Any tension between that asymmetry and `pre-commit.md`'s universal hard-gate language is a pre-existing scope question outside the scope of this rule.

**How to detect a process violation in practice**: if the agent has launched a commit-producing tool call, `git push`, or PR-creation tool call without an emitted `PRE-COMMIT GATE PASSED` block in the same chat turn (and outside the narrow `pre-commit.md` §"Skip conditions" exemptions) — regardless of how many panels converged READY beforehand — the diff-approval gate was bypassed. The user can call this out at any point; the agent MUST roll back the offending commits (revert / `git reset` + restore working tree) and re-run the gate. Same remediation procedure as `pre-commit.md` §"Falsification is a higher-severity failure than skipping" (which treats omission as the lower-severity sibling of falsification).

## Fix-iteration cap

After panel returns `NEEDS_REWORK`, agent applies fixes + re-runs panel. Cycle counter is `fix_iteration_count`; default cap is **3 cycles**.

When cap is hit:
- **`cap-with-regressions`**: each iteration introduces NEW findings on top of resolving old ones — abort; emit `ask_user` quoting all iterations' verdicts. User authorizes override OR routes via G4 `routed-deferred-with-tracker-and-ask_user`.
- **`cap-with-new-clean-categories`**: iterations resolve old findings but reveal new ones in previously-unreviewed code areas — typically indicates panel is doing useful work; user authorizes cap override (e.g., raise to 5) with explicit quoted approval.

Cap override is recorded in `fix_iteration_count_cap` field of `PANEL CONVERGED` block.

## System-prompt-rule enforcement (defensive — MANDATORY)

The agent's system prompt contains style rules that may not be fully wired into `gate-runner.{ps1,sh}` or `pattern-catalog.md` yet. Reviewers MUST flag violations of these rules even when no corresponding `coding-preferences.md` or `pattern-catalog.md` entry exists for the specific instance.

Each reviewer's prompt MUST include this preamble (alongside the same-state re-check preamble):

> The agent's system prompt enforces style rules beyond the catalog. In particular: "Only comment code that needs a bit of clarification. Do not comment otherwise." Treat this as a gate rule even if not enumerated in `coding-preferences.md`. **Apply only to code newly added or modified in this PR (the `+` lines of the diff); do NOT flag pre-existing comments on baseline lines of modified files.** Flag: multi-line `<remarks>` XML doc blocks; inline comments narrating what (not why) the code does; comments referencing PR history, panel slots, round numbers, or planning artifacts. Brief one-line `<summary>` on public APIs and one-line *why*-comments for subtle behavior are fine.

This is the catch-net for the gap between "rule exists in system prompt" and "rule is auto-detected by gate-runner". Without it, panel reviewers truthfully report "0 violations" against the catalog while system-prompt rules silently regress (the exact failure mode observed in the IModalCoordinator PR 1+2 review).

## Reviewer same-state re-checks

Each reviewer's prompt MUST include this preamble:
> Before producing your verdict, re-fetch `git rev-parse HEAD` in the consuming-project worktree. The expected SHA is `<panelHeadSha>` recorded at launch time. If your HEAD does NOT match (i.e., new commits landed after launch), ABORT with a `NEEDS_REWORK` verdict citing "stale launch SHA: launched against `<panelHeadSha>`, current HEAD is `<currentSha>`". The orchestrator will re-launch the panel from current HEAD.

This prevents reviewers from certifying a diff that has been amended/rebased mid-review.

## Review-pass-only pattern forwarding (Slot 1 NB-2)

For every catalog entry with `scope_mode: review-pass-only`, `invoke-panel.ps1` extracts the entry's `review_pass_only_prompt` text and appends it to the system prompt of EACH reviewer in the slate (full + triage modes). The reviewers see:
> ## Review-pass-only patterns to verify
> (one bulleted item per catalog `review_pass_only_prompt`)

Without this, the highest-frequency pattern in the seed corpus (`doc-impl-mismatch` at ~11% of all hits) is undetectable — rg cannot catch prose-vs-code divergence.

`lint-only` mode skips panel invocation entirely → review-pass-only patterns ARE NOT checked in lint-only mode. This is part of the user-acknowledged trade-off for the `lint-only-acknowledged` token (audit trail makes the gap explicit).

## Per-rule acknowledgement (rule-coverage gate)

Every panel verdict AND every pre-commit gate MUST emit a `core_rules_acknowledged` block enumerating every HIGH-tier review-pass-only catalog slug with an explicit disposition. This is the rule-coverage forcing function: without per-site evidence, an `applied` status is not falsifiable.

### Schema (canonical)

```yaml
core_rules_acknowledged:
  - slug: <string>                  # exact catalog slug
    status: <applied | not-applicable>
    evidence:                       # REQUIRED when status=applied for review-pass-only slugs
      per_site_citations:           # REQUIRED — aggregate counts alone are INVALID
        - file: <relative path>
          line: <int or int-range>
          disposition: <rename | extract | remove | restore | keep-because>
          rename_diff: <string>     # required when disposition=rename
          extract_diff: <string>    # required when disposition=extract
          restore_diff: <string>    # required when disposition=restore
          keep_reason: <string>     # required when disposition=keep-because; ≤12 words; MUST add information beyond comment text
      diff_metric_check: <string>   # cross-check: rg-violation count or git-diff-extracted count matched against per_site_citations.Count
      divergence_acknowledged: <string>  # required when rg-battery count > per_site_citations.Count; ≤50-word specific reason; logged to panel-misses.csv.divergence_override_history
    rationale: <string>             # REQUIRED when status=not-applicable; ≤30-word justification
```

### Verification (BLOCK with manual override)

The runner cross-references rg-battery violation counts (for hybrid/diff/tree-scoped rules) against `core_rules_acknowledged.evidence.per_site_citations` count:

- **Counts match**: gate-status OK
- **rg-battery count > acknowledged count**: BLOCK by default. Reviewer overrides by adding `divergence_acknowledged: <specific reason>` field (≤50 words). Tautology meta-rule: reason MUST cite a specific external factor (generator output, conditional-compilation, FP listed in catalog `fp_slug`) and MUST contain at least one content token not present in the original rule text.
- **Override is logged**: `panel-misses.csv.divergence_override_history` accumulates the reason string for audit.

### What counts as evidence

For each `status: applied` entry on a review-pass-only slug:
- **MANDATORY**: `per_site_citations` list with file:line:disposition triples for every site the slug applies to in the diff
- **MANDATORY**: `diff_metric_check` cross-reference (e.g., `git diff --cached -U0 | grep -cE '^\+\s*(//|///|/\*)'` returned N; `per_site_citations` covers N sites)
- **ROTE-CHECKBOX FAILURE MODE**: `evidence` with only an aggregate count and no per-site list → gate BLOCKED

For each `status: not-applicable` entry:
- **MANDATORY**: `rationale` (≤30 words) citing why slug doesn't apply (e.g., "no new sync calls in async methods; verified by diff inspection")

### Trivial-PR carve-out

The per-rule acknowledgement requirement is REDUCED (not eliminated) when ALL of:
- `panel_mode: lint-only` AND
- `diff_scope` shows ≤2 files changed AND
- The existing `least-privilege-audit.md` touched-file gate result returns "no public-surface delta" (NOT a regex-only check — reuses the existing audit's per-file classification)

In the reduced path, the agent emits `core_rules_acknowledged: [trivial-pr-carveout: applied]` with a single entry citing the audit result. Other HIGH-tier slugs are skipped with their auto-derived `not-applicable-because-trivial-pr-carveout` status.

## Anti-recidivism enforcement (PR-specific recurrence sweep)

For PRs with prior entries in `.github/pr-quality-gate/data/panel-misses.csv` (matched by `pr_ref` column), the panel + gate emit an ANTI-RECIDIVISM PREAMBLE listing every prior slug hit on this PR. Reviewers MUST emit `verified-no-recurrence: <slug>` per prior slug, OR surface a recurrence as a blocking finding.

### Activation

- `invoke-panel.ps1 -PrRef <ref>` (PRIMARY): emits anti-recidivism preamble in `PANEL LAUNCH CONTRACT` under `reviewer_prompt_must_include.anti_recidivism_preamble`; reviewers see it before producing verdict
- `gate-runner.ps1 -PrRef <ref>` (SECONDARY): emits same preamble in `QUALITY GATE` output for the agent's pre-commit visibility

`-PrRef` is a manually-supplied opaque token matching existing `panel-misses.csv.pr_ref` values (e.g., `consuming-pr-8`). NOT auto-derived. Default empty → no anti-recidivism (preserves backward compat).

### Verified-no-recurrence schema

```yaml
verified_no_recurrence:
  - slug: <prior-slug>
    fix_evidence:                   # REQUIRED — pointer to where prior occurrence was resolved
      commit_sha: <40-char>         # commit that addressed the prior occurrence
      diff_hunk: |                  # OR pasted diff hunk showing the fix
        <git-diff snippet>
```

Without `fix_evidence`, the verdict is treated as NEEDS_REWORK (textual ack alone is checkbox-theater).

## Machinery-side preamble emission (compaction-safe)

`gate-runner.ps1` + `gate-runner.sh` + `invoke-panel.ps1` ALL print these blocks at the top of their stdout on every invocation:

1. **HIGH-tier slug list**: `required_rule_ack: [<slug>, ...]` from current `pattern-catalog.md` HIGH-tier rows (via `HIGH-TIER-SLUGS.md` derived index)
2. **rg-battery flagged sites** (gate-runner only): `rg_flagged_sites: { <slug>: [{file, line}, ...] }` per slug from this run
3. **Anti-recidivism preamble** (when `-PrRef` supplied): listed slugs the agent / panel must clear

These print on EVERY invocation regardless of session-compaction state — the agent always sees them at the moment of need. This is the load-bearing mitigation: rules in `AGENTS.md` survive load-time compaction; machinery emission survives runtime-application-time compaction.

## Panel output → QUALITY GATE block mapping

`invoke-panel.ps1` emits a `PANEL CONVERGED` block when convergence is reached. Fields surfaced into the QUALITY GATE block's `panel:` subsection (per `README.md` block format):

```
panel:
  invoked: <true|false>                     # false only for lint-only
  slate_floor_passed: <bool>
  reviewers: [<slot>: <model> <family> <role>, ...]
  convergence_model: <enum>
  convergence_result: <passed|failed>
  dropped_reviewers: [<slot>, ...]
  panel_rounds: <int>
  fix_iteration_count: <int>
  must_fix_unresolved: <int>
  core_rules_acknowledged: <see §Per-rule acknowledgement>
  rule_coverage_passed: <bool>              # true if all HIGH-tier review-pass-only slugs have an applied/not-applicable disposition
  anti_recidivism_acknowledged: <list>      # verified-no-recurrence entries; empty if no PrRef
```

§1B enforcement requires `convergence_result: passed` AND `dropped_reviewers: []` (or replacements present) AND `must_fix_unresolved: 0` AND `rule_coverage_passed: true` before any G6 forbidden-tool call.

## Slate-floor checkpoint timing

- **Checkpoint #1**: BEFORE launch. If composition cannot satisfy floor (e.g., insufficient available models), abort with `ask_user`.
- **Checkpoint #2-N**: AFTER each drop+replacement. If floor would be broken after a drop, drop-handling rule above fires.
- **Final checkpoint**: BEFORE emitting `PANEL CONVERGED`. Final slate must meet floor; substitutions recorded in `slate_substitutions`.

Recorded in `slate_floor_passed: true|false` field. Any `false` → gate BLOCKED.
