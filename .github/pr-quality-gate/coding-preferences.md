# PR Quality Gate — Coding Preferences

Declarative coding-preferences metadata consumed by `gate-runner.ps1` (and `.sh` twin). Format per `README.md` §"coding-preferences.md (declarative metadata — NOT arbitrary shell)".

**RCE mitigation**: `params` JSON contains TYPED values per `check_type`; runner has switch/case on `check_type` and constructs invocations with explicit argv arrays (PowerShell `&` with array; bash `"${args[@]}"`). NEVER `Invoke-Expression` or string-eval.

**Analyzer binary + subcommand whitelist** (extend by amending gate-runner.ps1 + .sh + this list together):

| tool | allowed subcommands |
|---|---|
| `dotnet` | `format`, `build`, `test`, `restore` |
| `eslint` | (no subcommand; flags only) |
| `rubocop` | (no subcommand) |
| `flake8` | (no subcommand) |
| `mypy` | (no subcommand) |
| `shellcheck` | (no subcommand) |
| `clang-tidy` | (no subcommand) |

Unknown tool OR unknown subcommand → exit 2 at parse time (before any invocation).

## Wiring gap (READ THIS BEFORE THE TABLE)

`coding-preferences.md` rows are read by `gate-runner.{ps1,sh}` for the `prefs_revision` header, but per-row `check_type` dispatch is NOT yet implemented in the runner (only `pattern-catalog.md` entries are executed today). Until the wiring lands, rows in this file serve as the canonical documentation of enforced rules, and the actual rg/analyzer checks live as parallel entries in `pattern-catalog.md`. The `severity` column reflects the rule's intent once wired — actual blocking behavior today comes from the catalog mirror, not from this file. Fixing the wiring gap is a separate scope.

## Preferences

<!-- Schema: | slug | check_type | params (JSON) | scope | severity |
     params shape per check_type:
       rg              : {"pattern":"<regex>","globs":["<glob>",...]}
       rg-negative     : {"pattern":"<regex>","globs":["<glob>",...]}  (expects zero hits)
       commit-message-rg          : {"pattern":"<regex>","target":"HEAD"}
       commit-message-rg-negative : {"pattern":"<regex>","target":"HEAD"}
       commit-message-line-count  : {"max_lines":<int>,"target":"HEAD"}
       analyzer        : {"tool":"<whitelisted-tool>","subcommand":"<whitelisted-or-empty>","args":["<arg>",...]} -->

| slug | check_type | params | scope | severity |
|---|---|---|---|---|
| lock-not-object | rg | {"pattern":"private (readonly )?object _\\w+Lock","globs":["*.cs"]} | diff | blocking |
| minimal-comments | rg | {"pattern":"\\b(Slot \\d+\|R\\d+ (finding\|fix\|round\|rework\|ready)\|PR \\d+\\+\\d+\|pre-(implementation\|PR-creation) panel)\\b","globs":["*.cs"]} | diff | blocking |
| no-coauthored-by | commit-message-rg | {"pattern":"^Co-authored-by:","target":"HEAD"} | commit | blocking |
| single-line-commit | commit-message-line-count | {"max_lines":1,"target":"HEAD"} | commit | blocking |
| no-conventional-commit-prefix | commit-message-rg-negative | {"pattern":"^(feat\|fix\|chore\|docs\|test\|refactor\|style\|perf\|ci)(\\(.+\\))?: ","target":"HEAD"} | commit | blocking |
| sorted-usings | analyzer | {"tool":"dotnet","subcommand":"format","args":["--verify-no-changes","--include-generated","false"]} | diff | blocking |
| file-scoped-namespaces | rg-negative | {"pattern":"^namespace \\S+ \\{","globs":["*.cs"]} | diff | blocking |
| allocation-free-stopwatch | rg | {"pattern":"Stopwatch\\.StartNew\\(\\)\|new Stopwatch\\(\\)","globs":["*.cs"]} | diff | blocking |
| no-null-forgiving | rg | {"pattern":"\\b[a-zA-Z_]\\w*!\\.\|\\b[a-zA-Z_]\\w*!\\[","globs":["*.cs"]} | diff | blocking |
| no-trailing-whitespace | rg-negative | {"pattern":" +$","globs":["*.cs","*.razor","*.razor.cs","*.md"]} | diff | non-blocking |

