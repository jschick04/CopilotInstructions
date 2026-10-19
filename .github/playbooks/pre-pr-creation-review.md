# Playbook: Publish gate - pre-PR-creation review
<!-- read-receipt-token: 35dcca1d -->

## Purpose

Mandatory full reviewer-equivalent panel on the range diff and every whole file touched by any commit in `<panelBaseSha>..<panelHeadSha>`, read at `panelHeadSha`, before any PR is created or made review-visible. Mirrors the categories an LLM-based PR reviewer would surface - runs locally pre-push so findings are caught BEFORE reviewers see them. Sister to `post-code-change.md` §3 (per-commit panel, lightweight).

## Hard gates

### G1. Panel must run - not user-waivable

Cannot be skipped via `ask_user` quote. Only exit: convergence with must-fix=0.

### G2. Must-fix=0 - not user-waivable

Every reviewer-flagged `blocking` finding must be resolved via one of three G5 paths:

- `fixed` - applied as a change.
- `dismissed-source-grounded` - refuted by source evidence (file:line, doc URL, RFC, ADR, spec section) addressing the finding's claim. Hand-wave "out of scope" is invalid.
- `routed-deferred-with-tracker-and-ask_user` - see G4.

### G3. `QUALITY GATE` block emitted in the PR-creation turn - not user-waivable

The block (canonical schema in `../pr-quality-gate/quality-gate-block.md`; emission procedure in Step 7) MUST appear in the same chat turn as the G6 PR-creation tool call.

Because the AGENTS `gh pr create` flow requires an intervening `ask_user` for title/body approval, the block is emitted twice:

1. **Initial** (turn N): at end of Step 7 with `pr_creation_status: READY-pending-user-approval`.
2. **Re-emitted** (turn N+1): in the PR-creation tool-call turn, after user-approval `ask_user` returns, with same-state re-check the G6 pre-call checks in `quality-gate-block.md`: local HEAD equals `panelHeadSha`, advertised base tip still matches `base_tip_sha`, and recomputed merge-base equals `panelBaseSha`. Any check fails: restart at Step 2. Status: `READY-re-emitted-after-user-approval`.

Absence of block in PR-creation turn -> all G6 tools forbidden. Block in earlier turn does NOT satisfy.

**Companion mechanical backstop.** After the block reaches READY, write the `publish_gate_ready` receipt for the pushed tip (schema: `../pr-quality-gate/publish-gate-receipt.md`); the pre-push hook `check-publish-gate-prepush.ps1` independently blocks the push without a fresh receipt bound to this remote/branch/commit (honest ceiling: it enforces receipt PRESENCE at push, not that the panel ran - same modeled ceiling as this block).

### G4. `routed-deferred-with-tracker-and-ask_user` requires both:

1. Actual external tracker issue (GitHub issue, ADO work item, Linear ticket) created same turn with citable URL - NOT a session-todo, NOT a `TODO`/`FIXME` code comment, NOT "tracked internally".
2. Explicit `ask_user` approval in same turn naming the URL and confirming deferral.

### G5. C2 disposition enum

Per finding: `fixed | dismissed-source-grounded | routed-deferred-with-tracker-and-ask_user | routed-now-via-ask_user`. Every finding has a status; no orphans.

### G6. Forbidden-tool enumeration (mirrors §1B)

Until BOTH of these are present in the current turn, the agent MUST NOT call any tool below:

1. The G3 block from Step 9 (the **re-emitted** `QUALITY GATE` block) with `pr_creation_status: READY-re-emitted-after-user-approval`. The initial-emission status (`READY-pending-user-approval`) is NOT sufficient - user-approval + same-state re-check have not happened. `DRY-RUN-INFO-ONLY` is NEVER sufficient.
2. The block's mechanical region (computed in Step 2.5 by `gate-runner` full-mode; re-emitted in Step 9) against current `panelHeadSha` + current `catalogRevision`. MAY use only `catalog: empty-battery` or the narrowly-scoped `catalog: skipped-no-production-diff` in `pattern_preflight_skip_status`; the mechanical region must be PRESENT regardless. Additionally, the re-emitted `QUALITY GATE` block's `catalog_revision` / `pattern_preflight_skip_status` fields MUST be populated; absence or `<unset>` fails the gate.

