# PR Quality Gate - Panel Policy

Multi-reviewer panel governance for `full` and `triage` modes. The orchestrator reads this before invoking `invoke-panel.ps1`; the script stays a thin launcher so policy is reviewable + amendable independently.

## When the panel runs (timing requirement - MANDATORY)

TWO panel invocation points per task, both required for non-trivial work:

1. **Pre-implementation panel** - AFTER the agent drafts a plan and (when applicable) has it critiqued by `rubber-duck`, but BEFORE writing any production code. Reviewers see: (a) the issue / user request, (b) the plan, (c) the rubber-duck critique and the agent's response to each finding, (d) the relevant current code surfaces. Required verdict: `unanimous DESIGN_READY` before code is written. Catches design flaws while correction is cheap.
2. **Pre-PR-creation panel** - AFTER code + tests are written and the build is green, BEFORE `gh pr create` or `git push`. `gate-runner.ps1`/`.sh` runs the rg-battery + scaffolds the reviewer set; the panel + verdict are AGENT-ASSERTED via the §1B `QUALITY GATE` block. Reviewers see the diff + block. Target verdict: `unanimous CODE_REVIEW_READY`.

"Non-trivial" means any of: ≥3 files changed, new interface members, new state, behavioral changes to existing public APIs, security/concurrency code, or anything called a feature/refactor/add/implement. A small isolated single-file bugfix (e.g., 1-line typo) MAY skip pre-implementation panel if the agent justifies the skip in the same-turn `ask_user` quote.

Skipping pre-implementation panel for non-trivial work is a process violation. The agent MUST surface the skip via `ask_user` so the user can authorize before code is written.

## Mode definitions

| mode | reviewers | output cap | rg battery | `§1A` slate carve-out | Activation |
|---|---|---|---|---|---|
| `full` | 4 or more distinct heavy reviewers; default slate of 4 | none | yes | none - full floor applies | default; no receipt |
| `triage` | exactly 2 distinct-family light code-reviewers | none | yes | `slate-mode: triage; slate-size=2; convergence_model: unanimous` | all fast-path predicates + same-turn `triage-acknowledged` receipt; forbidden for governance/safety-critical changes |
| `lint-only` | 0 | n/a | yes | `slate-mode: lint-only; no panel invoked` | same-turn `lint-only-acknowledged` receipt |

CLI flag is the ONLY robust activation mechanism. Env vars and `plan.md` flags are NOT honored (too persistent, bypass-prone).

## Slate composition floor (`full` mode)

- At least 4 reviewers; all heavy-tier; distinct model names.
- At least 1 Claude, 1 GPT, 1 Gemini, and 2 combined GPT/Grok reviewers.
- At least 1 rubber-duck and 2 code-review roles.
- Default slate: heavy-claude-standard rubber-duck; heavy-gpt-premium, heavy-gemini-premium, heavy-grok-premium code-review. Optional fifth: heavy-gpt-codex.
- If Grok is unavailable, heavy-gpt-codex is the only cross-family fallback. Record `slate-substitution: slot:<id> tier:heavy-grok-premium from:<parent-grok-model> to:<parent-codex-model> reason:family-unavailable` plus `registry-rotation: "registry-rotation-acknowledged" ref:<approval-ref> map:heavy-grok-premium=<parent-grok-model>><parent-codex-model>`. Both models must resolve to those named parent-registry tiers; this fallback does not rotate the heavy allowlist.

## Triage floor and predicates

Triage is exactly 2 light code-review reviewers from distinct families, with distinct models and unanimous convergence. Default: light-claude-balanced + light-gpt; light-gemini may replace an unavailable family while keeping families distinct. The same-turn `triage-acknowledged` receipt is required. It is permitted only when all predicates hold: (a) not governance/instruction; (b) not safety-critical; (c) docs-only OR fewer than 10 changed lines with no control-flow, public-API, or concurrency change. Any uncertainty escalates to full. Triage is forbidden when `Test-RequiresFullPanel` is true.

Slot effort and context use the tier's registry values. `profile` in a panel ledger means the mode actually run: `full` or `triage`; `lint-only` emits no panel ledger.

