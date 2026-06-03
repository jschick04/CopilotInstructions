---
name: review-workflow-gates
description: Mandatory review workflow gates covering the rubber-duck-then-panel two-stage process, PR review root-cause analysis, scope reduction sign-off, and panel convergence iteration. Referenced by pre-implementation and post-PR-review phases.
triggers: []
---

# Playbook: Review workflow gates

## Purpose

Codifies the mandatory review workflow that prevents wasted cycles — both in the pre-implementation panel process and in PR review loops. Every rule here is a hard gate; skipping any stage requires explicit user approval with documented justification.

This playbook is referenced by:
- `pre-implementation.md` — for the two-stage review before code changes
- `post-code-change.md` — for the prior-PR-review sweep
- `post-pr-review.md` — for PR comment root-cause analysis
- `pre-pr-push.md` — for the prior-PR-review sweep before push
- `AGENTS.md` cross-cutting rules — for scope reduction sign-off and panel-gate hard stops

---

## 1. Two-stage review: rubber-duck then panel

### Why two stages

A rubber-duck critique is cheap (one agent, fast turnaround) and catches blind spots before they compound across a full panel review. Feeding rubber-duck findings into the panel means the panel starts from a stronger baseline, reducing iteration rounds from ~4-5 to ~2-3.

### Procedure

1. **Stage 1 — Rubber-duck critique.** Launch a single rubber-duck agent with the plan/design/implementation. Receive findings.
2. **Triage rubber-duck findings.** Adopt findings that clearly prevent bugs or test failures. Set aside findings that would significantly complicate the implementation without clear benefit. Document the triage rationale.
3. **Incorporate adopted findings** into the plan/design before Stage 2.
4. **Stage 2 — Full multi-model panel.** Launch the panel per `multi-model-review.md` with the rubber-duck-improved plan. Iterate until unanimous convergence.

### When to apply

- **Always apply** for non-trivial changes: multiple files, architectural decisions, unfamiliar codebases, complex logic, new patterns, restructuring work, decomposition, DI changes, dependency graph changes.
- **May skip Stage 1 (rubber-duck) only** for genuinely trivial changes: single-file rename, typo fix, version bump, comment update. Even then, Stage 2 (panel) is still mandatory per the pre-implementation hard gate.

### Skip escalation

Skipping either stage requires **all three**:

1. Explicit user approval via `ask_user` — not implicit silence.
2. A documented justification stronger than "low risk" or "simple change." Acceptable justifications: "user explicitly directed immediate implementation," "change is a mechanical rename with no behavioral delta and automated refactoring tool output."
3. The skip recorded in the session state so future review can audit the decision.

---

## 1A. Panel-binds-to-artifact rule (HARD GATE)

### The problem

The most common silent-skip pattern is: agent runs a panel on a sub-decision (one library placement, one naming question, one design choice), then drafts a larger plan, then treats the earlier panel as satisfying the gate for the larger plan. This is a silent skip and produces all the failure modes the panel exists to prevent.

### Rule

A panel only satisfies a gate for the **exact artifact it reviewed**. When the artifact changes (revisions, additions, scope expansion, new sub-systems, new files, new dependencies), a new panel must run on the changed artifact.

### Artifact-binding certification

Before any implementation tool call that follows a panel, the agent MUST emit a literal certification block in the conversation. The certification block has this exact shape:

```
PANEL CONVERGED
  artifact: <path or description, e.g. plan.md>
  artifact-hash: <SHA256 of artifact content, first 8 chars>
  artifact-bytes: <byte count>
  artifact-revision: <revision marker, e.g. "R3 — added Part 5 banner fix">
  panel-round: <round number when convergence was reached>
  verdicts: <list of reviewer ids that returned SOUND>
  unanimous: yes
```

The certification block:
1. Is emitted ONCE per artifact version, after Round N convergence.
2. Is invalid if the artifact changes after emission — agent must re-panel on the changed artifact and emit a new certification.
3. Sub-decision panels (single library placement, single naming choice, etc.) do NOT satisfy a plan-level gate. They certify ONLY the sub-decision; the plan-level gate is separate and requires its own certification.

### Sub-decision vs full-plan distinction

| Panel scope | Satisfies | Does NOT satisfy |
| --- | --- | --- |
| Single question (e.g. "where should file X live?") | The specific question | Plan-level gate, multi-file structure, cross-cutting concerns |
| Implementation plan (full document) | Plan-level gate for the exact plan reviewed | Future revisions of the plan |
| Revised plan (R2+) | The revised plan version | Earlier plan versions |

When the agent is uncertain whether a panel is sub-decision-scope or plan-scope, treat it as sub-decision and run a separate plan-level panel.

---

## 1B. Hard-stop tool list (HARD GATE)

### Rule

The following tools MUST NOT be called for implementation purposes until a current artifact-binding certification (per §1A) is present in the conversation:

- `create` — any file creation
- `edit` — any file edit, including instruction files and configuration
- `powershell` / `bash` with any of:
  - `mkdir`, `New-Item`, `md` — directory creation
  - `Set-Content`, `Add-Content`, `Out-File`, `>`, `>>` — file write
  - `Move-Item`, `Rename-Item`, `cp`, `mv` — file moves
  - `dotnet new`, `cargo new`, `npm init`, `git init` — project scaffolding
  - `git add` — stage changes (additionally requires `POST-CODE-CHANGE LEDGER` per §2B and, for project repos, the diff-approval gate below)
  - `git commit` — finalize commit (additionally requires `PRE-COMMIT GATE PASSED` block emitted in the current turn per `pre-commit.md`; the block records diff approval, ownership confirmation, message approval, format check, and staged-files list)
- Sub-agent launches with implementation intent (the sub-agent itself would edit files)

### Exceptions

The following are NOT implementation tools and remain available without certification:

- `view`, `grep`, `glob`, `view`-equivalent reads
- `powershell` for read-only commands (`Get-*`, `git diff`, `git log`, `git status`, `dotnet list`, `dotnet build` for verification)
- `ask_user`, `read_agent`, `write_agent`, `list_agents`
- Sub-agent launches with review/research intent (rubber-duck, explore, research, code-review)
- `sql` for session-store reads/writes (todo tracking is meta, not implementation)

