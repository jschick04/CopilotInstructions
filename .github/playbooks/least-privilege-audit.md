# Playbook: Least-privilege audit (cross-language)

## Purpose

Apply the **6-axis least-privilege checklist** to a defined scope (a single type, a touched-file diff, a single project, a whole solution / workspace, or a whole monorepo). Output: a per-type matrix with consumer evidence and grouped commit recommendations.

Least-privilege isn't language-specific — every language with a notion of visibility (C#, Java, Kotlin, TypeScript, Rust, Go, C++, Swift, Python with `_`-convention, etc.) has the same six axes. This playbook is the single canonical procedure for the audit; per-language tooling differences are captured in the table in the *Per-language axis mapping* section.

This playbook fires three ways:

1. **Phase trigger (touched-file scope)** — invoked from `post-code-change.md` for the touched-file set on every code change. Lightweight, fast, prevents new violations from landing.
2. **Phase trigger (branch-wide scope)** — invoked from `pre-pr-push.md` when the branch touches a project's public API surface across many files. Catches violations before reviewers see them.
3. **Strong trigger (on demand)** — when the user asks for an *"API tightening"*, *"visibility audit"*, *"least-privilege sweep"*, *"access-modifier audit"*, *"surface area review"*, or similar (artifact-shaped audit ask). The agent immediately offers this playbook via `ask_user`.

## Hard gates (also referenced in `AGENTS.md`)

