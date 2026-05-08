---
applyTo: "**/*.cs,**/*.csx,**/*.csproj,**/*.razor,**/*.razor.cs,**/*.cshtml,**/*.aspx"
---

# C# / .NET Instructions

> **Scope:** loaded automatically when the working set contains C# / Razor / project files. Extends the always-loaded `AGENTS.md` core. Where this file references the core, links use the form `[Core / X](../../AGENTS.md#anchor)` — the universal version of the rule lives there, and the bullets here are C#-specific additions or refinements.

---

## Comments — XML doc additions (extends [Core / Comments](../../AGENTS.md#31-comments))

The universal comment rules in `AGENTS.md` (rename-first protocol, no comments that restate code, no narration, no future-tense speculation, no TODO/FIXME/HACK, hard ≤ 12-word inline cap, mandatory self-review pass) all apply here unchanged. The bullets below are the C#-specific additions for XML doc comments.

- **No XML doc comments (`/// <summary>...`) on `private` members.** Period. Not on private fields, not on private methods, not on private nested types. The XML-doc-on-private-field is the most common violation. If the field needs explanation, the *name* needs work.
- XML docs that restate the method signature are forbidden the same way prose comments that restate code are: `/// <summary>Copies text to the clipboard.</summary>` on `Task CopyTextAsync(string text)` says nothing the signature doesn't.
- **Hard length caps for XML docs:**
  - `<summary>` on public/internal members: **one sentence.** No paragraphs. No `<para>`. No bullet lists. If the contract takes more than a sentence, the API is doing too much — split the method.
  - `<param>` / `<returns>` / `<exception>`: **one short clause each, only when the param/return/exception name doesn't carry it.**
- **`<exception>` tags must mirror the impl's branching precisely.** If a method throws *conditionally* — gated on a state field (`_disposed`, `_isCancelled`), an idempotency fast-path, or a race-window check that runs before the throw — the `<exception>` tag must spell out the gating condition. Bare "Throws X if invoked from state Y" when the impl is `if (alreadyDone) return; if (insideCallback) throw …;` misleads callers (who code defensively against the unconditional claim) and gets flagged by reviewers (human or bot) as a doc/impl mismatch. Self-check: read the `<exception>` text aloud while looking at the throw site; if any path through the method that *doesn't* throw isn't implied by the doc, refine the doc (or strengthen the impl to honor it — usually the doc is wrong because the impl deliberately added an idempotency / race-exemption fast-path that the original doc never anticipated).
- **XML doc comments on NEW public/internal API: default OFF.** Only add when the type/method signature genuinely cannot express the contract — e.g., a non-obvious failure mode (`/// <returns>true on success; false if the OS denied the request — caller must surface to the user.</returns>`), or a non-obvious thread-safety guarantee. Method names like `TryGet…` / `…Async` / `Copy…` already encode their contract. Do NOT preemptively document "for future maintainers" — the signature IS the doc.
- **Existing XML doc comments stay** — don't reformat or expand them when touching surrounding code.

**Common XML-doc failure modes flagged in past reviews:**
- Adding `/// <summary>` to a private field "to explain the race-handling design." Wrong — rename the field or, if a single short line truly is needed, use a single `// ` above the field.
- Adding a 3-line XML `<summary>` paragraph on a new public interface explaining "implementations are best-effort, any failure is logged and swallowed so callers can fire-and-forget." This is contract prose that belongs in the PR description; the method signature + a `Task` return + the implementation's try/catch already say it. If "best-effort" really must be in the doc, write `/// <summary>Best-effort copy; failures are logged and swallowed.</summary>` — one sentence.
- Writing `/// <exception cref="InvalidOperationException">Thrown when invoked from inside a callback.</exception>` on a method whose body is `if (_disposed) return; if (insideCallback) throw new InvalidOperationException(…);` — the post-disposal callback path is a silent no-op, but the doc says the throw is unconditional. Reviewers (notably the GitHub Copilot PR reviewer) catch this on sight. Either weaken the doc to publish the conditional contract ("Thrown when invoked from inside a callback while the resource is still live; if another thread already disposed, the call is a silent no-op for IDisposable idempotency") or strengthen the impl to honor the doc.

