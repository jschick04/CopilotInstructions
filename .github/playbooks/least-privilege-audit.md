# Playbook: Least-privilege audit (cross-language)

## Purpose

Apply the **6-axis least-privilege checklist** to a defined scope (single type / touched-file diff / single project / whole solution / whole monorepo). Output: a per-type matrix with consumer evidence and grouped commit recommendations.

Least-privilege isn't language-specific — every language with a notion of visibility (C#, Java, Kotlin, TypeScript, Rust, Go, C++, Swift, Python by convention) has the same six axes. This file is the **index**; the per-axis procedure lives in `least-privilege-audit/axis-N-<name>.md`. Cross-axis content (per-language mapping, phase integration, contradictions, anti-patterns) stays here.

This playbook fires three ways:

1. **Phase trigger (touched-file scope)** — invoked from `post-code-change.md` for the touched-file set on every code change. Lightweight, fast, prevents new violations.
2. **Phase trigger (branch-wide scope)** — invoked from `pre-pr-push.md` when the branch touches a project's public API surface across many files.
3. **Strong trigger (on demand)** — user asks for *"API tightening"*, *"visibility audit"*, *"least-privilege sweep"*, *"access-modifier audit"*, *"surface area review"*. Agent offers via `ask_user`.

## Hard gates (also referenced in `AGENTS.md`)

- **"Fresh grep" beats every cached classification.** *Fresh grep* = a fresh source search using the best tool for the language (`rg`, compiler index, language-server symbol search, package-export inspection) — not literally `grep(1)`. Survey documents and prior audit notes are HINTS only, never ground truth. Re-search at audit time; when you find a contradiction with a prior survey, record it explicitly so the survey can be corrected.
- **All 6 axes evaluated for every type that stays public after Axis 1.** Type-level internalization is one of six axes; the others (sealing/final, ctor visibility, member visibility, setter, field hygiene) yield independent wins on types that legitimately stay public. **Full audits MUST fetch all 6 axis sub-files**; single-axis fetches are allowed only when the user names a specific single-axis use case (e.g., *"just check sealing for these classes"*).
- **Per-type single-pass loop**: for each type in scope, evaluate Axis 1 first → if the type is demoted (internal / package-private / `pub(crate)` / etc.), SKIP axes 2–6 for that type (member tightening on a non-public type is out of scope). If the type stays public, fetch and apply axes 2–6 in order. Single-pass: do NOT iterate to fixpoint within one audit run.
- **Re-run advisory output**: when an Axis 1 internalization removes a previously-counted cross-asm consumer from another in-scope type's matrix (cascade), emit a `re-run advisory: <type>` line in the matrix output. The user decides whether to re-run; the audit does NOT auto-iterate.
- **Per-type matrix as output**, with consumer evidence (file paths + line numbers from the actual fresh-grep runs) for every internalization recommendation.
- **Whole-scope consumer search**: when auditing a project, the consumer search must scan the WHOLE solution / workspace / monorepo — not just the declaring project. Cross-project consumers are exactly what the audit is checking for.
- **Friend-grant verification before recommending internalization**: check whether the corresponding grant exists. C# csproj `<InternalsVisibleTo>` AND `Properties\AssemblyInfo.cs`; Java `module-info.java exports ... to`; Kotlin Gradle friend-paths (or same-module); TypeScript `package.json` `exports` subpath / tsconfig project references; Rust `pub(crate)` / `#[cfg(test)]`; Go `internal/` directory pattern. Don't recommend `internal` without confirming the grant; if missing, the recommendation is *internalize-and-add-friend-grant* (one extra change to surface).
- **Friend-grant proliferation is a coupling cost** — adding a NEW friend-grant exposes ALL current AND future internals of the granting asm to the receiving asm. Precedence ladder in `axis-1-type-access.md`: (1) split-member visibility, (2) co-location, (3) keep public, (4) add new friend-grant (LAST resort). Re-using an existing friend-grant is free; adding a new one is the LAST resort.
- **Framework-mandated visibility flagged, not silently overridden.** Razor `[Parameter]` setters, EF Core `DbContext` proxies, Spring `@Component`, Fluxor reducers, serialization-framework constraints — flag with NOTE; don't auto-recommend tightening.
- **G6 dead-code default-delete** (folded into Axis 1) — when Axis 1 grep shows zero in-repo consumers for a type, the **default action is DELETE** (not internalize-as-placeholder). Carve-outs: (a) **exported / public SDK / package surface**: conservative default — when external surface is uncertain, KEEP and flag for user approval (per-language detection rules in `axis-1-type-access.md`); (b) **predicate-supporting fields**: §3.7-audit-discovered fields require behavior proof (test, usage trace, or runtime read) before deletion — framework binding, serialization, or reflection may consume them silently. **Durable record location for non-deletion**: session todos OR issue tracker URL (NOT plan.md, which is session-scoped).

## Intake questions

Bundle these in one prompt:

