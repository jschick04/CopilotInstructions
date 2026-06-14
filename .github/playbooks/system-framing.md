---
name: system-framing
description: Use when user wants to understand how a piece of code or a proposed change fits into the wider system. Produces a layered map (symbol → module → assembly → product surface) plus a short narrative. Useful for joining a module, briefing someone, or when the agent's reasoning feels too narrow.
triggers:
  - "explain this in context"
  - "walk me through how X flows"
  - "where does this fit in the system"
  - "system framing for"
  - "broader context of"
  - "zoom out on"
---

# System framing

## Purpose

Whole-system framing for unfamiliar code or a proposed change. Produces a **layered map** (symbol → module → assembly → product surface) plus a short narrative. Used when:

- Joining a module and needing orientation.
- Briefing someone else on the area.
- The agent's reasoning feels too narrow (only seeing the symbol, missing the surrounding system).
- Pre-validating a proposed change by tracing its blast radius.

Standalone playbook (no chain dependency).

## Hard gates

- **Inputs required**: a symbol, file, or proposed change under question. The playbook does NOT run on open-ended *"explain the whole system"* requests - bound the scope first.
- **Evidence-gate output**: system map audit with scope, citations, and zero-count justification before the narrative (see *Procedure* step 3).
- **Source-grounded**: every consumer / caller / sibling claim cites `file:line`. Method (`grep`, `view`, language-server, call-graph tool) stated.
- **Greenfield short-circuit**: if the named subject does not exist (typo / not yet created), surface that as the result; do NOT invent context.

## Phase enforcement

OFFERED class. Detected at `pre-implementation.md` G6 step when the plan crosses module / project / assembly boundaries (new cross-asm reference or new project added). Enforced by ONE catalog rule:

- `pre-impl-skipped-system-framing-when-crossing-boundaries` (LOW, pre-impl) - fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.system-framing` is missing OR `not-applicable` (silent-downgrade bypass). Valid values when detected: `invoked` / `offered-and-declined: "<user-quoted justification>"` / `required-but-skipped: "<reason>"`.

## Intake questions

Bundle:

1. **Subject**: which symbol / file / change is under question? Required - playbook does not run without a bound subject.
2. **Depth**: immediate caller graph (one level out) OR whole-system map (caller graph + module + assembly + product surface). Default: whole-system map.
3. **Audience**: you (terse, code-shorthand OK) or someone you're briefing (more narrative, less jargon). Default: you.
4. **Format**: chat-rendered only (default) or save to a doc (ask for destination if save).

## Procedure

1. **Greenfield pre-check** - `grep` / `view` to confirm the subject exists. If not, output one-line "subject not found"; offer `scope-planning.md` if the user is planning a new symbol. Stop.
2. **Read consumers / callers / siblings** at the requested depth:
   - **Symbol layer** - file:line of the subject itself.
   - **Module layer** - namespace / module / folder containing it; sibling symbols in the same module.
   - **Assembly layer** - project / package / library; sibling modules within the assembly.
   - **Product surface layer** - how the assembly is consumed by the broader product (API endpoints, CLI commands, UI features, external clients, package consumers).
3. **Evidence-gate output** (chat-visible before the narrative):

   ```
   System map audit: scope=<files searched, method=grep|view|callgraph|language-server>, depth=<immediate|whole-system>.
   - consumers: C - <file:line list OR "none - zero-count justification: subject has no consumers per <command> across <scope>">
   - callers: K - <file:line list>
   - siblings: S - <file:line list>
   - assembly: <name + path to project/package/Cargo manifest>
   - product surface: <how-consumed OR "internal - not surfaced to product per <evidence>">
   ```

4. **Layered map** (chat-rendered) - ASCII tree with the four layers and citations:

   ```
   <symbol> (file:line)
     └ module: <namespace> (path)
       ├ siblings: <list with file:line>
       └ assembly: <project name> (manifest path)
         └ product surface: <how-consumed, with citations for the surfacing site(s)>
   ```

5. **Short narrative** - 1-3 paragraphs in the chosen audience register. Explain: what the subject does, where it sits, who depends on it, what changes here ripple to. Cite `file:line` for any claim a reader might want to verify.
6. **Save (optional)** - if the user wants the map saved, ask for destination; use `create` only after explicit destination + content approval.

## Output

Chat-rendered layered map + short narrative + evidence-gate audit output. Optional file save to user-approved destination.