- **"Fresh grep" beats every cached classification.** "Fresh grep" = a fresh source search using the best tool for the language (`rg`, compiler index, language-server symbol search, package-export inspection, etc.) — not literally `grep(1)`. Survey documents, prior audit notes, and checkpoints are HINTS only — never ground truth. Re-search at audit time and trust the live result. Surveys go stale (new consumers added since they were written) and sometimes contain factual errors. When you find a contradiction with a prior survey, record it explicitly so the survey can be corrected or marked superseded.
- **All 6 axes evaluated for every type.** Type-level internalization is one of six axes — the others (sealing / final, ctor visibility, member visibility, setter, field hygiene) yield independent wins on types that legitimately stay public.
- **Per-type matrix as output**, with consumer evidence (file paths + line numbers from the actual `rg` / `grep` runs) for every internalization recommendation.
- **Whole-scope consumer search.** When auditing a project, the consumer search must scan the WHOLE solution / workspace — not just the project that declares the type. Cross-project consumers are exactly what the audit is checking for.
- **Friend-asm / module-export mechanism verified before recommending internalization.** The audit must check whether the corresponding friend grant exists for the consumer it expects to keep working. Per language: C# csproj `<InternalsVisibleTo>` AND `Properties\AssemblyInfo.cs` (when present); Java `module-info.java exports ... to`; Kotlin Gradle friend-paths configuration (or same-module access); TypeScript `package.json` `exports` subpath fields / tsconfig project references; Rust `pub(crate)` / `#[cfg(test)]`; Go `internal/` directory pattern; etc. Don't recommend `internal` without confirming the grant; if missing, the recommendation is *internalize-and-add-friend-grant* (one extra change to surface to the user).
- **Friend-grant proliferation is a coupling cost** — adding a NEW friend-grant exposes ALL current AND future internals of the granting asm to the receiving asm, far heavier coupling than one named exposed type. The audit therefore never recommends *add new friend-grant* as the default tiebreaker. When a single cross-asm consumer would otherwise force the choice between *KEEP-PUBLIC* and *INTERNAL+ADD-NEW-FRIEND-GRANT*, the precedence ladder is: **(1) split-member visibility** (keep the type at the broader level needed by the cross-asm consumer, but tighten individual members that have only same-asm callers — language-specific: C# public class with mixed `public` / `internal` members; Kotlin `public` class with `internal` members; TypeScript `export class` with only the needed members exposed; Rust `pub` struct with `pub(crate)` methods; Go capitalized type with lowercase methods); **(2) co-location** (move the type into the consumer's asm so it becomes same-asm — applies when the type has exactly one cross-asm consumer and no domain reason to live elsewhere); **(3) keep public** (last resort when the type genuinely belongs in the declaring asm and split-visibility doesn't fit); **(4) add new friend-grant** (LAST resort — only when none of the above applies, e.g. broad surface needs to be reachable AND co-location is wrong AND the public surface would dwarf the friend-grant's coupling cost). Existing friend-grants on the declaring asm are free to use (no proliferation cost).
- **Framework-mandated visibility flagged, not silently overridden.** Razor `[Parameter]` setters must stay public; EF Core `DbContext` is usually not sealed (proxy generation); Spring `@Component` / `@Autowired` may need public; Fluxor reducer/effect static methods need public-static; serialization frameworks (System.Text.Json polymorphism, Jackson, serde) may have constraints. Flag with NOTE, don't auto-recommend tightening.

## Intake questions

Bundle these in one prompt:

1. **Scope?** (touched-file diff *(default for post-code-change)* / single-type / single-project / whole-solution / whole-workspace / whole-monorepo)
2. **Languages?** (detect from scope; for polyglot scopes, list which languages are in play so the per-language tooling table guides the grep commands)
3. **Friend-asm / module-export awareness:** for each project in scope, what mechanism grants cross-asm visibility for tests and friend libraries? (e.g. C# csproj `<InternalsVisibleTo>` vs `Properties\AssemblyInfo.cs` vs neither — the audit must verify before recommending `internal`)
4. **Output destination?** (chat-only summary / chat + persistent matrix in a session file / SQL todos for batched action across multiple PRs / commit grouping recommendation only)
5. **Already-known constraints?** (any types the user knows must stay public — DI seam, NuGet/npm package consumer, public SDK surface — listed up-front to skip)

## Procedure

### 1. Enumerate public types in scope

Per language:

- **C#:** `rg -t cs -n '^(public|public\s+sealed|public\s+abstract|public\s+partial|public\s+static)\s+(class|record|struct|interface|enum|delegate)' <scope>` then dedupe by type name.
- **Java:** `rg -t java -n '^public\s+(final\s+)?(class|interface|enum|record)\s+'`
- **Kotlin:** `rg -t kt -n '^(public\s+)?(open\s+|sealed\s+|abstract\s+|data\s+|enum\s+)?(class|interface|object|enum class)\s+'` (kotlin defaults to public; explicit `internal`/`private` modifies)
- **TypeScript:** `rg -t ts -n '^export\s+(default\s+)?(abstract\s+)?(class|interface|enum|type|function|const)\s+'`
- **Rust:** `rg -t rust -n '^pub(\s|\()'` (note `pub(crate)` is already-tightened — flag `pub` without restriction as the candidate)
- **Go:** any top-level identifier starting with an uppercase letter is exported. `rg -t go -n '^(func|type|var|const)\s+[A-Z]'`
- **C++:** public class members (look at headers); `rg -t cpp -n '^class\s+\w+|^struct\s+\w+'` plus inspect access labels.
- **Swift:** `rg -t swift -n '^(public|open)\s+(class|struct|enum|protocol|func|var|let)'`
- **Python:** no enforced visibility — convention is leading `_` for "private". `rg -t py -n '^(class|def)\s+[a-zA-Z]'` then exclude leading-`_`. Apply `__all__` lists when present.

For touched-file scope, restrict to files in the diff: `git diff --name-only <base>..HEAD | <filter by language>`.

### 2. For each public type, apply the 6 axes with fresh grep

The six axes are language-agnostic. Apply each in order; later axes are evaluated only if the type stays public after Axis 1.

#### Axis 1 — Type access modifier

Goal: demote `public` → most-restrictive that compiles AND keeps real consumers working.

For each public type, run a worktree-wide consumer search using a word-boundary grep for the type name. Bucket consumers as:

- **SAME-asm consumers** (declaring project) — never block internalization.
- **SAME-asm-FRIEND test consumers** (test project granted `InternalsVisibleTo` / equivalent) — never block internalization (already friended).
- **OTHER-asm prod consumers WITH existing friend-grant** — never block internalization (already friended).
- **OTHER-asm prod consumers WITHOUT friend-grant** — apply the friend-grant-proliferation precedence (see below).
- **OTHER-asm test consumers WITHOUT friend grant** — apply the friend-grant-proliferation precedence (see below).

**Friend-grant-proliferation precedence ladder** (per the hard gate above — adding a NEW friend-grant exposes ALL current AND future internals to the receiving asm, so it's the LAST resort, not the default):

1. **SPLIT-MEMBER-VISIBILITY** — keep the type at the broader access level needed by the cross-asm consumer, but tighten individual members that have only same-asm callers. Best when the cross-asm consumer needs only a small subset of the type's surface. Language-specific: C# `public` class with mixed `public` / `internal` members; Kotlin `public` class with `internal` members; TypeScript `export class` with only the necessary methods exported / public; Rust `pub` struct with `pub(crate)` methods; Go capitalized type with lowercase methods; C++ `class` with `public` and `private` access labels; Swift `public class` with `internal` members. The cross-asm consumer sees only the subset it needs; same-asm callers retain access to everything else.
2. **CO-LOCATION** — move the type into the consumer's asm so it becomes same-asm. Applies when the type has exactly one cross-asm consumer and no domain reason to live in the declaring asm.
3. **KEEP-PUBLIC** — last resort when the type genuinely belongs in the declaring asm and split-visibility doesn't fit (e.g. record-style data carrier with no internal-only members to tighten).
4. **INTERNAL+ADD-NEW-FRIEND-GRANT** — LAST resort. Only when (a) the cross-asm consumer needs broad surface that defeats split-visibility, AND (b) co-location is wrong domain-wise, AND (c) the public-surface delta from KEEP-PUBLIC would dwarf the friend-grant's coupling cost (e.g. dozens of types vs. one IVT line).

Existing friend-grants on the declaring asm are free to use — re-using an established `<InternalsVisibleTo>` / module export incurs no new proliferation cost.

Recommendation values: `INTERNAL` / `INTERNAL+REUSE-EXISTING-FRIEND-GRANT` / `SPLIT-MEMBER-VISIBILITY` / `CO-LOCATE-TO-<asm>` / `KEEP-PUBLIC` / `INTERNAL+ADD-NEW-FRIEND-GRANT` (last resort, justify in the matrix).

For polyglot scopes: a TypeScript class `export`ed only for the same package's tests can become non-exported (rely on subpath exports / vitest's `import` of source). A Java class `public` only for same-module callers can be package-private. A Rust `pub` item with only same-crate consumers can be `pub(crate)`. A Go uppercase identifier with only same-package consumers can be lowercased.

#### Axis 2 — `sealed` / `final` / closed-extension modifier

Goal: prevent unintended subclassing; enable compiler / runtime devirtualization where applicable.

For each non-abstract concrete class, search for derivers across the worktree:

- **C#:** `rg -t cs -P 'class\s+\w+\s*(?:<[^>]+>)?\s*:\s*[^,{]*\b<TypeName>\b'`
- **Java:** `rg -t java -P 'extends\s+<TypeName>\b'`
- **Kotlin:** Kotlin classes are `final` by default — flag any `open class` without a same-asm subclass for tightening to `final` (remove `open`).
- **TypeScript:** `rg -t ts -P 'extends\s+<TypeName>\b'` — TS has no built-in `final`; use ESLint `no-extend-class` or JSDoc `@final` if the team adopted them.
- **Rust:** structs/enums are not subclassable; sealing a TRAIT is the relevant pattern — flag public traits with downstream impls vs sealed-trait pattern (`mod sealed { pub trait Sealed {} }`).
- **Go:** no inheritance — N/A.
- **C++:** `rg -t cpp -P ':\s*(public|protected|private)\s+<TypeName>\b'` then recommend `final` keyword on the class.
- **Swift:** `rg -t swift -P ':\s+<TypeName>\b'` then recommend `final class`.

If no derivers found: recommend adding the seal/final modifier. Framework exceptions (record below):

- EF Core `DbContext` subclasses — usually NOT sealed (runtime proxy generation needs vtable slots).
- Designed-for-extension exception base classes.
- Spring beans with AOP proxies (Spring uses CGLib subclassing for some proxy modes).
- Hibernate entities (lazy-loading proxies subclass the entity).
- React class components (rare today; functional components don't have this concern).
- Rust traits intended as a public extension point.

When in doubt, FLAG with NOTE rather than auto-recommend; user decides.

#### Axis 3 — Constructor visibility

Goal: tighten ctors when no external code calls `new TypeName(...)`.

- Only audit if type stays public after Axis 1.
- Search for `new <TypeName>(` (or language equivalent: Kotlin `<TypeName>(`, Rust `<TypeName>::new(`, Go `<package>.New<TypeName>(`, Python `<TypeName>(`, Swift `<TypeName>(`) across the worktree.
- If only same-asm + friend-asm tests invoke the ctor: tighten ctor visibility to `internal` / package-private / `pub(crate)` / etc.
- If DI / reflection / `Activator.CreateInstance` from the same assembly: internal works (most DI frameworks support internal types when the registering asm has visibility).
- If DI / reflection from a DIFFERENT assembly (e.g. ASP.NET Core controllers in a separate asm): keep ctor public OR add friend grant.

#### Axis 4 — Method / property visibility

Goal: tighten members of remaining-public types.

- Skip interface members (bound by contract).
- Skip overrides of base-class members (must match base visibility).
- Skip framework-required members (Razor `[Parameter]` setters, Razor lifecycle methods, EF Core navigation properties, Fluxor `[ReducerMethod]` / `[EffectMethod]`, JSON converter `Convert*` overrides, Java JPA accessors, etc.).
- For each remaining public member, run a qualified search (`<TypeName>.<MemberName>` or call-site syntax) — be careful of name-collision false positives.
- If only consumed inside the declaring asm: demote to `internal` / package-private / `pub(crate)`.

This axis is best done as representative spot-check (not exhaustive enumeration of every member of every class); flag obvious wins, defer the long tail.

#### Axis 5 — Property setters / mutability

Goal: prevent post-construction mutation by external code unless that mutation is genuinely required.

- For each mutable public property on a remaining-public type, classify writers:
  - Never written outside the declaring type → **C#** `private set` / **Kotlin** `private set` on a `var` / **Java** drop the setter (and prefer `final`) / **TypeScript** `readonly` modifier / **Rust** remove `pub` from the field (Rust has no `pub mut` — a `pub` field on a value the caller owns is mutable; restrict by hiding the field and exposing read-only accessors / methods that take `&self`) / **Go** unexport the field; expose a getter method instead.
  - Written only via object-initializer / construction-time syntax outside (e.g. C# `new Foo { Prop = X }`) → **C# `init`** (semantically: settable at construction, not after). Other languages: factory pattern / builder pattern.
  - Mutated post-construction by external code → keep mutable.
- Records (C#) / data classes (Kotlin) / case classes (Scala) typically have init-only positional params — this axis bites manually-declared properties on classes.

#### Axis 6 — Field hygiene

Goal: shrink field surface area; immutability where possible.

- `private` non-readonly fields assigned only in ctor → **C# `readonly`** / **Java `final`** / **Kotlin `val`** / **TypeScript `readonly`** / **Rust** (already immutable by default; `mut` is opt-in) / **Go** (no const fields; document via comment) / **Swift `let`**.
- `internal` fields → check whether `private` would compile.
- `public` fields are almost always wrong (convert to property unless `const` / `static readonly` / Rust `pub const`).

### 3. Output the per-type matrix

Per type, one record like:

```
Type: <fully-qualified-type-name>
File: <relative path>
Current: <observed declaration>
- Axis 1: <recommendation> — <consumer evidence with file:line citations>. Verified via: <exact rg command>.
- Axis 2: <recommendation> — <derivers search result>.
- Axis 3: <recommendation>
- Axis 4: <recommendation>
- Axis 5: <recommendation>
- Axis 6: <recommendation>
- RECOMMENDATION: <one-line proposed declaration>
- RISK: low / medium / high (tie to consumer reach + framework caveats)
- CONTRADICTION: <if survey/prior-audit said something different, cite it>
```

Then a summary table (one row per type):

| Type | Axis 1 | Axis 2 | Axis 3 | Axis 4 | Axis 5 | Axis 6 | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |

Then a commit-grouping suggestion. Two valid grouping styles — pick whichever maps to easier review:

- **Per-type grouping** — one type's full multi-axis change per commit. Easier to review the *intent* of each tightening.
- **Per-axis sweep** — one axis applied across many types per commit (e.g., "Add sealed to all eligible classes — single sweep"). Easier mechanical review; faster to revert if it breaks something framework-related.

### 4. Record audit findings

If scope is multi-PR (e.g., a whole-solution audit before a stacked-PR series begins): write the matrix to a session-state file under the session folder, AND insert SQL todos for each per-PR action, with `depends_on` linking each todo to the PR it belongs to. Reference the matrix file from each todo so the executor can re-read evidence at action time.

If scope is touched-file or single-PR: chat output is enough; commit immediately with the matrix tucked into the commit author's notes (NOT the commit message — keep messages single-line).

### 5. Apply (if user approves)

Group changes per the commit-grouping suggestion, run `pre-commit.md` per commit (each commit gets diff + approval + single-line message), and surface any framework-related regressions immediately.

## Per-language axis mapping (tooling table)

| Language | Axis 1 (type visibility) | Axis 2 (closed-extension) | Axis 3 (ctor) | Axis 4 (member) | Axis 5 (setter) | Axis 6 (field) | Friend-grant mechanism |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **C#** | `public` → `internal` / `file` / `private` (nested) | `sealed` | `private` / `internal` ctor | `private` / `internal` member | `init` / `private set` | `readonly` | `[InternalsVisibleTo("Friend")]` (csproj `<InternalsVisibleTo>` preferred over `AssemblyInfo.cs`) |
| **Java** | `public` → package-private (default) → `private` (nested) | `final` class | `private` / package ctor | `private` / package member | drop setter; `final` field | `final` | `module-info.java exports <pkg> to <module>` (Java 9+); package-private otherwise |
| **Kotlin** | `public` (default) → `internal` (module) → `private` | classes are `final` by default — REMOVE `open` if no subclasses | `private constructor()` | `private` / `internal` member | `val` instead of `var`; `private set` on `var` | `val` + `private` | `internal` is module-scoped; tests in the same Gradle module see `internal` automatically; for `internal` access from a separate friend module, configure Kotlin friend-paths in the Gradle Kotlin compile task (no language-level friend grant) |
| **TypeScript** | `export` → not exported | no built-in `final`; ESLint `no-extend-class` / `@final` JSDoc | `private` ctor + factory | `private` / `protected` member | `readonly` modifier on property | `readonly` | tsconfig project references / package.json `exports` field with subpath exports for "internal-but-exposed-to-friend-test" |
| **JavaScript** | ES module `export` vs no-export | (none — convention) | no language-level private constructors; hide construction by not exporting the class and exporting a factory, or use a runtime guard / convention | `#private` members | (immutable via `Object.freeze` / no setter) | `#private` field | (none — separate package, conditional `exports`, or test-only export) |
| **Rust** | `pub` → `pub(crate)` → `pub(super)` → `pub(in path::to::mod)` → no-modifier | structs/enums are non-extensible; for traits, use sealed-trait pattern (`pub trait Foo: sealed::Sealed`) | `fn new` non-`pub` | non-`pub` method | (no setter convention; immutable by default; `&mut self` methods control mutation; remove `pub` from fields you don't want externally assignable) | (immutable by default) | `pub(crate)` for crate-internal; `#[cfg(test)]` for test-only items; no friend-asm equivalent — use crate boundaries |
| **Go** | exported (capitalized) → unexported (lowercase) | (no inheritance — N/A) | unexported `newFoo` factory | unexported method | (no setter convention) | unexported field | `internal/` subdirectory pattern restricts import to the parent's subtree (Go's "friend grant") |
| **C++** | `public` → `protected` → `private` access labels in class | `final` keyword on class or virtual function | `private` ctor + `friend` declaration | `private` / `protected` member | `const` member function | `const` member, immutable | `friend class` / `friend function` declaration |
| **Swift** | `open` → `public` → `internal` (default) → `fileprivate` → `private` | `final class` | `private init` | `private` / `fileprivate` / `internal` | `private(set) var` | `let` instead of `var` | `@testable import` for test access; Swift Package Manager `@_spi(Friend)` for sub-public friend exposure |
| **Python** | leading `_` convention; `__all__` for module exports; no enforcement | `typing.final` decorator (lint-checked) | leading-`_` factory; no language-level private ctor | leading-`_` method | `@property` with no `setter` decorator | `@dataclass(frozen=True)` field; `Final[T]` annotation | (none — convention only; testable via `_internal` access) |

## Phase integration

This playbook is invoked by other phase playbooks (the "core rotation" hook):

- **`post-code-change.md`** — touched-file scope. Lightweight: only the files in the diff. Mandatory step on every code-change cycle. The audit prevents new violations from landing in the same commit that introduces the new public surface.
- **`pre-pr-push.md`** — branch-wide scope. Mandatory if the branch touches a project's public API surface across multiple files. Catches the "many small commits each individually fine, but together leak a too-public surface" failure mode before reviewers see it.
- **Strong trigger** — user-requested whole-solution / whole-workspace audit. Defer to intake to scope.

## Common contradictions to watch for

These are recurring failure modes in past audits — re-grep at audit time even if the prior survey says otherwise:

- **Survey lists a type as "consumed by X, Y, Z" but fresh grep shows zero consumers in X/Y/Z.** Survey was wrong (often: confused "DbContext consumed by X" with "everything DbContext uses is consumed by X"; or the consumer was deleted in a later commit). Trust grep.
- **Friend-grant claimed but missing.** Survey says "tests use IVT" but the csproj has no `<InternalsVisibleTo>` and `AssemblyInfo.cs` doesn't exist. The audit must `view` the project file before recommending internalization.
- **Cross-asm consumer found in a place that "shouldn't" reference the type.** Often a layering bug worth surfacing separately — flag rather than silently keep public.
- **Razor `<MyComponent />` markup hits not picked up by `rg -t cs`.** Use `rg -t html` or `rg --type-add 'razor:*.razor' -t razor` for Razor markup; remember `_Imports.razor` and `@inherits` directives.
- **Reflection-discovered types** (Fluxor `Assembly.GetTypes()`, EF Core entity discovery, Newtonsoft `[JsonConverter]`, Spring component scanning) — `internal` is usually fine within the same assembly, but verify with a build + a runtime smoke test before committing.

## Anti-patterns the audit should reject

- "Make it public so the test can access it." NEVER. Friend-grant the test asm; keep production tight.
- "Make it public so future consumers can use it." NEVER. Promote when a real consumer materializes; speculative public surface is debt.
- "It's already public; leave it." NEVER on its own — re-evaluate whenever the audit fires; consumer sets shrink as code is refactored.
- "Skip the audit because the change is small." NEVER on touched-file scope; the audit is fast and the highest-leverage moment is when the change is fresh.
- **"Add a new friend-grant so we can internalize this one type."** REJECT when split-member visibility, co-location, or KEEP-PUBLIC would satisfy the cross-asm consumer's needs without proliferating IVT / module-export coupling. A new friend-grant exposes ALL current AND future internals of the granting asm to the receiving asm — far heavier than one named exposed type. See the Axis 1 precedence ladder.
