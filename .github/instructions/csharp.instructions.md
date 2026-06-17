---
applyTo: "**/*.cs,**/*.csx,**/*.csproj,**/*.razor,**/*.razor.cs,**/*.cshtml,**/*.aspx"
---

# C# / .NET Instructions

> **Scope:** loaded on C# / Razor / project files. Extends `AGENTS.md` core. Siblings: `csharp-style.instructions.md`, `csharp-runtime.instructions.md`, `csharp-smells.instructions.md`.

---
## Comments - XML doc additions (extends [Core / Comments](../../AGENTS.md#31-comments))

The universal comment rules in `AGENTS.md` (three-step comment protocol - clarity check → rename check → step-3 `ask_user` comment-approval gate; canonical exempt categories; no comments that restate code; no narration; no future-tense speculation; no TODO/FIXME/HACK; hard ≤ 12-word inline cap; mandatory self-review pass with `approval_turn:` citation) all apply here unchanged. The bullets below are the C#-specific additions for XML doc comments.

- **No XML doc comments (`/// <summary>...`) on `private` members.** Period. Not on private fields, not on private methods, not on private nested types. The XML-doc-on-private-field is the most common violation. If the field needs explanation, the *name* needs work.
- XML docs that restate the method signature are forbidden the same way prose comments that restate code are: `/// <summary>Copies text to the clipboard.</summary>` on `Task CopyTextAsync(string text)` says nothing the signature doesn't.
- **Hard length caps for XML docs:**
  - `<summary>` on public/internal members: **one sentence.** No paragraphs. No `<para>`. No bullet lists. If the contract takes more than a sentence, the API is doing too much - split the method.
  - `<param>` / `<returns>` / `<exception>`: **one short clause each, only when the param/return/exception name doesn't carry it.**
- **`<exception>` tags must mirror the impl's branching precisely.** If a method throws *conditionally* - gated on a state field (`_disposed`, `_isCancelled`), an idempotency fast-path, or a race-window check that runs before the throw - the `<exception>` tag must spell out the gating condition. Bare "Throws X if invoked from state Y" when the impl is `if (alreadyDone) return; if (insideCallback) throw ...;` misleads callers (who code defensively against the unconditional claim) and gets flagged by reviewers (human or bot) as a doc/impl mismatch. Self-check: read the `<exception>` text aloud while looking at the throw site; if any path through the method that *doesn't* throw isn't implied by the doc, refine the doc (or strengthen the impl to honor it - usually the doc is wrong because the impl deliberately added an idempotency / race-exemption fast-path that the original doc never anticipated).
- **XML doc comments on NEW public/internal API: default OFF.** Only add when the type/method signature genuinely cannot express the contract - e.g., a non-obvious failure mode (`/// <returns>true on success; false if the OS denied the request - caller must surface to the user.</returns>`), or a non-obvious thread-safety guarantee. Method names like `TryGet...` / `...Async` / `Copy...` already encode their contract. Do NOT preemptively document "for future maintainers" - the signature IS the doc.
- **Existing XML doc comments stay** - don't reformat or expand them when touching surrounding code.