Forbidden tools:

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
- Equivalents on any forge not enumerated (Bitbucket, Gitea, Forgejo, Codeberg, Radicle, etc.)

Pattern: absence of block IS the enforcement. New pathways extend by intent, not literal name.

### G7. Bootstrap exemption - only the new gate's self-application

`BOOTSTRAP-EXEMPTION: <name>` may skip only the new gate P's self-application on the PR that introduces P. It never skips the whole-branch panel, §2D publish gate, QUALITY GATE block, or publish-gate receipt. P cannot be §2D itself.

All conditions are required; any command failure means NOT exempt:

1. Verify `base_tip_sha` equals the validated SHA field of exactly one `git ls-remote <base_url> refs/heads/<base_branch>` record and `git cat-file -e <base_tip_sha>^{commit}` succeeds. If missing locally, fetch `<base_remote> <base_branch>`, verify the fetched tip still matches, retry once, then stop and ask the user if unresolved.
2. Let P be `.github/playbooks/<name>.md`. Parse the full `git diff -M -C --name-status <panelBaseSha> <panelHeadSha>` using each record's leading status letter (`R100` -> `R`, `C075` -> `C`). Any status outside `A`, `M`, `D`, `R`, `C`, or `T` makes the exemption invalid. P must have exactly one diff record, with leading status `A`; no `R` or `C` record may have P as destination, and `git cat-file -e <base_tip_sha>:P` must fail.
3. From that full diff, enumerate every OTHER gate-scope change (`AGENTS.md`, `.github/playbooks/**`, `.github/instructions/**`, `.github/copilot-instructions.md`, `.github/pr-quality-gate/**`, every `$GuardedPathPatterns` path, and every path matched by `Test-RequiresFullPanel` / `panel-ledger-helpers.psm1` panel-requires). A record is in scope if either path is in scope; show its status letter and both paths for renames/copies. Ask the user to confirm each companion change for making P operative post-merge. Any unconfirmed entry makes the exemption invalid.
4. Both the Step 8 approved body and the live PR body must contain literal `BOOTSTRAP-EXEMPTION: <name>`. P's companion edits must make it operative after merge. Removing the token revokes only P's exemption; subsequent pushes run P's own check. Existing-gate edits are fully panel-reviewed and do not expand the exemption beyond P's self-application.

G7 never exempts from §2D or any other existing gate; it skips only P's self-application. The §2D panel, QUALITY GATE block, and publish-gate receipt always run.

## Waive matrix

| Item | Waivable? | Conditions / floor |
| --- | --- | --- |
| G1 (panel must run) | NO | - |
| G2 (must-fix=0) | NO | Individual findings may use G4; gate-level must-fix=0 stands. |
| G3 (block in PR-creation turn) | NO | - |
| G5 (disposition per finding) | NO | - |
| G6 (forbidden tools) | NO | - |
| G7 conditions | NO | All G7 conditions hold, or the exemption does not apply. |
| Convergence model (`unanimous`) | NO | Every panel converges unanimously. |
| Slate composition | NO | Full floor is at least 4 distinct heavy models: Claude, GPT, Gemini, and one additional GPT or Grok; at least one rubber-duck and two code-review roles. Re-check after every replacement. |
| Individual finding via G4 | YES (with G4) | External tracker URL + same-turn `ask_user`. |

Items not in the matrix are NOT waivable.

## Reviewer slate (default heavy)

Tier -> current model via `multi-model-review/current-model-registry.md`.

