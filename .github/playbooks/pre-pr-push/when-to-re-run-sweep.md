# Playbook: Pre-PR-push / When to re-run the sweep

## Purpose

After the branch-wide sweep has run once, more pushes may happen on the branch — review-response amends, post-merge pushes, rebases, additional scope. Some of these re-trigger the full branch-wide sweep; others only require per-commit hygiene on the new amend. This file is the deterministic ruleset for that decision.

## Hard gates

- Re-run conditions checked before any push subsequent to the initial sweep.
- "Out of scope at initial sweep" set reconstructed from the recorded sweep SHAs (NOT later-resolved symbolic refs).
- If sweep SHAs are unavailable (older branches, operator miss, session loss), conservatively re-run the branch-wide sweep (or ask the user).

## Intake questions

Bundle these in one prompt:

1. **What changed since the last sweep?** Review-response amends only / new feature scope / new files / merge or rebase from base / conflict resolution / multiple of these?
2. **Are the recorded sweep SHAs available** (resolved base SHA + sweep HEAD SHA from the initial sweep)? If not, treat reconstruction as impossible and conservatively re-run.

## Re-run conditions — RE-RUN the branch-wide sweep if any apply

### Condition 1 — New feature / scope work

Re-run if you added new feature / scope work beyond the original PR scope, new files, or non-review-driven commits.

### Condition 2 — Conflict resolution touched comments or already-touched hunks

Re-run if conflict resolution from a merge / rebase added or modified comments, OR if it changed any hunk in a file that already appeared in the branch-wide comment set.

### Condition 3 — Post-sweep change brought a previously-out-of-scope comment back into scope

Re-run if any post-sweep change (merge, rebase, OR ordinary amend) changed code in the same hunk or immediate surrounding declaration / block / function as any pre-existing comment that was out of scope during the initial sweep — whether because the comment lives in a previously-untouched file, OR in a previously-untouched region of an already-touched file.

The branch now touches the surrounding code, putting those pre-existing comments back in scope per the "out of scope unless this branch also touched the surrounding code" rule from `branch-wide-sweep.md`.

**Definition:** "Out of scope during the initial sweep" means the comment's surrounding code does NOT appear in the diff `<sweep-base-SHA>..<sweep-HEAD-SHA>` (the resolved SHAs recorded at sweep time per `branch-wide-sweep.md` step 1 — NOT later-resolved symbolic refs like `origin/main`, which may have advanced). Per-comment metadata is not required.

## Do-NOT-re-run conditions

### Condition A — Ordinary review-response amends

Do NOT re-run for ordinary review-response amends — provided they do NOT add new files, do NOT expand scope beyond the original PR, and do NOT meet any re-run condition above.

Per-commit audit + rename-first on the new comment + its immediate surroundings suffices for the ordinary case.

### Condition B — Clean merge from base with no comment touches

Do NOT re-run for a clean merge / rebase from main with no comment touches and no scope expansion.

## Force-push amends in response to PR review — special rules

Force-push amends in response to PR review do NOT re-trigger the branch-wide sweep. The per-comment Comments-rule audit is still non-skippable for every new comment line you add during review-response amends.

**Rename-first also still applies** to any new / modified comment and its immediately surrounding identifiers — but if satisfying rename-first would widen scope beyond the immediate amend (e.g. the "better name" affects callers, an interface signature, or an implementation in another file), STOP treating it as an ordinary review-response amend.

Either:

1. **Ask the user** how to proceed, OR
2. **Widen the change** to cover every file in the rename chain (interface, abstract base, every implementation, every caller, every lambda that closes over the symbol — per `AGENTS.md` §3.6) and run the **full** workflow on that widened diff (`pre-implementation.md` → `post-code-change.md` → `pre-commit.md`).

A partial re-sweep limited to the file(s) in the immediate amend is NOT sufficient when the rename has cross-file caller implications.

## Decision quick-reference table

| Situation | Re-run branch-wide sweep? |
| --- | --- |
| Ordinary review-response amend, no new files, no scope expansion | NO (per-commit audit only) |
| Clean merge / rebase from base, no comment touches | NO |
| Added new feature / scope work beyond original PR | YES |
| Added new files | YES |
| Conflict resolution added / modified comments | YES |
| Conflict resolution changed a hunk in a file already in the comment set | YES |
| Post-sweep change touched code adjacent to a previously-out-of-scope comment | YES |
| Sweep SHAs unavailable (lost canonical session todos record, per AGENTS.md Phase-state tracking convention) | YES (conservatively) — or ask user |
| Force-push amend introduces a rename that crosses interface / impl boundary | Widen the amend OR ask user — partial re-sweep insufficient |

## After a re-run

If you re-run the sweep:

- Capture **new** sweep SHAs (`<NewBaseSha, NewHeadSha>`) and overwrite the recorded values in canonical session todos (a fresh `phase-state-<phase>-<yyyymmddHHMMSS>` record per AGENTS.md Phase-state tracking convention; older records remain for audit). The previous sweep's SHAs are no longer the "out of scope at initial sweep" baseline once the branch state has materially changed.
- Apply `cleanup-commit-buckets.md` to any changes the re-run sweep produces.
- Record `branchWideSweepStatus` per the AGENTS canonical enumeration: `rerun-done-clean` (re-run produced no changes), `rerun-done-cleanup-committed` (re-run produced cleanup commits), or `rerun-skipped-with-reason` (user explicitly authorized skipping the re-run per User-skip policy).

## When the re-run conditions check determines no re-run is needed

If the decision quick-reference table above says NO re-run for this push (e.g. ordinary review-response amend with no scope expansion, clean merge / rebase with no comment touches), write a fresh `phase-state-pre-pr-push-<yyyymmddHHMMSS>` record (per `AGENTS.md` *Phase-state tracking convention*) with:

- `branchWideSweepStatus = previously-done-no-rerun-needed`.
- `rerunConditionsChecked = true`.
- **Copy-forward all prior 10-field-predicate values from the most recent pre-PR-push phase-state record** — `baseRef`, `baseSha`, `sweepHeadSha`, `perCommitAuditCoverage`, `cleanupBucketOutcomes`, `pushCredentialsVerified` (re-verify via *Pre-check 0* for THIS push; do NOT blindly copy the prior value — credentials may have changed since the last push). The "most recent record wins" contract (per AGENTS.md *Phase-state tracking convention*) means the new record must be self-contained — omitting these keys would make the readiness predicate fail even though the sweep evidence exists in an older record.
  - **Update the `perCommitAuditCoverage` map for THIS push:** add entries for any new commit SHAs you per-commit-audited. **If an amend rewrote a commit that already had an entry, replace the pre-amend SHA's entry with the post-amend SHA's entry** — the readiness gate looks up commits at current HEAD, so stale pre-amend SHAs satisfy nothing for the current branch state (they remain in older phase-state records as audit history).
- Update the booleans `isFirstReviewExposurePush` and `remoteExposureExists` to reflect THIS push.

The pre-PR-push readiness check will accept the prior sweep's evidence on this basis.

## Reporting the state to the user

Before declaring "ready to push" again, the agent must explicitly state:

- Whether a re-run was needed.
- Which re-run condition triggered (or "none — ordinary amend").
- If re-run: the new sweep SHAs and what changed.

The user gets to see the chain so they can verify the agent didn't silently skip a re-run condition.
