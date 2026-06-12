---
applyTo: "**/*Tests*/**/*.cs,**/*Tests.cs,**/tests/**/*.cs,**/*Test/**/*.cs,**/*Test.cs,**/test/**/*.cs,**/*.Tests.csproj,**/*.UnitTests.csproj,**/*.IntegrationTests.csproj,**/*.FunctionalTests.csproj,**/*.AcceptanceTests.csproj,**/*.Test.csproj,**/*.UnitTest.csproj,**/*.IntegrationTest.csproj,**/*.FunctionalTest.csproj,**/*.AcceptanceTest.csproj"
---

# C# / .NET Test Infrastructure Instructions

> **Scope:** loaded automatically when the working set contains C# test files or test-project files. Extends the always-loaded `AGENTS.md` core AND the C# topic file `csharp.instructions.md` (which loads for any `.cs` / `.csproj`). The rules below apply specifically to test code — production C# rules live in `csharp.instructions.md`.

> **xUnit version note:** examples use **xUnit v3** syntax (the current shipping major). On v3, `IAsyncLifetime` inherits `IAsyncDisposable` and lifecycle hooks return `ValueTask`; `TestContext.Current` flows the cancellation token across `await` resumption points. xUnit v2 projects substitute `Task` for `ValueTask` and don't have `TestContext.Current` (pass `CancellationToken.None` or a per-test `CancellationTokenSource` instead).

---

## Tests — .NET test project layout (extends [Core / Tests and Benchmarks](coding-standards-code.instructions.md#34-tests-and-benchmarks))

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


---

> **Siblings:** `csharp-testing-quality.instructions.md` (test purpose, audit-and-delete), `csharp-testing-sync.instructions.md` (alternative patterns, test synchronization).
