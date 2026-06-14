---
name: ado-task-planning
description: Use when user wants to draft a NEW Azure DevOps work item or its content (task, story, feature, epic, bug). Produces two paired outputs - a markdown summary + an ADO-field-formatted block (Title / Description / Acceptance Criteria / Definition of Done / Tags). Does NOT modify existing ADO content; for factual questions about existing work items, answer directly without invoking this playbook.
triggers:
  - "draft an ADO work item for"
  - "plan out an ADO task for"
  - "write up an ADO bug for"
  - "create the deliverables for"
  - "draft acceptance criteria for"
  - "propose acceptance criteria for"
  - "ADO task for"
  - "ADO story for"
  - "ADO feature for"
  - "acceptance criteria for a new work item"
---

# Playbook: ADO task planning

## Purpose

Generate Azure DevOps work-item content at planning time - both a structured markdown summary (for chat / email / personal notes) and ADO-field-formatted text (paste-ready into the ADO task / story / bug / feature / epic). The agent runs intake first, drafts both outputs in chat, gets user approval, then optionally writes to a destination per intake.

Triggered when the user is asking to **draft a NEW work item or its content** - phrases like:

- *"I need to write an ADO task for…"*
- *"create the deliverables for…"*
- *"draft / propose / write acceptance criteria for…"* (note: purely factual questions about EXISTING acceptance criteria - e.g. *"what acceptance criteria does the parent feature use?"* / *"what's our team's definition of done?"* - are NOT strong; phrasings using *"should be"* are drafting requests and ARE strong)
- *"draft an ADO work item for…"*
- *"plan out an ADO task / story / feature for…"*
- *"write up an ADO bug for…"*

