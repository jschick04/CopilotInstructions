---
applyTo: "**/*Tests*/**/*.cs,**/*Tests.cs,**/tests/**/*.cs,**/*Test/**/*.cs,**/*Test.cs,**/test/**/*.cs,**/*.Tests.csproj,**/*.UnitTests.csproj,**/*.IntegrationTests.csproj,**/*.FunctionalTests.csproj,**/*.AcceptanceTests.csproj,**/*.Test.csproj,**/*.UnitTest.csproj,**/*.IntegrationTest.csproj,**/*.FunctionalTest.csproj,**/*.AcceptanceTest.csproj"
---

# C# / .NET Test Infrastructure Instructions

> **Scope:** loaded automatically when the working set contains C# test files or test-project files. Extends the always-loaded `AGENTS.md` core AND the C# topic file `csharp.instructions.md` (which loads for any `.cs` / `.csproj`). The rules below apply specifically to test code — production C# rules live in `csharp.instructions.md`.

> **xUnit version note:** examples use **xUnit v3** syntax (the current shipping major). On v3, `IAsyncLifetime` inherits `IAsyncDisposable` and lifecycle hooks return `ValueTask`; `TestContext.Current` flows the cancellation token across `await` resumption points. xUnit v2 projects substitute `Task` for `ValueTask` and don't have `TestContext.Current` (pass `CancellationToken.None` or a per-test `CancellationTokenSource` instead).

---

## Tests — .NET test project layout (extends [Core / Tests and Benchmarks](../../AGENTS.md#34-tests-and-benchmarks))

The universal test rules in `AGENTS.md` (descriptive method names as full sentences, deterministic timestamps, add/update unit tests with code) all apply here unchanged. The bullets below are .NET-specific.

**Placeholder definitions used throughout this section:** `<Solution>` = top-level repo / root namespace prefix (e.g., `AcmeCorp.Billing`); `<Domain>` = feature area / vertical slice within the solution (e.g., `Filtering`, `Reporting`); `<Project>` = a production project's **full root namespace** including the `<Solution>` prefix (e.g., `AcmeCorp.Billing.Filtering`) — the matching test project is `<Project>.Tests` (e.g., `AcmeCorp.Billing.Filtering.Tests`); `<Topic>` = a grouping label for related constants or helpers (e.g., `Provider`, `Database`).

> **Why shared TestUtils fits VSA:** the shared `<Solution>.<Domain>.TestUtils` project mirrors the `Common/<Domain>/` cross-cutting overlay for production code (AGENTS.md §3.12) — domain-scoped, not kind-scoped. VSA co-location is preserved because the shared project is bounded to **infrastructure only** (e.g., builders, fixtures, assertions, constants) — never test classes or test methods.

> **xUnit fixtures are orthogonal — do not eclipse them.** Use xUnit's `IClassFixture<T>` (one instance per test class, shared across that class's `[Fact]` / `[Theory]` methods) / `ICollectionFixture<T>` (one instance shared across multiple test classes within one assembly via `[CollectionDefinition]`) / **assembly fixtures** (xUnit v3 only — one instance for the entire test assembly) for **runtime lifecycle / resource sharing**; use shared TestUtils for **compile-time code / constant duplication across test assemblies**. Different problems, different solutions — they compose, they don't compete.

### Default — per-project `TestUtils/` for project-local helpers and constants

Every test project owns its `TestUtils/` folder. **This is the default convention; the shared-project escape hatch below applies only when duplication forces it.**

- **Helpers:** `TestUtils/<Topic>Utils.cs` (e.g., `HttpUtils.cs`, `LoggerUtils.cs`, `DeploymentUtils.cs`). The `*Utils` suffix is acceptable here **ONLY for genuinely-mixed-purpose infrastructure** — HTTP / logging / file IO / shell-out / serialization / compression. NOT acceptable for domain object creation, SUT setup, constants, or assertions — those use the domain-named classes (`<Domain>Builder` / `<Domain>Fixtures` / `<Domain>TestConstants` / `<Domain>TestFixtures` / `<Domain>Assertions`) in the naming table below.
- **Named fixtures for parity / golden-output tests:** `TestUtils/<Domain>TestFixtures.cs`. Exposes **ONLY** named, parameterless, **precomputed** `public static readonly` fields OR get-only properties backed by such fields. No `Create...` methods, no parameters, no allocation-in-getter, no conditional logic in the getter. Computed / parameterized factories belong in `<Domain>Builder` / `<Domain>Fixtures` classes — default per-project (`<Project>.Tests/TestUtils/`), promoted to the shared escape-hatch project only when the duplication trigger below is met. See the naming table below for full default-vs-shared placement.
- **Constants:** `TestUtils/Constants/Constants.<Topic>.cs` partial-class files (e.g., `Constants.Provider.cs`, `Constants.Database.cs`). Each file declares `public static partial class Constants` in `<Project>.Tests.TestUtils.Constants` namespace, exposes `public const` members (or `public static readonly` for values that genuinely cannot be `const` — see `[InlineData]` note below). Tests reference `Constants.Foo`. No collision because the partial lives in the project-scoped namespace and is consumed within its own assembly. **`[InlineData]` requirement**: xUnit's `[InlineData(...)]` accepts only compile-time constants — use `public const` for any value referenced from `[InlineData]`; use `MemberData` / `ClassData` for non-const values.

### Escape hatch — shared `<Solution>.<Domain>.TestUtils` class library when duplication forces it

When the **same** helper / fixture / constant is genuinely needed by **≥2 test projects** (the second consumer either exists in the current change OR already duplicates the helper today), promote it to a shared class library at `tests/Shared/<Solution>.<Domain>.TestUtils/`. **Promote unless behavior trace shows intentional drift** between the consumers (per the diverged-constants pattern below). This is a **scalable option when duplication forces sharing** — not a wholesale replacement for per-project `TestUtils/` (which remains the default for project-local helpers).