| Slot | Tier id | Family | Role |
| --- | --- | --- | --- |
| 1 | `heavy-claude-standard` | Claude | `rubber-duck` |
| 2 | `heavy-gpt-premium` | GPT | `code-review` |
| 3 | `heavy-gemini-premium` | Gemini | `code-review` |
| 4 | `heavy-grok-premium` | Grok | `code-review` |
| 5 | `heavy-gpt-codex` (optional) | GPT | `code-review` |

**Substitution**: only per `panel-policy.md` §Checker-enforced ledger rows (`model-retired` / `model-superseded` / `tier-added` / `family-unavailable` Grok -> codex; heavy allowlist). Record `slate_substitutions: [{slot, requested, substituted, reason}]`. Floor re-checked after every substitution.

## Reviewer prompt

Use `multi-model-review/pr-creation-mirror-prompt.md` (shared 11-category Copilot-mirror template). Consumer-specific substitutions: `<baseSha>` = `panelBaseSha`, `<headSha>` = `panelHeadSha`, `<repo-path>`, round context, prior-commit panel dispositions, Intake Q4 context notes.

## Procedure

### Step 1. Determine invocation mode

This gate does NOT classify whether push is review-targeting (that is `pre-pr-push.md`'s job).

- **Normal path**: `pre-pr-push.md` state present AND Step 5 hook fires -> `invocationMode: via-pre-pr-push-step-5`. Read `isFirstReviewExposurePush`, `remoteExposureExists`, and the binding fields (`phase-state-convention.md`) from that record. Continue to Step 2.

- **Direct invocation path** (no `pre-pr-push.md` state) -> `invocationMode: direct-invocation-dry-run-only`. For diagnostic/dry-run/education use ONLY; CANNOT emit `READY-*` status, CANNOT unblock G6.

  Forge-specific open-PR check (informational):
  - GitHub: `gh pr list --head <branch> --state open`
  - GitLab: `glab mr list --source-branch <branch> --state opened`
  - Gitea/Forgejo/Codeberg: `tea pr list --state open --head <branch>`
  - Azure DevOps: `az repos pr list --source-branch <branch> --status active`
  - Other forges: equivalent command or `ask_user` for guidance.

  Then `ask_user` with options:
  1. **STOP and run `pre-pr-push.md` first** (recommended) - normal entry point; exits the publish gate immediately.
  2. **Continue as DRY-RUN** - emits `pr_creation_status: DRY-RUN-INFO-ONLY`; does NOT unblock G6.
  3. **Abort the gate** - exit without panel.

  Attempting `READY-pending-user-approval` or `READY-re-emitted-after-user-approval` while `invocationMode == direct-invocation-dry-run-only` is a §1B violation.

  **Collect the approved base binding** (no pre-pr-push state): ask_user for `base_remote`, `base_branch`, `base_url`, and the head (push) remote `head_remote` (derive `head_url` = `git remote get-url --push <head_remote>`, `head_identity`, `head_owner`, `head_nwo`); never default to a local `origin/*` ref. Resolve and validate exactly one `git ls-remote <base_url> refs/heads/<base_branch>` record, extract its full SHA, fetch/verify the commit object, then compute `panelBaseSha = git merge-base <base_tip_sha> <panelHeadSha>` using the SHA only (Step 2 algorithm).

Record `invocationMode` and every approved base/head binding field in phase-state.

### Step 2. Re-run-trigger detection (ancestry-based)

When a prior publish-gate run exists, detect what changed:

```powershell
$priorHeadSha = <prior-run panelHeadSha, or "none">
$priorBase = <prior-run panelBaseSha, or "none">
$priorCommitCount = <prior-run panelCommitCount, or 0>
$baseUrl = <recorded base_url>
$baseBranch = <recorded base_branch>
$baseRef = "refs/heads/$baseBranch"
$tipRecords = @(git ls-remote $baseUrl $baseRef)
if ($LASTEXITCODE -ne 0 -or $tipRecords.Count -ne 1) { throw 'base branch must resolve to exactly one remote record' }
$tipMatch = [regex]::Match($tipRecords[0], ('^([0-9a-f]{40}|[0-9a-f]{64})\t' + [regex]::Escape($baseRef) + '$'))
if (-not $tipMatch.Success) { throw 'invalid base branch SHA/ref record' }
$baseTipSha = $tipMatch.Groups[1].Value
git cat-file -e "$baseTipSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --no-tags $baseUrl $baseRef
    if ($LASTEXITCODE -ne 0) { throw 'cannot fetch approved base branch' }
    $fetchedTip = @(git rev-parse --verify FETCH_HEAD)
    if ($LASTEXITCODE -ne 0 -or $fetchedTip.Count -ne 1 -or $fetchedTip[0] -cne $baseTipSha) { throw 'fetched base tip changed' }
}
$verifiedTip = @(git rev-parse --verify "$baseTipSha^{commit}")
if ($LASTEXITCODE -ne 0 -or $verifiedTip.Count -ne 1 -or $verifiedTip[0] -cne $baseTipSha) { throw 'base commit object unavailable or mismatched' }
$headRecords = @(git rev-parse --verify 'HEAD^{commit}')
if ($LASTEXITCODE -ne 0 -or $headRecords.Count -ne 1 -or $headRecords[0] -cnotmatch '^([0-9a-f]{40}|[0-9a-f]{64})$') { throw 'cannot capture full panelHeadSha' }
$currentHead = $headRecords[0]
$currentBase = git merge-base $baseTipSha $currentHead
if ($LASTEXITCODE -ne 0) { throw 'cannot determine approved base merge-base' }
$currentCommitCount = (git rev-list --count "$currentBase..$currentHead")

$triggers = @()
if ($priorHeadSha -eq "none") {
    $triggers += "first-run"
} else {
    git merge-base --is-ancestor $priorHeadSha $currentHead 2>$null
    $isPriorAncestor = ($LASTEXITCODE -eq 0)
    if (-not $isPriorAncestor)                          { $triggers += "history-rewrite" }
    if ($priorBase -ne "none" -and $priorBase -ne $currentBase) { $triggers += "base-shift" }
    if ($priorCommitCount -gt 0 -and $currentCommitCount -lt $priorCommitCount) { $triggers += "commit-squash" }
    if ($priorHeadSha -ne $currentHead -and $isPriorAncestor)   { $triggers += "net-new-commits" }
}
```

`re_run_triggers` is a LIST (can co-occur). `history-rewrite` covers force-push, amend, interactive rebase.

**Whole-branch panel coverage (default) + carry-forward exception**: the DEFAULT on every pre-PR op (every review-targeting transition routed through `pre-pr-push.md` - PR creation plus every review-response / update push) is a FULL re-read of the whole-branch diff `panelBaseSha..panelHeadSha` by the panel - no prior dispositions carried. Carry-forward of prior-commit-panel-dispositions is an EXPLICIT, user-authorized cost exception, ELIGIBLE only when `re_run_triggers == ["net-new-commits"]` (any rewrite/squash/base-shift forces a full re-read and invalidates priors). When - and only when - the user authorizes carry-forward, it MUST be recorded in the cited `panel_coverage` COVERAGE element with `mode: carry-forward-authorized` + `carry-forward-ref: <ask_user ref>` + `carried: <range>` (Step 7); absent that explicit authorization the panel re-reads the whole branch in full and records `panel_coverage` with `mode: full-whole-branch`. This default-full / audited-exception policy is process-descriptive (it bounds what was re-read this op), not a defect-free guarantee.

**Diff-size partition (RC2 large-batch-dilution)**: a `panelBaseSha..panelHeadSha` diff of more than 30 changed files MAY be partitioned across focused reviewers to scale correctness thoroughness, BUT (a) mirror-sets, sibling/variant sets, cited-doc pairs, and container+member sets MUST land in the SAME partition (a reviewer catches cross-file divergence only when it sees both sides), and (b) at least one reviewer holds the cross-file consistency lens (`mirrored-representation-parity`, `sibling-variant-consistency`, `doc-impl-mismatch` cited-canonical-doc sub-case) over the WHOLE diff, so partitioning never hides cross-file divergence. Per-file depth is owned by each partition reviewer; panel-level coverage stays 100%.

Record the binding fields (`phase-state-convention.md`), `panelBaseSha` (`$currentBase`), `panelHeadSha` (`$currentHead`), `panelCommitCount`, and `reRunTriggers` in phase-state.

### Step 2.5. Mechanical pattern floor via gate-runner

Runs BEFORE Step 3 so the mechanical findings are in reviewers' initial context. `gate-runner.ps1`/`.sh` full-mode runs the rg-battery against `../pr-quality-gate/pattern-catalog.md` and emits the MECHANICAL region of the `QUALITY GATE` block (canonical schema: `../pr-quality-gate/quality-gate-block.md`).

**Procedure**:

1. **Run gate-runner full-mode** (requires `COPILOT_INSTRUCTIONS_CLONE` set to the clone):
   ```
   gate-runner.ps1 -BaseSha <panelBaseSha> -HeadSha <panelHeadSha> -Mode full -ProjectRoot <project-root>
   ```
   It emits the mechanical region: `catalog_revision`, `prefs_revision`, `patterns_run`, and per-pattern `findings` (slug, hits, sites). `gate_status` is BLOCKED iff any pattern has hits>0 (mechanical, rg-only). Record `catalog_revision`. Empty/`fatal:` -> fetch `<base_remote> <base_branch>`, verify the fetched tip equals `ls-remote`, retry once; still failing -> `ask_user` + STOP. Allowed `pattern_preflight_skip_status` values: `catalog: empty-battery` (`patterns_run=0`) or `catalog: skipped-no-production-diff` only when every changed path is markdown/text or under docs, matches no catalog glob and no guarded pattern, and is outside workflows/actions. The battery still runs.

2. **Disposition every mechanical hit** (agent-appended region) with the Delta K enum (consistent with `review-workflow-gates-sweeps.md` §2B `delta-g-sweeps:` row). One disposition per `findings`/`sites` hit; no entry for a non-hit site:
   - `applied` - canonical fix in place. Requires `evidence: <file:line-range>`.
   - `already-applies` - site already correct at merge-base. Requires `evidence: <file:line-range>`.
   - `not-applicable` - site exempt. Requires `rationale: <one line>` citing (a) a code property verifiable from the cited file OR (b) a project-defined invariant. **Pure runtime-behavior assertions without code evidence are NOT valid rationale.**

3. **FP cross-check**: check each finding against the catalog's inline `FP-N` entries by technical claim (semantic match, not phrasing match). Match -> dismiss with the canonical template and record it in `findings_disposition` as `classification: dismissed-source-grounded` (grounded in the cited inline catalog `FP-N` entry), exclude from the panel. (Honest ceiling: gate-runner's FP mechanism is a per-pattern `fp_slug` column, NOT a site-level registry; the retired `known-false-positives.md` site-level FP memory is a disclosed narrowing per `quality-gate-block.md`.)

