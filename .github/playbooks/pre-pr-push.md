# Playbook: Pre-PR-push phase (INDEX)
<!-- read-receipt-token: d7154b3e -->

## Purpose

This is an INDEX, not a procedure. Pre-PR-push has four distinct sub-procedures and the right one to run depends on the user's situation. The agent runs intake first, then fetches the matching sub-file(s) per the deterministic decision tree below.

Fires when the user is preparing to push for code review — opening a PR, requesting review, or pushing to a shared branch others may pull from. Does NOT fire for personal sandbox / backup pushes that no one else watches.

## Hard gates (also in `AGENTS.md`)

- **Push credentials verified as the user's per `AGENTS.md` §4.2** — mechanism-aware verification (HTTPS+`gh` → `gh api user --jq .login`; HTTPS+system credential helper → user-confirm via `ask_user`; SSH → `ssh -T git@<host>` greeting; ambient `GH_TOKEN` / `GITHUB_TOKEN` / `GIT_ASKPASS` / `SSH_AUTH_SOCK` → STOP unless user confirms). Applies to EVERY push, including sandbox pushes that exit at the sandbox pre-check AND ref-publishing commands that implicitly push (`gh pr create` against an un-pushed branch, `gh repo sync`, `git push --mirror`, `git push --all`). Verification procedure + form schemas live in *Pre-check 0* below. Recorded as `pushCredentialsVerified` (the 10th predicate field, values `yes` / `user-confirmed-unverifiable` / `blocked`); a `blocked` value FAILS the readiness gate. Push-ownership `ask_user` is SEPARATE from commit-ownership (never bundled) and uses explicit `the agent` / `you (the user)` actor labels — never bare `I` / `me` / `you`.
- Per-commit comment audit run on every commit's diff (already gated by `AGENTS.md` §3.1 on each commit — verify it actually ran).
- Branch-wide rename-first sweep run once before first push intended for review.
- **Branch-wide least-privilege audit** run when `git diff <base>..HEAD` shows any **visibility / export / mutability surface delta** (same definition as `post-code-change.md`'s touched-file gate) across the branch. Procedure: `.github/playbooks/least-privilege-audit.md` with branch-wide scope restricted to the projects touched. Skipped only when the branch has no visibility / export / mutability surface delta — that fact recorded explicitly with the justifying file list. **Run AFTER any branch-wide rename-first sweep cleanup has been committed / amended** (so the audit sees the final branch state, not a sweep-mutated working tree). Fresh-source-search at audit time; per-commit classifications from earlier in the branch are stale by the time the branch is push-ready.
- **Branch-wide vertical-slice (VSA) audit** run when `git diff <base>..HEAD` adds / moves / renames any type or file, adds a root-level file to a folder-organized assembly, adds a new top-level type to an existing file, or introduces a multi-type file. Procedure: the vertical-slice lens of `.github/playbooks/codebase-architecture-audit.md` at branch-wide scope, re-grepped against the final branch state. Skipped only when the branch has no such structural delta, that fact recorded. A uniformly-flat small assembly is not folderized (see that playbook's scoped-invocation section for the objective bound); a documented prior CLEAN verdict stands unless the user overrides it.
- **PR title + body free of internal plan markers.** Before invoking `gh pr create` / `gh pr edit`, re-read the title + body and strip any session-internal references: plan IDs (`T1`, `F16e-2`, `FX-3`, `C5`, etc.), session file paths (`files/foo-audit.md`, `aa2fde9c/plan.md`), upstream commit SHAs that won't survive a rebase, or stage / phase markers from the agent's internal task tracker. The audience is the public repo, not the agent's planning workspace; the title + body must stand on their own. Concrete patterns that have leaked in past PRs and were caught only post-open: `"... (T1)"` suffix, `"Carries out the T1 audit from files/f3-test-quality-audit.md"`, `"... already shipped upstream by d3fcfa9"`. **Use the SUT names, the behavior change, and the test count delta** — never the internal phase IDs.
- Sweep base SHA + sweep HEAD SHA + base ref recorded for re-run logic.
- **Pre-PR-push state read-back evidence-gate output emitted** before any "ready to push" claim — structured chat block enumerating the 11-field state predicate + sandbox-confirmation informational field (12 lines total), verbatim from session-todo phase-state records, NOT from memory (see *Evidence-gate output before declaring "ready"* below).
- No "ready to push" claim until push credentials verified (§4.2), per-commit audit, branch-wide sweep, AND branch-wide least-privilege audit plus branch-wide vertical-slice (VSA) audit (each when applicable) done OR user explicitly skipped (with recorded warning per User-skip policy).

## Pre-check 0: Verify push credentials (always — runs BEFORE the sandbox pre-check)

`AGENTS.md` §4.2 applies to EVERY agent-run push — including sandbox / backup pushes that would otherwise exit at the next pre-check, AND ref-publishing commands that implicitly push (`gh pr create` against an un-pushed branch, etc.). This step runs FIRST so even sandbox-exit records carry a real `pushCredentialsVerified` value (no `n/a-sandbox-exit` sentinel for this field).

### Procedure

**1. Inspect the remote and credential helper.**

```powershell
git remote -v                       # HTTPS vs SSH for the remote being pushed to
git config --get-all credential.helper
```

**2. Check for ambient automation tokens / sockets in the environment.**

```powershell
$env:GH_TOKEN, $env:GITHUB_TOKEN, $env:GIT_ASKPASS, $env:SSH_AUTH_SOCK
```

If any of `GH_TOKEN`, `GITHUB_TOKEN`, `GIT_ASKPASS` is set, OR `SSH_AUTH_SOCK` points at an agent-controlled socket the user did not create, treat as automation auth. STOP and surface via `ask_user`. Default to `pushCredentialsVerified: blocked` unless the user explicitly confirms the token / socket is user-owned and intended.

**3. Apply mechanism-specific verification.**

| Mechanism | Verification command | Pass / fail criteria | Recorded value on pass |
| --- | --- | --- | --- |
| HTTPS + `gh` helper | `gh api user --jq .login` | Login matches the user's known GitHub account AND is NOT a `[bot]` account | `yes` |
| HTTPS + system credential helper (Windows Credential Manager / macOS Keychain / libsecret / GCM) — helper does not generally expose the cached principal | n/a (helper opaque) | Ask the user via `ask_user`: *"Your remote `<URL>` uses `<helper-name>`, which doesn't expose the cached username. Is the cached credential for this remote yours — not a Copilot / `[bot]` / shared / service account?"* | `user-confirmed-unverifiable` on yes; `blocked` on no / unsure |
| SSH | `ssh -T git@<host>` (when host supports a greeting, e.g. github.com prints `Hi <username>!`) | Greeting matches the user's known account | `yes` |
| Ambient `GH_TOKEN` / `GITHUB_TOKEN` / `GIT_ASKPASS` / `SSH_AUTH_SOCK` (from step 2) | n/a | STOP and ask via `ask_user`; default to `blocked` unless user explicitly confirms ownership + intent | `yes` only on explicit confirmation; otherwise `blocked` |

**4. Record `pushCredentialsVerified` in the pre-PR-push phase-state record** (per `AGENTS.md` *Per-phase additional fields*). One of:

- `yes` — mechanism returned the user's principal.
- `user-confirmed-unverifiable` — mechanism couldn't expose the principal; user confirmed via `ask_user` that the cached credential is theirs.
- `blocked` — verification revealed (or strongly suggested) a non-user principal OR user could not confirm. **Push MUST NOT proceed.** Surface the issue and let the user resolve it (re-auth, remote URL change, env-var unset, etc.) — see no-silent-re-auth rule below.

**5. No silent re-auth.** If the principal is wrong (or the cached credential is for the wrong account), surface via `ask_user`. The agent MUST NOT run `gh auth login`, `gh auth refresh`, `gh auth switch`, `git credential approve`, `git credential fill`, `git credential erase`, or any other credential-modifying command on its own.

### Push-ownership prompt (separate from commit-ownership)

Push-ownership is asked ONLY after (a) Pre-check 0 cleared (`pushCredentialsVerified` is `yes` or `user-confirmed-unverifiable`) AND (b) the readiness gate has cleared. It is a SEPARATE `ask_user` from commit-ownership (which lives in `pre-commit.md` Step 3b). Form schema:

```yaml
message: |
  Ready to push <local-branch> → <remote>/<remote-branch>.

  Push credentials verified as: <e.g. "gh login: jschick (HTTPS + gh)" / "SSH greeting: jschick@github.com" / "user-confirmed credential helper: manager (Windows Credential Manager)">.

  Who runs the push?

requestedSchema:
  properties:
    pushOwner:
      type: string
      title: "Who runs the push?"
      oneOf:
        - const: "user"
          title: "You (the user) — the agent will print the exact `git push` command; you (the user) run it yourself."
        - const: "agent"
          title: "The agent — the agent will run `git push <remote> <branch>` on your behalf."
      default: "user"
  required: [pushOwner]
```

Default to the user. The prompt MUST use the literal `the agent` / `you (the user)` actor labels in both message body and option titles — bare `I` / `me` / `you` are forbidden (they read ambiguously in agent-mediated chat).

## Pre-check: is this push intended for review at all?

Before consulting the truth table or fetching any sub-file, settle this single question via intake — **scoped to the current push, not the branch's eventual fate**: **will this specific push be used for review (by you or others) or pulled/inspected by anyone other than the user themselves?**

- If **personal-sandbox / backup-only** (this push is for the user's own backup, cross-machine sync, or local dress-rehearsal — nobody else will pull this push for review):
  1. **Record the phase-state record FIRST** per the *Sandbox-exit record* shape in `AGENTS.md` *Phase-state tracking convention* (`branchWideSweepStatus: not-applicable`, booleans recorded, predicate fields written as the literal `n/a-sandbox-exit` sentinel; this is a `done` phase-state record, not a "skipped" record — the playbook explicitly resolved as not-applicable for this push).
  2. Then emit this exact summary block to the user:
     > *"Out of pre-PR-push scope for this push — personal-sandbox / backup push, no sweep / hygiene checks run. Returning to ordinary push flow: confirm remote / branch and perform the push if you still want it; do not claim review-readiness. When this branch is later pushed for review (PR-opening, request-for-review, push to a shared branch others may pull), re-enter this playbook and intake will catch the prior sandbox exposure under `remoteExposureExists`."*
  3. **Override option:** if the user wants the review-readiness checks anyway (e.g. a deliberate dress-rehearsal sweep for upcoming review), they may say *"run pre-PR-push checks despite sandbox-only"* (or similar); treat the push as review-targeting from that point and continue to the booleans + truth table below.
- If **review-targeting for this push cycle** (first review push, amend in response to PR review, post-merge / post-rebase push on a branch already under review, OR a follow-up commit landing on an open PR before review comments arrive), continue to the two state booleans + truth table below. *(A branch that may LATER become a PR but whose CURRENT push is sandbox-only takes the personal-sandbox branch above — re-enter this playbook on the future review push.)*

This pre-check exists because the two state booleans alone cannot distinguish "sandbox-only repeat push" (out of scope) from "post-merge-rebase push or follow-up commit on a branch already under review" (in scope) — both are `(false, true)` — so per-push intent must be settled first. **Phrase the question as "this specific push", not "this branch eventually"**, so a branch that may *later* become a PR but whose *current* push is sandbox-only correctly exits.

## Two independent state booleans (record both at intake time)

These two booleans determine which sub-files apply when the playbook is in scope (per the pre-check above). They are independent — confusing them is the most common pre-PR-push mis-routing.

- **`isFirstReviewExposurePush`** — *Is THIS push the first one intended for review?* (PR-opening, request-for-review, first push to a shared branch others may pull from.) Drives whether the **branch-wide sweep is required** in this push cycle. Named as a verb-shaped predicate to prevent misreading as "this branch has never been pushed before". **Per-push, not branch-sticky:** a personal-sandbox / backup push records `false` (a sandbox push is not a review push); the FIRST subsequent review push of the same branch records `true`. Independence from `remoteExposureExists` is the point — prior sandbox pushes do NOT latch this boolean to `false` for the upcoming review push.
- **`remoteExposureExists`** — *Has this branch been pushed anywhere before, in any form (including personal sandbox)?* **Historical evidence only** — the primary amend-safety force-push gate is `isFirstReviewExposurePush=false` (the branch is already under review on a shared remote). **Sandbox exemption is conditional, not automatic**: when `(isFirstReviewExposurePush=true && remoteExposureExists=true)`, before any operation that rewrites already-pushed history the agent MUST ask a one-question sandbox-privacy confirmation (*"was the prior sandbox push truly personal/unwatched, and are you sure no one else pulled it?"*); on **yes** silent amend is safe, on **no/unsure** use the `(false, true)` amend-safety subflow only (booleans + decision-tree routing stay unchanged). Question fires lazily — only when an amend is about to happen, NOT preemptively at intake. The canonical contract for this gate lives in `AGENTS.md` *Per-phase additional fields*. Recorded for audit and as input to the `(false, true)` truth-table row's re-run logic.

| `isFirstReviewExposurePush` | `remoteExposureExists` | What this means | Which sub-files apply |
| --- | --- | --- | --- |
| true | false | Brand-new branch, first push will be the review push | per-commit-micro-hygiene + branch-wide-sweep + cleanup-commit-buckets (if sweep changes things). Amend-safety: amending is fine. |
| true | true | Branch was pushed (e.g. personal sandbox or backup) but never reviewed; this push is the review push | per-commit-micro-hygiene + branch-wide-sweep + cleanup-commit-buckets (if sweep changes things). Amend-safety: **conditional sandbox exemption** — before any silent amend, agent MUST ask the one-question sandbox-privacy confirmation per `remoteExposureExists` definition above; on yes, silent amend is safe; on no/unsure, use the `(false, true)` amend-safety subflow choices (booleans + routing stay unchanged — Step 2 sweep still runs). See `cleanup-commit-buckets.md` *Amend-safety invariant*. |
| false | true | Subsequent **review-targeting** push on a branch already under review (review-response amend, post-merge push, rebase, OR a follow-up commit landing on an open PR before review comments arrive). Sandbox-only repeat pushes are NOT in this row — they exit at the pre-check above. | per-commit-micro-hygiene on each new commit + when-to-re-run-sweep (decides whether the branch-wide sweep needs another run). |
| false | false | **Out of scope** — sandbox push to a never-pushed branch. Intent pre-check above already exited the playbook for this case; this row should not be reached. If it is, exit early; no pre-PR-push sub-files apply. | n/a |

## Intake questions (run FIRST, before fetching any sub-file)

Bundle these in one prompt. Q1 settles intent for the pre-check above; the booleans are populated next.

1. **What are you about to do?** Pick the closest:
   (a) first push intended for review (open PR / request review / push to shared branch),
   (b) subsequent review-targeting push on a branch already under review (review-response amend, post-merge / rebase from base, follow-up commit landing on an open PR, OR any combination of these),
   (c) personal-sandbox / backup push only — nobody else will pull this for review.
   *Mapping: (a) → review-targeting + `isFirstReviewExposurePush=true`; (b) → review-targeting + `isFirstReviewExposurePush=false`; (c) → exits at pre-check.*
2. **Has this branch been pushed before — anywhere, in any form including a personal sandbox or backup branch?** *(populates `remoteExposureExists`)*
3. **Base ref** — what is this branch being merged into? (Usually `origin/main` or `origin/master`; confirm.)
4. **Have you done any merges, rebases, or amends since the last branch-wide sweep on this branch?** (If unsure: yes, treat as if you have.) *(For option (b), this is also the disambiguator that drives `when-to-re-run-sweep.md` routing — review-response-only differs from review-response + rebase + new scope.)*
5. **Any additional facts that affect routing?** For example: this push both responds to review AND includes a rebase, merge, amend, new files, or new feature scope; or the branch is being moved to a new base. Multiple sub-files compose — they don't replace each other (see decision tree below).

## Decision tree (deterministic — apply in order, sub-files COMPOSE)

This is **not** "pick one playbook". The sub-files are sequential and conditional, and **multiple sub-files apply when multiple scenarios overlap** (e.g. an amend in response to PR review that also includes a rebase from base requires per-commit-micro-hygiene on the new commit AND when-to-re-run-sweep AND possibly cleanup-commit-buckets if the re-run sweep finds changes).

### Step 1 — DEFAULT (when the playbook applies): per-commit micro-hygiene on every new / amended commit

(This step is reached only when the pre-check above placed the push in scope. If the push is sandbox-only, the playbook already exited.) This is a **per-commit** rule, not a pre-push rule. It should already have run during each commit cycle (gated by `AGENTS.md` §3.1 — every new / modified comment in the diff gets the per-comment audit). At pre-PR-push time, verify it ran for **every** commit on the branch and **every** newly-amended commit since the last sweep — not just the most recent commit.

If it didn't run for some commits (e.g. a fast WIP series with no per-commit audit, or a force-push amend where the audit was skipped), fetch:

> `.github/playbooks/pre-pr-push/per-commit-micro-hygiene.md`

…and run it across each unaudited commit's diff before proceeding.

### Step 2 — IF `isFirstReviewExposurePush=true`: branch-wide sweep

If this is the first push intended for review (PR-opening, request-for-review, or first shared-branch push — see `isFirstReviewExposurePush` boolean above), fetch:

> `.github/playbooks/pre-pr-push/branch-wide-sweep.md`

…and run the branch-wide rename-first sweep across `<base>..HEAD` for the entire branch. **Record the resolved base SHA, sweep HEAD SHA, and base ref name in canonical session todos** (per `AGENTS.md` *Phase-state tracking convention*) so the re-run rules below can detect "out of scope at initial sweep" later.

### Step 3 — IF the sweep finds changes: pick the cleanup-commit bucket

If the branch-wide sweep modifies any files, fetch:

> `.github/playbooks/pre-pr-push/cleanup-commit-buckets.md`

…and pick the **strictest matching bucket** (no-renames / single-scope rename / cross-boundary). Apply the chosen bucket's commit / amend strategy. **Amend-safety check:** if `isFirstReviewExposurePush=false` (the branch is already under review on a shared remote), the buckets that say "amend into the work commit" require explicit user confirmation (force-push approval) — see the cleanup-commit-buckets amend-safety section. If `(isFirstReviewExposurePush=true && remoteExposureExists=true)`, the sandbox exemption is **conditional** — before silently amending, the agent MUST ask the one-question sandbox-privacy confirmation per `remoteExposureExists` definition above; on **yes**, silent amend is safe; on **no/unsure**, fall through to the same explicit force-push approval choices as `(false, true)` (booleans + routing stay unchanged).

### Step 3b — IF the branch has any visibility / export / mutability surface delta: branch-wide least-privilege audit

**Run AFTER Steps 2 + 3 are settled** (sweep changes committed / amended) so the audit sees the final branch state, not a sweep-mutated working tree.

Trigger: `git diff <base>..HEAD` shows any **visibility / export / mutability surface delta** — adds a public / exported type or member; widens visibility; removes `sealed` / `final` / closed-extension; adds or widens a constructor / member / setter; exposes a field; changes package / module exports; introduces an exported Go top-level identifier; widens Rust `pub(...)` to bare `pub`. Do NOT trigger on body-only edits to already-public types that change no surface.

> `.github/playbooks/least-privilege-audit.md` (branch-wide scope, restricted to the projects whose surface the branch touches)

This catches the "many small commits each individually fine, but together leaking too-public surface" failure mode before reviewers see it. Per-commit `post-code-change.md` audits cover touched-file scope only — they don't see cross-commit accumulation. The branch-wide pass re-greps with the ACTUAL final state of the branch.

**Audit-fix commit grouping is NOT cleanup-commit-buckets.** Cleanup buckets classify rename / comment / hygiene churn from the branch-wide sweep; they don't classify API-surface tightening. If the audit recommends changes, group them per `least-privilege-audit.md`'s own commit-grouping section (per-type or per-axis), not per the cleanup-buckets file.

Skip ONLY when the branch has no visibility / export / mutability surface delta. Record the skip explicitly with the justifying file list (e.g., test-only / docs-only / config-only / body-only-edits branches).

### Step 4 — IF `isFirstReviewExposurePush=false` AND `remoteExposureExists=true`: re-run rules

If this is a subsequent push (review-response amend, post-merge push, rebase push, OR a follow-up commit landing on an open PR) on a branch that already exists on a remote, fetch:

> `.github/playbooks/pre-pr-push/when-to-re-run-sweep.md`

…and apply the re-run conditions. Some scenarios re-trigger the full branch-wide sweep; others only require per-commit hygiene on the new amend.

### Step 5 — IF review-targeting push (any of the in-scope rows above): pre-PR-creation multi-model review (§2D)

For every review-targeting push (any of the in-scope rows above — first-review push OR subsequent review-targeting push), fetch:

> `.github/playbooks/pre-pr-creation-review.md`

…and run the §2D mandatory pre-PR-creation multi-model panel on the full branch diff (`<base>..HEAD`). The output of this step is `preCreationReviewStatus` (recorded in canonical session todos): `READY-pending-user-approval | READY-re-emitted-after-user-approval | BLOCKED-<reason>`. Until this field reads one of the `READY-*` values in the current turn, the PR-creation tools enumerated in §2D G6 are forbidden — see `pre-pr-creation-review.md` G3 for the same-turn enforcement.

This step is the SINGLE SOURCE OF TRUTH for "should §2D fire now?" — §2D itself does not re-classify whether the push is review-targeting; it reads from the §2D phase-state record that this step writes.

## State to record before declaring "ready to push"

Per `AGENTS.md` *Phase-state tracking convention*, record these in the canonical session todos table:

- `isFirstReviewExposurePush` (boolean) and `remoteExposureExists` (boolean) — set at intake.
- `baseRef` / `baseSha` / `sweepHeadSha` — captured at sweep time (NOT later-resolved symbolic refs).
- `perCommitAuditCoverage` — per-commit-SHA status (`done` / `skipped-with-reason` / `not-run`). Must be `done` or `skipped-with-reason` for every commit before "ready". *Recorded per-commit by `pre-commit.md` Step 5; pre-PR-push reads back the accumulated map.*
- `branchWideSweepStatus` — see `AGENTS.md` *Phase-state tracking convention* for the canonical enumeration (8 values: `not-applicable`, `done-clean`, `done-cleanup-committed`, `previously-done-no-rerun-needed`, `rerun-done-clean`, `rerun-done-cleanup-committed`, `rerun-skipped-with-reason`, `skipped-with-reason`). The producing sub-files (`branch-wide-sweep.md`, `cleanup-commit-buckets.md`, `when-to-re-run-sweep.md`) write the specific value; this field's contract lives in AGENTS to avoid drift.
- `cleanupBucketOutcomes` — for each cleanup commit: bucket chosen + reason + whether amend-safety required force-push approval.
- `sandboxPriorExposureConfirmation` — `confirmed-private` / `denied-or-unsure` / `not-needed`. Written only when the conditional sandbox-exemption gate fires (`(isFirstReviewExposurePush=true && remoteExposureExists=true)` and an amend was actually attempted). Canonical field definition lives in `AGENTS.md` *Per-phase additional fields*.
- `rerunConditionsChecked`— `true` (re-run conditions checked per `when-to-re-run-sweep.md`) or `false` for subsequent review-targeting pushes; or one of the documented sentinel values for the "doesn't apply" cases — `n/a-first-push` (this is the first review push, no prior sweep to re-run-check) or `n/a-sandbox-exit` (push exited at the sandbox pre-check). The canonical field definition + sentinel contract live in `AGENTS.md` *Per-phase additional fields*; both sentinels are predicate-complete (a strict reader MUST treat them as satisfying the field).
- `pushCredentialsVerified` — outcome of *Pre-check 0* above (mechanism-aware §4.2 verification). One of `yes` / `user-confirmed-unverifiable` / `blocked`. **Recorded for EVERY push including sandbox-exits** (no `n/a-sandbox-exit` sentinel for this field — credentials must be verified for sandbox pushes too). Canonical field definition lives in `AGENTS.md` *Per-phase additional fields*. A `blocked` value fails the readiness gate.
- `preCreationReviewStatus` — outcome of Step 5 above (§2D pre-PR-creation review per `pre-pr-creation-review.md`). One of `READY-pending-user-approval` / `READY-re-emitted-after-user-approval` / `BLOCKED-<reason>` / `n/a-sandbox-exit` (when this push exited at the sandbox pre-check). A `BLOCKED-*` value fails the readiness gate AND blocks the PR-creation tools enumerated in §2D G6.

Read these back from canonical session todos (per `AGENTS.md` *Phase-state tracking convention*) when declaring "ready"; do NOT infer from memory.

### Evidence-gate output before declaring "ready"

Print the state-predicate read-back as a structured chat block before claiming ready — the 11 predicate fields PLUS the `sandboxPriorExposureConfirmation` informational field (12 lines total in the block; the field set is referred to as the "11-field state predicate" in `AGENTS.md`, and the sandbox-confirmation field is the always-present informational twelfth). This is the **documented carve-out from the standard evidence-gate "zero-count justification" requirement** (per `multi-model-review/evidence-gate-spec.md` — state read-back prints state verbatim; there is no audit-count concept here).

```
Pre-PR-push state read-back: ready=<yes | no with blocker summary>.
- isFirstReviewExposurePush: <true | false>
- remoteExposureExists: <true | false>
- baseRef: <e.g., origin/main>
- baseSha: <40-char SHA at sweep time>
- sweepHeadSha: <40-char SHA at sweep time>
- perCommitAuditCoverage: { <SHA>: <done | skipped-with-reason | not-run>, ... } — must be `done` or `skipped-with-reason` for every commit
- branchWideSweepStatus: <one of 8 enum values per AGENTS.md Phase-state tracking convention>
- cleanupBucketOutcomes: <list of (bucket, commit-sha, amend-safety-result) tuples; empty when no cleanup>
- rerunConditionsChecked: <true | false | n/a-first-push | n/a-sandbox-exit>
- pushCredentialsVerified: <yes | user-confirmed-unverifiable | blocked>
- preCreationReviewStatus: <READY-pending-user-approval | READY-re-emitted-after-user-approval | BLOCKED-<reason> | n/a-sandbox-exit>
- sandboxPriorExposureConfirmation: <confirmed-private | denied-or-unsure | not-needed>
```

Any "ready" claim that lacks this structured output is a workflow violation per `AGENTS.md` cross-cutting findings audit rule. Re-confirm every field by reading session todos before emitting — values inferred from memory are NOT acceptable.

## When the user explicitly skips a pre-PR-push step

Per the User-skip policy:

1. Warn in one sentence: *"Skipping the branch-wide sweep means I cannot certify the branch as review-ready under this repo's workflow."*
2. Record the skip with the specific step skipped.
3. The "ready to push" message must explicitly enumerate which steps were skipped.
4. Skipping the branch-wide sweep on the first push intended for review is a **safety-critical skip** — re-confirm with the user before proceeding.

## Next phase

After the PR is open and review comments arrive, proceed to `post-pr-review.md`.