### Why this list is enumerated explicitly

A general rule like "no implementation until panel ran" leaves room for the agent to rationalize: "I'm just creating a folder, that's not really implementation." The enumeration removes that escape hatch — any of these tools called for implementation purposes without certification is a hard violation.

### `exit_plan_mode`, plan-summary approval, and "proceed with implementation" runtime messages are NOT certifications

The most common silent-skip path: the agent emits an `exit_plan_mode` plan summary, the user approves it (or the runtime returns "Plan approved! Proceed with implementing the plan"), and the agent treats that as satisfying §1A. **This is wrong.**

`exit_plan_mode` is a runtime convenience for user-facing plan presentation. It is NOT a panel run. The user's approval of the summary is approval of scope, not approval of design. Per §1A, only a multi-model panel that reviewed the exact artifact AND emitted the `PANEL CONVERGED` block in the current turn satisfies the gate.

If the agent has:

- exited plan mode, OR
- received user approval via `ask_user` on a plan summary, OR
- received a "proceed with implementation" directive from the runtime, OR
- had its `exit_plan_mode` accepted with `autopilot` / `autopilot_fleet`

…but has NOT run the panel and emitted `PANEL CONVERGED` in the current turn — implementation tools remain forbidden per §1B. User scope-approval is a necessary but not sufficient condition; the panel pass is the other necessary condition. The two conditions are independent and BOTH must be satisfied before §1B tools may run.

The skip-escalation in §1 (the "user explicitly directed immediate implementation" justification) requires both (a) an explicit `ask_user` whose body contains the phrase "skip the panel" or equivalent unambiguous skip-the-review directive, AND (b) recording the skip in the session state per the §1 skip-escalation rule. A generic "approved" / "proceed" / "exit plan mode" response is NOT a panel-skip directive — it's scope approval.

### Instruction-repo edits are §1B tool calls (no exemption for "meta-work")

Editing files in the instruction repository — `.github/playbooks/**/*.md`, `.github/instructions/**/*.instructions.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.github/playbooks/manifest.yaml`, or any other governance / instruction artifact in this repo or downstream repos that consume it — is **explicitly a §1B tool call** subject to the same `PANEL CONVERGED` certification as code-repo edits. The §1B enumeration above already says "any file edit, including instruction files and configuration" — this subsection exists to defeat the rationalization that instruction edits are "meta-work" or "small tweaks" or "plan-level work" exempt from the gate.

Meta-changes to the instruction set carry **higher** long-term risk than code changes: bad code is reverted in one commit; bad instructions corrupt future agent behavior across many sessions until someone notices and reverts. The required certification scrutiny is the same or higher for instruction edits, not lower.

When the panel reviews an instruction-set change, its prompt MUST include explicit focus on:

1. **Self-consistency** — does the new rule conflict with existing rules? Overlap in enforcement domains?
2. **Escape-hatch analysis** — what could a future agent do to skip the rule? Vague language, optional conditional skips, ambiguous "N/A — reason" clauses are red flags.
3. **Enforcement mechanism** — is the rule self-policing (a literal block emission that §1B can hard-stop on)? Or norm-based and easily forgotten?
4. **Reviewer slate / model / path stability** — do specific model names, tool names, or external system references have a deprecation story?
5. **Project-agnosticism** — does the rule leak project-specific names, paths, or domain concepts that would be wrong in other consuming repos?

The plan-file edit carve-out below applies ONLY to session `plan.md` files in `~/.copilot/session-state/<id>/`. It does NOT apply to instruction-repo files. The "implementation-intent vs preparation-intent" distinction below does NOT apply to instruction-repo files either — there is no "preparation" carve-out for instruction edits.

### Plan-file edit carve-out

Editing the session plan file (`plan.md` in the session-state folder) BEFORE the panel runs is allowed and expected — that's how the plan reaches a reviewable state. Editing the plan file AFTER the panel runs invalidates the certification and requires a new panel (per §1A).

### Implementation-intent vs preparation-intent

`powershell` calls to create a worktree, configure git identity, install tools, or set up the environment are PREPARATION, not implementation, and remain available without certification. The discriminator: does this tool call materially advance the work the panel reviewed? If yes, certification is required.

### Pushing changes to project (non-instruction) repos requires explicit user diff approval BEFORE staging (HARD GATE)

After a `PANEL CONVERGED` certification authorizes implementation, the agent may call `create` / `edit` to apply the panel-approved changes to the working tree. **But before any `git add` to a project repository, the user MUST see the actual working-tree diff (or a faithful summary of it) and explicitly approve.**

This gate is asymmetric with the instruction repo (e.g. `CopilotInstructions`): instruction-repo changes can proceed from `edit` → `git add` → `git commit` → `git push` without an additional user approval gate (the panel certification covers them). Project-repo changes require the user to gate the change at the **working-tree boundary BEFORE it enters the staging area**.

**Why pre-`git add` and not pre-`git push`?**

Earlier is better. A pre-push gate means the change is already staged, committed, and message-authored; reversing it requires `git reset` + history rewrite or `git commit --amend` + force-push. A pre-staging gate means the change is just files on disk; reversing it is `git restore` (or simply editing again). The earlier gate trades a slightly noisier review experience (user sees raw working-tree diff, not a polished commit) for cheaper reversal cost AND for a much harder skip path — if `git add` is gated, then `git commit` and `git push` can't run on un-approved changes by construction, eliminating the "I'll just push and ask for forgiveness" failure mode.

**Procedure before any `git add` (or equivalent staging command: `git stage`, `git add -A`, `git add -p`, `git add .`, etc.) in a project repo:**

1. Run `git --no-pager diff` (working tree vs HEAD) and surface the output to the user, plus a short summary of what each hunk does.
2. Call `ask_user` with the diff summary, asking for one of: approve / amend / discard.
3. Wait for the user response BEFORE running `git add`.

Once the user approves, the orchestrator may then chain `git add` → `git commit` → `git push` without further user approval for that specific change.

**Skip conditions (none apply unless explicitly documented this session):**