1. **Scope?** (touched-file diff *(default for post-code-change)* / single-type / single-project / whole-solution / whole-workspace / whole-monorepo)
2. **Languages?** (detect from scope; for polyglot scopes, list which languages are in play so the per-language tooling table guides the grep commands)
3. **Friend-asm / module-export awareness**: for each project in scope, what mechanism grants cross-asm visibility for tests and friend libraries? (e.g. C# csproj `<InternalsVisibleTo>` vs `Properties\AssemblyInfo.cs` vs neither)
4. **Output destination?** (chat-only summary / chat + persistent matrix in a session file / SQL todos for batched action across multiple PRs / commit grouping recommendation only)
5. **Already-known constraints?** (any types the user knows must stay public — DI seam, NuGet/npm package consumer, public SDK surface — listed up-front to skip)
6. **Scope of axis run** — full 6-axis (default) OR explicit single-axis use case (axis name + rationale). Single-axis only when the user names it.

## Procedure

### 1. Enumerate public types in scope

Run the language-specific public-type enumeration (see *Per-language axis mapping* table below for the per-language commands). For touched-file scope, restrict to files in the diff: `git diff --name-only <base>..HEAD | <filter by language>`.

### 2. For each public type, apply the 6 axes in single-pass order

For each type:

1. Fetch `axis-1-type-access.md` and apply Axis 1.
2. If the type is demoted (no longer public after Axis 1), skip axes 2–6 for this type. Record axes 2–6 as `N/A (demoted)` in the matrix.
3. If the type stays public, fetch and apply `axis-2-sealing-finality.md`, `axis-3-ctor-visibility.md`, `axis-4-member-visibility.md`, `axis-5-setter-visibility.md`, `axis-6-field-hygiene.md` in order.
4. After processing all types, detect cascades: if any Axis 1 internalization removed the only cross-asm consumer of another in-scope type, emit a `re-run advisory: <type>` line in the matrix. Single-pass — do NOT auto-iterate.

### 3. Output the per-type matrix

Per type, one record:

```
Type: <fully-qualified-type-name>
File: <relative path>
Current: <observed declaration>
- Axis 1: <recommendation> — <consumer evidence with file:line citations>. Verified via: <exact fresh-grep command>.
- Axis 2: <recommendation> — <derivers search result> | N/A (demoted by Axis 1)
- Axis 3: <recommendation> | N/A (demoted)
- Axis 4: <recommendation> | N/A (demoted)
- Axis 5: <recommendation> | N/A (demoted)
- Axis 6: <recommendation> | N/A (demoted)
- RECOMMENDATION: <one-line proposed declaration> | DELETE (per G6, zero in-repo consumers + not-exported confirmed) | KEEP + FLAG FOR USER APPROVAL (per G6 conservative default, external surface uncertain)
- RISK: low / medium / high
- CONTRADICTION: <if survey/prior-audit said something different, cite it>
```

Then a summary table (one row per type):

| Type | Axis 1 | Axis 2 | Axis 3 | Axis 4 | Axis 5 | Axis 6 | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |

Then a commit-grouping suggestion. Two valid grouping styles — pick whichever maps to easier review:

- **Per-type grouping** — one type's full multi-axis change per commit. Easier to review the *intent* of each tightening.
- **Per-axis sweep** — one axis applied across many types per commit (e.g., "Add sealed to all eligible classes — single sweep"). Easier mechanical review.

If any `re-run advisory` lines appear in the matrix, list them in the summary so the user can decide whether to re-run.

### 4. Record audit findings

Multi-PR scope (e.g., whole-solution audit before a stacked-PR series): write the matrix to a session-state file under the session folder AND insert SQL todos for each per-PR action, with `depends_on` linking each todo to its PR. Reference the matrix file from each todo so the executor can re-read evidence at action time.

Touched-file or single-PR scope: chat output is enough; commit immediately with the matrix tucked into commit author's notes (NOT the commit message — keep messages single-line).

### 5. Apply (if user approves)

Group changes per the commit-grouping suggestion. Run `pre-commit.md` per commit (each commit gets diff + approval + single-line message). Surface framework-related regressions immediately.

## Per-language axis mapping (tooling table)

| Language | Axis 1 (type visibility) | Axis 2 (closed-extension) | Axis 3 (ctor) | Axis 4 (member) | Axis 5 (setter) | Axis 6 (field) | Friend-grant mechanism |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **C#** | `public` → `internal` / `file` / `private` (nested) | `sealed` | `private` / `internal` ctor | `private` / `internal` member | `init` / `private set` | `readonly` | `[InternalsVisibleTo("Friend")]` (csproj `<InternalsVisibleTo>` preferred over `AssemblyInfo.cs`) |
| **Java** | `public` → package-private (default) → `private` (nested) | `final` class | `private` / package ctor | `private` / package member | drop setter; `final` field | `final` | `module-info.java exports <pkg> to <module>` (Java 9+); package-private otherwise |
| **Kotlin** | `public` (default) → `internal` (module) → `private` | classes are `final` by default — REMOVE `open` if no subclasses | `private constructor()` | `private` / `internal` member | `val` instead of `var`; `private set` on `var` | `val` + `private` | `internal` is module-scoped; tests in same Gradle module see `internal` automatically; for `internal` access from a separate friend module, configure Kotlin friend-paths in Gradle Kotlin compile task |
| **TypeScript** | `export` → not exported | no built-in `final`; ESLint `no-extend-class` / `@final` JSDoc | `private` ctor + factory | `private` / `protected` member | `readonly` modifier on property | `readonly` | tsconfig project references / `package.json` `exports` field with subpath exports for "internal-but-exposed-to-friend-test" |
| **JavaScript** | ES module `export` vs no-export | (none — convention) | no language-level private ctor; hide via factory or `#private` | `#private` members | (immutable via `Object.freeze` / no setter) | `#private` field | (none — separate package, conditional `exports`, or test-only export) |
| **Rust** | `pub` → `pub(crate)` → `pub(super)` → `pub(in path::to::mod)` → no-modifier | structs/enums are non-extensible; for traits, use sealed-trait pattern (`pub trait Foo: sealed::Sealed`) | `fn new` non-`pub` | non-`pub` method | (no setter convention; immutable by default; `&mut self` methods control mutation) | (immutable by default) | `pub(crate)` for crate-internal; `#[cfg(test)]` for test-only; no friend-asm equivalent — use crate boundaries |
| **Go** | exported (capitalized) → unexported (lowercase) | (no inheritance — N/A) | unexported `newFoo` factory | unexported method | (no setter convention) | unexported field | `internal/` subdirectory pattern restricts import to the parent's subtree (Go's "friend grant") |
| **C++** | `public` → `protected` → `private` access labels | `final` keyword | `private` ctor + `friend` declaration | `private` / `protected` member | `const` member function | `const` member, immutable | `friend class` / `friend function` declaration |
| **Swift** | `open` → `public` → `internal` (default) → `fileprivate` → `private` | `final class` | `private init` | `private` / `fileprivate` / `internal` | `private(set) var` | `let` instead of `var` | `@testable import` for test access; SPM `@_spi(Friend)` for sub-public friend exposure |
| **Python** | leading `_` convention; `__all__` for module exports; no enforcement | `typing.final` decorator (lint-checked) | leading-`_` factory; no language-level private ctor | leading-`_` method | `@property` with no `setter` decorator | `@dataclass(frozen=True)` field; `Final[T]` annotation | (none — convention only; testable via `_internal` access) |

