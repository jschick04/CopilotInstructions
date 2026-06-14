# Playbook: Pre-PR-push / Per-commit micro-hygiene

## Purpose

The per-commit comment audit. Covers ONLY comments added or modified in **the current commit's diff**. Each must have a one-line allowed-case justification per `AGENTS.md` §3.1, or be deleted before the diff is shown to the user. This is non-skippable per commit cycle.

Almost always already done during `pre-commit.md`. This file exists for the case where commits were made without running the audit (fast WIP series, work imported from elsewhere, recovery from an interrupted session) - at pre-PR-push time, audit each unaudited commit before the branch-wide sweep.

## Hard gates

- Every new or modified `//`, `///`, `#`, or `/* */` comment in the commit's diff has a one-line justification matching one of the allowed cases.
- Hard prohibitions deleted on sight.
- C# files with new XML doc on private members: doc deleted (per `csharp.instructions.md`).

## Intake questions

Bundle these in one prompt:

1. Which commit(s) need the audit? (Default: every commit on the branch that has new / modified comments. List commits where it wasn't run during their `pre-commit.md` cycle.)
2. Are there commits you've imported from elsewhere (cherry-pick, rebase from another branch) that I should treat as needing fresh audit?

## Procedure

For each commit that needs auditing:

### 1. Enumerate every NEW or MODIFIED comment line in the commit's diff

```powershell
git --no-pager show --format= <commit-sha> | Select-String '^\+.*(//|///|/\*|#)' | Select-String -NotMatch '^\+\+\+'
```

(Adjust the comment markers per the language - `#` for Python / shell / YAML, `//` and `/* */` for most C-family, `///` for C# / Rust XML / doc comments, `<!-- -->` for HTML / XML / Markdown.)

### 2. For each comment, write a one-line justification

The justification must match one of the three allowed cases from `AGENTS.md` §3.1:

- **non-obvious algorithmic invariant:** *e.g. "k-merge requires inputs already sorted by Timestamp ascending"*
- **external constraint workaround:** *e.g. "Win32: LoadLibraryEx with DATAFILE flag still maps writable on <Win10"*
- **deliberate trade-off the reader would otherwise question:** *e.g. "Monitor lock - ConcurrentDictionary lost on this benchmark"*

**If you cannot write that justification in one short clause, delete the comment.** This audit is non-skippable - running it sometimes catches 100% of the violations the reviewer would have flagged.

### 3. Apply the rename-first protocol

For every new comment, FIRST ask: *"Can a better name on the function / parameter / variable / type carry this fact?"*

- If yes → rename and delete the comment. The rename almost always wins.
- If the rename has cross-file caller implications (crosses an interface / impl boundary, changes a signature) → escalate to the cleanup-commit-buckets decision (see `cleanup-commit-buckets.md`).
- If no → check the comment passes the length cap (≤ 12 words for inline `//` and `#`).

### 4. Hard prohibitions - delete on sight

- Restating the code (`// Bump counter` next to `_counter++`).
- "Why we're about to do this" narration.
- Multi-line `//` blocks explaining design decisions in prose.
- Speculation about future callers / future surfaces.
- Restating contract terms encoded in naming or signature.
- TODO / FIXME / HACK / XXX comments - use the *Pre-existing issues* cross-cutting rule in `AGENTS.md` §1 (`ask_user` to fix now / defer / dismiss) instead.
- C# only: XML doc on `private` members (per `csharp.instructions.md`).

### 5. Apply the deletions / rewrites and re-amend the commit

If the audit modified the commit, amend it. Apply the amend-safety invariant in `cleanup-commit-buckets.md` (the matrix there covers all four `(isFirstReviewExposurePush, remoteExposureExists)` combinations). Two cases that may apply here: (1) `isFirstReviewExposurePush=false` (branch already under review) - never silently amend, use the explicit force-push approval choices; (2) `(isFirstReviewExposurePush=true && remoteExposureExists=true)` - conditional sandbox exemption fires, ask the one-question sandbox-privacy confirmation immediately before the amend (NOT preemptively at intake); on yes, silent amend is safe; on no/unsure, use the explicit force-push approval choices. Record the answer in `sandboxPriorExposureConfirmation` per `cleanup-commit-buckets.md` *Recording cleanup outcomes*.

### 6. Record state

For each commit audited:

- Commit SHA. **If the audit amended the commit, use the post-amend SHA - that is the SHA the pre-PR-push readiness check will look up.**
- Number of comments enumerated.
- Number deleted vs kept (with justification).
- Whether any rename-first cases escalated to cross-file scope.
- **`perCommitAuditCoverage` entry in the pre-PR-push phase-state record** (per `AGENTS.md` *Per-phase additional fields*) - write `{sha: <post-amend SHA>, status: done}` (or `skipped-with-reason` per User-skip policy) for the audited commit. The pre-PR-push readiness gate consumes this map; if the entry is missing, the commit appears as `not-run` and blocks readiness. Use the canonical enum (`done` / `skipped-with-reason` / `not-run`) - do not introduce other values.

## Scope clarification

This is **per-commit**. It only sees comments added / modified in the one commit's diff.

It does NOT cover:

- Pre-existing comments in `<base>` that this commit didn't touch (those are out of scope unless the surrounding code was also touched - see `branch-wide-sweep.md`).
- Drift across multiple commits (later commits adding context that should let earlier comments be deleted via rename-first - that's the branch-wide sweep's job).

The per-commit audit + the branch-wide sweep are **non-overlapping passes**. Do both. Don't try to substitute one for the other.
