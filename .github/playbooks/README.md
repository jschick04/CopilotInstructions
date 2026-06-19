# Playbooks

On-demand workflow detail for the Copilot CLI. **Not auto-loaded** - `AGENTS.md` references each playbook by path and the agent fetches it via `view` only when the corresponding phase is entered or when the agent detects a strong-trigger intent and the user confirms via `ask_user`.

## Why this folder exists

`AGENTS.md` (always-loaded core) holds:

- Universal coding standards (naming, comments policy, recurring smells, etc.).
- A workflow router table (user intent → required playbook).
- Per-phase **hard-gate checklists** - the rules that must hold for the phase to count as completed.
- A `STOP. Before this phase, view <playbook>.` directive per phase.

Procedural detail - multi-step instructions, intake questions, examples, decision trees - lives in this folder so it doesn't tax every session's prompt budget.

## Conventions

### File naming

Phase playbooks are named for the phase they cover: `pre-implementation.md`, `post-code-change.md`, `pre-commit.md`, `pre-pr-push.md`, `post-pr-review.md`. Domain playbooks are named for what they produce: `design-spec.md`, `ado-task-planning.md`. One-off helpers: `worktree-setup.md`, `software-install.md`.

Sub-files of a heavy playbook live in a sibling subfolder named after the parent. Example: `pre-pr-push.md` is the index, and `pre-pr-push/per-commit-micro-hygiene.md` / `branch-wide-sweep.md` / `cleanup-commit-buckets.md` / `when-to-re-run-sweep.md` hold the detail.

### Required structure for every playbook

Every playbook file starts with these sections in this order:

0. **Manifest frontmatter** (trigger-fired playbooks only - domain + utility classifications; phase playbooks skip this section). See *Manifest frontmatter* below.
1. **Purpose** - one paragraph: when this playbook applies and what it produces.
2. **Hard gates** (when applicable) - the rules that MUST hold for the phase / artifact to count as completed. Mirrored in `AGENTS.md` so the gate survives playbook-fetch failure (per the fail-closed rule).
3. **Intake questions** - the questions the agent must ask (or pre-fill from upfront input) as the first executable block, before doing anything else. Bundle independent questions; ask sequentially only when a later question depends on an earlier answer.
4. **Procedure** - the actual step-by-step. May reference sibling playbooks or other files.

### Manifest frontmatter (trigger-fired playbooks only)

Trigger-fired playbooks (domain + utility classifications) carry YAML frontmatter at the very top of the file:

```yaml
---
name: design-spec
description: Use when user wants to draft a design spec, current-state survey, or implementation spec for a system or service.
triggers:
  - "design spec for"
  - "write up a design for"
  - "document the current architecture of"
---
```

Fields:

- `name`: kebab-case slug; must equal the filename without `.md`. For folder-indexed playbooks (e.g. `least-privilege-audit.md` with sibling `least-privilege-audit/` sub-files), `name` matches the index file's slug.
- `description`: one paragraph in the form *"Use when user wants to X, mentions Y, or asks for Z"*.
- `triggers` (optional): list of canonical strong-trigger phrases - **illustrative only**.

**Frontmatter is metadata only.** It does NOT drive initial trigger detection - detection happens before the playbook is fetched. The `AGENTS.md` semantic discriminator (strong / weak / ambiguous artifact-adjacent) is canonical. Frontmatter aids discoverability (humans reading the file directly) and is mirrored into `.github/playbooks/manifest.yaml` for post-classification disambiguation when router rows alone do not distinguish adjacent triggers.

**Phase playbooks** (`pre-implementation.md`, `post-code-change.md`, `pre-commit.md`, `pre-pr-push.md`, `post-pr-review.md`) do NOT use frontmatter - they fire from workflow state, not from trigger detection.

### Intake-questions rules

- Use `ask_user` when available; otherwise ask in chat.
- **Bundle independent questions in one prompt.** Sequential one-at-a-time is reserved for conditional branching.
- **Pre-fill from upfront input** when the user opens with structured detail (e.g. `mode=current-state, audience=team`). Ask only the unfilled.
- **Confirm overloaded terms** before using them. Words like *team*, *owner*, *audience*, *scope*, *destination* are tentative; re-confirm if they affect output structure. Exact `key=value` syntax may pre-fill directly.
- Never infer IDs, owners, linked work items, or output destinations from bare phrases.

