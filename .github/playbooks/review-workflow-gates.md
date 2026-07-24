---
name: review-workflow-gates
description: Mandatory review workflow gates covering the rubber-duck-then-panel two-stage process, PR review root-cause analysis, scope reduction sign-off, and panel convergence iteration. Referenced by pre-implementation and post-PR-review phases.
triggers: []
---

# Playbook: Review workflow gates

## Purpose

Codifies the mandatory review workflow that prevents wasted cycles - both in the pre-implementation panel process and in PR review loops. Every rule here is a hard gate; skipping any stage requires explicit user approval with documented justification.

This playbook is referenced by:
- `pre-implementation.md` - for the two-stage review before code changes
- `post-code-change.md` - for the prior-PR-review sweep
- `post-pr-review.md` - for PR comment root-cause analysis
- `pre-pr-push.md` - for the prior-PR-review sweep before push
- `AGENTS.md` cross-cutting rules - for scope reduction sign-off and panel-gate hard stops

---

> Post-change sweep and ledger gates (§2, §2A, §2B, §2C, §2D) live in [review-workflow-gates-sweeps.md](review-workflow-gates-sweeps.md).

## 1. Two-stage review: rubber-duck then panel

### Why two stages

A rubber-duck critique is cheap (one agent, fast turnaround) and catches blind spots before they compound across a full panel review. Feeding rubber-duck findings into the panel means the panel starts from a stronger baseline, reducing iteration rounds from ~4-5 to ~2-3.

### Procedure

1. **Stage 1 - Rubber-duck critique.** Launch a single rubber-duck agent with the plan/design/implementation. Receive findings.
2. **Triage rubber-duck findings.** Adopt findings that clearly prevent bugs or test failures. Set aside findings that would significantly complicate the implementation without clear benefit. Document the triage rationale.
3. **Incorporate adopted findings** into the plan/design before Stage 2.
4. **Stage 2 - Full multi-model panel.** Launch the panel per `multi-model-review.md` with the rubber-duck-improved plan. Iterate until unanimous convergence.

> **Adversarial-framing methodology** (honest-ceiling; not a fail-closed gate in this increment): panel prompts are adversarial (assume defects; no pre-stated author conclusions - relocate them to an `Author claims to DISPROVE` section); full-mode `diff`-target panels carry an author-framing-free red-team reviewer (small diffs not exempt); and a success verdict counts toward convergence only with probing evidence (a `probing_evidence` block or its `probe:` chat lines). See `multi-model-review/procedure.md` §§ "Prompt hygiene (adversarial framing)" / "Adversarial red-team reviewer" and `multi-model-review/evidence-gate-spec.md` § "Probing evidence".

### When to apply

- **Always apply** for non-trivial changes: multiple files, architectural decisions, unfamiliar codebases, complex logic, new patterns, restructuring work, decomposition, DI changes, dependency graph changes.
- **May skip Stage 1 (rubber-duck) only** for genuinely trivial changes: single-file rename, typo fix, version bump, comment update. Even then, Stage 2 (panel) is still mandatory per the pre-implementation hard gate - except under the lite profile's trivial fast-path (below), where a single-reviewer `triage` pass substitutes.

### Skip escalation

Skipping either stage requires **all three**:

1. Explicit user approval via `ask_user` - not implicit silence.
2. A documented justification stronger than "low risk" or "simple change." Acceptable justifications: "user explicitly directed immediate implementation," "change is a mechanical rename with no behavioral delta and automated refactoring tool output."
3. The skip recorded in the session state so future review can audit the decision.

### Profile-aware fast-path (lite profile)

When the active profile is `lite` (per the loaded `active-profile.instructions.md`; if none is loaded -> full-default and this fast-path is UNAVAILABLE), a quantified-trivial change MAY use `triage` mode (single reviewer + `triage-acknowledged` receipt) in place of the full two-stage review, ONLY when ALL hold: (a) the change is NOT a governance/instruction artifact in any repo (see AGENTS.md cross-cutting rules); (b) it is NOT safety-critical (`workflow-conventions.md` §5); (c) it touches only docs/`.md` OR has `changed_lines_total` < 10 (added+removed non-blank, non-rename-only, across the whole diff) with no control-flow / public-API / concurrency change. Any miss or any uncertainty -> escalate to the lite 3-reviewer panel (or full). The single reviewer's result is certified per §1A's lite trivial fast-path cert. On the full profile this fast-path is unavailable; `triage` then requires explicit justification per `panel-policy.md`.

