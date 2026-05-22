---
name: github-to-ado-replication
description: >-
  Use when user wants to replicate GitHub issues into Azure DevOps work items using the
  OS process template (Scenario → Deliverable / Bug / Task hierarchy). Reads open issues
  from a GitHub repo, maps them to ADO work item types, applies OS-template field
  conventions, and creates via REST API — all parented to a user-specified Scenario.
  Includes idempotency checks, parent-field inheritance, time estimation, and
  dry-run-first workflow.
triggers:
  - "replicate GitHub issues to ADO"
  - "sync GitHub issues to ADO"
  - "create ADO items from GitHub issues"
  - "import GitHub issues into ADO"
  - "replicate issues to deliverables"
  - "mirror GitHub issues in ADO"
  - "create deliverables from GitHub issues"
  - "create bugs from GitHub issues"
---

# Playbook: GitHub → ADO Replication (OS Process Template)

## Purpose

Batch-replicate open GitHub issues into Azure DevOps work items in the user's ADO
project, parented to a user-specified Scenario. Each GitHub issue becomes a **Deliverable**
(enhancement) or **Bug** (defect) with the OS-template field conventions, HTML-formatted
descriptions, time estimates, and a parent link.

This is a **batch execution playbook** — it reads, transforms, creates, and verifies.
For interactive single-item drafting, use `ado-task-planning.md` instead.

## Hard gates

- Parent Scenario ID provided and validated (exists, correct type, fields readable).
- Idempotency check before every create — no duplicate ADO items for the same GitHub issue.
- Dry-run presented and approved before any API writes.
- Every created item has all required fields set (no partial items).
- Time estimates set on every created item.
- GitHub issue link preserved in every ADO item description.

---

## Intake

Bundle in one `ask_user` prompt:

1. **GitHub repo** — `owner/repo`.
2. **Issue filter** — open only (default), or include closed? Label filter?
3. **Parent Scenario ID** — ADO work item ID to parent all new items under.
4. **Assignee** — who to assign the new items to (default: inherit from parent Scenario).
5. **Time estimates** — should the agent propose estimates, or does the user want to set them?

---

## Procedure

### Step 0 — Authenticate

Acquire an ADO bearer token:

```powershell
$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
```

If `az account get-access-token` fails, run `az login` first (interactive browser flow).

### Step 1 — Fetch and validate parent Scenario

**Read the parent Scenario and extract inheritable fields.** ADO does NOT auto-inherit
fields from parent to child — the agent must explicitly read and copy them.

```
GET {org}/{project}/_apis/wit/workitems/{parentId}?api-version=7.1
```

Extract and store these fields from the parent (the **inheritance table**):

