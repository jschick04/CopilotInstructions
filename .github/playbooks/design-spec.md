---
name: design-spec
description: Use when user wants to draft a current-state survey, design-change request, or dev design spec for a system, service, or component. Strong-trigger discriminator from codebase-architecture-audit (audit / review / find-debt) - design-spec produces a durable artifact, audit produces a ranked findings list.
triggers:
  - "design spec for"
  - "write up a design for"
  - "document the current architecture of"
  - "document what we have in prod for"
  - "current-state survey for"
  - "design change request for"
  - "dev design spec for"
  - "implementation spec for"
  - "build spec for"
  - "architect review of"
---

# Playbook: Design-spec generation

## Purpose

Produce a design-spec document - one of three modes: a **current-state survey** of an existing system, a **design-change request** for a proposed change, or a **dev design spec** describing how an approved change will be built / deployed / observed / tested. The three are strictly separated. The agent runs intake first to choose the mode and gather grounding context, then drafts in chat, gets user approval, then (and only then) writes to the chosen destination.

Triggered when the user asks for a **durable artifact** describing a system or design change - any of:

- *"can you do an architect review of…"*
- *"I need a design spec for…"* / *"write up a design spec for…"*
- *"current-state survey for…"*
- *"I need a design change request for…"*
- *"write up a design for…"*
- *"document the current architecture of…"*
- *"document what we have in prod for…"*
- *"dev design spec for…"* / *"implementation spec for…"* / *"build spec for…"*
- *"how will we build / ship / test (the approved feature) X?"* (when phrased as a request for a written spec, not a casual question)

These are **strong triggers**: the agent immediately offers this playbook via `ask_user` (*"this looks like a design-spec ask - want me to run the design-spec playbook?"*). Decline-then-no-retry rule applies (per `AGENTS.md` trigger detection).

**Not a strong trigger:** factual existence questions or exploratory factual questions that do NOT request a document. Examples that should be answered directly (or with a single non-blocking offer of this playbook):

- *"is there a spec / design doc for X?"* - factual existence question; answer "yes/no" + path. Optionally add: *"if not and you'd like one, I can run the design-spec playbook."*
- *"how does X work?"*
- *"what do we have in prod for X?"* (asked casually, not as *"document what we have in prod for X"*)

Strong triggers require an artifact-request signal. **The canonical verb / noun discriminator lives in `AGENTS.md` *Trigger detection - strong vs weak*** - defer to that single source rather than maintaining a duplicate list here. Notably (per AGENTS canonical): bare *"review"* / *"audit"* are NOT strong on their own; they only become strong when paired with an artifact noun (*"architect review of"*, *"audit report"*, etc.). Bare unpaired forms fall into AGENTS' *ambiguous artifact-adjacent* category and trigger one short clarifying `ask_user`.

## Hard gates

- Intake completed before any drafting (no early starts).
- One of the three strict templates picked (no hybrid current-state-plus-change unless explicitly requested as a fallback per the linked-pair pattern below; no mixing dev-design-spec content into a current-state survey or design-change request).
- Draft rendered in chat first, regardless of intended destination.
- User explicitly approves before any file write.
- All claims about real systems grounded in source via `view` / `grep` / `explore` - no invented component names, file paths, GUIDs, IDs, or behaviors.
- Assumptions marked explicitly as `*(ASSUMED - not verified in source)*`.

## Intake questions

Bundle independent questions in one `ask_user` prompt. Sequential follow-ups only when later questions depend on prior answers.

**First batch (always asked, bundled):**

1. **Mode** - current-state survey, design-change request, OR dev design spec? (the three templates - see *"Picking the mode"* below if unsure)
2. **Audience** - internal team, leadership, vendor, cross-team review, etc.?
3. **Depth** - high-level architecture only, or include implementation-level detail?
4. **Scope** - what subsystem / feature / module? (be specific - names, repo paths, system identifiers)
5. **Output destination** - pasted into ADO task, sent in email, committed to repo, saved as a chat-only artifact, or a specific file path? (affects formatting decisions - internal links vs absolute URLs, embedded images vs referenced)
6. **Source material** - am I reading the codebase fresh, or do you have prior docs / runbooks / tickets I should ground in?
7. **Known constraints / non-goals** - anything I should explicitly call out as out of scope?

**Picking the mode** (use these prompts when the user is unsure):

| You're answering… | Mode |
| --- | --- |
| *"What does the system look like today?"* | current-state survey |
| *"What should change and why?"* | design-change request |
| *"How will we build / deploy / observe / test the approved change?"* | dev design spec |