The mechanical region (`catalog_revision`, `prefs_revision`, `patterns_run`, `findings`/`sites`) plus the agent-appended dispositions (`findings_disposition` per-site, `pattern_preflight_skip_status`) populate the `QUALITY GATE` block emitted in Step 7 (canonical schema + caveman chat form: `../pr-quality-gate/quality-gate-block.md`). Both the mechanical floor and the dispositions gate PR creation via G6 (this does NOT extend §1B).

**Catalog drift detection**: if `catalog_revision` differs from the prior run's recorded value, re-run gate-runner full-mode regardless of `re_run_triggers`. Step 9 re-fetches the catalog SHA and restarts here on drift.

### Step 3. Launch the panel in parallel

Per `multi-model-review/procedure.md` parallel-launch protocol. All reviewers launch in parallel with `pr-creation-mirror-prompt.md`; they inspect the range diff, full touched files at `panelHeadSha`, and relevant base versions. Reviewers independently compute `Get-ReviewedArtifactId.ps1 -Range "<panelBaseSha>..<panelHeadSha>"` (the captured full SHAs, never `HEAD`) at start and end and echo the matching id in their verdict. Prompts include reference to the gate-runner mechanical findings; reviewers verify `applied`/`already-applies` correctness, validate `not-applicable` rationale, and probe for catalog-uncovered patterns.

