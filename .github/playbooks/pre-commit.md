# Playbook: Pre-commit phase

## Purpose

Show the diff to the user, get explicit approval, confirm who handles the commit, and record the commit per the project's commit-message rules. Fires after `post-code-change.md` clears (build + tests + reviewer consensus + verify-fix all green).

## Hard gates (also in `AGENTS.md`)

- Diff shown to user; explicit approval received.
- **Commit author identity verified per `AGENTS.md` §4.1** — both effective config (`git config --show-scope --show-origin --get user.name` / `user.email`) AND `git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT` resolve to a non-empty human identity (not a disallowed automation identity); for `--amend` / `cherry-pick` / `rebase` / `am`, the preserved author + committer on the target commit are ALSO not disallowed automation identities. On missing / disallowed: prompt the user via `ask_user` (Step 3a below); write `--local` by default; promote to `--global` ONLY on explicit user opt-in.
- Commit ownership confirmed (user vs agent) via `ask_user` — prompt MUST display the resolved `<user.name> <<user.email>>` + scope AND use the literal `the agent` / `you (the user)` actor labels (no bare `I` / `me` / `you`). Step 3b below has the canonical form schema.
- Single-line commit message; no Conventional-Commit prefix; no `Co-authored-by` trailer; no body / footer.
- Stage only touched files (`git add <path>` — never `git add .`).
- **Comment audit on staged diff** — before emitting the `PRE-COMMIT GATE PASSED` block, scan the staged additions (`git diff --cached --diff-filter=AM`) for newly-added multi-line `<summary>` / `<remarks>` XML doc blocks (3+ lines of `///`), multi-line razor comments (`@* ... *@` spanning 2+ lines), and multi-line `/* ... */` comments (3+ lines) in `.cs` / `.razor` / `.css` / `.js` / `.ts` files. Each such block must be either justified inline as a one-line why-comment OR removed before commit. The block's `comment_audit:` field (Step 3 schema) records the count of multi-line blocks remaining after the audit + the rationale for any kept ones. The audit is enforcement of the system-prompt rule "Only comment code that needs a bit of clarification" at commit-time rather than panel-time (where the rule is technically catalogued but never fires on agent output because panels review specs, not implementations).
- **`PRE-COMMIT GATE PASSED` block emitted in the current turn** before any `git commit` tool call — §1B refuses `git commit` without this block (mirrors §1A's `PANEL CONVERGED` enforcement at the implementation boundary and §2B's `POST-CODE-CHANGE LEDGER` enforcement at the staging boundary).
- **A panel `READY` verdict (pre-implementation, pre-PR-creation, or any other panel slot) does NOT satisfy this gate on project (non-instruction) repos.** Panel review is technical; this gate is user review. Both are independent and both must pass. Chaining panel `READY` into a commit-producing tool call (`git commit`, `--amend`, `cherry-pick`, `rebase` replay, `am`, etc.), `git push`, or `gh pr create` without an intervening `ask_user`-based diff-approval step is a process violation. This rule does not modify the existing `review-workflow-gates.md` §1B project-vs-instruction-repo asymmetry. Full rule in `pr-quality-gate/panel-policy.md` §"User diff-approval after panel READY".
- **Pre-PR-create draft-state ask** — before any `gh pr create` (or equivalent PR-creation tool call), the agent MUST `ask_user` whether the PR should be created as `draft` or `ready for review`. The default option in the form should match the user's prior session-wide preference if one was set; otherwise default to `ready`. Recorded in the `pr_creation:` field of the `PRE-COMMIT GATE PASSED` block (see Step 3 schema) — `pr_creation: deferred` if this commit is not a PR-creation point; `pr_creation: draft` / `pr_creation: ready` if it is.

## `PRE-COMMIT GATE PASSED` block — required emission

Before any `git commit` (including `git commit --amend`, `git cherry-pick`, `git rebase`-driven commit replay, or any other tool call that produces a new commit object), the agent MUST emit a literal block in the **current turn** that records the outcome of each pre-commit gate. The block must appear in the same turn as the commit tool call. Per §1B, the absence of the block forbids the tool call — no rationalization (e.g., "the diff was approved a few turns ago", "the message is obvious from context", "this is just a small amend") is acceptable.

### Block format

```
PRE-COMMIT GATE PASSED
  diff_shown: yes (turn <N>)
  diff_approved: yes (turn <N+M> user response: "<verbatim approval phrase>")
  author_identity: <name> <<email>> (scope: <local | global | env-override>)
  commit_ownership: agent | user
  proposed_subject: "<single-line subject — exact string the agent will pass to git commit -m>"
  subject_approved: yes (turn <K> user response: "<verbatim approval phrase or 'edited to: ...'>")
  format_check:
    single_line: yes
    co_authored_by_trailer: no
    body: no
    conventional_commit_prefix: no
    subject_length_chars: <integer>
  comment_audit:
    multi_line_blocks_added: <integer count of newly-added 3+ line summaries/remarks/razor `@*...*@`/CSS `/* */` blocks>
    multi_line_blocks_kept_with_rationale: <integer; each kept block requires a one-line why-justification documented in the commit's review thread or this block>
    rule_source: "system-prompt 'Only comment code that needs a bit of clarification' + panel-policy.md §System-prompt-rule enforcement"
  pr_creation: deferred | draft | ready
  staged_files:
    - <explicit relative path 1>
    - <explicit relative path 2>
    - <... — must enumerate ALL staged files; "git add ." / "-A" / "--all" are forbidden per §0>
```

