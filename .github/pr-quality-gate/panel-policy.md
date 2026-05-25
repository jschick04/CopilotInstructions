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
```

§1B enforcement requires `convergence_result: passed` AND `dropped_reviewers: []` (or replacements present) AND `must_fix_unresolved: 0` before any G6 forbidden-tool call.

## Slate-floor checkpoint timing

- **Checkpoint #1**: BEFORE launch. If composition cannot satisfy floor (e.g., insufficient available models), abort with `ask_user`.
- **Checkpoint #2-N**: AFTER each drop+replacement. If floor would be broken after a drop, drop-handling rule above fires.
- **Final checkpoint**: BEFORE emitting `PANEL CONVERGED`. Final slate must meet floor; substitutions recorded in `slate_substitutions`.

Recorded in `slate_floor_passed: true|false` field. Any `false` → gate BLOCKED.