The semantic discriminator (artifact-requested vs exploratory-question, including the bare-*"review"*/*"audit"* and ambiguous-artifact-adjacent rules) is canonical per `AGENTS.md` *Trigger detection - strong vs weak*. The phrases above are illustrative - they help readers recognize the shape of an ADO drafting ask but are not exhaustive and do not override the discriminator.

These are **strong triggers**: agent immediately offers via `ask_user` (*"this looks like an ADO planning ask - want me to run the ADO task planning playbook?"*). Decline-then-no-retry rule applies.

**Not a strong trigger:** an exploratory question that doesn't ask for a draftable work item (*"what's our team's definition of done?"*, *"what acceptance criteria does the parent feature use?"*). Those are weak triggers - answer directly and optionally offer the playbook in a single non-blocking sentence.

## Hard gates

- Intake completed before drafting.
- Both outputs (markdown summary + ADO-field-formatted text) produced together - they are format-shifted versions of the same content.
- Acceptance criteria are testable - each answers *"how would we know this is done?"*.
- Deliverables are nouns (artifacts), not verbs (activities).
- No invented linked work-item IDs - only IDs the user provides.
- Draft rendered in chat first; user approves before any file write or paste-target write.

## Intake questions

Bundle independent questions in one `ask_user` prompt. Sequential follow-ups only when later questions depend on prior answers.

**First batch (always asked, bundled):**

1. **Process template** - Agile, Scrum, or CMMI? (Determines work-item type names and estimation field - see field tables below. Default Agile if not specified.)
2. **Work item type** - for Agile: Task / User Story / Bug / Feature / Epic. For Scrum: Task / Product Backlog Item / Bug / Feature / Epic. For CMMI: Task / Requirement / Bug / Feature / Epic.
3. **Title** - give me one, or want me to propose 3 options?
4. **Goal / outcome** - what does success look like in business / user terms?
5. **Audience for the description** - engineer picking it up cold / PM / leadership?
6. **Known constraints** - deadlines, dependencies, blocking work items, cross-team coordination?
7. **Definition of done** - what artifacts confirm completion (PR merged, doc published, dashboard updated, customer notified, etc.)? Note: DoD is NOT a standard ADO field; see the Definition of Done handling note below for how it's emitted.
8. **Acceptance criteria style** - prose bullets / Given-When-Then / checklist / follow what the parent feature uses?
9. **Estimation needed** - should I propose an estimate, or leave blank? (Field varies by template - Story Points for Agile, Effort for Scrum, Size for CMMI; on Tasks: Original Estimate + Remaining Work in hours. *Completed Work also exists on Tasks but is updated as work progresses, NOT proposed at planning time - not asked here.*)
10. **Linked work items** - parents, children, predecessors I should reference? (Provide IDs - I won't invent them.)
11. **Universal classification fields** - Iteration Path, Area Path, State, Assigned To. Provide values now or leave for you to set in ADO?
12. **Output destination** - chat-only / paste into the ADO web UI yourself / save as session artifact / commit to repo?

**Pre-fill from upfront input.** If the user opened with structured detail (e.g. *"ADO Story for the X migration, audience=engineer, points=5"*), pre-fill and ask only the unfilled questions.

**Re-confirm overloaded terms** ("audience", "owner", "destination") before using as pre-fill if they affect output structure.

**Conditional follow-ups** (asked after first batch, only if the answer wasn't pre-filled):

- **For Story / PBI / Requirement:** *"Priority (1-4, lower = higher)? Risk (1-3, Agile / CMMI only - skip if Scrum PBI)? Value Area (Business / Architectural)?"*.
- **For Bug:** *"Severity (1 - Critical / 2 - High / 3 - Medium / 4 - Low)? Priority (1-4)? Found In (build / version where the bug was discovered, if known)? Integrated In (build / version where the fix landed, if post-fix)? Environment / version / config that exhibits the bug?"* (drives Repro Steps + System Info + Severity + Priority + Found In + Integrated In).
- **For Task:** *"Activity (Development / Design / Documentation / Requirements / Deployment / Testing)?"* and *"Original / Remaining work in hours?"*.
- **For Feature:** *"Priority (1-4)? Value Area (Business / Architectural)? Target Date? Time Criticality (SAFe extensions only - skip if not enabled)?"*.
- **For Epic:** *"Value Area (Business / Architectural)? Start Date? Target Date?"*.

## Required fields per work-item type

These are the standard fields for the **Agile** process template (the most common). For Scrum and CMMI variants, swap in the per-template names noted in the *Process-template differences* section that follows.

### Universal fields (apply to every work-item type, every process template)

Every ADO work item - Task, Story / PBI / Requirement, Bug, Feature, Epic - has these required-or-near-required fields. The most common cause of a paste-ready ADO block failing on save is missing one of these. Always emit them:

- **Title** - one line.
- **State** - initial state varies by process template AND work-item type. **See the Initial state table in *Process-template differences* below as the single source of truth - never default to `New` blindly.** CMMI uses `Proposed` for every type; Agile / Scrum use `New` for stories/PBIs/Bugs/Features/Epics but `To Do` for Tasks. When in doubt, leave the field empty in Output 2 and ask the user.
- **Assigned To** - leave blank for unassigned, or use the user-provided email / display name. Do NOT invent.
- **Iteration Path** - sprint or release path (e.g. `MyProject\Sprint 24`). User-provided only.
- **Area Path** - team / component path (e.g. `MyProject\Backend\Auth`). User-provided only.
- **Tags** - comma-separated, agent-suggested, user-final-say.

### Task

- *(plus universal fields)*
- **Description**
- **Activity** - Development / Design / Documentation / Requirements / Deployment / Testing *(if known)*
- **Original Estimate** (hours) *(if estimating)*
- **Remaining Work** (hours) *(if estimating)*
- **Completed Work** (hours) *(updated as work progresses; NOT emitted in planning-time Output 2 - stays at `0` / blank in ADO until execution)*
- *(NOT included: Acceptance Criteria - not a standard field on Task in Agile/Scrum/CMMI; AC lives on the parent Story / PBI / Bug / Feature / Epic. If the user wants per-task acceptance, render it inside the Description.)*

### User Story (Agile) / Product Backlog Item (Scrum) / Requirement (CMMI)

- *(plus universal fields)*
- **Description** (in *"As a `<role>`, I want `<capability>` so that `<benefit>`"* format if the user prefers - Story / PBI only; Requirement uses problem-statement format)
- **Acceptance Criteria**
- **Estimation field** (template-specific):
  - Agile: **Story Points**
  - Scrum: **Effort**
  - CMMI: **Size**
- **Priority** *(1-4, lower = higher priority)*
- **Risk** *(1-3 - Agile / CMMI)*
- **Value Area** - Business / Architectural

### Bug

- *(plus universal fields)*
- **Repro Steps** (the canonical ADO field name; field reference `Microsoft.VSTS.TCM.ReproSteps`)
- **System Info** (separate ADO field; field reference `Microsoft.VSTS.TCM.SystemInfo`)
- **Severity** - 1 - Critical / 2 - High / 3 - Medium / 4 - Low
- **Priority** - 1-4
- **Acceptance Criteria** (often *"the bug no longer reproduces with steps from Repro Steps"*)
- **Found In** *(build / version where the bug was discovered)*
- **Integrated In** *(build / version where the fix landed - populated post-fix)*

### Feature

- *(plus universal fields)*
- **Description**
- **Acceptance Criteria**
- **Target Date** *(if known)*
- **Value Area** - Business / Architectural
- **Priority**
- **Time Criticality** *(if SAFe extensions are enabled)*

### Epic

- *(plus universal fields)*
- **Description**
- **Acceptance Criteria**
- **Start Date** / **Target Date** *(if known)*
- **Value Area**

### Process-template differences (Agile / Scrum / CMMI)

| Concept | Agile | Scrum | CMMI |
| --- | --- | --- | --- |
| User-facing story type | User Story | Product Backlog Item (PBI) | Requirement |
| Story estimation field | Story Points | Effort | Size |
| Bug workflow | Lives at story level | Lives at PBI level | Has its own dedicated workflow |
| CMMI extras | - | - | Triage, Blocked, Resolved Reason, Root Cause |

#### Initial state per work-item type per template (single source of truth)

| Work item type | Agile | Scrum | CMMI |
| --- | --- | --- | --- |
| Task | To Do | To Do | Proposed |
| User Story / PBI / Requirement | New | New | Proposed |
| Bug | New | New | Proposed |
| Feature | New | New | Proposed |
| Epic | New | New | Proposed |

The Universal-fields *State* bullet defers to this table - never emit `New` (or any other value) without cross-checking it.

When the user picks a non-Agile template during intake, swap in the template-specific names everywhere (work-item type, estimation field, initial state).

### Definition of Done - handling note

Definition of Done is NOT a standard ADO work-item field in any process template. Most teams handle DoD one of three ways:

1. **Team-wide DoD** - maintained outside ADO (wiki, README, team-norms doc) and not pasted per-item.
2. **Inline in Description** - appended as a `## Definition of Done` markdown subsection to the Description field.
3. **Inline in Acceptance Criteria** - bulleted at the end of the Acceptance Criteria field, clearly separated from story-specific AC.

During intake, ask which the team uses. The agent emits DoD per the chosen approach in Output 2 (see canonical mapping table below). Never emit DoD as a standalone `=== DEFINITION OF DONE ===` block claiming to be a paste-ready ADO field - there is no such field.

## Procedure

### 1. Run intake

Bundle the first-batch questions. Wait for answers. Pre-fill from upfront input where possible.

### 2. Draft Output 1 - structured markdown summary

This is for chat / email / personal notes. Section structure:

```markdown
# <Title>

**Type:** <Task / Story / Bug / Feature / Epic>
**Linked work items:** <parents / children / predecessors - only IDs the user gave>
**Tags:** <suggested tags>

## Goal / Outcome

<business / user framing - one paragraph>

## Description

<engineering framing - what work this represents>

## Deliverables

- <artifact 1 - noun, not verb>
- <artifact 2>
- <artifact 3>

## Acceptance Criteria

<style chosen during intake - prose bullets / G-W-T / checklist>

- <testable criterion 1>
- <testable criterion 2>

## Dependencies / Linked Items

- `<ADO #>` - `<title>` *(relationship: blocks / blocked by / parent / child / predecessor / successor / related)*
- *(if there is dependency rationale beyond the link itself, add it as a sub-bullet)*

## Risks / Open Questions

- <risk or question 1>
- <risk or question 2>

## Effort estimate

<story points / hours / "left blank per intake">
```

### 3. Draft Output 2 - ADO-field-formatted text

This is paste-ready into ADO. Output 2 is a **format shift** of Output 1 - the same canonical content, restructured into ADO field blocks. See the canonical mapping table immediately below for which markdown sections feed which ADO fields.

#### Canonical content model → ADO field mapping

The **Source** column makes explicit where each Output 2 field comes from. Some fields are sourced from Output 1 sections (true format-shifts), some from intake answers directly (universal classification, per-type required fields), and some from per-template defaults (Initial state). This is the complete map - no orphan Output 1 sections, no Output 2 fields without a stated source.

| ADO field block in Output 2 | Source | Notes |
| --- | --- | --- |
| `=== TITLE ===` | Output 1 `# <Title>` | One line. |
| `=== STATE ===` | Default - *Initial state per work-item type per template* table above | OR user-provided; never invent. Always emit. |
| `=== ASSIGNED TO ===` | Intake (universal classification question) | Blank if user did not provide. Always emit. |
| `=== ITERATION PATH ===` | Intake (universal classification question) | Blank if user did not provide. Always emit. |
| `=== AREA PATH ===` | Intake (universal classification question) | Blank if user did not provide. Always emit. |
| `=== TAGS ===` | Output 1 `**Tags:**` | Comma-separated. Always emit. |
| `=== DESCRIPTION ===` | Output 1 `## Goal / Outcome` + `## Description` + `## Deliverables` (as inline subsection) + `## Risks / Open Questions` (as inline subsection) + (per intake choice) `## Definition of Done` (as inline subsection) | Concatenate. ADO has no separate Deliverables / Risks / DoD field; render inline as markdown subsections. For Task, also append the `## Acceptance Criteria` content here (no AC field on Task). |
| `=== ACCEPTANCE CRITERIA ===` | Output 1 `## Acceptance Criteria` | Skip emitting this block entirely if the work-item type is Task. |
| `=== LINKED WORK ITEMS ===` | Output 1 `**Linked work items:**` header + `## Dependencies / Linked Items` body | Header gives the basic link list; body folds in any per-link relationship type and rationale. One block per linked item: `<relationship>: <ADO #> - <title> (<rationale if any>)`. |
| Estimation block - Story / PBI / Requirement: `=== STORY POINTS ===` (Agile) / `=== EFFORT ===` (Scrum) / `=== SIZE ===` (CMMI) | Output 1 `## Effort estimate` | Per-template field name. Skip if intake said leave blank. |
| Estimation block - Task: `=== ACTIVITY ===` + `=== ORIGINAL ESTIMATE ===` + `=== REMAINING WORK ===` | Output 1 `## Effort estimate` + intake (Activity) | Skip if intake said leave blank. `Completed Work` is updated as work progresses (post-planning) - it is NOT emitted in planning-time Output 2; it stays at `0` / blank in ADO until execution. |
| Bug-only: `=== REPRO STEPS ===` + `=== SYSTEM INFO ===` + `=== SEVERITY ===` + `=== PRIORITY ===` + `=== FOUND IN ===` + `=== INTEGRATED IN ===` | Intake (Bug-conditional follow-ups) | All six blocks always emitted for Bug. Repro Steps + System Info + Severity + Priority filled from intake; Found In emitted blank if user didn't provide a build/version (lets the user fill it in ADO); Integrated In emitted blank pre-fix (filled post-fix as a lifecycle update). Bug type only. |
| Story / PBI / Requirement: `=== PRIORITY ===` + `=== RISK ===` (Story in Agile, Requirement in CMMI; NOT on Scrum PBI) + `=== VALUE AREA ===` | Intake (per-type required-field follow-ups) | Risk on Bug is intentionally NOT emitted - Severity covers risk-prioritization on Bugs in standard ADO usage. Emit only if intake provided a value or `<unset>`. |
| Feature: `=== PRIORITY ===` + `=== VALUE AREA ===` + `=== TARGET DATE ===` + `=== TIME CRITICALITY ===` (SAFe extensions only) | Intake (Feature per-type required-field + conditional follow-ups) | Emit only if intake provided. Feature requires Priority and Value Area per the Feature field list above. |
| Epic: `=== VALUE AREA ===` + `=== START DATE ===` + `=== TARGET DATE ===` | Intake (Epic per-type required-field + conditional follow-ups) | Emit only if intake provided. Epic does NOT have a Priority field per the Epic field list above. |
| `=== DEFINITION OF DONE ===` | **NEVER EMIT THIS BLOCK** | DoD is not a standard ADO field. Per intake, render it inline in `=== DESCRIPTION ===` or appended to `=== ACCEPTANCE CRITERIA ===`, OR omit entirely (team-wide DoD). |

**The same fact appears in exactly one ADO field block.** If a fact is in two markdown sections (e.g. acceptance criteria mentioned in both `## Acceptance Criteria` and `## Description`), the Description block in Output 2 omits the AC sub-bullet - Output 2's Description references it instead (*"see Acceptance Criteria field"*). Exception: Task work items have no AC field, so AC content is appended to the Description for that one type.

**Intake follow-up coverage check.** Before drafting Output 2, verify intake gathered values (or `<unset>`) for every Output 2 source listed above as "Intake". If a required-by-type field is missing, ask via `ask_user` - do not invent.

#### Block structure

```
=== TITLE ===
<one line>

=== STATE ===
<initial state per process template, or user-provided>

=== ASSIGNED TO ===
<email or display name; blank if unassigned>

=== ITERATION PATH ===
<MyProject\Sprint NN; blank if user did not provide>

=== AREA PATH ===
<MyProject\Component\SubComponent; blank if user did not provide>

=== DESCRIPTION ===
<rich-text-friendly markdown - ADO renders most basic markdown
in the Description field; avoid GitHub-specific extensions like
GitHub-flavored task lists, callout blocks, or :emoji: shortcodes>

## Deliverables

- <artifact 1>
- <artifact 2>

## Risks / Open Questions

- <risk 1>

## Definition of Done   <!-- only if intake says "inline in Description" -->

- <DoD bullet 1>

=== ACCEPTANCE CRITERIA ===
<bullet list or G-W-T blocks per intake choice - SKIP this block for Task>

=== TAGS ===
<comma-separated suggestions based on the work content>

=== LINKED WORK ITEMS ===
Parent: <ADO #>
Predecessor: <ADO #>
```

For **Bug** type, also include:

```
=== REPRO STEPS ===
<numbered list, exact actions; canonical ADO field: Microsoft.VSTS.TCM.ReproSteps>

=== SYSTEM INFO ===
<environment, version, config - anything affecting reproducibility;
canonical ADO field: Microsoft.VSTS.TCM.SystemInfo>

=== SEVERITY ===
<1 - Critical | 2 - High | 3 - Medium | 4 - Low>

=== PRIORITY ===
<1 | 2 | 3 | 4 - lower number = higher priority>

=== FOUND IN ===
<build / version where the bug was discovered; blank if not known>

=== INTEGRATED IN ===
<build / version where the fix landed; blank if pre-fix>
```

For **User Story / PBI / Requirement**, also include the template-specific estimation block if intake provided an estimate (Feature and Epic do NOT have story-points-style estimation fields in standard ADO - omit this block for those types):

```
=== STORY POINTS ===   <!-- Agile -->
<number>

=== EFFORT ===         <!-- Scrum -->
<number>

=== SIZE ===           <!-- CMMI -->
<number>
```

For **Task** with hour estimates:

```
=== ACTIVITY ===
<Development | Design | Documentation | Requirements | Deployment | Testing>

=== ORIGINAL ESTIMATE ===
<hours>

=== REMAINING WORK ===
<hours>
```

### 4. Wait for user approval

Render BOTH outputs in chat. Wait for explicit approval. Apply revisions if requested and re-render.

### 5. Write to chosen destination - only after approval

Per the destination intake answer:

- **Chat-only:** done. No file write.
- **Paste into ADO web UI:** done. User pastes Output 2 themselves.
- **Session artifact:** write to `<copilot-session-state>/<session-id>/files/<filename>.md` (resolve the actual path on the host - e.g. `C:\Users\<user>\.copilot\session-state\...` on Windows, `~/.copilot/session-state/...` on Unix-like).
- **Repo:** confirm path with the user before writing.

### 6. Record state

Record in canonical session todos (per `AGENTS.md` *Phase-state tracking convention*):

- Work item type drafted.
- Title.
- Whether the user pasted into ADO themselves or the agent wrote to a destination.
- Linked work items referenced (so a follow-up session can chain them).

## Working principles for the agent

- **The same content must appear in both outputs.** Output 2 is just the format-shifted version of Output 1, per the canonical mapping table above.
- **Acceptance criteria must be testable** - each one answers *"how would we know this is done?"*.
- **Deliverables are nouns (artifacts), not verbs (activities).** *"Updated runbook"* not *"update the runbook"*. *"PR merged into main"* not *"merge the PR"*.
- **Definition of Done is NOT a standard ADO field.** Per intake, emit it inline in Description, inline at the end of Acceptance Criteria, or omit entirely (team-wide DoD). Never as a standalone `=== DEFINITION OF DONE ===` block claiming to be a paste-ready field.
- **Acceptance Criteria is NOT a standard field on Task.** For Task, render AC inside the Description instead.
- **Use the canonical ADO field name `Repro Steps`** (not "Steps to Reproduce") for Bug - that is the actual field name in the Agile / Scrum / CMMI process templates.
- **Universal fields always emitted.** State, Assigned To, Iteration Path, Area Path. Leave value blank if user didn't provide; never invent paths or assignees.
- **Never invent linked work item IDs.** Only use IDs the user provides. If the user mentions a parent feature without an ID, ask for the ID before referencing it.
- **Process template determines work-item type names and estimation field.** Agile uses User Story / Story Points; Scrum uses Product Backlog Item / Effort; CMMI uses Requirement / Size. If unspecified, default Agile and surface the assumption.
- **Keep the description audience-appropriate.** Engineer-cold-pickup descriptions need more context (links to source, related ADO items, definitions of unfamiliar terms) than PM / leadership descriptions.
- **Suggest tags based on the work content** - area path, technology, related epic, etc. - but the user gets final say.