## Phase integration

This playbook is invoked by other phase playbooks (the "core rotation" hook):

- **`post-code-change.md`** — touched-file scope. Mandatory step when the diff has a visibility / export / mutability surface delta. Prevents new violations from landing in the same commit that introduces the new public surface.
- **`pre-pr-push.md`** — branch-wide scope. Mandatory if the branch touches a project's public API surface across multiple files. Catches the "many small commits each individually fine, but together leak a too-public surface" failure mode before reviewers see it.
- **Strong trigger** — user-requested whole-solution / whole-workspace audit. Defer to intake to scope.

## Common contradictions to watch for

Re-grep at audit time even if a prior survey says otherwise:

- **Survey lists a type as "consumed by X, Y, Z" but fresh grep shows zero consumers in X / Y / Z.** Survey was wrong (often: confused "DbContext consumed by X" with "everything DbContext uses is consumed by X"; or the consumer was deleted in a later commit). Trust grep.
- **Friend-grant claimed but missing.** Survey says "tests use IVT" but the csproj has no `<InternalsVisibleTo>` and `AssemblyInfo.cs` doesn't exist. `view` the project file before recommending internalization.
- **Cross-asm consumer found in a place that "shouldn't" reference the type.** Often a layering bug worth surfacing separately — flag rather than silently keep public.
- **Razor `<MyComponent />` markup hits not picked up by `rg -t cs`.** Use `rg -t html` or `rg --type-add 'razor:*.razor' -t razor`; remember `_Imports.razor` and `@inherits` directives.
- **Reflection-discovered types** (Fluxor `Assembly.GetTypes()`, EF Core entity discovery, Newtonsoft `[JsonConverter]`, Spring component scanning) — `internal` is usually fine within the same assembly, but verify with a build + runtime smoke test before committing.

## Anti-patterns the audit should reject

- *"Make it public so the test can access it."* NEVER. Friend-grant the test asm; keep production tight.
- *"Make it public so future consumers can use it."* NEVER. Promote when a real consumer materializes; speculative public surface is debt.
- *"It's already public; leave it."* NEVER on its own — re-evaluate whenever the audit fires; consumer sets shrink as code is refactored.
- *"Skip the audit because the change is small."* NEVER on touched-file scope; the audit is fast and the highest-leverage moment is when the change is fresh.
- *"Add a new friend-grant so we can internalize this one type."* REJECT when split-member visibility, co-location, or KEEP-PUBLIC would satisfy the cross-asm consumer's needs without proliferating IVT / module-export coupling. See `axis-1-type-access.md` precedence ladder.
- *"Internalize as a placeholder for future use."* REJECT per G6 — zero in-repo consumers + not-exported confirmed = DELETE. Speculative non-deletion is debt; record near-term feature plans in session todos or issue tracker if the symbol is genuinely retained.
