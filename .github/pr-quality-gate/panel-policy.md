# PR Quality Gate — Panel Policy

Multi-reviewer panel governance for the `full` and `triage` modes. Read by the orchestrator before invoking `invoke-panel.ps1`. The script is a thin launcher; policy lives here so it's reviewable + amendable independently of the launcher code.

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

## Fix-iteration cap

After panel returns `NEEDS_REWORK`, agent applies fixes + re-runs panel. Cycle counter is `fix_iteration_count`; default cap is **3 cycles**.

When cap is hit:
- **`cap-with-regressions`**: each iteration introduces NEW findings on top of resolving old ones — abort; emit `ask_user` quoting all iterations' verdicts. User authorizes override OR routes via G4 `routed-deferred-with-tracker-and-ask_user`.
- **`cap-with-new-clean-categories`**: iterations resolve old findings but reveal new ones in previously-unreviewed code areas — typically indicates panel is doing useful work; user authorizes cap override (e.g., raise to 5) with explicit quoted approval.

Cap override is recorded in `fix_iteration_count_cap` field of `PANEL CONVERGED` block.

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
