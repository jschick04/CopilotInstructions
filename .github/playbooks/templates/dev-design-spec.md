# Template: Dev design spec

## How to use this template

This is a **reference skeleton** for the dev-design-spec mode of the design-spec playbook. The playbook (`design-spec.md`) drives intake; this file specifies the document structure.

A dev design spec describes **how an approved feature will be built, deployed, observed, and tested**. It is NOT a current-state survey (that's `current-state-survey.md` - describes what exists today) and NOT a design-change request (that's `design-change-request.md` - proposes a change and justifies it). The dev design spec assumes the change has already been approved at the design-change level and answers *"how do we ship it?"*.

When to use which template:

| You're answering... | Template |
| --- | --- |
| *"What does the system look like today?"* | `current-state-survey.md` |
| *"What should change and why?"* | `design-change-request.md` |
| *"How will we build, deploy, observe, and test the approved change?"* | `dev-design-spec.md` (this file) |

Replace every `<placeholder>` with verified information. Mark unverified claims as `*(ASSUMED - not verified in source)*`.

This template was modeled on a Microsoft-internal Dev Design Spec format and trimmed for general cloud / service / library work. Sections that were OS-shipping-specific (OEM customization, KIT / Manufacturing OS, processor-specific binary concerns, Update OS) were dropped or generalized. If your work IS OS-shipping or driver-level, ask the agent to add those subsections back during intake.

---

## Section list (in order)

### Header block

A key/value list at the top of the doc:

- **Subject:** `<feature / deliverable name>` *(plus work item ID if applicable)*
- **Authors:** `<name(s) of key contributors>`
- **Spec Status:** `<Draft / In Review / Accepted>`
- **Owning team:** `<team name>`
- **Document Goal:** *(static line)* This document describes how this deliverable will be implemented, deployed, observed, and tested.
- **Linked work items:** `<ADO IDs, related design-change requests, related current-state surveys, related PRs>`

### 1. Deliverable Description

#### 1.1 Summary

One paragraph: what's being built and what business / user outcome it delivers. Example: *"Add voice-driven correction and navigation to the X feature."*

#### 1.2 Architecture Decisions

Key architectural decisions and the rationale for each. Cover at least:

- **Online services used / introduced** - new external dependencies, SaaS calls, third-party APIs.
- **Significant performance characteristics** - new hot paths, expected throughput, latency budgets, asymptotic complexity choices.
- **Compatibility** - backward compatibility with existing clients / data / configs / contracts.
- **Security impact** - new attack surface, new ports / endpoints, new auth boundaries, new secret-handling, PII handling.
- **Convergence / consolidation** - does this build on shared infrastructure, replace duplicated code paths, or fork?
- **Observability decisions** - what new telemetry / logs / traces are required to operate this safely (detailed in §4).

| Decision | Rationale | Alternatives considered |
| --- | --- | --- |
| `<decision>` | `<why>` | `<alts>` |

#### 1.3 Build & Deployment

How the deliverable is built, packaged, and shipped. Cover:

- **Build artifacts** - binaries, container images, NuGet / npm / PyPI packages, Helm charts, Bicep / Terraform modules, etc.
- **Build system / CI pipeline** - which pipeline produces the artifact, what triggers it, what gates it.
- **Layering / dependency concerns** - what other components must build / version-bump first.
- **Differentiation / SKU / tier** - does this ship to all environments / tiers / customers, or a subset?
- **Processor / runtime targets** - `x64` / `arm64` / specific .NET / Node / Python versions, OS targets if applicable.

#### 1.4 Feature Dependencies (bidirectional)

##### Dependencies this design has on other features

Per-dependency table - repeat the row for each:

| Dependency | Owning team | Contacts (PM / Dev / Test) | Mitigation / Fallback if dependency slips |
| --- | --- | --- | --- |
| `<work item ID - feature title>` | `<team>` | `<names>` | `<plan>` |

##### Features that depend on this design

Per-dependent table - repeat the row for each:

| Dependent feature | Owning team | Description of what they need | Coordination plan |
| --- | --- | --- | --- |
| `<work item ID - feature title>` | `<team>` | `<what they consume>` | `<who tracks alignment>` |

### 2. Architectural Overview

#### 2.1 Diagram

