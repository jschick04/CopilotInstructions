# Playbook: Pre-PR-push / Branch-wide sweep

## Purpose

The branch-wide rename-first comment sweep. Enumerates ALL comments added or modified in `<base>..HEAD` (across every commit on the branch) and re-applies the `AGENTS.md` §3.1 Comments rules - especially rename-first, which often only becomes obvious after later commits add context that earlier WIP comments don't reflect.

Runs ONCE before the first push intended for review (PR-opening, request-for-review, or pushing to a shared branch others may pull from). Different scope than the per-commit audit - see `per-commit-micro-hygiene.md` for that one. Both passes are mandatory; this is not a choice between them.

## Hard gates

- All comments added / modified in `<base>..HEAD` enumerated and re-evaluated against `AGENTS.md` §3.1.
- Resolved base SHA + sweep HEAD SHA + base ref name **recorded in canonical session todos** (per `phase-state-convention.md` - same `phase-state-<phase>-<yyyymmddHHMMSS>` schema, with the SHAs in the `description` field; the `phase-state-convention.md` fallback chain applies if SQL is unavailable) at sweep time (not later-resolved symbolic refs, which may have advanced).
- C# files: XML doc rules in `csharp.instructions.md` re-applied across the branch.

## Intake questions

Bundle these in one prompt:

1. **Resolve the approved base binding** from the pre-PR-push intake: fetch `<base_remote> <base_branch>`, verify its fetched tip equals `ls-remote <base_url> refs/heads/<base_branch>`, then set `$BaseSha = git merge-base <base_tip_sha> HEAD`. Never use a local `origin/*` ref.
2. **Are there pre-existing comments in `<base>` that this branch's code touches** (e.g. branch added a method body next to an old comment)? Those re-enter scope.
3. **Has any non-review-driven work landed since the last sweep**, if there was one? (New scope, new files, merge / rebase touches.)

## Procedure

### 1. Resolve and record sweep SHAs

Capture the resolved SHAs at sweep start. Symbolic refs are NOT enough - they may advance later, and the re-run logic depends on stable SHA references.

```powershell
$BaseTipSha = <verified ls-remote tip>
$BaseSha = git merge-base $BaseTipSha HEAD
$HeadSha = git rev-parse HEAD
```

Record the binding fields (`phase-state-convention.md`), `baseSha` (`$BaseSha`), and `sweepHeadSha` (`$HeadSha`) in canonical session todos (per `phase-state-convention.md`). The "out of scope at initial sweep" set later will be reconstructed from `git diff $BaseSha..$HeadSha`.

### 2. Enumerate every NEW or MODIFIED comment line across the branch

```powershell
git --no-pager diff $BaseSha..$HeadSha | Select-String '^\+.*(//|///|/\*|#)' | Select-String -NotMatch '^\+\+\+'
```

Adjust comment markers per language. For HTML / XML / Markdown also check `<!-- -->`.

This will be a longer list than the per-commit audit because it spans every commit on the branch. Process every comment - sampling is not allowed (per `AGENTS.md` §3.6 "Comprehensive over sampled").

### 3. Re-apply the §3.1 Comments rules

For each comment:

- **Rename-first protocol** (mandatory). Test with: *"Can a better name on the function / parameter / variable / type carry this fact?"* If yes, rename and delete the comment. **This is the highest-yield rule for the branch-wide sweep** - later commits often add context that makes the rename obvious where it wasn't during the original commit.
- **Hard prohibitions deleted on sight.** Same list as `per-commit-micro-hygiene.md`.
- **Allowed cases must pass the one-line justification test.** If you can't write a clause matching one of the three allowed cases ("non-obvious invariant: X" / "external constraint: Y" / "trade-off: Z"), delete the comment.

### 4. Pre-existing comments - out of scope unless the branch touched the surrounding code

Pre-existing comments already in `<base>`: out of scope unless this branch also touched the surrounding code. In that case re-evaluate them too. Treat "the branch touched the surrounding code" as: the comment's block / function / immediate declaration appears in the `git diff $BaseSha..$HeadSha` output.

### 5. Pick the cleanup-commit bucket

If the sweep modified files, the next step is committing the changes. Fetch `cleanup-commit-buckets.md` and pick the **strictest matching bucket**. Do NOT silently amend across multiple commits without applying the bucket logic - the bucket choice depends on whether any rename-first action crossed interface / implementation boundaries.

### 6. If the sweep finds nothing

The branch is clean to push for the comment-hygiene dimension. Record `branchWideSweepStatus = done-clean` in the pre-PR-push phase-state record (per `phase-state-convention.md`) and move on. The PR is still subject to all other pre-push gates (build, tests, multi-model review on each commit, etc.).

### 7. Record sweep results

Record in canonical session todos (per `phase-state-convention.md`):

- the binding fields, `baseSha`, `sweepHeadSha` (the recorded sweep SHAs).
- Number of comments enumerated.
- Number deleted vs kept (with justification).
- Number of rename-first cases that triggered (and whether any escalated to cross-boundary scope per the cleanup-commit-buckets logic).
- Cleanup commits created (SHAs).
- `branchWideSweepStatus` - write `done-clean` if no cleanup was needed (per Step 6 above), or `done-cleanup-committed` if cleanup commits were created (per `cleanup-commit-buckets.md`). Use `skipped-with-reason` only if the user explicitly authorized skipping the sweep per the User-skip policy.
- `rerunConditionsChecked` - write the documented sentinel `n/a-first-push` (the first review push has no prior sweep to re-run-check, so the field is predicate-complete via this sentinel per `phase-state-convention.md` *Per-phase additional fields*). The pre-PR-push readiness predicate consumes this field; omitting it makes the record fail the pre-PR-push predicate even with the sweep done clean.
- `pushCredentialsVerified` - record the outcome of `pre-pr-push.md` *Pre-check 0* (one of `yes` / `user-confirmed-unverifiable` / `blocked`). This is a required predicate field per `phase-state-convention.md` *Per-phase additional fields*; omitting it fails the readiness predicate.

These are needed by `when-to-re-run-sweep.md` if more pushes happen on this branch.

## Why the branch-wide sweep happens pre-push (not per-commit)

Comments compound across many WIP commits. Running the branch-wide rename-first sweep once on the assembled branch produces a clean surface for reviewers from turn one and avoids tagging every commit with its own hygiene amend. Per-commit hygiene also burned context re-evaluating comments that prior commits' reviews had already approved - folding the branch-wide sweep into one pre-push pass is cheaper.

The per-commit audit + the branch-wide sweep are **non-overlapping passes**. The per-commit audit is for the current commit's diff. The branch-wide sweep is for branch-wide drift and rename-first opportunities surfaced by later commits. Letting obvious violations through every commit and planning to "clean them all up at the end" fails both rules.

## Next sub-file

If the sweep produced changes → `cleanup-commit-buckets.md`.
If the branch is later amended / merged / rebased before the next push → `when-to-re-run-sweep.md`.