## Checker-enforced ledger rows

Column-0 rows in the staged-bound `POST-CODE-CHANGE LEDGER` (schema: `review-workflow-gates-sweeps.md` §2B); `<...>` placeholders fail closed:

```
profile: <full|triage>
checker-edit: "checker-edit-acknowledged" ref:<call-ref> paths:<n>
triage-ack: "triage-acknowledged" ref:<call-ref>
slate-substitution: slot:<id> tier:<tier-id> from:<model|none> to:<model> reason:<model-retired|model-superseded|tier-added|family-unavailable>
registry-rotation: "registry-rotation-acknowledged" ref:<call-ref> map:<tier-id>=<from>><to>[,...]
```

- `checker-edit` iff the staged diff touches guarded paths: first `ask_user` listing EVERY guarded path; `paths:` equals that count (`git diff --cached --name-only --no-renames <parent_sha>`). A pure same-vendor heavy-model addition is not a rotation: it needs a guarded, checker-edit-acknowledged change to the rotation rule in `scripts/lib/panel-ledger-helpers.psm1` (listed in that `ask_user`), not just the ack.
- `triage-ack` iff `profile: triage`; never when `Test-RequiresFullPanel` is true.
- `slate-substitution` per changed slot (`from:none` only with `reason:tier-added`) plus exactly one `registry-rotation` whose `map:` lists every substitution and allowlist rotation; first `ask_user` showing each `<tier-id>=<from>><to>` mapping. Rotation must stay same-vendor except the Grok -> codex `family-unavailable` fallback.

## Convergence model

Every multi-reviewer panel requires unanimous success verdicts. A non-unanimous result requires fixes and another review round; reuse the same idle reviewers with the delta and their prior findings. There is no cap on rounds or follow-ups. Triage is also unanimous: both reviewers must return the success verdict. Reviewers bind each verdict to the artifact hash they independently compute; a verdict for an earlier artifact never carries forward.

## Drop handling (`full` mode only)

`lint-only` has no reviewers. Triage replacements must preserve two distinct families and light tiers.

| dropped_count | action |
|---|---|
| 0 | proceed |
| 1 | launch replacement (same family + role + tier; record in `replacement_reviewers` field) |
| 2 | `ask_user` quoting both drops; user decides proceed-with-2-replacements OR abort |
| ≥ 3 | hard escalate - abort panel; emit `ask_user` with all drops listed; require user to authorize remediation (retry later, etc.) |

Each drop is recorded in `dropped_reviewers` field with timestamp + reason (timeout, error, drop-explicit).

## Post-PR-review feedback loop (MANDATORY)

External reviewer findings (e.g., GitHub Copilot pull request reviewer, PR humans, post-merge security review) are OBSERVED ground truth for what the pre-PR panel missed. Treating them as one-off fixes without classification means the next PR likely has the same blind spot. The feedback loop is mandatory.

For EACH external-reviewer finding on a PR with a converged pre-PR panel:

1. **Classify** the finding (values map to the `data/panel-misses.csv` classification enum in `data/README.md`; `process-confirmation`/`process-violation` are non-triage row types - the former per `data/README.md`, the latter per the process-violation detector below):
   - `panel-miss`: should have caught it, but NO catalog rule covers it (rule absent). → Append a row (`pending`); propose a new `pattern-catalog.md` entry.
   - `panel-execution-failure`: a catalog rule EXISTED but the panel didn't apply it (execution lapse, not a gap). → Append a row (`catalog-existing`); if the rule's wording or audit-method let the miss through, refine it → `catalog-strengthened`.
   - `false-positive`: the reviewer's detection is wrong or spurious. → Append a row with source-grounded rationale; no catalog change.
   - `valid-deferred`: reasonably skipped (out-of-scope by design - post-merge, separate-PR, or infra). → Note in the PR; no catalog change.
   - `rejected`: the agent disputes the recommendation or severity (the issue may be arguable), with source-grounded rationale. → No catalog change; user may escalate.

