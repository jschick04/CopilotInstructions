# Playbook: Pre-commit phase

## Purpose

Show the diff to the user, get explicit approval, confirm who handles the commit, and record the commit per the project's commit-message rules. Fires after `post-code-change.md` clears (build + tests + reviewer consensus + verify-fix all green).

## Hard gates (also in `AGENTS.md`)

- Diff shown to user; explicit approval received.
- **Commit author identity verified per `AGENTS.md` §4.1** — both effective config (`git config --show-scope --show-origin --get user.name` / `user.email`) AND `git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT` resolve to a non-empty human identity (not a disallowed automation identity); for `--amend` / `cherry-pick` / `rebase` / `am`, the preserved author + committer on the target commit are ALSO not disallowed automation identities. On missing / disallowed: prompt the user via `ask_user` (Step 3a below); write `--local` by default; promote to `--global` ONLY on explicit user opt-in.
- Commit ownership confirmed (user vs agent) via `ask_user` — prompt MUST display the resolved `<user.name> <<user.email>>` + scope AND use the literal `the agent` / `you (the user)` actor labels (no bare `I` / `me` / `you`). Step 3b below has the canonical form schema.
- Single-line commit message; no Conventional-Commit prefix; no `Co-authored-by` trailer; no body / footer.
- Stage only touched files (`git add <path>` — never `git add .`).

## Intake questions

Bundle these in one prompt:

1. Will the agent run the commit on your behalf, or will you (the user) run the commit yourself? (Default: you run the commit — many of your workflows involve manual review, splitting, or amending before push.)
2. **If the agent commits:** confirm the proposed commit message before the agent runs `git commit`.

(Identity-verification questions — when needed — are asked in Step 3a below, separately from this ownership prompt.)

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

  Provide your name and email. The agent will write them to LOCAL repo scope (`git config --local`) — this repo only.
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
      description: "If checked, the agent will also run `git config --global user.name … && git config --global user.email …`. Leave unchecked to keep this identity in this repo only."
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

The agent MUST NEVER guess `user.name` / `user.email` from machine username, GitHub session principal, prior repos on the machine, or any other heuristic — values come from the user's `ask_user` answer.

§4.1 also forbids: `git commit --author="…"`, `git -c user.name=… -c user.email=…` flags, and unauthorized `--reset-author`. `--reset-author` may be used ONLY when the form returns `resetAuthorOnReplay=true` (and only on the corresponding replay command).

**Don't touch signing config.** Do NOT modify `commit.gpgsign`, `gpg.format`, `user.signingkey`, or `gpg.<format>.program`. If signing fails or the signing key looks like an automation key, surface via a separate `ask_user` — never bypass with `--no-gpg-sign` without explicit user approval.

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
          title: "You (the user) — the agent will print the staged diff and the prepared commit message; you (the user) run `git commit` yourself."
        - const: "agent"
          title: "The agent — the agent will run `git commit -m \"<approved message>\"` on your behalf."
      default: "user"
  required: [commitOwner]
```

Default to the user. Many of the user's workflows involve manual review, splitting commits, amending before push, or other prep that the agent should not pre-empt. If the user picks `agent`, proceed to Step 4. If `user`, the agent prints the staged file list, prepared commit message, and the exact `git commit -m "…"` command for the user to run.

**Push-ownership is asked SEPARATELY** in `pre-pr-push.md` *Pre-check 0* (per `AGENTS.md` §4.2). Do NOT bundle commit and push ownership in one prompt.

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