ASCII diagram of the component / sequence / data-flow architecture. Use real component names from the source - no invented names.

```
<ASCII diagram>
```

#### 2.2 Description

Prose walk-through of the diagram. Explain each component, the boundaries between them, and the request / event flow.

### 3. Interfaces and Interactions

#### 3.1 Public API Added / Changed

Public-facing API (callable by other teams / customers / downstream services). For each:

| Endpoint / method / operation | Change | Compat | Notes |
| --- | --- | --- | --- |
| `<name>` | `<add / modify / remove>` | `<breaking / non-breaking>` | `<details>` |

#### 3.2 Internal API Added / Changed

Same shape as §3.1, scoped to interfaces internal to the team / service.

#### 3.3 Format and Protocol Added / Changed

New or changed wire formats, message schemas, event-grid event shapes, queue payload formats, gRPC / OpenAPI definitions.

```jsonc
// Example new payload shape
{
  "<field>": "<type>",
  "<field>": "<type>"
}
```

#### 3.4 Persisted Data Format

Discuss for any data that survives a process restart. Cover all of:

- **Data format** - JSON / Protobuf / Avro / SQL columns / blob layout.
- **Storage** - table / container / database / file path.
- **Versioning plan** - how schema evolves; forward / backward compat strategy.
- **Roaming / cross-region strategy** - replication, eventual consistency, conflict resolution.
- **Security / PII** - what's sensitive, how it's protected at rest, key rotation plan.
- **Migration strategy** - how existing data moves to the new shape.
- **Backup / restore strategy** - backup cadence, retention, restore procedure.
- **Upgrade behavior from previous** - what happens to data created by the prior version.

#### 3.5 Breaking Changes

Any breaking change in any of §3.1-§3.4, plus what's done to guarantee the upgrade experience (apps still work, settings preserved, etc.).

| Breaking change | Affected consumers | Mitigation | Communication plan |
| --- | --- | --- | --- |
| `<change>` | `<list>` | `<what we do>` | `<who we tell when>` |

#### 3.6 Tools / Consumer Impact

Effect on developer tools, CLIs, dashboards, SDKs, helper scripts, internal portals.

| Tool / consumer | Impact | Action required |
| --- | --- | --- |
| `<name>` | `<what changes>` | `<update needed?>` |

### 4. Telemetry, Supportability, and Flighting

#### 4.1 Telemetry

Metrics, events, KPIs the change emits. Think end-to-end scenario coverage, not just per-component counters.

| Signal | Type (metric / event / trace) | Purpose | Owning dashboard / alert |
| --- | --- | --- | --- |
| `<name>` | `<type>` | `<what question it answers>` | `<where to look>` |

#### 4.2 Logging

Structured logs added / changed. Cover correlation IDs, log levels, sensitive-field redaction.

| Log location | Log level | Fields | Notes |
| --- | --- | --- | --- |
| `<component>` | `<info / warn / error>` | `<field list>` | `<correlation ID, redaction>` |

#### 4.3 Debugging Hooks

Trace correlations, debugger attach points, debug-only endpoints, dump / diagnostic capture, repro-time instrumentation.

#### 4.4 Feature Flighting

How the change is rolled out behind feature flags / rings / canaries. Cover:

- **Flag name** and owning system (e.g. ConfigCat, LaunchDarkly, internal flighting service).
- **Default state** in each environment / ring.
- **Rollout schedule** (per-ring percentages, time per ring, gates between rings).
- **Kill-switch behavior** if the flag is force-flipped off mid-rollout.

### 5. Deployment and Data Migration

#### 5.1 Provisioning / Installation

How the deliverable is provisioned in each environment (dev, staging, prod). Infra-as-code references (Bicep / Terraform / ARM / Helm), required identities / managed identities / role assignments, required networking (VNet, private endpoints, firewall rules), required quotas.

#### 5.2 Migration and Upgrade

In-place upgrade path from the prior version. Cover schema migrations, side-by-side run windows, dual-write windows, cutover steps.

#### 5.3 Servicing and Patching Cadence

Ongoing operations after launch. Patch cadence, dependency-update strategy, certificate / secret rotation cadence.

#### 5.4 Rollout Strategy

Phased rollout per environment / ring. Sequence of validations between phases, gates, owner per gate.

