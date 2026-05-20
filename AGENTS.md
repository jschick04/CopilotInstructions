# Copilot Instructions — Core

> **READ FIRST:** Before responding to any code-change request, re-read the "Mandatory Workflow for Code Changes" section below. Do not skip it.

This is the always-loaded core. Language-specific guidance (C#/.NET, C++, JS/TS, HTML, CSS) lives in topic files under `.github/instructions/` and loads conditionally based on the files in your working set. See [Topic-specific files](#topic-specific-files) at the bottom for the routing table.

---

## 1. Mandatory Workflow for Code Changes

Apply to ANY code change (no exceptions for "small" changes). Each phase is required, not optional. If you believe a change is too trivial to warrant the cycle, ASK before skipping.

This section is a **phase index**, not a procedure. Each phase has a small **hard-gate checklist** (the rules that must hold for the phase to count as completed — these stay always-loaded so they apply even if the playbook fetch fails) plus a **STOP directive** telling you which playbook to view before taking any action in that phase. The detailed procedures live in `.github/playbooks/`.

### Workflow router — which playbook to view based on the situation

| User intent / condition | Required playbook |
| --- | --- |
| Code edit requested, before implementation | `.github/playbooks/pre-implementation.md` |
| Files changed and diff not yet shown | `.github/playbooks/post-code-change.md` |
| User approved diff / asks to commit | `.github/playbooks/pre-commit.md` |
| User asks to push, open PR, request review, or push to a shared branch others may pull from | `.github/playbooks/pre-pr-push.md` (an INDEX — fetch sub-files per its decision tree) |
| PR exists / review comments present | `.github/playbooks/post-pr-review.md` |
| Strong design-spec trigger — user is asking for a **durable artifact** (verb-led: *"design spec for"*, *"write up a design for"*, *"document the current architecture of"*, *"document what we have in prod for"*; or noun-led: *"current-state survey for"*, *"design change request for"*, *"dev design spec for"*, *"implementation spec for"*, *"build spec for"*, *"architect review of"*) | OFFER `.github/playbooks/design-spec.md` (always-confirm via `ask_user`) |
| Strong ADO trigger — user is asking to **draft a NEW work item or its content** (verb-led: *"draft an ADO work item for"*, *"plan out an ADO task / story / feature for"*, *"write up an ADO bug for"*, *"create the deliverables for"*, *"draft / propose / write acceptance criteria for"*; or noun-led: *"ADO task / story / work item for"*, *"acceptance criteria for a new work item"*). Factual questions about **existing** ADO content (*"what acceptance criteria does the parent feature use?"*, *"what's our team's definition of done?"*) are NOT strong — those are weak triggers; answer directly and offer the playbook only if the user is asking to draft new content. | OFFER `.github/playbooks/ado-task-planning.md` (always-confirm via `ask_user`) |
| Strong least-privilege-audit trigger — user is asking for an **API tightening / visibility audit / access-modifier sweep / surface-area review** (verb-led: *"tighten the API surface for"*, *"audit visibility on"*, *"sweep access modifiers in"*, *"do a least-privilege pass on"*; or noun-led: *"least-privilege audit of"*, *"API tightening report for"*, *"visibility audit of"*, *"access-modifier matrix for"*). Bare unpaired *"audit"* / *"review"* falls into the ambiguous artifact-adjacent category and triggers one short clarifying `ask_user`. | OFFER `.github/playbooks/least-privilege-audit.md` (always-confirm via `ask_user`) |
| Install / upgrade / uninstall software | `.github/playbooks/software-install.md` |
| Create or restructure a worktree | `.github/playbooks/worktree-setup.md` |
| `scope-planning` strong trigger | OFFER `.github/playbooks/scope-planning.md` (see `manifest.yaml`) |
| `project-vocabulary` strong trigger | OFFER `.github/playbooks/project-vocabulary.md` (see `manifest.yaml`) |
| `implementation-planning` strong trigger | OFFER `.github/playbooks/implementation-planning.md` (see `manifest.yaml`) |
| `system-framing` strong trigger | OFFER `.github/playbooks/system-framing.md` (see `manifest.yaml`) |
| `codebase-architecture-audit` strong trigger (read-only audit; NOT a durable design-spec) | OFFER `.github/playbooks/codebase-architecture-audit.md` (see `manifest.yaml`) |
| `design-exploration` strong trigger (throwaway prototype) | OFFER `.github/playbooks/design-exploration.md` (see `manifest.yaml`) |
| `performance-comparison` strong trigger (throwaway perf prototype) | OFFER `.github/playbooks/performance-comparison.md` (see `manifest.yaml`) |
| `library-restructure` strong trigger | OFFER `.github/playbooks/library-restructure.md` (see `manifest.yaml`) |
| `multi-model-review` strong trigger (also utility-callable by `post-code-change.md`) | OFFER `.github/playbooks/multi-model-review.md` (see `manifest.yaml`) |
| Test-writing context within pre-implementation / post-code-change | AUTO-FIRE `.github/playbooks/intent-driven-testing.md` (sub-step) |

**Phrase examples are illustrative, not exhaustive.** The semantic discriminator below (artifact-requested vs exploratory-question) is canonical — when a user phrasing is novel, route by intent shape, not by phrase matching. Per-playbook frontmatter and `.github/playbooks/manifest.yaml` are discoverability aids only — they do NOT drive detection; the router governs.

### Pre-implementation phase

Hard gates (always apply, even if playbook unfetched):

- Diagnosis verified via deepened procedure (reproduce → minimise → hypothesise → instrument → reproduction-locked per `pre-implementation.md` Step 1).
- Reproduction (bug fix) or benchmark (perf work) exists. Artifact type (throwaway harness vs durable regression test) chosen at intake.
- G3 (Step 1.5 in-scope approach-selection) + G5 (Step 2 entry safety-critical-skip) per `pre-implementation.md`.
- Rubber-duck pass run unless user explicitly skipped (G5 escalates to safety-critical when triggers fire).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-implementation.md`.

### Post-code-change phase

Hard gates:

- **Pre-commit hygiene cleanup runs whole-solution, not just touched files** — moves and rename refactors leave stale `using`s and over-qualified type references in *consumer* files that the diff doesn't list. Restrict the cleanup to the using/qualifier hygiene diagnostics so it doesn't churn unrelated style (collection initializers, expression preferences, etc.). Touched-file imports / usings sorted and unused removed.
- **Touched-file least-privilege audit applied.** Trigger: the diff has any **visibility / export / mutability surface delta** — adds a public/exported type or member; widens visibility; removes `sealed` / `final` / closed-extension; adds or widens a constructor / member / setter; exposes a field; changes package / module exports; introduces an exported Go top-level identifier; widens Rust `pub(...)` to bare `pub`. Each such delta is justified by a real same-file / same-asm / cross-asm consumer. Unjustified additions are demoted before the diff is shown. Do NOT trigger on body-only edits to an already-public type that change no surface. Procedure: run `least-privilege-audit.md` (touched-file scope) — applies all 6 axes (type access, sealing/final, ctor visibility, member visibility, setter, field hygiene). The "fresh grep beats cached survey" rule is non-negotiable.
- **Touched-file review-recurring-pattern sweep run with explicit findings count reported** (per `post-code-change.md` step 2.5). MANDATORY on every commit-bound change, no matter how small — silent skip ("I don't think it applies", "the diff is too small to need it") is the failure mode this gate exists to prevent. Agent MUST output a one-line-per-pattern report (`Step 2.5 sweep: ran, N findings. - <pattern>: N matches`) in the message before showing the diff. `N/A` allowed only when a pattern's trigger condition definitionally cannot apply (e.g., no test files in diff for "test-class-vs-file-name"); "I don't think it applies" is NOT a valid skip reason.
- Multi-model reviewer panel via `multi-model-review.md` (utility) unanimous convergence; 0 unaddressed blocking; `subagent_ask_user_calls=0`.
- §3.1 comment audit evidence-gate output per `post-code-change.md` step 2.6 (before diff shown).
- Diagnosis-verifying benchmark / test re-run; metric moved or test passes.
- Affected builds + tests pass.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-code-change.md`. That playbook references `.github/playbooks/least-privilege-audit.md` for the touched-file 6-axis pass.

### Pre-commit phase

Hard gates:

- Diff shown to user; explicit approval received.
- **Commit author identity verified per §4.1** — `git config user.name` / `user.email` AND `git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT` resolve to a non-empty human identity (not a "disallowed automation identity" per §4); for `--amend` / `cherry-pick` / `rebase` / `am`, the preserved author + committer on the target commit are ALSO not disallowed automation identities. On missing OR disallowed identity, prompt the user via `ask_user`; write LOCAL repo scope by default (`git config --local`); promote to global ONLY on explicit user opt-in (boolean, default false). NEVER guess identity from machine username, GitHub session principal, or any other heuristic.
- Commit ownership confirmed (user vs agent) — the `ask_user` prompt MUST display the resolved `<user.name> <<user.email>>` + scope, AND use the literal labels `the agent` / `you (the user)` in both message body and option titles (no bare `I` / `me` / `you`). Push-ownership is asked SEPARATELY in pre-PR-push — never bundled.
- Single-line commit message; no Conventional-Commit prefix; no `Co-authored-by` trailer; no body / footer.
- Stage only touched files (`git add <path>` — never `git add .`).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-commit.md`.

### Pre-PR-push phase

Hard gates:

- **Push credentials verified as the user's per §4.2** — applies to EVERY push (including personal-sandbox / backup pushes that exit the review-readiness playbook at the sandbox pre-check, AND ref-publishing commands that implicitly push such as `gh pr create` against an un-pushed branch). Mechanism-aware verification (HTTPS+`gh` → `gh api user --jq .login`; HTTPS+system credential helper → user-confirm via `ask_user` when helper can't expose principal; SSH → `ssh -T git@<host>` greeting; ambient `GH_TOKEN` / `GITHUB_TOKEN` / `GIT_ASKPASS` / `SSH_AUTH_SOCK` → STOP unless user confirms). Recorded as `pushCredentialsVerified` (10th predicate field) — values `yes` / `user-confirmed-unverifiable` / `blocked`. A `blocked` value fails the readiness gate. Push-ownership `ask_user` is SEPARATE from commit-ownership (never bundled) and uses the same explicit `the agent` / `you (the user)` actor labels.
- Per-commit comment audit run on every commit's diff (already gated by §3.1 on each commit — verify it actually ran).
- Branch-wide rename-first sweep run once before first push intended for review.
- **Branch-wide least-privilege audit run** when `git diff <base>..HEAD` shows any **visibility / export / mutability surface delta** (same definition as the touched-file gate above) across the branch. Multiple small commits each individually fine can together leak too-public surface; the branch-wide pass re-greps with the final branch state. Procedure: run `least-privilege-audit.md` (branch-wide scope, restricted to the projects whose surface the branch touches). Skipped only when the branch has no visibility / export / mutability surface delta — that fact recorded explicitly with the justifying file list. Run AFTER any branch-wide rename-first sweep cleanup has been committed / amended, so the audit sees the final branch state. Fresh grep at audit time; cached classifications from earlier in the branch are stale.
- **No internal plan markers in PR titles or bodies.** PR title + body are public artifacts and must be readable without access to the planning artifacts. Forbidden in both: session plan IDs (`T1`, `F16e-2`, `FX-3`, `C5`, etc.), session file paths (`files/foo-audit.md`, `aa2fde9c/plan.md`), upstream commit SHAs that won't survive a rebase, and stage / phase markers from the agent's internal task tracker. Acceptable: the actual SUT names being modified, the actual behavior change being shipped, the actual test count delta. Audit the title + body for these markers BEFORE running `gh pr create` / `gh pr edit`; the cost of a rewrite later is higher than the 10-second pre-flight check.
- Resolved sweep base SHA + sweep HEAD SHA + base ref name **recorded in canonical session todos** (per *Phase-state tracking convention* below) for re-run logic.
- State read-back output per `pre-pr-push.md` before claiming ready (zero-count carve-out) — includes the 10-field state predicate (incl. `pushCredentialsVerified`) plus `sandboxPriorExposureConfirmation` informational field.
- No "ready to push" claim until push credentials verified (§4.2), per-commit audit, branch-wide sweep, AND branch-wide least-privilege audit (when applicable) are done OR user explicitly skipped (with recorded warning).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-pr-push.md`. That file is an INDEX — it runs intake first, then directs you to the matching sub-files (`per-commit-micro-hygiene.md`, `branch-wide-sweep.md`, `cleanup-commit-buckets.md`, `when-to-re-run-sweep.md`) per a deterministic decision tree. The least-privilege-audit playbook (`.github/playbooks/least-privilege-audit.md`) is a sibling invocation when the branch touches public API surface.

### Post-PR-review phase

Hard gates:

- Each bot finding verified against source before applying / dismissing.
- Sub-agent findings outside scope routed via `ask_user`; never silently dropped.
- Per-finding audit output per `post-pr-review.md` step 6 (C2 status enum + `subagent_ask_user_calls=0`).
- Instructions-file delta proposed for each fixed comment (project-agnostic).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-pr-review.md`.

### Trigger workflows — hard gates (always apply, even before fetching)

The strong-trigger workflows in the router table — design-spec, ADO task planning, and least-privilege audit — also have always-loaded hard gates so the agent doesn't lose critical invariants if the playbook can't be fetched. These are abbreviated; the playbooks have the full procedure.

**Design-spec hard gates:**

- Intake completed (mode = current-state survey OR design-change request OR dev design spec) before any drafting.
- Strict template separation: a current-state survey does NOT propose changes; a design-change request does NOT embed a full current-state survey (use linked-pair pattern — link to a standalone survey if one exists, or include a strictly-bounded "Current State Summary — provisional" with no tables / diagrams / subsections / failure-mode catalogs / file inventories, and no code-fenced schemas / configs / samples longer than 5 lines — full tripwire list lives in the playbook); a dev design spec assumes the change has already been approved at the design-change level and answers *"how do we ship it?"* — it does NOT debate the change.
- Every claim about real systems grounded in source via `view` / `grep` / `explore`. No invented component names, file paths, GUIDs, IDs, or behaviors.
- Assumptions marked explicitly as `*(ASSUMED — not verified in source)*`.
- Draft rendered in chat first; user explicitly approves before any file write.

**ADO task planning hard gates:**

- Intake completed (work item type, title, audience, output destination) before any drafting.
- Both outputs (markdown summary + ADO-field-formatted text) produced together; format-shifted versions of the same canonical content per the mapping table in the playbook.
- Acceptance criteria are testable — each answers *"how would we know this is done?"*.
- Deliverables are nouns (artifacts), not verbs (activities).
- No invented linked work-item IDs; only IDs the user provides.
- Draft rendered in chat first; user explicitly approves before any file write.

**Least-privilege-audit hard gates** (also fires automatically as a sub-step of `post-code-change.md` for touched-file scope and `pre-pr-push.md` for branch-wide scope):

- "Fresh grep" = a fresh source search using the best tool for the language (`rg`, compiler index, language-server symbol search, package-export inspection, etc.) — not literally `grep(1)`. Beats every cached classification: survey docs, prior audit notes, checkpoints are HINTS only, never ground truth. When you find a contradiction with a prior survey, record it explicitly so the survey can be corrected.
- All 6 axes evaluated for every public type in scope (type access / sealing-or-final / ctor visibility / member visibility / setter / field hygiene). Type-level internalization is one of six axes, not the only one.
- Per-type matrix as output, with consumer evidence (file:line citations from the actual grep) for every internalization recommendation.
- Whole-scope consumer search — when auditing a project, search the WHOLE solution / workspace, not just the declaring project. Cross-project consumers are exactly what the audit checks for.
- Friend-asm / module-export mechanism verified before recommending internalization. Check the relevant metadata for the language / project: C# csproj `<InternalsVisibleTo>` AND `Properties\AssemblyInfo.cs` (when present), Java `module-info.java` `exports ... to`, Kotlin module / Gradle friend paths, TypeScript `package.json` `exports` subpaths, Rust crate / module visibility, Go `internal/` directory pattern, etc. Don't recommend `internal` without confirming the corresponding grant; if missing, the recommendation is *internalize-and-add-friend-grant* (one extra change to surface to the user).
- Friend-grant proliferation is a coupling cost across ALL languages — adding a NEW friend-grant (C# IVT, Java `module-info` export, Kotlin friend-path, TS `package.json` exports entry, etc.) exposes ALL current AND future internals of the granting asm/module to the receiving one. Default precedence when faced with KEEP-PUBLIC vs ADD-NEW-FRIEND-GRANT for a single cross-asm consumer: (1) split-member visibility (public type, internal-only members where possible), (2) co-locate the type with its consumer, (3) keep public, (4) add new friend-grant (LAST resort). Re-using an existing friend-grant is free; adding a new one is not. Full ladder + per-language techniques in the playbook.
- Framework-mandated visibility (Razor `[Parameter]`, Spring beans, EF Core proxies, Fluxor reducers, etc.) flagged with NOTE, not auto-recommended for tightening.
- Applies to ALL languages (C#, Java, Kotlin, TypeScript, Rust, Go, C++, Swift, Python by convention) — see the per-language tooling table in the playbook.

> **STOP.** Before drafting any design-spec / ADO output, OR before invoking the least-privilege audit at any scope, view the matching playbook for the full intake + procedure.

### Fail-closed rule for on-demand playbook fetch

Playbook files under `.github/playbooks/` are NOT auto-loaded — the agent fetches them via `view` when entering a phase or accepting a trigger. If a required playbook **cannot** be fetched (file moved / renamed / unreadable / repo not in working set / fetch errors out), do NOT certify the phase complete. Bounded retry-then-escalate:

1. **Retry the fetch once** — for transient errors (network blip, CLI tool flake). Do NOT retry more than once without user input; unbounded retry hangs the session.
2. If the second attempt also fails, **ask the user via `ask_user` how to proceed** (e.g. *"the post-code-change playbook can't be fetched — is the file present? Do you want me to skip the multi-model panel for this change, or pause until the file is restored?"*). Surface the actual error message and the playbook path that failed.
3. If the user explicitly authorizes a skip, **record an explicit user skip per the User-skip policy below** (canonical mechanism, with reason "playbook fetch failed").
4. **Hard stop when `ask_user` is unavailable** (headless / non-interactive contexts where step 2's `ask_user` cannot reach a user — same condition as the User-skip policy *Hard stop when ALL recording paths fail* rule below): halt the phase and do NOT certify readiness. Surface a non-zero exit / failure signal to the runtime if one is available. The cascade has no authorized skip, so the workflow cannot proceed.

Do **not** proceed using only the abbreviated hard-gate checklist as the procedure — the checklist confirms the gate, the playbook teaches the procedure. Hard-gate-only execution silently degrades the phase (e.g. running one reviewer instead of the five-model parallel panel) while believing the gate passed.

### Cross-cutting rules (always apply, no fetch needed)

- **Pre-existing issues** (also referenced from playbooks as the *"Pre-existing issues / `ask_user` is mandatory"* cross-cutting rule): if you find one that could be or is causing an issue, route it via the canonical 4-status C2 enum per `multi-model-review/evidence-gate-spec.md` — `fixed` (apply the change), `routed-now` (via `ask_user`, user decides this turn), `routed-deferred` (external-record citation required — session todo / issue / tracker URL), or `dismissed-source-grounded` (source citation refuting the finding required). **Do NOT add a `TODO` / `FIXME` / `HACK` comment in code** (per §3.1 hard prohibitions).
- **This includes findings surfaced by sub-agents** (rubber-duck, code-review, etc.) that are tangentially related but **outside the current task or PR scope**. Apply the same C2 routing — do NOT silently expand scope to fix them, do NOT silently drop them.
- **`ask_user` is the default C2 routing**; `dismissed-source-grounded` and asymptotic-auto `routed-deferred` are the only bypass paths and both REQUIRE explicit citation in the C2 evidence-gate output. Mentioning a sub-agent finding inside your final review summary, the diff walkthrough, the "ready to commit" message, or any other prose without either a paired `ask_user` call OR a properly-cited C2 bypass entry counts as silently dropping it. Reviewer-applied labels — "out of scope," "pre-existing," "not introduced by this change," "low severity" — are NOT in themselves source-grounded dismissals; they are the reviewer's opinion, not your decision to make on the user's behalf.
- **Audit step before declaring ready.** Before saying any variant of "ready to commit" / "all reviewers agree" / "no remaining issues," confirm every sub-agent finding has been routed via one of the 4 C2 statuses (per `multi-model-review/evidence-gate-spec.md`) with the required citation. Emit C2 audit output (status enum + citation + `subagent_ask_user_calls=0`). If any finding lacks a C2 status, stop and route via `ask_user` first.
- **Sub-agents must NEVER prompt the user.** Reviewer / rubber-duck / code-review / explore / general-purpose / research and any other background or sync sub-agent runs autonomously — the user is typically away from the keyboard while panels are in flight, and the parallel-launch design assumes no agent will block on input. Every sub-agent prompt MUST include the explicit instruction *"Do not call `ask_user` or any other tool that prompts the user. If the task is ambiguous, make a reasonable assumption, document it in your output, and continue. Return findings only."* The orchestrator (you) is the **only** agent allowed to call `ask_user` — collect findings from all sub-agents, then surface decisions to the user yourself per the routing rules above. Sub-agents that block on user input deadlock the panel, defeat the point of background execution, and leave the user with nothing actionable when they return.
- **Unintended reverts:** if you see code that was removed, refactored, or renamed that differs from a previous change you made, ASK before reverting.
- **Do NOT report the task ready to push / ready to open the PR** until every required phase has either (a) been completed for every committed work cycle (per the relevant playbook's hard gates) or (b) been explicitly skipped by the user with a recorded warning. (The preamble's "ASK before skipping" rule is the only escape hatch — never self-judge a change as exempt.)
- **Sub-agent model selection defaults.** Override the runtime default model on every sub-agent launch to maximize reasoning depth:
  - **Rubber-duck** passes: `model: 'claude-opus-4.7'`.
  - **Standalone code-review**: `model: 'claude-opus-4.7-xhigh'`.
  - **Explore** agents for architecture, design-spec grounding, or multi-module cross-cutting investigation: `model: 'claude-sonnet-4.6'`. Simple single-file lookups may use the default.
  - **General-purpose** sub-agents doing reasoning-heavy work (debugging, synthesis, migration planning, ambiguity resolution): `model: 'claude-opus-4.7'`.
  - **Security-review**: `model: 'claude-opus-4.7-xhigh'`.
  - **Multi-model review panels**: exact per-slot models defined in `multi-model-review/intake.md` item 4 (canonical source).
- **Instruction-set maintenance — mind the context cost.** Every line in `AGENTS.md` / `.github/instructions/*.md` is loaded into every matching session forever; adding paragraphs raises the prompt cost of every future session unrelated to the new rule. **Hard check before editing any always-loaded instruction file:** principle / rule statement (1-3 sentences, applies broadly) → AGENTS.md or the appropriate language-specific instructions file; procedural detail (multi-step procedure, intake questions, decision trees, code examples, full rationale paragraphs) → new or existing playbook in `.github/playbooks/` with a brief `STOP. Before X, view <playbook>.` pointer. Size guideline: if a new AGENTS.md section would exceed ~10 lines / ~1.5KB, split detail to a playbook by default. Cost-of-add is one-time; cost-of-keep is per-session forever — when in doubt, lean to the playbook.

### Ask-first principle for all playbooks

Every playbook file under `.github/playbooks/` has an Intake Questions section as its first executable block. When entering a playbook, the agent's FIRST action is to view that file and run intake. Use `ask_user` when available; otherwise ask in chat. **Bundle independent questions in one prompt; ask sequentially only when a later question depends on the prior answer.** The agent does NOT produce playbook output, write to artifacts, or take downstream actions until intake is complete (or the user has explicitly skipped a specific step — see User-skip policy below).

**Phase triggers vs domain triggers — different semantics.**

- **Phase triggers** (the code-change phases in the router: pre-implementation, post-code-change, pre-commit, pre-PR-push, post-pr-review) are **mandatory** when their condition holds. The agent enters the phase and fetches the playbook. The user may skip a step within the phase only via the User-skip policy (with warning + recording + safety-critical re-confirmation). The agent does NOT ask "do you want to run this phase?" — it just enters.
- **Domain / documentation triggers** (design-spec, ADO task planning, codebase-architecture-audit, scope-planning, multi-model-review, etc.) are **offered** via `ask_user` because they're optional per-ask. Detection of a domain / documentation trigger never auto-fires the playbook — the agent always confirms first (substituting the matched playbook slug — *"this looks like a `<playbook-slug>` ask — want me to run that playbook?"*; not always "design-spec") and waits. If the user declines, the agent answers normally without the playbook.

### Intake pre-fill rule

If the user opens with structured detail that maps to intake questions (e.g. *"design-spec for the X service, current-state mode, audience=team"*), pre-fill those answers and ask only the unfilled questions.

**Confirm any pre-filled value that maps to an overloaded term** before using it: *"team"*, *"owner"*, *"audience"*, *"scope"*, *"destination"*, and similar are tentative and must be re-confirmed if they affect output structure. Exact `key=value` syntax (e.g. `audience=team`) may pre-fill directly without re-confirming. Never infer IDs, owners, linked work items, or output destinations from bare phrases.

### Trigger detection — strong vs weak

Per-playbook trigger phrases are listed in the workflow router table above. The discriminator between strong and weak is **semantic, not phrase-based**:

- **Strong triggers** — user is asking for a **durable artifact** (spec, survey, design doc, architecture write-up, current-state document, ADO work item, deliverable list) OR a **named on-demand workflow** (audit, planning lens, prototype scaffold, panel review — `codebase-architecture-audit`, `scope-planning`, `multi-model-review`, etc.; see `.github/playbooks/manifest.yaml` for the catalogue). Agent immediately offers the matched playbook via `ask_user` (substitute the slug — *"this looks like a `<playbook-slug>` ask — want me to run that playbook?"*; not always "design-spec"). If the user declines, do not re-offer in the same thread unless the ask materially changes.
- **Weak triggers** — user is asking an **exploratory factual question** without requesting a document: *"how does X work"*, *"what do we have in prod for X"* (asked casually, not as "document what we have in prod"), *"summarize"*, *"give me the gist"*. Agent does NOT block. Optionally adds a single non-blocking sentence in its normal response: *"I can answer directly, or run the design-spec playbook for a more formal write-up — which do you prefer?"*. Decline-then-no-retry rule still applies.

**Disambiguation rule for ambiguous phrasing.** When the same phrase could go either way (e.g. *"what do we have in prod for X"*), default to weak (answer directly + offer non-blocking) rather than strong (block with `ask_user`). Strong triggers should require a clear artifact-request signal:

- **Verb forms that imply written output:** *"write"*, *"draft"*, *"document"*, *"design"*, *"plan"*, *"architect"*, *"survey"*.
- **Artifact nouns:** *"spec"*, *"doc"*, *"survey"*, *"task"*, *"work item"*, *"deliverables"*, *"design change request"*.
- **Hortative-drafting forms paired with an artifact-shaped noun:** *"should be …"*, *"should look like …"*, *"what should the Y look like"*, *"what would the X (spec / API / contract / schema / acceptance criteria / surface) be"*. These imply the user wants you to *propose* a durable artifact. Strong even without a verb from the list above. **Filter:** strong only when the requested object is artifact-shaped (spec / API / contract / schema / surface / work item / criteria); pure factual hypotheticals like *"what would the cost be"*, *"what would the latency be"*, *"what would the result of this query be"* are exploratory analysis and stay weak.
- **Bare verbs *"review"* / *"audit"* are NOT strong on their own** — *"review the auth flow"* and *"audit my changes"* are analytical asks, not artifact requests. They become strong only when paired with an artifact noun: *"architect review of"*, *"audit report"*, *"review document for"*. Bare *"review"* / *"audit"* without a paired artifact noun fall into the ambiguous artifact-adjacent category below.

**Ambiguous artifact-adjacent — third category for phrasings that imply an artifact without naming one.** Phrases like *"can you draw up something on X"*, *"put together notes on X"*, *"outline the architecture for X"*, *"give me a write-up on X"*, *"I want a spec-ish thing for Y"*, bare *"review the auth flow"* / *"audit my changes"* don't include a clear artifact noun (`spec`/`doc`/`survey`) but the verb implies the user might want something durable. **Do not silently default to weak** (which would answer directly when the user wanted a doc) **and do not silently default to strong** (which would over-block, and would also pick the wrong playbook if the user actually wanted ADO planning). Instead, ask one short clarifying `ask_user` question that separates *format* from *playbook*:

> *"Do you want a quick chat answer, or a durable artifact? If artifact: the design-spec playbook (system / architecture write-up), the ADO task-planning playbook (work-item content), or another format you have in mind?"*

Then proceed accordingly. Do not run intake until the user picks. The decline-then-no-retry rule still applies after the choice. Defer destination/intake details until the chosen playbook's intake step.

### User-skip policy

The user may explicitly skip any playbook step or entire phase. When they do:

1. The agent must warn about the consequence in one sentence (e.g. *"Skipping the pre-PR-push sweep means I cannot certify the branch as review-ready under this repo's workflow."*).
2. The agent records the skip in **session todos** as the canonical mechanism. Concrete recording rules — designed so a resumed session can read the evidence back unambiguously:
   - **Required columns:** `id`, `title`, `description`, `status`. Many `todos` schemas reject inserts missing `title` — always populate it.
   - **`id`** = `skip-<phase>-<short-desc>-<yyyymmddHHMMSS>`. The timestamp suffix is mandatory because the same phase may be skipped more than once in a session (e.g. *"skip multi-model on this commit"* + *"skip multi-model on a follow-up commit"*) and a fixed ID would silently overwrite or fail to insert.
   - **`title`** = `Skipped <phase>: <short-desc>`.
   - **`description`** = the skipped phase or step name, the user's stated reason, and the time. Be explicit so a resumed-session reader can decide whether to re-run.
   - **`status`** = `'done'`.
   - **Schema bootstrapping:** if SQL is available but the `todos` table doesn't exist yet in this session, create it with a minimal schema (`id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT DEFAULT 'pending'`) before inserting.
   - **Fallback when SQL is entirely unavailable:** write the skip evidence to `<copilot-session-state>/<session-id>/files/skips.md` with the same field set (id / title / description / status / time) AND surface the skip in the chat summary so the user has a paper trail.
   - **Fallback when even the session-state path can't be resolved:** surface the situation in chat and require the user to explicitly re-acknowledge the skip on each subsequent assistant turn until evidence can be recorded. Do NOT silently proceed.
   - **Hard stop when ALL recording paths fail:** if SQL is unavailable, the session-state path cannot be resolved, AND there is no usable chat surface for per-turn re-acknowledgement (e.g. headless / non-interactive CI contexts), **halt the phase and do not certify readiness**. The skip cannot be evidenced, so the workflow cannot proceed. Surface a non-zero exit / failure signal to the runtime if one is available.
3. The agent must NOT later claim the full workflow completed — the "ready to push" / "ready to commit" / "all phases done" message must explicitly enumerate which phases were skipped (read the recorded skips back; do not rely on memory).
4. **If recorded skip evidence is missing or incomplete in a later session** (resumed work, agent handoff), treat the relevant phase as **not proven** and conservatively re-run the required checks or ask the user to explicitly accept a skip. Do not infer success from absence of evidence.
5. **Safety-critical skips** require explicit user re-confirmation before proceeding. Specifically:
   - Skipping the multi-model reviewer panel for any non-trivial change (defined: more than a single-line typo / single-property rename / single config-key value tweak).
   - Skipping pre-PR-push branch-wide sweep for any push intended for review (PR-opening, request-for-review, push to a shared branch others may pull from).
   - Skipping verification-of-fix when the change is justified by a perf metric, bug repro, or security claim.
   - Skipping the rubber-duck pass on changes touching concurrency / security / cryptography / native interop / payment or financial logic / authentication / authorization / shared global state.
   When in doubt about whether a class of work is safety-critical, default to "yes — re-confirm".

### Phase-state tracking convention

At each phase entry, record in **session todos** (canonical mechanism — same as User-skip policy above) using a parallel schema so a resumed session can read the evidence back unambiguously:

- **`id`** = `phase-state-<phase>-<yyyymmddHHMMSS>`. Timestamp-suffixed for the same reason skip IDs are: a single phase may be entered multiple times in one session (e.g. multiple commits each running pre-commit). Most recent record per phase wins; older records are kept for audit, not consulted for "ready" checks.
- **`title`** = `Phase state: <phase> @ <yyyymmddHHMMSS>`.
- **`status`** = `'in_progress'` while the phase is active, then `'done'` when all required steps + skips are complete.
- **`description`** carries the phase-state fields below (free-form prose acceptable; structured `key: value` lines preferred for grep-ability):

Required fields in `description`:

- Phase name and time entered.
- Playbook file viewed (or *"not viewed — explicit skip"* with skip reason).
- Intake completion status: complete / pre-filled-from-input / explicitly-skipped.
- User-approved skips of any sub-step.

Same fallback chain as the User-skip policy above (SQL bootstrap → `<copilot-session-state>` file → per-turn re-ack → hard stop) applies if SQL is unavailable.

**Concrete example record — pre-implementation phase** (illustrates the minimum canonical shape; other phases require additional `key: value` lines beyond this minimum — see *Per-phase additional fields* below):

```sql
-- Entering pre-implementation phase
INSERT INTO todos (id, title, description, status) VALUES (
  'phase-state-pre-implementation-20240115093045',
  'Phase state: pre-implementation @ 20240115093045',
  'phase: pre-implementation
time_entered: 2024-01-15T09:30:45Z
playbook_viewed: .github/playbooks/pre-implementation.md
intake_status: complete
user_approved_skips: none',
  'in_progress'
);

-- Completing the phase
UPDATE todos SET status = 'done',
  description = description || '
time_completed: 2024-01-15T09:42:11Z
hard_gates_satisfied: yes'
WHERE id = 'phase-state-pre-implementation-20240115093045';
```

When SQL is unavailable, write the same field set as a `## phase-state-<phase>-<yyyymmddHHMMSS>` heading with key:value lines under it in `<copilot-session-state>/<session-id>/files/phase-state.md`. **Reader contract** (LLM consuming the record in a resumed session): parse `key: value` lines from the description; treat unknown keys as informational; require `phase`, `time_entered`, `intake_status` (description) AND `status` (read from the SQL `status` column directly, or — in the markdown fallback — from a `status: <value>` line) to consider the record valid. Any phase-specific required fields (e.g. the 10-field pre-PR-push state predicate below) must additionally be present for the readiness check that consumes them.

### Per-phase additional fields

**Pre-PR-push readiness state is a state predicate** (per §3.7) — every required field must be enumerated. Record the following keys in addition to the minimum canonical shape above when running the pre-PR-push phase:

- `baseRef` — what the branch is being merged into (e.g. `origin/main`).
- `baseSha` — resolved SHA at sweep time (NOT later-resolved symbolic ref, which may have advanced).
- `sweepHeadSha` — branch HEAD SHA at sweep time.
- **`isFirstReviewExposurePush`** (boolean) — *Is THIS push the first one intended for review?* (PR-opening, request-for-review, or first push to a shared branch others may pull from.) Drives whether the branch-wide sweep is required. **Per-push, not branch-sticky:** a personal-sandbox / backup push records `false` (a sandbox push is not a review push); the FIRST subsequent review push of the same branch records `true`. Independence from `remoteExposureExists` is the point — prior sandbox pushes do NOT latch this boolean to `false` for the upcoming review push. Named as a verb-shaped predicate so a reader can't misread it as "this branch has never been pushed before".
- **`remoteExposureExists`** (boolean) — has this branch been pushed anywhere before, in any form (including personal sandbox)? **Historical evidence only** — the primary amend-safety force-push gate is `isFirstReviewExposurePush=false` (the branch is already under review on a shared remote). **Sandbox exemption is conditional, not automatic**: when `(isFirstReviewExposurePush=true && remoteExposureExists=true)` (first review push of a previously sandbox-pushed branch), before any operation that rewrites already-pushed history the agent MUST ask a one-question sandbox-privacy confirmation (*"was the prior sandbox push truly personal/unwatched, and are you sure no one else pulled it?"*). On **yes/private/unwatched**: silent amend is safe. On **no/unsure**: do NOT silently amend — use the explicit force-push approval choices from the `(false, true)` *amend-safety subflow only* (the recorded booleans and decision-tree routing are NOT remapped — Step 2 first-review sweep still runs, Step 4 is NOT entered). The question fires **lazily** — only when an amend is about to happen, NOT preemptively at intake. Recorded for audit and as input to the `(false, true)` truth-table row's re-run logic. These two booleans are independent — a branch pushed only to a personal sandbox has `remoteExposureExists=true` AND `isFirstReviewExposurePush=true` on its first subsequent review push.
- `perCommitAuditCoverage` — list of commit SHAs on the branch with audit status (`done` / `skipped-with-reason` / `not-run`). Must be `done` or `skipped-with-reason` for every commit before the branch is "ready". This is the canonical enum — playbooks that produce entries (e.g. `pre-commit.md`, `pre-pr-push/per-commit-micro-hygiene.md`) MUST use one of these three values; if extra detail is needed (e.g. *"audit modified the diff"*), put it in the entry's free-form description text, not in the `status` value.
- `branchWideSweepStatus` — one of:
  - `not-applicable` — push exited at the sandbox pre-check (out of pre-PR-push scope; no sweep applies).
  - `done-clean` — sweep ran in this push cycle, no changes.
  - `done-cleanup-committed` — sweep ran in this push cycle, cleanup commits made (list bucket + SHA per commit).
  - `previously-done-no-rerun-needed` — subsequent review-targeting push; prior sweep evidence present, re-run conditions checked, no re-run required.
  - `rerun-done-clean` — re-run sweep ran in this push cycle, no changes.
  - `rerun-done-cleanup-committed` — re-run sweep ran in this push cycle, cleanup commits made.
  - `rerun-skipped-with-reason` — re-run sweep explicitly skipped during a subsequent push (record reason per User-skip policy).
  - `skipped-with-reason` — initial sweep explicitly skipped during the first review push (record reason per User-skip policy).
- `cleanupBucketOutcomes` — for each cleanup commit: which bucket was chosen, why, and whether amend-safety required force-push approval.
- `sandboxPriorExposureConfirmation` — informational field, written when the conditional sandbox exemption gate fires (only on `(isFirstReviewExposurePush=true && remoteExposureExists=true)` and only when an amend is actually attempted). One of: `confirmed-private` (sandbox confirmed personal/unwatched, silent amend taken), `denied-or-unsure` (user said no/unsure, fell through to explicit force-push approval), `not-needed` (no amend was attempted in this push cycle, so the gate never fired). Recorded so a resumed session does not re-ask or silently infer safety from memory.
- `rerunConditionsChecked` — for each subsequent push: `true` (re-run conditions checked per `when-to-re-run-sweep.md`) or `false` (not yet checked / pending). Two documented sentinel values are also accepted for the "doesn't apply" case: the literal `n/a-first-push` (this is the first review push — no prior sweep to re-run-check; written by the first-review example) and the literal `n/a-sandbox-exit` (push exited at the sandbox pre-check; written by the sandbox-exit record). Both sentinels are predicate-complete — a strict reader MUST treat them as satisfying the field, not as missing.
- **`pushCredentialsVerified`** — outcome of the §4.2 mechanism-aware push-credential verification (recorded by `pre-pr-push.md` *Pre-check 0*; see §4.2 for the full procedure). One of:
  - `yes` — verification mechanism returned the user's principal (`gh api user --jq .login` matched the user; SSH greeting matched; etc.).
  - `user-confirmed-unverifiable` — verification mechanism couldn't expose the cached principal (e.g., Windows Credential Manager / macOS Keychain / libsecret) and the user confirmed via `ask_user` that the cached credential is theirs (not a Copilot / bot / shared account).
  - `blocked` — verification revealed (or strongly suggested) a non-user principal (e.g., `gh` logged in as a `[bot]` account; ambient `GH_TOKEN` / `GITHUB_TOKEN` / `GIT_ASKPASS` set; `SSH_AUTH_SOCK` pointing at an agent-controlled socket; user could not confirm in the unverifiable case). **A `blocked` value FAILS the readiness gate — the push MUST NOT proceed.**
  
  This is a required predicate field — §4.2 applies to EVERY push including sandbox-exits (no `n/a-sandbox-exit` sentinel; sandbox pushes must verify credentials too). A "ready to push" claim requires `yes` OR `user-confirmed-unverifiable`. This field brings the pre-PR-push state predicate to **10 fields** (1-9 above + `pushCredentialsVerified`); the `sandboxPriorExposureConfirmation` field remains the always-present informational eleventh entry in the read-back block.

**Sandbox-exit record** (used when the pre-PR-push pre-check exits because the current push is personal-sandbox / backup-only): write the standard minimum canonical shape PLUS `branchWideSweepStatus: not-applicable`, the booleans `isFirstReviewExposurePush: false` + `remoteExposureExists: <true|false per actual remote history>`, AND `pushCredentialsVerified: <yes | user-confirmed-unverifiable | blocked>` per §4.2 (NOT a `n/a-sandbox-exit` sentinel — credentials must be verified for sandbox pushes too; record the real verification outcome). Other 10-field-predicate keys (`baseRef`, `baseSha`, `sweepHeadSha`, `perCommitAuditCoverage`, `cleanupBucketOutcomes`, `rerunConditionsChecked`) may be written as the literal sentinel `n/a-sandbox-exit` (NOT omitted — predicate completeness still requires the keys to appear). The record is a normal `done` phase-state record, not a "skipped" record; it documents that the pre-PR-push playbook explicitly resolved as not-applicable for this push.

**Concrete example record — pre-PR-push first review push, sweep ran clean:**

```sql
-- Entering pre-PR-push phase (intake done, booleans set, sweep not yet run)
INSERT INTO todos (id, title, description, status) VALUES (
  'phase-state-pre-pr-push-20240115140312',
  'Phase state: pre-pr-push @ 20240115140312',
  'phase: pre-pr-push
time_entered: 2024-01-15T14:03:12Z
playbook_viewed: .github/playbooks/pre-pr-push.md
intake_status: complete
user_approved_skips: none
baseRef: origin/main
baseSha: a1b2c3d4e5f6...
sweepHeadSha: 9z8y7x6w5v4...
isFirstReviewExposurePush: true
remoteExposureExists: false',
  'in_progress'
);

-- Completing the phase after sweep + per-commit audit run clean
UPDATE todos SET status = 'done',
  description = description || '
time_completed: 2024-01-15T14:11:48Z
perCommitAuditCoverage: [{sha: 9z8y7x6w5v4, status: done}]
branchWideSweepStatus: done-clean
cleanupBucketOutcomes: none
rerunConditionsChecked: n/a-first-push
pushCredentialsVerified: yes'
WHERE id = 'phase-state-pre-pr-push-20240115140312';
```

The INSERT captures intake-time state (booleans + sweep-input SHAs); the UPDATE captures completion-time state (sweep outcome, audit map, cleanup outcomes, push-credential verification) and flips `status` to `'done'`. The `n/a-first-push` value on `rerunConditionsChecked` is the documented sentinel for "no prior sweep to re-run-check" (see field definition above); `pushCredentialsVerified: yes` records the §4.2 outcome.

Before declaring any variant of *"ready to commit / push / open PR"*, read the recorded state back and confirm every required phase has either run (per its hard gates) OR been explicitly skipped (per User-skip policy). Do not infer state from memory.

### Output-write ordering for documentation playbooks

For playbooks that produce a document (`design-spec.md`, `ado-task-planning.md`):

1. Intake determines the *intended* final destination.
2. The draft is rendered in chat first, regardless of intended destination.
3. The user reviews and approves (or requests revisions) on the draft.
4. Only after approval does the agent write to the chosen destination (file / save / paste-ready output).

Never write to a file before the user has approved the content.

---

## 2. Commit Messages

- **Single line only.** No body, no footers, no trailers of any kind.
- **Explicitly suppress the auto-injected `Co-authored-by: Copilot` trailer.** When invoking `git commit`, use `-m "<message>"` only — do not pass any additional `-m` flags, do not let any tool append a trailer, and do not add a blank line followed by `Co-authored-by:`. The commit message body must contain the single line and nothing else.
- **Describe what the change does**, not which plan item it implements. No `A2`, `(A2)`, plan section numbers, or Conventional-Commit prefixes (`perf:`, `fix:`, `feat:`, etc.).
- **Imperative mood, no trailing period.**

Examples:
- ✅ `Defer TagsDisplayName join until first read`
- ✅ `Add IsEnabled guard to LoggingMiddleware before serializing actions`
- ❌ `perf: defer TagsDisplayName join (A2)`
- ❌ `A2 - lazy tags`
- ❌ Any message followed by `Co-authored-by:` or any other trailer.

> The corresponding rules for the actual commit **author / committer identity** (`user.name` / `user.email` resolution + verification) and for `git push` **authentication** are in §4 *Git Identity & Push Credentials*. This section governs the message body only; §4 governs who the commit is attributed to and who authenticates the push.

---

## 3. General Coding Standards

These standards apply to **every** code change, in every language. They are non-negotiable; reviewers should reject PRs that violate them.

Language-specific additions live in the topic files under `.github/instructions/`. Examples: XML-doc comment rules and `nameof()` apply only when C# files are in the working set — see `csharp.instructions.md`.

### 3.1 Comments

**This rule is enforced strictly. Over-commenting is the most common style violation across past PRs — assume the reviewer will reject any comment that is not load-bearing. The default answer to "should I add a comment here?" is NO.**

- **Default: no comments.** Code is the primary documentation. Names carry intent. If you find yourself wanting to write a comment, first try renaming the variable/method or extracting a well-named helper.
- **Rename-first protocol (mandatory).** *Every* time you reach for a comment because "the code isn't clear" / "the reader won't know what this does" / "this is subtle," your **first** action is to read the surrounding identifier(s) — function, parameter, variable, type, field — and ask: *"Can a better name carry this fact?"* If yes, rename and drop the comment. Only if no rename can express the fact (genuinely external constraint, true non-obvious algorithmic invariant, or a deliberate trade-off the reader would otherwise question) is the comment allowed — and it still has to pass the hard length caps below. Examples: a comment that says "this method does X for Y reason" almost always means the method name should describe X-for-Y; a comment that says "this flag is true when Z" means the flag should be named `IsZ` or `HasZ`. Do this rename pass on **every** new comment you write, not just ones that feel borderline.
- **Hard prohibitions** (do not commit any of these — no exceptions):
  - **No comments that restate the code.** `// Bump counter` next to `_counter++`, `// Set flag to true` next to `_flag = true`, `// Loop over items` next to `foreach (var item in items)` — all forbidden.
  - **No "why we're about to do this" narration.** `// We need to clear the buffer here so that...` — if the reason is obvious from the next line, drop the comment; if it isn't, the next line probably needs a better name or a small refactor.
  - **No multi-line `//` blocks explaining a design decision in prose.** That belongs in the PR description, the commit message, or (if it's a true invariant) a *single short* line.
  - **No speculation about future callers, future surfaces, or "this will be used by X later."** Code comments describe what the code IS, not what's coming. Examples to never write: `// callers (banner copy-details, filter export, future surfaces) are typically fire-and-forget`, `// the future BannerHost will need this`, `// once we add Y this will also handle Z`. Future-tense forecasting belongs in the PR description.
  - **No restating contract terms that are already encoded in naming or signature.** A method named `CopyTextAsync(string text)` already says async + takes a string. Don't add a comment that says "Copies text asynchronously."
  - **No "TODO" / "FIXME" / "HACK" / "XXX" comments.** Use the *Pre-existing issues* cross-cutting rule in §1 (`ask_user` to fix now / defer / dismiss) instead.
- **Allowed** (rare, and only when ALL three apply: short, load-bearing, not inferable):
  - A non-obvious algorithmic invariant (e.g., `// k-merge requires inputs already sorted by Timestamp ascending`).
  - A workaround for an external constraint (e.g., `// Win32: LoadLibraryEx with DATAFILE flag still maps writable on <Win10`).
  - A deliberate trade-off the reader would otherwise question (e.g., `// Monitor lock — ConcurrentDictionary lost on this benchmark`).
- **Hard length cap on inline comments:**
  - Inline `//` and `#` comments: **one line, ≤ 12 words.** If you can't fit the load-bearing fact in 12 words, the surrounding code needs a better name or a helper extraction — not a longer comment.
- **Mandatory self-review pass before showing diff:** enumerate every NEW comment line in the diff. For each one, write a one-line justification matching one of the 3 allowed cases above ("non-obvious invariant: X" / "external constraint: Y" / "trade-off: Z"). **If you cannot write that justification in one short clause, delete the comment.** This audit is non-skippable — running it sometimes catches 100% of the violations the reviewer would have flagged.
- **Remove existing stale comments** that no longer add value when touching surrounding code. **Stale-comment disposition during rename / restructure**: rename-first protocol runs first; if still stale, default DELETE. Rewrite only when the comment captures a non-obvious invariant that no name / refactor can carry. Throwaway-marker exception: canonical `THROWAWAY: <prototype-name>` header in `prototypes/<name>/` is allowed (hosted in `design-exploration.md` / `performance-comparison.md`).

**Common failure modes flagged in past reviews:**
- Adding `// Only commit if we're still the most recent load.` above an `if (gen == _gen)` check. The check + name says it. Delete the comment.

> **C# adds:** XML doc comment rules (no XML doc on `private` members, length caps on `<summary>` / `<param>` / `<returns>`, default-OFF for new public/internal API). See `csharp.instructions.md`.

### 3.2 Naming — clarity over brevity

- Use **descriptive, full-word names**.
  - ✅ `userSessionCache`, `customerName`, `combinedRecords`
  - ❌ `cache`, `cn`, `cr`, `ctx` (don't abbreviate `context`), `tmp`, `data2`
- **Lambdas:** full names unless the parameter is **immediately and unambiguously** clear from the operation. When in doubt, use the full name.
  - ✅ `orders.Where(order => order.Status == OrderStatus.Open)`
  - ✅ `bytes.Sum(b => b.Length)` — single-letter is fine in a tight, obvious scope
  - ❌ `orders.Where(o => o.Status == OrderStatus.Open && (o.Region == "X" || o.Channel == "Y"))` — scope is big enough to deserve `order`
- **Method names:** verb-phrase that describes the *outcome*, not the implementation.
  - ✅ `MergeSortedRecordsIntoCombinedView`, `TryGetCachedErrorMessage`
  - ❌ `Process`, `DoWork`, `Handle`
- Avoid noise prefixes/suffixes (`Helper`, `Manager`, `Util`) unless the type genuinely is one.

### 3.3 When naming is ambiguous → ask first

If, while implementing, a name is not obviously correct or there are two or more reasonable choices that meaningfully differ in intent, **stop and present 2–4 options to the user via `ask_user`** with a one-line rationale per option. Do not invent a name and proceed.

Cases that warrant the ask:
- A new cache type that could be named after its key, its value, or its consumer (`UserSessionCache` vs `LoginTokenCache` vs `AuthRequestCache`).
- A new helper method whose name could imply a stronger or weaker contract (`TryGetMessage` vs `GetMessageOrNull` vs `LookupMessage`).
- A flag whose polarity matters (`IsLazy` vs `IsEager`, `RebuildAlways` vs `RebuildOnChange`).
- A model property where the prior name disagrees with the new behavior (e.g., renaming `TagsDisplayName` to better reflect that it is now lazy / on-demand — options: `TagsDisplayText`, `TagsJoined`, `FormattedTags`, leave-as-is-with-doc-comment).

When choices clearly differ only in style (and not in intent), pick one and move on — do not over-ask.

### 3.3.1 Opportunistic rename suggestions for existing symbols

When working in or touching a file (any reason — bug fix, feature, refactor, review), if you encounter an **existing** type / method / property / parameter / record / class / interface name that doesn't describe its intent well or has a clearly better name available, **stop and ask the user via `ask_user`** before renaming. Phrase it as: *"While here I noticed `OldName` doesn't describe its intent well — proposing `NewName` because [one-line rationale]. Rename now / leave / propose alternative?"*

When to surface a rename:
- Name is generic where a domain term applies (`Manager`, `Processor`, `Helper`, `Util`, `Data`, `Info` for non-`xxxInfo` types).
- Name describes implementation, not intent (`StringDictionary` vs `UserPreferences`, `IntList` vs `RetryDelays`).
- Name disagrees with current behavior because the type evolved (`SyncCache` that's now async, `ReadOnlyList` that exposes mutation).
- Name uses an outdated abbreviation or one that conflicts with project terminology (`Pkg` vs `Package`, `Auth` ambiguous between authentication / authorization).
- Name shadows a type (PascalCase local / parameter `LogPathType LogPathType`) — flag as a code-quality rename even if it currently compiles.
- Name uses pre-rename terminology that survived only because the rename pass missed it (e.g., a member named `XLogNames` on a class renamed to `LogChannelNames` should probably become `XLogChannels`).
- An interface name doesn't communicate the role (`IDatabaseCollectionProvider` for what's really an "active databases" provider).

When NOT to surface a rename:
- Name is locally consistent with project conventions even if it's not your preferred name (style-only).
- Rename would touch many unrelated files and the user is mid-flight on a different scope (defer to a follow-up via `ask_user` per the *Pre-existing issues* rule above).
- The "better" name is only marginally better and the cost of churn (PR diff noise, blame loss, downstream breakage) outweighs the clarity gain.
- Public API surface that's already shipped to external consumers — needs explicit deprecation strategy, not a silent rename.

The same `ask_user` choice template as §3.3 applies: present 2–4 candidates with one-line rationale each, let the user pick. Bundle multiple rename candidates in one prompt when reviewing a single file, but ask one prompt per file (don't bundle across files — the user loses track of context).

### 3.4 Tests and Benchmarks

- **Intent over coverage — the default for every test, new or existing.** Before writing or keeping a test, answer in one sentence: *"What concrete regression in the SUT would make this test fail?"* If the answer is "I can't think of one without changing the test itself", do not write it (or delete it if it already exists). The default is **intent-driven, thorough tests** that exercise real behavior, including the trigger that proves the asserted contract — not coverage-driven filler that pins trivial getters, framework code, language-guaranteed type checks, or "nothing happened" without including the would-be stimulus. Coverage-driven tests are appropriate **only** when the user explicitly asks for "complete code coverage", a coverage sweep, or similar. When a coverage report points at uncovered lines that don't represent real behavior (auto-properties, unreachable defensive branches, generated code), leave them uncovered — a high coverage number built from filler hides the real coverage gaps. When auditing a file you're editing, flag tests that fail this question for deletion or rewrite rather than preserving them out of inertia. See `csharp-testing.instructions.md` for the full audit-and-delete framework, including the deterministic-synchronization rules for tests that wait on async events.
- **Reviewing tests = intent audit AND gap audit — both directions, every time.** Whenever you author, port, refactor, or code-review tests, run the audit in *two* directions, not one. Direction A (covered above): does each present test pin a real regression? Direction B: enumerate the SUT's behaviors in scope (public/internal entry points, failure paths, boundary conditions, reverse/descending modes, null-valued inputs, integration seams, each branch of each `switch`/`if`) and ask *which of them has no test*. Missing tests for documented behaviors are defects of the same severity as filler tests — a high test count with one-direction coverage hides real gaps. Surface every observed gap explicitly (session note, follow-up issue, reviewer-panel prompt) — never silently inherit it. **Do NOT accept "tests pass and coverage didn't drop" as evidence of correctness.** Mechanical port / decompose commits are not the place to add new tests, but they ARE the place to write the gap list and propose a follow-up "harden test surface" commit.
- Tests and benchmarks follow all the standards above (no abbreviations, descriptive names, no narrative comments).
- **Test method names** are full sentences describing the scenario and expectation: `GetCustomer_WhenCaseDiffers_FindsExistingCustomer`.
- **Benchmark class and method names** match the production symbol they exercise: `UserSessionCacheBenchmarks.Lookup_HotCode_NoAllocation`.
- **Avoid wall-clock time sources in tests** (`DateTime.Now`, `DateTime.UtcNow`, `Date.now()`, `time.time()`, etc.) — they introduce non-deterministic behavior and timezone dependencies. Use fixed deterministic timestamps (e.g. `new DateTime(2024, 1, 1, 12, 0, 0, DateTimeKind.Utc)`) so tests are reproducible regardless of when or where they run.
- **Add or update unit tests** to cover new code and edge cases. Follow existing testing patterns. `.github/playbooks/intent-driven-testing.md` operationalizes this section as a phase-sub-step workflow.

> **C# adds:** the `TestUtils/` folder convention, `Constants` partial-class convention for shared test values, and the full naming framework (`<Domain>Builder` / `<Domain>Fixtures` / `<Domain>TestFixtures` / `<Domain>Assertions` / `<Domain>TestConstants`). See `csharp-testing.instructions.md`.

### 3.5 Performance

- Consider performance implications of every change.
- Avoid unnecessary allocations, prefer efficient algorithms, and use appropriate data structures.

### 3.6 Defaults and Consistency

- **When in doubt, follow the platform-standard naming guidelines** for the language in question (Microsoft for C#, C++, JS/TS, HTML, CSS; PEP 8 for Python; etc.). The language-specific topic files codify these.
- **When platform guidance and the existing code in a touched file disagree, prioritize consistency with the existing code in that file.** Don't reformat or rename surrounding code just to match the standard.
- **Comprehensive over sampled.** When the user asks for a review, scan, audit, sweep, or "look across all X" of any noun (sessions, files, PRs, callers, tests), default to **complete coverage** — enumerate the full set first, then process every item. Do not pick a representative subset on your own. If the set is genuinely too large to process in full (cost, time, context budget), surface that explicitly via `ask_user` with the count and propose a sampling strategy *before* starting. "I read 9 of the ~80 sessions" is a failure mode the user will catch every time.
- **Search-first for renames and refactors.** Before declaring any rename, signature change, or moved symbol complete, run a full-repo grep for the old identifier across **every** relevant file type — including `*.razor`, `*.razor.cs`, `*.cshtml`, `*.json`, JSON converter switch cases, `*.xaml`, test projects, doc comments, and trace/log strings. Report "0 matches" before declaring done. "I missed a consumer" is the most common post-refactor regression and almost always means the grep wasn't wide enough.
- **Parameter / property names must be consistent across the entire interface chain — not just at the top-level call site.** When introducing or renaming a parameter (especially boolean) that flows through `interface → implementation → caller → lambda capture`, pick the name **once** and apply it from the implementation up to every call site. The most common failure mode: the top-level handler gets the new "good" name, but the interface signature, the impl method signatures, the lambda parameters, and any private helper methods still show a draft/older name. This is greppable, but only if you grep — before declaring done, list every layer (interface, abstract base, every implementation, every caller, every lambda that closes over the argument) and verify the parameter name is identical across all of them. If you renamed a parameter mid-edit, that is also the moment to rerun the rename across the whole chain. Reviewers always spot the mismatch because they read the interface and the impl together; so should you.
- **Confirm the user-facing surface before non-trivial implementation.** For any change that introduces or modifies a user-visible surface — new commands, new CLI flags, new menu items, new API endpoints, new file formats, new public types, new dialog flows — sketch that surface (names, signatures, file boundaries, defaults) and confirm via `ask_user` **before** starting implementation, not after. Building the wrong shape and then re-cutting it costs more than asking. Pure internal refactors and bug fixes are exempt.
- **Convention precedence** — scan the solution for the dominant or closest-in-purpose sibling convention; match it. When no convention exists, default to the framework's documented best practice. Personal style is not a tiebreaker.
- **Match existing structural patterns when introducing new types.** Before creating a new interface, abstract class, exception, model, record, or service, look at how *sibling* types of the same role are organized in the project being edited and mirror that. Things to mirror, not invent:
  - **File layout for interfaces.** Some projects put every interface in a dedicated `Interfaces/` folder and its own file; others co-locate the interface with its sole production implementation in the same file (often `public interface IFoo` immediately above `public sealed class Foo : IFoo`); others put both in a feature folder. Find the dominant pattern for the kind of type you're adding (DI seam vs broader contract) and follow it. If both patterns are in use, prefer the one used by the closest-in-purpose neighbors (a new DI seam should look like the other DI seams, a new contract type should look like the other contract types).
  - **Folder/namespace by role.** Models, options, services, exceptions, abstract bases, etc. each tend to have a dedicated folder/namespace. Place new types in the matching one — do not invent a new folder when a fitting one already exists.
  - **Class shape.** Sealed-with-primary-constructor vs explicit constructor + readonly fields, `partial` only when source generators require it, abstract base classes only where a base-class hierarchy already exists. Match what neighbors do.
  - **Suffixes and prefixes.** `XxxBase` for abstract bases, `XxxService` / `XxxProvider` / `XxxRepository` / `XxxOptions` etc. — use the suffix the project already uses for that role, do not introduce a new vocabulary.
  - **Exposed surface.** If sibling services use NSubstitute-friendly interface seams, do the same; if they expose a sealed concrete with no interface, follow that. Don't add an interface "just in case" if the project's pattern is concrete-only.
  When two reasonable patterns coexist and the choice materially affects the contract or test surface, ask via `ask_user` rather than picking unilaterally. Surveying sibling files takes a minute and prevents a multi-file rewrite during review.

### 3.7 State predicates and emptiness checks

A "state predicate" is any boolean over a type's fields/properties that means *"this object is empty / equal / fully populated / cleared / serialized / matches X"*. These are notorious for missing fields when new members get added later or when the author only thinks about a subset of the type.

- **Encapsulate state predicates on the type that owns the state.** When you find yourself writing `x.A == 0 && x.B == 0 && !x.C.Any()` from outside the type, add the predicate as a member on the type itself (e.g., `IsEmpty`, `IsDefault`). This forces you to look at *every* field and naturally surfaces ones you'd otherwise miss. A multi-clause boolean over fields of a single type, written from outside that type, should be treated as a refactor smell.
- **Field-completeness justification.** When introducing or modifying any state predicate, enumerate **every** member of the type and justify (in your head, in the PR description, or in a doc comment on the predicate) why each member is included or excluded. "I forgot about it" is the failure mode this rule exists to prevent.
- **Reviewer enforcement.** When sending a diff to the rubber-duck or code-review agent that introduces such a predicate, name the type explicitly in the prompt and require the reviewer to enumerate its members independently. Do not summarize the predicate's scope — let the reviewer derive it from the source.
- **Match / equality predicates need enough fields to be unique in the domain.** A predicate that says *"these two records refer to the same thing"* must include every field required to disambiguate them in the broadest realistic context. Common failure modes: a composite key over `(LocalId, SubId)` collides once the records cross their original container — the source/owner field needs to be in the key too; an `IsEmpty` predicate over a few "obviously content-bearing" collections silently returns `true` for objects whose data lives in the *other* collections the author didn't think about. When in doubt, ask: *"could two domain-distinct objects compare equal under this predicate?"* If yes, it is incomplete.

### 3.8 Defer state mutations until after success

When an operation can fail (throws, returns false, awaits a remote call that may not return, etc.), do not record success-implying state until the operation has actually succeeded. This is one of the most common classes of bug flagged by PR review.

- **Membership / dedup sets** (`seen.Add(x)`, `_processed[id] = true`): perform the work first, then record membership. If the work throws, the next attempt should retry, not skip.
- **Registration / initialization flags** (`_registered = true`, `_initialized = true`): set only after the underlying call (interop, native handle acquisition, network registration) returns successfully.
- **Cache writes**: insert into the cache only on the success path; do not write a partially-populated entry that other callers may read.
- **Don't cache high-cardinality strings.** Before passing a value to a string-interning cache, confirm the value comes from a small, bounded set. Strings built by concatenating per-record fields (timestamps, IDs, paths, user input, payload data) are effectively unique per call and will grow the cache without bound. If a code path produces both canned and per-record variants from the same builder, split the cache call so only the canned branch is interned and the per-record branch returns directly.
- **Error state on success**: on the success path, explicitly clear any prior error fields (`LastErrorCode`, `LastException`, `_warningShown`). A successful run should leave no stale failure breadcrumbs.
- **Idempotency-first ref handoff**: when a method is idempotent (early-returns if already done), assign the long-lived reference (interop reference, native handle, subscription token) **before** the early-return guard, not after — otherwise the second caller sees `null` and the first caller's reference leaks on dispose.

> **C# / Blazor adds:** lifecycle patterns for `IJSRuntime`, `DotNetObjectReference`, `Lazy<Task<T>>`, `IAsyncDisposable`, `[Parameter]` properties, narrow JS-interop catches, and `AbortController` pairing. See `csharp.instructions.md`.

### 3.9 User-facing text — must match the actual behavior

Any string that a user reads — picker / dialog titles, prompts, button labels, toast / alert / banner messages, menu item text, tooltip / aria-label / alt text, error messages, status-bar copy, exception messages thrown to the user, telemetry/log strings that surface in user-visible diagnostics — is part of the contract. Treat it the same as a method signature: when the underlying behavior changes, the text must be re-read and updated to match.

- **Audit nearby user-facing text whenever you change the call shape.** When you switch a single-result API to a multi-result API (`PickAsync` → `PickMultipleAsync`, `GetFirst` → `GetAll`), or vice versa; when you change the verb (`Save` → `Export`, `Delete` → `Archive`); when you change the scope (per-row → per-selection, per-tab → per-window); when you change the unit (file → folder, single record → batch) — locate every user-facing string within the same method, the same component, and the call sites you touched, and re-read each one against the new behavior. The most common failure mode is leaving plural/singular, verb tense, or scope words out of sync with the new call shape (e.g., "Please select **a** database file" on a `PickMultipleAsync` call).
- **Re-evaluate inherited literals when you move or refactor code.** A string literal that read correctly in its old context may not read correctly after a `git mv`, an extract-method, or a parameter rename. Pre-existing copy that the diff makes visible is fair game to fix in the same change — see *"directly caused by or tightly coupled to the code you're changing"* in the global rules.
- **Be specific and contextual, not generic.** Prefer wording that names the actual operation, the scope, and what the user is being asked to do: "Please select database files to import" beats "Please select files" beats "Please select a file." Avoid generic placeholders left from scaffolding (`"Open"`, `"Choose..."`, `"OK"`) when the surface is a real user dialog with a specific intent.
- **Match plurality, tense, and voice to the runtime behavior.** Multi-select pickers / batch operations / list-returning APIs use plural noun forms ("files", "items", "results"). Idempotent re-runs use neutral phrasing ("Up to date") rather than action verbs ("Updated"). Async operations that may take time use progressive forms ("Importing...") not past-tense.
- **Aria-label / alt / tooltip text describes the control's behavior, not its appearance.** A button labeled "X" with `aria-label="Close dialog"` is correct; `aria-label="X icon"` is wrong. When the behavior changes, the accessibility text changes with it.
- **Reviewer enforcement.** When sending a diff that changes a call's shape, behavior, or scope to the rubber-duck or code-review agent, ask it to enumerate every user-facing string in the touched scope and verify each one still matches what the user will actually experience.

### 3.10 Recurring code smells from past PR reviews

Treat each of these as a hard-stop during self-review and as an explicit thing to look for during the multi-model code-review pass.

- **Constants — single source of truth.** Any literal that constrains a contract (page size, max-in-clause parameter count, default cache size, retention window, file size limit, magic timeout) lives in exactly one named constant. Duplicates across files **will** drift. If the same number appears in two places, extract it before the diff is reviewable.
- **A "list of X" collection must reference the same constants used by the code that produces X — not duplicate the literals.** When you create or maintain a collection whose purpose is to *describe* a hardcoded set elsewhere (a "well-known names" set, an "always-shown columns" list, a "system-known schemas" registry, an "allowed origins" array, a "hardcoded menu items" filter), and another file builds those same items by writing the literals directly, the collection silently goes out of sync the moment someone adds, removes, or renames an item at either site. Extract the literals to named constants in one place, have the collection initializer reference the constants, AND have the hardcoded site reference the same constants — never literals on either side. The collection's existence is itself the signal that the literals are a contract; leaving the literals at one of the two sites defeats the collection's entire purpose. When you encounter this pattern in a diff (yours or someone else's), fix both sites in the same change.
- **Sibling-constant consistency.** When you add or modify one of a *group* of related constants (default error messages, status labels, retry counts in a tier, timeouts per stage), look at its siblings in the same declaration block and verify formatting/punctuation/casing/units are consistent. Trailing-period-on-one-of-three-strings, `"OK"` vs `"Ok"` vs `"Okay"`, `5000` vs `5_000` — reviewers always spot these because they read sibling constants together. So should you.
- **Test specificity.** Assert exact values, never `Arg.Any<T>()` / `It.IsAny<T>()` / `Mock.Of<T>()` (or equivalents in your test framework) when the test's purpose is to verify *what was passed*. Such matchers are appropriate only when the test's contract genuinely doesn't care about the argument (rare). Prefer property-based matchers (e.g. `Arg.Is<T>(x => x.Property == expected)`) or capture-and-assert.
- **Negative assertions are weak when the contract is "exact value Y".** `Assert.DoesNotContain(forbidden, actual)` / `Assert.NotEqual(forbidden, actual)` pass for `null`, empty string, exception messages, and any random value — including when the code under test broke entirely and returned the wrong answer. Use them only when the contract genuinely is *"X must not be the result"* (e.g., regression tests for "this leaked secret never appears in the rendered output"). When the test's purpose is *"the fallback path produces Y"*, assert `Y` exactly with `Assert.Equal(expectedFallback, actual)`. Same energy as the test-specificity rule above — assert the contract, not its absence.
- **Don't materialize streams unnecessarily.** `.ToList()` / `.ToArray()` (and equivalents) inside a method that just iterates once is a wasted allocation and a smell that the author is hiding a re-enumeration bug behind it. Materialize only when (a) the result is consumed multiple times, (b) you need indexed access, or (c) you're crossing a boundary that requires a concrete collection. Same goes for eager collection ops in hot paths (`.Where(...).Count()` instead of `.Any()` / `.Count(predicate)`).
- **Lambda parameter shadowing.** Do not name a lambda parameter the same as an in-scope variable (`var filter = ...; filters.Where(filter => filter.X)`). The compiler accepts it; reviewers and humans misread it. Rename the lambda parameter to something distinct.
- **Failure paths must surface user-visible feedback (UI code).** When a `TryCreate`/`TryParse`/parsing operation returns `null`/`false` on the user-action path, do not silently no-op. Show a dialog, surface a validation message, or log at warning level — whichever matches the surface. Silent failures are the #1 bug source flagged in UI PRs.
- **Comment / path hygiene.** Never commit a `TODO`, `FIXME`, debug `Console.WriteLine` / `console.log` / `print()`, or absolute path that references your local machine (`C:\Users\<you>\...`, `/Users/<you>/...`, your Downloads folder). Strip these in self-review before showing the diff.
- **Idempotency / multi-dispatcher guards.** When you add a "have I done this already?" guard to one code path (`if (_done) return;`, `Add` → `TryAdd`), grep for every other code path that mutates the same state and add the guard there too. Reviewers consistently catch the second/third dispatcher that was missed.
- **Exception messages must stay diagnostic.** When you remove or change a parameter that previously fed an exception's message (computer name, file path, key, etc.), do not collapse the call to `string.Empty` or a bare type name. Replace it with whatever diagnostic context the catch site or log will actually need — typically the resource path, key, or operation that was attempted. Empty exception messages are unrecoverable in production logs.
- **Log messages must match the actually-taken code path.** When you add an early return, guard, or branch *between* a "we're about to do X" log and the code that does X, the log becomes a lie. Either move the log past the guards (so it only fires when X actually happens), or split into per-branch logs that name what really occurred ("Skipping fallback because input is rooted" vs "Falling back with leaf name 'foo.dll'"). Unconditional "Falling back to..." / "Retrying..." / "Loading..." messages that fire before a guard suppresses the action are the most common log-vs-behavior mismatch reviewers catch.
- **Log messages must match what the code actually returns.** A log that says "Returning null" / "No result" / "Failed to load" when the surrounding method actually returns a non-null empty/sentinel value (or vice versa) is a stale-text bug that reviewers always catch. When you change a method's return contract (null → empty collection, throw → return false, optional → required), grep every log line in that method for words describing the old contract and update them.
- **Test portability — no hardcoded system paths or locales.** Tests that touch the filesystem, registry, or system binaries must not hardcode `C:\Windows`, `C:\Program Files`, `\System32\en-US\`, drive letters, or specific UI culture folder names. Use the platform's standard "well-known folder" API or probe the available locale subfolders. Skip-gates are fine as a guard, but the *path you build* must adapt to the host. Same applies to environment variables that may not exist in CI.
- **No dead branches inside loops with the same termination condition.** When a loop's continuation condition already excludes some state (e.g., `while (!string.IsNullOrEmpty(culture.Name))`), an inner `if (state) break;` that fires on the *same* state is dead code — the loop would have terminated next iteration regardless. Either tighten the loop condition to express the full intent, or drop the redundant inner break. Reviewers (human and bot) consistently flag the redundancy and it implies the author hasn't traced the loop's exit conditions end-to-end. The corollary: when adding such an inner break, ask whether the loop condition already covers it; if yes, the break is the wrong fix.
- **Stale terminology when a method's scope widens.** When a helper that *was* legacy-only (or single-source, single-format, single-mode, single-tenant, etc.) gets re-used for a new path — modern fallback, additional file format, second source, multi-tenant — re-audit *every* string that referenced the original scope: the doc summary, the catch-block log message, exception messages, parameter names, exception-tag XML, `[Display]` / `[Description]` attribute strings, and any enclosing comment that named the old scope. Wording fossilizes when scope widens; reviewers (human and Copilot bot) consistently catch leftover qualifiers like "legacy" / "registry" / "v1" / "primary" / "single-tenant" when the implementation now serves the broader case. **Rule**: when broadening a method's input domain, grep its own body and its doc for the old-scope noun and either generalize the wording (drop the qualifier, use a neutral term) or split the helper into two (one per scope). **Self-check**: read the doc summary aloud while looking at the call sites; any call site that doesn't fit the doc is a doc bug, a code bug, or both. The same lens applies in reverse — when a doc says "for any X" but the body only handles X-of-type-Y, either the doc or the body is wrong.
- **Helper that hardcodes a parameter the caller threads through.** When `Outer(bool x)` does its own work for the `!x` case and then calls `Inner(..., x: true)` (with a literal, not the parameter), the asymmetry confuses every reader: `Inner`'s parameter looks ambiguous ("which `x` is right? the caller's or the literal?"), the contract is split between two places, and the structure invites the next maintainer to "fix" it by passing the parameter through and accidentally double-applying the `!x` work — a real regression. **Two clean fixes**: (a) move the `!x` work into `Inner` and propagate `x` through the call (single source of truth for the parameter's meaning); (b) rename `Inner`'s parameter so its different semantics are explicit at the call site (e.g., `combineWithExisting` for the outer caller-level intent vs `combineWithinBatch` for the inner per-iteration coalescing). Pick (a) when the `!x` work is shared by multiple `Outer`s; pick (b) when the two parameters genuinely mean different things. The status quo — same parameter name, different meaning depending on caller — is the bug. **Audit lens**: any time a diff hardcodes a literal for a parameter that the enclosing method also takes by name, ask whether the literal and the enclosing parameter mean the same thing; if yes, propagate; if no, rename.
- **Status / outcome enums must distinguish every outcome a caller could branch on.** When a method returns a status enum (`OpenLogStatus`, `LoadResult`, `ParseOutcome`, etc.), every value must correspond to **exactly one caller-relevant outcome**. The smell: a single enum value used for several distinct semantic cases — typically a "default" / "loaded" / "ok" value that the method returns from the success path AND from "no-op because already done" AND from "failed but recovered with a user-visible alert." This works while no caller distinguishes them, and silently breaks the moment a new caller needs to. Concrete instance: `OpenLogStatus { Loaded, Empty }` originally returned `Loaded` from (a) successful open + dispatch, (b) early-return on null path, (c) early-return on already-active log when combining, (d) `UnauthorizedAccessException` after showing a dialog, and (e) generic `Exception` after showing a dialog. A new batch caller that branches on "did this consume the close-existing semantics?" was correct for (a), wrong for (b)–(e), and the bug was undetectable until a reviewer traced every `return` site. **Rule**: every `return EnumValue;` statement in the method should map to a distinct, caller-meaningful outcome. If two `return` sites use the same value but one *did* the side effect and the other *didn't*, split the enum (`{ Opened, Skipped, Empty, Failed }` etc.). **Audit lens** when adding any new caller of an existing status enum: list every `return` statement in the producer, write down what side effect each one did or skipped, and check whether your new caller's branching matches that grouping. If it doesn't, the enum needs new values before the new caller is correct. The same principle applies to status returned via `out` parameter, tuple field, or `Result<T>`-style discriminator.
- **Sibling-producer parity for shared record / DTO types.** When two or more producers (`EventLogReader` and `EventLogWatcher`, two factories, multiple parsers, drag-drop and CLI entry points, etc.) emit instances of the same record/DTO type, every producer must stamp every metadata field that any downstream consumer depends on. The smell: one producer sets `Foo.Bar = X`, another doesn't, the field defaults to a value (`null`, `0`, `default`, `string.Empty`) that no downstream consumer is prepared for, and the bug only surfaces when the consumer that branches on `Bar` runs against the second producer's output. The compiler does not catch this because settable properties have implicit defaults. Concrete instance: `EventLogReader` set both `EventRecord.PathName` and `EventRecord.LogPathType` for every produced record; `EventLogWatcher` set only `PathName`, leaving `LogPathType` at the default `0` (which is *neither* `Channel = 1` nor `File = 2`). Downstream `XmlCacheKey` includes `LogPathType` in its key and the resolver passes it to `EvtQuery`/`EvtOpenLog`, so live-watched events silently failed XML resolution. **Rule**: when adding a metadata stamp to one producer, grep for every `new <RecordType>` and every method that returns the type, and add the matching stamp to each. **Audit lens**: any settable property on a shared record/DTO whose default is an "invalid sentinel" — an enum with no zero-mapped member, a string ID where `""` means "missing", a `Guid` where `Guid.Empty` means "unset" — should either (a) be `required` / `init`-only so the compiler forces every construction site to set it, or (b) live behind a non-nullable accessor that throws if read before set. **The combination of "field is settable" + "default value is invalid" + "downstream branches on the value" is the bug.**
- **Missing parameter null-guard in public extension methods (DI / builder / factory).** Any `public static T This<T>(this T self, ...)` extension method — composition-root DI extensions (`AddServices`, `RegisterUiLibrary`, `ConfigureServices`), builder extensions, fluent-API extensions — should validate its `this` parameter and any reference-typed required parameters with the language's null-check idiom (C# `ArgumentNullException.ThrowIfNull(...)`, Java `Objects.requireNonNull`, Kotlin `requireNotNull`, Python `if x is None: raise TypeError(...)`, Go nil-check + return error). The smell: a sibling extension method in the same project already does the guard but the new one doesn't — readers infer inconsistency means one of them is wrong, and the unguarded one will produce an opaque `NullReferenceException` 3 frames deep instead of a clear `ArgumentNullException`. Caught deterministically by `post-code-change.md` step 2.5.
- **Planning / commit-plan notation must NOT leak into public-facing comments.** Any XML doc summary, `///` doc comment, JSDoc `/** */`, Python docstring, Go godoc, public method comment, or `[Description]` / `[Summary]` attribute string referenced by external consumers MUST NOT include ephemeral planning IDs (`D6`, `D9`, `A2`, `Phase 5.5`, `step 7c`, `option B-hybrid`, `(per F16e-2 cascade)`, internal commit-plan section numbers). Future readers don't have the plan and can't dereference the ID. Either inline the explanation, link to a permanent issue/PR URL, or remove the reference entirely. The same rule applies to log strings that surface in user-visible diagnostics and to exception messages. Caught deterministically by `post-code-change.md` step 2.5.
- **Tests must NOT park on production timeouts.** Any test that exercises an async code path with a `TaskCompletionSource` await, `WaitHandle.WaitOne(timeout)`, `Task.WaitAsync(timeout)`, `await ... .WaitAsync(LogCloseTimeout)`, `await ... .WaitAsync(TimeSpan.FromSeconds(N))`, or similar production-timeout-bounded wait, must route or signal the dependency so the test completes in milliseconds. Tests that allow the production timeout to fire turn a unit test into a 30s integration test, slow down CI, and mask correctness bugs (the test "passes" because the wait expires, not because the code worked). The fix is to mock the waiter source (NSubstitute `.When(...).Do(...)`, Mockito `doAnswer`, pytest monkeypatch) so the awaited task signals quickly. **Audit lens**: any new test that takes >1 second to run is a smell — measure per-test duration and route any production-timeout dependency. Caught deterministically by `post-code-change.md` step 2.5.

> **C# adds (high-impact):** the **`nameof()` for code symbols inside ANY string** rule (including the test-mirror-via-named-argument pattern), brittle `Received(N)` count assertions on log/diagnostic mocks, **native interop / Win32 / P/Invoke return-value validation**, and **`LoadLibraryEx` / `Path.IsPathRooted` DLL-planting / wrong-binary risk**. See `csharp.instructions.md`. These bullets are the single highest-incidence smell class in the C# review history — read them once when first opening a C# file in a session.

### 3.11 Project and library structure

Every codebase — production app, library, CLI, sample — uses its language ecosystem's blessed project layout. **Do not invent a custom directory hierarchy** "because it makes more sense to me" or "because we only have one project right now." Tooling defaults (test discovery, build cache keys, IDE indexers, linters, package publishers, language servers, profiler attach paths) are written against the standard layout; deviating from it produces "works on my dev box, fails in CI" mysteries and forces every new contributor to learn a project-specific shape before their first useful edit.

| Ecosystem | Production | Tests | Root-level files |
|---|---|---|---|
| .NET (C#, F#, VB) | `src/<Project>/` | `tests/<Project>.Tests/`; with > 2 test projects split into `tests/Unit/` + `tests/Integration/` | `*.slnx` / `*.sln`, `Directory.Build.props`, `Directory.Packages.props`, `.editorconfig`, `global.json` |
| Node.js / TypeScript | `src/` | `test/` or framework-default (`__tests__/` for Jest, `test/` for Vitest) | `package.json`, `tsconfig.json`, lockfile |
| Python | `src/<package>/` (**src layout, mandatory**) | `tests/` | `pyproject.toml`, `README.md` |
| Rust | `src/main.rs` (binary) or `src/lib.rs` (library), `benches/` for benchmarks | `tests/` for integration; unit `#[cfg(test)] mod tests` inline | `Cargo.toml`, `Cargo.lock` |
| Go | `cmd/<binary>/main.go`, `internal/<pkg>/`, `pkg/<pkg>/` | `_test.go` files alongside the code under test | `go.mod`, `go.sum` |
| Java / Kotlin (Maven, Gradle) | `src/main/java/`, `src/main/kotlin/`, `src/main/resources/` | `src/test/java/`, `src/test/resources/` | `pom.xml` / `build.gradle` / `settings.gradle`, lockfiles |

When the ecosystem documents a "blessed" layout (Python's src layout, Go's `cmd/` + `internal/`, Maven's standard directory layout, .NET's `src/` + `tests/`), use it even when an alternative seems cleaner. The blessed layout is what tools assume; hand-rolled layouts cost everyone reading or building the project for the rest of its life.

**Surface deviations via `ask_user`, do not silently work around them.** When opening or working in an existing project, if you notice the layout deviates from its ecosystem standard in a way that has actual cost — test discovery breaks, CI configs hand-list project paths, contributors have to pass non-default `--working-directory`, build-config files (`Directory.Build.props`, `pyproject.toml`, `tsconfig.json`, `Cargo.toml`) sit below the projects they should govern, integration tests live next to unit tests with no separation, production code is intermixed with tests in the same root folder, lockfiles are duplicated across nested subdirectories — call `ask_user` with the deviation, the cost, and 3 options:

1. **Fix in this PR** (when the diff is naturally touching the affected area or the restructure is small).
2. **Fix as a separate PR** (recommended when the in-flight PR is already large or the restructure would dominate the diff and bury the actual change).
3. **Leave as-is and record the exception** (only when there is a documented constraint — vendored monorepo, downstream build system that hardcodes paths, ecosystem-specific reason — and the user confirms the cost is understood).

Do **not** silently work around the deviation by adding extra `cd` steps in pipelines, custom relative-path globs, per-project hand-maintained lists, or non-default `--working-directory` / `--project-dir` flags. Each workaround is a load-bearing assumption the future can lose; the layout fix is the actual repair.

**When restructuring an existing repo onto the standard layout**, use `git mv` (not `Move-Item` / `mv` / IDE drag-drop) to preserve git rename detection — otherwise `git log --follow`, `git blame`, and the code-review diff hunks all lose history at the move boundary. Move solution-level config files (linter configs, build props, package manifests, lock files) so they remain at or above the level of the projects they govern; don't leave them in the old location with relative paths the consumers can't see. After moving, immediately run the build and test commands locally to surface stale relative paths in `<ProjectReference>` / `<Compile Include>` / `import` / `require` / `extends` / `include` directives — the compiler / interpreter / bundler will find them faster than a code review will.

> **C# adds:** `src/` + `tests/Unit/` + `tests/Integration/` shape, the `IsTestProject` declaration requirement on every test csproj, the `dotnet sln add/remove` slnx-comment-stripping gotcha, and the directory-classified CI `dotnet test` loop pattern. See `csharp.instructions.md`.

### 3.12 Within-assembly folder topology — vertical slice + clean architecture

**VSA takes priority over clean architecture when they conflict.** Vertical slice — folder ownership by feature / domain — is the primary structural axis. Clean-architecture layering (cross-cutting domain types depend on nothing; slices depend on them) is overlaid on top and only kicks in when slice ownership doesn't determine placement (i.e., cross-cutting types). When a type could plausibly belong to one slice OR a shared `Common/<Domain>/`, prefer the slice unless the type already has ≥2 slice consumers. When naming an assembly, folder, or namespace, prefer slice-aware or domain-aware terms (`Workspace`, `Core`, `Features`, `Slices`, slice-named subfolders) over clean-arch-coded layer terms (`Application`, `Domain`, `Infrastructure`, `Presentation`). Layer terminology in names implies a tier-first organization that contradicts VSA priority.

Inside an assembly: **vertical-slice** (folders by feature / domain, not horizontal type-buckets like `Models/` + `Services/` + `Helpers/`) overlaid with **clean-architecture dependency direction** (cross-cutting domain types depend on nothing; slices depend on them). Cross-slice / cross-asm types live in `Common/<Domain>/` (e.g., `Common/Events/`, `Common/Channels/`); flat `Common/` is anti-pattern, the `<Domain>/` sub-folder is mandatory and DOMAIN-themed, not KIND-themed (no `Common/Models/` + `Common/Helpers/`). Slice-internal types stay in the slice. Avoid `Utils/` / `Helpers/` (as folder names AND as class-name suffixes — name what the code does: `DatabasePathSorter`, not `DatabaseHelpers`). For a single legitimate cross-asm consumer, prefer KEEP-PUBLIC in `Common/<Domain>/` (or split-member visibility on a public type) over adding a NEW friend-grant — friend-grants (C# `InternalsVisibleTo`, Java `module-info exports`, Kotlin friend-paths, TS subpath exports, etc.) expose ALL current AND future internals of the granting asm to the receiving one, far heavier coupling than one named exposed type. Re-using an existing friend-grant is free; adding a new one is the LAST resort. Full precedence ladder in `.github/playbooks/least-privilege-audit/axis-1-type-access.md`.

> **STOP.** Before restructuring assembly folder topology, extracting a duplicated method, or deciding `Common/<Domain>/` placement for a new cross-cutting type, view `.github/playbooks/library-restructure.md`. Covers consumer-audit checklist, namespace migration, test-mirror moves, IVT vs public trade-off, behavior-tracing for de-duplication, optimization patterns when extracting.

### 3.13 Plan structure for growth, not for current file count

Set up the folder structure you expect to grow into, even when one or two files would technically fit at the parent level today. The retrofit cost (`git mv` + namespace updates + `using` updates across every consumer + test-mirror moves) far exceeds the cost of pre-creating the sub-folder, so in practice the retrofit doesn't happen — whatever goes in unstructured tends to stay unstructured. Applies to STRUCTURAL decisions only: folder topology, namespace shape, project boundaries (production / unit-tests / integration-tests trio up front per §3.11), public-vs-internal accessibility, interface extraction, IVT grants. It does NOT override YAGNI for CODE decisions: don't add unused parameters, optional configuration knobs, abstract base classes "for future overrides", or strategy patterns that today have one strategy. Heuristic gate: create a sub-folder when you can name 2+ likely future additions to it — if you can't list them, the sub-folder is speculative. Structural debt compounds; code debt does not.

---

## 4. Git Identity & Push Credentials

Both **commit attribution** (`user.name` / `user.email` → author + committer of every commit) AND `git push` **authentication** MUST belong to the human user — never a "disallowed automation identity," defined (**case-insensitive match**) as any of: `Copilot`, `copilot[bot]`, `github-actions[bot]`, the Copilot CLI co-author email `223556219+Copilot@users.noreply.github.com`, any other `[bot]`-suffixed GitHub account, or any non-user service principal. A Copilot CLI session that authenticates as the **human user's own GitHub account** is fine — the forbidden case is attribution / authentication AS the agent.

Always-loaded. Procedure detail lives in `pre-commit.md` (§4.1 verification + prompt-when-missing + author-preservation on amend / replay) and `pre-pr-push.md` *Pre-check 0* (§4.2 mechanism-aware push verification + the `pushCredentialsVerified` state-predicate field defined in *Per-phase additional fields*).

### 4.1 Commit author identity — hard gates

- **No automation-identity injection.** The agent MUST NOT set `user.name` / `user.email` to a disallowed automation identity via ANY of: `git config` at any scope (`--local` / `--global` / `--system` / `--worktree`), `[include]` / `[includeIf]` file references, one-off `git -c user.name=… -c user.email=…` flags on a commit, `git commit --author="…"`, OR the environment variables `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` / `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` / `EMAIL`.

- **Prompt-when-missing.** Before any commit-producing operation (any Git command that lands a new commit — `commit`, `commit --amend`, `merge --no-ff`, `merge --continue`, `cherry-pick`, `rebase --continue`, `revert`, `am`, `am --signoff`, `commit-tree`, or any other), the agent MUST verify BOTH:
  1. **Effective config:** `git config --show-scope --show-origin --get user.name` AND `… --get user.email` resolve to non-empty values that are not a disallowed automation identity; `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` confirm what git would actually use **including env overrides** (env can override config silently — config inspection alone is not sufficient).
  2. **Preserved author** (for operations that preserve author from a replayed commit — `--amend` without `--reset-author`, `cherry-pick`, `rebase`, `am`): `git log -1 --format='%an <%ae>%n%cn <%ce>'` on the commit being amended / replayed shows neither author nor committer is a disallowed automation identity.
  
  On either check failing, the agent MUST surface via `ask_user` and either (a) collect `user.name` + `user.email` and write to **local** repo scope via `git config --local`, OR (b) for the preserved-author case, ALSO ask whether to pass `--reset-author` after the human identity is set. **Global-scope writes require an explicit user opt-in** (boolean in the same `ask_user` form, default `false`). The agent MUST NEVER guess name / email from machine username, GitHub session principal, prior repos on the machine, or any other heuristic — values come from the user's `ask_user` answer.

- **`--reset-author` is constrained.** Allowed ONLY to reset a disallowed-automation preserved author to the user's confirmed human identity (per the preserved-author branch above). It MUST NOT be used to overwrite a legitimate human author from another contributor, AND it MUST NOT be combined with `--author="…"`.

- **Don't touch commit signing.** The agent MUST NOT change `commit.gpgsign`, `gpg.format`, `user.signingkey`, or `gpg.<format>.program`. If signing fails OR the configured signing key looks like an automation key, surface via `ask_user` — never bypass with `--no-gpg-sign` without explicit user approval.

- **Commit-ownership prompts MUST display resolved identity AND use explicit actor labels.** Any `ask_user` that asks who runs the commit MUST include the resolved `<user.name> <<user.email>>` AND the resolving scope (`local` / `global` / `system` / `env-override`) in the message body, AND use the literal phrases `the agent` and `you (the user)` in BOTH the message body and the form-field option titles. **Bare `I` / `me` / `you` MUST NOT be used** in these prompts — they read ambiguously in agent-mediated chat (the user reads "you" as "me", the agent reads it as "the user", confusion follows). Commit-ownership is asked SEPARATELY from push-ownership — never bundle them in one prompt. The canonical form schema is in `pre-commit.md` Step 3b.

- **Surface unintended global-scope use.** When the resolved identity comes from `--global` scope, the commit-ownership prompt MUST surface that fact (the displayed scope makes it visible) so the user can choose to move it to `--local` before committing. The agent does NOT auto-migrate without user direction.

### 4.2 Push authentication — hard gates

- **§4.2 applies to EVERY agent-run push,** including personal-sandbox / backup pushes that exit the `pre-pr-push.md` review-readiness playbook at the sandbox pre-check, AND ref-publishing commands that implicitly push (`gh pr create` against an un-pushed branch, `gh repo sync`, `git push --mirror`, `git push --all`, anything else that creates or updates a remote ref).

- **No agent / automation principal.** The agent MUST NOT authenticate a push using: Copilot-owned credentials, a `gh` session logged in as a `[bot]` account or other automation account, ambient automation tokens (`GH_TOKEN`, `GITHUB_TOKEN`, `GIT_ASKPASS` injection, CI-provided tokens, `SSH_AUTH_SOCK` pointing at an agent-controlled socket) UNLESS the user explicitly confirms the token / agent socket is user-owned, OR any other non-user service principal.

- **Mechanism-aware verification before every push.** Determine the push mechanism from `git remote -v` + `git config credential.helper` and apply the matching verification (full procedure in `pre-pr-push.md` *Pre-check 0*):
  - **HTTPS + `gh` helper** → `gh api user --jq .login` returns the user's known GitHub username (NOT a `[bot]` account).
  - **HTTPS + system credential helper** (Windows Credential Manager, macOS Keychain, libsecret, GCM) — when the helper does NOT expose the cached principal, STOP and ask the user via `ask_user` to confirm the cached credential for the remote URL is theirs; record as `user-confirmed-unverifiable` on yes, `blocked` on no / unsure.
  - **SSH** → `ssh -T git@<host>` greeting matches the user's known account (when the host supports the greeting — e.g. github.com prints `Hi <username>!`).
  - **Ambient automation env vars present** (`GH_TOKEN`, `GITHUB_TOKEN`, `GIT_ASKPASS`, `SSH_AUTH_SOCK` not pointing at the user's own ssh-agent) → treat as unverified automation auth; STOP and ask the user via `ask_user`. Default to `blocked` unless user confirms otherwise.

- **No silent re-auth.** The agent MUST NOT run `gh auth login`, `gh auth refresh`, `gh auth switch`, `git credential approve`, `git credential fill`, `git credential erase`, or any other credential-modifying command on its own. If a push fails with an auth error, surface the error and let the user handle re-auth.

- **Push-ownership prompts are SEPARATE from commit-ownership.** Push-ownership MUST be asked in its own `ask_user` (never bundled with commit-ownership). It MUST use the same explicit actor labels rule from §4.1 (`the agent` / `you (the user)` — never bare `I` / `me` / `you`) AND MUST display the verified push principal (e.g. `verified via gh login: <login>` / `SSH greeting: <username>@github.com` / `user-confirmed credential helper: <helper-name>`) in the message body. The canonical form schema is in `pre-pr-push.md` *Pre-check 0*.

- **Recorded in pre-PR-push phase state.** `pushCredentialsVerified` is a **required predicate field** (10th field of the state predicate — see *Per-phase additional fields*). Values: `yes` / `user-confirmed-unverifiable` / `blocked`. A `blocked` value fails the readiness gate. Sandbox-exit records also record this field with a real value (no `n/a-sandbox-exit` sentinel — §4.2 applies to sandbox pushes too).

### 4.3 Composition

- §2 *Commit Messages* — forbids the `Co-authored-by: Copilot` trailer in the commit message body. Message-side mirror of §4.1's attribution rule.
- `pre-commit.md` Step 3 — applies §4.1 (Step 3a identity verify + preserved-author check; Step 3b commit-ownership prompt with explicit actor labels and resolved-identity display).
- `pre-pr-push.md` *Pre-check 0* — applies §4.2 (mechanism-aware verification + `pushCredentialsVerified` recording + push-ownership prompt). Runs BEFORE the sandbox pre-check so sandbox-exit records carry a real `pushCredentialsVerified` value.
- **Always-loaded scope.** §4 applies outside the formal phase playbooks too — to ad-hoc commits / pushes a user asks the agent to run without explicitly entering pre-commit / pre-pr-push. The verification + prompt-when-missing flow is mandatory regardless of which entry point reached the commit / push.

---

## 9. Repository & Worktree Layout Preference

Use the **single-root + hidden-bare-repo + sibling-checkouts** worktree layout for repos that need parallel checkouts. Procedure detail (setup steps, amend-safety, recovery from existing non-bare clones, per-worktree shell sessions, tooling caveats) lives in the playbook.

> **STOP.** Before creating, restructuring, or repairing a worktree, view `.github/playbooks/worktree-setup.md`. That file runs intake first (existing checkout state, custom hooks, branch refs) and walks the full setup / repair procedure.

---

## 10. Software Installation & Upgrades — Prefer the Platform Package Manager

When installing, upgrading, or uninstalling software on the user's machine, **prefer the platform package manager** (`winget` on Windows, `brew` on macOS, the distro's native manager on Linux) over hand-rolled downloads, vendor bootstrappers, or web-installer EXEs. Procedure detail (mandatory pre-flight checks, when to fall back to vendor bootstrappers, signature / version verification, "thank-you-for-downloading" page scraping for shortlink-rot recovery) lives in the playbook.

> **STOP.** Before installing, upgrading, or uninstalling any software, view `.github/playbooks/software-install.md`. That file runs intake first (target software, version constraints, target environment) and applies the full pre-flight + bootstrapper-validation procedure.

---

## Topic-specific files

The following files live under `.github/instructions/` and are loaded automatically by the Copilot CLI when files matching their `applyTo:` glob are in the working set. They extend the rules above with language-specific guidance.

| File | Loads when working with files matching | Adds |
|---|---|---|
| `csharp.instructions.md` | `**/*.cs`, `**/*.csx`, `**/*.csproj`, `**/*.razor`, `**/*.razor.cs`, `**/*.cshtml`, `**/*.aspx` | C# / .NET production-code style: XML-doc comment rules, `nameof()` requirement, NSubstitute / native-interop / `LoadLibraryEx` smells, Blazor + JS interop lifecycle, access modifiers, file + folder organization, recurring code smells, C# code style. `src/` + `tests/Unit/` + `tests/Integration/` solution layout, directory-classified CI `dotnet test` loops |
| `csharp-testing.instructions.md` | `**/*Tests*/**/*.cs`, `**/*Tests.cs`, `**/tests/**/*.cs`, `**/*Test/**/*.cs`, `**/*Test.cs`, `**/test/**/*.cs`, `**/*.Tests.csproj`, `**/*.UnitTests.csproj`, `**/*.IntegrationTests.csproj`, `**/*.FunctionalTests.csproj`, `**/*.AcceptanceTests.csproj`, `**/*.Test.csproj`, `**/*.UnitTest.csproj`, `**/*.IntegrationTest.csproj`, `**/*.FunctionalTest.csproj`, `**/*.AcceptanceTest.csproj` | C# / .NET test infrastructure: per-project `TestUtils/` default + shared `<Solution>.<Domain>.TestUtils` escape hatch, `<Domain>Builder` / `<Domain>Fixtures` / `<Domain>TestFixtures` / `<Domain>Assertions` / `<Domain>TestConstants` naming framework, fluent-builder escape clause, Testcontainers integration-infra pattern, sibling `<Solution>.<Domain>.TestUtils.Tests` project rule, test-purpose / gap audit / smells, test-name intent, test synchronization, alternatives-surface section |
| `cpp.instructions.md` | `**/*.cpp`, `**/*.h`, `**/*.hpp`, `**/*.cc`, `**/*.cxx`, `**/*.c` | C++ naming, formatting, member ordering |
| `javascript-typescript.instructions.md` | `**/*.ts`, `**/*.tsx`, `**/*.mts`, `**/*.cts`, `**/*.js`, `**/*.jsx`, `**/*.mjs`, `**/*.cjs` | JS/TS naming, formatting, expression preferences, imports |
| `html.instructions.md` | `**/*.html`, `**/*.htm`, `**/*.razor`, `**/*.cshtml` | HTML formatting, attribute order, semantic / accessibility best practices |
| `css.instructions.md` | `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less` | CSS naming (kebab-case / BEM), formatting, property order |

**To add a new topic file:** create `<topic>.instructions.md` under `.github/instructions/`, add a YAML frontmatter block with an `applyTo:` glob (comma-separated patterns), then write the rules. The CLI picks it up on the next session start. See `README.md` at the repo root for setup details.