**Slate-floor checkpoint #1**: verify floor BEFORE launch. Substitution broke floor -> escalate.

### Step 4. Wait for reviewers; handle drops

Per `multi-model-review.md` hard gates (notification-driven; no polling). Per-reviewer timeout: 10 minutes. On timeout: `write_agent` "status check"; +2 min grace; no response -> dropped.

If a reviewer is gone or unresponsive, replace it at the same registry tier (or the named Grok-to-codex fallback); preserve the full floor. The panel continues until unanimous convergence, without a round cap.

**Slate-floor checkpoint #2-N**: re-verify after every drop/replacement. Floor break -> escalate immediately.

### Step 5. Synthesize + apply convergence + C2 routing

Per `multi-model-review/procedure.md` synthesis (dedup by theme, severity, agreement). Apply unanimous convergence. C2-route every finding per G5.

`routed-deferred-with-tracker-and-ask_user` requires G4 conditions in this turn. Not met -> must be `fixed` or `dismissed-source-grounded`.

### Step 6. Apply fixes for must-fix findings

Every `blocking` finding is resolved via G2's three paths. For `fixed`: apply the change, run applicable build and tests, emit the required `POST-CODE-CHANGE LEDGER`, then send each idle reviewer the changed paths and delta for a fresh artifact-bound verdict. Replace only a reviewer that is gone or unresponsive. Continue until all reviewers converge on the same final artifact.