- **Project shape:** the shared project is a **class library, NOT a test project**. Set `<IsTestProject>false</IsTestProject>` (or omit the property entirely). The shared project **MUST NOT** reference test-runner / discovery packages — `xunit.runner.*` (e.g., `xunit.runner.visualstudio`), `Microsoft.NET.Test.Sdk`, `coverlet.collector` — those pull in the test host machinery and belong only in actual test projects. The shared project **MAY** reference: the **assertion-only `xunit.v3.assert` package** (for xUnit v3 projects; v2 projects use `xunit.assert`) when `<Domain>Assertions` helpers use `Xunit.Assert`; **`FluentAssertions`** if the project uses fluent-style assertion helpers; the **xUnit v3 core package** (`xunit.v3.core` on v3 projects; `xunit.core` is the legacy v2 path) if helpers expose xUnit theory data types such as `TheoryData<...>`; and **helper libraries** (`NSubstitute`, `Bogus`, `AutoFixture`) when builders / fixtures use them. Prefer the narrowest dependency — `xunit.v3.assert` over the umbrella `xunit` meta-package; framework-agnostic over framework-bound. Namespace mirrors the project name: `<Solution>.<Domain>.TestUtils`. Consumer test projects add `<ProjectReference Include="..\..\Shared\<Solution>.<Domain>.TestUtils\<Solution>.<Domain>.TestUtils.csproj" />`.
- **Class names MUST be domain-specific** — `<Domain>TestConstants`, `<Domain>Builder`, `<Domain>Fixtures`, `<Domain>Assertions`. If shared constants were generically named (`Constants`) the consumer test project's own per-project `Constants` partial AND the shared `Constants` partial would both be `using`-imported into the same file and `Constants.Foo` would trigger `CS0104: ambiguous reference`. Using `<Domain>TestConstants` (per this rule) avoids the situation entirely. A `using` alias is a valid fallback if you ever had to share a generically-named partial, but domain naming is the cleaner default — aliases tend to fall out of sync as test files are copied around.
- **Project-name `TestUtils` suffix carve-out**: the `.TestUtils` suffix is a **project-level discriminator** (analogous to `.Tests`), not a class-name suffix. It does NOT violate AGENTS.md §3.12's anti-`Utils`/anti-`Helpers` rule at the class level — classes inside the shared project are domain-named (`<Domain>Builder`, `<Domain>Fixtures`, `<Domain>Assertions`), never `Utils` / `Helpers`.
- **Visibility:** for **`Create...` factory-style classes** (the default in the naming table) — `public static class <Domain>Builder`, `public static class <Domain>Fixtures`, `public static class <Domain>Assertions` (cross-asm dispatch requires `public`; `static` because no state). For **fluent-builder-style `<Domain>Builder`** (see *Fluent-builder escape clause* below) — `public sealed class <Domain>Builder` (non-static because instance state per build; sealed because not designed for inheritance). The constants partial is always `public static partial class <Domain>TestConstants`.
- **Internal-type dependency check before promoting a helper to shared.** A candidate `<Domain>Builder` / `<Domain>Fixtures` / `<Domain>Assertions` can only compile in the shared TestUtils project if its parameters / return types / call sites are all `public` production API — the shared assembly cannot see `internal` production types without an `[InternalsVisibleTo("...")]` grant. Per the IVT rule below (no new IVT grants for shared TestUtils **absent the explicit decision gate**), apply this decision gate: (a) if all production types the helper touches are already `public` → promote freely; (b) if the helper depends on `internal` production types → **keep it per-project** (where `internal` access is already in scope) as the default safe choice; (c) if the helper is so widely duplicated that per-project copies are untenable AND the production types are deliberately internal → escalate via `ask_user` for an explicit decision between widening the production type to `public` (preferred per AGENTS.md §3.12 KEEP-PUBLIC precedence ladder) or adding a targeted `[InternalsVisibleTo("<Solution>.<Domain>.TestUtils")]` grant.
- **`InternalsVisibleTo` interaction:** do NOT add new `[InternalsVisibleTo("...")]` grants on production assemblies just to support shared TestUtils **without an explicit user decision per the internal-type dependency check above**. The shared project's `public` surface is the deliberate cross-asm dispatch channel; reflexive IVT grants widen access beyond what shared TestUtils requires and accumulate coupling cost (see AGENTS.md §3.12 friend-grant proliferation rule).
- **Linked source files (`<Compile Include="..\..\..." Link="..." />`) are deprecated** in favor of the shared TestUtils project. Existing links may remain until next touched — where "touched" means **the linked file's content changes OR the linked source is being replaced**; unrelated csproj maintenance (NuGet bumps, target-framework updates) does NOT trigger migration. Do not force unrelated churn.

### Naming patterns by purpose

| Class | Default vs escape hatch | Location | Purpose |
|---|---|---|---|
| `Constants` (partial) | DEFAULT (per-project) | `<Project>.Tests/TestUtils/Constants/Constants.<Topic>.cs` | Project-local constants (`public static partial class`); project-namespace-scoped (no collision) |
| `<Topic>Utils` | DEFAULT (per-project) | `<Project>.Tests/TestUtils/<Topic>Utils.cs` | Genuinely-mixed-purpose IO/log/HTTP/file/shell-out/serialization/compression helpers — NOT domain factories |
| `<Domain>TestFixtures` | DEFAULT (per-project) | `<Project>.Tests/TestUtils/<Domain>TestFixtures.cs` | Named, parameterless, precomputed `public static readonly` fields or get-only properties (no `Create...`, no parameters, no allocation-in-getter, no conditional logic in getter) for parity / golden-output tests |
| `<Domain>Builder` | DEFAULT (per-project) → ESCAPE HATCH (shared) when ≥2 test projects need it | `<Project>.Tests/TestUtils/<Domain>Builder.cs` (`internal static class`) → `tests/Shared/<Solution>.<Domain>.TestUtils/<Domain>Builder.cs` (`public static class`) on promotion | Parameterized factory for SUT *types* (e.g., domain events / DTOs / records) — `Create...` methods only (fluent-builder escape clause below) |
| `<Domain>Fixtures` | DEFAULT (per-project) → ESCAPE HATCH (shared) when ≥2 test projects need it | `<Project>.Tests/TestUtils/<Domain>Fixtures.cs` (`internal static class`) → `tests/Shared/<Solution>.<Domain>.TestUtils/<Domain>Fixtures.cs` (`public static class`) on promotion | Parameterized factory for SUT *setup* (e.g., configured services, populated stores) — `Create...` methods only |
| `<Domain>Assertions` | DEFAULT (per-project) → ESCAPE HATCH (shared) when ≥2 test projects need it | `<Project>.Tests/TestUtils/<Domain>Assertions.cs` (`internal static class`) → `tests/Shared/<Solution>.<Domain>.TestUtils/<Domain>Assertions.cs` (`public static class`) on promotion | Custom assertion helpers (`AssertXxx` methods or extension methods) — domain-specific assertion logic, NOT generic `*Utils` |
| `<Domain>TestConstants` (partial) | ESCAPE HATCH only (per-project equivalent is the bare `Constants` partial above) | `tests/Shared/<Solution>.<Domain>.TestUtils/Constants/<Domain>TestConstants.<Topic>.cs` | Cross-test-project constants (`public static partial class`); domain-scoped name avoids `CS0104` |

