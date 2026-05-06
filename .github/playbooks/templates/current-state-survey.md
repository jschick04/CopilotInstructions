# Template: Current-state survey

## How to use this template

This is a **reference skeleton** for the current-state-survey mode of the design-spec playbook. The playbook (`design-spec.md`) drives intake; this file specifies the document structure.

A current-state survey describes what exists today. It does NOT propose changes. If the user wants a change spec, use `design-change-request.md` instead.

Replace every `<placeholder>` with verified information from the source. Mark unverified claims as `*(ASSUMED — not verified in source)*`.

---

## Section list (in order)

### Header block

A key/value list at the top of the doc, formatted as bold-key followed by value:

- **Subject system / component:** `<name>`
- **System type:** `<e.g. "Azure Logic Apps Standard", "Azure Function App", ".NET Worker Service", "ASP.NET Core API", "On-prem Windows Service">`
- **Owning team:** `<team name>`
- **Status:** `<e.g. "In production since YYYY-MM", "Under active development", "Planned retirement YYYY-Q#">`
- **Source artifacts surveyed:** `<file paths / repo refs / runbooks / docs read for this survey>`

### 1. Purpose

What this system exists to do. One paragraph + 3–5 bullets covering its concrete responsibilities.

Example structure:

> The `<system>` provides `<core capability>` for `<consumers>`. It is the `<role — e.g. "primary integration point", "system of record", "edge cache">` between `<upstream>` and `<downstream>`.
>
> Concrete responsibilities:
> - `<responsibility 1>`
> - `<responsibility 2>`
> - `<responsibility 3>`

### 2. Scope of this document

Explicit in / out list. Which systems / components / behaviors are surveyed in this document and which are explicitly NOT.

| Status | Item |
| --- | --- |
| In scope | `<component or behavior>` |
| In scope | `<component or behavior>` |
| Out of scope | `<component or behavior>` — `<reason or pointer to other doc>` |

### 3. System Context

Upstream consumers, downstream dependencies, data flows in / out. ASCII diagram if it clarifies.

```
                ┌─────────────────┐
                │ <upstream>      │
                └────────┬────────┘
                         │ <protocol / event>
                         ▼
                ┌─────────────────┐
                │ <SUT>           │
                └─────────┬───────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ <downstream> │  │ <downstream> │  │ <downstream> │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 4. High-level Flow

Sequence of stages / components a typical request / event traverses. ASCII diagram with the actual action / component names from the source.

### 5. Component Specification

Per-component breakdown. Heavy table use; pull real names / IDs / paths from the source.

| Component | Type | Key configuration | Inputs | Outputs |
| --- | --- | --- | --- | --- |
| `<name>` | `<e.g. HTTP trigger, scheduled trigger, queue handler>` | `<key settings>` | `<schema or message type>` | `<schema or message type>` |

### 6. Request / Response / Data Body Schemas

Actual schemas with sample JSON / XML / etc. Mark dynamic fields with `@parameters('X')` / `<placeholder>` style.

```jsonc
{
  "fieldA": "<sample value>",
  "fieldB": "@parameters('X')",
  "fieldC": [
    {
      "subFieldA": "<value>",
      "subFieldB": "<value>"
    }
  ]
}
```

### 7. Configuration Parameters

Table of name / type / default / purpose. Include a recommended config-file snippet (`parameters.json`, `appsettings.json`, etc.) where applicable.

| Name | Type | Default | Purpose |
| --- | --- | --- | --- |
| `<name>` | `<string / int / bool / enum>` | `<default>` | `<what it controls>` |

```jsonc
{
  "parameters": {
    "<name>": {
      "type": "<type>",
      "value": "<value>"
    }
  }
}
```

### 8. Operational Requirements

Identity / auth setup, onboarding steps, classification settings, connection strings, runtime knobs. Include real resource IDs / connection-reference names / managed-identity object IDs where applicable (verified).

### 9. Error Handling & Observability

Failure-mode table. Where to look for runtime debugging.

| Failure mode | Observable behavior | Where to debug |
| --- | --- | --- |
| `<mode>` | `<symptom>` | `<run history / log query / dashboard>` |

### 10. Known Issues / Tech Debt *(if intake said yes)*

Numbered list with brief notes. Skip this section entirely if intake said "strictly describe what's there".

1. `<issue>` — `<brief notes>`
2. `<issue>` — `<brief notes>`

### 11. File / Artifact Inventory

Table of paths / files / status. Useful for handoff / repo-onboarding contexts.

| Path | Type | Status |
| --- | --- | --- |
| `<path>` | `<workflow / script / config / doc>` | `<active / deprecated / retired>` |

### 12. Glossary

Domain-specific terms, acronyms, IDs the reader will encounter. Sorted alphabetically.

| Term | Meaning |
| --- | --- |
| `<term>` | `<definition>` |

### 13. References

Links to source code, prior docs, runbooks, related work items. Include real URLs / repo paths / ADO IDs.

- `<source file>` — `<repo:path>`
- `<runbook>` — `<URL>`
- `<related ADO item>` — `<ADO #123>`

### 14. Open Questions

Anything you couldn't determine from the source. Distinct from §10 Known Issues — this is "I don't know yet" rather than "I know it's broken".

1. `<question>` — `<context / where I looked / who might know>`

---

## Notes for the agent

- **Strictly current-state.** Do not propose changes. If you find yourself wanting to recommend a fix, that's a signal to switch to `design-change-request.md` (and confirm with the user).
- **Ground every claim.** Use `grep` / `view` / `explore`. Mark unverified claims as `*(ASSUMED — not verified in source)*`.
- **Reuse the header block format** even when sections below are slim — the header block is the most-used section by readers skimming the doc.
- **Prefer tables over prose** for any structured list (components, parameters, failure modes, files, glossary).
- **Cite real identifiers** — don't invent GUIDs, connection IDs, resource names, or repo paths.
