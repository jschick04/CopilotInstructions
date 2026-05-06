# Template: Design-change request

## How to use this template

This is a **reference skeleton** for the design-change-request mode of the design-spec playbook. The playbook (`design-spec.md`) drives intake; this file specifies the document structure.

A design-change request describes a proposed change. It is NOT a current-state survey — if §4 Current State outgrows the limits in `design-spec.md`'s **linked-pair pattern** (more than 2 paragraphs, OR any tripwire fires — table, diagram, schema longer than 5 lines, subsection heading, failure-mode catalog, file inventory), extract a standalone current-state survey and link to it from §4.

Replace every `<placeholder>` with verified information. Mark unverified claims as `*(ASSUMED — not verified in source)*`.

---

## Section list (in order)

### Header block

A key/value list at the top of the doc:

- **Subject of change:** `<name>`
- **Change type:** `<new system / modification / migration / retirement / refactor>`
- **Owning team:** `<team name>`
- **Status:** `<Draft / Pending review / Approved / Implemented>`
- **Linked work items:** `<ADO IDs, related design docs, PRs>`

### 1. Problem Statement

What's broken / missing / suboptimal today, with **measurable impact** and the concrete pain. 1–2 paragraphs.

Avoid vague pain — quantify where possible (latency P99, cost / month, on-call pages / week, customer escalations / quarter).

### 2. Proposed Change

High-level summary in 1 paragraph. Distinct from the detailed §5 below — this is the elevator pitch; §5 is the engineering detail.

### 3. Goals / Non-Goals

Bullet lists. Non-goals are explicit "not in this change" guardrails.

**Goals:**

- `<goal 1>`
- `<goal 2>`

**Non-Goals:**

- `<non-goal 1>` — out of scope, will be handled in `<other change / not at all>`
- `<non-goal 2>` — out of scope, `<reason>`

### 4. Current State

Short summary (1–2 paragraphs). Link out to a current-state survey if one exists; do NOT duplicate it here.

If no survey exists:

- May include a *"Current State Summary — provisional"* section, clearly marked.
- **Hybrid tripwires (extract to standalone survey if ANY appear here):** more than 2 paragraphs of prose; any table; any diagram; any code-fenced schema/config/payload longer than 5 lines; any subsection heading (`####` or deeper); a failure-mode catalog (more than 2 named failure modes); an explicit file/artifact inventory. See `design-spec.md` linked-pair pattern for the full list and the extraction procedure.

### 5. Proposed Design

The meat. Components added / modified / removed; sequence diagrams or flow descriptions; data model changes; new schemas / API shapes / configuration. Heavy table + ASCII diagram use where it clarifies.

Suggested sub-structure:

#### 5.1 Components added / modified / removed

| Action | Component | Notes |
| --- | --- | --- |
| Add | `<name>` | `<purpose>` |
| Modify | `<name>` | `<what changes>` |
| Remove | `<name>` | `<why removable>` |

#### 5.2 Flow diagram (after the change)

```
<ASCII diagram of the new flow>
```

#### 5.3 Data model / schema changes

```jsonc
// Before
{ "<field>": "<type>" }

// After
{ "<field>": "<type>", "<newField>": "<type>" }
```

#### 5.4 API / interface changes

| Endpoint / Method | Change | Compat |
| --- | --- | --- |
| `<name>` | `<add / change / remove>` | `<breaking / non-breaking>` |

#### 5.5 Configuration changes

Table of new / modified / removed parameters.

### 6. Alternatives Considered

At least one alternative, with reasons not chosen. *"Do nothing"* is sometimes a valid alternative to enumerate.

| Alternative | Pros | Cons | Decision |
| --- | --- | --- | --- |
| `<alt name>` | `<pros>` | `<cons>` | Not chosen — `<reason>` |
| Do nothing | Zero-cost | `<problem persists>` | Not chosen — `<problem outweighs>` |

### 7. Migration / Rollout Plan

Phased steps, feature flags, parallel-run strategy, rollback procedure.

| Phase | Action | Validation |
| --- | --- | --- |
| 1 | `<action>` | `<how validated>` |
| 2 | `<action>` | `<how validated>` |
| 3 | `<action>` | `<how validated>` |

**Rollback procedure:** `<concrete steps to revert if a phase fails>`

### 8. Risks & Mitigations

Table of risk → likelihood → impact → mitigation.

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| `<risk>` | `<low / med / high>` | `<low / med / high>` | `<plan>` |

### 9. Impact Assessment

Affected teams, services, downstream consumers, perf, cost, security, compliance.

| Dimension | Impact |
| --- | --- |
| Teams | `<list>` |
| Services | `<list>` |
| Downstream consumers | `<list>` |
| Performance | `<expected delta>` |
| Cost | `<expected delta>` |
| Security | `<changes>` |
| Compliance | `<changes>` |

### 10. Acceptance Criteria

Bullet list of "done means…" — testable conditions.

- `<testable criterion 1>`
- `<testable criterion 2>`
- `<testable criterion 3>`

### 11. Test Plan

How the change will be validated. Cover unit / integration / smoke / manual / regression checklist.

| Test type | Coverage | Owner |
| --- | --- | --- |
| Unit | `<what>` | `<role>` |
| Integration | `<what>` | `<role>` |
| Smoke (post-deploy) | `<what>` | `<role>` |
| Manual | `<what>` | `<role>` |

### 12. Operational Impact

Identity / auth changes, onboarding deltas, monitoring / alerting changes, runbook updates.

- **Identity / auth:** `<changes>`
- **Onboarding:** `<changes>`
- **Monitoring / alerting:** `<changes>`
- **Runbook updates required:** `<list>`

### 13. Open Questions / Decisions Needed

Outstanding items the reviewer must resolve before the change can proceed.

1. `<question>` — `<context / who decides>`
2. `<question>` — `<context / who decides>`

### 14. References

ADO items, related design docs, source files, external docs.

- `<ADO #>` — `<title>`
- `<related design doc>` — `<link>`
- `<source file>` — `<repo:path>`
- `<external doc>` — `<URL>`

---

## Notes for the agent

- **Strictly proposed-change.** This is what should be done, not what is. Current-state grounding belongs in §4 (short) or in a linked standalone current-state survey.
- **Ground every claim about the existing system** — use `grep` / `view` / `explore`. Mark unverified claims as `*(ASSUMED — not verified in source)*`.
- **Quantify the problem statement.** Vague pain rarely passes review. Numbers, dates, frequencies, costs.
- **Always include at least one alternative.** "Do nothing" counts. The point is to show the reviewer the decision was considered.
- **Acceptance criteria must be testable** — each one answers *"how would we know this is done?"*.
- **Migration / rollout plan must include a rollback procedure** — a phased rollout without a rollback plan is incomplete.
