---
name: project-vocabulary
description: Use when user wants to create, bootstrap, or refresh a per-repo vocabulary doc that disambiguates project-specific terms, overloaded concepts, or jargon. Standalone doc-maintenance skill; produces a repo-local `project-vocabulary.md` (or user-specified path) that the agent can grep against in future sessions.
triggers:
  - "create vocabulary doc"
  - "disambiguate project terms"
  - "refresh the project vocabulary"
  - "document the shared vocabulary"
  - "build a glossary for"
  - "project glossary"
---

# Project vocabulary

## Purpose

Bootstrap or refresh a per-repo vocabulary doc that disambiguates project-specific terms, concepts, and overloaded words. Produces a **repo-local artifact** (not always-loaded; not loaded by AGENTS.md / instructions) the agent can grep against in future sessions to decode jargon, reduce token spend on re-explaining terms, and keep variable / function / file names aligned with the shared language.

Used standalone OR called by `implementation-planning.md` when no vocab doc exists at the expected path. Output-write ordering enforced: chat-render first, save only after explicit destination + content approval.

## Hard gates

- **Output-write ordering**: glossary entries rendered in chat first; save to file only after user approves both the destination path AND the content.
- **Repo-local artifact**: the vocab doc lives in the consumer repo, NOT in `AGENTS.md` / `.github/instructions/` / always-loaded paths. Never adds to context-window cost of unrelated sessions.
- **Evidence-gate output**: vocabulary scan reported as structured chat output before the chat-rendered draft (see *Procedure* step 3).
- **Source-grounded entries**: every proposed term entry cites the codebase site(s) where the term appears (`file:line`) — no invented terms.

## Phase enforcement

OFFERED class. Detected at `pre-implementation.md` G6 step when the plan introduces ≥3 new domain terms (types / methods / concepts) NOT in `project-vocabulary.md`. Enforced by ONE catalog rule:

- `pre-impl-skipped-project-vocabulary-when-new-terms` (LOW, pre-impl) — fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.project-vocabulary` is missing OR `not-applicable` (silent-downgrade bypass). Valid values when detected: `invoked` / `offered-and-declined: "<user-quoted justification>"` / `required-but-skipped: "<reason>"`.

## Intake questions

Bundle in one `ask_user` prompt:

1. **Destination**: where should the doc live? Default `project-vocabulary.md` at repo root. Common alternatives: `docs/vocabulary.md`, `CONTEXT.md`, `GLOSSARY.md`. **Confirm even when the user named a destination upfront** — destination is overloaded across teams.
2. **Audience**: who reads this? Devs (assume programming knowledge), domain stakeholders (assume domain knowledge but minimal code), or both (sections separated by audience). Affects entry phrasing.
3. **Mode**: bootstrap (no vocab doc exists; build from codebase scan) or refresh (vocab doc exists; reconcile against current codebase).
4. **Scan scope**: whole repo OR specific folders / projects (when working in a large monorepo or specific subsystem).

## Procedure

1. **Codebase scan** — `grep` / `view` across the chosen scope for:
   - Repeated proper nouns / capitalized identifiers (likely domain terms).
   - Module / namespace / project names.
   - Concepts that appear in multiple files but never as a class / method name (likely informal vocabulary).
   - Acronyms / abbreviations (`Mgr`, `Svc`, `Ctx`, `Pkg`).
   - Terms that overload common English (`load`, `process`, `handle`, `service`) where the project uses them with a specific meaning.
2. **Candidate term list** — produce a deduplicated list. Categorize: Add (clear domain term needing definition), Keep (already in existing vocab doc; entry stays as-is), Reject (English with English meaning; not domain-specific), Refresh (existing entry that drifted from current usage).
3. **Evidence-gate output** (chat-visible before the chat-rendered draft):

   ```
   Vocabulary scan: scope=<files/globs scanned, method=grep|view>, T candidate terms surfaced, A proposed Add entries, K Keep, R Reject, F Refresh.
   - Add: <term>: <one-sentence definition> (citations: <file:line list>)
   - Keep: <term>: (existing entry retained; citation: <existing-vocab-path:line>)
   - Reject: <term>: <reason — not domain-specific / English meaning suffices> (citation: <where it appears, for reviewer cross-check>)
   - Refresh: <term>: <new definition replacing old> (old: <quote>, new: <quote>, citation: <file:line>)
   - Zero-count justifications: any of T/A/K/R/F = 0 → state why (e.g., "0 Reject entries — every surfaced term has domain-specific meaning per scan").
   ```

4. **Chat-rendered draft** — produce the proposed full vocabulary doc (or diff against existing) in chat. Use one entry per term, alphabetically sorted within each audience section. Format:

   ```
   ### <Term>

   <One-paragraph definition.> Used in: <citations>. Related: <other terms>.
   ```

5. **User approval** — wait for explicit approval of both destination path (re-confirmed) AND content. Do not write to file until both are explicit.
6. **Write** — `create` (bootstrap) or `edit` (refresh) the chosen destination. Output the final byte count + path so the user can verify.
7. **Stable-heading discipline** — entries use `### <Term>` headings so the agent can grep `### Foo` in future sessions for fast lookup. Do NOT rename headings during refresh unless the term itself changed.

## Output

Repo-local vocabulary doc at the user-approved path. Stable `### <Term>` headings for grep-anchored lookup. Survives across sessions (file persists in the repo). Future sessions can `view` it on demand when the agent encounters unfamiliar terms; not always-loaded.