2. **Apply the fix** (amend or follow-up commit) AND update tracking in the SAME session:
   - For each `panel-miss`, `panel-execution-failure`, or `false-positive`: append a row to `data/panel-misses.csv` (status per `data/README.md`).
   - For each new or refined catalog rule proposed: append to `pattern-catalog.md` and run a panel on the change (full iteration discipline applies - no rule lands without convergence).
   - The agent MUST NOT close the PR loop without updating tracking. If tracking is deferred (e.g., user authorizes "fix-now-track-later"), the agent MUST surface it via same-turn `ask_user` with literal token `panel-miss-deferred`.

3. **`data/panel-misses.csv` schema**: see `data/README.md` §"panel-misses.csv" for the authoritative 10-field schema, status enum, classification enum, RFC 4180 quoting requirements, and append discipline.

**Why this loop matters**: the pre-PR panel is the agent's quality gate. When an external reviewer finds something the panel missed, that's evidence of a blind spot. Without converting blind spots into catalog rules, the next PR has the same blind spot.

**How to detect a process violation**: if a PR has external-reviewer findings AND the agent has amended/follow-up-committed AND there is NO corresponding entry in `data/panel-misses.csv`, the loop was bypassed. The user can call this out at any point and the agent MUST classify + record before further work. A `process-violation` row carries `status=pending` while the gap is open and the appropriate `catalog-*` status once the gap is mechanized into a gate/instruction (mirrors a remediated miss).

## Iteration discipline (panel re-convergence) - MANDATORY

When a panel returns any verdict other than its unanimous success verdict, the agent MUST iterate:

1. **Revise the plan / code** addressing every finding (or explicitly document why a finding is set aside with rationale).
2. **Re-launch the SAME panel slate** (same composition; substitutions allowed per the floor rules) on the revised work.
3. **Repeat until the panel reaches its unanimous success verdict.** There is no round cap.

The agent MUST NOT:

- **Substitute user approval for panel re-convergence.** If a panel returns `NEEDS_REWORK`, presenting a synthesized revised plan to the user as a "please approve so I can implement" step is a process violation. User approval is necessary but NOT sufficient - the panel is the independent-validation mechanism, and only the panel can clear its own findings.
- **Treat "I addressed the findings" as equivalent to "the panel cleared the findings".** The panel must see the revised work and re-verify.
- **Silently skip iteration** by collapsing multiple rounds into "we'll fix it in implementation". Findings are the panel's word; only the panel can retract them.

The agent MAY surface iteration status between rounds as information. It must continue until unanimous convergence.

**How to detect a process violation in practice**: if the agent has emitted a synthesis of panel findings + a "approve this revised plan?" `ask_user` without a fresh panel slate launch between the two, the iteration discipline was bypassed. The user can call this out at any point and the agent MUST re-launch the panel before any further implementation work.

## User commit-approval after panel CODE_REVIEW_READY - MANDATORY

The pre-PR-creation panel certifies the code from a multi-model technical-review perspective. **On project (non-instruction) repositories**, this does NOT substitute for the user's commit-approval gate in `pre-commit.md`.

When a panel returns `unanimous CODE_REVIEW_READY` on uncommitted project-repo work, the agent MUST NOT:

- **Substitute panel CODE_REVIEW_READY for the `pre-commit.md` user-review gate.** Panel verdict is necessary but NOT sufficient. The `pre-commit.md` flow (classify the staged set, commit-approval `ask_user`, emit `PRE-COMMIT GATE PASSED` block) MUST still fire before any commit-producing tool call (`git commit`, `git commit --amend`, `git cherry-pick`, `git rebase`-driven replay, `git am`, or any other tool call that produces a new commit object), `git push`, or PR-creation tool call. The narrow `pre-commit.md` §"Skip conditions" remain available where their stated conditions apply - they govern when the `PRE-COMMIT GATE PASSED` block may be omitted (e.g., mechanical `--amend --no-edit` after a clean rebase) and are NOT a generic "panel CODE_REVIEW_READY covers user-review" waiver.
- **Chain panel CODE_REVIEW_READY into commit-producing tool calls, `git push`, or `gh pr create`.** This skips two independent gates (user commit-approval AND the `PRE-COMMIT GATE PASSED` block) by treating the panel as both technical-review and user-review. The two are independent: the panel reviews technical correctness; the user reviews scope, intent, and approves the resulting commit.
- **Treat a panel run on uncommitted changes as "post-commit review".** A panel on the staged index is a *pre-commit* technical review; commit gates still apply afterward.

