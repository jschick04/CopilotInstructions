# Playbook: Pre-commit phase
<!-- read-receipt-token: a57a7dff -->

## Purpose

Show the diff to the user, get explicit approval, confirm who handles the commit, and record the commit per the project's commit-message rules. Fires after `post-code-change.md` clears (build + tests + reviewer consensus + verify-fix all green).

## Hard gates (also in `AGENTS.md`)

- Diff shown to user; explicit approval received.
- **Commit author identity verified per `AGENTS.md` §4.1** - both effective config (`git config --show-scope --show-origin --get user.name` / `user.email`) AND `git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT` resolve to a non-empty human identity (not a disallowed automation identity); for `--amend` / `cherry-pick` / `rebase` / `am`, the preserved author + committer on the target commit are ALSO not disallowed automation identities. On missing / disallowed: prompt the user via `ask_user` (Step 3a below); write `--local` by default; promote to `--global` ONLY on explicit user opt-in.
- Commit ownership confirmed (user vs agent) via `ask_user` - prompt MUST display the resolved `<user.name> <<user.email>>` + scope AND use the literal `the agent` / `you (the user)` actor labels (no bare `I` / `me` / `you`). Step 3b below has the canonical form schema.
- Single-line commit message; no Conventional-Commit prefix; no `Co-authored-by` trailer; no body / footer.
- Stage only touched files (`git add <path>` - never `git add .`).
- **Comment audit on staged diff (HARD GATE per `comment-protocol.md` §3.1 + §Persisted audit file)** - every commit MUST run the §3.1 comment-protocol DISCIPLINE on every NEW or substantively-rewritten comment in the diff (clarity-check → rename-check → step-3 `ask_user` OR exempt-category citation; details in `comment-protocol.md` and `post-code-change.md` §2.6). Tracking format depends on whether the consuming repo has adopted the audit-file workflow: **(adopted repos)** stage `.github/pr-quality-gate/audits/last.md` containing the §2.6 audit block verbatim with the required `parent_sha:` header - the audit-file path is enumerated in `staged_files` and CANNOT be omitted; `pr-gate-check.yml` fails the PR if the file is missing or the audit `parent_sha` doesn't match the commit's actual parent. **(non-adopted repos)** comment-audit tracking happens INLINE via the `comment_audit` block in `PRE-COMMIT GATE PASSED` only - DO NOT create the audit file (see `comment-protocol.md` §Persisted audit file - adoption gate). Adoption detection: at least ONE of `.github/workflows/pr-gate-check.yml`, `scripts/check-comment-audit.ps1`, or a pre-existing `.github/pr-quality-gate/audits/last.md` in main. Run the audit AFTER the diff is shown + approved but BEFORE `git add`, so the recorded content reflects what's actually being committed. Full procedure: `comment-protocol.md` (canonical) + `post-code-change.md` §2.6 (ledger format).
- **`PRE-COMMIT GATE PASSED` block emitted in the current turn** before any `git commit` tool call - §1B refuses `git commit` without this block (mirrors §1A's `PANEL CONVERGED` enforcement at the implementation boundary and §2B's `POST-CODE-CHANGE LEDGER` enforcement at the staging boundary).
- **A panel `READY` verdict (pre-implementation, pre-PR-creation, or any other panel slot) does NOT satisfy this gate on project (non-instruction) repos.** Panel review is technical; this gate is user review. Both independent, both must pass. Chaining panel `READY` into any commit-producing tool call, `git push`, or `gh pr create` without an intervening `ask_user`-based diff-approval is a process violation. Full rule in `pr-quality-gate/panel-policy.md` §"User diff-approval after panel READY".
- **Pre-impl panel `READY` does NOT satisfy the post-implementation review.** The pre-implementation panel reviews specifications; it cannot see actual code. Implementation-level bugs emerge only after code is written. `post-code-change.md` step 3 (multi-model reviewer panel) MUST run after implementation lands and before `git add` of staged-for-commit files - its result is recorded in `POST-CODE-CHANGE LEDGER` per §2B as `post-code-change-panel: ran, unanimous`. The pre-impl and post-impl panels are independent gates; BOTH must clear before `git commit`. Bypass tracked as `post-impl-review-skipped-after-pre-impl-panel-ready` in `pr-quality-gate/data/panel-misses.csv`. **Lightweight escape hatch:** when the change is trivial (single-file, ≤10 lines, no new types/methods/behavior - typo fix, config bump, dependency upgrade, comment edit), a single-agent code-review pass on the staged diff substitutes for the full multi-model panel; record this as `post-code-change-panel: ran, single-agent-review (rationale: <trivial-change reason>)` in the ledger.
- **Pre-PR-create draft-state ask** - before any `gh pr create` (or equivalent PR-creation tool call), the agent MUST `ask_user` whether the PR should be created as `draft` or `ready for review`. The default option in the form should match the user's prior session-wide preference if one was set; otherwise default to `ready`. Recorded in the `pr_creation:` field of the `PRE-COMMIT GATE PASSED` block (see Step 3 schema) - `pr_creation: deferred` if this commit is not a PR-creation point; `pr_creation: draft` / `pr_creation: ready` if it is.
- **Ack-file sync (HARD GATE)** - if `pr-quality-gate/pattern-catalog.md` is in the staged diff (`git diff --cached --name-only` shows it), then `pr-quality-gate/HIGH-TIER-SLUGS.md` MUST ALSO be staged AND match the catalog state. Run `pwsh -File scripts/sync-critical-rules.ps1` to regenerate, then `git add .github/pr-quality-gate/HIGH-TIER-SLUGS.md`. The `.githooks/pre-commit` hook (installed via `setup.ps1`/`setup.sh` setting `core.hooksPath .githooks`) enforces this automatically; the CI workflow `.github/workflows/catalog-sync-check.yml` is the backstop for `--no-verify` bypass. Full design in `pr-quality-gate/panel-policy.md` §"Catalog-edit + ack-sync invariant". Process violation if commit lands with drift; tracked in `panel-misses.csv` under `catalog-ack-drift`.