**Common XML-doc failure modes flagged in past reviews:**
- Adding `/// <summary>` to a private field "to explain the race-handling design." Wrong - rename the field or, if a single short line truly is needed, use a single `// ` above the field.
- Adding a 3-line XML `<summary>` paragraph on a new public interface explaining "implementations are best-effort, any failure is logged and swallowed so callers can fire-and-forget." This is contract prose that belongs in the PR description; the method signature + a `Task` return + the implementation's try/catch already say it. If "best-effort" really must be in the doc, write `/// <summary>Best-effort copy; failures are logged and swallowed.</summary>` - one sentence.
- Writing `/// <exception cref="InvalidOperationException">Thrown when invoked from inside a callback.</exception>` on a method whose body is `if (_disposed) return; if (insideCallback) throw new InvalidOperationException(...);` - the post-disposal callback path is a silent no-op, but the doc says the throw is unconditional. Reviewers (notably the GitHub Copilot PR reviewer) catch this on sight. Either weaken the doc to publish the conditional contract ("Thrown when invoked from inside a callback while the resource is still live; if another thread already disposed, the call is a silent no-op for IDisposable idempotency") or strengthen the impl to honor the doc.
- **TOCTOU (time-of-check-to-time-of-use) honesty in doc comments about filesystem / network / external-state freshness.** When a type carries paths, URLs, descriptors, handles, or any other reference to mutable external state whose value was verified at construction time, the XML doc MUST NOT claim that callers can "rely on" the verification holding at consumption time. The producer's check and the consumer's use are separated by an arbitrary wall-clock interval (often seconds in a UI event-handler → background-dispatch loop, or unbounded across IPC / queue / persistence boundaries), and the external state can change in that window. Misleading "live at moment of use" phrasing trains downstream callers to skip defensive handling that the runtime requires. **Pattern to apply** - replace the live-guarantee claim with the explicit two-part contract: (a) "Producer verified at construction time" + (b) "Consumer MUST still handle the state having changed since construction":
  ```csharp
  /// <summary>
  ///     Normalized result of inspecting a Windows app activation. <see cref="FilePaths"/> contains paths the producer
  ///     verified at construction time as pointing at existing <c>.dat</c> files. Producers SHOULD drop nonexistent
  ///     or inaccessible paths before construction (best-effort filtering), but consumers MUST still handle paths
  ///     that became missing, locked, or otherwise inaccessible AFTER construction - the verification is
  ///     point-in-time, not a live guarantee, and a TOCTOU window exists between producer-check and consumer-use.
  /// </summary>
  ```
  **Anti-pattern phrasings to grep for and rewrite:** "callers may rely on ...", "guaranteed to be live", "exists at the moment of activation", "always accessible", "verified to be present at use time". Each of these claims a freshness invariant the runtime cannot hold across a process boundary, a thread hop, or even a few microseconds of GC pause. The Copilot reviewer reliably flags these claims as misleading. **Self-check** when documenting a record / DTO / value type whose fields name external mutable state: read the doc aloud while imagining a 30-second pause between producer return and consumer use. If anything in the doc would be wrong after the pause, the doc is wrong now.