- The user has stated in THIS session: "auto-stage for `<repo>` is fine" / "you can `git add` project changes without asking" / equivalent unambiguous opt-out for that specific project repo.
- The change being staged is a `git restore` / revert of working-tree state the user just asked to be reverted.
- The change is a trivially mechanical fix (single file, ≤10 line delta, fixing a clearly identified review comment) AND the orchestrator already showed the user the planned change in the same turn.

**What about instruction-repo pushes?**

Pushes to instruction repositories (e.g. `CopilotInstructions/main`) do NOT require this pre-`git add` gate. The panel certification on the instruction-repo edit is sufficient. The asymmetry exists because:

- The user's plan-stage approval covers the instruction strategy.
- Instruction edits are typically narrow and structural (delta proposals).
- The panel's review of an instruction artifact IS a review of the user-visible shape (no rendered output, no UX impact).
- Project-repo pushes affect a long-lived shared repo with multiple consumers; instruction-repo pushes only affect the agent's own behavior in future sessions and are reverted by another commit.

If the user explicitly states a preference for auto-staging project commits as well, this gate is relaxed for the duration of the session (record the override in the session state).

**Failure mode if skipped:** the agent presents a "shipped!" summary to the user before the user has seen the code; the user discovers an issue post-push; revert/amend cycle inflates round count and erodes trust in the gate process. The pre-`git add` placement is specifically chosen so that the agent's normal "build → test → stage → commit → push" cadence cannot proceed past the staging step without the user in the loop.

---

## 2. PR review comment root-cause analysis

### The problem this solves

When a PR review comment (bot or human) identifies an issue, a surface-level fix that passes the immediate check but leaves the underlying pattern in place causes the same class of issue to be flagged again in subsequent reviews. This wastes reviewer time, developer time, and erodes confidence in the review process.

### Hard gate

Every PR review comment must be analyzed through this checklist before marking it resolved:

