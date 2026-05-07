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

**Phrase examples are illustrative, not exhaustive.** The semantic discriminator below (artifact-requested vs exploratory-question) is canonical — when a user phrasing is novel, route by intent shape, not by phrase matching. Per-playbook trigger lists in `.github/playbooks/*.md` mirror these illustratively but the router table here governs.

### Pre-implementation phase

Hard gates (always apply, even if playbook unfetched):

- Diagnosis verified against source (NOT just inherited from prior agent / report / user prompt).
- Reproduction (bug fix) or benchmark (perf work) exists. No fix without a number that can move OR a failing test.
- Rubber-duck pass run unless user explicitly skipped (with recorded warning per User-skip policy below).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-implementation.md`.

### Post-code-change phase

Hard gates:

- Touched-file imports / usings sorted and unused removed.
- **Touched-file least-privilege audit applied.** Trigger: the diff has any **visibility / export / mutability surface delta** — adds a public/exported type or member; widens visibility; removes `sealed` / `final` / closed-extension; adds or widens a constructor / member / setter; exposes a field; changes package / module exports; introduces an exported Go top-level identifier; widens Rust `pub(...)` to bare `pub`. Each such delta is justified by a real same-file / same-asm / cross-asm consumer. Unjustified additions are demoted before the diff is shown. Do NOT trigger on body-only edits to an already-public type that change no surface. Procedure: run `least-privilege-audit.md` (touched-file scope) — applies all 6 axes (type access, sealing/final, ctor visibility, member visibility, setter, field hygiene). The "fresh grep beats cached survey" rule is non-negotiable.
- Multi-model reviewer panel run **in parallel** (no serializing); consensus reached or all dissents addressed.
- Diagnosis-verifying benchmark / test re-run; metric moved or test passes.
- Affected builds + tests pass.

> **STOP.** Before taking any action in this phase, view `.github/playbooks/post-code-change.md`. That playbook references `.github/playbooks/least-privilege-audit.md` for the touched-file 6-axis pass.

### Pre-commit phase

Hard gates:

- Diff shown to user; explicit approval received.
- Commit ownership confirmed (user vs agent).
- Single-line commit message; no Conventional-Commit prefix; no `Co-authored-by` trailer; no body / footer.
- Stage only touched files (`git add <path>` — never `git add .`).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-commit.md`.

### Pre-PR-push phase

Hard gates:

- Per-commit comment audit run on every commit's diff (already gated by §3.1 on each commit — verify it actually ran).
- Branch-wide rename-first sweep run once before first push intended for review.
- **Branch-wide least-privilege audit run** when `git diff <base>..HEAD` shows any **visibility / export / mutability surface delta** (same definition as the touched-file gate above) across the branch. Multiple small commits each individually fine can together leak too-public surface; the branch-wide pass re-greps with the final branch state. Procedure: run `least-privilege-audit.md` (branch-wide scope, restricted to the projects whose surface the branch touches). Skipped only when the branch has no visibility / export / mutability surface delta — that fact recorded explicitly with the justifying file list. Run AFTER any branch-wide rename-first sweep cleanup has been committed / amended, so the audit sees the final branch state. Fresh grep at audit time; cached classifications from earlier in the branch are stale.
- Resolved sweep base SHA + sweep HEAD SHA + base ref name **recorded in canonical session todos** (per *Phase-state tracking convention* below) for re-run logic.
- No "ready to push" claim until per-commit audit, branch-wide sweep, AND branch-wide least-privilege audit (when applicable) are done OR user explicitly skipped (with recorded warning).

> **STOP.** Before taking any action in this phase, view `.github/playbooks/pre-pr-push.md`. That file is an INDEX — it runs intake first, then directs you to the matching sub-files (`per-commit-micro-hygiene.md`, `branch-wide-sweep.md`, `cleanup-commit-buckets.md`, `when-to-re-run-sweep.md`) per a deterministic decision tree. The least-privilege-audit playbook (`.github/playbooks/least-privilege-audit.md`) is a sibling invocation when the branch touches public API surface.

### Post-PR-review phase

Hard gates:

