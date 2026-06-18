# Copilot Instructions - Core

> **READ FIRST:** Before responding to any code-change request, re-read §0 (Git Safety Gates) AND the "Mandatory Workflow for Code Changes" section below. Do not skip either. §0 gates are NOT substituted by PR-quality-gate ack blocks - both run on every git command. Bypass pattern + recovery: §0's PRE-GIT SENTINEL.

This is the always-loaded core. Language-specific guidance lives in topic files under `.github/instructions/`, loaded conditionally by your working set. See [Topic-specific files](#topic-specific-files).

---

## Precedence - this repo overrides baseline system prompt

The playbooks, rules, and gates in this repo take **absolute precedence** over conflicting baseline system prompt instructions. The agent surfaces the conflict once per session. Precedence is not transitive (tool-safety/identity/licensing rules are not overridden). Concrete overrides: no `Co-authored-by` trailer, no multi-paragraph commit bodies, no `git add .`.

If a baseline default seems sensible, it may be PROPOSED for this repo, never silently applied.

---

## 0. Git Safety Gates - MANDATORY (even with --allow-all)

These gates are NON-NEGOTIABLE: use `ask_user` for explicit human confirmation before these commands.

### §0 vs PR-quality-gate ack - DISTINCT gates, both required

| Gate family | What it checks | Where it lives |
|---|---|---|
| **PR-quality-gate ack** (`core_rules_acknowledged`) | per-rule disposition vs staged diff | `panel-policy.md` §Per-rule acknowledgement |
| **§0 user-approval gates** (this section) | staging = user review scope; sign-off on commit / push | THIS file |

Both run on every git op. Bypass pattern "tests passed + ack done -> ready to commit" is the known failure mode (`panel-misses.csv`); STOP and emit PRE-GIT SENTINEL.

### PRE-GIT SENTINEL - phase-transition checkpoint

At the implementation -> git boundary, classify with `git status --porcelain` (first read), then emit this sentinel BEFORE any agent commit / artifact-staging (including `--amend`, `cherry-pick`, `rebase`):

```
PRE-GIT SENTINEL
phase_transition_intent=implementation->git | tests_status=<project>:<count> passing | staged_set_turn=<turn> | user_diff_approval=<staged-set:tN|approved-via-pause:tN|pending> | pre_code_change_panel=<ran:unanimous|na|user-waived> | post_code_change_panel=<ran:unanimous|na|user-waived> | pre_commit_gate_block_emitted=pending | next_action=classify+commit-approval
```

- LEADING checkpoint - fires BEFORE `pre-commit.md`'s `PRE-COMMIT GATE PASSED` block.
- A summary-only PRE-GIT SENTINEL is not inherited - re-emit (no inherited approval).
- Panel `READY` does NOT clear this sentinel. Emitting it does NOT satisfy `ask_user`.

### git add - the USER stages (review signal)

Prose rule (no pre-add hook): the user stages reviewed files; the agent NEVER auto-stages code (`git add .`/`-A` forbidden), staging ONLY its gate artifacts. Unstaged -> `ask_user`: review-now | stage-for-me | skip-file | abort. Protocol: `pre-commit.md`.

### git commit

Before ANY `git commit`:
1. Present the message + the staged file set (flag unexpected paths).
2. `ask_user` to approve / edit / reject.
3. Execute only after the user explicitly approves the final message.
4. If the user edits it, use their version exactly.
5. NEVER `--no-verify` (commit also `-n`) on `git commit`/`git push`. A hook bypass is itself a §0 action: `ask_user` the reason, execute only on approval.

### git push --force / --force-with-lease

1. Use `--force-with-lease` - NEVER bare `--force` / `-f`.
2. `ask_user` confirming intent + commit range being replaced.
3. Execute only after approval.

### git push (non-force, including first push of a new branch)

1. `ask_user` confirming push intent + target remote/branch + commit range.
2. Execute only after approval. A "new branch" is NOT a free pass.

### gh pr create

Before ANY `gh pr create`:
1. `pre-pr-creation-review.md` (§2D) must have emitted `PRE-PR REVIEW COVERAGE` with `READY-pending-user-approval`. Absent -> STOP, run §2D first.
2. Present PR title, body, target branch.
3. `ask_user` with full details (approve / edit / reject).
4. Re-emit `PRE-PR REVIEW COVERAGE` with `READY-re-emitted-after-user-approval` (same-state re-check) in the same turn as the invocation.
5. Execute only after step 4 + the user's step-3 approval.

---

## 1. Mandatory Workflow for Code Changes

Apply to ANY code change (no "small change" exceptions). Each phase is required. If you believe a change is too trivial, ASK before skipping. This section is a **phase index**: hard-gate checklist (always-loaded) + STOP directive to the playbook. Procedures live in `.github/playbooks/`.

### Mandatory pre-tool reads

Before executing the listed tool call, the matching file(s) MUST have been viewed this phase. Gate blocks carry `reads=<file>@<token>` per the read-receipt convention below.

| Trigger (tool or transition) | Required on-demand read(s) |
|---|---|
| `git add` / `git commit` (any form) | `.github/playbooks/pre-commit.md` |
| `gh pr create` / PR-creation tools | `.github/playbooks/pre-pr-creation-review.md` |
| First-review `git push` | `.github/playbooks/pre-pr-push.md` |
| Entering post-code-change (after edits, before showing diff) | `.github/playbooks/post-code-change.md` |
| About to add/rewrite a comment | `.github/playbooks/comment-protocol.md` |
| Editing code files | the matching `.github/instructions/*` topic file(s) - view-on-demand, receipt-gated |

### Read-receipt convention

Gate blocks depending on an on-demand file include a `reads=<file>@<token>` field (`<token>` = that file's `read-receipt-token:` header value). `check-read-receipts` (commit) + the pre-push reads-note re-validation mechanically reject a CODE-topic citation (`.github/instructions/*` with a non-`**/*` `applyTo`) that is missing or stale; other on-demand reads stay convention. Each file carries its 8-hex `read-receipt-token:` in an HTML comment after its H1 - the ONLY token source, extracted at verify time (no central map). `read-receipts.tsv` lists the receipt files.

### Workflow router - which playbook to view based on the situation

| User intent / condition | Required playbook |
| --- | --- |
| Code edit requested, before implementation | `pre-implementation.md` |
| Files changed and diff not yet shown | `post-code-change.md` |
| User approved diff / asks to commit | `pre-commit.md` |
| User asks to push, open PR, request review | `pre-pr-push.md` (INDEX) |
| PR exists / review comments present | `post-pr-review.md` |
| Strong design-spec trigger (durable artifact request) | OFFER `design-spec.md` |
| Strong ADO trigger (draft NEW work item content) | OFFER `ado-task-planning.md` |
| Strong GitHub-to-ADO replication trigger | OFFER `github-to-ado-replication.md` |
| Strong least-privilege-audit trigger | OFFER `least-privilege-audit.md` |
| Install / upgrade / uninstall software | `software-install.md` |
| Create or restructure a worktree | `worktree-setup.md` |
| `scope-planning` / `project-vocabulary` / `implementation-planning` / `system-framing` strong trigger | OFFER matching playbook (see `manifest.yaml`) |
| `codebase-architecture-audit` / `design-exploration` / `performance-comparison` / `library-restructure` strong trigger | OFFER matching playbook (see `manifest.yaml`) |
| `multi-model-review` strong trigger | OFFER `multi-model-review.md` |
| Strong cross-file-bug-investigation trigger | OFFER `cross-file-bug-investigation.md` |
| Test-writing context within pre-implementation / post-code-change | AUTO-FIRE `intent-driven-testing.md` |
| About to add/rewrite a comment | AUTO-FIRE `comment-protocol.md` |
| Editing any file in the instruction-set repo | `instruction-set-maintenance.md` |

All playbook paths are under `.github/playbooks/`. Domain triggers always confirmed via `ask_user`; phase triggers are mandatory. Phrase examples are illustrative; route by intent shape. Per-playbook frontmatter and `manifest.yaml` are discoverability aids only.

### Workflow conventions (ask-first, intake pre-fill, trigger detection, user-skip policy)

**Always-loaded invariants:**
- Ask-first principle: every playbook's Intake Questions run FIRST before any output. Phase triggers are mandatory; domain triggers are offered via `ask_user`.
- User-skip policy: safety-critical skips (multi-model panel on non-trivial changes, branch-wide sweep for review pushes, verification-of-fix, pre-impl panel on any safety-critical class) require explicit user RE-CONFIRMATION before proceeding. Safety-critical includes at minimum: concurrency, security, crypto, native-interop, payment, auth, shared-state, data-integrity/schema/migration, destructive/irreversible ops, permissions/ACL, secrets/credentials, privacy/PII, release/deploy/CI, governance/instruction artifacts (canonical list in `workflow-conventions.md` §5; if uncertain, treat as safety-critical). All skips are recorded in session todos with warning. When in doubt whether a skip is safety-critical, default to "yes - re-confirm".
- Record phase entry/exit in session todos per the phase-state convention.

> **STOP.** For the full ask-first procedure, intake pre-fill rules, strong-vs-weak trigger detection, user-skip recording mechanics, and phase-state tracking convention, view `.github/playbooks/workflow-conventions.md` and `.github/playbooks/phase-state-convention.md`.

### Pre-implementation phase

Hard gates (always apply, even if playbook unfetched):

- Diagnosis verified (reproduce, minimise, hypothesise, instrument, reproduction-locked).
- Reproduction (bug fix) or benchmark (perf work) exists.
- Multi-model panel (target-type: `plan`), unanimous convergence, 0 blocking, `subagent_ask_user_calls=0`. **Profile-aware:** the active profile (`active-profile.instructions.md`; none loaded -> full-default) sets the default panel mode + slate floor (full = 4-6; lite = 3 cross-family light-tier); both keep unanimous convergence. Lite trivial fast-path = `triage` (single-reviewer) ONLY when all active-profile LITE-FAST-PATH predicates hold + a `triage-acknowledged` receipt; safety-critical OR governance/instruction artifacts -> full slate on both profiles. Emit `profile=<full|lite|full-default>`.
- **Rubber-duck-then-panel mandatory.** Skipping either needs explicit panel-skip approval - approval of the change REQUEST (the WHAT) is NOT it (§1 in `review-workflow-gates.md`); the lite `triage` fast-path is the sole sanctioned exception.
- **PRE-EDIT SENTINEL.** Before the FIRST `create`/`edit`/file-write/`git add`/impl sub-agent in a code/governance change, emit: `PRE-EDIT SENTINEL | change_class=<code|governance|trivial> | pre_impl_panel=<ran:unanimous|user-waived:ref:<call-ref>|na:not-panel-required> | next_action=<run-panel|edit>`. If `change_class!=trivial`: `pre_impl_panel` MUST be `ran:unanimous` (PANEL CONVERGED emitted, §1A) or `user-waived:ref` BEFORE `next_action=edit`; `na` only for trivial; governance/instruction artifacts are NEVER trivial; tier-2 forbids `user-waived`/`na`; revised plan -> new panel; read tools OK pre-panel. Prose-class (no edit-time hook; git-time §2B backstops). A summary-only PANEL CONVERGED / PRE-EDIT SENTINEL is NOT inherited - re-establish before the next edit.
- **Pre-PR-creation review (§2D).** >=4 reviewer panel on full branch diff before PR-creation tools. Full procedure in `pre-pr-creation-review.md`.
- **Per-rule acknowledgement (§1A.1).** `core_rules_acknowledged` block lists each HIGH-tier slug in `HIGH-TIER-SLUGS.md` with `status: applied | not-applicable | violated` + per-site `file:line:disposition` + rationale. Schema in `panel-policy.md`.
- **Anti-recidivism (§1A.2).** PRs with `panel-misses.csv` entries: `verified-no-recurrence` per slug with `fix_evidence`.
- **Full-scan-against-new-rule (§1A.3).** Catalog edits from bot findings: full-diff scan immediately.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-implementation.md`.

### Post-code-change phase

Hard gates:

- **Hygiene cleanup runs whole-solution** (not just touched files) for moves/renames/namespace changes.
- **Touched-file least-privilege audit.** Trigger: visibility/export/mutability surface delta. All 6 axes; fresh grep is non-negotiable.
- **Touched-file VSA audit.** Trigger: new type/file, move/rename, root-level addition, multi-type file.
- **Recurring-pattern sweep with findings count.** MANDATORY on every commit-bound change; silent skip is the failure mode.
- **Prior-PR-review sweep.** Two-scope: current PR thread + last 10 merged PRs (§2A in `review-workflow-gates-sweeps.md`).
- **DRY remediation gate.** Refactor where 2+ files share >=5 identical lines (§2C in `review-workflow-gates-sweeps.md`). DRY gate output shape: `ran, <N> duplications, <K> refactored, <J> waived`.
- Multi-model panel, unanimous convergence, 0 blocking, `subagent_ask_user_calls=0`.
- §3.1 comment audit evidence-gate output.
- Diagnosis-verifying re-run passes.
- Affected builds + tests pass.
- **Post-code-change ledger emitted before commit.** Without it in current turn, the commit is forbidden (§2B in `review-workflow-gates-sweeps.md`). Ledger enumerates every gate with status `ran` | `N/A: <reason>` | `user-waived: "<quote>"`.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-code-change.md`.

### Pre-commit phase

Hard gates:

- **Staged set approved.** User stages = review; commit-approval shows it. ALL commit ops (incl. `--amend`/cherry-pick/rebase); no "trivial amend" exemption.
- **Ledger emitted before commit.** Fresh each commit; previous-turn waivers do not carry forward (§2B in `review-workflow-gates-sweeps.md`).
- **Agent never auto-stages code.** Stages only artifacts; code only via `stage-for-me`, else pauses (`pre-commit.md` step 2).
- **Panel READY != user-review.** Both independent; both must pass on project repos.
- **Author identity verified per §4.1.** Preserved author also checked on amend/replay.
- **Commit ownership confirmed** with `the agent`/`you (the user)` labels.
- **Message approved** via separate `ask_user` before `git commit` runs.
- Single-line; no Conventional-Commit prefix; no `Co-authored-by`; no body/footer.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-commit.md`.

### Pre-PR-push phase

Hard gates:

- **Push credentials verified per §4.2** (every push including sandbox). `blocked` = gate fails.
- Per-commit comment audit on every commit's diff.
- Branch-wide rename-first sweep before first review push.
- **Branch-wide least-privilege audit** when diff shows visibility/export/mutability delta.
- **Branch-wide VSA audit** when diff adds/moves/renames types or files.
- **Branch-wide prior-PR-review sweep** (two-scope against full branch diff; §2A in `review-workflow-gates-sweeps.md`).
- **No internal plan markers** in PR titles or bodies.
- State read-back (11-field predicate) before claiming ready.
- No "ready to push" until all gates done OR explicitly skipped with warning.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-pr-push.md` (INDEX with deterministic decision tree).

### Post-PR-review phase

Hard gates:

- Each bot finding verified against source before applying / dismissing.
- Sub-agent findings outside scope routed via `ask_user`; never silently dropped.
- Per-finding audit output per `post-pr-review.md` step 6 (C2 status enum + `subagent_ask_user_calls=0`).
- Instructions-file delta proposed for each fixed comment (project-agnostic).
- **PR review comments are hard blockers.** Root-cause each, sweep similar patterns across the diff, update instructions on a revealed gap. Procedure: `review-workflow-gates-sweeps.md` §2.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-pr-review.md`.

### Trigger workflows - hard gates (always apply, even before fetching)

**Design-spec:** Intake first. Template separation (survey/change-request/dev-spec). Claims grounded in source. Assumptions marked. Draft in chat; user approves before write.

**ADO task planning:** Intake first. Both outputs together. Testable acceptance criteria. Deliverables are nouns. No invented IDs. Draft in chat; user approves before write.

**Least-privilege-audit** (sub-step of `post-code-change.md`/`pre-pr-push.md`): Fresh grep beats cached survey. All 6 axes for every public type. Per-type matrix with consumer evidence. Whole-scope search. Friend-asm verified. NEW friend-grant is LAST resort. Framework-mandated visibility flagged, not auto-tightened. All languages.

> **STOP.** Before drafting design-spec / ADO output, OR invoking least-privilege audit, view the matching playbook.

### Fail-closed rule for on-demand playbook fetch

If a required playbook cannot be fetched: (1) retry once; (2) if still fails, `ask_user` how to proceed; (3) if user authorizes skip, record per User-skip policy; (4) if `ask_user` unavailable (headless), halt and do NOT certify readiness. Do not proceed on the hard-gate checklist alone - the playbook teaches the procedure. Playbook paths are relative to the instruction-set repo root (the `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` entry holding this `AGENTS.md`), not cwd.

### Cross-cutting rules (always apply, no fetch needed)

- **Pre-existing issues:** route via 4-status C2 enum (`fixed`/`routed-now`/`routed-deferred`/`dismissed-source-grounded`). Do NOT add `TODO`/`FIXME`/`HACK` comments. Includes sub-agent findings outside scope.
- **`ask_user` is the default C2 routing;** bypass requires explicit citation. A finding mentioned without `ask_user`/cited C2 bypass = silently dropped. Reviewer labels ("out of scope") are NOT source-grounded dismissals.
- **Scope reduction requires explicit user sign-off** via `ask_user` (§3 in `review-workflow-gates.md`).
- **Audit step before declaring ready.** Confirm every sub-agent finding routed via C2 with citation. Emit C2 audit output (`subagent_ask_user_calls=0`).
- **Sub-agents must NEVER prompt the user** (every prompt includes *"Do not call `ask_user`; return findings only"*) or introduce comments via `edit` (propose in the return value; orchestrator runs the §3.1 gate).
- **Unintended reverts:** ASK before reverting code that was previously removed/refactored/renamed.
- **Do NOT report ready** until every phase completed or explicitly skipped with recorded warning.
- **Sub-agent model selection.** Resolve tier via `multi-model-review/current-model-registry.md` (rubber-duck/general=heavy-claude-standard, code-review/security=heavy-claude-xhigh, explore=light-claude-balanced, panels=per `intake.md` item 4).
- **Governance/instruction artifacts are safety-critical (never the lite fast-path).** Any file governing agent behavior or the instruction set - `AGENTS.md`, `.github/instructions/**`, `.github/playbooks/**`, `.github/copilot-instructions.md`, `.github/pr-quality-gate/**`, in ANY repo - always full review rigor, both profiles.
- **Instruction-set maintenance.** STOP + view `.github/playbooks/instruction-set-maintenance.md` before any instruction-repo edit.
- **Output: caveman-terse.** Results over narration; no lead-ins. Never shortens a forcing-function gate block (emit those in full, caveman form).

---

## 2. Commit Messages

- **Single line only.** No body, no footers, no trailers.
- **Suppress `Co-authored-by: Copilot` trailer.** Use `-m "<message>"` only.
- **Describe the change**, not which plan item. No `A2`, plan numbers, or Conventional-Commit prefixes.
- **Imperative mood, no trailing period.**

Examples: OK: `Defer CategoryDisplayName join until first read` / BAD: `perf: defer CategoryDisplayName join (A2)` / BAD: any trailer.

> §4 governs commit author identity and push authentication; this section governs message content only.

---

## 3. General Coding Standards

These standards apply to **every** code change, in every language. Reviewers reject PRs that violate them. Language-specific additions in `.github/instructions/` topic files.

### 3.1 Comments

**Over-commenting is the most common style violation across past PRs. The default answer to "should I add a comment here?" is NO.**

- **Default: no comments.** Code is the primary documentation. Names carry intent.
- **Three-step comment protocol - HARD GATE on every NEW or rewritten comment.** Step 1: clarity check (names already clear? -> no comment). Step 2: rename check (better name carries the fact? -> rename + drop). Step 3: `ask_user` approval gate (on reject/no-response -> DROP). **Headless -> DROP, never block.** Categorical bans not reachable via step 3; default-OFF rules reachable but HIGH bar. Sub-agents: proposed in return value only. Exempt categories: `typo`|`deletion`|`stale-comment-fix-per-§3.9/§3.10`|`generated`|`vendored`|`THROWAWAY-header`. Full procedure in `.github/playbooks/comment-protocol.md`.
- **Hard prohibitions** (no exceptions):
  - No comments restating code. No "why we're about to do this" narration. No multi-line `//` design-decision prose. No speculation about future callers/surfaces. No restating contract terms encoded in naming/signature. No `TODO`/`FIXME`/`HACK`/`XXX`. No panel-artifact references (`Slot N`, `Round N`, etc.). No test section-separator banners. No comments restating a test's name.
- **Allowed** (rare; short + load-bearing + not inferable): non-obvious algorithmic invariant; external-constraint workaround; deliberate trade-off.
- **Self-review pass:** every new/rewritten comment must have valid `approval_turn:` citation; missing -> delete.
- **Remove stale comments** when touching surrounding code.

> **STOP.** Before adding ANY new comment, view `.github/playbooks/comment-protocol.md`.

> **C# adds:** XML doc comment rules. See `csharp.instructions.md`.

General coding standards (naming, tests, perf, defaults, state predicates, deferred mutations, user-facing text, recurring smells, project/folder structure) live in two auto-loaded files: `coding-standards.instructions.md` (universal, loaded on every edit) covers naming, ambiguous-naming-ask, opportunistic rename, defaults/consistency, and user-facing text; `coding-standards-code.instructions.md` (loaded on code edits) covers tests, performance, state predicates, deferred mutations, recurring smells, and project/folder structure.

### 3.14 No em-dashes or smart punctuation (HARD BAN)

**Never emit U+2014 (em-dash), U+2013 (en-dash), U+2015 (horizontal bar), U+2018/U+2019 (curly single quotes), U+201C/U+201D (curly double quotes), or U+2026 (ellipsis) anywhere** - code, comments, docs, strings, Markdown, commits, PR text, chat prose. Replace with ASCII equivalents.

- **Pre-commit/post-code-change scan (HARD GATE).** Grep diff added lines for banned code points; any hit fails closed. Recorded as `emdash-scan` ledger row.
- **Authoring rule (always on).** Never type a banned code point in ANY output.
- **Exemptions.** Only vendored/generated/third-party files the change does not author.

---

## 4. Git Identity & Push Credentials

Both **commit attribution** (`user.name`/`user.email`) AND `git push` **authentication** MUST belong to the human user - never a "disallowed automation identity" (case-insensitive: `Copilot`, `copilot[bot]`, `github-actions[bot]`, `223556219+Copilot@users.noreply.github.com`, any `[bot]`-suffixed account, any non-user service principal). A session authenticating as the human's own GitHub account is fine.

Always-loaded. Procedure in `pre-commit.md` (§4.1) and `pre-pr-push.md` Pre-check 0 (§4.2).

### 4.1 Commit author identity - hard gates

- **No automation-identity injection** via any scope of `git config`, `[include]`/`[includeIf]`, `git -c` flags, `--author`, or env vars (`GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL`/`EMAIL`).
- **Prompt-when-missing.** Before any commit-producing op: verify `git var GIT_AUTHOR_IDENT`/`GIT_COMMITTER_IDENT` (including env overrides) are non-empty + non-disallowed; for `--amend`/`cherry-pick`/`rebase`/`am`, check preserved author too. On fail: `ask_user`, write **local** (global requires opt-in). NEVER guess from machine username.
- **`--reset-author` constrained** to disallowed-automation only. Never overwrite legitimate human author.
- **Don't touch commit signing.** Surface signing failures via `ask_user`; never bypass with `--no-gpg-sign`.
- **Actor labels in prompts:** literal `the agent`/`you (the user)`. Display resolved identity + scope. No bare `I`/`me`/`you`. Commit-ownership separate from push-ownership.

### 4.2 Push authentication - hard gates

- **Applies to EVERY push** including sandbox-exits and implicit ref-publishing commands.
- **No agent/automation principal.** No Copilot credentials, `[bot]` accounts, ambient `GH_TOKEN`/`GITHUB_TOKEN`/`GIT_ASKPASS`/`SSH_AUTH_SOCK` UNLESS user confirms user-owned.
- **Mechanism-aware verification:** HTTPS+`gh` -> `gh api user --jq .login`; system credential helper -> `ask_user`; SSH -> `ssh -T` greeting; ambient env -> default `blocked`.
- **No silent re-auth.** Never run `gh auth login/refresh/switch` or `git credential approve/fill/erase`.
- **Push-ownership SEPARATE from commit-ownership.** Same actor labels. Display verified principal.
- **Recorded as `pushCredentialsVerified`** (required predicate field): `yes`/`user-confirmed-unverifiable`/`blocked`. `blocked` = gate fails.

### 4.3 Composition

- §2 forbids `Co-authored-by` trailer (message-side mirror of §4.1).
- `pre-commit.md` Step 3 applies §4.1. `pre-pr-push.md` Pre-check 0 applies §4.2.
- **Always-loaded scope.** §4 applies to ad-hoc commits/pushes outside formal phases too.

---

## 9. Repository & Worktree Layout Preference

Use **single-root + hidden-bare-repo + sibling-checkouts** for parallel checkouts.

> **STOP.** Before creating/restructuring/repairing a worktree, view `.github/playbooks/worktree-setup.md`.

---

## 10. Software Installation & Upgrades

**Prefer the platform package manager** (`winget`/`brew`/distro native) over hand-rolled downloads.

> **STOP.** Before installing/upgrading/uninstalling software, view `.github/playbooks/software-install.md`.

---

## Topic-specific files

Files under `.github/instructions/` load automatically when matching files are in the working set:

| File | Loads when | Adds |
|---|---|---|
| `csharp.instructions.md` | `**/*.cs`, `**/*.csx`, `**/*.csproj`, `**/*.razor`, `**/*.cshtml`, `**/*.aspx` | C# XML-doc, project structure, access modifiers, file/folder organization |
| `csharp-style.instructions.md` | (same C# glob) | C# naming conventions, formatting, member ordering, expression preferences |
| `csharp-runtime.instructions.md` | (same C# glob) | Async/disposal lifecycle, return-value contracts, concurrency primitives |
| `csharp-smells.instructions.md` | (same C# glob) | C#-specific recurring code smells from PR reviews |
| `csharp-testing.instructions.md` | `**/*Tests*/**/*.cs`, test `.csproj` variants | C# test layout, naming, constants, TestUtils |
| `csharp-testing-quality.instructions.md` | (same test glob) | Test purpose, audit-and-delete framework |
| `csharp-testing-sync.instructions.md` | (same test glob) | Alternative test patterns, test synchronization |
| `coding-standards.instructions.md` | `**/*` | §3.2, §3.3, §3.3.1, §3.6, §3.9: naming, ambiguous-naming-ask, opportunistic rename, defaults/consistency, user-facing text |
| `active-profile.instructions.md` (generated by setup; gitignored) | `**/*` | Active profile (full/lite) parameters; none present -> full-default. Templates in `profiles/`; see `README.md`. |
| `coding-standards-code.instructions.md` | `**/*.{cs,csx,razor,cshtml,cpp,h,hpp,cc,cxx,c,ts,tsx,mts,cts,js,jsx,mjs,cjs,py,go,rs,java,kt}` | §3.4-§3.5, §3.7-§3.8, §3.10-§3.13: tests, perf, state predicates, deferred mutations, recurring smells, structure |
| `cpp.instructions.md` | `**/*.cpp`, `**/*.h`, `**/*.hpp`, `**/*.cc`, `**/*.cxx`, `**/*.c` | C++ naming, formatting, COM patterns, vcxproj |
| `msbuild.instructions.md` | `**/*.csproj`, `**/*.props`, `**/*.targets`, `**/*.vcxproj` variants | MSBuild escaping, Exec trim, tool acquisition |
| `javascript-typescript.instructions.md` | `**/*.ts`, `**/*.tsx`, `**/*.js`, `**/*.jsx` variants | JS/TS naming, formatting, imports |
| `html.instructions.md` | `**/*.html`, `**/*.htm`, `**/*.razor`, `**/*.cshtml` | HTML formatting, accessibility |
| `css.instructions.md` | `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less` | CSS naming, formatting, property order |

**To add a new topic file:** create `<topic>.instructions.md` with `applyTo:` YAML frontmatter. See `README.md`.
