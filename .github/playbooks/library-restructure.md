---
name: library-restructure
description: Use when user wants to restructure a library or assembly's folder topology (vertical slice + clean-architecture overlay per §3.12), plan growth structure pre-emptively, or de-duplicate methods across consumers. Includes consumer-audit checklist, namespace migration, test-mirror moves, IVT vs public trade-off, and behavior-tracing for de-duplication.
triggers:
  - "restructure this library"
  - "restructure the folder topology"
  - "plan the structure for"
  - "de-duplicate this method across"
  - "consolidate these duplicate methods"
  - "library restructure for"
---

# Playbook: Library restructure - VSA topology, growth planning, de-duplication

## Purpose

Triggered when the agent is about to (a) restructure an assembly's folder topology, (b) decide `Common/<Domain>/` placement for a new cross-cutting type, (c) extract a duplicated method into a single canonical implementation, or (d) decide between `public` in `Common/` and `internal + InternalsVisibleTo`. Covers the procedural detail behind AGENTS.md §3.12 (vertical slice + clean architecture) and §3.13 (plan structure for growth) plus the de-duplication-and-optimization procedure they reference.

## Hard gates

- **Consumer audit before promoting a slice-internal type to `Common/<Domain>/`.** Run a fresh `grep` for the type's actual cross-slice / cross-asm consumers - never trust a guess or a stale survey. A type only earns a `Common/<Domain>/` slot when at least two slices (or another assembly) genuinely consume it.
- **Behavior trace before extracting a duplicate.** Read both implementations end-to-end and list every divergence (extension stripping, culture-comparison defaults, null/empty handling, off-by-one, exception-on-error contract). Decide explicitly which behavior the unified impl preserves and document any intentional behavior change in the commit message AND lock with a test.
- **Tests move with the code.** Extracting a method to a new class means a matching new test file (`tests/Unit/<Asm>.Tests/Common/<Domain>/<Type>Tests.cs`) and the relevant tests move there. Tests do not stay in the previous owner's test file after extraction.
- **`partial` cleanup when removing the only `[GeneratedRegex]`.** Drop the `partial` modifier AND the `using System.Text.RegularExpressions;` from the class. Otherwise CS8795 + CS0246.
- **Friend-asm grant check before recommending `internal + IVT`.** Open the producing project's csproj and `Properties/AssemblyInfo.cs` (if present) and confirm the `[InternalsVisibleTo("ConsumerAsm")]` entry covers the friend you expect. If missing, the recommendation becomes *internalize-and-add-IVT-entry*. Per `csharp.instructions.md`, prefer csproj `<InternalsVisibleTo Include="OtherAsm" />` over `Properties/AssemblyInfo.cs`.

## Phase enforcement

REQUIRED-decision-recorded class. Detected at `pre-implementation.md` G6 step when the plan touches folder topology - **any move or rename of a folder or namespace** (verbatim G5 safety-critical trigger scope reused by G6). Enforced by TWO catalog rules:

- `pre-impl-skipped-library-restructure-on-folder-or-namespace-move` (MEDIUM, pre-impl) - fires when G6 detected the trigger but POST-CODE-CHANGE LEDGER `gates.pre-impl-playbook-decisions.library-restructure` is missing OR `not-applicable` / `offered-and-declined` / `not-required-trigger-not-detected`. Valid values: `invoked` OR `required-but-skipped: "<safety-critical re-confirmation per User-skip policy>"`.
- `library-restructure-required-on-folder-namespace-move-in-diff` (HIGH, post-impl) - companion that catches the ad-hoc `git mv` bypass: when `git diff <base>..HEAD --name-status` shows `R` (rename) entries crossing directory boundaries OR added `namespace` declarations with new path-prefix segments AND the ledger still says `not-required-trigger-not-detected`, fire. Satisfiability: the agent re-enters G6 per `pre-implementation.md` *G6 re-entry clause* and updates the LEDGER decision line.

## Intake questions

Bundle these in one prompt unless answers cascade:

1. **Trigger:** which of the four triggers fired - folder restructure, `Common/<Domain>/` placement, de-duplication extraction, or `public` vs `internal + IVT` choice? (Determines which sections of the playbook apply.)
2. **Scope:** single type / single folder / whole-assembly restructure / cross-assembly migration?
3. **Plan-for-growth threshold:** can you name 2+ likely-future-additions to any sub-folder you're considering creating? (If no, the sub-folder is speculative - skip it.)
4. **For de-duplication only:** are the two impls truly equivalent or do they have load-bearing behavioral divergences for different callers? (If divergent, the duplication may be intentional - extract a shared helper that both call into, with the divergent step at the call site.)
5. **For `public` vs `internal + IVT` only:** is the cross-asm consumer a single legitimate caller (single named type) or "the entire test project" / "all current and future internals"? (Single caller → prefer `public`; whole-internals consumer → IVT is the right tool.)