1. **Root cause identified.** What pattern, assumption, or gap caused the issue? Not "this line was wrong" but "this type of line is consistently missed because X."
2. **Fix addresses root cause.** The change prevents the issue from recurring, not just from appearing at this specific location.
3. **Similar patterns swept.** Search the rest of the diff (and ideally the rest of the changed files) for the same pattern. Fix all instances in one pass, not one at a time across review rounds.
4. **Instructions updated.** If the comment reveals a gap in the instruction set (a pattern the pre-implementation panel should have caught but didn't), propose an instruction-file delta:
   - A new sweep pattern in `post-code-change.md`
   - A new checklist item in the relevant playbook
   - A new hard gate if the issue class is severe enough
5. **Repeat-finding test.** Before re-requesting review, mentally simulate: "If the same reviewer runs the same review pass, will they find the same class of issue anywhere in the diff?" If yes, the fix is incomplete.

### Repeat findings are process failures

When the same class of issue is flagged across multiple review rounds:

1. Treat it as evidence that the pre-implementation panel missed something.
2. Identify why the panel missed it (was the pattern not in the sweep list? Was the reviewer angle too narrow? Was the rubber-duck stage skipped?).
3. Feed the learning back: update the instruction set, add a sweep pattern, or adjust panel reviewer angles.

---

## 2A. Prior-PR-review sweep (HARD GATE)

### The problem

PRs frequently get the same class of review comment that prior PRs already received. Each round of fix-up commits wastes reviewer time, developer time, and slows the merge cycle. The patterns are visible in the prior PR review history — fetching them and sweeping the current diff prevents the second-round comments.

### Procedure

Two-scope sweep — current branch + recent repo PRs:

**Scope A — Current branch PR thread:**
1. If the current branch already has an open PR, fetch all review comments (both inline and review-body) from that PR via `gh api repos/<owner>/<repo>/pulls/<n>/comments` and `gh api repos/<owner>/<repo>/pulls/<n>/reviews`.
2. Extract the pattern from each comment — not the specific file/line, but the class of issue (e.g. "empty CompareExchange guard", "ProviderDbContext 2-arg overload defaults ensureCreated=true", "HTML disabled on span tag").
3. Sweep the current uncommitted/staged diff for each pattern.

**Scope B — Recent repo PRs:**
1. Fetch the last 10 merged PRs in the repo: `gh pr list --state merged --limit 10 --json number,title`.
2. For each PR, fetch review comments (bot + human) via the same API calls.
3. Extract patterns (same as Scope A).
4. Sweep the current diff for each pattern.

**Output requirement:**

Emit a one-line-per-pattern sweep report before showing the diff to the user:

```
Prior-PR-review sweep: ran, M patterns checked, N findings.
  - <pattern description from PR #X>: matches/no matches
  - ...
```

### When this gate fires

- **`post-code-change.md`** — every commit-bound change runs the sweep before the diff is shown.
- **`pre-pr-push.md`** — every push intended for review runs the sweep against the full branch diff (`git diff <base>..HEAD`).

### Skip conditions

This sweep may be skipped when:
- The repo has no prior merged PRs (e.g. brand-new repo) — skip Scope B; Scope A still applies if a current PR exists.
- The current change has no production-code edits (pure docs / pure CI config change with no code patterns to match) — explicitly document this fact.

In every other case, the sweep is mandatory. Silent skip ("I don't think any prior patterns apply") is the failure mode this gate exists to prevent.

### Why both scopes

- **Scope A catches re-pushed fixes** — same PR thread, prior round flagged X, fix-up commit re-introduces X elsewhere. Most common in iterative review cycles.
- **Scope B catches "patterns the team has already learned about"** — comments from prior PRs reflect what reviewers care about; the current PR should not re-trigger them.

### Cost containment

Fetching review comments for 10 PRs is ~20 API calls. Use `gh api --paginate` only when a PR has >30 comments. Cache the extracted pattern list in the session todo store with a TTL so re-runs within the same session don't refetch.

---

## 2B. Post-code-change ledger (HARD GATE)

### The problem

The pre-implementation phase has a single named certification block (`PANEL CONVERGED` per §1A) whose presence is enforced by §1B — implementation tools are forbidden until it appears. The post-code-change phase has no analogous block. Multiple hard gates exist in `AGENTS.md` (`post-code-change.md` step 2.5 sweep, §2A prior-PR-review sweep, touched-file LPA, hygiene cleanup, comment audit, build, tests), but each gate enforces only its own one-liner. There is no single attestation that **all** of them ran for a given commit, so a `git add` / `git commit` pair can execute with one or two gates having silently skipped — and the user has no easy way to detect it after the fact.

This is the failure mode that landed on this branch: `PANEL CONVERGED` was emitted once for the plan; subsequent implementation commits proceeded with build + tests + diff-approval but **without** the §2.5 sweep, §2A sweep, LPA, or comment audit running. The user had previously waived the diff-approval `ask_user` step on an earlier commit; that single-step waiver was implicitly carried forward and treated as a blanket post-code-change waiver on later commits.

### Rule

Before ANY `git add` (or `git commit --amend` that re-stages files, or `git stash pop` that resolves into a commit), the agent MUST emit a literal `POST-CODE-CHANGE LEDGER` block in the **current turn**. The block enumerates the status of every post-code-change gate that applies to the staged content. Without the ledger, `git add` is forbidden — extending §1B's hard-stop list to cover the commit boundary, not just the pre-implementation boundary.

### Ledger format

```
POST-CODE-CHANGE LEDGER
  commit-subject: <one-line subject the agent will use for git commit>
  files-touched: <count + brief shape, e.g. "21 (370+/0-)">
  gates:
    hygiene-cleanup: <ran | N/A — reason>
    touched-file-LPA: <ran (N findings, K unjustified) | N/A — reason>
    recurring-pattern-sweep: <ran, N findings>
      - <pattern>: <N matches | no matches>
      - ...
    prior-PR-review-sweep: <ran, M patterns checked, N findings | N/A — no prior merged PRs / no production-code edits>
      - <pattern from PR #X>: <matches | no matches>
      - ...
    dry-audit: <ran, N duplications, K refactored, J waived | N/A — reason>
      - <pattern shape>: <file:line, file:line, ...> → <refactored to <abstraction> | waived ("<user quote>")>
      - ...
    post-code-change-panel: <ran, unanimous | N/A — reason | user-waived — "<quote>">
    intent-driven-testing-audit: <ran — prospective | ran — retrospective | N/A — <reason>>
      # Enforced by catalog rule `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH).
      # Fires when diff contains EITHER (a) NEW or modified test files OR (b) ANY production-source
      # modification that changes the SUT surface — new exported member, signature change, NEW
      # conditional branch (if/switch/?:/when), new state-mutating statement, new method declaration
      # (public OR private), new error-handling branch (try/catch/throw), or new state-transition.
      # `N/A` reason MUST cite a specific carve-out from `intent-driven-testing.md`: rename-only
      # delta (test body byte-equivalent before/after), mechanical-port commit per §3.4, auto-generated
      # test files, pure whitespace/comment/formatting change, pure deletion. Bare `N/A` or
      # `N/A — private-only SUT delta` is NOT a valid carve-out (private branches still need test
      # coverage per §3.4 Direction B).
    delta-g-sweeps: <ran, N patterns swept, M sites enumerated | N/A — reason>
      # Format and semantics defined in `multi-model-review/pr-creation-mirror-prompt.md` Delta K
      # (status enum, evidence/rationale rules, branch_new_files_verified format, falsifiability).
      # Unlike other §2B rows (single-line sub-bullets), `delta-g-sweeps:` uses a richer nested
      # sub-block per pattern. Future grammar-tightening passes must preserve this nesting —
      # falsifiability depends on it.
      - pattern: <slug; lowercase-hyphenated; e.g. "js-import-jsexception-wrap">
        discovery_query: <exact command the agent ran; reviewer can re-run and diff>
        sites:
          - path: <relative path>
            status: applied | already-applies | not-applicable
            evidence: <file:line-range>     # REQUIRED for applied + already-applies; cites
                                             #   the exact line range where P is present at HEAD
            rationale: <one line>            # REQUIRED for not-applicable; (a) code property
                                             #   verifiable from the cited file OR (b) repo invariant
        branch_new_files_verified: yes — merge-base <SHA8>
    pre-impl-trigger-detections:
      # Cycle-3 (`pre-implementation.md` G6). Mirrors G6 chat-visible `trigger-detected-<playbook>:`
      # lines into the LEDGER. Each cycle-3-scope playbook gets one line; this is the audit anchor
      # for OFFERED-class rules 6/7/8/10/11 (silent-downgrade-to-`not-applicable` bypass closure).
      # Updated by G6 re-entry per `pre-implementation.md` if scope changes mid-implementation.
      implementation-planning: <yes | no>
      library-restructure: <yes | no>
      design-exploration: <yes | no>
      performance-comparison: <yes | no>
      scope-planning: <yes | no>
      system-framing: <yes | no>
      project-vocabulary: <yes | no>
    pre-impl-playbook-decisions:
      # Cycle-3 (`pre-implementation.md` G6). Mirrors G6 chat-visible `playbook-decision-<playbook>:`
      # lines into the LEDGER. Enforced by catalog rules 2, 3, 4, 6, 7, 8, 10, 11, 12, 13.
      #
      # **Allowed decision values per playbook class:**
      # - REQUIRED-decision-recorded class (implementation-planning, library-restructure):
      #   VALID = {invoked | required-but-skipped: "<safety-critical re-confirmation per User-skip policy>" | not-required-trigger-not-detected}
      #   INVALID = {offered-and-declined, not-applicable} — these silently bypass the required gate
      #   The `not-required-trigger-not-detected` sentinel is the canonical value when G6 emitted
      #   `trigger-detected: no` (preserves fixed cardinality without omission contradiction).
      # - OFFERED class (design-exploration, performance-comparison, scope-planning, system-framing, project-vocabulary):
      #   VALID when trigger-detected: yes = {invoked | offered-and-declined: "<quote>" | required-but-skipped: "<reason>"}
      #   VALID when trigger-detected: no = {not-applicable}
      #   INVALID when trigger-detected: yes = {not-applicable} (silent-downgrade bypass)
      #
      # User-quoted values use double-quoted YAML strings (RFC YAML) to handle `: ` and special chars
      # in user quotes. Example: `offered-and-declined: "user said 'this is a simple bump'"`
      implementation-planning: <invoked | required-but-skipped: "<re-confirmation>" | not-required-trigger-not-detected>    # REQUIRED class
      library-restructure: <invoked | required-but-skipped: "<re-confirmation>" | not-required-trigger-not-detected>        # REQUIRED class
      design-exploration: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      performance-comparison: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      scope-planning: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      system-framing: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      project-vocabulary: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
    playbook-invocations:
      # Cycle-3. Evidence each playbook actually ran during implementation. Scope: ONLY the 4
      # playbooks that have a corresponding `pre-impl-playbook-decisions` entry AND produce
      # implementation-phase artifacts. intent-driven-testing-prospective is enforced separately
      # by cycle-2 rule `intent-driven-testing-required-on-test-or-SUT-delta` and is NOT in
      # cycle-3 scope. The 3 decision-only playbooks (scope-planning, system-framing,
      # project-vocabulary) have NO implementation evidence — their decision-line IS the evidence
      # (rules 8/10/11 check the decision sub-block directly).
      implementation-planning: <ran (artifact-path:line) | N/A — <reason>>
      library-restructure: <ran (artifact-path:line) | N/A — <reason>>
      design-exploration: <ran (prototypes/<name>/ citation) | N/A — <reason>>
      performance-comparison: <ran (benchmark citation) | N/A — <reason>>
    comment-audit-§3.1: <ran | N/A — no comments touched | failed — <site list of file:line bullets with invalid/missing approval_turn>>
    build: <passed | failed: …>
    tests: <passed, N/total | failed: …>
    diff-shown: <yes (ask_user turn …) | user-waived — "<quote>">
    commit-message-approved: <PENDING | yes (ask_user turn …)>