| Phase | Action | Validation | Gate-keeper |
| --- | --- | --- | --- |
| 1 | `<action>` | `<how validated>` | `<role>` |

#### 5.5 Rollback / Restorability

Rollback procedure if a phase fails - concrete steps, data restoration plan, max acceptable rollback window.

### 6. Functional and Unit Testing

#### 6.1 Test Approach

Overall approach to functional testing. What WILL be automated, what WILL NOT, why. Call out coverage gaps and mitigations (e.g. functionality validated only in scenario / chaos tests). Consider open-source test cases that apply.

#### 6.2 Test Cases

Functional test cases that must complete and pass 100% before code-complete. Numbered list.

| # | Scenario | Expected outcome | Owner |
| --- | --- | --- | --- |
| 1 | `<scenario>` | `<outcome>` | `<role>` |

#### 6.3 Automated Test Cases

New automated tests - unit, integration, contract. Existing tests being ported / extended.

| Test | Type (unit / integration / contract / e2e) | What it covers |
| --- | --- | --- |
| `<name>` | `<type>` | `<coverage>` |

#### 6.4 Manual Test Cases

Should be empty in most cases. Only list manual tests when automation is genuinely impractical (visual UI, real-hardware, real-customer-data scenarios). Justify each one.

### 7. Gating Criteria

The subset of §6 that's added to integration gates / pre-merge / pre-release validation.

#### 7.1 Test Design

Which §6 tests gate which milestone (PR merge, RI / integration, release).

#### 7.2 Technology Decisions

Test framework / harness / fixtures used. Alternatives considered. Rationale.

#### 7.3 Test Architecture

High-level architecture of the test harness. Test hooks, designed-for-testability seams.

#### 7.4 Test Detailed Design

Artifacts used for the manual and automated test cases - fixture files, mock services, recorded responses.

### 8. Open Issues

Outstanding questions / undecided design points / areas the spec deliberately leaves open for follow-up.

| # | Issue | Owner | Decision needed by |
| --- | --- | --- | --- |
| 1 | `<question>` | `<role>` | `<milestone / date - be careful with dates per AGENTS.md>` |

### 9. Cut Deliverables and Behavior

What was originally planned for this feature but was descoped, deferred, or removed during design. Helps reviewers understand "why isn't X in here?" and helps future work identify candidates for follow-on specs.

| Originally planned | Why cut | Tracking item (if reopened) |
| --- | --- | --- |
| `<deliverable>` | `<reason - out of scope / cost / risk / dependency slipped>` | `<work item ID or "not tracked">` |

### 10. References

ADO items, related design-change requests, related current-state surveys, source files, external docs, runbooks.

- `<ADO #>` - `<title>`
- `<design-change request>` - `<link>`
- `<current-state survey>` - `<link>`
- `<source file>` - `<repo:path>`
- `<external doc>` - `<URL>`
- `<runbook>` - `<link>`

---

## Notes for the agent

- **Strictly post-decision.** This template assumes the change has been approved (a design-change request exists or the feature is otherwise greenlit). Do NOT use this template to debate whether the feature should be built - that belongs in `design-change-request.md`.
- **Bidirectional dependencies are mandatory.** §1.4 has TWO subsections - what this depends on AND what depends on this. Both halves matter for coordination; do not collapse to one.
- **§3.4 Persisted Data Format is non-negotiable when there's any persistent state.** Skip only if nothing survives a restart. When in doubt, fill it in - reviewers consistently catch missing data-format / migration / backup answers.
- **§4 Telemetry must include end-to-end scenario coverage**, not just per-component counters. The right question is *"can on-call diagnose a customer-reported failure end-to-end?"*, not *"did we increment a counter?"*.
- **§5.5 Rollback is non-negotiable.** A phased rollout without a rollback plan is incomplete.
- **§9 Cut Deliverables is intentionally about what's NOT here.** Don't skip it - listing what was descoped is part of the contract with reviewers.
- **Mark every system claim as verified or assumed.** Use `grep` / `view` / `explore` to verify; mark unverified claims `*(ASSUMED - not verified in source)*` inline.
- **Use real names from the source** for components, files, IDs, configuration keys. Never invent.
- **Do NOT introduce dates / time estimates** unless the user provides them - per `AGENTS.md`, agents must not generate time / date estimates.
