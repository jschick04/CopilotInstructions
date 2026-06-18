---
applyTo: "**/*Tests*/**/*.cs,**/*Tests.cs,**/tests/**/*.cs,**/*Test/**/*.cs,**/*Test.cs,**/test/**/*.cs,**/*.Tests.csproj,**/*.UnitTests.csproj,**/*.IntegrationTests.csproj,**/*.FunctionalTests.csproj,**/*.AcceptanceTests.csproj,**/*.Test.csproj,**/*.UnitTest.csproj,**/*.IntegrationTest.csproj,**/*.FunctionalTest.csproj,**/*.AcceptanceTest.csproj"
---

# C# / .NET Test Synchronization & Alternative Patterns Instructions

<!-- read-receipt-token: b67d19d1 -->

> **Scope:** loaded on C# test files. Contains alternative test-infrastructure patterns and test synchronization rules. Siblings: `csharp-testing.instructions.md` (layout, naming, constants), `csharp-testing-quality.instructions.md` (test purpose, audit).

---
## Patterns this rule does NOT replace

The per-project `TestUtils/` + shared `<Solution>.<Domain>.TestUtils/` escape hatch is **one viable approach** for organizing test infrastructure. Several established alternative patterns address different problems or different trade-offs - they are NOT eclipsed by this rule and may coexist with it. When the per-project default genuinely fails for your slice, the alternatives below are valid escape hatches in their own right.

- **Test base classes** (e.g., `IntegrationTestBase`, `DatabaseTestBase`): inheritance-based code sharing common in older xUnit codebases. Trade-off: tight coupling via inheritance, harder to compose, subclasses can override base behavior in incompatible ways. **Use case**: shared setup / teardown that genuinely applies to every test in a category AND a `[Fact]` / `[Theory]` method-decoration approach doesn't fit. **Prefer xUnit fixtures over test base classes** when the shared concern is lifecycle / resource (database, container) rather than helper-method reuse.