## Notes

- **`lock-not-object`** enforces user's "use `Lock` type, not `object`" preference (C# 9+ `System.Threading.Lock`). The rg pattern `object _\w+Lock` catches the legacy `private readonly object _xxxLock = new()` form; the `Lock` form (`private readonly Lock _xxxLock = new()`) does not match this regex.

- **`no-coauthored-by`** rejects `Co-authored-by:` trailers in commit messages per user's preference (commits are agent-or-user owned, never both).

- **`single-line-commit`** enforces single-line commit messages — no body, no footer. Co-authored-by trailers would also be caught by this rule, but `no-coauthored-by` provides a more specific error message.

- **`no-conventional-commit-prefix`** rejects `feat:`, `fix:`, `chore:`, etc. prefixes per user's preference (commit subjects are natural prose, not Conventional Commits format).

- **`sorted-usings`** runs `dotnet format --verify-no-changes --include-generated false` over the diff-scoped file set. Non-zero exit = formatting violation = preference violated.

- **`file-scoped-namespaces`** rejects block-scoped `namespace Foo { ... }` declarations. C# file-scoped namespaces (`namespace Foo;`) preferred per user's style.

- **`allocation-free-stopwatch`** rejects `Stopwatch.StartNew()` and `new Stopwatch()` in favor of the allocation-free pair available since .NET 7: `var t = Stopwatch.GetTimestamp(); ... var elapsed = Stopwatch.GetElapsedTime(t);`. The instance form heap-allocates a `Stopwatch` object for short-lived timing; the timestamp form uses two stack-only API calls. Override is acceptable only when the surrounding code genuinely needs the instance API (`Restart`, `Reset`, observable `IsRunning` state) — in that case, dismiss the violation with the source-grounded rationale citing the specific method called.

- **`no-null-forgiving`** rejects the C# null-forgiving operator (`!`) on **member access** (`obj!.Prop`) and **index access** (`arr![0]`) — the patterns that silently disable compiler nullability analysis at a use site. User strongly prefers explicit null-handling: store the non-null expression in a local variable BEFORE the access, OR introduce an explicit null check + early return, OR fix the upstream nullability annotation. The `!` operator hides real null-deref risks; the local-variable pattern lets the compiler reason about it. Override only when interfacing with non-nullable-annotated third-party APIs that genuinely return non-null — and even then, prefer a one-line wrapper method that performs the check explicitly. **NOT flagged** (acceptable Blazor idioms): `[Inject] ... = null!;` initialization, `RenderFragment ... = null!;`, `Value = default!;` — these are property initializers required by Blazor's lifecycle/DI contract (the framework sets the value before the property is read). **Logical NOT (`!foo`, `!isOpen`) is unaffected** — the regex matches identifier-followed-by-`!`-followed-by-`.`-or-`[`, never `!`-followed-by-identifier.

- **`no-trailing-whitespace`** is non-blocking — surfaces in QUALITY GATE block but doesn't gate commit. Easy to fix post-PR if missed.

- **`minimal-comments`** enforces the system-prompt rule "only comment code that needs a bit of clarification; do not comment otherwise." The rg pattern catches the *unambiguous* surface-level violation — panel/PR artifact references in `.cs` source (slot numbers, round-N verdict tokens like `finding`/`fix`/`rework`/`ready`, PR-bundle labels like `PR 1+2`, panel-phase names). These never belong in shipped source. Per the Wiring-gap section above, the `blocking` severity is documentary; today's actual enforcement comes from the mirror entry `panel-artifact-leakage` in `pattern-catalog.md`. The broader semantic judgment ("is this comment genuinely necessary at all?") cannot be detected by regex and is enforced by the `comment-necessity` review-pass-only entry in `pattern-catalog.md`, which is forwarded to every panel reviewer. The narrow rg scope avoids tree-wide false positives on pre-existing `<remarks>` blocks (semantic judgment, not surface pattern). Override only when the panel-artifact reference is genuinely required (e.g., a test class literally named after a panel slot in a meta-project) — dismiss with the source-grounded rationale on the specific line.