**Hard rule:** `<Domain>Fixtures` (parameterized factory) and `<Domain>TestFixtures` (named precomputed instances) MUST NOT mix roles in one class. `<Domain>Fixtures` exposes ONLY `Create...` methods (parameterized, allocate-on-call); `<Domain>TestFixtures` exposes ONLY named `public static readonly` fields or get-only properties backed by such fields (parameterless, precomputed, no conditional logic in getter). The single-word `Test` distinction is the disambiguator — don't blur it.

### Fluent-builder escape clause for `<Domain>Builder`

The naming table mandates `Create...` parameterized factory methods on `<Domain>Builder` as the default. When parameter lists become unwieldy (≥5 parameters with frequent defaults, complex nested-object construction, tests that need to compose / mutate the object across phases of arrangement), the fluent **Test Data Builder** pattern is an acceptable alternative:

```csharp
internal sealed class <Domain>Builder
{
    private string _name = "default";
    private int _priority = 0;
    private readonly List<<Domain>Child> _children = new();

    public <Domain>Builder WithName(string name) { _name = name; return this; }
    public <Domain>Builder WithPriority(int priority) { _priority = priority; return this; }
    public <Domain>Builder WithChild(<Domain>Child child) { _children.Add(child); return this; }
    public <Domain> Build() => new(_name, _priority, _children.ToImmutableArray());
}

// Usage: new <Domain>Builder().WithName("test").WithPriority(5).WithChild(...).Build()
```

**Prefer fluent over `Create...` when:** parameter list has ≥5 entries with frequent defaults; the object graph is nested (children, collections, optional sub-records); tests need to compose / mutate the object across phases of arrangement.

**Prefer `Create...` over fluent when:** ≤3 parameters, almost always positional; single-shot construction (no mutation pre-build); backward compat with existing `Create...` patterns in the project.

**Same default-vs-shared rule applies**: fluent builder lives per-project default (`internal sealed class <Domain>Builder`) → promoted to shared (`public sealed class`) when ≥2 test projects need it. The class becomes non-static (instance state per build) but the per-project/shared placement rule is unchanged. The hard rule against mixing factory / named-instances roles still applies — a fluent `<Domain>Builder` exposes ONLY fluent `With...` + `Build()`; it does NOT expose `Create...` static methods or `public static readonly` named instances.

### Integration-test infrastructure with Testcontainers

