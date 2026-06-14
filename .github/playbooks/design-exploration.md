---
name: design-exploration
description: Use when user wants to scaffold a deliberately-throwaway prototype to explore design alternatives, architectural approaches, or UI variations. Loudly throwaway; never wired into production. Output: working variants + decision log capturing trade-offs.
triggers:
  - "build a prototype"
  - "throwaway prototype"
  - "explore this design"
  - "design exploration for"
  - "spike on"
  - "UI variations to explore"
---

# Design exploration

## Purpose

Scaffold a deliberately-**throwaway** build to explore design theories, architectural alternatives, or UI variations. Loudly throwaway: marked at folder, file-header, and build-config levels; never imported by production code. Output: working variant(s) + a short decision log capturing what was explored, the trade-offs, and what drove the eventual decision.

Companion playbook for performance-driven exploration: `performance-comparison.md`. Both share the throwaway-hardening discipline below.

## Hard gates

- **Folder discipline**: every prototype lives under `prototypes/<name>/`. The `prototypes/` root is the only allowed location.
- **Canonical throwaway header on comment-capable files**: every comment-capable source file (`.cs`, `.ts`, `.js`, `.py`, `.go`, `.rs`, `.cpp`, `.java`, `.swift`, `.kt`, etc.) starts with a header comment containing the canonical string `THROWAWAY: <prototype-name>`. **This is a narrow exception to AGENTS.md §3.1 "no narrative comments"** - the header is load-bearing (marks the file as throwaway; downstream tooling and humans rely on it), not narrative. AGENTS.md §3.1 cross-references this playbook for the exception scope.
- **Folder-level marker for non-commentable files**: JSON, YAML, binary, generated, or other non-commentable files do NOT get an in-file header. Instead, the prototype folder MUST contain a `README.md` whose first line is `THROWAWAY: <prototype-name>` (acts as the folder-level marker).
- **Build isolation**: prototype folder excluded from main build / test paths. Default: `.gitignore prototypes/` (prototypes are untracked unless explicitly committed-as-artifact per the cleanup gate). When committed-as-artifact, exclude via project-file mechanism (`.csproj` `<Compile Remove>`, `tsconfig.json` `exclude`, Cargo `[workspace.exclude]`, Maven `pluginManagement` excludes, etc.).
- **Zero production-to-prototype imports**: production / build paths MUST NOT import or reference prototype paths. Grep-verified at the cleanup gate. (Prototype → production read-only references allowed only when the prototype is build-isolated.)
- **Cleanup / expiry gate**: before declaring the exploration "ready" or "done", the user explicitly chooses: (a) delete (default), (b) commit-as-artifact (with documented rationale + 0-import grep proof), or (c) defer-with-explicit-expiry-event in the decision log.
- **Evidence-gate output**: variants audit produced as structured chat output before the decision log (see *Procedure* step 4).
- **Catalog rule cross-references**: two catalog rules enforce this playbook's invariants continuously (not just at user strong-trigger time):
  - `prototype-imported-by-production` (HIGH, tree-scoped rg) - multi-language import-statement detection (C# `using`, TS/JS `import`/`require`, Python `import`/`from`, Rust `use`, Go `import`, Java/Kotlin `import`, C++ `#include`) for any production-code reference to `prototypes/`. Excludes prototype subtree via `--glob '!prototypes/**'`. Word-boundary anchored to avoid `myprototypes`/`prototypes2` false positives.
  - `prototype-file-missing-throwaway-marker` (MEDIUM, review-pass-only) - fires when diff adds a NEW file under `prototypes/` without the canonical `THROWAWAY: <name>` header (or sibling README marker for non-commentable files).
  
  See `pr-quality-gate/pattern-catalog.md` for full audit methods.

## Phase enforcement

OFFERED class. Detected at `pre-implementation.md` G6 step when the plan has ≥2 viable competing approaches (plan text contains "option A vs B", "either approach", "compare", "trade-off", OR user asked "which X is better"). Enforced by ONE pre-impl catalog rule plus the existing prototype invariants:

- `pre-impl-skipped-design-exploration-when-competing-approaches` (MEDIUM, pre-impl) - fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.design-exploration` is missing OR `not-applicable` (silent-downgrade bypass - `not-applicable` is INVALID when trigger was detected). Valid values when detected: `invoked` / `offered-and-declined: "<user-quoted justification>"` / `required-but-skipped: "<reason>"`.

Prototype invariants (continuously enforced, NOT pre-impl-only) - see *Hard gates* above for the full list.

## Intake questions

Bundle in one `ask_user` prompt:

1. **What's being explored**: one-sentence framing of the design question (e.g., "compare lock-based vs lock-free queue", "three UI layouts for the filter panel", "evaluate sync vs async repository pattern").
2. **Variant count**: how many variants? Default 2-3 (enough to compare; not so many that the audit becomes the work).
3. **Destination folder**: default `prototypes/<name>/` at repo root. Confirm even when user names a destination (overloaded term).
4. **Retention**: delete-after-decision (default), commit-as-artifact, or expiry-event defer (record explicit event in decision log).
5. **Language / stack**: which language(s) the prototype uses. Affects header convention and build-isolation mechanism.

## Procedure

1. **Scaffold the prototype folder** - `prototypes/<name>/` with subfolders per variant when ≥2 variants share file structure.
2. **Author each variant** - minimal runnable code. Each comment-capable file gets the `THROWAWAY: <prototype-name>` header on line 1. Each non-commentable file group lives alongside a sibling `README.md` with `THROWAWAY: <prototype-name>` as its first line.
3. **Wire build isolation** - `.gitignore prototypes/` by default (or the project-file mechanism for the relevant language when committed-as-artifact). Confirm: production code cannot reach prototype code via the build graph.
4. **Evidence-gate output** (chat-visible before the decision log):

   ```
   Variants audit: N variants scaffolded, throwaway markers compliant: yes (folder + per-file headers OR sibling README for non-commentable), production imports of prototype: 0 (grep verified, scope=<production glob>), build isolation: confirmed (exclude method=<.gitignore | csproj <Compile Remove> | tsconfig exclude | ...>).
   - <variant>: <one-line trade-off summary> (location: prototypes/<name>/<variant>/)
   - cleanup/expiry decision: <delete | commit-as-artifact (rationale) | defer-with-expiry: <event>>
   ```

5. **Decision log** (chat-rendered; may be saved to `prototypes/<name>/DECISION.md` on user request) - what was explored, trade-offs per variant, the chosen direction, what's NOT being pursued (and why).
6. **Cleanup gate** - apply the retention decision from intake:
   - **Delete**: remove the folder. Confirm via `git status` (untracked) or `git rm` (tracked).
   - **Commit-as-artifact**: stage the folder; verify build-isolation grep still shows 0 production imports; include the decision log in the commit.
   - **Expiry-event defer**: record the explicit expiry event in the decision log; agent surfaces this at future sessions when the expiry condition fires.

## Output

Working variants in `prototypes/<name>/` + chat-rendered decision log + variants audit evidence-gate output. Retention per intake.