---

## 1A. Panel-binds-to-artifact rule (HARD GATE)

### The problem

The most common silent-skip pattern is: agent runs a panel on a sub-decision (one library placement, one naming question, one design choice), then drafts a larger plan, then treats the earlier panel as satisfying the gate for the larger plan. This is a silent skip and produces all the failure modes the panel exists to prevent.

### Rule

A panel only satisfies a gate for the **exact artifact it reviewed**. When the artifact changes (revisions, additions, scope expansion, new sub-systems, new files, new dependencies), a new panel must run on the changed artifact.

### Artifact-binding certification

Before any implementation tool call that follows a panel, the agent MUST emit a literal certification block in the conversation. The certification block has this exact shape:

```
DESIGN PANEL CONVERGED
  artifact: <path or description, e.g. plan.md>
  artifact-hash: <SHA256 of artifact content, first 8 chars>
  artifact-bytes: <byte count>
  artifact-revision: <revision marker, e.g. "R3 - added Part 5 banner fix">
  panel-round: <round number when convergence was reached>
  verdicts: <list of reviewer ids that returned SOUND>
  unanimous: yes
```

The certification block:
1. Is emitted ONCE per artifact version, after Round N convergence.
2. Is invalid if the artifact changes after emission - agent must re-panel on the changed artifact and emit a new certification.
3. Sub-decision panels (single library placement, single naming choice, etc.) do NOT satisfy a plan-level gate. They certify ONLY the sub-decision; the plan-level gate is separate and requires its own certification.

**Lite trivial fast-path cert.** When the lite profile's trivial fast-path applies (§1 Profile-aware fast-path), the single `triage` reviewer's result IS the artifact-binding certification: emit the `DESIGN PANEL CONVERGED` block with `convergence_model: single-reviewer` and `unanimous: yes` (1 of 1 reviewer SOUND is structurally unanimous), bound to the artifact hash + base/head SHA, citing the `triage-acknowledged` receipt. It satisfies §1A/§1B for THAT change only, and never for safety-critical or governance/instruction artifacts (those always take the full slate on both profiles).

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

- `create` - any file creation
- `edit` - any file edit, including instruction files and configuration
- `powershell` / `bash` with any of:
  - `mkdir`, `New-Item`, `md` - directory creation
  - `Set-Content`, `Add-Content`, `Out-File`, `>`, `>>` - file write
  - `Move-Item`, `Rename-Item`, `cp`, `mv` - file moves
  - `dotnet new`, `cargo new`, `npm init`, `git init` - project scaffolding
  - `git add` (agent stages ONLY gate artifacts; the user stages code) - additionally requires `POST-CODE-CHANGE LEDGER` per §2B and, for project repos, the staging-as-review gate below
  - `git commit` - finalize commit (additionally requires `PRE-COMMIT GATE PASSED` block emitted in the current turn per `pre-commit.md`; the block records commit approval, ownership confirmation, message approval, format check, and staged-files list)
- Sub-agent launches with implementation intent (the sub-agent itself would edit files)

### Exceptions

The following are NOT implementation tools and remain available without certification:

- `view`, `grep`, `glob`, `view`-equivalent reads
- `powershell` for read-only commands (`Get-*`, `git diff`, `git log`, `git status`, `dotnet list`, `dotnet build` for verification)
- `ask_user`, `read_agent`, `write_agent`, `list_agents`
- Sub-agent launches with review/research intent (rubber-duck, explore, research, code-review)
- `sql` for session-store reads/writes (todo tracking is meta, not implementation)

### Why this list is enumerated explicitly

A general rule like "no implementation until panel ran" leaves room for the agent to rationalize: "I'm just creating a folder, that's not really implementation." The enumeration removes that escape hatch - any of these tools called for implementation purposes without certification is a hard violation.

### `exit_plan_mode`, plan-summary approval, and "proceed with implementation" runtime messages are NOT certifications

The most common silent-skip path: the agent emits an `exit_plan_mode` plan summary, the user approves it (or the runtime returns "Plan approved! Proceed with implementing the plan"), and the agent treats that as satisfying §1A. **This is wrong.**