### Step 7. Emit the `QUALITY GATE` block (initial)

Mandatory before AGENTS user-approval. Emit the `QUALITY GATE` block (canonical schema + caveman chat form: `../pr-quality-gate/quality-gate-block.md`) with `emission_phase: initial-pending-user-approval` and `pr_creation_status: READY-pending-user-approval`. The mechanical region comes from gate-runner (Step 2.5); the agent-appended dispositions (slate, panel_coverage, resolution, must_fix_unresolved, routed_deferred_with_tracker, prior_commit_panel_dispositions, pr_text_scan, etc.) come from Steps 2.5-6. The FOUR enumerations (`slate`, `resolution`, `routed_deferred_with_tracker`, `panel_coverage`) STAY enumerated even in the caveman form - the keys are the forcing function. `catalog_revision` + `pattern_preflight_skip_status` MUST be populated from phase-state on every emission.

The `pr_text_scan` field records the result of running `scripts/check-pr-text.ps1` against the PROPOSED PR title + body BEFORE the G6 `gh pr create` tool (the pre-open agent catch); the CI `pull_request` job (`pr-text-check.yml`) is the merge-blocking backstop. `tier1-fail` BLOCKS PR creation until the markers are stripped (re-run + re-emit `clean`); `tier2-warn` is surfaced, not blocking. Honest ceiling: the gate catches MODELED markers only - an unmodeled phrasing escapes, so the field is a floor-raise, not a guarantee.

#### Chat-emission form (caveman)

#### Chat-emission form (caveman)

The caveman (compressed KV) chat form of the `QUALITY GATE` block lives with the canonical schema in `../pr-quality-gate/quality-gate-block.md`; the FOUR enumerations (`slate`, `resolution`, `routed_deferred_with_tracker`, `panel_coverage`) STAY enumerated even there (counts and coverage-mode are fakeable as bare scalars; the keys are the forcing function).

