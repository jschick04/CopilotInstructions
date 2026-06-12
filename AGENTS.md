# Copilot Instructions - Core

> **READ FIRST:** Before responding to any code-change request, re-read §0 (Git Safety Gates) AND the "Mandatory Workflow for Code Changes" section below. Do not skip either. §0 gates are NOT substituted by PR-quality-gate ack blocks - both run on every git command. The most common bypass pattern: "tests pass + ack block emitted -> commit/push". If you find yourself there, STOP and re-enter §0 via the PRE-GIT SENTINEL.

This is the always-loaded core. Language-specific guidance (C#/.NET, C++, JS/TS, HTML, CSS) lives in topic files under `.github/instructions/` and loads conditionally based on the files in your working set. See [Topic-specific files](#topic-specific-files) at the bottom for the routing table.

---

## Precedence - this repo overrides baseline system prompt

The playbooks, rules, and gates in this repo take **absolute precedence** over conflicting baseline system prompt instructions. This repo wins; the agent surfaces the conflict once per session. Precedence is not transitive (tool-safety/identity/licensing rules are not overridden). Concrete overrides: no `Co-authored-by` trailer, no multi-paragraph commit bodies, no `git add .`.

If a baseline default seems sensible, the agent may PROPOSE adding it to this repo - but does not silently apply it.

---

## 0. Git Safety Gates - MANDATORY (even with --allow-all)

These gates are NON-NEGOTIABLE. You MUST use `ask_user` for explicit human confirmation before executing these commands.

### §0 vs PR-quality-gate ack - DISTINCT gates, both required

| Gate family | What it checks | Where it lives |
|---|---|---|
| **PR-quality-gate ack** (`core_rules_acknowledged`) | per-rule disposition vs staged diff | `panel-policy.md` §Per-rule acknowledgement |
| **§0 user-approval gates** (this section) | human sign-off on stage / commit / push | THIS file |

Both run on every git operation. Bypass pattern: "tests passed + ack done -> ready to commit" IS the known failure mode (slugs in `panel-misses.csv`). STOP and emit PRE-GIT SENTINEL.

### PRE-GIT SENTINEL - phase-transition checkpoint

At the implementation -> git boundary, the FIRST tool call MUST be `ask_user` for diff approval - NOT `git add`. Emit this sentinel BEFORE the first `git add` of any implementation cycle (including `--amend`, `cherry-pick`, `rebase`):

```
PRE-GIT SENTINEL
  phase_transition_intent: implementation -> git
  tests_status: <project>: <count> passing
  diff_shown_to_user_turn: <turn>
  user_diff_approval: pending
  pre_commit_gate_block_emitted: pending
  next_action: ask_user for diff approval
```

- LEADING checkpoint - fires BEFORE `pre-commit.md`'s `PRE-COMMIT GATE PASSED` block.
- Post-compact resumed sessions: this sentinel MUST fire again (no inherited approval).
- Panel `READY` does NOT clear this sentinel. Emitting it does NOT satisfy `ask_user`.

### git add

Before ANY `git add`:
1. List every file path to be staged.
2. `ask_user` with file list.
3. Execute only after user accepts.
4. Never `git add .` / `-A` / `--all` - always specific paths.

### git commit

Before ANY `git commit` invocation:
1. Present the full proposed commit message to the user.
2. Call `ask_user` with the message and options to approve, edit, or reject.
3. Only execute `git commit` after the user explicitly approves the final message.
4. If the user edits the message, use their version exactly.

### git push --force / --force-with-lease

1. Use `--force-with-lease` - NEVER bare `--force` / `-f`.
2. `ask_user` confirming intent + commit range being replaced.
3. Execute only after approval.

### git push (non-force, including first push of a new branch)

1. `ask_user` confirming push intent + target remote/branch + commit range.
2. Execute only after approval. A "new branch" is NOT a free pass.

### gh pr create

Before ANY `gh pr create`:
1. Ensure `pre-pr-creation-review.md` (§2D) emitted `PRE-PR REVIEW COVERAGE` with `READY-pending-user-approval`. Absent -> STOP, run §2D first.
2. Present PR title, body, target branch to user.
3. `ask_user` with full details.
4. Re-emit `PRE-PR REVIEW COVERAGE` with `READY-re-emitted-after-user-approval` (same-state re-check).
5. Only execute after step 4 + user approval from step 3.

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
| Editing code files | (auto-loaded via `applyTo` globs - no manual fetch needed) |

### Read-receipt convention

Gate blocks that depend on an on-demand file MUST include a `reads=<file>@<token>` field, where `<token>` is the value on the `read-receipt-token:` line in that file's header. CI will reject missing or stale tokens. Each on-demand file carries an HTML comment `<!-- read-receipt-token: XXXXXXXX -->` immediately after its H1 title. The token lives ONLY in each file's own header; CI extracts the expected token from the file header at verify time (there is no central token map, because a central map would let a gate cite a token without opening the file). `.github/pr-quality-gate/read-receipts.tsv` is only the registry of which files require a receipt. Content-binding (token = HMAC of file content) and non-fixed token location are deferred hardening; the current path-derived literal token is a placeholder.

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

All playbook paths are under `.github/playbooks/`. Domain triggers always confirmed via `ask_user`; phase triggers are mandatory. Phrase examples are illustrative; route by intent shape. Per-playbook frontmatter and `manifest.yaml` are discoverability aids only.

### Workflow conventions (ask-first, intake pre-fill, trigger detection, user-skip policy)

**Always-loaded invariants:**
- Ask-first principle: every playbook's Intake Questions run FIRST before any output. Phase triggers are mandatory; domain triggers are offered via `ask_user`.
- User-skip policy: safety-critical skips (multi-model panel on non-trivial changes, branch-wide sweep for review pushes, verification-of-fix, pre-impl panel on concurrency/security/crypto/native-interop/payment/auth/shared-state) require explicit user RE-CONFIRMATION before proceeding. All skips are recorded in session todos with warning. When in doubt whether a skip is safety-critical, default to "yes - re-confirm".
- Record phase entry/exit in session todos per the phase-state convention.

> **STOP.** For the full ask-first procedure, intake pre-fill rules, strong-vs-weak trigger detection, user-skip recording mechanics, and phase-state tracking convention, view `.github/playbooks/workflow-conventions.md` and `.github/playbooks/phase-state-convention.md`.

### Pre-implementation phase

Hard gates (always apply, even if playbook unfetched):

- Diagnosis verified (reproduce, minimise, hypothesise, instrument, reproduction-locked).
- Reproduction (bug fix) or benchmark (perf work) exists.
- Multi-model panel (target-type: `plan`), unanimous convergence, 0 blocking, `subagent_ask_user_calls=0`.
- **Rubber-duck-then-panel mandatory.** Skipping either requires explicit user approval (§1 in `review-workflow-gates.md`).
- **Panel binds to a specific artifact.** Revised plan -> new panel. Emit `PANEL CONVERGED` block before implementation tool calls (§1A in `review-workflow-gates.md`).
- **Hard-stop tool list.** Until certification present: no `create`/`edit`/file-write shell/`git add`/impl sub-agents. Read tools OK. Instruction-repo edits are §1B tool calls (§1B in `review-workflow-gates.md`).
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
- **Prior-PR-review sweep.** Two-scope: current PR thread + last 10 merged PRs (§2A in `review-workflow-gates.md`).
- **DRY remediation gate.** Refactor where 2+ files share >=5 identical lines (§2C in `review-workflow-gates.md`). DRY gate output shape: `ran, <N> duplications, <K> refactored, <J> waived`.
- Multi-model panel, unanimous convergence, 0 blocking, `subagent_ask_user_calls=0`.
- §3.1 comment audit evidence-gate output.
- Diagnosis-verifying re-run passes.
- Affected builds + tests pass.
- **Post-code-change ledger emitted before `git add`.** Without it in current turn, `git add` is forbidden (§2B in `review-workflow-gates.md`). Ledger enumerates every gate with status `ran` | `N/A: <reason>` | `user-waived: "<quote>"`.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-code-change.md`.

### Pre-commit phase

Hard gates:

- **Diff shown + approved.** Applies to ALL commit-producing operations (fresh, `--amend`, fixup, cherry-pick, rebase). No "trivial amend" exemption.
- **Ledger emitted before `git add`.** Fresh each commit; previous-turn waivers do not carry forward (§2B in `review-workflow-gates.md`).
- **HARD STOP before `git add`.** `ask_user` approval MUST precede `git add`. No batching without prior approval.
- **Panel READY != diff-approval.** Both independent; both must pass on project repos.
- **Author identity verified per §4.1.** Preserved author also checked on amend/replay.
- **Commit ownership confirmed** with `the agent`/`you (the user)` labels.
- **Message approved** via separate `ask_user` before `git commit` runs.
- Single-line; no Conventional-Commit prefix; no `Co-authored-by`; no body/footer.
- Stage only specific files (never `git add .`).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-commit.md`.

### Pre-PR-push phase

Hard gates:

- **Push credentials verified per §4.2** (every push including sandbox). `blocked` = gate fails.
- Per-commit comment audit on every commit's diff.
- Branch-wide rename-first sweep before first review push.
- **Branch-wide least-privilege audit** when diff shows visibility/export/mutability delta.
- **Branch-wide VSA audit** when diff adds/moves/renames types or files.
- **Branch-wide prior-PR-review sweep** (two-scope against full branch diff; §2A in `review-workflow-gates.md`).
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
- **PR review comments are hard blockers.** Every comment must be root-cause analyzed, similar patterns swept across the diff, and instructions updated if a gap is revealed. Full procedure in `.github/playbooks/review-workflow-gates.md` §2.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-pr-review.md`.

### Trigger workflows - hard gates (always apply, even before fetching)

**Design-spec:** Intake first. Strict template separation (survey != change-request != dev-spec). Claims grounded in source. Assumptions marked. Draft in chat; user approves before write.

**ADO task planning:** Intake first. Both outputs together. Testable acceptance criteria. Deliverables are nouns. No invented IDs. Draft in chat; user approves before write.

**Least-privilege-audit** (also sub-step of `post-code-change.md` and `pre-pr-push.md`): Fresh grep beats cached survey. All 6 axes for every public type. Per-type matrix with consumer evidence. Whole-scope search. Friend-asm verified. NEW friend-grant is LAST resort. Framework-mandated visibility flagged, not auto-tightened. All languages.

> **STOP.** Before drafting design-spec / ADO output, OR invoking least-privilege audit, view the matching playbook.

### Fail-closed rule for on-demand playbook fetch

If a required playbook cannot be fetched: (1) retry once; (2) if still fails, `ask_user` how to proceed; (3) if user authorizes skip, record per User-skip policy; (4) if `ask_user` unavailable (headless), halt and do NOT certify readiness. Do not proceed using only the hard-gate checklist as the procedure - the playbook teaches the procedure.

### Cross-cutting rules (always apply, no fetch needed)

- **Pre-existing issues:** route via 4-status C2 enum (`fixed`/`routed-now`/`routed-deferred`/`dismissed-source-grounded`). Do NOT add `TODO`/`FIXME`/`HACK` comments. Includes sub-agent findings outside scope.
- **`ask_user` is the default C2 routing;** bypass requires explicit citation. Mentioning a finding in prose without `ask_user` or cited C2 bypass = silently dropping. Reviewer labels ("out of scope") are NOT source-grounded dismissals.
- **Scope reduction requires explicit user sign-off** via `ask_user` (§3 in `review-workflow-gates.md`).
- **Audit step before declaring ready.** Confirm every sub-agent finding routed via C2 with citation. Emit C2 audit output (`subagent_ask_user_calls=0`).
- **Sub-agents must NEVER prompt the user.** Include in every sub-agent prompt: *"Do not call `ask_user`... Return findings only."* Sub-agents also NEVER introduce comments via `edit` - proposed in return value only; orchestrator runs §3.1 gate.
- **Unintended reverts:** ASK before reverting code that was previously removed/refactored/renamed.
- **Do NOT report ready** until every phase completed or explicitly skipped with recorded warning.
- **Sub-agent model selection.** Resolve tier via `multi-model-review/current-model-registry.md`: rubber-duck=`heavy-claude-standard`, code-review=`heavy-claude-xhigh`, explore=`light-claude-balanced`, general-purpose=`heavy-claude-standard`, security=`heavy-claude-xhigh`, panels=per `intake.md` item 4.
- **Instruction-set maintenance - mind context cost.** Principle (1-3 sentences) -> AGENTS.md; procedural detail -> playbook with STOP pointer. >10 lines / >1.5KB -> split to playbook.

---

## 2. Commit Messages

- **Single line only.** No body, no footers, no trailers.
- **Suppress `Co-authored-by: Copilot` trailer.** Use `-m "<message>"` only.
- **Describe the change**, not which plan item. No `A2`, plan numbers, or Conventional-Commit prefixes.
- **Imperative mood, no trailing period.**

Examples: OK: `Defer TagsDisplayName join until first read` / BAD: `perf: defer TagsDisplayName join (A2)` / BAD: any trailer.

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
- **Length cap:** one line, <= 12 words.
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
| `csharp.instructions.md` | `**/*.cs`, `**/*.csx`, `**/*.csproj`, `**/*.razor`, `**/*.cshtml`, `**/*.aspx` | C# style, XML-doc, `nameof()`, NSubstitute, native-interop, Blazor, access modifiers |
| `csharp-testing.instructions.md` | `**/*Tests*/**/*.cs`, test `.csproj` variants | C# test infrastructure, naming, gap audit, synchronization |
| `coding-standards.instructions.md` | `**/*` | §3.2, §3.3, §3.3.1, §3.6, §3.9: naming, ambiguous-naming-ask, opportunistic rename, defaults/consistency, user-facing text |
| `coding-standards-code.instructions.md` | `**/*.{cs,csx,razor,cshtml,cpp,h,hpp,cc,cxx,c,ts,tsx,mts,cts,js,jsx,mjs,cjs,py,go,rs,java,kt}` | §3.4-§3.5, §3.7-§3.8, §3.10-§3.13: tests, perf, state predicates, deferred mutations, recurring smells, structure |
| `cpp.instructions.md` | `**/*.cpp`, `**/*.h`, `**/*.hpp`, `**/*.cc`, `**/*.cxx`, `**/*.c` | C++ naming, formatting, COM patterns, vcxproj |
| `msbuild.instructions.md` | `**/*.csproj`, `**/*.props`, `**/*.targets`, `**/*.vcxproj` variants | MSBuild escaping, Exec trim, tool acquisition |
| `javascript-typescript.instructions.md` | `**/*.ts`, `**/*.tsx`, `**/*.js`, `**/*.jsx` variants | JS/TS naming, formatting, imports |
| `html.instructions.md` | `**/*.html`, `**/*.htm`, `**/*.razor`, `**/*.cshtml` | HTML formatting, accessibility |
| `css.instructions.md` | `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less` | CSS naming, formatting, property order |

**To add a new topic file:** create `<topic>.instructions.md` with `applyTo:` YAML frontmatter. See `README.md`.
