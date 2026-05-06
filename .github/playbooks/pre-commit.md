# Playbook: Pre-commit phase

## Purpose

Show the diff to the user, get explicit approval, confirm who handles the commit, and record the commit per the project's commit-message rules. Fires after `post-code-change.md` clears (build + tests + reviewer consensus + verify-fix all green).

## Hard gates (also in `AGENTS.md`)

- Diff shown to user; explicit approval received.
- Commit ownership confirmed (user vs agent).
- Single-line commit message; no Conventional-Commit prefix; no `Co-authored-by` trailer; no body / footer.
- Stage only touched files (`git add <path>` — never `git add .`).

## Intake questions

Bundle these in one prompt:

1. Will you commit / push, or do you want me to? (Default to user committing — many of their workflows involve manual review, splitting, or amending before push.)
2. **If agent commits:** confirm the proposed commit message before I run it.

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

### 3. Confirm commit ownership

Ask explicitly via `ask_user`:

> Will you handle the commit and push, or do you want me to?

Default to the user. Many of their workflows involve manual review, splitting commits, amending before push, or other prep that the agent shouldn't pre-empt.

### 4. If the agent commits

#### Stage only touched files

```powershell
git add <path1> <path2> <path3>
```

Never `git add .` or `git add -A` — those pick up unrelated stray files.

#### Commit message rules (from `AGENTS.md` §2)

- **Single line only.** No body, no footers, no trailers of any kind.
- **Explicitly suppress the auto-injected `Co-authored-by: Copilot` trailer.** When invoking `git commit`, use `-m "<message>"` only — do not pass any additional `-m` flags, do not let any tool append a trailer, and do not add a blank line followed by `Co-authored-by:`. The commit message body must contain the single line and nothing else.
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
- `perCommitAuditCoverage` entry for the new commit SHA — `done` (audit ran, regardless of whether it modified the diff before the commit landed) or `skipped-with-reason` per User-skip policy. The canonical readiness enum lives in `AGENTS.md` *Per-phase additional fields* — `done` / `skipped-with-reason` / `not-run`; do NOT introduce additional values here. If the audit modified the diff before commit, note that detail in the entry's description text (free-form), keeping `status` itself canonical. Pre-PR-push reads back the accumulated map; if this entry is missing, that commit will appear as `not-run` and block the readiness gate.

This feeds into pre-PR-push amend-safety logic and the "ready to push" check.

## Next phase

If the user is preparing to push for review (open PR, request review, or push to a shared branch others may pull from), proceed to `pre-pr-push.md`.

If the commit is just an intermediate WIP and more work is coming, return to the next pre-implementation cycle.