### Output-write ordering (for documentation playbooks)

For playbooks that produce a document (`design-spec.md`, `ado-task-planning.md`):

1. Intake determines the *intended* final destination.
2. The draft is rendered in chat first, regardless of intended destination.
3. The user reviews and approves (or requests revisions) on the draft.
4. Only after approval does the agent write to the chosen destination.

Never write to a file before the user has approved the content.

## How to add a new playbook

1. Create `.github/playbooks/<name>.md` (and a sibling subfolder if the playbook needs sub-files).
2. Lead with the four required sections (Purpose / Hard gates (when applicable) / Intake questions / Procedure) per the canonical structure above.
3. Add an entry to the workflow router table in `AGENTS.md` - both the trigger condition and the required playbook path.
4. If the playbook should be offered on a strong trigger, add the trigger to AGENTS.md's workflow router as a row with the strong-trigger intent description (artifact requested / phase reached). The semantic discriminator in AGENTS.md is canonical; per-playbook trigger lists are illustrative only - never make detection depend on exact phrase matching.
5. Run a path-consistency audit: grep the repo for the new path; verify it resolves; verify no stale path references the old layout.

## Trigger semantics

| Tier | Behavior |
| --- | --- |
| **Strong trigger** (user requests a durable artifact - *"design spec for…"*, *"draft an ADO task for…"*) | Agent immediately offers the playbook via `ask_user`: *"this looks like a design-spec ask - want me to run that playbook?"*. If declined, do not re-offer in the same thread unless the ask materially changes. |
| **Weak trigger** (exploratory factual question - *"how does X work?"*, *"what do we have in prod for X?"* asked casually) | Agent does NOT block. Optionally adds a single non-blocking sentence: *"I can answer directly, or run the design-spec playbook for a more formal write-up - which do you prefer?"*. |
| **Phase trigger** (workflow-state-driven, e.g. user just approved a diff) | Agent enters the phase, fetches the playbook, runs intake. **Fail-closed on fetch failure** (per `AGENTS.md` *Fail-closed rule for on-demand playbook fetch*): retry the fetch once for transient errors; if it still fails, ask the user via `ask_user` how to proceed; record an explicit user skip per the User-skip policy ONLY if the user explicitly authorizes one. Do NOT retry more than once without user input. The abbreviated hard-gate checklist in `AGENTS.md` confirms the gate; it does NOT substitute for the playbook procedure. |

The semantic discriminator (artifact-requested vs exploratory-question) is canonical per `AGENTS.md` *Trigger detection - strong vs weak*. Per-playbook strong-trigger phrase lists are illustrative - they help readers recognize the shape of the ask but are not exhaustive and do not override the discriminator. Playbook frontmatter (`description`, `triggers`) and `.github/playbooks/manifest.yaml` are metadata / discoverability aids only - they do NOT drive detection. After AGENTS.md has selected or shortlisted a workflow, the manifest may be consulted for disambiguation prose on adjacent trigger pairs.

## Authoring conventions cross-reference

Conventions that span multiple playbooks plus AGENTS.md, summarized here with pointers to the canonical source:

- **Manifest frontmatter** (trigger-fired playbooks only) - see *Manifest frontmatter (trigger-fired playbooks only)* in the Conventions section above. Metadata only; does not drive trigger detection.
- **Evidence gates** - structured chat-visible audit output the agent MUST produce before declaring a phase / task complete or before producing an artifact. Every gate output includes: search scope (files / globs / method used), file:line citations for each item counted, and zero-count justification (e.g. "scope X has 0 items per scan command Y") for any audit category that finds nothing. `pre-pr-push.md` state read-back is the documented carve-out - it prints the state predicate verbatim and has no zero-count concept. Applies to: `AGENTS.md` §3.1 comment audit (spec hosted in `post-code-change.md`), cross-cutting findings audit (spec in `multi-model-review/evidence-gate-spec.md`), pre-PR-push state read-back (spec in `pre-pr-push.md`), `post-pr-review.md` per-finding audit, and every new domain playbook's procedure section.
- **Discoverability manifest** - `.github/playbooks/manifest.yaml` is the sibling-of-the-router index. One entry per trigger-fired playbook with `name`, `path`, `classification` (phase | domain | sub-step | utility), `description`, `triggers`, `status`, optional `discrimination`. Generated / derived from playbook frontmatter - keep it in sync when a playbook's frontmatter changes. Consulted only AFTER the AGENTS.md router has shortlisted a workflow; never drives initial trigger detection.
- **Multi-model review loop** - `multi-model-review.md` codifies the panel-of-reviewers convergence pattern. Trigger-fired as a domain playbook for plan / design / spec reviews; utility-called by `post-code-change.md`'s multi-model reviewer panel hard gate. Three convergence models selected at intake: unanimous (default), threshold (≥75% DESIGN_READY + 0 unaddressed blocking findings), confidence-weighted (≥80% avg confidence + 0 unaddressed blocking). Max-loop default 5 rounds; escalate via `ask_user` on exceedance. Holdout blocking findings always require explicit `ask_user` routing regardless of convergence model. Sole-NEEDS-reviewer dissent on precise polish (1-2 line fixes, no architectural concern) auto-routes to C2 `routed-deferred` rather than triggering another round - the asymptotic-convergence pattern documented in `multi-model-review/convergence-models.md`.

## User-skip policy

See `AGENTS.md` §1 *User-skip policy* for the canonical rules. Summary: warn on consequence, record the skip in the canonical mechanism (session todos), enumerate skips in any "ready" message, re-confirm safety-critical skips. Do not duplicate the canonical text here - read AGENTS.md to avoid drift.

## Phase-state tracking

See `AGENTS.md` §1 *Phase-state tracking convention* for the canonical field set, todo schema (`phase-state-<phase>-<yyyymmddHHMMSS>` ID pattern, parallel to skip records), and recording rules. Pre-PR-push specifically uses a **10-field state predicate** (base ref / base SHA / sweep HEAD SHA / `isFirstReviewExposurePush` / `remoteExposureExists` / per-commit audit coverage / branch-wide sweep status / cleanup bucket outcomes / re-run conditions checked / **`pushCredentialsVerified`** - the §4.2 push-credential verification outcome, values `yes` / `user-confirmed-unverifiable` / `blocked`) plus one informational eleventh field (`sandboxPriorExposureConfirmation` - `confirmed-private` / `denied-or-unsure` / `not-needed`, written only when the conditional sandbox-exemption gate fires AND an amend is actually attempted; absent / `not-needed` otherwise). Enumerate every predicate member when recording, and read state back from canonical session todos - never infer from memory - before declaring "ready to commit / push / open PR".

## Fetch discipline (keep the on-demand model paying for itself)

The whole point of moving procedural detail into this folder is to keep the always-loaded prompt small. That benefit evaporates if the agent prefetches every sibling file or re-views playbooks it has already read. Discipline:

1. **Fetch only the index file first** when entering a phase or accepting a trigger (e.g. `pre-pr-push.md`). Read its decision tree, then fetch only the sub-files the tree directs you to (per the conditional steps).
2. **Do NOT prefetch illustrative templates** (`templates/*.md`) - fetch them only when the playbook says you're about to write the artifact.
3. **Do NOT re-view a playbook already viewed in the same session** unless one of these exceptions applies: (a) the file may have changed (e.g. the agent edited it); (b) phase-state evidence was lost (reset session); (c) the agent crossed into a different phase that requires a different playbook; (d) **context-recovery** - the playbook's procedural content is no longer in the agent's current context (long session, summarization, or other context loss) and the agent cannot faithfully apply it from notes or memory. When re-viewing for context-recovery, record that the re-view was a context-recovery re-fetch (not prefetching) in the phase-state record's `description` so a reader can distinguish disciplined re-fetches from undisciplined prefetches. Phase-state tracking records `playbook viewed` per phase entry - consult it before re-fetching.
4. **Sub-files compose, not replace** - `pre-pr-push.md` is an INDEX. The sub-files under `pre-pr-push/` are conditional. Don't fetch all four when only one or two apply.