```

Each line is mandatory. If a gate is not applicable, the entry MUST say `N/A — <reason>` — not blank, not omitted, not "skipped".

### Waiver semantics

A `user-waived` value MUST quote the user's waiver from the **current turn**. Waivers from earlier turns do NOT carry forward to new commits. This is the specific rule that catches the silent-skip failure mode: "the user said staged-means-reviewed on commit N" cannot waive any gate on commit N+1.

Example valid waiver:
```
diff-shown: user-waived — "go ahead and ammend these changes into that commit and pop the stash"
```

Example invalid waiver (previous-turn quote, current-turn approval missing):
```
diff-shown: user-waived — "staged means I reviewed it" [turn 47]
```

### Required outputs per gate

The ledger does NOT replace each gate's own required output (e.g. §2.5 sweep still emits `Step 2.5 sweep: ran, N findings`, §2A still emits its sweep line). The ledger AGGREGATES those into a single signed-off block. Per-gate output must still appear in the same turn — the ledger just confirms each gate ran AND attests to its result.

### When this gate fires

Every `git add` of files staged for a commit. Specifically:

1. Fresh commits (`git add` → `git commit`).
2. Amend commits (`git add` → `git commit --amend`) when files are re-staged after edits.
3. Conflict resolution after `git stash pop` / `git merge` / `git rebase` IF the resolution results in a `git add` to mark conflicts resolved AND a commit is intended in the same turn.
4. Cherry-pick / rebase operations that resolve conflicts and stage the resolved state.

**Carve-outs (no ledger required):**

- `git add` to mark conflicts as resolved when **no commit will follow in the current turn** — i.e. the user has explicitly directed leaving the resolved state in the working tree for their own review before any commit.
- `git add` followed by `git stash push` (preparing to stash, not commit).
- `git restore --staged <path>` (unstaging — no commit pathway).

### Skip conditions

A gate row may be `N/A — <reason>` when:

- **hygiene-cleanup**: the diff contains no consumer files with stale usings or qualifiers that the change could have affected (e.g. the diff only adds new files in new directories).
- **touched-file-LPA**: the diff contains no visibility / export / sealing / mutability surface deltas (per `AGENTS.md` Post-code-change phase). Body-only edits to already-public types do NOT trigger LPA.
- **recurring-pattern-sweep**: no pattern's trigger condition definitionally applies (e.g. no test files in diff for test-name patterns). "I don't think it applies" is NOT acceptable.
- **prior-PR-review-sweep**: the repo has no prior merged PRs AND no current PR thread, OR the change has no production-code edits.
- **post-code-change-panel**: pure re-commit / rebase with zero behavioral delta vs. the previously-panelled artifact (e.g. style-only amendments to an already-reviewed commit). The ledger MUST justify this explicitly: `N/A — pure re-commit of already-reviewed content, 0 behavioral delta`.
- **comment-audit-§3.1**: no comments added, removed, or modified in the diff. `failed — <site list>` is NEVER waivable: any bullet with invalid/missing `approval_turn:` in the §2.6 ledger produces `failed`, which hard-blocks `git add` per `comment-protocol.md` §Recording. On **adopted repos** (per `comment-protocol.md` §Persisted audit file — adoption gate), missing `.github/pr-quality-gate/audits/last.md` ALSO produces `failed`. On **non-adopted repos**, the audit file is intentionally absent and tracking happens INLINE via `PRE-COMMIT GATE PASSED`'s `comment_audit` block — missing-file is NOT a failure in that mode.
- **delta-g-sweeps**: N/A only via recorded zero-result `discovery_query` at HEAD. The
  `discovery_query` MUST scope to AT MINIMUM the unique directory parents of every file
  in the commit's diff (extract from `git diff --name-only <merge-base>..HEAD`; repo-root
  files whose dirname is `.` expand to the repo's source roots — typically `src/`, `tests/`
  — and exclude generated/vendored trees such as `node_modules/`, `vendor/`, `obj/`, `bin/`
  per the repo's `.gitignore`). Wider scope is permitted and encouraged for cross-cutting
  patterns; narrower scope is forbidden. If a sister site outside the recorded scope is
  later discovered, the LEDGER is falsified per §2B and the falsified-ledger remediation
  below applies. "No plausible sister sites" is NOT acceptable; the query must be recorded
  so a reviewer can re-run it.
- **pre-impl-trigger-detections** / **pre-impl-playbook-decisions** / **playbook-invocations**: NEVER `N/A` as a whole sub-block — these sub-blocks are mandatory on every commit-bound `POST-CODE-CHANGE LEDGER` and mirror the pre-impl G6 outputs per `pre-implementation.md`. Individual entries within `playbook-invocations` may be `N/A — <reason>` (e.g., `implementation-planning: N/A — playbook-decision was not-required-trigger-not-detected`). Individual entries within `pre-impl-playbook-decisions` MUST use one of the valid decision values for the playbook's class (REQUIRED-class accepts `invoked` / `required-but-skipped` / `not-required-trigger-not-detected`; OFFERED-class accepts the 4 base values per Phase 2 schema). Catalog rules 2, 3, 4, 6, 7, 8, 10, 11, 12, 13 fire on bypass values.

### Why this exists

The asymmetry with §1A produced the failure mode. §1A enforces "no implementation tools without `PANEL CONVERGED`"; the absence of the certification block is itself the enforcement. §2B mirrors that pattern at the commit boundary: "no `git add` without `POST-CODE-CHANGE LEDGER`". The literal block is the enforcement; absent block = forbidden tool call. This makes the rule self-policing in the same way §1A is.

The ledger is also the audit trail: when a future review (post-merge, retrospective, or PR review on the open PR) discovers that a gate slipped, the ledger explicitly records *which* gate was skipped and *why*. No more reconstructing intent from chat history.

### Repeat failure escalation

If a `POST-CODE-CHANGE LEDGER` block is later found to have falsified a gate status (claimed `ran` for a gate that did not actually run, or quoted a waiver the user never gave), the agent MUST proactively report this to the user as a process violation in the next turn, propose a remediation, and ask the user to re-review. False-positive ledger entries are a higher-severity failure than silent skips because they erode the trust the rule depends on.

---

## 2C. DRY remediation gate (HARD GATE)

### The problem

The agent has repeatedly noticed code duplication during implementation but proceeded to commit without refactoring — leaving the user to call it out later. Examples from recent sessions: 5 tab classes sharing 100+ lines of run/cancel/state/log plumbing (caught by user, base class extracted after commit); 3 picker services sharing the WinUI window-init dance (caught by user, shared helper extracted after commit). The pattern is "I saw it, I didn't act." This wastes a re-review round and erodes trust.

### Rule

During the post-code-change phase, the agent MUST run a DRY audit on the staged diff before showing it for approval. If any of the following are detected, the agent MUST either refactor in-place OR present the duplication to the user via `ask_user` with a refactor-or-waive choice:

1. **Cross-file duplication.** Two or more files contain ≥5 lines of substantively-identical logic (member ordering, parameter renames, and trivial whitespace differences do not count as different).
2. **Three-or-more pattern.** A pattern (method shape, field cluster, dispatch wrapper, etc.) appears 3+ times anywhere in the staged diff or in code the staged diff touches.
3. **Copy-paste growth.** A new file is structurally identical to an existing file with only parameterized differences (different request type, different service method).

### Refactor recommendations

The default action is refactor, using the smallest abstraction that captures the duplication:

- 2+ classes sharing fields + methods → base class (abstract for behavior, concrete for shared state).
- 2+ files calling the same 3–10 lines of platform/util code → static helper.
- 2+ methods with same shape but different generic parameter → generic method.
- 2+ types with parallel members → extension method, interface, or partial class.
- 2+ Razor components sharing template + binding → component inheritance or shared `RenderFragment`.

### Waiver semantics

If refactoring is not appropriate, the agent presents the duplication to the user with:

1. The pattern (concrete code or shape).
2. The file paths + line ranges where it appears.
3. The proposed refactor + why the agent is recommending against it (e.g., "premature abstraction — only 2 sites today, abstraction would obscure rather than help").
4. A `refactor | waive` choice via `ask_user`.

A `user-waived` entry in the LEDGER's `dry-audit` row MUST quote the user's waiver from the **current turn**.

### Exceptions (no audit needed)

- Test fixtures that intentionally duplicate setup for isolation.
- Trivial 1–2 line guards (`ArgumentNullException.ThrowIfNull(x)`).
- Tool-generated code (EF migrations, Razor compilation output, scaffolding).
- Boilerplate the language requires (e.g., `partial` declarations, attribute decorators).

### Required output

In the post-code-change LEDGER (§2B), add the gate row:

```
dry-audit: ran, N duplications, K refactored, J waived
  - <pattern shape>: <file:line, file:line, ...> → refactored to <abstraction> | waived ("<user quote>")
