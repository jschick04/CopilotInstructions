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
  - `git add` — stage changes
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

### Plan-file edit carve-out

Editing the session plan file (`plan.md` in the session-state folder) BEFORE the panel runs is allowed and expected — that's how the plan reaches a reviewable state. Editing the plan file AFTER the panel runs invalidates the certification and requires a new panel (per §1A).

### Implementation-intent vs preparation-intent

`powershell` calls to create a worktree, configure git identity, install tools, or set up the environment are PREPARATION, not implementation, and remain available without certification. The discriminator: does this tool call materially advance the work the panel reviewed? If yes, certification is required.

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
    post-code-change-panel: <ran, unanimous | N/A — reason | user-waived — "<quote>">
    comment-audit-§3.1: <ran | N/A — no comments touched>
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
- **comment-audit-§3.1**: no comments added, removed, or modified in the diff.

### Why this exists

The asymmetry with §1A produced the failure mode. §1A enforces "no implementation tools without `PANEL CONVERGED`"; the absence of the certification block is itself the enforcement. §2B mirrors that pattern at the commit boundary: "no `git add` without `POST-CODE-CHANGE LEDGER`". The literal block is the enforcement; absent block = forbidden tool call. This makes the rule self-policing in the same way §1A is.

The ledger is also the audit trail: when a future review (post-merge, retrospective, or PR review on the open PR) discovers that a gate slipped, the ledger explicitly records *which* gate was skipped and *why*. No more reconstructing intent from chat history.

### Repeat failure escalation

If a `POST-CODE-CHANGE LEDGER` block is later found to have falsified a gate status (claimed `ran` for a gate that did not actually run, or quoted a waiver the user never gave), the agent MUST proactively report this to the user as a process violation in the next turn, propose a remediation, and ask the user to re-review. False-positive ledger entries are a higher-severity failure than silent skips because they erode the trust the rule depends on.

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
- `post-code-change.md` — invokes §2A (prior-PR-review sweep), §2B (post-code-change ledger), §4 (panel convergence) during the multi-model reviewer panel.
- `pre-commit.md` — invokes §2B (post-code-change ledger) before any `git add` / `git commit` / `git commit --amend`.
- `post-pr-review.md` — invokes §2 (root-cause analysis) when processing reviewer comments.
- `pre-pr-push.md` — invokes §2A (prior-PR-review sweep, branch-wide scope) before push.
- `multi-model-review.md` — owns the panel mechanics (reviewer selection, verdict format, model assignments); this playbook owns the workflow gates around when/how panels run and what happens with their output.
- `AGENTS.md` cross-cutting rules — references §1A/§1B (panel-binds-to-artifact + hard-stop tool list), §2A (prior-PR-review sweep), §2B (post-code-change ledger), and §3 (scope reduction sign-off) as hard gates.

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