- **`publication-barrier-order`** (documentation-only; semantic enforcement via `pattern-catalog.md#publication-barrier-order` review-pass-only) — in a writer method that updates multiple fields under a lock AND uses `Volatile.Write` / `Interlocked.Exchange` / `Interlocked.CompareExchange` as a publication barrier, the volatile/interlocked write must happen LAST. The .NET memory model guarantees writes preceding a `Volatile.Write` aren't reordered past it; cross-thread readers that observe the published value are guaranteed to see prior writes. If the publication is first/middle, plain-field writes can still be observed by cross-thread readers as stale (the lock's release barrier only fires on `Monitor.Exit`; readers using a different lock or no lock can observe partial state during the writer's lock body). The mirror clear-path pattern: clear plain fields first, then write the sentinel id LAST. Rule is reviewer-driven because identifying "intended publication barrier" requires reading the writer's intent.

- **`event-ordering-test-subscription`** (documentation-only; semantic enforcement via `pattern-catalog.md#event-ordering-test-subscription` review-pass-only) — when a test asserts ordering between an event invocation and a subject-action (e.g., TCS completion that resumes an awaiter), the test's event subscription must happen AFTER any non-asserted setup action that fires the same event. Subscribing before a setup `Show()`/`Initialize()`/`Open()` that fires the event causes the setup-fired event to satisfy the assertion flag, masking whether the subject-action-fired event actually preceded the awaiter. The test then passes regardless of correctness. Fix options: (a) move `+= ...` AFTER setup, (b) count event invocations and assert on the Nth, (c) reset the flag between setup and subject-action. Rule is reviewer-driven because identifying "the test asserts ordering" requires structural reading.

- **`strongly-typed-ids`** (documentation-only; semantic enforcement via `pattern-catalog.md#strongly-typed-id-preference` review-pass-only) — when introducing a new logical ID domain in `.cs` code, prefer a `public readonly record struct XxxId(Guid Value)` wrapper with `static Create()` factory over a primitive `Guid`/`long`/`int`/`string`. Applies to fields/properties/parameters/locals with `Id`/`ID`/`id` suffix AND primitive IDs introduced through generic type arguments (e.g., `Dictionary<long, ModalSession>` collection keys). Mirrors the codebase's established pattern (`FilterId`, `FilterGroupId`, `BannerId`, `EventLogId`, `StatusActivityId`, `UpgradeBatchId`). Strongly-typed IDs prevent accidental cross-domain ID confusion (e.g., passing a `FilterId` where a `BannerId` was expected — caught at compile time). **NOT flagged** (acceptable): extensions of legacy primitive-ID subsystems where switching one site would create inconsistency (reviewer must cite the specific pre-existing primitive surface); EF Core entity row IDs that mirror the database schema; Blazor framework-required `[Parameter] string Id` and `[Parameter] Guid Id`; Windows platform IDs (`ushort EventId`); interop / P/Invoke handles; correlation/trace/diagnostic tokens not crossing domain boundaries. Regex cannot reliably detect "new domain vs extension"; rule is reviewer-driven.