`exit_plan_mode` is a runtime convenience for user-facing plan presentation. It is NOT a panel run. The user's approval of the summary is approval of scope, not approval of design. Per §1A, only a multi-model panel that reviewed the exact artifact AND emitted the `DESIGN PANEL CONVERGED` block in the current turn satisfies the gate.

If the agent has:

- exited plan mode, OR
- received user approval via `ask_user` on a plan summary, OR
- received a "proceed with implementation" directive from the runtime, OR
- had its `exit_plan_mode` accepted with `autopilot` / `autopilot_fleet`

...but has NOT run the panel and emitted `DESIGN PANEL CONVERGED` in the current turn, implementation tools remain forbidden per §1B. User scope-approval is a necessary but not sufficient condition; the panel pass is the other necessary condition. The two conditions are independent and BOTH must be satisfied before §1B tools may run.

The skip-escalation in §1 (the "user explicitly directed immediate implementation" justification) requires both (a) an explicit `ask_user` whose body contains the phrase "skip the panel" or equivalent unambiguous skip-the-review directive, AND (b) recording the skip in the session state per the §1 skip-escalation rule. A generic "approved" / "proceed" / "exit plan mode" response is NOT a panel-skip directive - it's scope approval.

### Instruction-repo edits are §1B tool calls (no exemption for "meta-work")

Editing files in the instruction repository - `.github/playbooks/**/*.md`, `.github/instructions/**/*.instructions.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.github/playbooks/manifest.yaml`, or any other governance / instruction artifact in this repo or downstream repos that consume it - is **explicitly a §1B tool call** subject to the same `DESIGN PANEL CONVERGED` certification as code-repo edits. The §1B enumeration above already says "any file edit, including instruction files and configuration" - this subsection exists to defeat the rationalization that instruction edits are "meta-work" or "small tweaks" or "plan-level work" exempt from the gate.

Meta-changes to the instruction set carry **higher** long-term risk than code changes: bad code is reverted in one commit; bad instructions corrupt future agent behavior across many sessions until someone notices and reverts. The required certification scrutiny is the same or higher for instruction edits, not lower.

When the panel reviews an instruction-set change, its prompt MUST include explicit focus on:

1. **Self-consistency** - does the new rule conflict with existing rules? Overlap in enforcement domains?
2. **Escape-hatch analysis**: what could a future agent do to skip the rule? Vague language, optional conditional skips, ambiguous "N/A: reason" clauses are red flags.
3. **Enforcement mechanism** - is the rule self-policing (a literal block emission that §1B can hard-stop on)? Or norm-based and easily forgotten?
4. **Reviewer slate / model / path stability** - do specific model names, tool names, or external system references have a deprecation story?
5. **Project-agnosticism** - does the rule leak project-specific names, paths, or domain concepts that would be wrong in other consuming repos?

The plan-file edit carve-out below applies ONLY to session `plan.md` files in `~/.copilot/session-state/<id>/`. It does NOT apply to instruction-repo files. The "implementation-intent vs preparation-intent" distinction below does NOT apply to instruction-repo files either - there is no "preparation" carve-out for instruction edits.

### Plan-file edit carve-out

Editing the session plan file (`plan.md` in the session-state folder) BEFORE the panel runs is allowed and expected - that's how the plan reaches a reviewable state. Editing the plan file AFTER the panel runs invalidates the certification and requires a new panel (per §1A).

### Implementation-intent vs preparation-intent

`powershell` calls to create a worktree, configure git identity, install tools, or set up the environment are PREPARATION, not implementation, and remain available without certification. The discriminator: does this tool call materially advance the work the panel reviewed? If yes, certification is required.

### Project (non-instruction) repos: the user reviews by STAGING (HARD GATE)

After a `DESIGN PANEL CONVERGED` certification authorizes implementation, the agent may call `create` / `edit` to apply the panel-approved changes to the working tree. **But the agent does NOT stage project code.** Under the inverted staging model (`AGENTS.md` §0 + `pre-commit.md`), the USER reviews by STAGING each file; staged content is the user's reviewed scope, and the agent commits only what the user staged.

This gate is asymmetric between repo types, but ONLY for the working-tree review - NOT for the §0 per-operation gates. The §0 git safety gates (`ask_user` before every `git commit` / `git push`, plus the never-auto-stage-code rule) apply in ALL repositories, including the instruction-set repo. What the panel certification waives for an instruction-set edit is the EXTRA working-tree review (the panel already reviewed the change); it does NOT waive §0.