**Pre-fill from upfront input.** If the user opened with structured detail mapping to these questions (e.g. *"design-spec for the X service, current-state mode, audience=team"*), pre-fill those answers and ask only the unfilled questions.

**Re-confirm overloaded terms** before using as pre-fill: "team", "owner", "audience", "scope", "destination" are tentative and must be re-confirmed if they affect output structure. Exact `key=value` syntax (e.g. `audience=team`) may pre-fill directly without re-confirming.

**Conditional follow-ups** (asked only after the mode is locked):

- **If current-state survey:**
  - *"Should I include known issues / tech debt / recent incidents, or strictly describe what's there?"*
  - *"Is there a recent incident or runbook I should pull failure-mode information from?"*
- **If design-change request:**
  - *"What's the problem being solved? What's the proposed change? Are there alternatives I should compare?"*
  - *"Does a current-state survey already exist for the system being changed?"* (if yes → §4 Current State will link to it; if no → see linked-pair pattern below)
- **If dev design spec:**
  - *"Does an approved design-change request or other approval artifact exist for this work? If yes - what's the link / path?"* (if no, ask whether the user wants to switch to design-change-request mode first OR proceed with a `*(ASSUMED - approval not in source)*` note)
  - *"Does this work involve OS-shipping or driver-level concerns (OEM customization, KIT / Manufacturing OS, processor-specific binaries, Update OS)?"* (if yes - add those subsections back to §1.3 / §5; the default template trims them)
  - *"Is there persistent state involved (data files, database tables, blobs, queues with durable messages)?"* (if no - §3.4 may be skipped; if yes - §3.4 Persisted Data Format is non-negotiable)
  - *"Will this ship behind a feature flag / canary / ring rollout?"* (if no - §4.4 Feature Flighting may be marked N/A; if yes - must be filled)

## Procedure

### 1. Run intake

Run the intake bundle above. Wait for answers. Pre-fill where possible per the rules.

### 2. Pick the template

Pick ONE template based on the mode answer:

- **Current-state survey** → see `templates/current-state-survey.md` for the section list, header block, and worked example.
- **Design-change request** → see `templates/design-change-request.md` for the section list, header block, and worked example.
- **Dev design spec** → see `templates/dev-design-spec.md` for the section list, header block, and worked example.

### 3. Ground in the source

Use `grep` / `view` / `glob` / the `explore` agent to ground every claim about real systems. Do NOT invent:

- Component names
- File paths
- GUIDs / connection IDs / resource IDs
- Behaviors / failure modes
- Schema field names

Mark assumptions inline: *"(ASSUMED - not verified in source)"* in italics.

### 4. Draft the doc IN CHAT first

Render the full document in chat, regardless of intended destination. This is mandatory per the output-write ordering rule (`AGENTS.md`).

Use:

- **Tables** for variables / parameters / cases / failure-modes / file inventories. Easier to scan than prose.
- **ASCII flow diagrams** where a sequence has more than 3 stages.
- **Code-fenced JSON / YAML / etc.** for any schema or config example. Reference real `@parameters('X')` / config-key names verbatim from the source.

### 5. Wait for user approval

Do not write to any file before the user has reviewed the draft and approved (or after revisions, re-approved).

If they request revisions:

- Apply them.
- Re-render the affected sections in chat.
- Re-ask for approval.

### 6. Write to the chosen destination - only after approval

Per the destination intake answer:

- **Chat-only:** done. No file write.
- **Session workspace:** write to `<copilot-session-state>/<session-id>/files/<filename>.md` (resolve the actual path on the host - e.g. `C:\Users\<user>\.copilot\session-state\...` on Windows, `~/.copilot/session-state/...` on Unix-like).
- **Repo `docs/`:** confirm path with the user before writing.
- **Specific path:** write to that path.
- **Email / paste-ready:** keep in chat, optionally re-format for the destination (e.g. strip GitHub-specific markdown extensions for ADO, inline image links for email).

### 7. Comparison-against-baseline (early adoption)

If the user has a prior design-spec output from a previous workflow (a legacy hybrid current-state-plus-change spec, or any earlier doc on a similar subject), they may share its path during intake. For the first few real runs of this workflow, ask the user during intake whether such a baseline exists and, if so, compare the output structure to validate that the strict-split structure produces something at least as useful. Refine the section list / working principles based on observed gaps. Do **not** assume any specific baseline path - it is per-user and per-session.

## Linked-pair pattern (avoids forcing two full docs)

The three templates are strictly separated, but the downstream modes often need to ground in earlier ones:

- A **design-change request** often needs to reference a **current-state survey** of the system being changed.
- A **dev design spec** often needs to reference an approved **design-change request** AND, transitively, a **current-state survey** of the system it's being added to.