The agent MAY:

- Surface panel CODE_REVIEW_READY to the user as informational status (e.g., "4/4 panel CODE_REVIEW_READY on the user-staged index").
- Before the diff panel, let the user review by STAGING; use INDEX-ONLY sources (`git diff --cached`, `git show :path`, or an index export). Any later index change invalidates the panel and requires re-review; the agent does NOT auto-stage code.

**Instruction-repo scope**: §0 git safety gates (`ask_user` before every `git commit` / `git push`, plus the never-auto-stage-code rule) apply in ALL repos. The panel certification waives ONLY the EXTRA §1B working-tree-review step for instruction-repo edits (see `review-workflow-gates.md` §1B), never §0.

**How to detect a process violation in practice**: if the agent has launched a commit-producing tool call, `git push`, or PR-creation tool call without an emitted `PRE-COMMIT GATE PASSED` block in the same chat turn (and outside the narrow `pre-commit.md` §"Skip conditions" exemptions) - regardless of how many panels converged CODE_REVIEW_READY beforehand - the commit-approval gate was bypassed. The user can call this out at any point; the agent MUST roll back the offending commits (revert / `git reset` + restore working tree) and re-run the gate. Same remediation procedure as `pre-commit.md` §"Falsification is a higher-severity failure than skipping" (which treats omission as the lower-severity sibling of falsification).


## System-prompt-rule enforcement (defensive - MANDATORY)

The agent's system prompt contains style rules not yet fully wired into `gate-runner.{ps1,sh}` or `pattern-catalog.md`. Reviewers MUST flag violations of these rules even when no corresponding `coding-preferences.md` or `pattern-catalog.md` entry exists for the specific instance.

Each reviewer's prompt MUST include this preamble (alongside the same-state re-check preamble):

> The agent's system prompt enforces style rules beyond the catalog. In particular: "Only comment code that needs a bit of clarification. Do not comment otherwise." Treat this as a gate rule even if not enumerated in `coding-preferences.md`. **Apply only to code newly added or modified in this PR (the `+` lines of the diff); do NOT flag pre-existing comments on baseline lines of modified files.** Flag: multi-line `<remarks>` XML doc blocks; inline comments narrating what (not why) the code does; comments referencing PR history, panel slots, round numbers, or planning artifacts. Brief one-line `<summary>` on public APIs and one-line *why*-comments for subtle behavior are fine.

This is the catch-net for the gap between "rule exists in system prompt" and "rule is auto-detected by gate-runner". Without it, panel reviewers truthfully report "0 violations" against the catalog while system-prompt rules silently regress.

## Reviewer same-state re-checks

Each reviewer's prompt MUST include this preamble:
> At review start and before verdict, recompute the mode artifact with `Get-ReviewedArtifactId.ps1 -Staged [-ParentSha <HEAD^ full SHA | none>]` for an index panel, `-Commit <full sha>` for a committed commit panel, or `-Range "<BaseSha>..<HeadSha>"` using recorded full SHAs for a range panel. For an amend, staged review uses the first-parent SHA (or `none` for a root commit); cherry-pick and rebase replay use plain `-Staged`. Compare the first stdout line to the launch artifact. A mismatch or command failure requires `NEEDS_REWORK` and a fresh panel against the current artifact; HEAD alone cannot detect index changes.

This prevents certifying a diff amended/rebased mid-review.

## Review-pass-only pattern forwarding (Slot 1 NB-2)

For every catalog entry with `scope_mode: review-pass-only`, `invoke-panel.ps1` extracts the entry's `review_pass_only_prompt` text and appends it to the system prompt of EACH reviewer in the slate (full + triage modes). The reviewers see:
> ## Review-pass-only patterns to verify
> (one bulleted item per catalog `review_pass_only_prompt`)

