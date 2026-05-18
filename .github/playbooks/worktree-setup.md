---
name: worktree-setup
description: Use when user wants to create, restructure, or repair a git worktree using the single-root + hidden-bare-repo + sibling-checkouts layout. Also use for stacked-PR worktree creation when current work is review-blocked but follow-up work is ready.
triggers:
  - "set up worktree"
  - "hidden bare repo layout"
  - "create a worktree for"
  - "stacked worktree for"
  - "restructure my worktree"
  - "fix my worktree layout"
---

# Playbook: Worktree setup

## Purpose

Create or restructure a git worktree using the user's preferred **single-root + hidden-bare-repo + sibling-checkouts** layout. Fires when the user asks to set up a new worktree, parallelize work on multiple branches, or restructure an existing repo to match this layout.

## Hard gates

- **Restructure path only:** existing checkout verified clean (no uncommitted changes, no stashes, no local-only branches that aren't pushed, no in-progress rebase / merge / cherry-pick) BEFORE any destructive step. Surface custom hooks (`.git/hooks/*` that aren't `*.sample`) and non-standard config in `.git/config` to the user before destroying the old `.git`.
- **No silent destruction:** the old `.git` (renamed to `.old`) is kept until end-to-end verification of the new layout (worktree `git status` from each worktree returns clean). Only delete `.old` AFTER verification.
- **Bare clone source:** the bare repo MUST be created from the origin URL (not from the local `.git`) so refspecs and remote tracking are correct. Confirm `remote.origin.fetch` is `+refs/heads/*:refs/remotes/origin/*` after the bare clone; set explicitly if not, then `git fetch origin` to populate `refs/remotes/origin/*` before any `git worktree add`.
- **Worktree gitdir links repaired after move:** after moving the temporary bare repo into its final `.git` location, run `git worktree repair` on each worktree before any further git operations.

## Intake questions

Bundle these in one prompt unless answers cascade:

1. Is this a NEW worktree against an existing layout (just `git worktree add`), or a RESTRUCTURE of an existing non-bare clone into the layout?
2. What's the projects root? (e.g. `E:\Projects\`, `C:\dev\`)
3. What's the repo name? (becomes the parent folder name)
4. Origin URL for the bare clone (only needed for restructure / first setup).
5. Which branch / ref does the new worktree check out?
6. **Restructure only:** has the existing checkout been verified clean (no uncommitted changes, no stashes, no local-only branches not pushed, no in-progress rebase/merge/cherry-pick)? If you don't know — STOP and check before proceeding. Custom hooks or non-standard config? Surface those before destroying the old `.git`.

## Procedure

### Layout

For a repo named `RepoName` under a `<projects-root>`:

- `<projects-root>\RepoName\.git\` — the **bare** repo (despite the `.git` name; `core.bare = true`). Single source of truth for all refs; all worktrees share its object database.
- `<projects-root>\RepoName\main\` — worktree of the default branch.
- `<projects-root>\RepoName\<branch-leaf>\` — one folder per additional worktree, named for the **leaf segment** of the branch (the part after the last `/`, e.g. `feature-x` for branch `user/feature-x`).

The `<projects-root>\RepoName\` directory contains exactly: the hidden `.git` bare repo plus one subfolder per worktree — no loose files, no nested checkouts.

### Why hidden `.git` instead of a sibling `RepoName.git\`

The user prefers a single-root layout so `RepoName` remains the one project folder visible to file managers, IDE workspace lists, and recent-folder menus. The hidden `.git` keeps the bare data discoverable to git but out of the way visually.

### NEW worktree on an existing layout

```powershell
# from anywhere
git -C <projects-root>\RepoName\.git worktree add <projects-root>\RepoName\<branch-leaf> <branch-or-ref>

# verify
git -C <projects-root>\RepoName\<branch-leaf> status
```

### RESTRUCTURE: introducing the layout to an existing non-bare clone

1. Verify the existing checkout is clean (see intake question 6). If unclean, ASK before proceeding.
2. Check for custom hooks (`.git/hooks/*` that aren't `*.sample`) and non-standard config in `.git/config`. If anything custom is present, surface it to the user and ask whether to migrate it to the new bare repo before destroying the old `.git`.
3. Clone bare from the **origin URL** (not from the local `.git`) — a fresh clone produces correct refspecs and remote tracking out of the box. Clone to a temporary sibling location first (e.g. `<projects-root>\RepoName.git`); you'll move it into the final `.git` location after the parent folder exists.
4. After the bare clone, confirm `remote.origin.fetch` is the standard `+refs/heads/*:refs/remotes/origin/*` (set it explicitly if not), then run `git fetch origin` so `refs/remotes/origin/*` exists for `git worktree add`.
5. Move the existing checkout aside to a `.old` sibling (do NOT delete it yet), create the new `<projects-root>\RepoName\` parent folder, add the worktrees against the temporary bare repo (`git -C <projects-root>\RepoName.git worktree add <projects-root>\RepoName\<branch-leaf> <branch-or-ref>`), then verify each worktree.
6. Move the temporary bare repo into its final location: `Move-Item <projects-root>\RepoName.git <projects-root>\RepoName\.git`. The worktrees' `.git` files now contain stale gitdir paths.
7. Run `git -C <projects-root>\RepoName\.git worktree repair <each-worktree-path>` to rewrite the per-worktree `.git` gitdir links to the new bare location. Verify with `git -C <worktree> status` from each worktree.
8. Optionally set per-branch upstream tracking (`git -C <worktree> branch --set-upstream-to=origin/<branch> <branch>`) so plain `git push` / `git pull` work without `-u`.
9. Verify with `git worktree list` from inside the bare (or any worktree) and `git status` from each worktree.
10. Only after end-to-end verification, delete the `.old` folder.

### `git worktree add` from a bare repo and existing local branches

When the bare repo is freshly cloned, the initial fetch sometimes auto-creates local branches that mirror remote-tracking refs. If `git worktree add <path> -b <branch> origin/<branch>` fails with `a branch named '<branch>' already exists`, drop the `-b` flag and check it out directly: `git worktree add <path> <branch>`. Then set upstream tracking explicitly per step 8.

## When NOT to apply the layout automatically

If the existing repo has local-only branches, custom hooks, uncommitted work, in-progress operations, or non-standard config that the user hasn't explicitly agreed to discard, ASK before restructuring. Don't silently re-clone over a checkout that may carry state the user cares about.

## Per-worktree shell sessions

When starting work in a worktree, `cd` into the worktree subfolder before running git commands. The bare repo at `<projects-root>\RepoName\.git` is for `git worktree add`/`remove`/`repair` operations only — daily work happens inside the worktree subfolder. Note that `<projects-root>\RepoName\` itself is **not** a worktree — running `git status` from there will error because the folder's `.git` is a bare repo with no working tree.

## Caveat — tools that auto-detect `.git`

Some tooling (file watchers, search indexers, some IDE git integrations) walks up to find `.git` and assumes a non-bare repo. With this layout, `<projects-root>\RepoName` has a `.git` directory but no working tree. If a tool misbehaves when opened against the parent folder (rather than against a specific worktree), open it against the worktree subfolder instead.
