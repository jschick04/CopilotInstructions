---
name: solution-architecture
description: .NET solution architecture reference covering root layout, VSA topology, DI conventions, test infrastructure, and deployment patterns.
triggers:
  - "solution architecture"
  - "new .NET solution"
  - "restructure solution"
---

# Playbook: .NET solution architecture

## Purpose

Generic .NET solution architecture reference aligned with [Microsoft's clean architecture guidance](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures#clean-architecture) and industry best practices. Extended with procedural detail for multi-library .NET solutions.

Use this playbook when:

- Bootstrapping a new .NET solution.
- Restructuring an existing solution onto the standard layout (also read `library-restructure.md` for per-library mechanics).
- Reviewing an architecture proposal or an extraction PR.

**When this playbook does NOT apply:**

- Single-project solutions, prototypes, or sample repos -- apply selectively at your discretion.
- Questions about where to put a single file -- consult `AGENTS.md` section 3.12 directly.
- Non-.NET solutions -- the principles may transfer but the procedural detail is .NET-specific.

The companion files own narrower scopes -- read them when their scope applies:

- `AGENTS.md` section 3.11 / 3.12 / 3.13 -- the universal rules. **Do not duplicate them here.** This playbook adds .NET-specific procedural detail.
- `csharp.instructions.md` -- C# / csproj / slnx specifics (layout, `IsTestProject`, slnx-comment-stripping, CI directory loops, root file inventory).
- `csharp-testing.instructions.md` -- test-project layout, TestUtils naming, fixtures, xUnit v3 lifecycle, Testcontainers.
- `library-restructure.md` -- consumer audit, behavior tracing, IVT vs public ladder, namespace migration.

---

## 1. Root folder layout

The root-file inventory (`Directory.Build.props`, `Directory.Packages.props`, `.editorconfig`, `global.json`) and `src/` + `tests/` convention are owned by `csharp.instructions.md` and `AGENTS.md` section 3.11. The restructure procedure (`git mv`, move config first) is documented in `AGENTS.md` section 3.11. This section covers only the **net-new** folders and files beyond those rules.

```
/
+-- .github/             # [Required]  CI workflows, PR templates, instructions, playbooks
+-- src/                 # [Required]  Production projects (one folder per csproj)
|   +-- <Project>/<Project>.csproj
+-- tests/               # [Required]  Test projects
|   +-- Unit/            # [Required when tests exist]  Fast, isolated unit tests
|   +-- Integration/     # [Required per section 3.13]  Environment-dependent tests
|   +-- Shared/          # [Conditional: >=2 test projects share utilities]
+-- docker/              # [Conditional: solution uses containers]
+-- docs/                # [Conditional: documentation beyond README.md]
+-- fork/                # [Conditional: vendored upstream fork needed]
+-- scripts/             # [Conditional: developer scripts exist]
+-- compose.yml          # [Conditional: paired with docker/]
+-- <Solution>.runsettings  # [Conditional: see section 5 caveat]
+-- <Solution>.slnx
+-- README.md
```

Per `AGENTS.md` section 3.13, `Unit/` and `Integration/` directories are structural decisions scaffolded up front. Conditional folders (docker/, fork/, scripts/, etc.) appear when their trigger condition is met -- do not scaffold speculatively.

### Folder notes

- **`docker/`** -- Dockerfiles and container-only assets (entrypoint scripts, healthchecks). `compose.yml` stays at the **root** so `docker compose` finds it by default.
- **`scripts/`** -- developer scripts: `run-integration-tests.ps1`, `bootstrap-env.ps1`, `build.ps1`. PowerShell preferred on Windows-first repos; add parallel `.sh` versions when the repo also targets Linux dev boxes.
- **`docs/`** -- long-form documentation, ADRs (`docs/adr/NNNN-title.md`), architecture diagrams. `README.md` at the root is the entry point.
- **`fork/`** -- last-resort vendored forks of upstream dependencies. One subfolder per upstream (`fork/<Upstream>/`), containing the upstream source (prefer git submodule) and a csproj built as `<ProjectReference>`. Document the fork, patches, and exit criteria in `fork/<Upstream>/README.md`. Track removal as an open issue labeled `vendored-fork`. Use only when: (1) upstream has a material defect, (2) a fix is in flight or maintainer is unresponsive, (3) no consumer-side workaround exists. Do not create `fork/` until the first fork lands.

### What does NOT belong at root

- Production or test csprojs (they live in `src/` or `tests/`).
- Per-project build configuration (belongs in csproj or `Directory.Build.props`).
- Loose `.cs` files. Everything compiles through a csproj.
- Generated artifacts (`bin/`, `obj/`, `TestResults/`) -- gitignored.

---

## 2. VSA within-assembly topology

The universal rules live in `AGENTS.md` section 3.12 (vertical slice + clean-architecture overlay, `Common/<Domain>/`, no kind-buckets, friend-grant precedence ladder). Read section 3.12 directly -- this section adds only what it does not spell out.

### Slice ownership

Each feature / domain slice owns its actions, reducers, effects, state, and commands. A slice keeps everything its actions touch unless another slice already imports it. The promotion gate follows section 3.12: **two or more current consumers** earn a `Common/<Domain>/` slot.

### `Common/<Domain>/` placement

When the first cross-slice consumer appears for a slice-internal type:

1. Run a fresh `grep` for the type across all slices and assemblies -- never trust a stale survey (`library-restructure.md` hard gate).
2. If exactly one cross-assembly consumer exists, promote to `public Common/<Domain>/<Type>.cs` rather than adding a new IVT grant (per section 3.12 precedence ladder -- IVT is last resort).
3. If two or more, promote to `Common/<Domain>/` and update consumers in the same PR.

### Shared coordination types

When decomposing a large class (section 3 below) and `private` fields are used by **multiple split classes** to coordinate concurrent operations (semaphores, cancellation sources, state flags), those fields must move to **named coordination types** registered as singletons -- never duplicated across the split classes.

Naming: `<Feature><Role>` -- e.g., a type holding a `SemaphoreSlim` + active-request set becomes a named concurrency-state type; a type orchestrating shutdown ordering becomes a named coordinator. These types live in the slice that owns the coordination, not in `Common/`.

---

## 3. Large class decomposition

Apply when a single class has **visibly distinct responsibility groups** (separate state, separate dependencies, separate call patterns). LOC is a signal to look, not a gate to act -- the responsibility-group test is the actual trigger.

### Before-splitting checklist

Before decomposing a large class, inventory:

1. **Public API surface** -- public constructors, public methods, DI registration shape, external `new` call sites.
2. **Private fields by responsibility** -- group by which methods use each field.
3. **Disposable ownership** -- which fields implement `IDisposable` / `IAsyncDisposable` and who owns disposal.
4. **Synchronization boundaries** -- timers, cancellation tokens, semaphores, async operation ordering.
5. **Direct `new` consumers** -- any code outside the assembly that constructs the class directly.

### Shared-state extraction

1. Fields used by **only one group** stay with that group's class.
2. Fields used by **multiple groups** become a cohesive named type registered as a singleton:
   - Group by role, not by data type. A `SemaphoreSlim` + `HashSet<string>` + `CancellationTokenSource` that together gate concurrent access become one named type, not three separate singletons.
   - Singletons get an `I<Name>` interface alias for tests, even when there is only one production implementation today (DI swap surface for fakes).

### Facade pattern (keep public interface stable)

When the class being split has external consumers, keep the original type as a thin facade behind its existing public interface (the GoF Facade pattern). The facade is an `internal sealed` implementation detail; the public contract is the interface.

```csharp
// The facade is internal -- only the interface is public.
internal sealed class OrderService : IOrderService
{
    private readonly OrderValidation _validation;
    private readonly OrderPersistence _persistence;

    public OrderService(
        OrderValidation validation,
        OrderPersistence persistence)
    {
        _validation = validation;
        _persistence = persistence;
    }
    // public ctor required: Microsoft.Extensions.DependencyInjection resolves
    // constructors via Type.GetConstructors() which returns public-only.

    public Task PlaceAsync(...) => _validation.ValidateAndPlace(...);
    public Task<Order?> GetAsync(...) => _persistence.GetAsync(...);
}
```

Per [Microsoft's DI guidelines](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection-guidelines), prefer constructor injection for split services so the DI container manages lifetimes and disposal. Only use direct `new` construction for pure helpers with no DI-managed dependencies, no disposal needs, and no lifetime concerns.

The split services are `internal sealed`. DI registers the facade and its dependencies:

```csharp
services.AddScoped<OrderValidation>();
services.AddScoped<OrderPersistence>();
services.AddScoped<IOrderService, OrderService>();
```

Tests for individual internal classes use `InternalsVisibleTo`; integration tests go through the facade interface.

When the class has no external consumers -- handler classes auto-discovered by a framework via assembly scanning are a typical example -- there is no facade. The split classes become the new surface, each registered independently.

### DI registration after a split

- **Framework-discovered classes** (e.g., MediatR handlers, any framework that scans assemblies for types via reflection) are auto-discovered by framework scanning. No manual entry needed. Note: ASP.NET Core hosted services (`IHostedService` / `BackgroundService`) are **not** auto-discovered - register them explicitly with `services.AddHostedService<T>()`.
- **Non-discovered split classes** need explicit registration. For singletons that also implement an interface:

  ```csharp
  services.AddSingleton<ConcurrencyState>();
  services.AddSingleton<IConcurrencyState>(sp => sp.GetRequiredService<ConcurrencyState>());
  ```

  The double registration (concrete + interface alias) is required only when production code resolves through the interface AND test harnesses resolve the concrete type directly. If tests can also resolve through the interface, prefer single registration: `services.AddSingleton<IConcurrencyState, ConcurrencyState>()`.

### Test harness for split classes

Create a harness in the test project that constructs every split class against shared singletons:

```csharp
private sealed class ServiceHarness
{
    public IConcurrencyState ConcurrencyState { get; }
    public FeatureAHandler FeatureA { get; }
    public FeatureBHandler FeatureB { get; }

    public ServiceHarness(/* fakes injected here */)
    {
        ConcurrencyState = new ConcurrencyState();
        FeatureA = new FeatureAHandler(ConcurrencyState, ...);
        FeatureB = new FeatureBHandler(ConcurrencyState, ...);
    }
}
```

This is the only place that knows the full construction graph. Per-test setup uses the harness -- when the harness signature changes, the compiler walks every test for free.

---

## 4. Per-library DI registrar convention

Per [Microsoft's guidance on registering groups of services](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/dependency-injection#register-groups-of-services-with-extension-methods), each library that registers services owns a single public extension method. Gate: apply when the solution has **>=2 libraries** or a library is consumed by an external solution. For single-library solutions, the composition root registering directly is fine.

### Convention

- **Method name:** `Add<SolutionPrefix><LibraryName>(this IServiceCollection services)` -- returns `IServiceCollection` for chaining.
- **Location:** `src/<Project>/DependencyInjection/<LibraryName>ServiceCollectionExtensions.cs`.
- **Namespace:** `Microsoft.Extensions.DependencyInjection` -- the convention used by Microsoft's own packages (`AddDbContext`, `AddHttpClient`, `AddLogging`). Extension methods in this namespace are discoverable without an extra `using`.
- **Scope:** registers only types owned by this library. Does not register dependencies from other libraries.

```csharp
namespace Microsoft.Extensions.DependencyInjection;

public static class OrderingServiceCollectionExtensions
{
    public static IServiceCollection AddMyAppOrdering(this IServiceCollection services)
    {
        services.AddSingleton<IOrderService, OrderService>();
        return services;
    }
}
```

### Composition root

The composition root calls each library's registrar explicitly:

```csharp
builder.Services
    .AddMyAppOrdering()
    .AddMyAppInventory()
    .AddMyAppNotifications();
```

**No bundling helper.** Do not write an `AddAll()` that calls every registrar -- it hides which libraries are used and breaks the delete-a-library diagnostic.

### Smoke test

Every library with a DI registrar ships a smoke test that resolves each host-facing interface:

```csharp
[Theory]
[InlineData(typeof(IOrderService))]
public void Registrar_ShouldResolveHostFacingAbstraction(Type serviceType)
{
    var services = new ServiceCollection();
    services.AddMyAppOrdering();
    using var provider = services.BuildServiceProvider(
        new ServiceProviderOptions { ValidateScopes = true, ValidateOnBuild = true });
    using var scope = provider.CreateScope();

    var resolved = scope.ServiceProvider.GetService(serviceType);

    Assert.NotNull(resolved);
}
```

This pattern enumerates the public API surface explicitly via `[InlineData]` -- adding a new public interface forces adding a test row. Using `CreateScope()` ensures scoped services resolve correctly. `ValidateOnBuild` catches missing dependencies at provider construction time.

When the library's services depend on types from other libraries or the host, the smoke test must supply those dependencies (e.g., `services.AddLogging()`, `services.AddSingleton<IExternalDep>(NullExternalDep.Instance)`). The test validates this library's registrar in isolation, not the full composition root.

**Limitations:** Keyed services require a `GetRequiredKeyedService` variant. Factory-only registrations are exercised but constructor params are not validated beyond what the factory does.

---

## 5. Integration test container gating

For most integration tests, use [Testcontainers for .NET](https://dotnet.testcontainers.org/) as described in `csharp-testing.instructions.md` -- it handles container lifecycle programmatically within the test process.

The pattern below applies when **external orchestration** is required instead: Windows containers (where Testcontainers support is limited), shared long-lived services across multiple test assemblies, or Docker engine-switching scenarios. Goal: tests **fail loudly** if the container environment is not configured. Integration tests do not skip -- they either run or fail with a clear remediation message.

### Components

1. **Assembly fixture** -- throws `InvalidOperationException` in the constructor if the required gate env var is not set. xUnit v3 assembly fixtures run once per assembly, providing one shared initialization point and one consistent failure reason. The gated assembly must contain **only** container-required tests; do not mix unit and integration tests in the same project.

   ```csharp
   public sealed class ContainerRequiredFixture
   {
       public ContainerRequiredFixture()
       {
           if (string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable("REQUIRE_CONTAINER")))
               throw new InvalidOperationException(
                   "Integration tests require the REQUIRE_CONTAINER env var. " +
                   "Run via scripts/run-integration-tests.ps1 or set the var manually.");
       }
   }

   [assembly: AssemblyFixture(typeof(ContainerRequiredFixture))]
   ```

2. **`compose.yml` at root** with one service per integration-test suite that needs a container.

3. **`scripts/run-integration-tests.ps1`** -- developer workflow script:
   - Switches Docker to the required engine mode if needed.
   - `docker compose up -d` to start services.
   - Sets the gate env var.
   - Runs `dotnet test tests/Integration/...` in a directory loop.
   - `docker compose down` in `finally`.

4. **CI** starts the required container services (e.g., `docker compose up -d` or equivalent runner-image setup) and sets the gate env var in the job env block. The wrapper script is not needed in CI, but containers must be running before test execution begins.

### `.runsettings` caveat

A root `.runsettings` file can inject the gate env var for `dotnet test --settings` invocations under **VSTest** mode. Note that native xUnit v3 / Microsoft.Testing.Platform does not honor VSTest RunSettings directly; partial support exists via `Microsoft.Testing.Extensions.VSTestBridge`. Treat the script + env var pattern as the primary portable mechanism; `.runsettings` is a convenience for VSTest-mode invocations only.

### `testenvironments.json` considerations

VS Test Explorer's Docker integration (`testenvironments.json`) provides container lifecycle for remote testing scenarios. However, it has known reliability issues with Windows containers (engine-switch handshake races test discovery). Evaluate for your scenario -- the script + env-var pattern is more portable when `testenvironments.json` proves unreliable.

---

## 6. Test project layout

Test-project layout, `IsTestProject` discipline, TestUtils naming, and IVT targeting are owned by `csharp-testing.instructions.md`. Read that file directly.

The additions below are solution-level conventions:

- Both `tests/Unit/<Lib>.Tests` and `tests/Integration/<Lib>.IntegrationTests` mirror the production project's folder structure 1:1. A test for `src/<Lib>/Foo/Bar.cs` lives at `tests/Unit/<Lib>.Tests/Foo/BarTests.cs`.
- Per `AGENTS.md` section 3.13, the per-library trio (`<Lib>` + `<Lib>.Tests` + `<Lib>.IntegrationTests`) is scaffolded up front as a structural decision. Integration test projects may remain empty until integration tests are written.
- `<Lib>.TestUtils` appears only when >=2 test projects share utilities (per `csharp-testing.instructions.md` escape hatch).

---

## 7. `_Imports.razor` and `GlobalUsings.cs` hygiene

Both files implicitly add `using` directives to every source file in the project. The failure mode is silent bloat.

### Usage-threshold heuristic

A namespace belongs in `_Imports.razor` or `GlobalUsings.cs` only when it is used by a significant majority of the project's source files. As a working heuristic, this playbook recommends **>=30%** usage as the threshold. This is not an industry standard -- it is a tuning knob to balance convenience against implicit-import bloat.

**Counting method:**
- Exclude generated files (`obj/`, `*.g.cs`, `*.razor.g.cs`, designer files).
- Require both >=30% **and** >=5 files using the namespace before adding it globally.
- When in doubt, leave it out. Per-file usings cost a line; project-wide usings cost compilation surface area and reader confusion.

### Acceptable `GlobalUsings.cs` content

- **Disambiguation aliases** that solve a real CS0104 across the project.
- **Truly pervasive namespaces** beyond what `<ImplicitUsings>enable</ImplicitUsings>` already provides.
- **Project-specific framework imports** that legitimately meet the threshold in the measured files.

### Audit cadence

Audit periodically -- at minimum when a library is restructured or a test project is split. Count file matches with `grep`, drop anything below the threshold.

---

## 8. Dependency graph rules

The csproj `<ProjectReference>` graph is the reviewable enforcement boundary for dependency direction. Compilation alone does not validate layering - a project can reference any other project and still compile. The rules below define which references are allowed; review `<ProjectReference>` entries against these rules to catch violations.

### Layering

Per Microsoft's clean architecture, dependencies flow **inward** -- outer layers depend on inner layers, never the reverse:

```
            Composition root
           /                \
          v                  v
  Presentation        Infrastructure
          \                /
           v              v
         Application Core
```

- **Application Core** (inner layer) -- domain types, application logic, interface definitions. No outward dependencies.
- **Presentation** and **Infrastructure** are peer outer layers that both depend on Application Core, but **not on each other**.
- **Composition root** references all layers to wire implementations to abstractions.

These are conceptual tiers describing dependency direction, not prescribed project names. Per section 3.12, project and folder names should be slice/domain-themed (e.g., `MyApp.Ordering`, `MyApp.Ordering.Persistence`); the tier name describes what role a library plays, not what it is called.

Tiers collapse when slices don't justify them -- a simple solution may have only Application Core + Composition.

### Rules

- **Application Core at the leaf.** Zero `<ProjectReference>` to Infrastructure or Presentation projects. Owns domain types, application logic, and interface definitions. May reference framework packages (`Microsoft.Extensions.Logging.Abstractions`, `System.Text.Json`).
- **Infrastructure depends only on Application Core.** Implements persistence, external service clients, and other interfaces defined by Application Core. Peer infrastructure dependencies indicate a type belongs in `Common/<Domain>/` of the core library, or the libraries should merge.
- **Presentation depends on Application Core.** Dispatches actions and renders state -- does not reference Infrastructure directly (except in the composition root for wiring).
- **Composition root composes everything.** References every library, calls each registrar (section 4), owns platform adapters. This is the only layer that references both Application Core and Infrastructure.
- **Data-access packages confined to Infrastructure.** EF Core, Dapper, and similar packages belong in the persistence library only. If transitive references leak data-access types into upper layers, hide them behind an interface owned by Application Core.

### Detection

- `dotnet list <Project> reference` -- direct references.
- `dotnet list <Project> package --include-transitive` -- grep for infrastructure packages (`EntityFrameworkCore`, `Dapper`, `Npgsql`) to find leaks.
- The DI smoke test (section 4) catches missing registrations from incorrect dependency direction.

---

## 9. Naming conventions

For the universal rules (domain-themed folders, no kind-buckets, `Common/<Domain>/`), see `AGENTS.md` section 3.12. The additions below are .NET-specific.

### Folders (within an assembly)

- **`DependencyInjection/`** -- the per-library registrar (section 4).
- **`Adapters/<Subsystem>/`** -- platform adapters (`Adapters/Settings/`, `Adapters/Telemetry/`, `Adapters/FileSystem/`). Adapters implementing Application Core interfaces live in Infrastructure-tier libraries; pure platform adapters with no Application Core contract may live in the composition root.

### Classes

- **Split classes** -- `<Feature><Responsibility>`. Examples: `OrderValidation`, `OrderPersistence`, `PaymentGateway`.
- **Coordination / state types** -- `<Feature><Role>`. Examples: `ImportCoordinator`, `ProcessingConcurrencyState`.
- **Adapters** -- `<Domain><Subsystem>Adapter`. Example: `UserPreferencesAdapter`.
- **Interfaces** -- `I<Name>` matching the concrete name. `IOrderService` for `OrderService`; `IConcurrencyState` for `ConcurrencyState`.

### Projects

- **Solution prefix on every project.** `<Solution>.<LibraryName>`. Avoids assembly-name collisions.
- **Test projects** mirror production: `<Project>.Tests`, `<Project>.IntegrationTests`.
- **Shared TestUtils** uses `.TestUtils` suffix (carve-out per `csharp-testing.instructions.md`).

### Files

- **One public type per file.** File name matches the type. Partial classes: one file per logical group.
- **Test files** suffix `Tests`: `OrderServiceTests.cs`.
- **DI registrar files** named for the extension class: `OrderingServiceCollectionExtensions.cs`.

---

## 10. Library extraction sequence

When extracting a library from an existing assembly, follow this procedure:

1. **Scaffold** -- create the empty library csproj + `<Lib>.Tests` + `<Lib>.IntegrationTests` (per section 3.13 trio). Register in slnx. Add `<Lib>.TestUtils` only when the >=2-consumer gate is met.
2. **Abstract** -- introduce the interface in the **producer** assembly. Wire consumers to the interface. This decouples consumers from the implementation type before any files move.
3. **Move** -- `git mv` the implementation files to the new library. Add `<ProjectReference>` from consumers. Keep the original namespace temporarily so the move is a pure file relocation.
4. **Rename** -- update namespaces to match the new library. Add `using` directives in consumers.
5. **Cleanup** -- remove temporary using aliases, drop empty folders left behind, verify no dangling IVT grants remain in the producer assembly.

Each step is a separate commit (or PR in a stacked workflow) so that `git bisect` can isolate regressions.

---

## Appendix A: Reusable precedent patterns

Patterns distilled from real restructures. These supplement the procedural guidance in sections 3-5 with concise decision rules.

### Timer lifecycle in async workflows

**Pattern:** When using disposable timers (`PeriodicTimer`, `System.Threading.Timer`), `await DisposeAsync()` (or `Dispose()`) **before** the final dispatch / state mutation.

**Anti-pattern:** `using` declaration or `Change(Infinite, Infinite)` -- neither waits for in-flight callbacks.

**Principle:** `Timer.Change(Infinite, Infinite)` only prevents future scheduling -- already-queued ThreadPool callbacks can still execute. Explicit disposal is the only ordering that guarantees no stale writes after the final operation.

### Narrow extraction surface (YAGNI for library boundaries)

**Principle:** When extracting a library, expose the narrowest public interface that satisfies current consumers. Defer hexagonal port-and-adapter splits until multiple consumers with divergent needs exist. One library with one public interface is simpler to maintain than three projects.

### Loud failure over silent skip

**Principle:** When a test suite requires an external dependency (container, service, network), fail loudly if the dependency is missing rather than skipping. Skipped tests look identical to passing tests in CI dashboards -- invisible non-execution is worse than a clear failure.

---

## Appendix B: cross-references

- `AGENTS.md` section 3.11 -- ecosystem-blessed layout, `src/` + `tests/` rule, restructure procedure.
- `AGENTS.md` section 3.12 -- VSA + clean-arch overlay, `Common/<Domain>/`, anti-kind-buckets, friend-grant precedence ladder.
- `AGENTS.md` section 3.13 -- plan structure for growth (folder + project + IVT decisions; not code decisions).
- `csharp.instructions.md` -- `IsTestProject` declaration, slnx-comment-stripping, CI directory loops, csproj `<InternalsVisibleTo>`, root file inventory, extension class naming.
- `csharp-testing.instructions.md` -- TestUtils per-project default, shared escape hatch, naming table, fluent-builder escape clause, xUnit v3 fixtures, Testcontainers.
- `library-restructure.md` -- consumer audit checklist, behavior tracing, namespace migration, test-mirror moves, IVT-vs-public decision procedure.
- `pre-implementation.md` -- multi-model panel gate before implementation.
- `post-code-change.md` -- hygiene sweep, least-privilege audit, multi-model reviewer panel.
- `multi-model-review.md` -- panel convergence pattern for architecture proposals.