## `PRE-COMMIT GATE PASSED` block - required emission

Before any `git commit` (including `git commit --amend`, `git cherry-pick`, `git rebase`-driven commit replay, or any other tool call that produces a new commit object), the agent MUST emit a literal block in the **current turn** that records the outcome of each pre-commit gate. The block must appear in the same turn as the commit tool call. Per §1B, the absence of the block forbids the tool call - no rationalization (e.g., "the diff was approved a few turns ago", "the message is obvious from context", "this is just a small amend") is acceptable.

### Block format

```
PRE-COMMIT GATE PASSED
gate|diff_shown=yes:t<N>|diff_approved=yes:t<N+M>:"<approval phrase>"|staged_diff_verified=<yes:(N files,+X/-Y)matches-shown | no:<discrepancy>>|profile=<full|lite|full-default>|author_identity=<name> <<email>>(scope:<local|global|env-override>)|commit_ownership=<agent|user>|rule_coverage_passed=<bool>|pr_creation=<deferred|draft|ready>
subject|proposed_subject="<exact -m string>"|subject_approved=yes:t<K>:"<phrase|edited to:...>"|format_check=single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:<int>
comment_audit|audit_file_staged=<yes:.github/pr-quality-gate/audits/last.md | no-not-adopted(no pr-gate-check.yml AND no check-comment-audit.ps1 AND no audit file in main) | no-FAILS(adopted but missing)>|parent_sha=<literal SHA from audit header = git rev-parse HEAD at write time; EMPTY_TREE for root>|new_or_rewritten=<int>|approval_entries=<int valid approval_turn bullets>|schema_source="comment-protocol.md §Persisted audit file + post-code-change.md §2.6"
core_rules_acknowledged:   # caveman one-line-per-slug per post-code-change.md §"core_rules_acknowledged - chat-emission form (caveman)"; enumerate EVERY HIGH-tier review-pass-only slug; aggregate counts INVALID
  - slug:<slug> status:applied sites:<site[,...]> metric:rg=<C/N> disp:<rename|extract|remove|restore|keep> [keep_reason:"<=12w"]
  - ... (one line per slug x disposition-group; status:na lines carry na_reason)
full_scan_results:   # REQUIRED iff this turn ALSO commits a catalog edit (new slug OR enhanced audit-method); absent/empty = §1A.3 violation. Structured per-site (STAYS):
  - new_or_enhanced_slug: <slug>
    change_type: <new | enhanced-audit-method>
    sites_scanned: <int - code sites the audit-method examined across the full PR diff>
    gaps_found: [<file:line>, ...]
    gaps_fixed_in_this_amend: [<file:line>, ...]
    gaps_deferred_with_reason: [<file:line - <=30w justification>, ...]
staged_files:   # per-path enumeration (STAYS); "git add ." / "-A" / "--all" forbidden per §0
  - <explicit relative path 1>
  - <... enumerate ALL staged files>
```