## Procedure

### 1. Folder topology - vertical slice + clean architecture

**Default to vertical slice (VSA) for in-assembly folder organization.** Folders organize by feature / domain concept, not by horizontal type-bucket (`Models/` + `Services/` + `Interfaces/` + `Helpers/`). The horizontal-layer pattern was the .NET-Framework default; in modern code it spreads each feature across 4-7 folders, hides cohesion, and turns "what files belong to feature X?" into a search task. Vertical slices co-locate every file a feature touches (its model, its handler, its interface, its tests in the test mirror) into one folder.

**Overlay clean-architecture dependency direction.** Cross-cutting domain types depend on nothing (the inner-domain kernel); slices depend on them; the kernel never depends back on slices. Concretely: `Common/<Domain>/` types use only the standard library; outer slice folders (`Resolvers/`, `Readers/`, `Providers/`) `using Acme.Core.Common.Events;` etc., never the reverse.

**Cross-slice / cross-assembly types live in `Common/<Domain>/`.** Both data-shaped types (DTOs, value records, enums) AND stateless behavior-shaped types (algorithm helpers, pure-function utilities, well-known constants) belong here - the shared-ness is what unites them, not the data-vs-behavior distinction. Sub-divide by DOMAIN (`Common/Events/`, `Common/Channels/`, `Common/Databases/`), NOT by KIND (no `Common/Models/` + `Common/Helpers/` + `Common/Constants/`). The horizontal-layer pattern resurfaces if you split `Common/` by kind, defeating the VSA choice for the rest of the assembly.

**Slice-internal types stay in the slice.** A type consumed only by one slice (a private helper, a slice-specific enum, a single-file resolver pipeline step) lives in that slice's folder, not in `Common/`. Promoting slice-internal types to `Common/` widens the API surface and creates phantom coupling to consumers that don't actually exist. Verify cross-slice usage with a `grep` of the actual consumer set before moving anything to `Common/`.

**Avoid `Utils/` / `Helpers/`** as folder names AND as class-name suffixes. They are anti-patterns - they signal "I couldn't decide where this goes" and grow without bound, accumulating unrelated single-method classes whose only connection is "the author ran out of folder ideas". The contents either belong in the slice that uses them (slice-internal) or in `Common/<Domain>/` (cross-slice). A class named `XxxHelpers` / `XxxUtils` is the same smell at the type level - name it after what it actually does (`FilePathSorter`, `XmlPayloadParser`, `ChannelConfigParser`), not after how it's used.

**`Internal/` follows the .NET BCL convention** for genuinely-implementation-detail types when a sibling assembly we own needs to call them, paired with `[InternalsVisibleTo("OtherAsm")]`. Reach for `Internal/` + IVT only when the type really is implementation detail AND you accept the friend-asm contract on the rest of the internal surface.

### 2. `public` in `Common/<Domain>/` vs `internal + InternalsVisibleTo` - the trade-off

`InternalsVisibleTo` exposes ALL current AND future internals of the producing assembly to the named consumer - meaningful coupling, not just one type. For a SINGLE legitimate cross-asm helper, `public + namespace-segregated` (e.g., `Common/<Domain>/`) is often cleaner than `internal + IVT`. Reach for IVT when:

- The type is genuinely implementation detail (would be `private` if cross-asm visibility weren't needed).
- The consumer assembly is logically a peer / extension of the producer (a test project, a partial / experimental host, a generated-code consumer).
- You accept that EVERY future internal of the producer becomes visible to that consumer - you'll have to think about it on every internal-API change.

Prefer `public` when:

- The type is part of a shared-domain kernel (`Common/<Domain>/`) consumed by an unrelated assembly (UI consuming a Core helper, a CLI tool consuming a Core model).
- The consumer is one of many - adding another caller in the future shouldn't require widening IVT.
- The type's intent is "shared API"; the lack of cross-asm visibility was an oversight or a prior YAGNI decision being revisited.

### 3. Plan structure for growth

Set up the folder structure you expect to grow into, even when one or two files would technically fit at the parent level today. The retrofit cost (`git mv` + namespace updates + `using` updates across every consumer + test-mirror moves + multi-file diff that looks structural for reviewers but should be focused on the actual change) far exceeds the cost of pre-creating the sub-folder. In practice, the retrofit doesn't happen - whatever goes in unstructured tends to stay unstructured.

**Heuristics:**

- **Folders:** create a sub-folder when you can name 2+ likely-future-additions to it. The naming-the-future-additions step is the gate - if you can't list them, you don't actually expect growth and the sub-folder is speculative. Examples that pass: `Common/Channels/` (WidgetNames + WidgetMethods + SourceKind - 3 named files, all cross-asm consumed). Examples that fail: `Common/Authorization/` because "we might add auth later" with no specific files in mind.
- **Namespaces:** match the planned folder topology, not the current one. Don't keep a namespace flat "until we add the second file" - the second file tends to inherit the flat namespace because nobody wants to refactor everyone's `using` directives for one new type.
- **Project boundaries:** when extracting a library, set up the production / unit-tests / integration-tests project trio up front, not just `src/Foo/` + a single `tests/Foo.Tests/`. The integration-tests project becomes load-bearing the moment the first host-dependent test slips in, and adding it later requires moving + re-namespacing a batch of tests.
- **Accessibility:** when promoting a type to cross-asm-public, also add the `InternalsVisibleTo` for the consumer's test project at the same time, even if no test exists yet. Adding IVT later requires finding every test that worked around its absence (reflection, friend-asm shims, duplicate fixtures) and undoing the workaround.

**Plan-for-growth applies to STRUCTURAL decisions only**: folder topology, namespace shape, project boundaries, public-vs-internal accessibility, interface extraction, IVT grants. It does NOT override YAGNI for CODE decisions: don't add unused parameters, optional configuration knobs, abstract base classes "for future overrides", or strategy patterns that today have one strategy. Code abstractions are cheap to add at first real use; folder structure is expensive to add after the fact.

### 4. De-duplication procedure

When the same logic exists in two places - different slices in one assembly, different assemblies in one solution, or worst-case cross-repo - extract a single canonical implementation.

**Step 1 - Trace behavior end-to-end on both sides.** Open both implementations and read them line-by-line. List every divergence:

- Extension stripping (does one impl call `Path.GetFileNameWithoutExtension` and the other call `Path.GetFileName` then strip?).
- Culture-comparison defaults (`StringComparer.Ordinal` vs `OrdinalIgnoreCase` vs `InvariantCultureIgnoreCase`).
- Null / empty handling (does one return early on null, the other throw?).
- Off-by-one on a loop bound or array slice.
- Exception-type-on-error contract (does one throw `InvalidDataException`, the other `FormatException`?).
- Numeric-parse paths (`int.Parse` vs `int.TryParse` vs `long.TryParse`).
- Logging side effects (does one log + return, the other return silently?).

Decide explicitly which behavior the unified impl preserves. Document any intentional behavior change in the commit message AND add a test that locks in the chosen behavior. If both behaviors are load-bearing for different callers, the duplication may be intentional - extract a shared helper that both call into, with the divergent step at the call site.

**Step 2 - Place the canonical impl in the assembly closest to the domain.** The canonical sort of provider-database paths belongs in the resolver assembly (which owns the database concept), not in the UI assembly that happens to also call it. The other consumer reaches DOWN through a `using` directive across the assembly boundary; that's the right dependency direction (UI → Core). If the canonical impl can't live in either existing assembly because neither should depend on the other, the original duplication probably indicated the helper belongs in a third (`.Common` / `.Abstractions`) assembly that both depend on.

**Step 3 - Single API for multiple input shapes when only preprocessing differs.** If one caller has full paths and the other has file names, unify on the canonical input transform inside the helper (`Path.GetFileNameWithoutExtension`) and let both callers pass their natural input. Don't write `Sort(paths)` + `Sort(fileNames)` overloads - they multiply API surface for one operation.

**Step 4 - Eliminate redundant string / object reconstructions.** If the old impl extracted parts and rebuilt the input identically (`Path.Join(dir, file)` where the input was already the joined path), drop the rebuild and return the original. The reconstruction is dead work the original author added "just in case the parts changed".

**Step 5 - Move tests with the extracted code.** Create a matching new test file (`tests/Unit/<Asm>.Tests/Common/<Domain>/<Type>Tests.cs`) and move the relevant tests from the previous owner's test file. Don't leave them in the old test file - the tests are now testing functionality that no longer lives there, which makes file ownership confusing on the next maintenance pass and bloats the old test file with content unrelated to its remaining responsibilities. Mirror the production folder structure in the test project (extracted to `Common/Databases/` → tests in `tests/Unit/<Asm>.Tests/Common/Databases/`).

**Step 6 - Optimize during extraction, not in a separate pass.** The extraction commit is reviewed against the union of both old impls' behavior, so the optimization rides along naturally. Common opportunities:

- **Single-pattern regex → `LastIndexOf` / `IndexOf` / `Span<char>`** - zero-alloc, often 5-10× faster on parse for fixed delimiters. (Multi-pattern or character-class regex stays as regex.)
- **Anonymous types → `readonly record struct`** for sort keys / intermediate tuples.
- **`OrderBy + ThenBy + ThenBy` chains → `Array.Sort` + `IComparable<T>`** for hot paths.
- **`ToList()` / `ToArray()` materialization → pre-allocated array** when the output size is known up front.
- **`Substring(...)` for sort-key extraction → `Span<char>` slice** without intermediate string allocs.
- **Drop `partial` modifier + `using System.Text.RegularExpressions;`** when removing the only `[GeneratedRegex]` from a class. Otherwise CS8795 + CS0246.

Do NOT bundle unrelated optimizations elsewhere in the file - the rule is "the canonical impl gets the better shape", not "while we're here, rewrite neighboring methods".

### 5. Worked example - the `FilePathSorter` extraction

This session extracted a duplicated `SortFilePaths` from `Acme.UI/Services/OrderService.cs` and `Acme.Core/Resolvers/PayloadResolver.cs` into a single canonical `Acme.Core/Common/Items/FilePathSorter.Sort(IEnumerable<string>) → IReadOnlyList<string>`.

- **Behavior trace:** both impls used the same regex (`(.+) (\d+\.\d+\.\d+\.\d+)`), the same `OrderBy(name).ThenBy(major).ThenBy(minor).ThenBy(build).ThenBy(revision)`. UI impl took filenames; core impl took full paths and called `Path.GetFileNameWithoutExtension` first. UI impl reconstructed paths; core impl returned the input full paths.
- **Decision:** unify on `IEnumerable<string>` input + `IReadOnlyList<string>` output, returning the originals. Internally call `Path.GetFileNameWithoutExtension` on each element once for sort-key extraction; both filename-only and full-path callers pass their natural input.
- **Optimizations folded in:** `LastIndexOf(' ')` + `Span<char>` slicing replaced the regex; `readonly record struct SortKey : IComparable<SortKey>` replaced the anonymous-type sort key; `Array.Sort` replaced the `OrderBy + 4×ThenBy` chain; pre-allocated arrays replaced LINQ materialization.
- **Cleanup:** dropped `partial` modifier + `using System.Text.RegularExpressions;` from both `OrderService.cs` and `PayloadResolver.cs` (each had only one `[GeneratedRegex]` - the now-removed `SplitName` / `ParseVersionRegex`).
- **Tests:** 8 sort tests moved from `PayloadResolverTests.cs` to new `tests/Unit/Acme.Core.Tests/Common/Items/FilePathSorterTests.cs`; +1 new file-names-only test added (covering the input shape that wasn't previously tested).

### 5b. Worked example - shared test infrastructure variant

When de-duplication crosses test-project boundaries (the same builder / fixture-factory / assertion helper / constant appears in ≥2 test projects), follow `csharp.instructions.md` *Tests - .NET test project layout* and promote to a shared `tests/Shared/<Solution>.<Domain>.TestUtils/` class library. **Consumer test projects keep their per-project `TestUtils/` folder** (e.g., its own `Constants` partial, `<Topic>Utils` helpers, `<Domain>TestFixtures` named instances) - only the genuinely duplicated infrastructure moves to the shared project. `tests/Shared/` is NOT a new default; it is an escape hatch.

- **Behavior trace** (same shape as section 5): list every divergence across the duplicated helpers - default parameter values, ordering, null handling, culture-comparison defaults. Unify on one shape; document divergence preserved or changed. If the trace surfaces intentional drift, **do NOT promote** - keep both copies project-local with explicit variant suffixes per the diverged-constants pattern.
- **Project shape:** class library (`<IsTestProject>false</IsTestProject>`), namespace `<Solution>.<Domain>.TestUtils`. The shared project **MUST NOT** reference test-runner / discovery packages (`xunit.runner.*`, `Microsoft.NET.Test.Sdk`, `coverlet.collector`); **MAY** reference assertion-only `xunit.assert`, `FluentAssertions`, `xunit.core` (for `[Theory]` data), or helper libraries (`NSubstitute`, `Bogus`, `AutoFixture`) when builders / fixtures / assertions genuinely use them. Prefer the narrowest dependency - `xunit.assert` over umbrella `xunit`. Consumers add `<ProjectReference>` to the new project's csproj.
- **Class names domain-specific:** `<Domain>TestConstants` (partial), `<Domain>Builder` (parameterized SUT-type factory), `<Domain>Fixtures` (parameterized SUT-setup factory), `<Domain>Assertions` (custom assertion helpers). Generic names (`Constants`, `Utils`, `Helpers`) **can cause** `CS0104: ambiguous reference` against per-project `Constants` partials still owned by the consumer test projects when both are `using`-imported into the same file. A `using` alias is a valid fallback, but domain naming avoids needing one - and aliases tend to fall out of sync as test files are copied around.
- **Internal-type dependency check:** before promoting any `<Domain>Builder` / `<Domain>Fixtures` / `<Domain>Assertions` to shared, verify the helper's signatures (parameters / return types / call sites) depend only on `public` production API. If the helper reads or constructs `internal` production types, it cannot compile in the shared project without an `[InternalsVisibleTo]` grant - **keep it per-project** (default safe choice). Escalate via `ask_user` only when per-project copies are untenable AND the production types are deliberately internal; the resolution is either widening the production type to `public` (preferred per AGENTS.md §3.12) or adding a targeted IVT grant (last resort).
- **Tests do NOT move.** Test METHODS stay in their owning test project (which keeps its own `TestUtils/` for project-local helpers + bare `Constants` partial). Only the duplicated *helpers / fixtures / assertions / constants* move to the shared project. Per-project `Constants.<Topic>.cs` files in each consumer test project are pruned to delete the entries now sourced from the shared `<Domain>TestConstants`.
- **Linked-source migration:** if either consumer test project previously had `<Compile Include="..\..\..." Link="..." />` against the duplicated source, drop the linked-source line from the consumer csproj as part of the same commit - the `<ProjectReference>` to the new shared project replaces it.
- **Verification:** the full test suite (`dotnet test`) must pass post-extraction; the shared project itself has no independent behavioral assertions to lock - only compilation success + consumer-test green prove the extraction is correct. If the shared project's own helpers grow complex enough to warrant tests, create a sibling `<Solution>.<Domain>.TestUtils.Tests` project under `tests/Unit/` (same test-mirror principle as production code).

### 6. Restructure execution checklist

Apply when actually moving files:

1. `git mv` for every rename (preserves blame). Don't drag-drop in the IDE.
2. Update the file's `namespace` declaration to match the new folder.
3. Search every consumer for the old fully-qualified name and the old `using` directive. Search includes: `.cs`, `.razor`, `.razor.cs`, `_Imports.razor`, `.xaml`, `.csproj` linked items, JSON converter switch cases, log / trace strings.
4. Add the new `using` directive to consumers (BOM-preserving, alphabetic insert respecting copyright header - see `csharp.instructions.md` for the BOM-preservation pattern).
5. Remove orphan `using` directives from consumers that no longer need the old namespace.
6. Build the affected project, then the full solution. Surface CS0234 (namespace not found) / CS0246 (type or namespace not found) early.
7. Run `dotnet format style <slnx> --diagnostics IDE0005 IDE0065 --no-restore --verify-no-changes` and `dotnet format whitespace <slnx> --no-restore --verify-no-changes` per the hard pre-commit gate.
8. Run all tests: unit + integration (per the directory-classified `dotnet test` loop pattern in `csharp.instructions.md`).
9. Multi-model panel review (per `pre-commit.md`) - folder restructure changes touch many files and benefit from cross-model verification.
10. Commit with a single-line message describing the restructure (per AGENTS.md §2).

### 7. When to stage as multiple commits vs one

A folder restructure that touches 50+ files is large but mechanically uniform - one commit per discrete restructure decision (one folder created, one rename, one extraction) usually reads best in review. Stage separately when:

- The restructure spans multiple assemblies and each assembly's diff is independently reviewable.
- The restructure includes both file moves AND a behavioral extraction (de-duplication) - split move-only from behavior-changing.
- A reviewer would benefit from seeing the move + namespace + using-update for one type before the next type's diff lands.

Bundle into one commit when:

- The restructure is a single conceptual change (e.g., "split `Common/` into domain sub-folders" - the unit of meaning is the whole sub-folder topology, not each individual file).
- The intermediate state would not build (e.g., moving a type and updating its 30 consumers - splitting would leave the build broken at a commit boundary).