| Child field to set          | Read from parent field           | Required |
|-----------------------------|----------------------------------|----------|
| `System.AreaPath`           | `System.AreaPath`                | Yes      |
| `System.IterationPath`      | `System.IterationPath`           | Yes      |
| `System.AssignedTo`         | `System.AssignedTo`              | Yes (unless intake overrides) |
| `Microsoft.VSTS.Common.Release` | `Microsoft.VSTS.Common.Release` | Yes  |
| `OSG.ProductFamily`         | `OSG.ProductFamily`              | Yes      |
| `OSG.Product`               | `OSG.Product`                    | Yes      |
| `System.Tags`               | `System.Tags`                    | Yes (child gets parent's tags) |

**Abort if** the parent is not of type `Scenario`, or any required field is empty.

### Step 2 — Fetch GitHub issues

```powershell
gh issue list --repo {owner/repo} --state open --json number,title,body,labels --limit 100
```

### Step 3 — Map GitHub labels → ADO work item types

| Condition                     | ADO Type     |
|-------------------------------|-------------|
| `bug` label only              | Bug          |
| `enhancement` label only      | Deliverable  |
| Both `bug` and `enhancement`  | Ask user     |
| Neither label                 | Ask user     |

Preserve unmapped labels as ADO tags (appended to the parent's tag set).

### Step 4 — Idempotency check

Before creating, search ADO for existing items that match each GitHub issue.
Use a WIQL query scoped to the parent's area path:

```
SELECT [System.Id] FROM workitems
WHERE [System.AreaPath] UNDER '{areaPath}'
  AND [System.Title] = '{exact title}'
```

If a match exists, **skip** that issue and report it. Do not create duplicates.

### Step 5 — Dry run (mandatory)

Present a table to the user showing what will be created:

```
| GitHub # | ADO Type    | Title                          | Est (days) | Status  |
|----------|-------------|--------------------------------|------------|---------|
| #540     | Deliverable | Re-evaluate Blazor Component…  | 3          | CREATE  |
| #526     | Bug         | Banner: chevron nav not work…  | 1          | CREATE  |
| #539     | Deliverable | (already exists as ADO #12345) | —          | SKIP    |
```

Wait for explicit user approval before proceeding. The user may adjust estimates,
change types, or exclude specific issues.

### Step 6 — Create work items

Process one issue at a time. Record each created ADO ID. On failure, stop and report
the created/skipped/failed breakdown.

#### API shape

```
POST {org}/{project}/_apis/wit/workitems/$Deliverable?api-version=7.1
Content-Type: application/json-patch+json
Authorization: Bearer {token}
```

The request body is a JSON Patch array. See the field tables below for the complete
field set per work item type.

#### Parent link (on every item)

```json
{
  "op": "add",
  "path": "/relations/-",
  "value": {
    "rel": "System.LinkTypes.Hierarchy-Reverse",
    "url": "{org}/_apis/wit/workitems/{parentId}"
  }
}
```

`System.LinkTypes.Hierarchy-Reverse` means "this item's parent is {parentId}."

### Step 7 — Verify

After all creates, query the parent's children to confirm the count and titles match.

### Step 8 — Report

Show a final summary table with ADO IDs, links, and any issues that were skipped or failed.

---

## Field conventions — OS process template

### Common fields (all work item types)

| Field                                    | Value / Source                | Notes |
|------------------------------------------|------------------------------|-------|
| `System.AreaPath`                        | Copy from parent Scenario    | Never hardcode |
| `System.IterationPath`                   | Copy from parent Scenario    | Never hardcode |
| `System.AssignedTo`                      | Copy from parent (or intake) | UPN format, e.g. `alias@microsoft.com` |
| `System.Tags`                            | Copy parent tags + append any unmapped GitHub labels | Semicolon-separated |
| `Microsoft.VSTS.Common.Release`          | Copy from parent Scenario    | Current release train |
| `OSG.ProductFamily`                      | Copy from parent Scenario    | Typically `Windows` |
| `OSG.Product`                            | Copy from parent Scenario    | `Internal` or `OS` |
| `OSG.Partner.PartnerProgram`             | Copy from parent Scenario    | Read from parent or area-path siblings |

### Time estimation fields (required on every item)

| Field                                       | Unit | Notes |
|---------------------------------------------|------|-------|
| `Microsoft.VSTS.Scheduling.OriginalEstimate` | Days | ⚠️ Unit is **days** in this OS template, not hours |
| `OSG.RemainingDays`                         | Days | Set to same value as OriginalEstimate at creation |
| `OSG.RemainingDevDays`                      | Days | Set to same value as OriginalEstimate at creation |

#### Estimation benchmarks

| Scope                          | Typical estimate | Examples |
|--------------------------------|-----------------|----------|
| Learning deliverable           | 0.5d            | Training, skill adoption, tool setup |
| SFI / compliance bug           | 0.5d            | Storage, networking, security config |
| SFI / compliance task          | 1–2d            | CodeQL, SDL assessment, Liquid onboarding |
| Small code bug fix             | 0.5d            | Single-file logic fix, wiring existing branch |
| Medium code bug fix            | 1d              | Multi-file fix, two related issues in one component |
| Evaluation / research          | 2d              | Architecture evaluation, benchmark + decision doc |
| Prototype + documentation      | 3d              | Research + prototype + pattern documentation |

If no estimate is available, do NOT create the item — ask the user first.

### Deliverable-specific fields

| Field                                    | Value          |
|------------------------------------------|----------------|
| `System.State`                           | `Proposed`     |
| `System.Reason`                          | `Not Committed`|
| `OSG.FuncSpecStatus`                     | `Placeholder`  |
| `OSG.DevDesignStatus`                    | `Placeholder`  |
| `Custom.CommitmentStatus`                | `New`          |
| `OSG.Tenets.EnforcementStatus`           | `Not Assessed` |
| `OSG.Tenets.ComplianceAssessmentState`   | `Not Started`  |
| Content field                            | `System.Description` (HTML) |

### Bug-specific fields

| Field                                    | Value              |
|------------------------------------------|--------------------|
| `System.State`                           | `Active`           |
| `System.Reason`                          | `New`              |
| `Microsoft.VSTS.CMMI.TaskType`           | `Bug`              |
| `OSG.IssueType`                          | `Code Defect`      |
| `Microsoft.VSTS.Common.Triage`           | `Triage Needed`    |
| `OSG.RI.FastTrack`                       | `No`               |
| `OSG.HotFix`                             | `No`               |
| `OSG.Partner.PartnerBlocked`             | `No`               |
| `Custom.BulletinClassEvaluation`         | `Evaluation Needed`|
| Content field                            | `Microsoft.VSTS.TCM.ReproSteps` (HTML) |

**Bugs use `Microsoft.VSTS.TCM.ReproSteps`** — NOT `System.Description`.

### Fields NOT set (auto-populated)

- `OSG.Order` — auto-assigned
- `OSG.Partner.AssignedBack` — auto-populated from AssignedTo
- `OSG.CreatedOnBehalfOf` — auto-populated
- `OSG.OriginalID` — auto-populated
- `WEF_*` Kanban columns — auto-populated from board state
- `OSG.Justification` — template text auto-populated on bugs

---

## Content transformation: GitHub Markdown → ADO HTML

### Deliverable description template

The `System.Description` field uses HTML with this section structure:

```html
<h2>GitHub Issue</h2>
<p><a href="https://github.com/{owner}/{repo}/issues/{number}">#{number}</a></p>

<h2>Outcome</h2>
<p>{Synthesize the issue body into a clear outcome statement}</p>

<h2>Scope</h2>
<ul>
<li>{Scope item derived from the issue body}</li>
<li>{Scope item 2}</li>
</ul>

<h2>Done when</h2>
<ul>
<li>{Testable acceptance criterion derived from the issue}</li>
<li>{Criterion 2}</li>
</ul>
```

### Bug repro steps template

The `Microsoft.VSTS.TCM.ReproSteps` field uses HTML with this section structure:

```html
<h2>GitHub Issue</h2>
<p><a href="https://github.com/{owner}/{repo}/issues/{number}">#{number}</a></p>

<h2>Summary</h2>
<p>{Brief problem description}</p>

<h2>Repro Steps</h2>
<ol>
<li>{Step 1}</li>
<li>{Step 2}</li>
</ol>

<h2>Expected</h2>
<p>{Expected behavior}</p>

<h2>Actual</h2>
<p>{Actual behavior}</p>

<h2>Root Cause Analysis</h2>
<p>{Technical analysis if available from the issue body; omit section if none}</p>

<h2>Files</h2>
<ul>
<li><code>{file path referenced in the issue}</code></li>
</ul>
```

### Markdown → HTML conversion rules

| GitHub Markdown            | ADO HTML                          |
|----------------------------|-----------------------------------|
| `# Heading`                | `<h2>Heading</h2>` (flatten to h2)|
| `- bullet`                 | `<ul><li>bullet</li></ul>`        |
| `1. item`                  | `<ol><li>item</li></ol>`          |
| `` `code` ``               | `<code>code</code>`               |
| `**bold**`                 | `<b>bold</b>`                     |
| `- [ ] task`               | `<li>task</li>` (strip checkbox)  |
| `![img](url)`              | Omit or `<p>(image: url)</p>`     |
| `@mention`                 | Plain text `@mention`             |
| `#123` issue ref           | `<a href="...">link text</a>`     |
| Empty body                 | Minimal placeholder description   |

**Always preserve the GitHub issue URL** as the first section in the ADO content.

---

## Partial failure recovery

- Process issues one at a time, sequentially.
- After each successful create, record the ADO ID in session state (SQL todos table or
  session artifact).
- On API failure: stop, report the error, show the created/skipped/failed breakdown.
- On rerun: the idempotency check (Step 4) prevents duplicates for already-created items.

---

## Working principles

- **Dry run first, always.** Never batch-create without showing the plan and getting approval.
- **One source of truth per fact.** The parent Scenario is the authority for area, iteration,
  release, product, and product family. Read and copy — never hardcode these values.
- **Estimates are in days, not hours.** The OS process template uses days for
  `OriginalEstimate`, `RemainingDays`, and `RemainingDevDays`. An estimate of `0.5` means
  half a day, not half an hour.
- **Bugs use ReproSteps, not Description.** The content field for bugs is
  `Microsoft.VSTS.TCM.ReproSteps`. Setting `System.Description` on a bug may appear to
  work but won't render in the ADO Bug form's primary content area.
- **Deliverables start Proposed; Bugs start Active.** Different initial states per type.
- **No invented IDs.** Only reference work item IDs the user provides or that the agent
  has verified exist via API.
- **Preserve the GitHub link.** Every ADO item must link back to its source GitHub issue
  in the description/repro-steps HTML.