When integration tests need real external dependencies (databases, message queues, web services), [Testcontainers for .NET](https://dotnet.testcontainers.org/) is the established pattern. **Testcontainers fixtures sit behind xUnit `ICollectionFixture<T>` / `IClassFixture<T>` (per the xUnit-orthogonality rule above), NOT inside `<Domain>Builder` / `<Domain>Fixtures` classes** — lifecycle semantics require xUnit's `IAsyncLifetime`, not a `Create...` factory.

```csharp
// tests/Shared/<Solution>.<Domain>.TestUtils/PostgresFixture.cs (public sealed class, lives in shared project)
public sealed class PostgresFixture : IAsyncLifetime
{
    // Pin the image explicitly — the parameterless PostgreSqlBuilder() ctor is obsolete in current Testcontainers.
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder("postgres:16-alpine").Build();
    public string ConnectionString => _container.GetConnectionString();
    public ValueTask InitializeAsync() => new(_container.StartAsync());
    public ValueTask DisposeAsync() => _container.DisposeAsync();
}

// IMPORTANT: the [CollectionDefinition] class lives in EACH CONSUMER TEST ASSEMBLY, NOT in the shared TestUtils project.
// xUnit collection definitions are assembly-scoped — they're only discovered when in the same assembly as the tests
// that declare [Collection("...")]. Each consumer integration-test project declares its own:
//
// tests/Integration/<Project>.IntegrationTests/PostgresCollection.cs (in the CONSUMER, not the shared project):
[CollectionDefinition("Postgres")]
public sealed class PostgresCollection : ICollectionFixture<PostgresFixture> { }

// Consumer integration test (same assembly as PostgresCollection above):
[Collection("Postgres")]
public sealed class MyServiceIntegrationTests
{
    private readonly PostgresFixture _postgres;
    public MyServiceIntegrationTests(PostgresFixture postgres) { _postgres = postgres; }
    // ...
}
```

Rules:

- **Lifecycle via xUnit fixtures, not factory methods.** Don't put `CreatePostgresContainer()` in `<Domain>Fixtures` — the SUT-setup factory pattern doesn't carry lifecycle semantics. xUnit's `IAsyncLifetime` + `[CollectionDefinition]` does (and only the test runner can call `InitializeAsync` / `DisposeAsync` at the right moments).
- **`[CollectionDefinition]` lives in the consumer assembly, not the shared TestUtils project.** xUnit only discovers `[CollectionDefinition]` classes within the same assembly as the tests that reference them by `[Collection("Postgres")]`. The `PostgresFixture` itself can live in shared TestUtils (cross-asm `public` class is fine), but each consuming test assembly must declare its own `[CollectionDefinition("Postgres")] public sealed class PostgresCollection : ICollectionFixture<PostgresFixture> { }`. Putting the collection definition in the shared project leaves it undiscovered — xUnit cannot satisfy the test class's fixture-constructor arguments and **fails test initialization at runtime** (the test class is never instantiated, not "the parameter is null").
- **Shared lifecycle when expensive.** A Postgres container is expensive enough to share — startup often takes several seconds on a cold Docker cache. Share across an entire test collection via `ICollectionFixture<T>` to amortize startup cost. **Per-class** (`IClassFixture<T>`, one instance per test class shared across its `[Fact]` / `[Theory]` methods) is appropriate only when state isolation across classes requires it.
- **Network ports auto-assigned by Testcontainers.** Never hardcode container ports — `_container.GetConnectionString()` provides the dynamic mapping. Hardcoded ports break parallel test execution.
- **Shared-fixture-type vs shared-instance distinction.** The `<Solution>.<Domain>.TestUtils` project's `PostgresFixture` *type* may be **shared across assemblies** when ≥2 consumer test projects need an identically-configured container — the standard escape-hatch trigger applies. When only ONE consumer test project needs the container, the fixture type may stay per-project (no cross-asm sharing needed). The `[CollectionDefinition]` is **always per-consumer-assembly** regardless of where the fixture type lives — that's a xUnit discovery rule, not a placement choice.
- **NuGet dependency carve-out**: when adding Testcontainers, the shared TestUtils project may reference `Testcontainers` + the specific module package (e.g., `Testcontainers.PostgreSql`, `Testcontainers.RabbitMq`). These are helper libraries, not test runners — allowed per the package rules above.

### When shared TestUtils itself needs tests

The shared `<Solution>.<Domain>.TestUtils` project's builders / fixtures / assertions are typically simple enough that their tests are the consumer test suites themselves (if `<Domain>Builder.CreateTestX(...)` is broken, every consumer test that uses it fails — immediate signal). When the shared infra grows complex enough to warrant direct testing — computed transformations in `<Domain>Builder`, conditional setup logic in `<Domain>Fixtures`, custom-assertion compositions in `<Domain>Assertions` — create a sibling test project:

- Path: `tests/Unit/<Solution>.<Domain>.TestUtils.Tests/`
- `<IsTestProject>true</IsTestProject>` (it IS a test project; references the shared TestUtils as the SUT).
- Same test-mirror principle as production code: test the public surface of the shared TestUtils class.
- Per-project `TestUtils/` inside the sibling test project is allowed (it's a test project like any other) but usually empty — meta-test infrastructure rarely needs its own infra.
- The sibling project follows the same per-project default + escape-hatch rules; the recursion bottoms out when the meta-test SUTs are simple enough that consumer tests provide adequate coverage.

### Diverged constants — explicit-suffix pattern

When two constants have similar intent but diverge meaningfully (e.g., default `StringComparison` vs `OrdinalIgnoreCase`), use **explicit suffix** rather than splitting into separate classes:

```csharp
public const string <Domain>DescriptionContainsX    = "...";
public const string <Domain>DescriptionContainsXOic = "..."; // OrdinalIgnoreCase variant
```

Single class, suffix-disambiguated. Apply the same convention whether the constant lives in a per-project `Constants` partial or a shared `<Domain>TestConstants` partial.

### Constant naming — name must match the value's actual domain

A test-constant's identifier must accurately describe what the value IS, not what the author once *intended* it to be. When the value-vs-name domain drifts — typically because a test was refactored from one scenario to a broader one but the constant name fossilized — readers misclassify the test, reviewers (human and Copilot bot) flag the mismatch on sight, and downstream tests inherit the misleading frame.

The canonical violation: `public const string BadUncPath = @"E:\bad-unc-path";` — the name asserts UNC (`\\server\share\...`) but the value is a local-drive path. Tests using `BadUncPath` then talk about "simulated UNC timeout" while actually exercising "any path that throws during probe", which is broader. Two fixes:

- **Rename the constant to match the value's actual domain** (preferred when the test's real intent is the broader scenario): `BadUncPath` → `ProbeFailurePath`. Update all references AND any exception messages / comments that referenced the old narrow scope.
- **Change the value to match the name** (preferred when the test genuinely needs a UNC path): `BadUncPath = @"\\unreachable-server\share\path";`. Be aware that "looks like UNC" values can produce different runtime behavior than local-drive values (UNC resolution timeouts, different exception types, host-network-dependent timing) — verify the test still exercises the intended code path.

**Audit lens** (apply during test refactors and during PR self-review):
- For every test constant declared in `Constants.<Topic>.cs`, read the name aloud while looking at the value. Do they describe the same thing?
- Domain keywords in constant names — `Unc`, `Http`, `File`, `Folder`, `Json`, `Xml`, `Base64`, `Guid`, `Email`, `Uri` — each carries a structural commitment. The value MUST satisfy that structure. `EmailAddress = "not-an-email"` is the same class of bug.
- Negative-scenario prefixes — `Bad`, `Invalid`, `Malformed`, `Nonexistent`, `Unreadable`, `ProbeFailure` — describe the FAILURE the test exercises, not the value's surface format. Pick the prefix that matches what the test is actually verifying. "`Bad`" alone is too vague; "`BadFormat`", "`BadAuth`", "`ProbeFailure`" each communicate something specific.

When you refactor a test from a narrow scenario (UNC timeout) to a broader one (any probe failure), this rule fires the same way as the user-facing-text re-audit in `AGENTS.md §3.9`: scope-widening leaves stale narrow-scope language in names, comments, and exception messages — sweep all three.

### Extracting duplicated test values

- Same non-trivial literal in **≥2 tests within ONE test project** → add to project-local `TestUtils/Constants/Constants.<Topic>.cs`.
- Same non-trivial literal across **DIFFERENT test projects** — the second consumer either exists in the current change OR already duplicates the literal today: **promote to shared `<Solution>.<Domain>.TestUtils/Constants/<Domain>TestConstants.<Topic>.cs` unless behavior trace shows intentional drift**. When unit + integration suites have intentional drift (e.g., integration suite needs a different default), keep both copies project-local with explicit variant suffixes per the diverged-constants pattern above — don't force a shared constant that doesn't match either suite's contract.
- **Do NOT declare per-test-class `private const` blocks at the top of test files** — keep test files focused on test logic so values are discoverable and reusable.
- Trivial values (empty string, single characters, well-known sentinels like `"main"`) and strings that genuinely must differ between tests are exempt.

---

## Patterns this rule does NOT replace

The per-project `TestUtils/` + shared `<Solution>.<Domain>.TestUtils/` escape hatch is **one viable approach** for organizing test infrastructure. Several established alternative patterns address different problems or different trade-offs — they are NOT eclipsed by this rule and may coexist with it. When the per-project default genuinely fails for your slice, the alternatives below are valid escape hatches in their own right.

- **Test base classes** (e.g., `IntegrationTestBase`, `DatabaseTestBase`): inheritance-based code sharing common in older xUnit codebases. Trade-off: tight coupling via inheritance, harder to compose, subclasses can override base behavior in incompatible ways. **Use case**: shared setup / teardown that genuinely applies to every test in a category AND a `[Fact]` / `[Theory]` method-decoration approach doesn't fit. **Prefer xUnit fixtures over test base classes** when the shared concern is lifecycle / resource (database, container) rather than helper-method reuse.

- **Object Mother pattern** (Fowler's article describes the pattern; name was coined on a ThoughtWorks project — *not* in *Patterns of Enterprise Application Architecture*): one class per domain object with named static instances (e.g., `Customers.ValidGold`, `Customers.LapsedRenewal`). **Mostly subsumed by** this rule's `<Domain>TestFixtures` (named static instances pattern) — the naming convention is different but the structural pattern is the same. Use `<Domain>TestFixtures` to match this rule; reach for the literal "Object Mother" naming only when the codebase has historical precedent. The scenario-catalog role (named instances collectively documenting domain-relevant test states) carries over.

- **AutoFixture / Bogus**: **anonymous test-data / fake-data generation** (NOT property-based testing — that's a separate category, e.g., **FsCheck** for .NET). AutoFixture creates anonymous specimen values for varied inputs without per-field arrangement; Bogus generates plausible-looking fake names / addresses / etc. **Use case**: tests need lots of similar-but-not-identical objects, compact construction of complex object graphs where most fields don't matter, or fake-but-realistic seed data. **Trade-off**: less explicit test data — readers must trust the framework's generator. **Compatible with this rule**: use AutoFixture / Bogus *inside* `<Domain>Builder` — whether the Builder is a `Create...` factory (`<Domain>Builder.Create()` calls AutoFixture for default fields) or a fluent builder (`new <Domain>Builder().With...().Build()` calls AutoFixture for unspecified fields). The domain-named builder still carries intent at the call site.

- **Property-based testing** (separate category): **FsCheck** (.NET port of QuickCheck) generates inputs against invariants ("for all `x`, predicate holds"). Different mental model from anonymous-data generation — you write the *property*, the framework explores inputs. **Use case**: invariants that must hold across input space (commutativity, idempotency, round-trip serialization). **Not subsumed by this rule**: property-based tests typically live in their own per-project test classes and don't need shared TestUtils infrastructure for the generators (those come from FsCheck itself).

- **HTTP / service-boundary virtualization** (separate category from container-based integration): `WebApplicationFactory<T>` / `TestServer` (Microsoft ASP.NET Core) for in-process API testing without Docker; **WireMock.Net** for stubbing external HTTP dependencies in integration tests; **MockServer** (the external server / container; configure from .NET via `MockServer.Net.Client`) for stubbing external HTTP dependencies that need cross-language sharing; **RichardSzalay.MockHttp** for `HttpClient` message-handler mocking in unit tests. **Use case**: testing code that talks HTTP to other services without booting real containers. **Placement**: per-project `TestUtils/<Topic>Utils.cs` (e.g., `HttpUtils.cs` containing a configured `HttpClient` factory) or behind xUnit fixtures when the lifecycle is expensive.

- **Testcontainers**: real infrastructure for integration tests (databases, queues, APIs). See the dedicated *Integration-test infrastructure with Testcontainers* section above. **Placement**: behind xUnit `ICollectionFixture<T>`, not inside `<Domain>Builder` / `<Domain>Fixtures`. **Use case**: integration tests against real dependencies when in-process simulation (`WebApplicationFactory<T>`, in-memory fakes) isn't faithful enough.

- **Per-slice in-memory fakes** (e.g., `InMemoryRepository<T>` co-located within each slice's test project): the slice owns its test infrastructure end-to-end. **Compatible** when one slice owns the fake and no other consumer needs it (the fake IS the slice's `<Domain>Fixtures`-equivalent — a parameterized factory for SUT setup using an in-memory backend). **Competes** with this rule when ≥2 slices duplicate the same fake AND a team deliberately keeps both copies per-slice to preserve VSA slice independence over DRY. That's a legitimate VSA-over-DRY trade-off — document the choice explicitly so future contributors understand the deviation from the shared-promotion trigger.

- **xUnit fixtures** (`IClassFixture<T>`, `ICollectionFixture<T>`, assembly fixtures (v3)): runtime lifecycle / resource sharing within ONE test assembly. **Orthogonal to this rule** (which addresses compile-time code / constant sharing across MULTIPLE test assemblies). Both compose freely — a shared `<Domain>Fixtures.CreateConfiguredService(...)` can be called inside an `IClassFixture<T>` constructor, for example.

- **`InternalsVisibleTo` for white-box testing**: separate coupling decision per AGENTS.md §3.12. This rule's "Internal-type dependency check" already addresses the IVT trade-off for shared TestUtils helpers; for direct white-box testing of internal SUT types (without a TestUtils intermediary), follow §3.12's friend-grant proliferation precedence ladder.

When choosing among these patterns for a new test project, **start with this rule's per-project `TestUtils/` default**. Reach for alternatives only when the per-project default genuinely fails for your slice, and document the choice in the test project's README / `CONTRIBUTING` so future contributors understand the deviation.

---

## Test purpose — every test pays for its existence

The universal test-specificity and negative-assertion rules in `AGENTS.md` apply unchanged. The bullets below codify *why a test should exist at all* and what to delete during test-quality audits. Tests are code; coverage for coverage's sake is a maintenance liability that gives false confidence and slows future refactors.

**The default is intent-driven, thorough tests — not coverage-driven filler.** Every test (new or existing) must justify itself by naming the regression it would catch *and* exercising the actual behavior it claims to guard. A "negative" test that does not include the stimulus it's meant to disprove is vacuous — it only proves "the system was quiet for N ms", which is trivially true on most CI runs. A "positive" test whose assertion is structurally guaranteed by the preceding code (or by the production return type) is tautological. **Coverage-driven tests are appropriate only when the user explicitly asks for "complete code coverage" or a coverage sweep** — and even then, prefer expanding the SUT's documented surface (so existing intent-driven tests cover more) over adding filler tests that pin uninteresting behavior. When in doubt about whether a coverage gap is worth a test, ask via `ask_user`.

**A test is worth keeping only if it would catch a real regression.** Before writing or keeping a test, answer: "What concrete behavior change in the SUT would make this test fail?" If the answer is "I can't think of one without changing the test itself", delete or rewrite.

**Do NOT test:**
- **Trivial getters / setters / pass-through methods.** A test that does `x.Foo = 1; Assert.Equal(1, x.Foo);` verifies the language compiler, not your code. Same for properties whose only logic is `=> _field`.
- **Framework code.** Don't test that EF Core saves entities, that `System.Text.Json` serializes a record, that `IServiceCollection.AddSingleton` registers a service. Test *your* code that integrates with the framework.
- **Private implementation details.** Tests that pin internal data structures, private method signatures, or specific algorithm steps break on every refactor without catching real regressions. Test observable behavior through the public contract. **Special case — never assert `NullReferenceException` on null inputs.** An NRE is an *implementation detail* (currently a `foreach` over a null reference, a `.Length` access, a deref of a `_field`) — it tells the reader nothing about the API contract and silently turns into a different exception the moment anyone adds an `ArgumentNullException.ThrowIfNull` guard. If a method takes a non-nullable parameter and you want to pin "null is rejected", add `ArgumentNullException.ThrowIfNull(param)` (or `ArgumentException.ThrowIfNullOrWhiteSpace` for non-empty strings) at the top of the method and assert `Assert.Throws<ArgumentNullException>(...)` — never `Assert.Throws<NullReferenceException>(...)`. The SUT change is the test's whole point: an explicit guard documents the contract once and survives every future internal refactor.
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
- **Brittle exact-string assertions on multi-token attribute / token-list values.** When the contract under test is "this token list must (not) contain X, Y, Z" — manifest attribute values (`IgnorableNamespaces="uap rescap"`, MSIX `Capabilities`), HTML/Razor class lists (`class="btn btn-primary"`), role/permission lists (`Roles="admin,editor"`), HTTP header lists (`Accept`, `Content-Encoding`, CORS `Access-Control-Allow-Methods`), CSV / space-separated allowlists, `[Flags]` enum debug strings, command-line argument lists — do NOT assert the entire serialized string with `Assert.Contains("uap rescap", content)` or `Assert.Equal("uap rescap", value)`. The test then fails on harmless reorderings (`"rescap uap"`), added whitespace (`"uap  rescap"`), or additions of new harmless tokens (`"uap rescap mp"`) that don't change the contract — producing false-fail churn that trains reviewers to "just update the string" without checking whether the underlying contract was actually preserved. Pattern to apply: regex-extract or parse the attribute value, split on the delimiter, and assert presence / absence per token:
  ```csharp
  var match = Regex.Match(content, @"IgnorableNamespaces=""([^""]*)""");
  Assert.True(match.Success, "IgnorableNamespaces attribute not declared.");
  var tokens = match.Groups[1].Value.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
  foreach (var forbidden in new[] { "uap2", "uap3", "desktop4", "desktop5", "com" })
      Assert.DoesNotContain(forbidden, tokens);
  ```
  The intent is exclusion-of-specific-tokens (or inclusion-of-required-tokens), not exact-serialized-form. Assert the intent, not the implementation detail. **Audit lens**: any `Assert.Contains` / `Assert.Equal` / `Assert.Matches` on a value whose contract is "list-of-tokens", "set of attributes", or "headers-must-include" — replace with split + per-token presence/absence assertions. The same rule applies to JSON property arrays, XML attribute-value tokens, and HTTP header values that the spec defines as comma-separated lists.
- **Brittle test path resolution — fixed-depth `..\..\..\` from `AppContext.BaseDirectory`.** When a test needs to read a file checked into the repo (source file for drift assertions, manifest XML for schema tests, fixture JSON / SQL / golden-output), do NOT compute the path with a hardcoded `Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\..\..\src\<File>")` segment count. The depth from test-output directory to repo root depends on the TFM directory (`net10.0/` vs `net10.0-windows10.0.19041.0/`), configuration (`Debug/` vs `Release/`), publish vs build (`win-x64/` subfolder appears in publish output), and any future addition of a per-runner subdirectory (e.g., `dotnet test --results-directory`). A fixed `..\..\..` count works on the author's machine and silently breaks on a different runner / config — the test then fails with "file not found" pointing at a wrong path, which reviewers (human and Copilot bot) flag on sight. **Pattern to apply**: walk up from `AppContext.BaseDirectory` until you find a sentinel that anchors the repo root (typically the solution file `*.slnx` / `*.sln`, less commonly `.git/`), then `Path.Combine` the discovered root with the relative segments:
- **NSubstitute Arrange discipline — no standalone `Arg.Any<T>(...)` calls outside `When`/`Returns`/`Do` contexts.** When configuring a substitute, every `_substitute.Method(Arg.Any<T>(), ...)` invocation MUST be inside a configuration context: `Returns(...)` / `ReturnsForAnyArgs(...)` / `When(...)` / `WhenForAnyArgs(...)` / `Do(...)`. A standalone call like `_substitute.Method(Arg.Any<double>(), Arg.Any<string>());` (no surrounding configuration) is treated by NSubstitute as a REAL invocation that gets recorded in the substitute's call history — silently inflating any future `Received(N).Method(...)` assertion by 1, AND obscuring the helper's intent. The pattern often appears as "I want to set up `Arg.Any` matchers for the subsequent `WhenForAnyArgs.Do(...)` setup" — but `WhenForAnyArgs(s => s.Method(default, default, ...))` already declares the method signature for matcher purposes; the prior standalone call adds nothing and only harms. **Fix patterns**: (a) DELETE the standalone call; (b) move the matcher INTO a `Returns` chain (`_substitute.Method(Arg.Any<T>()).Returns(value)`); (c) use `WhenForAnyArgs(s => s.Method(default, ...)).Do(callback)` for capture patterns (no prior call needed). **Acceptable (do NOT flag)**: `Arg.Any` inside `Returns(...)` / `When(...)` / `Do(...)` blocks; standalone calls in the Act section that ARE the test's subject. **Audit lens**: regex-grep `_\w+\.\w+\([^)]*Arg\.Any` in NEW or modified test files. For each match, verify the enclosing statement is inside `When*(...)` / `Returns*(...)` / `Do(...)`. If standalone, flag.
- **Test comments must describe the mechanism the test actually uses.** When a test method has multi-line `//` comments explaining "how" it verifies something — references to "via reflection-based count", "via subscriber count introspection", "via NSubstitute call history", "via mock verification", "we assert via X" — the named mechanism MUST match what the test body actually does. Misleading comments that describe techniques never invoked (no `typeof(...).GetField(...)`, no `Received().Count`, no `Received(...).Method(...)` for the cited contract) create false impressions of test complexity AND mislead maintainers about the actual oracle. Often the real oracle is simpler — "raise event after Dispose; if subscriber is still attached, the callback throws via bUnit's disposed-renderer guard; no exception = unsubscribed". Sub-case of the universal [`code-comment-mismatch`](../../AGENTS.md#310-recurring-code-smells-from-past-pr-reviews) smell specific to test patterns. **Fix patterns**: (a) DELETE the misleading comments per AGENTS.md §3.1 deletion-exempt category — test name + assertion shape are often self-documenting; (b) REPLACE with an accurate ≤3-line comment describing the ACTUAL oracle (requires §3.1 ask_user approval for new comment); (c) RENAME the test to embed the mechanism (`Dispose_Unsubscribes_SoRaisingEventAfterDoesNotThrowOnDisposedRenderer`). **Audit lens** when reviewing a new test method with explanatory comments: read the comment + read the test body. If the comment names an API or technique the body doesn't invoke, flag.
  ```csharp
  private static string ResolveRepoRelativePath(params string[] segments)
  {
      var directory = new DirectoryInfo(AppContext.BaseDirectory);

      while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "<Solution>.slnx")))
      {
          directory = directory.Parent;
      }

      Assert.NotNull(directory);

      var combined = Path.Combine([directory.FullName, .. segments]);
      Assert.True(File.Exists(combined), $"Expected file at {combined} to exist.");

      return combined;
  }
  ```
  Use the project's own solution-file name as the sentinel (e.g., `EventLogExpert.slnx` in this repo). If multiple solutions live under one repo, prefer `.git/` (a directory check) or a repo-specific marker file. **Audit lens**: `rg -t cs "Path\.GetFullPath\(Path\.Combine\(AppContext\.BaseDirectory.*\\.\\.\\.\\.\\." tests/` over the test tree — every match with ≥3 `..` segments is a candidate for the walk-up pattern. Each test project's first such helper should be promoted to its `TestUtils/PathFixtures.cs` per the *Default — per-project `TestUtils/`* section above; subsequent test files in the same project use the helper.
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
- **At authoring:** before writing each test, articulate the regression it would catch in one sentence. If you can't, don't write it. **Also** name one SUT behavior in scope that does not yet have a test — and decide whether that gap is acceptable for this commit.
- **During every test-mirror / refactor PR:** audit the existing tests in scope in *both* directions — delete tests that fail the "what regression would this catch" question; AND list every SUT behavior in scope that has no test. Rewrite eager tests as focused tests. Move slow tests out of the unit suite. Surface every observed gap in the PR description or session note.
- **When porting or decomposing tests** (slice rework, god-object split, file relocation): port verbatim in the mechanical commit so the diff stays reviewable, but capture the gap list in the same commit's session note / reviewer-panel prompts. Propose a follow-up "harden test surface" commit that adds the missing intent-driven tests. Never silently inherit a gap into the new file structure.
- **When a test breaks during a refactor with no behavior change:** that test was probably testing implementation, not behavior. Fix or delete the test rather than reverting the refactor.

**Test gap audit — missing tests are also defects (the second direction of [Core / Tests and Benchmarks](../../AGENTS.md#34-tests-and-benchmarks)).**

Every time you touch a SUT or its tests, run the audit in *two* directions, not one:

1. **Existing tests → kept or deleted** (covered by the rules above): does each test pin a real regression?
2. **SUT behaviors → covered or gap**: enumerate every behavior of the SUT in scope (every public/internal entry point, every documented failure path, every boundary, every branch of every `switch`/`if`, every reverse/descending mode, every null-valued or empty input, every integration seam) and ask which of them has *no* test.

The second direction is what catches the high-test-count gaps that hide behind green CI: "we have 11 tests for `SortEvents` ascending and zero for descending", "every reducer has a happy-path test and zero failure-path tests", "we test `MergeSorted` indirectly through one caller and never directly", "every column comparer has an ascending-only test and no null-valued-input test". A 1000-test file with one-direction coverage is *worse* than a 200-test file with two-direction coverage, because the high count gives false confidence and slows the next refactor.

**When code-reviewing a diff that touches tests OR a SUT branch**: do not only ask "is this test correct?" — also ask "does the SUT behavior the diff modifies have any test now? does it have one *that would have failed before the change and now passes*?" If a behavior change has no test with that property, the diff is incomplete (or the author's test is testing the wrong thing). Reviewers must NOT accept "tests pass and coverage didn't drop" as evidence of correctness — that only proves the existing one-direction tests still hold.

**Test name intent — the third segment names a domain outcome, not a return type.** The three-segment xunit convention is already shown by the `AGENTS.md` example `GetCustomer_WhenCaseDiffers_FindsExistingCustomer`. The third segment carries the test's intent and is where most regressions creep in: it must describe **what the SUT accomplishes for the caller**, not the literal shape of the value the assertion happens to inspect.

- **`_ShouldReturnTrue` / `_ShouldReturnFalse` / `_ShouldReturnNull` / `_ShouldReturnEmpty` are smells on any predicate, query, or boolean-returning property.** They mirror the assertion (`Assert.True(result)` ⇄ `_ShouldReturnTrue`) and tell a future reader nothing the `Assert` line doesn't already say. Rewrite the third segment in the SUT's domain vocabulary. Concrete patterns from past Filter-slice rework:
  - Predicate `MatchesDateFilter(...)` → `_ShouldReturnFalse` becomes `_ShouldFailDateConstraint` / `_ShouldRejectNullEvent`; `_ShouldReturnTrue` becomes `_ShouldSatisfyDateConstraint` / `_ShouldNotConstrainEvent` / `_ShouldTreatBoundaryAsInclusive`.
  - Predicate `MatchesFilters(...)` → `_ShouldReturnFalse` becomes `_ShouldExcludeEvent`; `_ShouldReturnTrue` becomes `_ShouldIncludeEvent` / `_ExcludeTakesPriority` / `_ShouldNotRequireIncludeMatch`.
  - Query `HasFilteringChangedFrom(...)` (`bool` return that means *"did the filter set semantically change?"*) → `_ShouldReturnTrue` becomes `_ShouldReportChange`; `_ShouldReturnFalse` becomes `_ShouldReportNoChange`. (Perception verb because the SUT's job is to *report*, not to *be*.)
  - Property `IsFilteringEnabled` (`bool` state) → `_ShouldReturnTrue` becomes `_ShouldBeEnabled`; `_ShouldReturnFalse` becomes `_ShouldBeDisabled`. (State verb because the SUT's job is to *be* in a state.)
- **Naming-family hint by SUT shape** — pick the verb family from the SUT's role, not from its return type:
  - **Action** (mutator, command): third segment = side-effect verb on the affected resource (`_ShouldDispatchOpenAction`, `_ShouldClearSelection`).
  - **Predicate** (`Matches…`, `Contains…`, `Allows…`): third segment = action verb on the outcome domain (`_ShouldExcludeEvent`, `_ShouldRejectNullEvent`).
  - **Query** (`Has…Changed`, `Get…Count`, `Find…`): third segment = perception/result verb (`_ShouldReportChange`, `_ShouldFindExistingCustomer`).
  - **Property / state accessor** (`IsX`, `HasX`, `CanX`): third segment = state-of-being verb (`_ShouldBeEnabled`, `_ShouldHaveDefaultColor`).
- **Acceptable mechanical forms — when the framework type IS the contract.** A literal type / value name in the third segment is fine when that type is exactly what the test pins: `_ShouldThrowArgumentNullException` (paired with the `ArgumentNullException.ThrowIfNull` rule above), `_ShouldThrowObjectDisposedException`, `_ShouldYieldEmptyEnumerable` when "empty enumerable" IS the documented contract (not just a side effect of an early return), `_ShouldReturnDefault` when `default(T)` is the documented sentinel. The discriminator: would the test name still be accurate if the SUT switched the return value's *encoding* (bool → enum, string → record) but kept the same caller-visible behavior? If yes, the name is intent-revealing. If the rename forces the test name to change, the name was tied to encoding (smell).
- **Audit lens — derivable-from-Assert is the smell test.** Read just the test method name and the `Assert.X(result)` line, with the body covered. If you can predict the third segment from the `Assert` line alone — `Assert.True(result)` ⇒ `_ShouldReturnTrue`, `Assert.Null(result)` ⇒ `_ShouldReturnNull` — the name carries zero information beyond the assertion and must be rewritten in domain terms. Conversely, if the third segment names a domain outcome (`_ShouldExcludeEvent`, `_ShouldReportNoChange`, `_ShouldBeDisabled`) that you couldn't have derived from the assertion alone, the name pulls its weight.
- **When the rule fires:**
  - **At authoring** — pick the third segment in domain vocabulary on the first draft; do not write `_ShouldReturnTrue` "to come back to later". The mechanical name will outlive the intent.
  - **During code review** — for every new or modified `[Fact]` / `[Theory]` in the diff, apply the audit lens above. Mechanical-name regressions on touched tests are a review block, same severity as the missing-test gaps in *Test gap audit* above. A diff that ports tests verbatim from a mechanical-naming source is exempt from the rewrite gate but must capture the rename list in a follow-up "harden test names" commit (mirrors the porting carve-out under *When to evaluate test purpose*).
  - **During every test-quality audit** — when scanning a touched test file, grep for `_ShouldReturn` / `_ReturnsTrue` / `_ReturnsFalse` / `_IsTrue` / `_IsFalse` in test method names and rewrite each in domain vocabulary, or document why the mechanical form is the contract (see *Acceptable mechanical forms* above).

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

**Negative tests need the stimulus, not just the wait.** This is the same rule as the *Exercise the negative case, don't infer it* bullet under *Test purpose / DO test*, restated here for the synchronization angle: a deterministic wait around no stimulus is still vacuous, just faster. The full pattern:

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