### Field requirements

- **`diff_shown` / `diff_approved`** — record the actual turn numbers (or message indices) in the current conversation. If the diff was shown but never explicitly approved by the user, `diff_approved: no` MUST appear and the commit MUST NOT proceed.
- **`author_identity`** — verbatim output of `git var GIT_AUTHOR_IDENT` (name + email). For amend / cherry-pick / rebase operations, the preserved author on the replay target must ALSO be verified to be a non-automation identity per `AGENTS.md` §4.1; that verification result goes in a separate `replay_author_identity:` line.
- **`commit_ownership`** — must be either `agent` or `user`. If `user`, the agent must STOP at this gate and let the user run `git commit` themselves — no chain-through to `git push`.
- **`proposed_subject`** — the EXACT string that will be passed to `git commit -m`. Not a summary; the literal value.
- **`subject_approved`** — record the user response that approved the proposed subject. If the user edited the subject during approval, `proposed_subject` must reflect the edited version, and `subject_approved` should quote the edit.
- **`format_check`** — five boolean sub-fields. Any `no` on `single_line` / `subject_length_chars > 72` / etc. that contradicts the playbook's format rules MUST cause the agent to revise the message before re-emitting the block.
- **`comment_audit`** — runs after staging, before block emission. Run `git diff --cached --diff-filter=AM -- '*.cs' '*.razor' '*.css' '*.js' '*.ts'` and scan the added lines (those starting with `+` excluding the file-header `+++`) for: (a) consecutive 3+ lines beginning with `///` (multi-line XML doc summary/remarks); (b) razor `@*` openers paired with a `*@` closer on a different line (multi-line razor comment); (c) `/*` openers paired with a `*/` closer ≥ 2 lines away (multi-line block comment). For each match, either remove it OR document a one-line why-rationale (justified examples: catch-block reason for swallow, license headers, non-obvious algorithmic choice with cited spec section). `multi_line_blocks_added` = total matches found; `multi_line_blocks_kept_with_rationale` = subset retained with rationale. If `multi_line_blocks_added > multi_line_blocks_kept_with_rationale` and the un-justified blocks haven't been removed, the agent MUST revise the staged diff before emitting the block. This gate is the commit-time enforcement layer for the system-prompt comment rule that the panel review layer cannot reach (panels review specs before implementation; this audit catches what gets typed during implementation).
- **`pr_creation`** — three valid values:
    - `deferred` — this commit is not the PR-creation commit (no `gh pr create` happening in the same turn). The draft-state question is asked at the moment `gh pr create` is invoked, not at every prior commit.
    - `draft` — `gh pr create --draft` was approved by the user via `ask_user` in this session for this PR.
    - `ready` — `gh pr create` (no `--draft` flag) was approved by the user via `ask_user` in this session for this PR.
  The `ask_user` prompt MUST present both options (`draft` / `ready`) and record the user's response verbatim in the `PR-CREATION GATE PASSED` block (see `pr-creation.md` for the full schema if one exists, else this `pr_creation` field captures the decision inline). For amends/force-pushes to an EXISTING PR, `pr_creation: deferred` is correct because no new PR is being created.
- **`staged_files`** — enumerated list. `git add .`, `git add -A`, `git add --all` are forbidden per §0; the staged files list must come from an explicit `git add <path>` per file.

### Falsification is a higher-severity failure than skipping

If the block claims a gate was satisfied (e.g., `diff_approved: yes (turn 42)`) but the conversation record shows it was not, that is a more severe violation than omitting the block entirely. The agent MUST self-report falsified block entries proactively in the next turn and propose remediation (typically: revert the commit, restore working tree, re-run the gates).

### Skip conditions (none apply unless explicitly documented this session)

- The user has stated in THIS session: "skip the pre-commit block" or equivalent unambiguous waiver for a specific commit or range. The waiver MUST be recorded in the session state with the affected commit identifier.
- `git commit --amend --no-edit` that is mechanically restoring a previously-emitted committer timestamp without changing tree or message (e.g., immediately after a successful `git rebase --continue`) — the original commit's `PRE-COMMIT GATE PASSED` block is preserved by reference.

The trivial-mechanical-fix carve-out from the §1B project-repo gate does NOT apply to the `PRE-COMMIT GATE PASSED` block — the block exists precisely because "obvious mechanical fixes" are the rationalization path through which Co-authored-by trailers, multi-line bodies, and missed message approvals slipped historically.

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

#### Show the diff and wait for approval

Before ANY `git add` or `git commit` (including `--amend`), the agent MUST:

1. Show the diff to the user (`git --no-pager diff` for unstaged changes, or `git --no-pager diff --cached` if already staged).
2. Wait for explicit user approval ("approved" / "looks good" / "go ahead" / equivalent).
3. Only then proceed to staging and committing.

This applies to fresh commits, amends, fixups, and any other commit-producing operation. The user must see every change before it enters the git history. Silence is not approval.

#### Confirm the commit message

Before staging or running `git commit`, the agent MUST present the proposed commit message to the user via `ask_user` and wait for explicit approval. The agent does NOT run `git commit` until the user has seen and approved the exact message text. This is a **separate prompt** from the ownership prompt in step 3b — never bundle them.

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