### Step 8. AGENTS user-approval

Per AGENTS.md `gh pr create` section: present PR title + body + base via `ask_user`. User approves/edits/rejects. Non-GitHub forges: mirror same flow before G6 tool.

#### Step 8a. PR-description coherence check (mandatory before user-approval `ask_user`)

Before presenting PR description, re-read it against the diff. Verify every named type, interface, path, method, or behavioural claim actually appears in the diff with the attributed role. Common incoherences: renamed-but-not-updated symbols, capability misattributed to wrong interface, moved-but-stale paths, behavioural overclaims (feature scaffolded but not implemented), SHAs that won't survive rebase.

When incoherence found: fix description (or route back to panel as finding). Treat as blocking pre-PR-creation gate.

Record `prDescriptionCoherenceCheck`: `ran-clean` / `ran-fixed-description-before-create` / `ran-routed-back-to-panel-as-finding`.

### Step 9. Re-emit blocks after approval

In PR-creation tool-call turn (after Step 8 `ask_user` returns):

- Re-run Step 2's same-state checks. Any failure (new commits, force-push, base shift) -> restart at Step 2.
- Re-fetch `catalog_revision` per Step 2.5. Differs -> restart at Step 2.5.
- Re-emit the `QUALITY GATE` block with `emission_phase: ready-re-emitted-after-user-approval`, `pr_creation_status: READY-re-emitted-after-user-approval`, `same_state_recheck: passed`, catalog field from current phase-state. If `catalog_revision` + `panelHeadSha` unchanged, the mechanical region is a literal carry-forward; if changed, the Step 2.5 gate-runner re-run produces a fresh region (panel already re-ran per the restart above).

Both blocks precede the Step 10 tool call in the same response.

### Step 10. Invoke the G6 tool

Only after Step 9's re-emitted `QUALITY GATE` block (with `pr_creation_status: READY-re-emitted-after-user-approval` + `same_state_recheck: passed`) is present in the same response.

## State to record in canonical session todos

Per `phase-state-convention.md`:

`invocationMode`, `reRunTriggers`, `base_remote`, `base_branch`, `base_url`, `base_tip_sha`, `base_identity`, `base_nwo`, `base_project_path`, `head_remote`, `head_url`, `head_identity`, `head_owner`, `head_nwo`, `head_project_path`, `gh_host`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount`, `slateActuallyRun`, `slateSubstitutions`, `panelRounds`, `panelConvergence`, `droppedReviewers`, `replacementReviewers`, `priorCommitPanelDispositions`, `mustFixFindings`, `mustFixResolved`, `prDescriptionCoherenceCheck`, `bootstrapTokenStatus`, `prCreationStatus`, `catalogRevision`, `patternPreflightSkipStatus`, `prTextScan`.

Read from session todos when emitting blocks; never infer from memory.

## §2B carve-out forward-reference

When `review-workflow-gates-sweeps.md` §2B tightens `post-code-change-panel` from `ran | N/A - reason | user-waived` to `ran | N/A - reason`, preserve the existing N/A carve-out for pure-recommit/rebase with zero behavioral delta vs. previously-panelled artifact. Removing `user-waived` is correct; removing the N/A carve-out would be a regression.

## §2D's own introducing companion set (historical)

A new gate P needs the companion edits that make P itself operative post-merge.

## Future enhancements (deferred)

See `pre-pr-creation-review/implementation-roadmap.md` for deferred capability-tier and context-budget work. The current procedure does not cap convergence rounds.

## Why this gate exists

LLM-based PR reviewers consistently surface known pattern categories. Running a multi-model panel pre-PR shifts findings from "comment after PR opens" to "blocking finding before PR opens"; same work, dramatically lower visibility cost. When a finding lands on a PR that PASSED the publish gate, follow `review-workflow-gates-sweeps.md` §2 root-cause analysis and propose a catalog/prompt addition. The gate improves via this feedback loop.