- Each bot finding verified against source before applying / dismissing.
- Sub-agent findings outside scope routed via `ask_user`; never silently dropped.
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
- Framework-mandated visibility (Razor `[Parameter]`, Spring beans, EF Core proxies, Fluxor reducers, etc.) flagged with NOTE, not auto-recommended for tightening.
- Applies to ALL languages (C#, Java, Kotlin, TypeScript, Rust, Go, C++, Swift, Python by convention) — see the per-language tooling table in the playbook.

> **STOP.** Before drafting any design-spec / ADO output, OR before invoking the least-privilege audit at any scope, view the matching playbook for the full intake + procedure.

### Fail-closed rule for on-demand playbook fetch

Playbook files under `.github/playbooks/` are NOT auto-loaded — the agent fetches them via `view` when entering a phase or accepting a trigger. If a required playbook **cannot** be fetched (file moved / renamed / unreadable / repo not in working set / fetch errors out), do NOT certify the phase complete. Bounded retry-then-escalate:

1. **Retry the fetch once** — for transient errors (network blip, CLI tool flake). Do NOT retry more than once without user input; unbounded retry hangs the session.
2. If the second attempt also fails, **ask the user via `ask_user` how to proceed** (e.g. *"the post-code-change playbook can't be fetched — is the file present? Do you want me to skip the multi-model panel for this change, or pause until the file is restored?"*). Surface the actual error message and the playbook path that failed.
3. If the user explicitly authorizes a skip, **record an explicit user skip per the User-skip policy below** (canonical mechanism, with reason "playbook fetch failed").
4. **Hard stop when `ask_user` is unavailable** (headless / non-interactive contexts where step 2's `ask_user` cannot reach a user — same condition as the User-skip policy *Hard stop when ALL recording paths fail* rule below): halt the phase and do NOT certify readiness. Surface a non-zero exit / failure signal to the runtime if one is available. The cascade has no authorized skip, so the workflow cannot proceed.

Do **not** proceed using only the abbreviated hard-gate checklist as the procedure — the checklist confirms the gate, the playbook teaches the procedure. Hard-gate-only execution silently degrades the phase (e.g. running one reviewer instead of the four-model parallel panel) while believing the gate passed.

### Cross-cutting rules (always apply, no fetch needed)

- **Pre-existing issues** (also referenced from playbooks as the *"Pre-existing issues / `ask_user` is mandatory"* cross-cutting rule): if you find one that could be or is causing an issue, ask whether to resolve it now via `ask_user` (fix now / defer / dismiss with reason). Otherwise record it as a follow-up — log it in the session, file an issue, or add it to the user's tracker. **Do NOT add a `TODO` / `FIXME` / `HACK` comment in code** (per §3.1 hard prohibitions); use the user-facing escalation path described in this rule instead.
- **This includes findings surfaced by sub-agents** (rubber-duck, code-review, etc.) that are tangentially related but **outside the current task or PR scope**. Do NOT silently expand scope to fix them, and do NOT silently drop them. Briefly summarize each finding (1 line each), state your recommendation, and use `ask_user` to choose: address now in this change, defer to a follow-up (record externally — session note, issue, or tracker — never as a TODO comment), or dismiss with reason.
- **`ask_user` is mandatory, not optional.** Mentioning a sub-agent finding inside your final review summary, the diff walkthrough, the "ready to commit" message, or any other prose without a paired `ask_user` call counts as silently dropping it. Even findings the reviewer itself labels "out of scope," "pre-existing," "not introduced by this change," or "low severity" must go through `ask_user` — those labels are the reviewer's opinion, not your decision to make on the user's behalf.
- **Audit step before declaring ready.** Immediately before saying any variant of "ready to commit" / "all reviewers agree" / "no remaining issues," re-read every sub-agent response from this task and confirm that every distinct finding (regardless of severity or scope label) has either (a) been fixed in the diff, or (b) been routed through an `ask_user` call this turn. If any finding is in neither bucket, stop and route it through `ask_user` first.
- **Unintended reverts:** if you see code that was removed, refactored, or renamed that differs from a previous change you made, ASK before reverting.
- **Do NOT report the task ready to push / ready to open the PR** until every required phase has either (a) been completed for every committed work cycle (per the relevant playbook's hard gates) or (b) been explicitly skipped by the user with a recorded warning. (The preamble's "ASK before skipping" rule is the only escape hatch — never self-judge a change as exempt.)

### Ask-first principle for all playbooks

Every playbook file under `.github/playbooks/` has an Intake Questions section as its first executable block. When entering a playbook, the agent's FIRST action is to view that file and run intake. Use `ask_user` when available; otherwise ask in chat. **Bundle independent questions in one prompt; ask sequentially only when a later question depends on the prior answer.** The agent does NOT produce playbook output, write to artifacts, or take downstream actions until intake is complete (or the user has explicitly skipped a specific step — see User-skip policy below).

**Phase triggers vs domain triggers — different semantics.**

- **Phase triggers** (the code-change phases in the router: pre-implementation, post-code-change, pre-commit, pre-PR-push, post-pr-review) are **mandatory** when their condition holds. The agent enters the phase and fetches the playbook. The user may skip a step within the phase only via the User-skip policy (with warning + recording + safety-critical re-confirmation). The agent does NOT ask "do you want to run this phase?" — it just enters.
- **Domain / documentation triggers** (design-spec, ADO task planning) are **offered** via `ask_user` because they're optional per-ask. Detection of a domain / documentation trigger never auto-fires the playbook — the agent always confirms first (*"this looks like a design-spec ask — want me to run that playbook?"*) and waits. If the user declines, the agent answers normally without the playbook.

### Intake pre-fill rule

If the user opens with structured detail that maps to intake questions (e.g. *"design-spec for the X service, current-state mode, audience=team"*), pre-fill those answers and ask only the unfilled questions.

**Confirm any pre-filled value that maps to an overloaded term** before using it: *"team"*, *"owner"*, *"audience"*, *"scope"*, *"destination"*, and similar are tentative and must be re-confirmed if they affect output structure. Exact `key=value` syntax (e.g. `audience=team`) may pre-fill directly without re-confirming. Never infer IDs, owners, linked work items, or output destinations from bare phrases.

### Trigger detection — strong vs weak

Per-playbook trigger phrases are listed in the workflow router table above. The discriminator between strong and weak is **semantic, not phrase-based**:

- **Strong triggers** — user is asking for a **durable artifact**: a spec, survey, design doc, architecture write-up, formal current-state document, ADO work item, or formal deliverable list. Agent immediately offers the playbook via `ask_user`: *"this looks like a design-spec ask — want me to run that playbook?"*. If the user declines, do not re-offer in the same thread unless the ask materially changes.
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

When SQL is unavailable, write the same field set as a `## phase-state-<phase>-<yyyymmddHHMMSS>` heading with key:value lines under it in `<copilot-session-state>/<session-id>/files/phase-state.md`. **Reader contract** (LLM consuming the record in a resumed session): parse `key: value` lines from the description; treat unknown keys as informational; require `phase`, `time_entered`, `intake_status` (description) AND `status` (read from the SQL `status` column directly, or — in the markdown fallback — from a `status: <value>` line) to consider the record valid. Any phase-specific required fields (e.g. the 9-field pre-PR-push state predicate below) must additionally be present for the readiness check that consumes them.

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

**Sandbox-exit record** (used when the pre-PR-push pre-check exits because the current push is personal-sandbox / backup-only): write the standard minimum canonical shape PLUS `branchWideSweepStatus: not-applicable` and the booleans `isFirstReviewExposurePush: false` + `remoteExposureExists: <true|false per actual remote history>`. Other 9-field-predicate keys (`baseRef`, `baseSha`, `sweepHeadSha`, `perCommitAuditCoverage`, `cleanupBucketOutcomes`, `rerunConditionsChecked`) may be written as the literal sentinel `n/a-sandbox-exit` (NOT omitted — predicate completeness still requires the keys to appear). The record is a normal `done` phase-state record, not a "skipped" record; it documents that the pre-PR-push playbook explicitly resolved as not-applicable for this push.

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
rerunConditionsChecked: n/a-first-push'
WHERE id = 'phase-state-pre-pr-push-20240115140312';
```

The INSERT captures intake-time state (booleans + sweep-input SHAs); the UPDATE captures completion-time state (sweep outcome, audit map, cleanup outcomes) and flips `status` to `'done'`. The `n/a-first-push` value on `rerunConditionsChecked` is the documented sentinel for "no prior sweep to re-run-check" (see field definition above).

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
- **Remove existing stale comments** that no longer add value when touching surrounding code. Don't preserve old narration just because it was there before.

**Common failure modes flagged in past reviews:**
- Adding `// Only commit if we're still the most recent load.` above an `if (gen == _gen)` check. The check + name says it. Delete the comment.
- Adding `// Bump generation so an in-flight Refresh skips its commit` above `_gen++` in a Dispose path. The dispose context + a well-named field carry it. Delete.
- Adding `// Same best-effort contract as CopySelectedEvent: callers (banner copy-details, filter export, future surfaces) are typically fire-and-forget UI handlers.` above a try/catch around a clipboard call. Triple violation: speculation about future callers + restating-what-the-code-does + multi-clause prose. Delete the entire comment — the try/catch + the log message ARE the contract.

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

### 3.4 Tests and Benchmarks

- **Intent over coverage — the default for every test, new or existing.** Before writing or keeping a test, answer in one sentence: *"What concrete regression in the SUT would make this test fail?"* If the answer is "I can't think of one without changing the test itself", do not write it (or delete it if it already exists). The default is **intent-driven, thorough tests** that exercise real behavior, including the trigger that proves the asserted contract — not coverage-driven filler that pins trivial getters, framework code, language-guaranteed type checks, or "nothing happened" without including the would-be stimulus. Coverage-driven tests are appropriate **only** when the user explicitly asks for "complete code coverage", a coverage sweep, or similar. When a coverage report points at uncovered lines that don't represent real behavior (auto-properties, unreachable defensive branches, generated code), leave them uncovered — a high coverage number built from filler hides the real coverage gaps. When auditing a file you're editing, flag tests that fail this question for deletion or rewrite rather than preserving them out of inertia. See `csharp.instructions.md` for the full audit-and-delete framework, including the deterministic-synchronization rules for tests that wait on async events.
- Tests and benchmarks follow all the standards above (no abbreviations, descriptive names, no narrative comments).
- **Test method names** are full sentences describing the scenario and expectation: `GetCustomer_WhenCaseDiffers_FindsExistingCustomer`.
- **Benchmark class and method names** match the production symbol they exercise: `UserSessionCacheBenchmarks.Lookup_HotCode_NoAllocation`.
- **Avoid wall-clock time sources in tests** (`DateTime.Now`, `DateTime.UtcNow`, `Date.now()`, `time.time()`, etc.) — they introduce non-deterministic behavior and timezone dependencies. Use fixed deterministic timestamps (e.g. `new DateTime(2024, 1, 1, 12, 0, 0, DateTimeKind.Utc)`) so tests are reproducible regardless of when or where they run.
- **Add or update unit tests** to cover new code and edge cases. Follow existing testing patterns in the codebase.

> **C# adds:** the `TestUtils/` folder convention and the `Constants` partial-class convention for shared test values. See `csharp.instructions.md`.

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

> **C# adds (high-impact):** the **`nameof()` for code symbols inside ANY string** rule (including the test-mirror-via-named-argument pattern), brittle `Received(N)` count assertions on log/diagnostic mocks, **native interop / Win32 / P/Invoke return-value validation**, and **`LoadLibraryEx` / `Path.IsPathRooted` DLL-planting / wrong-binary risk**. See `csharp.instructions.md`. These bullets are the single highest-incidence smell class in the C# review history — read them once when first opening a C# file in a session.

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
| `csharp.instructions.md` | `**/*.cs`, `**/*.csx`, `**/*.csproj`, `**/*.razor`, `**/*.razor.cs`, `**/*.cshtml`, `**/*.aspx` | C# / .NET style, XML-doc comment rules, `nameof()` requirement, NSubstitute / native-interop / `LoadLibraryEx` smells, Blazor + JS interop lifecycle, `TestUtils` folder + `Constants` partial-class convention |
| `cpp.instructions.md` | `**/*.cpp`, `**/*.h`, `**/*.hpp`, `**/*.cc`, `**/*.cxx`, `**/*.c` | C++ naming, formatting, member ordering |
| `javascript-typescript.instructions.md` | `**/*.ts`, `**/*.tsx`, `**/*.mts`, `**/*.cts`, `**/*.js`, `**/*.jsx`, `**/*.mjs`, `**/*.cjs` | JS/TS naming, formatting, expression preferences, imports |
| `html.instructions.md` | `**/*.html`, `**/*.htm`, `**/*.razor`, `**/*.cshtml` | HTML formatting, attribute order, semantic / accessibility best practices |
| `css.instructions.md` | `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less` | CSS naming (kebab-case / BEM), formatting, property order |

**To add a new topic file:** create `<topic>.instructions.md` under `.github/instructions/`, add a YAML frontmatter block with an `applyTo:` glob (comma-separated patterns), then write the rules. The CLI picks it up on the next session start. See `README.md` at the repo root for setup details.