Without this, the highest-frequency pattern in the seed corpus (`doc-impl-mismatch` at ~11% of all hits) is undetectable - rg cannot catch prose-vs-code divergence.

`lint-only` mode skips panel invocation entirely → review-pass-only patterns ARE NOT checked in lint-only mode. This is part of the user-acknowledged trade-off for `lint-only-acknowledged` (audit trail makes the gap explicit).

## Per-rule acknowledgement (rule-coverage gate)

Every panel verdict AND every pre-commit gate MUST emit a `core_rules_acknowledged` block enumerating every HIGH-tier review-pass-only catalog slug with an explicit disposition. This is the rule-coverage forcing function: without per-site evidence, an `applied` status is not falsifiable.

**Process rules** (slugs that check a process artifact rather than code - currently `implementation-to-commit-transition-bypasses-user-approval`, `full-scan-against-new-rule-not-triggered-after-bot-finding`, `least-privilege-audit-required-on-visibility-delta`, `intent-driven-testing-required-on-test-or-SUT-delta`): reviewer verifies the artifact (PRE-GIT SENTINEL block, POST-CODE-CHANGE LEDGER field, `full_scan_results` field) in the agent's text output earlier in the conversation. The `evidence.per_site_citations` for a process rule points at the ledger / sentinel block citation rather than a source-file location.

### Schema (canonical)

```yaml
core_rules_acknowledged:
  - slug: <string>                  # exact catalog slug
    status: <applied | not-applicable>
    evidence:                       # REQUIRED when status=applied for review-pass-only slugs
      per_site_citations:           # REQUIRED - aggregate counts alone are INVALID
        - file: <relative path>
          line: <int or int-range>
          disposition: <rename | extract | remove | restore | keep-because>
          rename_diff: <string>     # required when disposition=rename
          extract_diff: <string>    # required when disposition=extract
          restore_diff: <string>    # required when disposition=restore
          keep_reason: <string>     # required when disposition=keep-because; MUST add information beyond comment text
      diff_metric_check: <string>   # cross-check: rg-violation count or git-diff-extracted count matched against per_site_citations.Count
      divergence_acknowledged: <string>  # required when rg-battery count > per_site_citations.Count; ≤50-word specific reason; logged to panel-misses.csv.divergence_override_history
    rationale: <string>             # REQUIRED when status=not-applicable; 3-30w, >=1 repo/code-specific token, NOT in {na,n/a,skip,none,unknown,false-positive,not-applicable} (anti-tautology)
```

### Chat-emission form (caveman)

Chat + gate emit `core_rules_acknowledged` in the compressed one-line-per-slug grammar defined in `post-code-change.md` §"core_rules_acknowledged - chat-emission form (caveman)" (DRY). The YAML above is the canonical/audit-file form.

### Verification (BLOCK with manual override)

The runner cross-references rg-battery violation counts (for hybrid/diff/tree-scoped rules) against `core_rules_acknowledged.evidence.per_site_citations` count:

- **Counts match**: gate-status OK
- **rg-battery count > acknowledged count**: BLOCK by default. Reviewer overrides by adding `divergence_acknowledged: <specific reason>` field (≤50 words). Tautology meta-rule: reason MUST cite a specific external factor (generator output, conditional-compilation, FP listed in catalog `fp_slug`) and MUST contain at least one content token not present in the original rule text.
- **Override is logged**: `panel-misses.csv.divergence_override_history` accumulates the reason string for audit.

### What counts as evidence

`status: applied` (review-pass-only slug): `per_site_citations` (file:line:disposition per applicable site) AND `diff_metric_check` (e.g. `git diff --cached -U0 | grep -cE '^\+\s*(//|///|/\*)'` returned N; citations cover N) are BOTH MANDATORY. Aggregate count with no per-site list = ROTE-CHECKBOX FAILURE = gate BLOCKED. `status: not-applicable`: `rationale` MANDATORY (anti-tautology constraint in the schema above).

### Trivial-PR carve-out