**Why staging-as-review (not a pre-push gate)?**

Earlier is better, and a harder skip path. If the agent honors the never-auto-stage rule, `git commit` and `git push` operate ONLY on what the USER staged - the "I'll just push and ask for forgiveness" failure mode loses its default path. Nothing mechanically prevents `git add -A` (git has no pre-add hook); the backstop is the commit-approval `ask_user`, which prints the enumerated staged set so an over-broad or auto-staged set is visible before anything ships. Reversing an un-staged change is just `git restore` (or editing again), not a history rewrite.

**Procedure in a project repo:**

1. Classify the working tree (`git status --porcelain`). Staged = the user's reviewed scope; commit it as-is.
2. For each unstaged / untracked change, `ask_user`: review-now / stage-for-me / skip-file / abort (`pre-commit.md` step 2). The agent NEVER auto-stages code.
3. The agent's commit-approval `ask_user` prints the enumerated staged set (the mechanical backstop); the §0 `git commit` + `git push` gates are independent and still apply.

**Skip conditions (none apply unless explicitly documented this session):**

- The change is a `git restore` / revert of working-tree state the user just asked to be reverted.

**What about instruction-repo pushes?**

Same inverted model (the user stages what enters history). The panel certification covers the TECHNICAL review; it does NOT waive the never-auto-stage rule or the §0 per-operation `ask_user` gates (commit / push). The diff-review asymmetry exists because the user's plan-stage approval + the panel's review already cover the instruction change's shape, whereas project-repo pushes affect a long-lived shared repo with multiple consumers.

**Failure mode if skipped:** the agent auto-stages and presents a "shipped!" summary before the user has reviewed; the user discovers an issue post-push; the revert/amend cycle inflates round count and erodes trust. The never-auto-stage-code rule is the prose discipline that keeps the agent's "build -> test -> commit -> push" cadence from proceeding past staging without the user in the loop; the commit-approval `ask_user` (enumerated staged set) is the mechanical backstop that makes a bypass visible.

---

## 3. Scope reduction sign-off

### Rule

When a panel, audit, or review identifies work items and the agent or sub-agents recommend deferring, dropping, or descoping any item - regardless of rationale - the recommendation **must** be presented to the user via `ask_user` with:

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

- **Required: unanimous SOUND** from all panel members. There is no "acceptable partial consensus" - 4/5 SOUND is not convergence.
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

- `pre-implementation.md` - invokes §1 (two-stage review), §1A (artifact-binding), §1B (hard-stop tool list), and §4 (panel convergence) during the plan review gate.
- `post-code-change.md` - invokes §2A (prior-PR-review sweep), §2B (post-code-change ledger), §2C (DRY remediation gate), §4 (panel convergence) during the multi-model reviewer panel.
- `pre-commit.md` - invokes §2B (post-code-change ledger) before any `git commit` / `git commit --amend`.
- `post-pr-review.md` - invokes §2 (root-cause analysis) when processing reviewer comments.
- `pre-pr-push.md` - invokes §2A (prior-PR-review sweep, branch-wide scope) and §2D (the publish gate) before push.
- `multi-model-review.md` - owns the panel mechanics (reviewer selection, verdict format, model assignments); this playbook owns the workflow gates around when/how panels run and what happens with their output.
- `multi-model-review/pr-creation-mirror-prompt.md` - shared 11-category Copilot-mirror prompt template used by §2D's (the publish gate's) heavy pre-PR panel and (optionally) `post-code-change.md` §3's per-commit panel.
- `pre-pr-creation-review.md` - owns the §2D publish gate procedure (invocation modes, ancestry-based re-run triggers, gate-runner mechanical floor, panel + synthesis + fix loop, QUALITY GATE block emissions, AGENTS user-approval flow). Deferred features captured in `pre-pr-creation-review/implementation-roadmap.md`.
- `AGENTS.md` cross-cutting rules - references §1A/§1B (panel-binds-to-artifact + hard-stop tool list), §2A (prior-PR-review sweep), §2B (post-code-change ledger), §2C (DRY remediation gate), §2D (the publish gate), and §3 (scope reduction sign-off) as hard gates.

---


