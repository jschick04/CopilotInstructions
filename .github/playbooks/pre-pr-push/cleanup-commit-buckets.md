# Playbook: Pre-PR-push / Cleanup commit buckets

## Purpose

After the branch-wide sweep produces changes, decide HOW to commit them. There are three buckets — pick the **strictest matching one**. Bucket choice depends on whether any rename-first action crossed interface / implementation boundaries, and on whether the branch has already been pushed (the amend-safety invariant).

## Hard gates

- Strictest matching bucket selected (do not pick a looser one because it's faster).
- Amend-safety invariant respected (no silent force-push of an amend on a branch others may have pulled).
- Search-first rule from `AGENTS.md` §3.6 honored before any rename is amended into a "small" or "local" bucket.

## Intake questions

Bundle these in one prompt:

1. **What did the sweep change?** Comment-only deletions / a symbol rename / both? If renames: how many files touched and does any rename cross an interface or change a signature?
2. **Has this branch been pushed already?** And if yes — only to a personal sandbox no one else watches, OR to a feature branch / draft PR / shared branch that someone else may have pulled?

## The three buckets

Pick the **strictest** (numbered most-strict to least-strict — bucket 3 is strictest). When in doubt, escalate one bucket up.

### Bucket 1 — No renames anywhere

**Criteria:** Sweep changes are comment-only deletions / re-wordings / additions. **Zero** symbol renames anywhere in the diff.

**Action:**

- Amend the changes into the final work commit.
- Run `post-code-change.md` step 1 (import / using hygiene) on the touched files.
- Run `post-code-change.md` step 6 (build + tests).
- Run `pre-commit.md` (show diff, get approval).

This is the lightest bucket. Use only when truly nothing renamed — even a single symbol rename disqualifies this bucket; escalate to bucket 2 (single-scope) or bucket 3 (cross-boundary).

### Bucket 2 — Single-scope rename, no boundary crossings

**Criteria:** Exactly one rename (or a tightly-related cluster of renames), confined to one file or a small same-package cluster, that does NOT cross an interface / implementation boundary, and does NOT change any signature.

**Action:**

- Run a **full-repo grep for the old identifier** across every relevant file type (per `AGENTS.md` §3.6 search-first for renames and refactors). Examples of where to grep:
  - All language-specific source extensions (`.cs`, `.razor`, `.razor.cs`, `.cshtml`, `.ts`, `.tsx`, `.py`, `.go`, `.cpp`, `.h`, `.java`, etc.)
  - JSON / YAML config files (the symbol may appear as a string key or value)
  - JSON converter switch cases / discriminator maps
  - XAML / HTML / Markdown
  - Test projects + test fixtures
  - Doc comments
  - Trace / log strings
- Confirm "0 matches" before amending.
- **Any non-zero grep hit disqualifies this bucket.** Escalate to bucket 3 (or ask the user).
- If grep is clean: amend into the final work commit and run the same post-amend steps as bucket 1 (import hygiene + build + tests + diff approval).

### Bucket 3 — Large or cross-boundary

**Criteria:** Spans many files, OR the rename-first protocol triggered any symbol rename that:

- Crosses an interface / implementation boundary, OR
- Affects a signature, OR
- Otherwise has cross-file caller implications.

**Action:**

- Commit it **separately** (do NOT amend into the work commit).
- Run the **full** workflow on the cleanup commit: `pre-implementation.md` → `post-code-change.md` (especially the multi-model review at step 2 — the cross-file rename consistency rules in `AGENTS.md` §3.6 are exactly what step 3 *Anti-anchoring rules* asks the reviewer panel to check) → `pre-commit.md`.

This is the strictest bucket because cross-boundary renames are the highest-risk class of comment-cleanup change. The multi-model review pass is non-negotiable here.

## Commit-message examples (apply to whichever bucket)

Apply the standard `AGENTS.md` §2 single-line commit message rules. Examples specific to cleanup commits:

| Verdict | Message |
| --- | --- |
| ✅ | `Drop restating-code comments from upgrade pipeline` (hygiene-only) |
| ✅ | `Rename _flag → _hasOpenedRecoveryDialog and drop comment` (rename-driven) |
| ❌ | `cleanup: drop comments` (Conventional-Commit prefix forbidden) |
| ❌ | Any message followed by `Co-authored-by:` (trailer forbidden) |

## Amend-safety invariant

"Amend the final work commit" above (buckets 1 and 2) assumes the branch is NOT yet under review on a shared remote. The matrix below is the full force-push approval gate — apply by the recorded booleans (`isFirstReviewExposurePush`, `remoteExposureExists` — see `pre-pr-push.md` *Two independent state booleans*). The gate fires **lazily** — only at the moment a history-rewriting operation (amend, rebase, force-push) is about to be applied, NOT preemptively at intake.

| `isFirstReviewExposurePush` | `remoteExposureExists` | Amend behavior |
| --- | --- | --- |
| true | false | **Silent amend is safe.** Brand-new branch; no prior remote to disrupt. |
| true | true | **Conditional sandbox exemption.** Before any history-rewriting amend, ask the one-question sandbox-privacy confirmation: *"was the prior sandbox push truly personal/unwatched, and are you sure no one else pulled it?"* On **yes/private/unwatched** → silent amend is safe; on **no/unsure** → use the explicit force-push approval choices below (do NOT remap the recorded booleans; do NOT skip Step 2 first-review sweep; do NOT enter Step 4 `when-to-re-run-sweep.md`). Record the answer in `sandboxPriorExposureConfirmation` (per `AGENTS.md` *Per-phase additional fields*). |
| false | true | **Never silently amend.** Branch is already under review. Use the explicit force-push approval choices below. |
| false | false | Unreachable in practice (the pre-PR-push pre-check exits at this combination). If reached, treat as `(false, true)` and ask the user. |

**Explicit force-push approval choices** (used by `(false, true)` always, and by `(true, true)` on a no/unsure sandbox confirmation). Ask the user (`ask_user`) to choose one:

1. **Force-push the amend.** Acceptable on a draft PR or feature branch the user owns — but the user must confirm no one else has it pulled.
2. **Add a separate hygiene commit instead.** Always safe.
3. **Defer the hygiene to the next push cycle.** Record the deferred sweep in canonical session todos (per AGENTS.md Phase-state tracking convention).

The pre-push pass is designed to run BEFORE the first push intended for review (PR-opening, request-for-review, or pushing to a shared branch others may pull from). When that timing held AND prior sandbox exposure was truly private, amend is safe; otherwise the explicit choices above apply.

## Recording cleanup outcomes

After cleanup commits are made (any bucket), record in the pre-PR-push phase-state record (per `AGENTS.md` Phase-state tracking convention):

- `cleanupBucketOutcomes` — for each cleanup commit: bucket chosen (1 / 2 / 3), reason, and whether amend-safety required force-push approval.
- `branchWideSweepStatus` — set to `done-cleanup-committed` (initial sweep cycle) or `rerun-done-cleanup-committed` (re-run sweep cycle) per the canonical enumeration in AGENTS.
- `sandboxPriorExposureConfirmation` — `confirmed-private` / `denied-or-unsure` / `not-needed`. Written when the `(true, true)` conditional sandbox-exemption gate fires AND an amend was actually attempted; otherwise leave as `not-needed`. Canonical field lives in `AGENTS.md` *Per-phase additional fields*.

## What "strictest" means

When the diff has both comment-only changes AND a rename:

- Pure comment-only changes (no rename anywhere): bucket 1.
- Exactly one rename (or a tight cluster), contained in one file, doesn't cross an interface or change a signature, full-repo grep returns 0 hits: bucket 2.
- Anything with cross-file caller implications, cross-package scope, or signature changes: bucket 3.

When in doubt, ask the user via `ask_user` before picking. The cost of a wasted multi-model review is much smaller than the cost of a regressed rename.

## Next sub-file

If more pushes will happen on this branch (review-response amends, post-merge pushes, rebases) → `when-to-re-run-sweep.md`.