> Universal `//` comment failure-mode examples (e.g., the "Same best-effort contract as `CopySelectedEvent`" case) live in [Core / Comments](../../AGENTS.md#31-comments) under "Common failure modes flagged in past reviews" - not duplicated here.

---

## Project and solution structure (extends [Core / Project and library structure](coding-standards-code.instructions.md#311-project-and-library-structure))

The .NET ecosystem standard is `src/` for production projects and `tests/` for test projects, both directly under the repo root. The bullets below codify the .NET-specific details. When you encounter a repo whose layout deviates from this - production and test projects intermixed in the same directory, solution file in a nested subfolder, `Directory.Build.props` placed below the projects it should govern, integration tests not split out from unit tests into `tests/Unit/` + `tests/Integration/` - surface it via `ask_user` per `AGENTS.md` §3.11. Do not silently work around the deviation by adding extra `cd` steps in pipelines, custom `--working-directory` flags, or hand-maintained per-project lists.

- **Layout - `src/<Project>/` for production, `tests/<Project>.Tests/` for tests; per `AGENTS.md` §3.13, scaffold the `tests/Unit/` and `tests/Integration/` split up front as a structural decision.** Production projects live as `src/<Project>/<Project>.csproj`. Test projects live as `tests/Unit/<Project>.Tests/<Project>.Tests.csproj` (unit) or `tests/Integration/<Project>.IntegrationTests/<Project>.IntegrationTests.csproj` (integration). Integration test projects may remain empty until integration tests are written. When the same helper or constant is needed by ≥2 test projects, share it via a `tests/Shared/<Solution>.<Domain>.TestUtils/` class library (see `csharp-testing.instructions.md` *Tests - .NET test project layout*) - do not introduce new `<Compile Include="..\..\Unit\..." Link="..." />` cross-links.
- **Solution-level files live at the repo root.** `*.slnx` / `*.sln`, `Directory.Build.props`, `Directory.Packages.props`, `.editorconfig`, `global.json` all sit at the repo root so MSBuild's parent-directory walk picks them up for both the `src/` and `tests/` subtrees. **`IsTestProject` is not auto-detected from a `tests/` directory** - every test csproj must still declare `<IsTestProject>true</IsTestProject>` explicitly, otherwise a root-level `<ItemGroup Condition="'$(IsTestProject)' == 'true'">` block (typical home for shared `xunit` / `NSubstitute` / `coverlet.collector` `<PackageReference>`s) silently won't fire.
- **CI test isolation - classify by directory, not by `--filter` or csproj name globs.** When CI runs unit and integration suites as separate steps, enumerate per-project from the directory: `Get-ChildItem tests/Unit -Filter *.csproj -Recurse | ForEach-Object { dotnet test $_.FullName -c Release --no-build }` (and the symmetric loop for `tests/Integration`). **Do not** rely on `dotnet test <solution> --filter "FullyQualifiedName!~Integration"` to skip a suite - `--filter` runs *after* the test host has loaded every project in the solution, so a discovery-time failure in the supposedly-excluded project (missing dependency, native-interop init, slow assembly load) still fails the unit step. Naming-convention globs (`*Integration*.csproj`, `--filter "FullyQualifiedName!~..."`) are equally brittle: any project whose name accidentally matches the pattern is silently included or excluded with no error. With directory-based classification the pipeline has no list of project names to maintain, no aggregator file (no `.slnf`, no per-suite `.sln`) that can drift from disk, and adding a new test project means dropping it in the right folder - pipeline change is zero. Wrap each `dotnet test` invocation in a `try`/`catch` (or capture `$LASTEXITCODE` into a `$failed` flag and `throw` at the end) so one project's failure doesn't short-circuit the rest of the suite.
- **`dotnet sln add` / `dotnet sln remove` rewrite `*.slnx` from scratch and destroy XML comments.** Any `<!-- ... -->` annotation you put in `*.slnx` (e.g., a comment explaining a folder grouping or a deliberately-excluded project) will be silently dropped the next time someone adds or removes a project via the CLI. Either keep the explanation out of the slnx (put it in `CONTRIBUTING.md`, the repo `README`, or the `Directory.Build.props` it's actually about) or hand-edit the slnx and accept that the next `dotnet sln` invocation will erase it.

---

> **Test rules moved**: all C# test-infrastructure rules (test-project layout, per-project + shared <Solution>.<Domain>.TestUtils escape hatch, naming patterns, test-purpose / gap audit, mocking guidance, test-name intent, test synchronization, Testcontainers, alternatives surface) live in csharp-testing.instructions.md (loads only when test files are in the working set, narrower `applyTo` glob - see the AGENTS.md topic-file routing table).

## Access modifiers - least-permissive that still compiles

Default to the most-restrictive access modifier at every level. Promoting later expands the API surface and makes future tightening a breaking change; demoting later requires combing every consumer site (markup, reflection, DI, attributes, friend assemblies). Start tight; widen only when a real consumer demands it.

**Restrictive-to-permissive progression in C# - these are the six axes the cross-language audit playbook (`.github/playbooks/least-privilege-audit.md`) checks for every public type:**

- **Type:** `file > private (nested) > internal > protected internal > public`. Top-level types get `internal` by default; promote to `public` only when an external consumer actually exists.
- **Class modifier:** `sealed > unsealed`. Add `sealed` to every non-abstract class with no derivers in the same assembly. `sealed` enables compiler/JIT devirtualization and prevents accidental subclassing.
- **Constructor:** `private > internal > protected internal > public`. `Microsoft.Extensions.DependencyInjection` resolves constructors via `Type.GetConstructors()` (public-only) - DI-activated services registered with the built-in container **require a `public` constructor**. Third-party containers (Autofac, Lamar) can resolve non-public constructors; scope the `internal` ctor optimization to those only. Reflection-constructed types follow the same principle: match the accessibility to what the constructing framework actually calls.
- **Method / property:** `private > protected private > internal > protected internal > public`. A member only consumed within the declaring assembly should be `internal` even on a `public` type.
- **Property setter:** `init-only > no setter > private set > internal set > public set`. Default to `init` for state set in the constructor; promote only if mutation after construction is genuinely required.
- **Field:** `readonly` first, then `private > internal > public`. Public fields should almost never exist (use a property); the rare exception is `public const` or `public static readonly`.

**When the audit runs:**

- **At authoring** - pick the most restrictive modifier that satisfies the immediate consumer set; don't future-proof speculatively.
- **At end of a unit of work** - touched-file scope of the audit fires automatically as part of `post-code-change.md` (new `public` types/members must be justified or demoted before the diff is shown).
- **Before first review push** - branch-wide scope fires automatically as part of `pre-pr-push.md` when the branch touches public API surface across multiple files.
- **On demand** - user requests an "API tightening", "visibility audit", "least-privilege sweep", or similar; the canonical procedure is in `.github/playbooks/least-privilege-audit.md` (single source of truth).

**C#-specific reflection caveats - verify these still work after tightening:**

- **Fluxor** (`[FeatureState]`, `[ReducerMethod]`, `[EffectMethod]`) uses `Assembly.GetTypes()` (not `GetExportedTypes`), so internal types are discovered, but constructor/method visibility still matters - build + dispatcher round-trip after tightening. **EffectMethod signature is enforced at registration time:** when `[EffectMethod(typeof(SomeAction))]` is used (the typed form that doesn't infer action type from a parameter), the method MUST take exactly one parameter and it MUST be `IDispatcher` (`public async Task HandleX(IDispatcher dispatcher)`). Fluxor's `EffectMethodInfoFactory` throws `ArgumentException` at host startup if a parameterless signature slips in - unit tests that call the method directly will NOT catch it (they bypass Fluxor's binding). When adding or refactoring an `[EffectMethod(typeof(...))]`, verify the `IDispatcher` parameter is present even when the body doesn't use it.
- **`System.Text.Json` polymorphism / converters** - works for internal types in the same assembly; verify a round-trip from a consumer assembly when the converter or attribute crosses the assembly boundary.
- **EF Core** entity / converter discovery - works for internal types. **EF Core `DbContext`** subclasses are usually NOT sealed (runtime proxy generation needs vtable slots).
- **`Microsoft.Maui.Hosting` / `Microsoft.Extensions.DependencyInjection`** - works for internal types when the registering assembly has visibility (friend asm).
- **Generic component constraints in Razor** (e.g., `IModalService.Show<TModal, TResult> where TModal : IComponent`) - internal `TModal` works fine across friend assemblies.
- **Razor markup binding from another assembly** - `<InternalComponent />` works when IVT is granted; the Razor compiler in the consuming assembly resolves through friend visibility. Use `rg --type-add 'razor:*.razor' -t razor` (or `-t html`) when searching for Razor markup consumers, plus `_Imports.razor` and `@inherits` directives.
- **Razor `[Parameter]` properties** - must be `public` with a `public` setter (framework parameter binding asserts this). **`[CascadingParameter]`** is also framework-set, but Blazor's component activator uses non-public reflection and current versions accept non-public cascading parameters; verify with build + a render test before tightening. **`[Inject]`** properties can be non-public / `internal`; verify the injection still resolves after tightening. **`[JSInvokable]`** methods invoked from JavaScript must be `public` (the JS interop dispatcher uses public reflection).
- **Source generators** may have visibility assumptions; build after tightening.

**C#-specific friend-assembly mechanism:** when an `internal` type / member needs to be reachable from another assembly we own (test project, MAUI head consuming a UI service), grant access via `[InternalsVisibleTo("OtherAssembly")]`. Two declaration locations:

- **Preferred (.NET 5+):** csproj `<ItemGroup><InternalsVisibleTo Include="OtherAssembly" /></ItemGroup>`. SDK-style projects auto-generate the assembly-level attribute at build time, keeping `Properties/AssemblyInfo.cs` empty (or absent entirely).
- **Legacy:** `[assembly: InternalsVisibleTo("OtherAssembly")]` in `Properties/AssemblyInfo.cs`. Still works; migrate to csproj when convenient.

The audit playbook's hard gate "friend-asm mechanism verified before recommending internalization" applies in C# as: open the project's csproj AND `Properties/AssemblyInfo.cs` (if present) and confirm the IVT entry covers the friend you expect. Don't recommend `internal` without the grant in place; if missing, the recommendation is *internalize-and-add-IVT-entry*.

**C#-specific common misses caught in past reviews** (these are the failure-mode catalog the audit playbook's per-language tuning should catch):

- Service registered as `AddSingleton<IFoo, Foo>` declared `public class Foo` even though no caller outside the registering assembly references `Foo` directly → should be `internal sealed class Foo`.
- Razor component used only in same-assembly markup declared `public partial class MyComponent` → should be `internal sealed partial class MyComponent`.
- `public set` on a property only assigned in the constructor → change to `init`.
- `public static readonly` field with no consumer outside the assembly → demote to `internal static readonly`.
- Synthesized record `public` constructor on a type only constructed inside its assembly → demote both the record and its consumers' usage; record primary ctors inherit the record's declared accessibility, so making the record `internal` is enough.
- **`public sealed record FooAction(...)` for a Fluxor action only dispatched and reduced inside the declaring assembly → should be `internal sealed record FooAction(...)`.** Fluxor's reflection-based discovery works on internal types (it uses `Assembly.GetTypes()`, not `GetExportedTypes()`), so internal actions / reducers / effects are first-class. Cascade caveat: if the action is a method parameter on a `public` Reducer class, demoting the action requires demoting the Reducer class too (CS0051 "inconsistent accessibility"). Tests reference the action by type via `[InternalsVisibleTo]` IVT grant.

---

## File organization - split multi-type files when contents are unrelated

The default is **one top-level type per file**, with the filename matching the type name. Multi-type files are a maintenance hazard: they hide types from search-by-filename, conceal coupling, fight diff readability, and make `git mv` rename-tracking less reliable.

**Acceptable reasons to keep multiple types in one file:**
- **Tight pattern of related variants sharing private support.** Example: a private/internal base struct + a small set of public variant structs that all delegate to it (e.g., interpolated string handlers per log level sharing one private `LogHandlerCore`). Splitting would obscure the pattern and force the private base to widen.
- **Primary type with file-scoped support types it owns exclusively.** A `private` nested class, file-scoped record used only by the primary type's implementation, or `[JsonConverter]` paired with its converter type when the converter has no other consumers.
- **Single cohesive native API surface.** A file representing one native library's enum / flag / constant set (e.g., one file per Win32 module's `Evt*` enums for `wevtapi.dll`, one file per POSIX header's flag constants). The types are siblings of one external interface and travel together because they're audited together against external docs (MSDN, man pages). Document the exception with a one-line comment naming the API surface.
- **Generated / partial / source-generator files** that the tool requires to be co-located.

**Unacceptable patterns - always split:**
- Enums sitting alongside an unrelated class. P/Invoke flags enums (`EvtRenderFlags`, `LoadLibraryFlags`, etc.) belong in their own files in the `Interop/` folder, not bundled into `NativeMethods.cs` or a method wrapper class. One enum per file unless the enums form a tightly-related set (e.g., `HttpStatusCategory` + `HttpStatusCode` extension on the same concept).
- An interface bundled with an unrelated class (interfaces co-locate with their implementation when name-matched per the rules below, not with random helpers).
- Unrelated utility / helper types lumped together in a `Helpers/`-style file (e.g., `Helpers/EventMethods.cs` containing a P/Invoke wrapper + 12 unrelated enum definitions). Split into one-type-per-file and distribute by concern.
- Domain models stacked together "because they're small" - each model gets its own file; small files are fine.
- Records nested inside other records / classes that act as a fake namespace (e.g., `EventLogAction.AddEvent`, `EventLogAction.Clear` nested under a container record). Split into one record per file unless the nested type is genuinely private and only used by the outer type.

**Interface-and-implementation co-location (sibling pattern) - visibility gates the merge decision:**

The "sibling pattern" (interface + implementation in **one** file) is a narrow exception to the one-type-per-file default. Apply it ONLY when **all** of the following hold:
- Both the interface and the implementation are `internal` (or stricter - `file`/`private` nested).
- The implementation name is exactly `I` + interface name (`IFoo` + `Foo`).
- There is exactly one implementation in the same assembly, and the interface exists primarily as a testing or DI seam, not as a public contract.

When any of those conditions fails, **keep two files** in the same feature folder. Specifically:

- **Public interfaces always live in their own file.** Even when the impl name matches and the impl is in the same assembly, a `public interface` is part of the assembly's API surface; consumers (in this repo or downstream) navigate to it by file name (`IFoo.cs`), tooling (Go-to-File, source-link, NuGet docs, IntelliSense peek-definition) assumes one-public-type-per-file, and bundling it with the impl makes future tightening / a second implementation a noisier diff. This matches Microsoft's large repos, StyleCop SA1402/SA1649, and the vertical-slice convention.
- **Mismatched names always stay as two files** (`IFileLogger` + `DebugLogService`, `ILogWatcherService` + `LiveLogWatcherService`). The mismatch signals that the implementation has its own concept beyond "default impl of the interface".
- **Multiple implementations of one interface always stay as separate files** (one for the interface, one per impl).
- **Cross-assembly interfaces** (impl lives in a different assembly than the interface - e.g., `IActiveItemsProvider` defined in `Acme.Core` but implemented by `OrderService` in `Acme.UI`) **always stay in their own file** in the defining assembly, regardless of whether the consuming assembly happens to have a single matching impl.

**Folder placement is independent of file count.** Whether you co-locate into one file or keep two files, both belong in the **same feature folder** (`Services/User/IUserService.cs` + `Services/User/UserService.cs`, or `Services/User/UserService.cs` containing both). Avoid an `Interfaces/` folder - that's an "organize by kind" anti-pattern; organize by feature / domain concept instead.

**Restructure decision flow:**
1. Are both types `internal` (or stricter)? If no → two files in the feature folder.
2. Do the names match (`IFoo` ↔ `Foo`)? If no → two files in the feature folder.
3. Is there exactly one impl in the same assembly? If no → two files in the feature folder.
4. All three yes → single file using the sibling pattern (`internal interface IFoo` + `internal sealed class Foo : IFoo`), filename matches the implementation.

**When to evaluate file splits:**
- **At authoring:** if you're about to add a second top-level type to a file, ask whether the new type genuinely shares the file's purpose. If not, create a new file.
- **During reorgs / restructure passes:** scan every file for multi-type contents and apply the rules above. Document any deliberately retained multi-type files with a one-line comment explaining why (the "tight pattern" rationale).

---

## Folder organization - feature folders, no catch-all "Helpers" (extends [Core / Within-assembly folder topology](coding-standards-code.instructions.md#312-within-assembly-folder-topology-vertical-slice-clean-architecture))

`Helpers/`, `Utilities/`, `Misc/`, **flat `Common/`** (no sub-folders), and similar catch-all folders are anti-patterns: they collect unrelated code that has no other home, hide coupling, and grow without bound. Every file should live in a folder that names a domain concept or technical concern, not a generic bucket.

**Cross-cutting / cross-assembly domain types live in `Common/<Domain>/`** - not in flat `Common/` and not in any slice folder. The parent `Common/` is a navigational marker; the `<Domain>/` sub-folder (`Common/Events/`, `Common/Channels/`, `Common/Databases/`) is the actual domain-named feature folder per the rule. Sub-divide `Common/` by DOMAIN, not by KIND (no `Common/Models/` + `Common/Helpers/`). See [Core §3.12](coding-standards-code.instructions.md#312-within-assembly-folder-topology-vertical-slice-clean-architecture) for the full topology rule and [§3.13](coding-standards-code.instructions.md#313-plan-structure-for-growth-not-for-current-file-count) for the plan-for-growth threshold (create the sub-folder up front when you can name 2+ likely additions).

**Standard folder conventions per project type:**
- **.NET class libraries (domain-library style):** feature folders (`PayloadResolvers/`, `Providers/`, `Readers/`), `Common/<Domain>/` for cross-slice domain types (DTOs, contracts, well-known constants, algorithm helpers), `Interop/` for P/Invoke + handles + native structs (per FxCop CA1060), `Logging/` for tracing primitives, `Extensions/` for true extension method classes (named `*Extensions`, not `*Methods`). Avoid `Models/` as a flat catch-all - distribute slice-internal models into their owning feature folder, and cross-slice models into `Common/<Domain>/`.
- **Blazor component libraries:** components grouped by feature / page area; shared layout components in `Layout/`; modals in `Modals/`; small reusable presentational components in `Controls/` or grouped with their consumers.
- **Fluxor state stores:** `Store/<FeatureName>/` per Fluxor official tutorial - one folder per feature containing `<Feature>State.cs`, `Effects.cs`, `Reducers.cs`, and one file per action record. Drop the feature prefix from `Effects` / `Reducers` class names since the folder already namespaces them.
- **MAUI heads:** `Layout/` (MainLayout, exception handler), `Panels/` or feature-named folders for major UI sections; avoid wrapping everything in a `Components/` parent.
- **Console / CLI tools:** `Commands/` for command handlers, `Sources/` or feature folders for data sources; `Program.cs` at root.

**`InternalsVisibleTo` placement:** in csproj, not `Properties/AssemblyInfo.cs`. Csproj keeps the friend-asm policy visible alongside dependencies, survives reorgs, and avoids a near-empty `AssemblyInfo.cs` whose only contents are IVT directives. Use:
```xml
<ItemGroup>
  <InternalsVisibleTo Include="OtherAssembly" />
</ItemGroup>
```
Delete `Properties/AssemblyInfo.cs` if IVT was its only content.

**Naming conventions for utility classes:**
- Extension method classes: `<TypeName>Extensions` (e.g., `StringExtensions`, `LogEntryExtensions`), not `<TypeName>Methods`.
- P/Invoke classes: `NativeMethods` (per FxCop CA1060), `internal static class`. Split per native API surface when one file gets large (`NativeMethods.Evt.cs`, `NativeMethods.Wevtapi.cs` as partials, or separate classes if no shared state).
- Constants / defaults: `<Domain>Defaults` or `<Domain>Constants`, grouped in a `Defaults/` or `Constants/` folder when there are multiple.

**When to evaluate folder structure:**
- **At project creation:** lay out the folder convention up front per the project type above.
- **At every reorg PR:** validate against the conventions; document deliberate deviations with rationale in PR description.
- **Whenever a `Helpers/` or `Utilities/` folder appears:** treat as a refactor signal. Each file in it should move to a feature folder, an `Extensions/`, an `Interop/`, or be promoted to a domain concept folder.

---

## Argument validation - validate at the public boundary

A public factory that forwards its argument into a validating constructor leaks the *constructor's* parameter name to a caller who never passed it: `Create(string name) => new Foo(name)` (where `Foo`'s ctor calls `ArgumentException.ThrowIfNullOrEmpty(value)`) throws `ParamName` `"value"` on `Create("")`, a name the caller never used. Validate up front (`ArgumentException.ThrowIfNullOrEmpty(name)`) so the thrown `ParamName` names the caller-visible parameter.

---