- **`prefer-async-suffix`** (documentation-only; semantic enforcement via `pattern-catalog.md#prefer-async-suffix` review-pass-only; partial rg coverage via existing `async-correctness` hybrid pattern for `.Result`/`.Wait()`/`SaveChanges()`) — inside a genuinely async method (has the `async` keyword OR body contains `await`), call the `Async`-suffixed sibling of any method that has one. Common high-signal sites: `DbConnection.Open` / `SqliteConnection.Open` / `SqlConnection.Open` → `OpenAsync` (note: `IDbConnection` itself does NOT define `OpenAsync`); `DbContext.SaveChanges` → `SaveChangesAsync`; `Stream.Dispose` → `await DisposeAsync`; `CancellationTokenRegistration.Dispose` → `DisposeAsync`; `HttpClient.Send` → `SendAsync`; `IDbContextFactory<T>.CreateDbContext` → `CreateDbContextAsync`. Sync calls in async methods either block thread-pool threads (real perf hit at scale) or signal a missed async opportunity. **NOT flagged** (acceptable): types without an Async sibling (`Utf8JsonReader.Read`, `Process.Start`, `ILogger.Debug`, `Math.Sqrt`); sync bridge/adapter implementations of an async-shaped contract that return `Task.CompletedTask`/`Task.FromResult` without `await` (these are not actually async); the synchronous form is required by a framework contract; explicit diagnostic-only sync I/O where the cost is intentional and commented. Overlap with `async-correctness` rg (which catches `SaveChanges()`/`.Result`/`.Wait()`): when `async-correctness` already surfaced a finding on a line, do NOT duplicate-flag under `prefer-async-suffix`. Regex cannot reliably resolve "does an Async sibling exist on this exact type"; rule is reviewer-driven.

- **`event-completion-fault-isolation`** (documentation-only; semantic enforcement via `pattern-catalog.md#event-completion-fault-isolation` review-pass-only) — when a writer method invokes a public event OR a caller-supplied callback (`Action`, `Func<T>`, `Action<T>`, custom delegate parameter) and then completes a `TaskCompletionSource` (or invokes a captured cancel/resume delegate), wrap the event/callback invocation in `try`/`finally` so the completion runs even when a subscriber/callback throws. Pattern that hangs awaiters: ``StateChanged?.Invoke(); tcs.TrySetResult(value);`` or ``onComplete?.Invoke(); tcs.TrySetResult(value);``. Pattern that doesn't: ``try { StateChanged?.Invoke(); } finally { tcs.TrySetResult(value); }``. Applies to `TrySetResult`/`TrySetCanceled`/`TrySetException` and captured cancel-delegate invocations. Subscriber/callback exceptions still propagate to the caller after `finally`, preserving diagnostics. Rule is reviewer-driven because the writer's intent (is the completion semantically gated on subscriber outcome?) requires judgment.

- **`test-aaa-pattern`** (documentation-only; semantic enforcement via `pattern-catalog.md#test-aaa-pattern` review-pass-only) — new test methods follow the Arrange/Act/Assert convention with explicit `// Arrange`, `// Act`, `// Assert` line-prefixed comment markers, matching the established codebase convention. Pure state-assertion tests with no Act phase may use `// Arrange` + `// Assert` only. Pre-existing tests in modified files that predate the convention are NOT in scope (separate cleanup work). Rule is reviewer-driven because detecting "the test has a discernible setup → action → verification flow" requires structural reading.

## Wiring gap

`coding-preferences.md` rows are read by `gate-runner.{ps1,sh}` for the `prefs_revision` header, but per-row `check_type` dispatch is NOT yet implemented in the runner (only `pattern-catalog.md` entries are executed today). Until the wiring lands, rows in this file serve as the canonical documentation of enforced rules, and the actual rg/analyzer checks live as parallel entries in `pattern-catalog.md`. Duplicates the up-front Wiring-gap note above for readers who jumped past the table.

## Maintenance

Adding a new preference requires:
1. New row in this table with appropriate `check_type` + `params` JSON
2. If the check needs a new `check_type` enum value, amend `gate-runner.ps1` and `gate-runner.sh` to implement it
3. If the `analyzer` invokes a new tool, add to the whitelist table above AND to `gate-runner.{ps1,sh}` validation
4. Commit all three files together (no partial updates)
