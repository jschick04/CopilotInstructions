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