To avoid forcing the user to write multiple full docs when one would do:

- A design-change request's **§4 Current State** is intentionally short (1-2 paragraphs).
- A dev design spec's **References** section links to the approved design-change request (and transitively to any current-state survey) rather than duplicating their content.
- If a separate current-state survey exists, the design-change request's §4 links to it and stays brief.
- If no survey exists, §4 may include a *"Current State Summary - provisional"* section that's clearly marked.
- If the dev design spec has no approved design-change request to ground in, the agent must surface that during intake (per Conditional follow-ups above) and offer to switch modes OR proceed with an explicit `*(ASSUMED - approval not in source)*` note in the header block.

**Hybrid tripwires - extract to standalone survey if ANY of these appear in §4 Current State:**

- More than 2 paragraphs of prose.
- Any **table** (variable / parameter / failure-mode / file inventory / config / schema field).
- Any **diagram** (ASCII flow, sequence, component diagram).
- Any **code-fenced schema, config, or sample payload** longer than 5 lines.
- Any **subsection** (an `####` heading or deeper) - meaning the current state is being broken into structured sub-areas.
- A **failure-mode catalog** (more than 2 named failure modes with descriptions).
- An explicit **file / artifact inventory**.

Any one of these is the signal that the §4 content has outgrown a "summary" and the reader will benefit from a separate, navigable current-state survey. When a tripwire fires, recommend extracting the §4 content into a standalone current-state survey (run the current-state-survey mode of this playbook, save it, and replace §4 with a link + 1-paragraph synopsis) **before** approving the design-change request.

**Tripwire timing - when to apply the check:**

- **During drafting:** check after each §4 revision and before rendering the draft for user approval. Most extractions happen here.
- **After user approval but before file write:** if a tripwire is noticed at this stage (e.g. the user requested a §4 expansion that crosses a tripwire), STOP, surface the tripwire, and re-ask for approval after either extracting or recording the user's explicit override.
- **Default when a tripwire fires (during drafting OR after approval):** extract to a standalone current-state survey. Keeping the hybrid is NOT the default - a bare *"yes, looks good"* after the tripwire is surfaced means *"yes, extract per the default"*. Keeping the hybrid requires an **explicit** user sentence ("keep it in §4", "don't extract", "I want the table in the design-change doc") naming the override intent.
- **User-requested hybrid override:** if the user explicitly asks to keep a hybrid despite a fired tripwire (*"I want the table to stay in §4 - it's a small ad-hoc doc, no separate survey needed"*), allow it but mark the document with an explicit hybrid-exception note at the top: *"Note: This document is a deliberate hybrid - §4 contains current-state detail beyond the standard linked-pair pattern, by user request."* Record the override in session todos so resumed sessions can see the deliberate decision. **The override is scoped** to the specific §4 content and the specific tripwire(s) the user saw at approval time - record both in the override todo's `description`.
- **Override invalidation rule:** any **material §4 change after override** (additional tripwire fires that the user did NOT explicitly approve, content expansion that crosses a NEW tripwire, or wholesale §4 rewrite) requires re-surfacing the new tripwire(s) and a fresh `ask_user` confirmation. The original override does not blanket-cover later additions. Update the override todo on each re-confirmation; do not silently extend the prior override.
- **What counts as "material" for §4 change:**
  - **Non-material** (override stays in force, no re-confirmation): typo fixes, formatting tweaks, link-only fixes, citation cleanup, wording rephrases that do NOT change facts, scope, structure, or tripwire status.
  - **Material** (re-surface tripwires + re-confirm): any new or changed factual claim about the system; any new system / component / behavior described; any new failure mode added; scope expansion (new subsystem, new feature area pulled into §4); any structural change (new subsection, new diagram, new table, new code-fenced sample); any change that brings §4 closer to or across one of the tripwires above (e.g. growing from 1 paragraph to 2.5 paragraphs is borderline-material - re-check tripwires; growing from 2 paragraphs to a paragraph with a new failure-mode list is material).
  - **When in doubt:** treat as material and re-surface. The cost of one extra `ask_user` is much lower than silently expanding a hybrid past what the user actually approved.

This preserves strict template separation while letting most change requests stand alone.

## Working principles for the agent

- Never produce the doc without running intake first.
- When grounding in code, use `grep` / `view` / `explore` to verify claims before writing them.
- Prefer tables over prose for any structured list.
- Use ASCII diagrams for multi-stage flows.
- Code-fenced examples for any schema or config.
- Mark unverified claims with `*(ASSUMED - not verified in source)*`.
- Save the doc per the destination intake answer - but only after user approval.
- Cite source files / repo refs / ADO IDs by their real identifiers (verified, not invented).