The per-rule acknowledgement requirement is REDUCED (not eliminated) when ALL of:
- `panel_mode: lint-only` AND
- `diff_scope` shows ≤2 files changed AND
- The existing `least-privilege-audit.md` touched-file gate result returns "no public-surface delta" (NOT a regex-only check - reuses the existing audit's per-file classification)

In the reduced path, the agent emits `core_rules_acknowledged: [trivial-pr-carveout: applied]` with a single entry citing the audit result. Other HIGH-tier slugs are skipped with their auto-derived `not-applicable-because-trivial-pr-carveout` status.

## Anti-recidivism enforcement (PR-specific recurrence sweep)

For PRs with prior entries in `.github/pr-quality-gate/data/panel-misses.csv` (matched by `pr_ref` column), the panel + gate emit an ANTI-RECIDIVISM PREAMBLE listing every prior slug hit on this PR. Reviewers MUST emit `verified-no-recurrence: <slug>` per prior slug, OR surface a recurrence as a blocking finding.

### Activation

- `invoke-panel.ps1 -PrRef <ref>` (PRIMARY): emits anti-recidivism preamble in `PANEL LAUNCH CONTRACT` under `reviewer_prompt_must_include.anti_recidivism_preamble`; reviewers see it before producing verdict
- `gate-runner.ps1 -PrRef <ref>` (SECONDARY): emits same preamble in `QUALITY GATE` output for the agent's pre-commit visibility

`-PrRef` is a manually-supplied opaque token matching existing `panel-misses.csv.pr_ref` values. NOT auto-derived. Default empty → no anti-recidivism (preserves backward compat).

### Verified-no-recurrence schema

```yaml
verified_no_recurrence:
  - slug: <prior-slug>
    fix_evidence:                   # REQUIRED - pointer to where prior occurrence was resolved
      commit_sha: <full 40- or 64-hex>         # commit that addressed the prior occurrence
      diff_hunk: |                  # OR pasted diff hunk showing the fix
        <git-diff snippet>
```

Without `fix_evidence`, the verdict is treated as NEEDS_REWORK (textual ack alone is checkbox-theater).

## Machinery-side preamble emission (compaction-safe)

`gate-runner.ps1` + `gate-runner.sh` + `invoke-panel.ps1` ALL print these blocks at the top of their stdout on every invocation:

1. **HIGH-tier slug list**: `required_rule_ack: [<slug>, ...]` from current `pattern-catalog.md` HIGH-tier rows (via `HIGH-TIER-SLUGS.md` derived index)
2. **rg-battery flagged sites** (gate-runner only): `rg_flagged_sites: { <slug>: [{file, line}, ...] }` per slug from this run
3. **Anti-recidivism preamble** (when `-PrRef` supplied): listed slugs the agent / panel must clear

These print on EVERY invocation regardless of session-compaction state - the agent always sees them at the moment of need. This is the load-bearing mitigation: rules in `AGENTS.md` survive load-time compaction; machinery emission survives runtime-application-time compaction.

## Panel output → QUALITY GATE block mapping

`invoke-panel.ps1` emits a `CODE-REVIEW PANEL CONVERGED` block when convergence is reached. Fields surfaced into the QUALITY GATE block's `panel:` subsection (per `README.md` block format):

```
panel:
  invoked: <true|false>                     # false only for lint-only
  profile: <full|triage>
  slate_floor_passed: <bool>
  reviewers: [<slot>: <model> <family> <role>, ...]
  convergence_model: <enum>
  convergence_result: <passed|failed>
  dropped_reviewers: [<slot>, ...]
  panel_rounds: <int>
  must_fix_unresolved: <int>
  core_rules_acknowledged: <see §Per-rule acknowledgement>
  rule_coverage_passed: <bool>              # true if all HIGH-tier review-pass-only slugs dispositioned
  anti_recidivism_acknowledged: <list>      # verified-no-recurrence entries; empty if no PrRef
```

§1B enforcement requires `convergence_result: passed` AND `dropped_reviewers: []` (or replacements present) AND `must_fix_unresolved: 0` AND `rule_coverage_passed: true` before any G6 forbidden-tool call (the caveman `key=value` form satisfies this identically; `invoke-panel.ps1`'s per-mode contracts list all four keys for EVERY mode incl triage).

## Slate-floor checkpoint timing

- **Checkpoint #1**: BEFORE launch. If composition cannot satisfy floor (e.g., insufficient available models), abort with `ask_user`.
- **Checkpoint #2-N**: AFTER each drop+replacement. If floor would be broken after a drop, drop-handling rule above fires.
- **Final checkpoint**: BEFORE emitting `CODE-REVIEW PANEL CONVERGED`. Final slate must meet floor; substitutions recorded in `slate_substitutions`.

Recorded in `slate_floor_passed`. Any `false` = gate BLOCKED.

## Catalog-edit + ack-sync invariant - MANDATORY

`pattern-catalog.md` is the canonical source of HIGH-tier review-pass-only slugs that the panel MUST acknowledge per-commit (see §"Per-rule acknowledgement"). `HIGH-TIER-SLUGS.md` is a GENERATED file derived from `pattern-catalog.md` via `scripts/sync-critical-rules.ps1` (or its bash twin `scripts/sync-critical-rules.sh`, which produces byte-identical output). The invariant is: **every commit that edits `pattern-catalog.md` MUST also stage `HIGH-TIER-SLUGS.md` regenerated by the sync script**.

If the two files drift, the per-rule ack gate doesn't enforce newly-added HIGH-tier rules - the panel can silently skip them and the bot will catch them on PR review (back-and-forth the gate was designed to prevent). This invariant is enforced in **4 layers**:

| Layer | Mechanism | What it catches | Bypassable by |
|---|---|---|---|
| 1. Pre-commit hook | `.githooks/pre-commit` runs `sync-critical-rules -Verify -StagedMode` against the staged blobs | Local developer who forgot to regen before commit | `git commit --no-verify`; missing `core.hooksPath` config |
| 2. gate-runner pre-check | `gate-runner.ps1` / `gate-runner.sh` runs `sync-critical-rules -Verify` at startup | Stale CopilotInstructions clone in consuming projects | gate-runner not run for this PR |
| 3. invoke-panel pre-check | `invoke-panel.ps1` runs `sync-critical-rules -Verify` BEFORE the lint-only short-circuit | Stale clone at panel-launch time, even in lint-only mode | Panel not invoked for this PR |
| 4. CI workflow | `.github/workflows/catalog-sync-check.yml` runs `verify` job + `parity` job on every push and PR | `--no-verify` bypass at the local hook AND drift between pwsh+bash twins | Disabling required-checks on the merge branch (admin override) |

**Layer 1 enforcement**: `setup.ps1` (Windows) and `setup.sh` (Unix) configure `git -C <repo> config --local core.hooksPath .githooks`. Existing contributors who pulled this safeguard for the first time must run their platform's setup script OR manually `git config --local core.hooksPath .githooks`.

**Layer 4 parity job**: catches silent drift between `scripts/sync-critical-rules.ps1` (pwsh) and `scripts/sync-critical-rules.sh` (bash). Both must produce byte-identical output for every catalog state - the parity job hashes both via `git hash-object --stdin` and asserts equality. Any divergence blocks merge.

**Cross-platform stability**: content hash embedded in `HIGH-TIER-SLUGS.md` uses `git hash-object` (canonical normalized blob SHA-1, immune to working-tree CRLF/LF drift). The `.gitattributes` file (`* text=auto`) ensures consistent normalization on commit.

**When a future schema bump happens** (7th column, new tier value, etc.), the change MUST propagate to ALL of:
1. `scripts/sync-critical-rules.ps1` (pwsh generator)
2. `scripts/sync-critical-rules.sh` (bash twin)
3. `.github/pr-quality-gate/gate-runner.ps1` (`Read-CatalogTable`)
4. `.github/pr-quality-gate/gate-runner.sh` (bash parser)
5. `.github/workflows/catalog-sync-check.yml` (if it does any parsing of its own - currently doesn't)
6. `.githooks/pre-commit` (currently delegates to the sync script - no schema knowledge of its own)
7. `.github/pr-quality-gate/invoke-panel.ps1` (reviewer-prompt forwarding)

Otherwise a future schema bump can ship with stale layers (one implementation parses the new column, the others don't), the parity job fails, and back-and-forth resumes.