- **Object Mother pattern** (Fowler's article describes the pattern; name was coined on a ThoughtWorks project - *not* in *Patterns of Enterprise Application Architecture*): one class per domain object with named static instances (e.g., `Customers.ValidGold`, `Customers.LapsedRenewal`). **Mostly subsumed by** this rule's `<Domain>TestFixtures` (named static instances pattern) - the naming convention is different but the structural pattern is the same. Use `<Domain>TestFixtures` to match this rule; reach for the literal "Object Mother" naming only when the codebase has historical precedent. The scenario-catalog role (named instances collectively documenting domain-relevant test states) carries over.

- **AutoFixture / Bogus**: **anonymous test-data / fake-data generation** (NOT property-based testing - that's a separate category, e.g., **FsCheck** for .NET). AutoFixture creates anonymous specimen values for varied inputs without per-field arrangement; Bogus generates plausible-looking fake names / addresses / etc. **Use case**: tests need lots of similar-but-not-identical objects, compact construction of complex object graphs where most fields don't matter, or fake-but-realistic seed data. **Trade-off**: less explicit test data - readers must trust the framework's generator. **Compatible with this rule**: use AutoFixture / Bogus *inside* `<Domain>Builder` - whether the Builder is a `Create...` factory (`<Domain>Builder.Create()` calls AutoFixture for default fields) or a fluent builder (`new <Domain>Builder().With...().Build()` calls AutoFixture for unspecified fields). The domain-named builder still carries intent at the call site.

- **Property-based testing** (separate category): **FsCheck** (.NET port of QuickCheck) generates inputs against invariants ("for all `x`, predicate holds"). Different mental model from anonymous-data generation - you write the *property*, the framework explores inputs. **Use case**: invariants that must hold across input space (commutativity, idempotency, round-trip serialization). **Not subsumed by this rule**: property-based tests typically live in their own per-project test classes and don't need shared TestUtils infrastructure for the generators (those come from FsCheck itself).

- **HTTP / service-boundary virtualization** (separate category from container-based integration): `WebApplicationFactory<T>` / `TestServer` (Microsoft ASP.NET Core) for in-process API testing without Docker; **WireMock.Net** for stubbing external HTTP dependencies in integration tests; **MockServer** (the external server / container; configure from .NET via `MockServer.Net.Client`) for stubbing external HTTP dependencies that need cross-language sharing; **RichardSzalay.MockHttp** for `HttpClient` message-handler mocking in unit tests. **Use case**: testing code that talks HTTP to other services without booting real containers. **Placement**: per-project `TestUtils/<Topic>Utils.cs` (e.g., `HttpUtils.cs` containing a configured `HttpClient` factory) or behind xUnit fixtures when the lifecycle is expensive.

- **Testcontainers**: real infrastructure for integration tests (databases, queues, APIs). See the dedicated *Integration-test infrastructure with Testcontainers* section above. **Placement**: behind xUnit `ICollectionFixture<T>`, not inside `<Domain>Builder` / `<Domain>Fixtures`. **Use case**: integration tests against real dependencies when in-process simulation (`WebApplicationFactory<T>`, in-memory fakes) isn't faithful enough.

- **Per-slice in-memory fakes** (e.g., `InMemoryRepository<T>` co-located within each slice's test project): the slice owns its test infrastructure end-to-end. **Compatible** when one slice owns the fake and no other consumer needs it (the fake IS the slice's `<Domain>Fixtures`-equivalent - a parameterized factory for SUT setup using an in-memory backend). **Competes** with this rule when ≥2 slices duplicate the same fake AND a team deliberately keeps both copies per-slice to preserve VSA slice independence over DRY. That's a legitimate VSA-over-DRY trade-off - document the choice explicitly so future contributors understand the deviation from the shared-promotion trigger.

- **xUnit fixtures** (`IClassFixture<T>`, `ICollectionFixture<T>`, assembly fixtures (v3)): runtime lifecycle / resource sharing within ONE test assembly. **Orthogonal to this rule** (which addresses compile-time code / constant sharing across MULTIPLE test assemblies). Both compose freely - a shared `<Domain>Fixtures.CreateConfiguredService(...)` can be called inside an `IClassFixture<T>` constructor, for example.

- **`InternalsVisibleTo` for white-box testing**: separate coupling decision per AGENTS.md §3.12. This rule's "Internal-type dependency check" already addresses the IVT trade-off for shared TestUtils helpers; for direct white-box testing of internal SUT types (without a TestUtils intermediary), follow §3.12's friend-grant proliferation precedence ladder.

When choosing among these patterns for a new test project, **start with this rule's per-project `TestUtils/` default**. Reach for alternatives only when the per-project default genuinely fails for your slice, and document the choice in the test project's README / `CONTRIBUTING` so future contributors understand the deviation.

---

## Test synchronization - eliminate `Thread.Sleep`, fail-fast on regression

`Thread.Sleep(N)` in a test means "the test thread spins its wheels for N milliseconds, then checks what happened." It is wrong in both directions: too short and the test is flaky; too long and the suite is slow. Worse, in regression cases the test still waits the full N before failing, hiding the diagnostic signal. Whenever the SUT exposes a callback, event, or other observable signal, replace `Thread.Sleep` with deterministic synchronization on that signal.

**Replace `Thread.Sleep(N)` with the most precise primitive available, in this order of preference:**

1. **`ManualResetEventSlim` / `CountdownEvent` - when a callback or event signals completion or arrival.** Add the signal in the handler, then `signal.Wait(TimeSpan.FromMilliseconds(N), TestContext.Current.CancellationToken)`. Strictly better than `Thread.Sleep`:
   - **Positive case** (event expected): the test wakes the moment the event fires - usually well before N ms.
   - **Regression case** (unexpected event): the wait returns `true` immediately when the spurious event signals; assert `Assert.False(received, "...")` and the test fails with a precise message, not a timeout.
   - **Cancellation**: honors `TestContext.Current.CancellationToken` so the suite can stop a hung test cleanly.
2. **`await Task.Delay(TimeSpan, ct)` in `async Task` tests - when you genuinely need to space test stimulus** (e.g., asserting events arrive in order with bounded gaps between writes). Cooperative-cancellation friendly and non-blocking. Convert the test signature from `void` to `async Task` to enable this; xUnit v3 supports it natively and `TestContext.Current` flows across `await` resumption points.
3. **`Thread.Sleep(N)` - only as a last resort**, and only when no observable signal exists from the SUT. Acceptable cases are narrow:
   - A no-subscribers smoke test where there is literally no callback to wait on.
   - A stress test where the sleep is *itself* the test mechanism - deliberate scheduler jitter inside `Parallel.Invoke` to interleave operations under contention, or a SQLite file-handle release backoff. These are not event waits; removing them defeats the test's purpose.
   - When kept, the test (or the immediately surrounding code) must include a comment explaining *why* a signal-based wait is impossible.

**Negative tests need the stimulus, not just the wait.** This is the same rule as the *Exercise the negative case, don't infer it* bullet under *Test purpose / DO test*, restated here for the synchronization angle: a deterministic wait around no stimulus is still vacuous, just faster. The full pattern:

```csharp
int eventCount = 0;
var received = new ManualResetEventSlim(false);

watcher.LogEntryWritten += (_, _) =>
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

**Document non-obvious SUT contract dependencies with a one-line in-test comment.** When a test's correctness depends on a particular SUT guarantee - e.g., *"`Unsubscribe()` blocks until in-flight callbacks complete, so no handler can fire between the count capture and the `Reset()`"* - record that dependency where someone reading the test can see it. Reviewers cannot audit a contract they cannot see; future SUT optimizations that break the contract will silently flake the test.

**Thread-safety on shared state read by both the test thread and a callback thread.** When a callback fires on a non-test thread (timer, native event, `RegisteredWaitHandle`, `Parallel.Invoke` worker, etc.) and the test thread reads the result, prefer thread-safe primitives:

- `int eventCount = 0;` + `Interlocked.Increment(ref eventCount)` in the handler + `Volatile.Read(ref eventCount)` in the assertion - for negative tests where you only care about *whether* and *how many* events arrived.
- `ConcurrentBag<T>` / `ConcurrentQueue<T>` - when you need the actual records.
- A regular `List<T>.Add` from a callback thread + `.Count` from the test thread is a data race even when it usually works in practice; use it only when the callback is guaranteed not to fire concurrently with the assertion (rare, and worth a comment).

**Sleep-style anti-patterns to flag during review:**

- `Thread.Sleep(small)` followed by `Assert.Empty(list)` / `Assert.Equal(0, count)` with no stimulus between them: vacuous negative test - add the stimulus or delete the test.
- `Thread.Sleep(large)` followed by `Assert.NotEmpty(list)`: positive test with a slow guard band. Replace with `signal.Wait(large, ct)`; the test now usually completes in <1 ms while still tolerating slow CI.
- `Thread.Sleep(any)` inside a `Parallel.Invoke` / `Parallel.For` worker that *is* the SUT under stress test: NOT an event wait - it's deliberate jitter for thread-interleaving. Keep, but comment it explicitly so the next person doesn't "clean it up".
- `await Task.Delay(N)` without a `CancellationToken` argument: convert to `await Task.Delay(N, ct)` so the suite's cancellation works.
- `Thread.Sleep` alongside `Assert.True(thingHappened)` with no signal-based wait: replace the entire pattern with `Assert.True(signal.Wait(timeout, ct), "thingHappened did not happen within timeout")`.

**When to apply this rule:**

- **At authoring:** any new test that needs to wait for an asynchronous event uses a signal, not a sleep. `Thread.Sleep` in a new test is a review block unless it falls in one of the narrow last-resort cases above.
- **During every test-quality audit:** grep the touched files for `Thread.Sleep` and `Task.Delay(`. Each occurrence is either replaced with a signal-based wait, or kept with a comment explaining why a signal is impossible.
- **When a test goes flaky:** if the flake is at a `Thread.Sleep` boundary, the fix is the signal-based primitive - not bumping the sleep duration. Bumping the sleep masks the symptom and makes the suite slower for everyone.
