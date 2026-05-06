---
applyTo: "**/*.cs,**/*.csx,**/*.csproj,**/*.razor,**/*.razor.cs,**/*.cshtml,**/*.aspx"
---

<!-- CopilotInstructions: SENTINEL csharp -->

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
- **XML doc comments on NEW public/internal API: default OFF.** Only add when the type/method signature genuinely cannot express the contract — e.g., a non-obvious failure mode (`/// <returns>true on success; false if the OS denied the request — caller must surface to the user.</returns>`), or a non-obvious thread-safety guarantee. Method names like `TryGet…` / `…Async` / `Copy…` already encode their contract. Do NOT preemptively document "for future maintainers" — the signature IS the doc.
- **Existing XML doc comments stay** — don't reformat or expand them when touching surrounding code.

**Common XML-doc failure modes flagged in past reviews:**
- Adding `/// <summary>` to a private field "to explain the race-handling design." Wrong — rename the field or, if a single short line truly is needed, use a single `// ` above the field.
- Adding a 3-line XML `<summary>` paragraph on a new public interface explaining "implementations are best-effort, any failure is logged and swallowed so callers can fire-and-forget." This is contract prose that belongs in the PR description; the method signature + a `Task` return + the implementation's try/catch already say it. If "best-effort" really must be in the doc, write `/// <summary>Best-effort copy; failures are logged and swallowed.</summary>` — one sentence.

> Universal `//` comment failure-mode examples (e.g., the "Same best-effort contract as `CopySelectedEvent`" case) live in [Core / Comments](../../AGENTS.md#31-comments) under "Common failure modes flagged in past reviews" — not duplicated here.

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

---

## C#-specific recurring code smells (extends [Core / Recurring code smells](../../AGENTS.md#310-recurring-code-smells-from-past-pr-reviews))

The universal smells in `AGENTS.md` (constants single source of truth, list-of-X must reference constants, sibling-constant consistency, test specificity vs `Arg.Any<T>()`, negative assertions weak, don't materialize streams, lambda parameter shadowing, failure paths surface user-visible feedback, comment / path hygiene, idempotency / multi-dispatcher guards, exception messages stay diagnostic, log messages match path, log messages match return, test portability — no hardcoded system paths or locales, no dead branches inside loops with same termination condition) all apply here. The bullets below are the C#-specific additions.

- **Native interop return-value validation — audit while you're there.** Whenever you touch a Win32 / P/Invoke call site, validate every native return value that can be `IntPtr.Zero` / `NULL` / `INVALID_HANDLE_VALUE` for the *entire* sequence in that block — not just the one you came to fix. `LoadResource`, `LockResource`, `LoadLibraryEx`, `OpenProcess`, `CreateFile`, `RegOpenKeyEx`, `FindResourceEx`, etc. all return failure sentinels that, if dereferenced (`Marshal.ReadInt32`, `Marshal.PtrToStructure`, `Marshal.PtrToStringUni`), crash the process. PR reviewers always read the surrounding native sequence; do the same in self-review and add `if (handle == IntPtr.Zero) { log; continue/return; }` guards before any Marshal read.
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

### Null-forgiving operator (`!`) — avoid

- **Do not use the `!` (null-forgiving / "damn-it") operator to silence nullable warnings.** It tells the compiler "trust me" without doing the work to actually prove the value is non-null at the use site. If the assumption is wrong (or becomes wrong after a refactor), the result is a `NullReferenceException` at runtime instead of a compile-time error — exactly the class of bug nullable reference types exist to prevent.
- **Do the actual work to make the value non-null.** In order of preference:
  - **Restructure to remove the nullable**: change a method signature, model field, or carrier type so the value cannot be null at the call site. Examples: parameter typed `Foo` instead of `Foo?`; split a state union so the "has-value" arm carries a non-nullable; surface the value through a constructor instead of a settable property.
  - **Pattern-match into a non-null local with `is { }`** at the narrowest scope that needs it: `if (value is { } nonNull) { ... use nonNull ... }`. Inside the block, `nonNull` is the non-nullable type, including across lambda captures.
  - **`when` clause on a `case` label**: `case Foo when value is { } nonNull:` narrows in the case body and is captured cleanly by lambdas inside that body. This is often the cleanest fix in `switch`/Razor `@switch` blocks where one arm semantically requires a value to be present.
  - **Early-return / early-break narrowing**: `if (value is null) { return; }` then continue with `value` (now narrowed) for non-lambda uses. Note: lambdas capture the *original* nullable type, so for a lambda that needs the value, prefer one of the patterns above OR copy into an explicitly-typed non-nullable local first (`Foo nonNull = value;` after the null check).
  - **Throw with a meaningful message** when reaching the use site without a value is genuinely a contract violation: `var nonNull = value ?? throw new InvalidOperationException("Foo must be set before BarAsync runs.");`. The thrown exception has to name what's missing and why it's required.
- **Particularly avoid sprinkling `!` inconsistently across multiple uses of the same value** (e.g., `@x!.A` followed by `@x.B` in Razor markup, or `x!.Method()` followed by `x.Property` in C#). Either narrow once for the whole scope or change the type.
- **Reviewer enforcement**: when reviewing a diff that contains `!`, ask whether the suppressor could be replaced with one of the patterns above. Only accept `!` after that question has been answered with a specific reason (typically: "this is the absolute last layer of the API and the contract is enforced by upstream tests"). "It compiles" is not a reason.