> Universal `//` comment failure-mode examples (e.g., the "Same best-effort contract as `CopySelectedEvent`" case) live in [Core / Comments](../../AGENTS.md#31-comments) under "Common failure modes flagged in past reviews" — not duplicated here.

---

## Project and solution structure (extends [Core / Project and library structure](../../AGENTS.md#311-project-and-library-structure))

The .NET ecosystem standard is `src/` for production projects and `tests/` for test projects, both directly under the repo root. The bullets below codify the .NET-specific details. When you encounter a repo whose layout deviates from this — production and test projects intermixed in the same directory, solution file in a nested subfolder, `Directory.Build.props` placed below the projects it should govern, integration tests not split out from unit tests despite having more than ~2 test projects — surface it via `ask_user` per `AGENTS.md` §3.11. Do not silently work around the deviation by adding extra `cd` steps in pipelines, custom `--working-directory` flags, or hand-maintained per-project lists.

- **Layout — `src/<Project>/` for production, `tests/<Project>.Tests/` for tests; split into `tests/Unit/` and `tests/Integration/` once there are more than ~2 test projects.** Production projects live as `src/<Project>/<Project>.csproj`. Test projects live as `tests/Unit/<Project>.Tests/<Project>.Tests.csproj` (unit) or `tests/Integration/<Project>.IntegrationTests/<Project>.IntegrationTests.csproj` (integration). Cross-link sources from one test project into another only when the link is genuinely shared infrastructure (e.g., `<Compile Include="..\..\Unit\<Project>.Tests\TestUtils\Constants\Constants.Foo.cs" Link="TestUtils\Constants\Constants.Foo.cs" />`); duplicate the constant when the integration suite needs to drift from the unit suite.
- **Solution-level files live at the repo root.** `*.slnx` / `*.sln`, `Directory.Build.props`, `Directory.Packages.props`, `.editorconfig`, `global.json` all sit at the repo root so MSBuild's parent-directory walk picks them up for both the `src/` and `tests/` subtrees. **`IsTestProject` is not auto-detected from a `tests/` directory** — every test csproj must still declare `<IsTestProject>true</IsTestProject>` explicitly, otherwise a root-level `<ItemGroup Condition="'$(IsTestProject)' == 'true'">` block (typical home for shared `xunit` / `NSubstitute` / `coverlet.collector` `<PackageReference>`s) silently won't fire.
- **CI test isolation — classify by directory, not by `--filter` or csproj name globs.** When CI runs unit and integration suites as separate steps, enumerate per-project from the directory: `Get-ChildItem tests/Unit -Filter *.csproj -Recurse | ForEach-Object { dotnet test $_.FullName -c Release --no-build }` (and the symmetric loop for `tests/Integration`). **Do not** rely on `dotnet test <solution> --filter "FullyQualifiedName!~Integration"` to skip a suite — `--filter` runs *after* the test host has loaded every project in the solution, so a discovery-time failure in the supposedly-excluded project (missing dependency, native-interop init, slow assembly load) still fails the unit step. Naming-convention globs (`*Integration*.csproj`, `--filter "FullyQualifiedName!~..."`) are equally brittle: any project whose name accidentally matches the pattern is silently included or excluded with no error. With directory-based classification the pipeline has no list of project names to maintain, no aggregator file (no `.slnf`, no per-suite `.sln`) that can drift from disk, and adding a new test project means dropping it in the right folder — pipeline change is zero. Wrap each `dotnet test` invocation in a `try`/`catch` (or capture `$LASTEXITCODE` into a `$failed` flag and `throw` at the end) so one project's failure doesn't short-circuit the rest of the suite.
- **`dotnet sln add` / `dotnet sln remove` rewrite `*.slnx` from scratch and destroy XML comments.** Any `<!-- ... -->` annotation you put in `*.slnx` (e.g., a comment explaining a folder grouping or a deliberately-excluded project) will be silently dropped the next time someone adds or removes a project via the CLI. Either keep the explanation out of the slnx (put it in `CONTRIBUTING.md`, the repo `README`, or the `Directory.Build.props` it's actually about) or hand-edit the slnx and accept that the next `dotnet sln` invocation will erase it.

---

## Tests — .NET test project layout (extends [Core / Tests and Benchmarks](../../AGENTS.md#34-tests-and-benchmarks))

The universal test rules in `AGENTS.md` (descriptive method names as full sentences, deterministic timestamps, add/update unit tests with code) all apply here unchanged. The bullets below are .NET-specific.

- **Test project layout — `TestUtils` folder convention.** Every test project uses a `TestUtils/` folder for shared test infrastructure:
  - Reusable helper classes (factories, fakes, builders, IO/HTTP/compression helpers) live directly under `TestUtils/` as `<Topic>Utils.cs` (e.g., `EventUtils.cs`, `FilterUtils.cs`, `HttpUtils.cs`, `DeploymentUtils.cs`).
  - Shared constants live under `TestUtils/Constants/` as topic-grouped partial-class files named `Constants.<Topic>.cs` (e.g., `Constants.Provider.cs`, `Constants.Resolver.cs`, `Constants.Database.cs`, `Constants.Filter.cs`).
  - Each constants file declares `public sealed partial class Constants` in namespace `<Project>.Tests.TestUtils.Constants` and exposes `public const string` (or other const) members. Tests reference them via `Constants.Foo`.
  - Each test project has its own `TestUtils/` (do not share across projects).
- **Extract duplicated test values into the shared `TestUtils/Constants` location.** When the same non-trivial literal (provider names, task/keyword/message names, descriptions, parameter values, template fragments like `"<template></template>"`, log names, paths) appears in two or more tests — whether in the same file or across files — add it to the appropriate `Constants.<Topic>.cs` partial (creating a new topic file if none fits) and reference via `Constants.Foo`. **Do NOT declare per-test-class `private const` blocks at the top of test files** — keep test files focused on test logic so values are discoverable and reusable by future tests. Trivial values (empty string, single characters, well-known sentinels like `"main"`) and strings that genuinely must differ between tests are exempt.

---

## Test purpose — every test pays for its existence

The universal test-specificity and negative-assertion rules in `AGENTS.md` apply unchanged. The bullets below codify *why a test should exist at all* and what to delete during test-quality audits. Tests are code; coverage for coverage's sake is a maintenance liability that gives false confidence and slows future refactors.

**The default is intent-driven, thorough tests — not coverage-driven filler.** Every test (new or existing) must justify itself by naming the regression it would catch *and* exercising the actual behavior it claims to guard. A "negative" test that does not include the stimulus it's meant to disprove is vacuous — it only proves "the system was quiet for N ms", which is trivially true on most CI runs. A "positive" test whose assertion is structurally guaranteed by the preceding code (or by the production return type) is tautological. **Coverage-driven tests are appropriate only when the user explicitly asks for "complete code coverage" or a coverage sweep** — and even then, prefer expanding the SUT's documented surface (so existing intent-driven tests cover more) over adding filler tests that pin uninteresting behavior. When in doubt about whether a coverage gap is worth a test, ask via `ask_user`.

**A test is worth keeping only if it would catch a real regression.** Before writing or keeping a test, answer: "What concrete behavior change in the SUT would make this test fail?" If the answer is "I can't think of one without changing the test itself", delete or rewrite.

**Do NOT test:**
- **Trivial getters / setters / pass-through methods.** A test that does `x.Foo = 1; Assert.Equal(1, x.Foo);` verifies the language compiler, not your code. Same for properties whose only logic is `=> _field`.
- **Framework code.** Don't test that EF Core saves entities, that `System.Text.Json` serializes a record, that `IServiceCollection.AddSingleton` registers a service. Test *your* code that integrates with the framework.
- **Private implementation details.** Tests that pin internal data structures, private method signatures, or specific algorithm steps break on every refactor without catching real regressions. Test observable behavior through the public contract.
- **Mock setup verification.** A test that does `mock.Setup(x => x.Foo()).Returns(42)` then asserts `mock.Foo() == 42` tests NSubstitute, not the SUT. The SUT must be involved between Arrange and Assert.
- **Tautologies.** `Assert.Equal(x, x)`, `Assert.True(true)`, `Assert.NotNull(new Foo())` (constructor null-returning is impossible in C# without exceptions). If the assertion is structurally guaranteed by the code preceding it, delete the test.
- **Generated code.** `[GeneratedRegex]`, source-generator output, designer-generated partials. Test the inputs and the consumed outputs, not the generator.
- **Auto-implemented `record` `Equals`/`GetHashCode`/`ToString` for the trivial cases.** Test these only when you've manually overridden them or when value semantics are a load-bearing contract that consumers depend on.

**DO test:**
- **Boundary conditions.** Empty/null/single-element collections, min/max numeric values, max string lengths, off-by-one boundaries (e.g., the `>=` vs `>` boundary in pagination, time-window cutoffs).
- **Failure paths.** The branches reviewers are most likely to break: error returns from native interop, `try`/`catch` fallback paths, retry logic, cancellation, partial failure in batch operations. These are *higher* value than happy-path tests.
- **Integration seams.** Where YOUR code talks to a dependency: cache hit vs miss, fallback chain ordering, eviction semantics, concurrent access coalescence. The interesting bugs live at these seams.
- **Public contract — input → output.** For every documented behavior in XML doc comments, there should be at least one test exercising it. Doc-comment-driven test discovery is a useful audit lens.
- **State transitions.** Before/after a method call, idempotency under repeated calls, ordering guarantees. Especially for stateful services and Fluxor reducers.
- **Concurrency contracts.** Where the type claims thread-safety, prove it under contention. Where it doesn't claim thread-safety, document the assumption and don't write a multi-threaded test that hides a real bug behind timing.
- **Exercise the negative case, don't infer it.** A test that claims *"no event arrives after Disable"* must actually write an event after the Disable; a test that claims *"no callback fires when not subscribed"* must actually fire the source the callback would have observed. A bounded-timeout wait with no stimulus only proves the system was quiet for N milliseconds — which is trivially true on most CI runs and false-passes when the asserted behavior is broken. The pattern is: arrange the watcher → cause the disable/unsubscribe/etc. → snapshot the count → reset the signal → **emit the would-be trigger** → wait for either the signal or the timeout → assert `Assert.False(received, "...")` *and* the count is unchanged. Same energy as the negative-assertion rule in `AGENTS.md`: assert the contract — *including the contract's trigger* — not its absence in a vacuum.
- **Race tests must exercise the protected code path, not the early-return guard.** When a SUT has a fast-path early-return (`Interlocked.CompareExchange`, `if (_disposed != 0) return;`, `if (_isCancelled) return;`, double-checked-locking idempotency check), a "race-N-threads-on-method-X" test can falsely pass even when the protected code is broken — every losing thread short-circuits at the guard before reaching the racy code path. Before claiming a test guards a race, trace the code: which call site actually exercises the race window? Often it's a *different* method (or a different parameter shape) whose entry doesn't hit the same guard. Concrete example: a `Dispose()` with an `Interlocked.CompareExchange(ref _disposed, 1, 0)` gate at the top serializes Dispose-vs-Dispose; a "race four `Dispose()` calls" test is a placebo for any teardown race the lock inside `Dispose(bool)`'s `if (disposing)` branch is meant to protect — only one thread ever reaches the protected code. The actual race window is between two callers that *bypass* the `_disposed` gate — e.g., two public stop-method callers, or a stop-method racing with `Dispose()`. **Test design rule**: when adding a regression test for a concurrency fix, locally revert the fix and confirm the test FAILS. If the test still passes with the fix reverted, it isn't testing the fix — it's testing some other guard that already ran.

**Test smells — refactor or delete:**
- **Eager tests.** One test method exercising 3 unrelated behaviors (`Test_DoesXAndYAndZ`). Split into 3 focused tests with names that read as specifications. Multi-asserts are OK only when verifying related state of *one* outcome (`result.Status == Success && result.Count == 5 && result.Errors.IsEmpty`).
- **Mystery guest data.** Test inputs hidden in a builder/fixture/JSON file far from the test body, where the reader can't tell what's load-bearing for the assertion. Inline the data, or make the fixture name self-documenting (`AnEventWithNoMatchingProvider()` not `BuildEvent()`).
- **Conditional logic in tests.** `if`, `foreach`, `switch`, `Skip` in test bodies usually signals two tests pretending to be one (or a missing `[Theory]`). Convert loops to `[Theory]` + `[InlineData]`; convert conditionals to separate test methods.
- **Magic values without explanation.** A literal `0x3A9D` in an assert needs a `nameof(SomeNamedConstant)` reference or a comment explaining why that exact value is the expected outcome.
- **Brittle ordering / count assertions on diagnostic logs.** `mock.Received(3).LogTrace(...)` breaks every time someone adds a log line that doesn't change behavior. Assert log content (the message that proves the path was taken) at most once, or don't assert on logs at all if there's a stronger observable to check.
- **Slow tests masquerading as unit tests.** A "unit test" that opens a real SQLite database, hits the file system, or sleeps is an integration test. Move to the integration suite or replace the dependency with an in-memory fake. Unit tests should be < 100ms each.
- **Tests that pass when the SUT is deleted.** Run the test mentally after `throw new NotImplementedException();` is the only thing in the SUT. If it still passes (e.g., it only verified mock setups, or it only asserted that an exception was thrown without checking which one), the test has no purpose.

**Mocking guidance:**
- **Mock at architectural boundaries** — databases, HTTP, file system, time, native interop, message queues. These are the interfaces you control; substituting them keeps tests fast and deterministic.
- **Do NOT mock value objects, DTOs, simple data structures, or types you own that are pure functions.** Construct real instances. Mocking a record / struct / model class is almost always a smell.
- **Do NOT mock the SUT.** If you find yourself mocking part of the type under test, the type has too many responsibilities — split it.
- **Do NOT mock methods on classes you don't own without an interface seam.** Wrap them in your own interface first; then mock that.
- **Verify behavior, not implementation.** Assert what the SUT *did* (the side effect on the mock that consumers observe), not how it called internal helpers. `Received(1)` on a single boundary call is fine; `Received(N)` on a chain of internal helper calls is brittle.

**Coverage as guide, not goal:**
- 100% coverage on critical paths and complex branching logic is the target.
- 0% coverage on trivial code (auto-properties, single-line wrappers) is fine and preferred over filler tests.
- A high coverage number with mostly trivial-getter tests is *worse* than a lower number with high-value tests, because it hides the real coverage gaps.
- When evaluating a coverage report, ignore the percentage and look at the uncovered lines: are the uncovered lines important behavior? If yes, write tests. If no (auto-property, exception branch that can't be reached, dead code), don't.

**When to evaluate test purpose:**
- **At authoring:** before writing each test, articulate the regression it would catch in one sentence. If you can't, don't write it.
- **During every test-mirror / refactor PR:** audit the existing tests in scope. Delete tests that fail the "what regression would this catch" question. Rewrite eager tests as focused tests. Move slow tests out of the unit suite.
- **When a test breaks during a refactor with no behavior change:** that test was probably testing implementation, not behavior. Fix or delete the test rather than reverting the refactor.

---

## Async, disposal, and JS interop lifecycle (Blazor / .NET)

These patterns recur in every Blazor + JS-interop PR review. Apply them whenever touching a `.razor.cs`, `IJSRuntime`, `DotNetObjectReference`, `IAsyncDisposable`, or any fire-and-forget async path.

- **`Lazy<Task<T>>` caches fault forever.** If the task throws, the same faulted task is handed to every future caller. Never use `Lazy<Task<T>>` for a cache that must be retryable. Prefer an explicit "produce-then-cache-on-success" pattern that re-runs on failure.
- **`DotNetObjectReference` ownership**: whichever object creates the reference owns disposing it. If you hand it to JS, dispose it in the same scope's tear-down (`DisposeAsync` / `UnregisterAsync`). Do not let it dangle when the component re-renders.
- **Narrow catches around JS interop.** Catch `JSDisconnectedException` and `TaskCanceledException` (and `OperationCanceledException`) specifically — never a bare `catch` or `catch (Exception)`. The first two are expected during teardown / circuit loss; everything else is a real bug and must surface.
- **`AbortController` for JS event listeners.** When wiring `addEventListener` from .NET, pair it with an `AbortController` (or symmetric `removeEventListener`) so listeners detach when the component disposes. Otherwise the page leaks listeners across navigation.
- **Fire-and-forget must be deliberate.** `_ = SomeAsync()` is acceptable only when (a) the call is idempotent or has its own error handling, and (b) you've added `.ConfigureAwait(false)` and a `.catch(...)` / try-catch that logs. Plain `SomeAsync();` without `await` and without a discard is a bug — Copilot reviewer flags it on sight.
- **`invokeMethodAsync` from JS needs `.catch(() => {})`** at minimum (preferably with logging) — otherwise a disconnected circuit produces an unhandled promise rejection in the browser.
- **`DisposeAsync` vs domain-specific tear-down.** If a service has a meaningful "stop using me but stay alive" operation (e.g., `UnregisterAsync`, `CloseAsync`), do not collapse it into `DisposeAsync`. `DisposeAsync` is for terminal cleanup; the domain method is for revocable lifecycle.
- **`[Parameter]` properties are framework-owned — never mutate them.** Compute a derived value or copy into a local field; do not assign to a `[Parameter]` from `OnParametersSetAsync`, `OnInitialized`, or any handler. Blazor will overwrite your value on the next render and the bug surfaces as "value snaps back".
- **`Dispose(bool disposing)` must release every owned `IDisposable` field — including kernel-handle wrappers like `AutoResetEvent` / `ManualResetEvent` / `SemaphoreSlim` / `EventWaitHandle`.** A class that owns a `private readonly AutoResetEvent _signal = new(false);` field but doesn't call `_signal.Dispose()` in its `Dispose(bool)` method leaks the underlying OS event handle on every instance lifetime. The garbage collector's finalizer will eventually release the handle, but: (a) finalizer collection is non-deterministic and can lag arbitrarily under allocation pressure, exhausting the per-process kernel-handle budget on long-lived hosts; (b) any class implementing `IDisposable` is documented to release unmanaged resources promptly, and the GC fallback is not part of the contract callers can rely on. **Audit lens**: when reviewing a `Dispose(bool)`, list every field in the class and check each against the disposing block — especially `WaitHandle` subclasses (their `Dispose` releases the `SafeWaitHandle` / kernel handle), `Stream` subclasses, `HttpClient`, `CancellationTokenSource`, `Timer`, and any custom `IDisposable` you constructed in the constructor. **Ordering matters**: dispose handles AFTER tearing down anything that references them. A `RegisteredWaitHandle` registered against an `AutoResetEvent` must be `Unregister`'d-and-drained before the `AutoResetEvent` is disposed, otherwise the threadpool callback can hit `ObjectDisposedException` mid-flight. The sequence is teardown → drain → release.

---

## Access modifiers — least-permissive that still compiles

Default to the most-restrictive access modifier at every level. Promoting later expands the API surface, ties the codebase to consumers you didn't intend to support, and makes future tightening a breaking change. Demoting later requires combing through every consumer site (markup, reflection, DI, attributes, friend assemblies). Start tight; widen only when a real consumer demands it.

**Restrictive-to-permissive progression in C# — these are the six axes the cross-language audit playbook (`.github/playbooks/least-privilege-audit.md`) checks for every public type:**

- **Type:** `file > private (nested) > internal > protected internal > public`. Top-level types get `internal` by default; promote to `public` only when an external consumer actually exists.
- **Class modifier:** `sealed > unsealed`. Add `sealed` to every non-abstract class with no derivers in the same assembly. `sealed` enables compiler/JIT devirtualization and prevents accidental subclassing.
- **Constructor:** `private > internal > protected internal > public`. DI-instantiated services and reflection-constructed types rarely need a `public` ctor — `internal` is enough when the friend-asm relationship covers the registering assembly.
- **Method / property:** `private > protected private > internal > protected internal > public`. A member only consumed within the declaring assembly should be `internal` even on a `public` type.
- **Property setter:** `init-only > no setter > private set > internal set > public set`. Default to `init` for state set in the constructor; promote only if mutation after construction is genuinely required.
- **Field:** `readonly` first, then `private > internal > public`. Public fields should almost never exist (use a property); the rare exception is `public const` or `public static readonly`.

**When the audit runs:**

- **At authoring** — pick the most restrictive modifier that satisfies the immediate consumer set; don't future-proof speculatively.
- **At end of a unit of work** — touched-file scope of the audit fires automatically as part of `post-code-change.md` (any new `public` type/member must be justified by a real consumer or demoted before the diff is shown).
- **Before first review push** — branch-wide scope of the audit fires automatically as part of `pre-pr-push.md` when the branch touches public API surface across multiple files.
- **On demand** — user requests an "API tightening", "visibility audit", "least-privilege sweep", or similar; the canonical procedure is in `.github/playbooks/least-privilege-audit.md` (single source of truth — do NOT re-derive the 6-axis matrix here).

**C#-specific reflection caveats — verify these still work after tightening:**

- **Fluxor** (`[FeatureState]`, `[ReducerMethod]`, `[EffectMethod]`) uses `Assembly.GetTypes()` (not `GetExportedTypes`), so internal types are discovered, but constructor/method visibility still matters — build + dispatcher round-trip after tightening.
- **`System.Text.Json` polymorphism / converters** — works for internal types in the same assembly; verify a round-trip from a consumer assembly when the converter or attribute crosses the assembly boundary.
- **EF Core** entity / converter discovery — works for internal types. **EF Core `DbContext`** subclasses are usually NOT sealed (runtime proxy generation needs vtable slots).
- **`Microsoft.Maui.Hosting` / `Microsoft.Extensions.DependencyInjection`** — works for internal types when the registering assembly has visibility (friend asm).
- **Generic component constraints in Razor** (e.g., `IModalService.Show<TModal, TResult> where TModal : IComponent`) — internal `TModal` works fine across friend assemblies.
- **Razor markup binding from another assembly** — `<InternalComponent />` works when IVT is granted; the Razor compiler in the consuming assembly resolves through friend visibility. Use `rg --type-add 'razor:*.razor' -t razor` (or `-t html`) when searching for Razor markup consumers, plus `_Imports.razor` and `@inherits` directives.
- **Razor `[Parameter]` properties** — must be `public` with a `public` setter (framework parameter binding asserts this). **`[CascadingParameter]`** is also framework-set, but Blazor's component activator uses non-public reflection and current versions accept non-public cascading parameters; verify with build + a render test before tightening (some house styles still keep them public for consistency — codify your stance per project). **`[Inject]`** properties can be non-public / `internal`; verify the injection still resolves after tightening. **`[JSInvokable]`** methods invoked from JavaScript must be `public` (the JS interop dispatcher uses public reflection).
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

---

## File organization — split multi-type files when contents are unrelated

The default is **one top-level type per file**, with the filename matching the type name. Multi-type files are a maintenance hazard: they hide types from search-by-filename, conceal coupling, fight diff readability, and make `git mv` rename-tracking less reliable.

**Acceptable reasons to keep multiple types in one file:**
- **Tight pattern of related variants sharing private support.** Example: a private/internal base struct + a small set of public variant structs that all delegate to it (e.g., interpolated string handlers per log level sharing one private `LogHandlerCore`). Splitting would obscure the pattern and force the private base to widen.
- **Primary type with file-scoped support types it owns exclusively.** A `private` nested class, file-scoped record used only by the primary type's implementation, or `[JsonConverter]` paired with its converter type when the converter has no other consumers.
- **Single cohesive native API surface.** A file representing one native library's enum / flag / constant set (e.g., one file per Win32 module's `Evt*` enums for `wevtapi.dll`, one file per POSIX header's flag constants). The types are siblings of one external interface and travel together because they're audited together against external docs (MSDN, man pages). Document the exception with a one-line comment naming the API surface.
- **Generated / partial / source-generator files** that the tool requires to be co-located.

**Unacceptable patterns — always split:**
- Enums sitting alongside an unrelated class. P/Invoke flags enums (`EvtRenderFlags`, `LoadLibraryFlags`, etc.) belong in their own files in the `Interop/` folder, not bundled into `NativeMethods.cs` or a method wrapper class. One enum per file unless the enums form a tightly-related set (e.g., `HttpStatusCategory` + `HttpStatusCode` extension on the same concept).
- An interface bundled with an unrelated class (interfaces co-locate with their implementation when name-matched per the rules below, not with random helpers).
- Unrelated utility / helper types lumped together in a `Helpers/`-style file (e.g., `Helpers/EventMethods.cs` containing a P/Invoke wrapper + 12 unrelated enum definitions). Split into one-type-per-file and distribute by concern.
- Domain models stacked together "because they're small" — each model gets its own file; small files are fine.
- Records nested inside other records / classes that act as a fake namespace (e.g., `EventLogAction.AddEvent`, `EventLogAction.Clear` nested under a container record). Split into one record per file unless the nested type is genuinely private and only used by the outer type.

**Interface-and-implementation co-location (sibling pattern) — visibility gates the merge decision:**

The "sibling pattern" (interface + implementation in **one** file) is a narrow exception to the one-type-per-file default. Apply it ONLY when **all** of the following hold:
- Both the interface and the implementation are `internal` (or stricter — `file`/`private` nested).
- The implementation name is exactly `I` + interface name (`IFoo` + `Foo`).
- There is exactly one implementation in the same assembly, and the interface exists primarily as a testing or DI seam, not as a public contract.

When any of those conditions fails, **keep two files** in the same feature folder. Specifically:

- **Public interfaces always live in their own file.** Even when the impl name matches and the impl is in the same assembly, a `public interface` is part of the assembly's API surface; consumers (in this repo or downstream) navigate to it by file name (`IFoo.cs`), tooling (Go-to-File, source-link, NuGet docs, IntelliSense peek-definition) assumes one-public-type-per-file, and bundling it with the impl makes future tightening / a second implementation a noisier diff. This matches Microsoft's own large repos (.NET runtime, ASP.NET Core, EF Core), StyleCop SA1402/SA1649, and the "vertical slice / feature folder" convention.
- **Mismatched names always stay as two files** (`IFileLogger` + `DebugLogService`, `ILogWatcherService` + `LiveLogWatcherService`). The mismatch signals that the implementation has its own concept beyond "default impl of the interface".
- **Multiple implementations of one interface always stay as separate files** (one for the interface, one per impl).
- **Cross-assembly interfaces** (impl lives in a different assembly than the interface — e.g., `IDatabaseCollectionProvider` defined in `EventLogExpert.Eventing` but implemented by `DatabaseService` in `EventLogExpert.UI`) **always stay in their own file** in the defining assembly, regardless of whether the consuming assembly happens to have a single matching impl.

**Folder placement is independent of file count.** Whether you co-locate into one file or keep two files, both belong in the **same feature folder** (`Services/User/IUserService.cs` + `Services/User/UserService.cs`, or `Services/User/UserService.cs` containing both). Avoid an `Interfaces/` folder — that's an "organize by kind" anti-pattern; organize by feature / domain concept instead.

**Restructure decision flow:**
1. Are both types `internal` (or stricter)? If no → two files in the feature folder.
2. Do the names match (`IFoo` ↔ `Foo`)? If no → two files in the feature folder.
3. Is there exactly one impl in the same assembly? If no → two files in the feature folder.
4. All three yes → single file using the sibling pattern (`internal interface IFoo` + `internal sealed class Foo : IFoo`), filename matches the implementation.

**When to evaluate file splits:**
- **At authoring:** if you're about to add a second top-level type to a file, ask whether the new type genuinely shares the file's purpose. If not, create a new file.
- **During reorgs / restructure passes:** scan every file for multi-type contents and apply the rules above. Document any deliberately retained multi-type files with a one-line comment explaining why (the "tight pattern" rationale).

---

## Folder organization — feature folders, no catch-all "Helpers"

`Helpers/`, `Utilities/`, `Common/`, `Misc/`, and similar catch-all folders are anti-patterns: they collect unrelated code that has no other home, hide coupling, and grow without bound. Every file should live in a folder that names a domain concept or technical concern, not a generic bucket.

**Standard folder conventions per project type:**
- **.NET class libraries (Eventing-style):** feature folders (`EventResolvers/`, `Providers/`, `Readers/`), `Interop/` for P/Invoke + handles + native structs (per FxCop CA1060), `Logging/` for tracing primitives, `Extensions/` for true extension method classes (named `*Extensions`, not `*Methods`). Avoid `Models/` as a flat catch-all — distribute models into their owning feature folder.
- **Blazor component libraries:** components grouped by feature / page area; shared layout components in `Layout/`; modals in `Modals/`; small reusable presentational components in `Controls/` or grouped with their consumers.
- **Fluxor state stores:** `Store/<FeatureName>/` per Fluxor official tutorial — one folder per feature containing `<Feature>State.cs`, `Effects.cs`, `Reducers.cs`, and one file per action record. Drop the feature prefix from `Effects` / `Reducers` class names since the folder already namespaces them.
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
- Extension method classes: `<TypeName>Extensions` (e.g., `StringExtensions`, `EventRecordExtensions`), not `<TypeName>Methods`.
- P/Invoke classes: `NativeMethods` (per FxCop CA1060), `internal static class`. Split per native API surface when one file gets large (`NativeMethods.Evt.cs`, `NativeMethods.Wevtapi.cs` as partials, or separate classes if no shared state).
- Constants / defaults: `<Domain>Defaults` or `<Domain>Constants`, grouped in a `Defaults/` or `Constants/` folder when there are multiple.

**When to evaluate folder structure:**
- **At project creation:** lay out the folder convention up front per the project type above.
- **At every reorg PR:** validate against the conventions; document deliberate deviations with rationale in PR description.
- **Whenever a `Helpers/` or `Utilities/` folder appears:** treat as a refactor signal. Each file in it should move to a feature folder, an `Extensions/`, an `Interop/`, or be promoted to a domain concept folder.

---

## C#-specific recurring code smells (extends [Core / Recurring code smells](../../AGENTS.md#310-recurring-code-smells-from-past-pr-reviews))

The universal smells in `AGENTS.md` (constants single source of truth, list-of-X must reference constants, sibling-constant consistency, test specificity vs `Arg.Any<T>()`, negative assertions weak, don't materialize streams, lambda parameter shadowing, failure paths surface user-visible feedback, comment / path hygiene, idempotency / multi-dispatcher guards, exception messages stay diagnostic, log messages match path, log messages match return, test portability — no hardcoded system paths or locales, no dead branches inside loops with same termination condition) all apply here. The bullets below are the C#-specific additions.

- **Native interop return-value validation — audit while you're there.** Whenever you touch a Win32 / P/Invoke call site, validate every native return value that can be `IntPtr.Zero` / `NULL` / `INVALID_HANDLE_VALUE` for the *entire* sequence in that block — not just the one you came to fix. `LoadResource`, `LockResource`, `LoadLibraryEx`, `OpenProcess`, `CreateFile`, `RegOpenKeyEx`, `FindResourceEx`, etc. all return failure sentinels that, if dereferenced (`Marshal.ReadInt32`, `Marshal.PtrToStructure`, `Marshal.PtrToStringUni`), crash the process. PR reviewers always read the surrounding native sequence; do the same in self-review and add `if (handle == IntPtr.Zero) { log; continue/return; }` guards before any Marshal read.
- **`SafeHandle.IsInvalid` is NOT `IsClosed` — they answer different questions.** `SafeHandle.IsInvalid` is a virtual property derived from the underlying handle value (e.g., handle `== 0` or `== INVALID_HANDLE_VALUE`); it does NOT flip after `Dispose()` runs. `IsClosed` is what flips on `Dispose()`. The footgun: a guard like `if (!_handle.IsInvalid) { _handle.Dispose(); }` inside a method that can be entered twice (e.g., a serialized teardown where multiple callers pass through the same `lock`, an idempotent close path with a state-only gate, or an explicit `Stop()` followed by `Dispose()`) will call `Dispose()` a second time on every subsequent invocation — silent today because `SafeHandle.Dispose` is idempotent via internal reference counting, but a latent footgun the moment a derived `SafeHandle` overrides `ReleaseHandle()` with non-idempotent logic, or the moment another reviewer reads the code and assumes the guard reflects whether `Dispose` has run. **Rule of thumb**: guard with `IsClosed` for "skip if `Dispose` already ran"; reserve `IsInvalid` for "skip if the native call returned a sentinel and the handle was never live."
- **Do not bypass an intentional in-house native-interop layer with BCL convenience APIs.** When a solution deliberately re-implements a native surface (its `Interop/` folder + `NativeMethods.*.cs` partials are the contract), reaching into the equivalent BCL convenience namespace in production *or* tests *or* fixtures defeats the purpose: it forks behavior, hides bugs that the in-house layer is supposed to surface (handle-leak audits, error-mapping coverage, lifecycle ownership), and breaks the assumption that the SUT-under-test exercises the *only* path. Concrete instance: in **EventLogExpert** the entire `EventLogExpert.Eventing` project owns the EVT P/Invoke layer (`Interop/NativeMethods.Evt.cs` + `Readers/EventLogReader.cs` + handles); `System.Diagnostics.Eventing.Reader` (BCL) **must not** appear anywhere in the solution — not in production, not in test bodies, not in test fixtures, not as a "just for the assertion / count / probe" shortcut. The only acceptable mention is a doc-comment cross-reference that explains *why* the project re-implements the surface (e.g. "BCL `StandardEventKeywords` uses different display names — we redefine ours here"). Same principle for any other in-house wrapper layer (a custom WinHTTP wrapper rules out `System.Net.HttpClient` for the same surface, etc.). When you need a one-shot probe / validation that would normally use the BCL API, route it through the project's own wrapper or shell out to the appropriate OS tool (`wevtutil`, `reg`, `sc`) instead — both options keep the in-house contract whole.
- **`Path.IsPathRooted` is not enough when reducing to a leaf name.** If your fallback path strips a file path down to its leaf via `Path.GetFileName(file)` and then resolves it against the OS search order (`LoadLibraryEx`, `Process.Start`, `File.Open`, etc.), guarding only with `Path.IsPathRooted` lets relative-but-qualified inputs like `"subdir\foo.dll"` slip through — the directory portion is silently dropped and a *different* same-named binary on the search path can be loaded, producing wrong results that look correct. Whenever you call `Path.GetFileName(x)` to *replace* `x`, gate the fallback with `string.Equals(x, Path.GetFileName(x), StringComparison.Ordinal)` (or equivalent: assert the input has no directory separators) so only true bare leaf names are rewritten. This applies to any path-reducing fallback, not just `LoadLibraryEx`.
- **Bare `LoadLibraryEx`/`Process.Start`/`CreateFile` on a leaf name is a DLL-planting / wrong-binary risk.** When *any* fallback path resolves a bare filename through the OS default search order (which includes the application directory first), an attacker — or just an unrelated same-named binary on `PATH` — can be loaded instead of the system one you intended. Two acceptable fixes: (a) build a full path via `Path.Combine(Environment.SystemDirectory, leafName)` (or another trusted root) and `File.Exists`-gate before loading, or (b) pass `LOAD_LIBRARY_SEARCH_SYSTEM32` / `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS` (after `SetDefaultDllDirectories`). Never hand a leaf name to `LoadLibraryEx` with `LOAD_LIBRARY_AS_DATAFILE` alone, even for "data only" loads — the system can still map the wrong file and you'll happily read its bytes. This applies to `Process.Start("foo.exe")`, `File.Open("config.json")` from a working directory you don't control, and similar.
- **Brittle exact `Received(N)` counts on log/diagnostic mocks.** Asserting `mockLogger.Received(4).Debug(...)` couples the test to the *current* number of fallback / retry / fix-up steps. The next person who adds a diagnostic log or tightens a fallback gate (legitimate code change) breaks the test for no behavioral reason. For diagnostic / log mocks, prefer one of: (a) `Received(N)` with a content matcher tied to *exactly the contract* you mean to verify, where `N` is derived from the input shape (e.g., `inputs.Length`) and the matcher asserts a substring tied to the contract (e.g., a key phrase plus the input's identifier); (b) `Received().Debug(...)` (at-least-once) when only presence matters. The exact-count rule from [Core / Recurring code smells](../../AGENTS.md#310-recurring-code-smells-from-past-pr-reviews) ("Test specificity") still applies to *behavioral* assertions on argument values — this is its log/diagnostic counterpart: assert the *contract*, not the *current implementation's verbosity*.
- **🚨 CRITICAL — `nameof()` for code symbols inside ANY string, production OR test — mandatory.** This rule has been violated repeatedly; treat every string literal in a diff as suspect until you've confirmed it isn't a symbol name. Any string that embeds the name of a type, method, property, field, parameter, local variable, or enum member MUST use `nameof(...)` (or, when shorter, a member-access form like `nameof(MyClass.Method)`) instead of a hardcoded literal. Pick whichever form is **more compact** at the call site — the goal is rename-safety, not a specific syntax. `nameof()` is a compile-time constant (zero runtime cost) and survives renames; hardcoded names silently rot when the symbol is renamed and the next reader sees a string that names something that no longer exists. **Self-review checklist before declaring any change ready: grep your diff for double-quoted strings and ask of each one — "is this value or is this a name?" If it's a name, it must be `nameof()`.**
    - Log messages: `_logger.Error($"{nameof(FooService)}.{nameof(DoWork)}: failed: {ex}")` — never `$"FooService.DoWork: failed: {ex}"`.
    - `ArgumentNullException` / `ArgumentException` / `ObjectDisposedException` constructors: `nameof(parameter)` / `nameof(MyClass)`.
    - Property-changed and other reflection-style notifications.
    - Exception messages that reference a method or parameter: `throw new InvalidOperationException($"{nameof(Initialize)} must be called first.")`.
    - When you genuinely need both the class name and the method name in one string, prefix with `nameof(EnclosingClass)` once and `nameof(MethodName)` for the method — do not concatenate hardcoded segments with `nameof` segments (a future rename of just the class leaves the string half-stale).
    - **Tests asserting on `ex.ParamName`, `ex.Message`, or log-message content MUST also use `nameof()`.** `Assert.Equal("actionLabel", ex.ParamName)` rots when the production parameter is renamed but the test isn't. The fix pattern when the parameter belongs to *another* type (so a direct `nameof(SomeClass.SomeMethod.actionLabel)` isn't expressible): introduce a local variable with the **same name as the production parameter**, pass it via a **named argument** (`actionLabel: actionLabel`), and assert with `nameof(actionLabel)`. The named-argument call site fails to compile if production renames, prompting the local rename, which propagates to `nameof()` automatically. Same pattern for log substring checks: `h.ToString().Contains(nameof(MyClass))` is rename-safe; `h.ToString().Contains("MyClass")` is not. Sentence-fragment substrings (`Contains("action threw")`) that happen to appear in a log are acceptable only when no symbol is involved — and even then, prefer asserting on a paired symbol (`nameof(MyClass)`) for the rename-safe portion of the contract.
    - **NSubstitute `Received(...).MethodName(...)` calls are already rename-safe** (the method group is a real symbol). But string arguments inside `Arg.Is<T>(x => x.Property == "literal")` matchers are NOT rename-safe if the literal is a property name — use `nameof(MyType.Property)`.
  Exempt: user-facing UI strings (localized/static), serialization keys / JSON property names / SQL column names that intentionally don't track the C# identifier, configuration keys, log category names that are part of an external contract, **and freeform sentence fragments in log messages that aren't symbol names** (e.g., `"connection lost"`, `"retry exhausted"`). When in doubt, prefer `nameof` — it costs nothing and the worst case is a tiny readability hit.

---

## C# / .NET Code Style

### Naming Conventions (Microsoft .NET Guidelines)

- **Interfaces:** prefix with `I`, PascalCase (`IUserRepository`).
- **Types** (classes, structs, enums): PascalCase (`UserRepositoryBase`).
- **Public/Internal/Protected members** (properties, methods, events): PascalCase (`GetUser`).
- **Private instance fields:** `_camelCase` (`_logger`, `_cache`).
- **Private static fields:** `s_camelCase` (`s_defaultOptions`).
- **Thread-static fields:** `t_camelCase`.
- **Const fields (class-level):** PascalCase (`DefaultTimeout`).
- **Public/Internal fields:** PascalCase (`CustomerDetails`) — but prefer properties over public fields.
- **Protected fields:** avoid; use protected properties to maintain encapsulation for derived classes.
- **Parameters and local variables:** camelCase (`userRecord`, `returnValue`).
- **Local constants:** camelCase, same as local variables (`maxRetryCount`).
- **Type parameters:** prefix with `T`, PascalCase (`TResult`).
- **Abbreviations:**
  - Two-letter acronyms: UPPERCASE (`IO`, `ID`, `DB`).
  - Three+ letter acronyms: PascalCase (`Xml`, `Json`, `Html`).
  - In camelCase context: `userId`, `xmlParser`, `htmlContent`.

### Code Formatting

- 4 spaces for indentation (no tabs).
- File-scoped namespaces.
- Opening braces on new lines (Allman style).
- Use `var` only when the type is evident from the right-hand side.
- Use expression-bodied members when applicable (methods, properties, accessors, constructors, local functions).
- Require braces for `if`, `for`, `foreach`, `while` statements.
- No `this.` qualification unless necessary.
- Use language keywords over BCL types (`string` not `String`).
- Modifier order: `public, private, protected, internal, file, static, extern, new, virtual, abstract, sealed, override, readonly, unsafe, required, volatile, async`.
- Max 1 blank line between declarations and inside code blocks.
- Place `while` on a new line in `do-while` statements.
- Insert a final newline in every file.
- Namespace must match folder structure.

### Member Ordering (StyleCop Layout)

1. Constants
2. Static fields
3. Instance fields
4. Constructors and destructors
5. Delegates
6. Events (public first, then interface implementations, then others)
7. Enums
8. Interfaces
9. Properties (public first, then interface implementations, then others)
10. Indexers
11. Methods (public first, then interface implementations, then others)
12. Operators
13. Nested structs
14. Nested classes

### Expression Preferences

- Prefer pattern matching over `as`/`is` with null checks.
- Prefer null propagation (`?.`) and coalesce (`??`) operators.
- Prefer object/collection initializers.
- Prefer conditional expressions for simple assignments/returns.
- Prefer switch expressions over switch statements.
- Prefer the `not` pattern (e.g., `is not null`).
- Prefer extended property patterns.
- Prefer `is null` over `ReferenceEquals`.
- Prefer explicit tuple names over `Item1`, `Item2`.
- Prefer inferred tuple and anonymous type member names.
- Prefer simplified boolean expressions.
- Prefer simplified interpolation.
- Prefer auto-properties.
- Prefer compound assignment (`+=`, `-=`, etc.).
- Prefer index operator (`^1`) and range operator (`..`).
- Prefer local functions over anonymous functions.
- Prefer method group conversion.
- Prefer simple `default` expression (`default` not `default(T)`).
- Prefer deconstructed variable declarations.
- Prefer target-typed `new()` when type is evident.
- Prefer inline variable declarations (`out var`).
- Prefer tuple swap.
- Prefer UTF-8 string literals where applicable.
- Prefer throw expressions.
- Use discards for unused values.

### Code Block Preferences

- Prefer simple `using` statements (without braces) when possible.
- Prefer top-level statements for `Program.cs`.
- Prefer static local functions when not capturing variables.
- Use the conditional delegate call (`?.Invoke()`).

### Field, Parameter, and Modifier Preferences

- Mark fields as `readonly` when possible.
- Treat unused parameters as warnings (do not silently leave them).
- Always specify accessibility modifiers (except for interface members).

### Parentheses

- Use parentheses for clarity in arithmetic, binary, and relational operators.
- Omit parentheses only when obviously unnecessary.

### Using Directives

- Place `using` directives **outside** the namespace.
- Don't separate import groups.
- Don't prioritize System directives first.
- **When sorting / removing usings, the formatter must respect the repo's `.editorconfig` AND any ReSharper `.DotSettings` overrides.** Specifically, honor `dotnet_separate_import_directive_groups`, `dotnet_sort_system_directives_first`, and `csharp_using_directive_placement`. Use `dotnet format` (which honors `.editorconfig` natively) or ReSharper / Rider cleanup with the solution's settings. Do NOT use a tool that defaults to "System first" sorting and ignores `.editorconfig` — it produces a churn diff that fights the project convention. If you cannot determine which tool is in use, do NOT bulk-resort usings; only remove the genuinely unused entries and leave the order alone. The same rule applies to manual edits: never re-order existing using lines just because one block "looks tidier" — the convention is whatever the project's `.editorconfig` says, period.

### Concurrency Primitives

- **Lock fields: prefer `System.Threading.Lock` (.NET 9+) over `object`.** When a field exists solely to be the target of a `lock` statement, declare it as `private readonly Lock _stateLock = new();` rather than `private readonly object _stateLock = new();`.
  - The `Lock` type uses an internal optimized fast path; the C# 13 compiler recognizes it as the target of a `lock` statement and emits `EnterScope()` / `LockScope.Dispose()` IL instead of `Monitor.Enter` / `Monitor.Exit`. This is measurably faster on hot paths and removes the object header lock-word dependency.
  - The `Lock` type also enforces type-safety: `Lock` instances cannot be accidentally used as general-purpose objects (e.g., passed to `Monitor.Enter` directly, or used as a dictionary key meaningfully). `object`-typed lock fields silently allow these mistakes.
- **Lock syntax: prefer the `lock (lockField) { ... }` keyword over explicit `using (lockField.EnterScope()) { ... }`.** When `lockField` is typed `Lock`, the compiler emits identical IL for both forms, so the keyword form is the more concise and idiomatic choice. Reserve `EnterScope()` for cases where you actually need a `LockScope` value (e.g., conditional acquire stored in a variable for later release).
- **Mutator-side lock + reader-side lock + event-outside-lock** is the standard pattern for a thread-safe service that exposes state via properties and raises change notifications:
  ```csharp
  private readonly Lock _stateLock = new();
  private SomeImmutableState _state = SomeImmutableState.Empty;

  public IReadOnlyList<TItem> Items
  {
      get { lock (_stateLock) { return _state.Items; } }
  }

  public event Action? StateChanged;

  public void Mutate(...)
  {
      lock (_stateLock) { _state = _state.With(...); }
      StateChanged?.Invoke(); // outside the lock to avoid handler re-entrancy deadlocks
  }
  ```
  Property getters MUST acquire the lock — single-field reads are atomic for references, but cross-field reads from the outside can otherwise observe inconsistent snapshots. Raising the change event under the lock is a common bug source: handlers that read properties (and therefore re-acquire the lock) will deadlock if the lock is non-reentrant, and even with a reentrant lock the handler runs while the mutator's logical operation is incomplete.
- **`RegisteredWaitHandle.Unregister(waitObject)` returns `false` AND silently skips signaling when already unregistered.** Per the BCL contract on `ThreadPool.RegisterWaitForSingleObject`'s returned handle: if `Unregister` is called on a handle that is no longer registered, it returns `false` *and the provided `waitObject` is never signaled*. Code that ignores the return value and unconditionally calls `waitObject.WaitOne()` will hang indefinitely on the second call. Two callers serializing teardown (e.g., a `Stop()` racing `Dispose()`, or two `Stop()` callers racing) hit this every time without coordination. Two acceptable fixes: (a) **lock the entire teardown** — including the `_waitHandle is not null` check, the `Unregister` call, the `WaitOne` drain, and the `_waitHandle = null` assignment — so only one caller ever calls `Unregister` per registration; or (b) check `Unregister`'s return value and skip `WaitOne()` when it returns `false`. **Prefer (a) when the contract is "no callback fires after teardown returns"** — the losing thread MUST observe the winning thread's drain, which the return-value check alone does not guarantee (the loser would skip `WaitOne` and return *before* the winner's callback drain completes). Same trap exists for any in-house wait/registration API that only signals on success and returns a "was-it-still-registered" boolean.

### Lifecycle serialization — symmetric mutators share the same lock

- **When a lock protects one half of a lifecycle pair (e.g., `Unsubscribe`), it must also protect the other half (`Subscribe`).** A lock on `Unsubscribe` alone does not stop `Subscribe` racing with it — `Subscribe` still mutates the same fields (`_handle`, `_isActive`, `_waitRegistration`) outside the lock, so a concurrent `Subscribe` racing `Unsubscribe`/`Dispose` can leave a freshly-allocated handle disposed mid-method, the `_isActive` flag inconsistent with the actual subscription state, or the teardown drain waiting on a wait-registration that the racing `Subscribe` is still in the middle of installing. **Audit lens**: when adding a lock to a teardown method, list every field the teardown reads or writes, then grep for every other method that mutates one of those fields — each must enter the same lock (or be reachable only via that lock). For lifecycle-pair locks, the lock name should reflect the scope (`_lifecycleLock`, not `_teardownLock`) so future contributors don't add a third caller of the *other* half outside the lock.

### Null-forgiving operator (`!`) — avoid

- **Do not use the `!` (null-forgiving / "damn-it") operator to silence nullable warnings.** It tells the compiler "trust me" without doing the work to actually prove the value is non-null at the use site. If the assumption is wrong (or becomes wrong after a refactor), the result is a `NullReferenceException` at runtime instead of a compile-time error — exactly the class of bug nullable reference types exist to prevent.
- **Do the actual work to make the value non-null.** In order of preference:
  - **Restructure to remove the nullable**: change a method signature, model field, or carrier type so the value cannot be null at the call site. Examples: parameter typed `Foo` instead of `Foo?`; split a state union so the "has-value" arm carries a non-nullable; surface the value through a constructor instead of a settable property.
  - **Pattern-match into a non-null local with `is { }`** at the narrowest scope that needs it: `if (value is { } nonNull) { ... use nonNull ... }`. Inside the block, `nonNull` is the non-nullable type, including across lambda captures.
  - **`when` clause on a `case` label**: `case Foo when value is { } nonNull:` narrows in the case body and is captured cleanly by lambdas inside that body. This is often the cleanest fix in `switch`/Razor `@switch` blocks where one arm semantically requires a value to be present.
  - **Early-return / early-break narrowing**: `if (value is null) { return; }` then continue with `value` (now narrowed) for non-lambda uses. Note: lambdas capture the *original* nullable type, so for a lambda that needs the value, prefer one of the patterns above OR copy into an explicitly-typed non-nullable local first (`Foo nonNull = value;` after the null check).
  - **Throw with a meaningful message** when reaching the use site without a value is genuinely a contract violation: `var nonNull = value ?? throw new InvalidOperationException("Foo must be set before BarAsync runs.");`. The thrown exception has to name what's missing and why it's required.
  - **Sequence-of-nullables: prefer `foreach` with flow narrowing over LINQ.** When you need to drop nulls (and possibly empties) from a sequence and continue working with the non-nullable element, the cleanest no-`!` pattern is a `foreach` loop that leans on `[NotNullWhen(false)]` annotations: `foreach (var r in source) { var p = r?.X; if (!string.IsNullOrEmpty(p)) { list.Add(p); } }`. Inside the `if`, `p` is narrowed to non-null `string` by the framework annotation on `string.IsNullOrEmpty` — no `!` needed, and benchmarks (BenchmarkDotNet, .NET 10) put it 3-5× faster than the LINQ alternatives below at N=1..100 with comparable allocation. This is the default for any non-trivial pipeline, especially hot paths.
  - **LINQ fallback when foreach genuinely doesn't fit** (e.g. you must hand the result to another LINQ operator, or you want point-free pipeline style for a small UI-frequency callback): use `OfType<T>()` over `.Where(x => x is not null).Select(x => x!)`. `OfType<T>()` is a runtime type filter that drops `null` and yields `IEnumerable<T>`, so the rest of the pipeline is statically non-null with no `!`. Example: `results.Select(r => r?.FullPath).OfType<string>().Where(p => p.Length > 0).ToList()`. Project to the nullable first (`Select(r => r?.X)`) then `OfType<T>()` — don't filter the carrier (`Where(r => r is not null)`) and then `Select(r => r!.X)`, because the latter forces `!` on every projection. **Caveat 1**: `OfType<T>()` also drops elements whose runtime type is not `T`, so use it only when the source is conceptually `IEnumerable<T?>` (or you genuinely want a runtime type narrowing). For `IEnumerable<object?>` / `IEnumerable<Base?>` where non-`T` non-null elements should pass through, narrow differently. **Caveat 2**: `OfType<T>()` is measurably slower than `foreach` (4-25% time vs the cast-baseline, 5× allocation in the empty-source case because it instantiates its enumerator unconditionally) — fine for one-shot UI callbacks, not fine for hot paths.
- **Particularly avoid sprinkling `!` inconsistently across multiple uses of the same value** (e.g., `@x!.A` followed by `@x.B` in Razor markup, or `x!.Method()` followed by `x.Property` in C#). Either narrow once for the whole scope or change the type.
- **Reviewer enforcement**: when reviewing a diff that contains `!`, ask whether the suppressor could be replaced with one of the patterns above. Only accept `!` after that question has been answered with a specific reason (typically: "this is the absolute last layer of the API and the contract is enforced by upstream tests"). "It compiles" is not a reason.

---

## Test synchronization — eliminate `Thread.Sleep`, fail-fast on regression

`Thread.Sleep(N)` in a test means "the test thread spins its wheels for N milliseconds, then checks what happened." It is wrong in both directions: too short and the test is flaky; too long and the suite is slow. Worse, in regression cases the test still waits the full N before failing, hiding the diagnostic signal. Whenever the SUT exposes a callback, event, or other observable signal, replace `Thread.Sleep` with deterministic synchronization on that signal.

**Replace `Thread.Sleep(N)` with the most precise primitive available, in this order of preference:**

1. **`ManualResetEventSlim` / `CountdownEvent` — when a callback or event signals completion or arrival.** Add the signal in the handler, then `signal.Wait(TimeSpan.FromMilliseconds(N), TestContext.Current.CancellationToken)`. Strictly better than `Thread.Sleep`:
   - **Positive case** (event expected): the test wakes the moment the event fires — usually well before N ms.
   - **Regression case** (unexpected event): the wait returns `true` immediately when the spurious event signals; assert `Assert.False(received, "...")` and the test fails with a precise message, not a timeout.
   - **Cancellation**: honors `TestContext.Current.CancellationToken` so the suite can stop a hung test cleanly.
2. **`await Task.Delay(TimeSpan, ct)` in `async Task` tests — when you genuinely need to space test stimulus** (e.g., asserting events arrive in order with bounded gaps between writes). Cooperative-cancellation friendly and non-blocking. Convert the test signature from `void` to `async Task` to enable this; xUnit v3 supports it natively and `TestContext.Current` flows across `await` resumption points.
3. **`Thread.Sleep(N)` — only as a last resort**, and only when no observable signal exists from the SUT. Acceptable cases are narrow:
   - A no-subscribers smoke test where there is literally no callback to wait on.
   - A stress test where the sleep is *itself* the test mechanism — deliberate scheduler jitter inside `Parallel.Invoke` to interleave operations under contention, or a SQLite file-handle release backoff. These are not event waits; removing them defeats the test's purpose.
   - When kept, the test (or the immediately surrounding code) must include a comment explaining *why* a signal-based wait is impossible.

**Negative tests need the stimulus, not just the wait.** This is the same rule as the *Exercise the negative case, don't infer it* bullet under "Test purpose / DO test", restated here for the synchronization angle: a deterministic wait around no stimulus is still vacuous, just faster. The full pattern:

```csharp
int eventCount = 0;
var received = new ManualResetEventSlim(false);

watcher.EventRecordWritten += (_, _) =>
{
    Interlocked.Increment(ref eventCount);
    received.Set();
};

watcher.Enabled = true;
// ... initial events to populate state ...

// Act: cause the behavior under test (Disable, Unsubscribe, etc.)
watcher.Enabled = false;

// Snapshot post-action state and clear any signal accumulated during the populate phase.
int countBefore = Volatile.Read(ref eventCount);
received.Reset();

// The trigger that proves the action worked:
WriteAnEvent();

bool fired = received.Wait(TimeSpan.FromMilliseconds(100), TestContext.Current.CancellationToken);

Assert.False(fired, "Should not receive events after Disable");
Assert.Equal(countBefore, Volatile.Read(ref eventCount));
```

**Document non-obvious SUT contract dependencies with a one-line in-test comment.** When a test's correctness depends on a particular SUT guarantee — e.g., *"`Unsubscribe()` blocks until in-flight callbacks complete, so no handler can fire between the count capture and the `Reset()`"* — record that dependency where someone reading the test can see it. Reviewers cannot audit a contract they cannot see; future SUT optimizations that break the contract will silently flake the test.

**Thread-safety on shared state read by both the test thread and a callback thread.** When a callback fires on a non-test thread (timer, native event, `RegisteredWaitHandle`, `Parallel.Invoke` worker, etc.) and the test thread reads the result, prefer thread-safe primitives:

- `int eventCount = 0;` + `Interlocked.Increment(ref eventCount)` in the handler + `Volatile.Read(ref eventCount)` in the assertion — for negative tests where you only care about *whether* and *how many* events arrived.
- `ConcurrentBag<T>` / `ConcurrentQueue<T>` — when you need the actual records.
- A regular `List<T>.Add` from a callback thread + `.Count` from the test thread is a data race even when it usually works in practice; use it only when the callback is guaranteed not to fire concurrently with the assertion (rare, and worth a comment).

**Sleep-style anti-patterns to flag during review:**

- `Thread.Sleep(small)` followed by `Assert.Empty(list)` / `Assert.Equal(0, count)` with no stimulus between them: vacuous negative test — add the stimulus or delete the test.
- `Thread.Sleep(large)` followed by `Assert.NotEmpty(list)`: positive test with a slow guard band. Replace with `signal.Wait(large, ct)`; the test now usually completes in <1 ms while still tolerating slow CI.
- `Thread.Sleep(any)` inside a `Parallel.Invoke` / `Parallel.For` worker that *is* the SUT under stress test: NOT an event wait — it's deliberate jitter for thread-interleaving. Keep, but comment it explicitly so the next person doesn't "clean it up".
- `await Task.Delay(N)` without a `CancellationToken` argument: convert to `await Task.Delay(N, ct)` so the suite's cancellation works.
- `Thread.Sleep` alongside `Assert.True(thingHappened)` with no signal-based wait: replace the entire pattern with `Assert.True(signal.Wait(timeout, ct), "thingHappened did not happen within timeout")`.

**When to apply this rule:**

- **At authoring:** any new test that needs to wait for an asynchronous event uses a signal, not a sleep. `Thread.Sleep` in a new test is a review block unless it falls in one of the narrow last-resort cases above.
- **During every test-quality audit:** grep the touched files for `Thread.Sleep` and `Task.Delay(`. Each occurrence is either replaced with a signal-based wait, or kept with a comment explaining why a signal is impossible.
- **When a test goes flaky:** if the flake is at a `Thread.Sleep` boundary, the fix is the signal-based primitive — not bumping the sleep duration. Bumping the sleep masks the symptom and makes the suite slower for everyone.