```

### Repeat-failure escalation

If the same duplication pattern is detected in a subsequent commit (i.e., the user had to call it out after the agent shipped without refactoring), that counts as a §2B "falsified ledger" — agent reports the slip proactively and proposes remediation. Two such slips in the same session triggers an explicit pause + plan-correction cycle.

---

## 2D. Pre-PR-creation multi-model review (HARD GATE)

### Rule

Before any PR-creation or review-visibility transition tool call (full list in `pre-pr-creation-review.md` G6), a multi-model heavy panel (≥4 reviewers per slate floor in `pre-pr-creation-review.md` waive matrix) MUST run on the FULL branch diff (`<base>..HEAD`) with the 11-category Copilot-mirror prompt template (`multi-model-review/pr-creation-mirror-prompt.md`). Every reviewer-flagged `blocking` finding MUST be resolved via `fixed` / `dismissed-source-grounded` / `routed-deferred-with-tracker-and-ask_user` (G4 conditions). A `PRE-PR REVIEW COVERAGE` block MUST appear in the same turn as the PR-creation tool call (initial emission at end of synthesis + re-emission after the AGENTS user-approval `ask_user` returns).

Strict mandatory — G1 (panel run), G2 (must-fix=0), G3 (block emission), G5 (disposition per finding), G6 (forbidden-tool list), and G7 conditions are NOT user-waivable. Convergence model and slate composition ARE user-waivable within floors (see waive matrix in the consumer playbook).

### LEDGER row format

When §2D is in scope (review-targeting push per `pre-pr-push.md` Step 5), the §2D ledger row appears in `PRE-PR REVIEW COVERAGE` per the playbook's Step 7 / Step 9 emission format. The `pr-creation-status` field is the gate's READY signal — values:

- `READY-pending-user-approval` (initial emission, end of synthesis turn).
- `READY-re-emitted-after-user-approval` (PR-creation tool-call turn, after AGENTS user-approval ask_user returns + same-state re-check passes).
- `BLOCKED — <N> must-fix unresolved` (must-fix findings still pending).
- `BLOCKED — slate-floor violated` (slate composition fell below the waive matrix floor).
- `BLOCKED — bootstrap-token-removed` (G7 token removed from PR body after initial emission).
- `BLOCKED — same-state-check-failed` (HEAD / base / commit-count changed between initial and re-emission).

The PR-creation tool call is forbidden unless `pr-creation-status` reads `READY-re-emitted-after-user-approval` in the same turn.

### Bootstrap exemption (narrow scope)

The PR that introduces §2D itself (this entire gate, the consumer playbook, the cross-cutting AGENTS.md bullet, the `review-workflow-gates.md` §2D section, the `pre-pr-push.md` Step 5 hook, the `multi-model-review/pr-creation-mirror-prompt.md` template, the `pre-pr-creation-review/implementation-roadmap.md` deferred-features document, and the `manifest.yaml` registration) is EXEMPT from §2D for THAT specific PR. The exemption requires ALL of:

1. The PR introduces a NEW mandatory gate that did not exist on `origin/<base>` pre-PR.
2. The PR body contains the literal token `BOOTSTRAP-EXEMPTION: §2D pre-PR-creation review gate`.
3. The PR includes ALL companion edits required for the gate to be operative post-merge (listed above).

PRs that modify, tighten, loosen, or refactor §2D-as-already-shipped are NOT bootstrap-exempt — they go through §2D normally. If the bootstrap token is removed from the PR body before merge, the exemption is revoked.

This template applies to any future meta-change introducing a new mandatory gate at the §2-level: the introducing PR is exempt from the gate it introduces; subsequent modification PRs go through the gate normally.

### Full procedure

See `.github/playbooks/pre-pr-creation-review.md` for the full procedure (Step 1 invocation mode, Step 2 ancestry-based re-run-trigger detection, Steps 3-6 panel + synthesis + fix loop, Steps 7-10 LEDGER emissions and user approval flow). Deferred features (capability-tier registry, context-budget circuit breaker, branch-level fix-iteration cap, citation-preserving compaction format, etc.) live in `pre-pr-creation-review/implementation-roadmap.md` for follow-up PRs.

### Why §2D exists

LLM-based PR reviewers (GitHub Copilot's PR-review feature, GitLab Duo Code Review, similar bot reviewers) consistently surface a known set of pattern categories on every PR. Patching the static-pattern catalog reactively after each PR is whack-a-mole. The LLM-judgment patterns (doc-impl divergence, comment-promises-behavior-code-doesn't-deliver, hardcoded ARIA, framework-binding stale-render, attach-without-detach, etc.) need an LLM in the loop to catch. Running our own multi-model panel pre-PR with the same category coverage shifts those findings from "review comment after PR opens" to "blocking finding before PR opens" — the work to fix is the same; the visibility cost (reviewer time, PR thread churn, CI cycles, force-push pollution) is dramatically lower.

---

## 3. Scope reduction sign-off

### Rule

When a panel, audit, or review identifies work items and the agent or sub-agents recommend deferring, dropping, or descoping any item — regardless of rationale — the recommendation **must** be presented to the user via `ask_user` with:

1. **The item** being deferred/dropped.
2. **The rationale** for deferral (YAGNI, low priority, compliance theater, borderline finding, etc.).
3. **Dissenting opinions** from any panel member who disagreed with the deferral.
4. **The consequence** of deferring (what risk does the user accept?).

### What is NOT acceptable

- Unilaterally dropping scope because a reviewer said "defer."
- Presenting a summary that omits deferred items.
- Marking items as "dropped" without user confirmation.
- Using labels like "out of scope," "pre-existing," "low severity" as justification without user sign-off.
- Deciding that an item is "compliance theater" without user agreement.

### The agent does NOT have authority to drop scope

Only the user can decide what is deferred vs. what is done. The agent's role is to present the options with context; the user's role is to decide. This applies to:

- Panel findings during pre-implementation review
- Audit remediation items
- PR scope decisions
- TODO list triage
- Any context where identified work is being deprioritized

---

## 4. Panel convergence iteration

### The iteration loop

1. **R1:** All reviewers review the initial artifact. Collect verdicts.
2. **Synthesize findings.** Group by theme, identify consensus vs disagreement.
3. **Apply fixes** for all items where the panel agrees.
4. **Present disagreements** to the user for decisions (per §3 scope reduction sign-off).
5. **R2:** All reviewers re-review the revised artifact. Repeat until convergence.

### Convergence criteria

- **Required: unanimous SOUND** from all panel members. There is no "acceptable partial consensus" — 4/5 SOUND is not convergence.
- **Disagreements go to the user.** When panel members disagree and iteration cannot resolve it, the user is the tie-breaker. Present each contested point via `ask_user` with the arguments from both sides.
- **Not acceptable:** declaring convergence with any reviewer still at NEEDS_ANOTHER_ROUND, regardless of how trivial the remaining issue appears to the agent.

### Max iterations

If the panel has not converged after 5 rounds, escalate to the user:

1. Present the remaining disagreements.
2. Ask the user to decide each contested point.
3. Apply user decisions as final.
4. Run one last confirmation round to verify no regressions from the final edits.

### Cross-round learning

After convergence, review which issues survived to later rounds:

- Issues caught in R3+ that should have been caught in R1 indicate a reviewer-angle gap.
- Issues caught by one model family consistently indicate that model's strength should be assigned to that angle.
- Issues that required user escalation indicate the panel's scope for that artifact type needs refinement.

Document these learnings for future panel configurations.

---

## Appendix: relationship to other playbooks

- `pre-implementation.md` — invokes §1 (two-stage review), §1A (artifact-binding), §1B (hard-stop tool list), and §4 (panel convergence) during the plan review gate.
- `post-code-change.md` — invokes §2A (prior-PR-review sweep), §2B (post-code-change ledger), §2C (DRY remediation gate), §4 (panel convergence) during the multi-model reviewer panel.
- `pre-commit.md` — invokes §2B (post-code-change ledger) before any `git add` / `git commit` / `git commit --amend`.
- `post-pr-review.md` — invokes §2 (root-cause analysis) when processing reviewer comments.
- `pre-pr-push.md` — invokes §2A (prior-PR-review sweep, branch-wide scope) and §2D (pre-PR-creation multi-model review) before push.
- `multi-model-review.md` — owns the panel mechanics (reviewer selection, verdict format, model assignments); this playbook owns the workflow gates around when/how panels run and what happens with their output.
- `multi-model-review/pr-creation-mirror-prompt.md` — shared 11-category Copilot-mirror prompt template used by §2D's heavy pre-PR panel and (optionally) `post-code-change.md` §3's per-commit panel.
- `pre-pr-creation-review.md` — owns the §2D heavy pre-PR-creation review gate procedure (invocation modes, ancestry-based re-run triggers, panel + synthesis + fix loop, LEDGER emissions, AGENTS user-approval flow). Deferred features captured in `pre-pr-creation-review/implementation-roadmap.md`.
- `AGENTS.md` cross-cutting rules — references §1A/§1B (panel-binds-to-artifact + hard-stop tool list), §2A (prior-PR-review sweep), §2B (post-code-change ledger), §2C (DRY remediation gate), §2D (pre-PR-creation multi-model review), and §3 (scope reduction sign-off) as hard gates.

---

## 2. PR review comment root-cause analysis

### The problem this solves

When a PR review comment (bot or human) identifies an issue, a surface-level fix that passes the immediate check but leaves the underlying pattern in place causes the same class of issue to be flagged again in subsequent reviews. This wastes reviewer time, developer time, and erodes confidence in the review process.

### Hard gate

Every PR review comment must be analyzed through this checklist before marking it resolved:

1. **Root cause identified.** What pattern, assumption, or gap caused the issue? Not "this line was wrong" but "this type of line is consistently missed because X."
2. **Fix addresses root cause.** The change prevents the issue from recurring, not just from appearing at this specific location.
3. **Similar patterns swept.** Search the rest of the diff (and ideally the rest of the changed files) for the same pattern. Fix all instances in one pass, not one at a time across review rounds.
4. **Instructions updated.** If the comment reveals a gap in the instruction set (a pattern the pre-implementation panel should have caught but didn't), propose an instruction-file delta:
   - A new sweep pattern in `post-code-change.md`
   - A new checklist item in the relevant playbook
   - A new hard gate if the issue class is severe enough
5. **Repeat-finding test.** Before re-requesting review, mentally simulate: "If the same reviewer runs the same review pass, will they find the same class of issue anywhere in the diff?" If yes, the fix is incomplete.

### Repeat findings are process failures

When the same class of issue is flagged across multiple review rounds:

1. Treat it as evidence that the pre-implementation panel missed something.
2. Identify why the panel missed it (was the pattern not in the sweep list? Was the reviewer angle too narrow? Was the rubber-duck stage skipped?).
3. Feed the learning back: update the instruction set, add a sweep pattern, or adjust panel reviewer angles.

---

## 3. Scope reduction sign-off

### Rule

When a panel, audit, or review identifies work items and the agent or sub-agents recommend deferring, dropping, or descoping any item — regardless of rationale — the recommendation **must** be presented to the user via `ask_user` with:

1. **The item** being deferred/dropped.
2. **The rationale** for deferral (YAGNI, low priority, compliance theater, borderline finding, etc.).
3. **Dissenting opinions** from any panel member who disagreed with the deferral.
4. **The consequence** of deferring (what risk does the user accept?).

### What is NOT acceptable

- Unilaterally dropping scope because a reviewer said "defer."
- Presenting a summary that omits deferred items.
- Marking items as "dropped" without user confirmation.
- Using labels like "out of scope," "pre-existing," "low severity" as justification without user sign-off.
- Deciding that an item is "compliance theater" without user agreement.

### The agent does NOT have authority to drop scope

Only the user can decide what is deferred vs. what is done. The agent's role is to present the options with context; the user's role is to decide. This applies to:

- Panel findings during pre-implementation review
- Audit remediation items
- PR scope decisions
- TODO list triage
- Any context where identified work is being deprioritized

---

## 4. Panel convergence iteration

### The iteration loop

1. **R1:** All reviewers review the initial artifact. Collect verdicts.
2. **Synthesize findings.** Group by theme, identify consensus vs disagreement.
3. **Apply fixes** for all items where the panel agrees.
4. **Present disagreements** to the user for decisions (per §3 scope reduction sign-off).
5. **R2:** All reviewers re-review the revised artifact. Repeat until convergence.

### Convergence criteria

- **Required: unanimous SOUND** from all panel members. There is no "acceptable partial consensus" — 4/5 SOUND is not convergence.
- **Disagreements go to the user.** When panel members disagree and iteration cannot resolve it, the user is the tie-breaker. Present each contested point via `ask_user` with the arguments from both sides.
- **Not acceptable:** declaring convergence with any reviewer still at NEEDS_ANOTHER_ROUND, regardless of how trivial the remaining issue appears to the agent.

### Max iterations

If the panel has not converged after 5 rounds, escalate to the user:

1. Present the remaining disagreements.
2. Ask the user to decide each contested point.
3. Apply user decisions as final.
4. Run one last confirmation round to verify no regressions from the final edits.

### Cross-round learning

After convergence, review which issues survived to later rounds:

- Issues caught in R3+ that should have been caught in R1 indicate a reviewer-angle gap.
- Issues caught by one model family consistently indicate that model's strength should be assigned to that angle.
- Issues that required user escalation indicate the panel's scope for that artifact type needs refinement.

Document these learnings for future panel configurations.

---

## Appendix: relationship to other playbooks

- `pre-implementation.md` — invokes §1 (two-stage review) and §4 (panel convergence) during the plan review gate.
- `post-code-change.md` — invokes §4 (panel convergence) during the multi-model reviewer panel.
- `post-pr-review.md` — invokes §2 (root-cause analysis) when processing reviewer comments.
- `multi-model-review.md` — owns the panel mechanics (reviewer selection, verdict format, model assignments); this playbook owns the workflow gates around when/how panels run and what happens with their output.
- `AGENTS.md` cross-cutting rules — references §3 (scope reduction sign-off) as a hard gate.