### Field requirements

- **`diff_shown` / `diff_approved`** - record the actual turn numbers (or message indices) in the current conversation. If the diff was shown but never explicitly approved by the user, `diff_approved: no` MUST appear and the commit MUST NOT proceed.
- **`author_identity`** - verbatim output of `git var GIT_AUTHOR_IDENT` (name + email). For amend / cherry-pick / rebase operations, the preserved author on the replay target must ALSO be verified to be a non-automation identity per `AGENTS.md` §4.1; that verification result goes in a separate `replay_author_identity:` line.
- **`commit_ownership`** - must be either `agent` or `user`. If `user`, the agent must STOP at this gate and let the user run `git commit` themselves - no chain-through to `git push`.
- **`proposed_subject`** - the EXACT string that will be passed to `git commit -m`. Not a summary; the literal value.
- **`subject_approved`** - record the user response that approved the proposed subject. If the user edited the subject during approval, `proposed_subject` must reflect the edited version, and `subject_approved` should quote the edit.
- **`format_check`** - five boolean sub-fields. Any `no` on `single_line` / `subject_length_chars > 72` / etc. that contradicts the playbook's format rules MUST cause the agent to revise the message before re-emitting the block.
- **`comment_audit`** - runs after the diff is approved by the user but before `git add`. Procedure: (1) for each file in the staged additions, use the per-extension comment-syntax map from `comment-protocol.md` §Scope to count NEW or substantively-rewritten comment lines (NOT pre-existing comments that happen to live in modified files); (2) for each counted comment, classify per `comment-protocol.md` (clarity-check → rename-check → step-3 `ask_user` OR an exempt category from the canonical 6); (3) tracking format depends on adoption (see `comment-protocol.md` §Persisted audit file - adoption gate): **(adopted repos)** write the §2.6 audit block to `.github/pr-quality-gate/audits/last.md` with `parent_sha:` set to `git rev-parse HEAD` (the commit's about-to-be parent), `commit_subject:` set to the proposed commit subject, and one bullet per NEW or substantively-rewritten comment; stage the audit file via explicit `git add .github/pr-quality-gate/audits/last.md` (enumerated in `staged_files`). Meta-changes with zero source-code edits still write the audit file with the zero-count template - the file's presence is invariant on adopted repos. **(non-adopted repos)** DO NOT create the audit file; record the dispositions INLINE in this `comment_audit` block (counts + per-comment approval-turn citations from the session's `ask_user` history). The `comment_audit` block records the audit-file status + counts + the parent_sha used (when applicable); on adopted repos, mismatch between the audit's parent_sha and the actual commit parent fails `pr-gate-check.yml` post-push.
- **`core_rules_acknowledged`** - REQUIRED enumeration of every HIGH-tier review-pass-only catalog slug. Schema and verification semantics are canonical in `panel-policy.md` §Per-rule acknowledgement; chat emits the caveman one-line-per-slug form (`post-code-change.md` §"core_rules_acknowledged - chat-emission form (caveman)"). Per-site citations are MANDATORY for `status:applied`; aggregate counts alone are INVALID. **Forcing-function recipe** for the most common HIGH-tier slugs:
    - `comment-necessity`: cite per-bullet `approval_turn:` value from the §2.6 ledger (paste from `.github/pr-quality-gate/audits/last.md` on adopted repos OR from the inline `comment_audit` block on non-adopted repos). Valid forms: (i) real `ask_user` turn/message ref + `allowed-case` (non-obvious invariant | external constraint | trade-off); (ii) `n/a - exempt: <category from canonical 6>` (`typo` | `deletion` | `stale-comment-fix-per-§3.9/§3.10` | `generated` | `vendored` | `THROWAWAY-header`); (iii) `n/a - degraded-mode-drop`; (iv) `n/a - no-response-drop`; (v) `deleted (per protocol step-3 rejection | rename-first resolution)`. Any other value = violation. On adopted repos, the audit file MUST be staged via explicit `git add .github/pr-quality-gate/audits/last.md` (enumerated in `staged_files`); on non-adopted repos, the audit file is NOT created and the citations live in the inline block.
    - `prefer-async-suffix`: paste output of `git diff --cached -U0 | grep -nE '^\+.*\.(Open|SaveChanges|Read|Write|Flush|Send|Dispose|CreateDbContext)\(' | grep -v '^\+\+\+'` then cite per site (used-async-overload / no-async-overload-on-receiver / sync-justified:<reason>). If choosing sync where Async exists, MUST justify.
    - `panel-artifact-leakage`: run `git diff --cached -U0 | grep -nEi '(round[ -]?\d|bot.*(caught|finding|flagged)|Slot \d|PR ?\d+\+\d)' | grep -v '^\+\+\+'`. Zero matches = `status:applied sites:[] metric:rg=0/0`. Any match BLOCKS the commit until removed.
    - Other HIGH-tier slugs: see catalog `review_pass_only_prompt` text for the slug's check. Cite per-site disposition for any matches in the diff.
  Verification: if rg-battery violation count (from gate-runner output) > acknowledged per_site_citations count → gate BLOCKED unless `divergence_acknowledged: <specific reason>` is set with ≤50-word justification. Divergence override is logged to `panel-misses.csv.divergence_override_history` for audit.
- **`rule_coverage_passed`** - boolean derived from `core_rules_acknowledged`: true iff every HIGH-tier review-pass-only slug from `pattern-catalog.md` (or `HIGH-TIER-SLUGS.md` once Phase E lands) has an `applied` or `not-applicable` disposition with valid evidence/rationale. A missing slug = `rule_coverage_passed: false` = gate BLOCKED.
- **`full_scan_results`** - REQUIRED when this turn's commits include a catalog edit (new slug OR enhanced audit-method on an existing slug) per `AGENTS.md` §1A.3. For each catalog change, the agent runs the new/enhanced rule's `Audit method` clause against the FULL PR diff (not just the bot-flagged site) and reports: `sites_scanned` (how many candidate sites the audit examined), `gaps_found` (file:line of every site that violates the new rule), `gaps_fixed_in_this_amend` (subset of gaps_found that the agent fixed in this same commit), `gaps_deferred_with_reason` (subset deferred with explicit ≤30-word justification). Bot findings reveal catalog gaps; verifying the rule finds ALL instances prevents one-by-one surfacing in future rounds. Slug `full-scan-against-new-rule-not-triggered-after-bot-finding` enforces at review time.
- **`pr_creation`** - three valid values:
    - `deferred` - this commit is not the PR-creation commit (no `gh pr create` happening in the same turn). The draft-state question is asked at the moment `gh pr create` is invoked, not at every prior commit.
    - `draft` - `gh pr create --draft` was approved by the user via `ask_user` in this session for this PR.
    - `ready` - `gh pr create` (no `--draft` flag) was approved by the user via `ask_user` in this session for this PR.
  The `ask_user` prompt MUST present both options (`draft` / `ready`) and record the user's response verbatim in the `PR-CREATION GATE PASSED` block (see `pr-creation.md` for the full schema if one exists, else this `pr_creation` field captures the decision inline). For amends/force-pushes to an EXISTING PR, `pr_creation: deferred` is correct because no new PR is being created.
- **`staged_files`** - enumerated list. `git add .`, `git add -A`, `git add --all` are forbidden per §0; the staged files list must come from an explicit `git add <path>` per file.
- **`staged_diff_verified`** - after running `git add <paths>` and BEFORE running `git commit`, the agent MUST run `git diff --cached --stat` and compare the output against the diff shown to the user in `diff_shown`. If the staged-diff file list or line-count differs from the shown-diff, the commit is FORBIDDEN until the agent investigates the divergence and either re-stages or reverts. Recorded in the `PRE-COMMIT GATE PASSED` block as `staged_diff_verified: yes (staged stat: <N files, +X/-Y>) matches shown-diff` or `staged_diff_verified: no - <discrepancy details>`. Catches files edited in working tree that fail to make it into the commit. Tracked as `fix-silently-lost-between-shown-diff-and-commit` in `pr-quality-gate/data/panel-misses.csv`.

### Falsification is a higher-severity failure than skipping

If the block claims a gate was satisfied (e.g., `diff_approved: yes (turn 42)`) but the conversation record shows it was not, that is a more severe violation than omitting the block entirely. The agent MUST self-report falsified block entries proactively in the next turn and propose remediation (typically: revert the commit, restore working tree, re-run the gates).

### Skip conditions (none apply unless explicitly documented this session)

- The user has stated in THIS session: "skip the pre-commit block" or equivalent unambiguous waiver for a specific commit or range. The waiver MUST be recorded in the session state with the affected commit identifier.
- `git commit --amend --no-edit` that is mechanically restoring a previously-emitted committer timestamp without changing tree or message (e.g., immediately after a successful `git rebase --continue`) - the original commit's `PRE-COMMIT GATE PASSED` block is preserved by reference.

The trivial-mechanical-fix carve-out from §1B does NOT apply to the `PRE-COMMIT GATE PASSED` block - "obvious mechanical fixes" is the rationalization path through which format violations slipped historically.

## Intake questions

Bundle these in one prompt:

1. Will the agent run the commit on your behalf, or will you (the user) run the commit yourself? (Default: you run the commit - many of your workflows involve manual review, splitting, or amending before push.)
2. **If the agent commits:** confirm the proposed commit message before the agent runs `git commit`.

(Identity-verification questions - when needed - are asked in Step 3a below, separately from this ownership prompt.)

## Procedure

### 1. Show the diff

Render the diff for the user. Cover:

- Files touched (count + names).
- For each file: a brief summary of what changed and why.
- Anything notable that might surprise the reviewer (rename, file move, new dependency, new config knob).
- Anything intentionally NOT changed but reviewer might expect to be (so they don't waste a review cycle wondering).

### 2. Wait for explicit approval

Do not commit until the user says "approved" / "looks good" / "go ahead" / equivalent. Silence is not approval.

If the user requests revisions:

- Apply the revisions.
- Return to `post-code-change.md` for build + tests if the revision touched code.
- Re-show the updated diff.

### 3. Verify commit author identity, then confirm commit ownership

Step 3 has two parts: **3a** resolves and verifies the author / committer identity per `AGENTS.md` §4.1 (including amend / cherry-pick / rebase / am author preservation), and **3b** asks via `ask_user` who runs the commit, displaying the resolved identity AND using explicit actor labels.

#### 3a. Resolve and verify the author identity

Run these to determine the effective identity AND its scope:

```powershell
git config --show-scope --show-origin --get user.name
git config --show-scope --show-origin --get user.email
git var GIT_AUTHOR_IDENT       # what git would actually use, including env overrides
git var GIT_COMMITTER_IDENT
```

Also inspect env-var overrides (env beats config silently):

```powershell
$env:GIT_AUTHOR_NAME, $env:GIT_AUTHOR_EMAIL, $env:GIT_COMMITTER_NAME, $env:GIT_COMMITTER_EMAIL, $env:EMAIL
```

For commit-producing operations that preserve the author from a replayed commit (`--amend` without `--reset-author`, `cherry-pick`, `rebase`, `am`), ALSO inspect the commit being amended / replayed:

```powershell
git --no-pager log -1 --format='%an <%ae>%n%cn <%ce>' <target-commit-sha>
```

**Disallowed automation identity** = case-insensitive match against `Copilot`, `copilot[bot]`, `github-actions[bot]`, `223556219+Copilot@users.noreply.github.com`, any other `[bot]`-suffixed GitHub account, or any non-user service principal. Full definition in `AGENTS.md` §4.

**Trigger the `ask_user` flow** when ANY of these hold: (a) effective `user.name` or `user.email` is empty in all scopes; (b) effective identity (config or env override) is a disallowed automation identity; (c) preserved author / committer on a replay target is a disallowed automation identity.

Form schema:

```yaml
message: |
  Git can't find a usable user.name / user.email for this commit.

  Effective config (inspected via `git config --show-scope` + `git var GIT_AUTHOR_IDENT`):
    user.name  = <value or "(empty)"> (scope: <local | global | system | env-override | none>)
    user.email = <value or "(empty)"> (scope: <local | global | system | env-override | none>)

  (For amend / cherry-pick / rebase / am: the replay target's author is also shown if it's a disallowed automation identity, with a separate choice to reset the author after the human identity is set.)

  Provide your name and email. The agent will write them to LOCAL repo scope (`git config --local`) - this repo only.
  Check the "also write to --global" box ONLY if you want this identity to apply to every future repo on this machine.

requestedSchema:
  properties:
    userName:
      type: string
      title: "Your name (as it should appear on commits)"
      minLength: 1
    userEmail:
      type: string
      format: email
      title: "Your email"
    alsoWriteToGlobal:
      type: boolean
      default: false
      title: "Also write to --global (default: local only)"
      description: "If checked, the agent will also run `git config --global user.name ... && git config --global user.email ...`. Leave unchecked to keep this identity in this repo only."
    resetAuthorOnReplay:
      type: boolean
      default: false
      title: "(Replay only) Reset author to your identity"
      description: "Only shown when amend / cherry-pick / rebase / am has a disallowed-automation preserved author. If checked, the agent will pass `--reset-author` to the commit-producing command."
  required: [userName, userEmail]
```

After the user accepts the form, the agent writes:

```powershell
git config --local user.name  "<userName>"
git config --local user.email "<userEmail>"
# Only if alsoWriteToGlobal=true:
git config --global user.name  "<userName>"
git config --global user.email "<userEmail>"
```

The agent MUST NEVER guess `user.name` / `user.email` from machine username, GitHub session principal, prior repos on the machine, or any other heuristic - values come from the user's `ask_user` answer.

§4.1 also forbids: `git commit --author="..."`, `git -c user.name=... -c user.email=...` flags, and unauthorized `--reset-author`. `--reset-author` may be used ONLY when the form returns `resetAuthorOnReplay=true` (and only on the corresponding replay command).

**Don't touch signing config.** Do NOT modify `commit.gpgsign`, `gpg.format`, `user.signingkey`, or `gpg.<format>.program`. If signing fails or the signing key looks like an automation key, surface via a separate `ask_user` - never bypass with `--no-gpg-sign` without explicit user approval.

#### 3b. Confirm commit ownership

Once identity is resolved and verified, ask via `ask_user`:

```yaml
message: |
  Ready to commit. Author identity resolved as:

      <user.name> <<user.email>>
      (from <local | global | system | env-override> config)

  Who runs the commit?

requestedSchema:
  properties:
    commitOwner:
      type: string
      title: "Who runs the commit?"
      oneOf:
        - const: "user"
          title: "You (the user) - the agent will print the staged diff and the prepared commit message; you (the user) run `git commit` yourself."
        - const: "agent"
          title: "The agent - the agent will run `git commit -m \"<approved message>\"` on your behalf."
      default: "user"
  required: [commitOwner]
```

Default to the user. Many of the user's workflows involve manual review, splitting commits, amending before push, or other prep that the agent should not pre-empt. If the user picks `agent`, proceed to Step 4. If `user`, the agent prints the staged file list, prepared commit message, and the exact `git commit -m "..."` command for the user to run.

**Push-ownership is asked SEPARATELY** in `pre-pr-push.md` *Pre-check 0* (per `AGENTS.md` §4.2). Do NOT bundle commit and push ownership in one prompt.

### 4. If the agent commits

#### Show the diff and wait for approval

Before ANY `git add` or `git commit` (including `--amend`), the agent MUST:

1. Show the diff to the user (`git --no-pager diff` for unstaged changes, or `git --no-pager diff --cached` if already staged).
2. Wait for explicit user approval ("approved" / "looks good" / "go ahead" / equivalent).
3. Only then proceed to staging and committing.

This applies to fresh commits, amends, fixups, and any other commit-producing operation. The user must see every change before it enters the git history. Silence is not approval.

#### Confirm the commit message

Before staging or running `git commit`, the agent MUST present the proposed commit message to the user via `ask_user` and wait for explicit approval. The agent does NOT run `git commit` until the user has seen and approved the exact message text. This is a **separate prompt** from the ownership prompt in step 3b - never bundle them.

```yaml
message: |
  Proposed commit message:

      <proposed single-line message>

  Approve this message, or provide an alternative.

requestedSchema:
  properties:
    approved:
      type: boolean
      title: "Approve this commit message?"
      default: true
    alternativeMessage:
      type: string
      title: "Alternative message (only if not approved)"
      description: "Leave blank to use the proposed message."
  required: [approved]
```

If the user provides an alternative, use that instead. If the user declines without providing an alternative, ask again with a revised proposal.

#### Stage only touched files

```powershell
git add <path1> <path2> <path3>
```

Never `git add .` or `git add -A` - picks up stray files.

#### Commit message rules (from `AGENTS.md` §2)

- **Single line only.** No body, no footers, no trailers of any kind.
- **No `Co-authored-by` trailer.** Use `git commit -m "<message>"` only - no additional `-m` flags, no tool-appended trailers, no blank line followed by `Co-authored-by:`. The commit must contain the single line and nothing else.
- **Describe what the change does**, not which plan item it implements. No `A2`, `(A2)`, plan section numbers, or Conventional-Commit prefixes (`perf:`, `fix:`, `feat:`, etc.).
- **Imperative mood, no trailing period.**

Examples:

| Verdict | Message |
| --- | --- |
| ✅ | `Defer TagsDisplayName join until first read` |
| ✅ | `Add IsEnabled guard to LoggingMiddleware before serializing actions` |
| ❌ | `perf: defer TagsDisplayName join (A2)` |
| ❌ | `A2 - lazy tags` |
| ❌ | Any message followed by `Co-authored-by:` or any other trailer. |

#### Run the commit

```powershell
git commit -m "<single-line message>"
```

Verify the resulting commit has no trailer:

```powershell
git --no-pager log -1 --format=%B
```

The output should be exactly the single line. If a trailer appears, amend immediately:

```powershell
git commit --amend -m "<single-line message>"
```

### 5. Record state

Record in phase-state tracking:

- Commit SHA created.
- Commit message used.
- Whether the user or the agent ran the commit.
- `perCommitAuditCoverage` entry for the new commit SHA - `done` / `skipped-with-reason` per User-skip policy. Canonical enum (`AGENTS.md` *Per-phase additional fields*): `done` / `skipped-with-reason` / `not-run`; do NOT add values. Pre-PR-push reads the map; missing entry = `not-run` = blocks readiness gate.

This feeds into pre-PR-push amend-safety logic and the "ready to push" check.

## Next phase

If the user is preparing to push for review (open PR, request review, or push to a shared branch others may pull from), proceed to `pre-pr-push.md`.

If the commit is just an intermediate WIP and more work is coming, return to the next pre-implementation cycle.
