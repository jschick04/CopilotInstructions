# Playbook: Pre-PR-creation review (§2D)
<!-- read-receipt-token: b339bc16 -->

## Purpose

Mandatory multi-model code-review panel on the FULL branch diff (`<base>..HEAD`) before any PR is created or made review-visible. Mirrors the categories an LLM-based PR reviewer (GitHub Copilot's PR-review feature and similar bot reviewers) would surface — runs locally pre-push so findings are caught and fixed BEFORE reviewers see them, not after.

Sister to `post-code-change.md` §3 (per-commit panel, lightweight). This is the branch-wide heavy pass once per PR-creation transition.

## Hard gates

### G1. Panel must run — not user-waivable

Cannot be skipped via `ask_user` quote. The only exit is convergence with must-fix=0.

### G2. Must-fix=0 — not user-waivable

Every reviewer-flagged `blocking` finding must be resolved via one of three G5 paths:

- `fixed` — applied as a change.
- `dismissed-source-grounded` — refuted by source evidence (file:line, doc URL, RFC, ADR, spec section) addressing the finding's claim. Hand-wave "out of scope" is invalid.
- `routed-deferred-with-tracker-and-ask_user` — see G4.

### G3. `PRE-PR REVIEW COVERAGE` block emitted in the PR-creation turn — not user-waivable

The block (format below) MUST appear in the same chat turn as the G6 PR-creation tool call.

Because the AGENTS `gh pr create` flow requires an intervening `ask_user` for title/body approval, the block is emitted twice:

1. **Initial** (turn N): at end of Step 7 with `pr-creation-status: READY-pending-user-approval`.
2. **Re-emitted** (turn N+1): in the PR-creation tool-call turn, after the user-approval `ask_user` returns, with same-state re-check (`git rev-parse HEAD` matches recorded `panelHeadSha`; `git merge-base --is-ancestor <panelHeadSha> HEAD` returns true; `git rev-parse <baseRef>` matches `panelBaseSha`). If any check fails, restart at Step 2. Block status: `READY-re-emitted-after-user-approval`.

Absence of the appropriate block in the PR-creation turn → all G6 tools are forbidden. Block being present only in an earlier turn does NOT satisfy this gate.

### G4. `routed-deferred-with-tracker-and-ask_user` requires both:

1. An actual external tracker issue (GitHub issue, ADO work item, Linear ticket, etc.) created in the same turn with a citable URL — NOT a session-todo, NOT a `TODO` / `FIXME` code comment, NOT a "tracked internally" hand-wave.
2. Explicit `ask_user` approval in the same turn naming the issue URL and confirming deferral.

### G5. C2 disposition enum

Per finding: `fixed | dismissed-source-grounded | routed-deferred-with-tracker-and-ask_user | routed-now-via-ask_user`. Every finding has a status; no orphans.

### G6. Forbidden-tool enumeration (mirrors §1B)

Until BOTH of these are present in the current turn, the agent MUST NOT call any of the tools below:

1. The G3 block from Step 9 (the **re-emitted** `PRE-PR REVIEW COVERAGE` block in the PR-creation tool-call turn) with `pr-creation-status: READY-re-emitted-after-user-approval`. The initial-emission status (`READY-pending-user-approval` from Step 7) is NOT sufficient — it indicates the panel converged but the user-approval step + same-state re-check have not yet happened. The `DRY-RUN-INFO-ONLY` status from the direct-invocation path is NEVER sufficient.
2. The `PATTERN PREFLIGHT` block (re-emitted in Step 9 alongside the COVERAGE block; computed in Step 2.5 originally) against the current `panelHeadSha` + current `catalogRevision`/`fpRegistryRevision`. The block MAY use one of the documented skip-condition statuses (`catalog: not-yet-built`, `catalog: empty-battery`, `catalog: skipped-bootstrap`, `catalog: skipped-no-production-diff`); the block must be present regardless. Absence of the block (not just a value) is the violation. Additionally, the re-emitted `PRE-PR REVIEW COVERAGE` block's `catalog-revision` / `fp-registry-revision` / `pattern-preflight-skip-status` fields (per the §G3 block format below) MUST be populated; absence or `<unset>` in those fields fails the gate.

- `gh pr create` (any flags incl. `--draft`)
- `gh pr ready`, `gh pr ready --undo`
- `gh api` POST/PATCH/PUT targeting `/repos/*/pulls`, `/repos/*/pullrequests`, or any PR-creation / draft-state-mutation endpoint
- `glab mr create`, `glab mr update --ready`/`--draft`
- `tea pr create`
- `az repos pr create`, `az repos pr update` (toggling draft)
- `git push` with `-o merge_request.create=*` / `-o pull_request.create=*` / `-o topic=*` auto-creating MR
- `git push <remote> HEAD:refs/for/*` (Gerrit)
- Any MCP-server tool whose intent is PR/MR creation or draft-state mutation on any forge
- Raw `curl`/`Invoke-WebRequest` to forge REST/GraphQL APIs posting PR-creation/draft-state endpoints
- Equivalents on any forge not enumerated above (Bitbucket, Gitea, Forgejo, Codeberg, Radicle, etc.)

Pattern: absence of the block IS the enforcement. New PR-creation pathways extend the list by intent, not literal name match.

### G7. Bootstrap exemption — narrow scope

A PR is BOOTSTRAP-EXEMPT from §2D only if ALL of:

1. The PR introduces a NEW mandatory gate that did not exist on `origin/<base>` pre-PR (verifiable: `git show origin/<base>:.github/playbooks/<gate-file>.md` does not exist or doesn't contain the gate definition).
2. The PR body includes the literal token `BOOTSTRAP-EXEMPTION: <gate-name>` (e.g., `BOOTSTRAP-EXEMPTION: §2D pre-PR-creation review gate`).
3. The PR includes ALL companion edits required for the new gate to be operative post-merge.

PRs that modify, tighten, loosen, or refactor an existing gate are NOT bootstrap-exempt — they go through the gate they're modifying. If the bootstrap token is removed from the PR body before merge, the exemption is revoked and subsequent pushes trigger §2D normally.

## Waive matrix

| Item | Waivable with `ask_user` quote? | Conditions / floor |
| --- | --- | --- |
| G1 (panel must run) | NO | — |
| G2 (must-fix=0) | NO | Individual findings may use G4 `routed-deferred-with-tracker-and-ask_user`; the gate-level must-fix=0 requirement stands. |
| G3 (block in PR-creation turn) | NO | — |
| G5 (disposition per finding) | NO | — |
| G6 (forbidden tools) | NO | — |
| G7 conditions | NO | Either all 3 conditions met or exemption doesn't apply. |
| Convergence model (default `unanimous`) | YES | Floor: `threshold ≥75%` or `confidence-weighted ≥80%`. Recorded under `convergence-waive`. Must-fix=0 still applies. |
| Slate composition | YES | Floor: ≥4 reviewers; ≥1 Claude family + ≥2 GPT family (one premium + one cross-version-or-codex) + ≥1 Gemini family; ≥1 `rubber-duck` role + ≥2 `code-review` role; ≥1 heavy-tier. Recorded under `slate-waive`. Re-checked after every drop/replacement. |
| Individual finding via G4 routed-deferred | YES (with G4) | External tracker URL + same-turn `ask_user` approval. |

Items not in the matrix are NOT waivable.

## Reviewer slate (default heavy)

Tier → current model via `multi-model-review/current-model-registry.md`.

| Slot | Tier id | Family | Role |
| --- | --- | --- | --- |
| 1 | `heavy-claude-xhigh` | Claude | `code-review` |
| 2 | `heavy-gpt-premium` | GPT | `code-review` |
| 3 | `heavy-gpt-codex` | GPT | `code-review` |
| 4 | `heavy-gpt-cross-version` | GPT | `code-review` |
| 5 | `heavy-gemini-premium` | Gemini | `code-review` |
| 6 | `heavy-claude-standard` | Claude | `rubber-duck` |

**Substitution rule**: if a model is unavailable (deprecated, API down, removed from runtime), substitute the highest-capability successor from the same family. Record under `slate-substitutions: [{slot, requested, substituted, reason}]`. Slate-floor (from waive matrix) re-checked after every substitution.

Liberal expansion encouraged for risky / cross-cutting / unfamiliar-area branches.

## Reviewer prompt

Use `multi-model-review/pr-creation-mirror-prompt.md` (the shared 11-category Copilot-mirror template). Consumer-specific substitutions: `<baseSha>`, `<headSha>`, `<repo-path>`, round context (when iterating), prior-commit panel dispositions (from `post-code-change.md` §3 ledgers when present), Intake Q4 context notes.

## Procedure

### Step 1. Determine invocation mode

This gate does NOT classify whether the push is review-targeting — that's `pre-pr-push.md`'s job.

- **Normal path** — If `pre-pr-push.md` phase-state record present AND its Step 5 hook fires this gate → `invocationMode: via-pre-pr-push-step-5`; read `isFirstReviewExposurePush`, `remoteExposureExists`, `baseRef` from that record. Continue to Step 2.

- **Direct invocation path** (no `pre-pr-push.md` state present) → `invocationMode: direct-invocation-dry-run-only`. This path is for diagnostic / dry-run / education-mode use ONLY; it CANNOT emit a `READY-*` status and CANNOT unblock G6 PR-creation tools.

  Run a forge-specific open-PR check (so the dry-run is informative):
  - GitHub: `gh pr list --head <branch> --state open`
  - GitLab: `glab mr list --source-branch <branch> --state opened`
  - Gitea / Forgejo / Codeberg: `tea pr list --state open --head <branch>`
  - Azure DevOps: `az repos pr list --source-branch <branch> --status active`
  - Bitbucket / SourceHut / Radicle / other forges: equivalent command, or `ask_user` for forge-specific guidance.

  Then `ask_user` with three options:
  1. **STOP and run `pre-pr-push.md` first** (recommended) — this is the normal entry point. §2D fires from there via Step 5. This option exits §2D immediately so `pre-pr-push.md` can run its prerequisite gates (§4.2 push-credential verification, per-commit audit, branch-wide sweep, branch-wide LPA) before §2D is re-invoked.
  2. **Continue as DRY-RUN** — §2D runs the panel for informational purposes; emits a `PRE-PR REVIEW COVERAGE` block with `pr-creation-status: DRY-RUN-INFO-ONLY`. **This status does NOT unblock G6 tools.** The agent cannot proceed to `gh pr create` / `gh pr ready` / equivalents on this invocation. To actually create a PR, the agent must subsequently run `pre-pr-push.md` (which will re-fire §2D from Step 5).
  3. **Abort §2D** — exit without running the panel; this is the correct choice if the invocation was unintended.

  **`direct-invocation-dry-run-only` MUST NOT emit `READY-pending-user-approval` or `READY-re-emitted-after-user-approval`.** If the orchestrator attempts to emit one of those statuses while `invocationMode == direct-invocation-dry-run-only`, that is a workflow violation per §1B. This rule prevents the bypass where direct invocation circumvents `pre-pr-push.md`'s OTHER required gates.

  **Collect `baseRef` explicitly in this mode** (since there's no `pre-pr-push.md` state to read from): `ask_user` for `baseRef` (default `origin/main`, or the parent branch for stacked PRs) BEFORE proceeding to Step 2. Resolve the SHA via `git rev-parse <baseRef>` and record as `panelBaseSha`. If the SHA cannot be resolved, escalate via `ask_user` immediately.

Record `invocationMode` and `baseRef` in the phase-state record.

### Step 2. Re-run-trigger detection (ancestry-based)

When a prior §2D run exists on this branch, detect what changed since:

```powershell
$priorHeadSha = <prior-run panelHeadSha, or "none">
$baseRef = <prior-run panelBaseRef, or intake baseRef>
$priorBase = <prior-run panelBaseSha, or "none">
$priorCommitCount = <prior-run panelCommitCount, or 0>
$currentBase = git rev-parse $baseRef
$currentHead = git rev-parse HEAD
$currentCommitCount = (git rev-list --count "$currentBase..HEAD")

$triggers = @()
if ($priorHeadSha -eq "none") {
    $triggers += "first-run"
} else {
    git merge-base --is-ancestor $priorHeadSha HEAD 2>$null
    $isPriorAncestor = ($LASTEXITCODE -eq 0)
    if (-not $isPriorAncestor)                          { $triggers += "history-rewrite" }
    if ($priorBase -ne "none" -and $priorBase -ne $currentBase) { $triggers += "base-shift" }
    if ($priorCommitCount -gt 0 -and $currentCommitCount -lt $priorCommitCount) { $triggers += "commit-squash" }
    if ($priorHeadSha -ne $currentHead -and $isPriorAncestor)   { $triggers += "net-new-commits" }
}
```

`history-rewrite` covers force-push, `git commit --amend`, and interactive rebase that rewrites. `re-run-triggers` is a LIST (triggers can co-occur).

**Prior-commit-panel-dispositions carry-forward**: dispositions from a previous run carry forward IF AND ONLY IF `re-run-triggers == ["net-new-commits"]`. Any rewrite / squash / base shift invalidates prior dispositions.

Record `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `reRunTriggers` in the phase-state record.

### Step 2.5. Pattern preflight against catalog

Runs BEFORE the panel launch (Step 3) so the `PATTERN PREFLIGHT` block is in the reviewers' initial context. The preflight is a deterministic sweep against the empirical pattern catalog at `multi-model-review/pr-review-pattern-catalog.md` + FP registry at `multi-model-review/known-false-positives.md`. Goal: surface sister sites of known recurring patterns BEFORE the panel sees the diff, so the panel verifies the orchestrator's preflight (lower cost) rather than re-discovers each pattern from scratch (higher cost).

**Procedure**:

1. **Resolve catalog revisions**. Run (from any clone of `CopilotInstructions`):
   ```
   git -C <copilotinstructions-clone> log -1 --format=%H -- .github/playbooks/multi-model-review/pr-review-pattern-catalog.md
   git -C <copilotinstructions-clone> log -1 --format=%H -- .github/playbooks/multi-model-review/known-false-positives.md
   ```
   - Record the two SHAs as `catalog_revision` and `fp_registry_revision`.
   - **Interpretation of empty stdout**: if `git log -1` returns empty stdout for a file path, it means the file does not exist in any commit reachable from HEAD. This is the **`catalog: not-yet-built`** signal — record `catalog_revision: not-yet-built` and proceed to the skip-condition path (do NOT STOP). The clone-path failure handling at the bottom of this section is for `fatal:` exits (clone doesn't exist, ref unknown), NOT for empty output.
   - **Authoritative existence check**: in tandem with the `git log -1`, run `git -C <copilotinstructions-clone> ls-tree HEAD -- .github/playbooks/multi-model-review/pr-review-pattern-catalog.md` (exit code 0 + empty stdout = file absent in HEAD; non-empty line = file present). Both outputs are quoted in the skip block per the not-yet-built skip path.

2. **Per high-frequency pattern in the catalog** (the patterns in the "Patterns (high-frequency battery)" section that have an executable `discovery_query` field): run the entry's `discovery_query`. The catalog entry specifies the scope-mode (`diff-scoped` over `<merge-base>..HEAD` files, `tree-scoped` over the consuming project's source tree, or `hybrid` requiring BOTH a tree-scoped baseline AND a diff-scoped enforcement run).
   - **Diff-scoped (Linux/macOS, NUL-safe)**: `git diff --name-only -z <merge-base>..HEAD -- '<glob>' | xargs -0 -r rg --line-number --no-heading --color never <pattern>`. The `-z` + `-0` pair handles paths containing spaces, tabs, or newlines without splitting. PowerShell: `git diff --name-only <merge-base>..HEAD -- '<glob>' | ForEach-Object { rg --line-number --no-heading --color never <pattern> -- $_ }` (PowerShell's `ForEach-Object` iterates by line and passes each path as a single argument; `--` terminates rg's option parsing so paths starting with `-` are handled correctly). Both produce the same hit set.
   - **Tree-scoped**: `rg --line-number --no-heading --color never <pattern> <source-tree>`. Identical on both shells.
   - **Hybrid**: emit ONE `preflight_findings` entry with `scope_mode: hybrid` that contains both `tree_query` and `diff_query` keys and a combined `sites:` list. Each site MUST tag which query surfaced it: `surfaced_via: tree | diff`. The tree run answers "what's in the project's baseline?"; the diff run answers "what's new in this PR?".
   - **Review-only patterns** (entries with `discovery_query: <review-pass-only>` — currently `doc-impl-mismatch`): no automated discovery. The catalog entry's `§2D preflight prompt` becomes a required reviewer instruction surfaced via Step 3's panel prompt. The preflight block records these patterns with `hits: review-required`, `sites: []`. The panel is the verification layer (this aligns with the catalog's own description of these as "discipline patterns, not regex patterns").
   - All `rg` invocations include `--line-number --no-heading --color never` to ensure stable, deterministic output across machines.

3. **Per match**, classify with the Delta K enum (consistent with §2B `delta-g-sweeps:` row):
   - `applied` — the pattern's canonical fix is in place in the current change. Requires `evidence: <file:line-range>`.
   - `already-applies` — the site was already correct at merge-base. Requires `evidence: <file:line-range>`.
   - `not-applicable` — the site is exempt. Requires `rationale: <one line>` citing (a) a code property verifiable from the cited file OR (b) a project-defined invariant. **Pure runtime-behavior assertions without code evidence are NOT valid rationale** (matches Delta K v4 rubric in `review-workflow-gates.md` §2B `delta-g-sweeps:` row).

4. **FP cross-check**: for each Copilot finding (if any) that the agent is processing alongside this preflight, check against `known-false-positives.md`. If the finding matches an FP entry by **technical claim** (per `known-false-positives.md` Matching policy — semantic match, not phrasing match): dismiss with the canonical template, record in `pr_review_findings.classification = 'recurring-false-positive'`, and DO NOT include in the panel's reviewable findings. **If the consuming project's `<project-root>/.github/data/pr-review-findings.csv` (or `.sqlite`) does not exist, follow the bootstrap procedure in `pr-review-findings-schema.md` §Initial seeding to create it before recording the row.**

5. **Emit a `PATTERN PREFLIGHT` block** in the same response that launches the Step 3 panel (the block precedes the panel-launch tool calls in that response). Format (strict; required keys must appear in the order shown; multi-line strings use YAML literal block scalar `|` with 4-space indent):

```
PATTERN PREFLIGHT
  catalog_revision: <SHA from Step 2.5.1>
  fp_registry_revision: <SHA from Step 2.5.1>
  patterns_checked: <count>
  preflight_findings:
    - pattern: <slug from catalog>
      scope_mode: diff-scoped | tree-scoped | hybrid | review-pass-only
      discovery_query: <exact command run, including paths> | "<review-pass-only — see §2D preflight prompt>"
      hits: <count> | review-required
      sites:
        - path: <project-relative>
          status: applied | already-applies | not-applicable
          surfaced_via: tree | diff       # only for scope_mode: hybrid
          evidence: <file:line-range>     # for applied + already-applies
          rationale: <one line>            # for not-applicable
  fps_recognized:
    - fp: FP-N (slug)
      sites: [<paths>]
```

**Failure handling for the commands above**:
- Step 2.5.1 (`git -C <copilotinstructions-clone> log -1`): empty stdout = catalog file not present in HEAD = use the `catalog: not-yet-built` skip path below (NOT a failure). A `fatal:` exit (e.g., clone path doesn't exist, repo not initialized) ⇒ retry once with `git fetch origin main` in the clone; if still failing, `ask_user` for the clone path and STOP.
- Step 2.5.2 (`git diff`, `rg`): non-zero exit from `git diff` (e.g., bad ref / unknown merge-base) ⇒ `ask_user`. `rg` returns exit code 1 on no-match — this is NOT an error; treat as `hits: 0`. Any other non-zero `rg` exit ⇒ `ask_user`.
- Output normalization: capture `rg` output verbatim; sort sites by `path` then `line_number` ascending for deterministic ordering across runs.

**Enforcement** (via G6, NOT via §1B's all-tool gate):

- The block becomes a prerequisite for the **G6 forbidden tools** (the PR-creation subset: `gh pr create`, `gh api .../pulls`). G6 already gates these on `PRE-PR REVIEW COVERAGE` emission per G3. This step adds: G6 ALSO requires `PATTERN PREFLIGHT` emission in the same turn as the `PRE-PR REVIEW COVERAGE` block. Both blocks together gate PR creation.
- This step does NOT extend §1B (which gates ALL `create` / `edit` tools on artifact-binding certification per §1A — that gate is independent and continues to apply at implementation time, not at PR creation).

**Skip conditions**:
- **`catalog: not-yet-built`** — the catalog file does not exist in CopilotInstructions HEAD. Trigger condition: empty stdout from BOTH `git -C <copilotinstructions-clone> log -1 --format=%H -- .github/playbooks/multi-model-review/pr-review-pattern-catalog.md` AND `git -C <copilotinstructions-clone> ls-tree HEAD -- .github/playbooks/multi-model-review/pr-review-pattern-catalog.md`. To use this skip: emit `PATTERN PREFLIGHT` with status `catalog: not-yet-built` AND include a quoted block containing (a) the exact `git log -1` command run including the resolved clone path, its empty stdout, and its exit code (0); (b) the exact `git ls-tree HEAD` command run, its empty stdout, and its exit code (0). Both commands MUST run against the CopilotInstructions clone (per Step 2.5.1), NOT the consuming project's repo. Honest-agent verification: panel reviewers see both quotes and can independently rerun the commands. Cryptographic proof of non-fabrication is NOT provided by this mechanism; the defense is auditability, not unforgeability.
- **`catalog: empty-battery`** — the catalog file exists but its "Patterns (high-frequency battery)" section contains no patterns. Trigger condition: `git -C <copilotinstructions-clone> log -1` returns a non-empty SHA AND the catalog file at that SHA contains zero `^### \d+\.` numbered entries between the literal headings `## Patterns (high-frequency battery)` and the next `^## ` heading. To use this skip: emit `PATTERN PREFLIGHT` with status `catalog: empty-battery` AND quote: (a) the catalog_revision SHA; (b) the output of `git -C <copilotinstructions-clone> show <SHA>:.github/playbooks/multi-model-review/pr-review-pattern-catalog.md | awk '/^## Patterns \\(high-frequency battery\\)/,/^## [^P]/' | grep -c '^### '` proving the count is `0`.
- **`catalog: skipped-bootstrap`** — the PR is **G7 bootstrap-exempt** (all 3 G7 conditions met, including `BOOTSTRAP-EXEMPTION:` body token). Emit `PATTERN PREFLIGHT` with status `catalog: skipped-bootstrap` and quote the G7 token from the PR body / panel phase-state `bootstrapTokenStatus: present-in-body`.
- **`catalog: skipped-no-production-diff`** — the diff contains no production code (touches only `.github/**`, `docs/**`, `*.md`, `*.txt`, fixture data, or test snapshots — no `.cs`/`.ts`/`.razor`/equivalent production-language files). Emit `PATTERN PREFLIGHT` with status `catalog: skipped-no-production-diff` and quote the `git diff --name-only <merge-base>..HEAD` output as evidence.

**Catalog drift detection**: if `catalog_revision` differs from the prior PR's recorded value (read from `catalogRevision` in the panel phase-state), the orchestrator MUST run the FULL preflight even when `re-run-triggers` would otherwise skip Step 2's re-fetch. Step 9's re-fetch (same procedure as Step 2.5.1) catches catalog updates between initial panel and PR-creation turn and restarts at Step 2.5 when SHAs drift.

**Stickiness recommendation (advisory; not gate-enforced)**: catalog maintainers SHOULD avoid committing more than one catalog revision per 24-hour window to limit preflight churn. This is advisory because no persistent counter / timestamp store is defined; the procedure does not block on it. Adding tracked state for the throttle is a future enhancement (see `pr-review-pattern-catalog.md` maintenance section).

### Step 3. Launch the panel in parallel

Per `multi-model-review/procedure.md` parallel-launch protocol. All reviewers launched in the same response (background mode), with the shared `pr-creation-mirror-prompt.md` template populated. The reviewer prompts include a reference to the `PATTERN PREFLIGHT` block emitted in Step 2.5 — reviewers' job becomes: (a) verify each `applied` / `already-applies` site is genuinely correct at HEAD, (b) verify each `not-applicable` rationale is mechanically grounded, (c) probe for patterns NOT in the catalog (long-tail discovery; these are candidates for new catalog entries).

**Slate-floor checkpoint #1**: verify floor holds BEFORE launch. If a substitution broke floor, escalate via `ask_user`.

### Step 4. Wait for reviewers; handle drops

Per `multi-model-review.md` hard gates (notification-driven; no polling). Per-reviewer scheduled timeout: 10 minutes. On timeout: `write_agent` "status check"; +2 min grace; treat as dropped if still no response.

Cumulative drop events:

- 0 → proceed.
- 1 → launch replacement per substitution rule (same family, highest-capability successor).
- 2 → escalate via `ask_user`: wait additional 10 min / proceed degraded if slate-floor still holds / abort.
- ≥3 → hard escalate; cannot proceed without user explicitly authorizing degraded mode AND floor satisfied.

**Slate-floor checkpoint #2-N**: re-verify floor after every drop and every replacement. Floor break → escalate immediately regardless of drop-count row.

### Step 5. Synthesize + apply convergence + C2 routing

Per `multi-model-review/procedure.md` synthesis (dedup by theme, severity ranking, agreement count). Apply chosen convergence model. C2-route every finding per G5.

`routed-deferred-with-tracker-and-ask_user` requires G4 conditions in this turn. If not met, the finding is `fixed` or `dismissed-source-grounded` only.

### Step 6. Apply fixes for must-fix findings (with branch-level iteration tracking)

Every reviewer-flagged `blocking` finding resolved via G2's three paths.

For `fixed` findings: apply change in this turn, re-stage, re-run build + tests, emit `POST-CODE-CHANGE LEDGER` per `review-workflow-gates.md` §2B, then re-run the panel from Step 2.

**Before re-launching the panel from Step 2 after a `fixed` finding, increment `fixIterationCount` in the §2D phase-state record.** If `fixIterationCount > fixIterationCountCap` (default `3`), STOP and escalate via `ask_user`. The escalation prompt MUST classify the iteration history into one of two shapes so the user can make an informed call:

- **cap-with-regressions** — at least one prior round's fix introduced a NEW finding that itself required a fix (the same code being re-iterated, possibly with the same pattern class). This indicates real instability of the fix process; the §2D cap is doing its job. Default recommendation: pause, split branch, or route remaining via G4.
- **cap-with-new-clean-categories** — every fix-round verified correct in the next round, and each subsequent round caught a genuinely NEW pattern category (different anti-pattern shape, different file area, different framework concern). This indicates the gate is productively prompt-mining — Copilot or the panel keeps surfacing new pattern families because the diff is large or unfamiliar, NOT because the fixes are unstable. Default recommendation: authorize one more iteration with explicit new cap; queue the newly-discovered pattern categories as instruction-file deltas for the next CopilotInstructions PR.

Then offer the user the four standard options:

1. Authorize an override of `fixIterationCountCap` to a higher value (record the new cap under `fix-iteration-count-cap` in the next LEDGER emission). Recommended for cap-with-new-clean-categories.
2. Route remaining must-fix findings via G4 `routed-deferred-with-tracker-and-ask_user` (one tracker + same-turn `ask_user` per finding). Recommended for cap-with-regressions.
3. Split the branch / reduce scope. Recommended for cap-with-regressions on a large diff.
4. Abort the gate. Always available as escape hatch.

Do NOT re-enter Step 2 until the user has authorized one of these paths. Reset `fixIterationCount` to `0` only on `re-run-triggers: ["first-run"]` (fresh branch) or on successful gate completion (`READY-re-emitted-after-user-approval` final emission).

The round-level max-loop (5 per `multi-model-review/procedure.md`) covers within-panel cycling — that's a different counter from `fixIterationCount`, which tracks fix-then-re-panel CYCLES across panel invocations on the same branch. Full automated escalation handling is deferred to `pre-pr-creation-review/implementation-roadmap.md` priority 3; the count-tracking field + the prose escalation rule are implemented in v4 so the gate's bounded-iteration guarantee has backing state.

### Step 7. Emit `PRE-PR REVIEW COVERAGE` block (initial)

Mandatory before invoking the AGENTS user-approval flow. Format:

```
PRE-PR REVIEW COVERAGE
  emission-phase: initial-pending-user-approval
  invocation-mode: <via-pre-pr-push-step-5 | direct-invocation-dry-run-only>
  re-run-triggers: <[trigger, ...]>
  panel-base-ref: <baseRef>
  panel-base-sha: <40-char SHA>
  panel-head-sha: <40-char SHA>
  panel-commit-count: <N>
  diff-scope: <baseSha>..<headSha> (<N> files, +<X>/-<Y> lines)
  slate:
    - slot 1: <model> <family> <role> [substituted from <requested>: <reason>]
    - ...
  slate-substitutions: <[] or list>
  slate-waive: <"no waive" or user-quote>
  convergence-model: <unanimous | threshold-N% | confidence-weighted-N%>
  convergence-waive: <"no waive" or user-quote>
  rounds: <K>
  fix-iteration-count: <N — incremented per Step 6 fix-then-re-run cycle; 0 for first run>
  fix-iteration-count-cap: <3 default, or user-authorized override>
  dropped-reviewers: <[] or list>
  replacement-reviewers: <[] or list>
  prior-commit-panel-dispositions: <"none — <reason>" or compacted list>
  findings: <total raw>, dedupe'd to <M themes>
  resolution (every finding has a status):
    - [<category 1-11>] <severity> [<reviewer>]: <finding>: <status>: <citation>
    - ...
  must-fix-blocking-findings-resolved: <K of K>
  routed-deferred-with-tracker:
    - <finding> → <tracker URL> (ask_user: <call ref>)
    - ... (default: [])
  bootstrap-token-status: <not-applicable | present-in-body | removed-revokes-exemption>
  catalog-revision: <40-char SHA | not-yet-built>
  fp-registry-revision: <40-char SHA | not-yet-built>
  pattern-preflight-skip-status: <ran | catalog: not-yet-built | catalog: empty-battery | catalog: skipped-bootstrap | catalog: skipped-no-production-diff>
  pr-creation-status: <READY-pending-user-approval | READY-re-emitted-after-user-approval | DRY-RUN-INFO-ONLY | BLOCKED — <reason>>
  subagent_ask_user_calls=0 (per AGENTS.md)
```

The `catalog-revision`, `fp-registry-revision`, and `pattern-preflight-skip-status` fields ARE the state-echo for G6's PATTERN PREFLIGHT check — they MUST be populated from the §2D phase-state on every emission. Use `not-yet-built` for the SHA fields only when `pattern-preflight-skip-status: catalog: not-yet-built`; for any other skip status (or `ran`), the SHA fields hold the real catalog/registry SHAs from Step 2.5.1.

### Step 8. AGENTS user-approval

Per AGENTS.md `gh pr create` section: present PR title + body + base via `ask_user`. User approves / edits / rejects.

For non-GitHub forges, mirror the same user-approval flow before invoking the equivalent G6 tool.

#### Step 8a. PR-description coherence check (mandatory before user-approval `ask_user`)

Before presenting the PR title + body for user approval, re-read the proposed description against the diff. Verify that every named type, interface, file path, public method, configuration knob, or behavioural claim in the description actually appears in the diff with the role the description attributes to it.

Common failure modes (Bot reviewers consistently catch these on PR-open):

- **Renamed but not updated**: description references the old symbol name after a rename.
- **Capability misattributed**: description claims interface `IFoo` does X, but `IFoo` actually exposes Y and the X capability lives on `IBar` (existing or new).
- **Moved but stale path**: description references a file path that was moved during the diff.
- **Behavioural overclaim**: description describes a feature the diff scaffolds but doesn't actually implement (e.g., "supports cancellation" when no `CancellationToken` is threaded).
- **SHAs that won't survive rebase**: description cites specific commit SHAs of upstream merges that will not exist after the base branch advances.

When any incoherence is found, FIX the description (or, if the description is correct and the code is wrong, route back through the panel as a finding). Treat this as a blocking pre-PR-creation gate — coherence defects always become reviewer comments, and the fix is cheap if caught here vs. after PR-open.

Record `prDescriptionCoherenceCheck` in the §2D phase-state record: `ran-clean` / `ran-fixed-description-before-create` / `ran-routed-back-to-panel-as-finding`.

### Step 9. Re-emit blocks after approval

In the PR-creation tool-call turn (after Step 8 `ask_user` returns):

- Re-run Step 2's same-state checks. If any fails (new commits, force-push, base shift since initial emission), restart at Step 2 (re-running Steps 2 → 3 → ... → 8 in order; the panel must re-run because the diff has changed).
- Re-fetch `catalog_revision` + `fp_registry_revision` per Step 2.5.1. If either differs from the recorded value, restart at Step 2.5 (re-running Steps 2.5 → 3 → ... → 8 in order; the panel must re-run because reviewers were operating on the stale catalog).
- Re-emit `PRE-PR REVIEW COVERAGE` block with `emission-phase: ready-re-emitted-after-user-approval`, `pr-creation-status: READY-re-emitted-after-user-approval`, and the catalog/registry fields populated from current phase-state.
- Re-emit `PATTERN PREFLIGHT` block in the same turn. If catalog/registry SHAs are unchanged AND `panelHeadSha` is unchanged from Step 2.5's run, the carry-forward MUST be a literal copy of the Step 2.5 block (no recomputation needed). If anything changed, the Step 2.5 re-run produces the new block (and the panel has already re-run per the restart bullets above). Both blocks (`PRE-PR REVIEW COVERAGE` + `PATTERN PREFLIGHT`) precede the Step 10 tool call in the same response.

### Step 10. Invoke the G6 tool

Only after Step 9's re-emitted `PRE-PR REVIEW COVERAGE` block AND `PATTERN PREFLIGHT` block are both present in the same response, immediately preceding the tool call.

## State to record in canonical session todos

Per `AGENTS.md` *Phase-state tracking convention*:

`invocationMode`, `reRunTriggers`, `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `slateActuallyRun`, `slateSubstitutions`, `slateWaive`, `convergenceModelUsed`, `convergenceWaive`, `panelRounds`, `fixIterationCount`, `fixIterationCountCap`, `panelConvergence`, `droppedReviewers`, `replacementReviewers`, `priorCommitPanelDispositions`, `mustFixFindings`, `mustFixResolved`, `prDescriptionCoherenceCheck`, `bootstrapTokenStatus`, `prCreationStatus`, `catalogRevision`, `fpRegistryRevision`, `patternPreflightSkipStatus`.

Read these back from canonical session todos when emitting `PRE-PR REVIEW COVERAGE`; never infer from memory.

## §2B carve-out forward-reference

When the future `review-workflow-gates.md` §2B edit lands (tightening `post-code-change-panel` from `ran | N/A — reason | user-waived` to `ran | N/A — reason`), preserve the existing N/A carve-out for pure-recommit / rebase with zero behavioral delta vs. previously-panelled artifact (~line 297). Removing `user-waived` is correct; removing the N/A carve-out would be a regression.

## Cross-cutting fit — companion edits required (G7 condition 3)

The introducing PR for §2D MUST include ALL of:

- This playbook (`pre-pr-creation-review.md`).
- `multi-model-review/pr-creation-mirror-prompt.md` — shared 11-category prompt.
- `pre-pr-creation-review/implementation-roadmap.md` — deferred-features document.
- `AGENTS.md` `gh pr create` section — extended to require G3 block emissions before user-approval.
- `AGENTS.md` cross-cutting hard-gate bullets — new bullet referencing §2D.
- `pre-pr-push.md` Step 5 — invokes this playbook for review-targeting pushes. Adds `preCreationReviewStatus` field to the state predicate.
- `review-workflow-gates.md` §2D — LEDGER row + G1-G7 enforcement summary.
- `.github/playbooks/manifest.yaml` — registers `pre-pr-creation-review`.

Missing any of these → §2D is non-operative post-merge → G7 bootstrap exemption invalid.

## Future enhancements (deferred)

See `pre-pr-creation-review/implementation-roadmap.md` for design notes on: capability-tier registry indirection (model-fragility insurance), context-budget circuit breaker (1M-context-cap protection), branch-level fix-iteration cap, compaction format with citation preservation, forge-agnostic state field, automated slate-floor re-check infrastructure, automated same-state re-check infrastructure.

Each ships in a follow-up PR triggered by first real-world failure or explicit prioritization.

## Why this gate exists

LLM-based PR reviewers consistently surface a known set of pattern categories on every PR. Patching the static-pattern catalog reactively after each PR is whack-a-mole — the deterministic patterns get caught faster but the LLM-judgment patterns (doc-impl divergence, comment-promises-behavior-code-doesn't-deliver, hardcoded ARIA, framework-binding stale-render, attach-without-detach, etc.) need an LLM in the loop to catch.

Running our own multi-model panel pre-PR with the same category coverage shifts those findings from "review comment after PR opens" to "blocking finding before PR opens". The work to fix is the same; the visibility cost (reviewer time, PR thread churn, CI cycles, force-push pollution) is dramatically lower.

When a Copilot-bot PR-review finding lands on a PR that PASSED §2D, treat it as evidence the 11-category prompt or the per-commit catalog has a gap. Follow `review-workflow-gates.md` §2 root-cause analysis and propose an addition to the §2.5 catalog or the prompt template in the next `post-pr-review.md` cycle. The §2D gate improves via this feedback loop.
