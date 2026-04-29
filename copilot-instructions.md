# Copilot Instructions

> **READ FIRST:** Before responding to any code-change request, re-read the "Mandatory Workflow for Code Changes" section below. Do not skip it.

---

## 1. Mandatory Workflow for Code Changes

Apply to ANY code change (no exceptions for "small" changes). Each step is required, not optional. If you believe a change is too trivial to warrant the cycle, ASK before skipping.

1. **Verify the diagnosis first.** Treat any root-cause claim from a prior agent, plan, report, bug, or user prompt as a **hypothesis**. Read the implicated code and confirm the mechanism behaves as described **before** designing a fix.
   - **Perf work:** identify (or write) a benchmark or test that measurably captures the regression. If that number wouldn't move after the proposed fix, the diagnosis is wrong — stop and re-investigate. No fix without a number that changes.
   - **Bug fixes:** write a failing test that reproduces the bug first. If you can't reproduce it, the bug isn't understood yet.
   - **Cleanup of ad-hoc benchmarks/tests:** any benchmark or test created **solely to validate a diagnosis or fix** must be removed before the change is reported complete, unless the user explicitly asks to keep it. Capture the resulting numbers in the task summary or commit body so the evidence is preserved without leaving throwaway code in the tree.

2. **Rubber-duck the plan** with the **rubber-duck** agent before implementing. Always include in the prompt: *"Is the named root cause actually true? Verify against the source before evaluating the fix."* Address findings or explicitly justify dismissal.

3. **Implement.** Then run the **code-review** agent on the diff with the default model. Iterate until clean.

4. **Multi-model agreement.** Re-run the **code-review** agent on the same diff with at least one model from a different family (default is Claude Opus → also run with `model: "gpt-5.5"` or `gpt-5.3-codex`). Iterate, re-running every model after each fix round, until **all models agree** with no substantive findings. Briefly summarize cross-model agreement before declaring ready.
   - **Do not anchor reviewers on your own framing.** Prompts must instruct the reviewer to treat the description of the fix as a hypothesis and independently read the affected types and call sites. If the diff introduces a predicate over a type's state (see 3.7), the reviewer must open that type's source and enumerate every member before accepting the predicate as complete.

5. **Verify the fix actually fixed it.** The benchmark/test from step 1 must show the expected delta (perf) or pass (functional). If the metric didn't move, the change is a no-op — revert and re-diagnose.

6. **Run affected builds and tests.** All must pass before proceeding.

7. **Show the diff to the user and wait for explicit approval.** Do not commit before approval.
   - **Ask who commits.** When presenting the diff, ask whether the user will handle the commit/push or wants you to. Default to the user committing — many of their workflows involve manual review, splitting, or amending before push.

8. **Commit.** Stage only touched files (`git add <path>` — never `git add .`). Use a single-line message per the *Commit Messages* rules below.

9. **After a PR exists,** run the **pr-review** agent and iterate the same multi-model way (step 4).
   - **Verify each bot finding against the source before applying it.** GitHub Copilot's PR reviewer (and any external reviewer) is sometimes wrong — it lacks full context, can hallucinate symbol behavior, or propose fixes that would obviously break callers. For each comment: read the cited code and the surrounding context, then either (a) apply the fix, (b) push back with a one-line justification on the PR thread and resolve the comment as "won't fix", or (c) ask the user when ambiguous. Do not silently apply changes you cannot independently justify.
   - **Propose an instructions-file delta after each fix.** Once a PR comment is resolved, briefly identify what could be added to `~/.copilot/copilot-instructions.md` to catch the same class of issue earlier (in self-review or by the multi-model code-review pass). If something fits, propose the delta in your summary. Skip silently if the comment is genuinely one-off (typo, taste, etc.).

10. **Pre-existing issues:** if you find one that could be or is causing an issue, ask whether to resolve it now. Otherwise add a TODO comment so it can be picked up later.
    - **This includes findings surfaced by sub-agents** (rubber-duck, code-review, etc.) that are tangentially related but **outside the current task or PR scope**. Do NOT silently expand scope to fix them, and do NOT silently drop them. Briefly summarize each finding (1 line each), state your recommendation, and use `ask_user` to choose: address now in this change, defer to a follow-up (you create a TODO or note), or dismiss with reason.

11. **Unintended reverts:** if you see code that was removed, refactored, or renamed that differs from a previous change you made, ASK before reverting.

12. **Do NOT report the task complete** until steps 1–8 are satisfied (style/trivia excepted).

---

## 2. Commit Messages

- **Single line only.** No body, no footers, no trailers of any kind.
- **Explicitly suppress the auto-injected `Co-authored-by: Copilot` trailer.** When invoking `git commit`, use `-m "<message>"` only — do not pass any additional `-m` flags, do not let any tool append a trailer, and do not add a blank line followed by `Co-authored-by:`. The commit message body must contain the single line and nothing else.
- **Describe what the change does**, not which plan item it implements. No `A2`, `(A2)`, plan section numbers, or Conventional-Commit prefixes (`perf:`, `fix:`, `feat:`, etc.).
- **Imperative mood, no trailing period.**

Examples:
- ✅ `Defer TagsDisplayName join until first read`
- ✅ `Add IsEnabled guard to LoggingMiddleware before serializing actions`
- ❌ `perf: defer TagsDisplayName join (A2)`
- ❌ `A2 - lazy tags`
- ❌ Any message followed by `Co-authored-by:` or any other trailer.

---

## 3. General Coding Standards

These standards apply to **every** code change, in every language. They are non-negotiable; reviewers should reject PRs that violate them.

### 3.1 Comments

- **Default: no comments.** Code is the primary documentation. Names carry intent.
- Add a comment **only** when intent cannot be inferred from code, for example:
  - A non-obvious algorithmic invariant (e.g., "k-merge requires inputs already sorted by `Timestamp` ascending").
  - A workaround for an external constraint (e.g., a Win32 API quirk, a SQLite collation behavior, or a framework middleware ordering requirement).
  - A deliberate trade-off the reader would otherwise question (e.g., "kept Monitor lock here — `ConcurrentDictionary` lost on this benchmark").
- Comments must be **short** and to the point. No tutorial-style narration. No restating what the code says.
- Remove existing comments that no longer add value when touching surrounding code.
- XML doc comments stay where they exist on public/internal API surfaces — don't add new ones unless an API contract genuinely needs one.

### 3.2 Naming — clarity over brevity

- Use **descriptive, full-word names**.
  - ✅ `userSessionCache`, `customerName`, `combinedRecords`
  - ❌ `cache`, `cn`, `cr`, `ctx` (don't abbreviate `context`), `tmp`, `data2`
- **Lambdas:** full names unless the parameter is **immediately and unambiguously** clear from the operation. When in doubt, use the full name.
  - ✅ `orders.Where(order => order.Status == OrderStatus.Open)`
  - ✅ `bytes.Sum(b => b.Length)` — single-letter is fine in a tight, obvious scope
  - ❌ `orders.Where(o => o.Status == OrderStatus.Open && (o.Region == "X" || o.Channel == "Y"))` — scope is big enough to deserve `order`
- **Method names:** verb-phrase that describes the *outcome*, not the implementation.
  - ✅ `MergeSortedRecordsIntoCombinedView`, `TryGetCachedErrorMessage`
  - ❌ `Process`, `DoWork`, `Handle`
- Avoid noise prefixes/suffixes (`Helper`, `Manager`, `Util`) unless the type genuinely is one.

### 3.3 When naming is ambiguous → ask first

If, while implementing, a name is not obviously correct or there are two or more reasonable choices that meaningfully differ in intent, **stop and present 2–4 options to the user via `ask_user`** with a one-line rationale per option. Do not invent a name and proceed.

Cases that warrant the ask:
- A new cache type that could be named after its key, its value, or its consumer (`UserSessionCache` vs `LoginTokenCache` vs `AuthRequestCache`).
- A new helper method whose name could imply a stronger or weaker contract (`TryGetMessage` vs `GetMessageOrNull` vs `LookupMessage`).
- A flag whose polarity matters (`IsLazy` vs `IsEager`, `RebuildAlways` vs `RebuildOnChange`).
- A model property where the prior name disagrees with the new behavior (e.g., renaming `TagsDisplayName` to better reflect that it is now lazy / on-demand — options: `TagsDisplayText`, `TagsJoined`, `FormattedTags`, leave-as-is-with-doc-comment).

When choices clearly differ only in style (and not in intent), pick one and move on — do not over-ask.

### 3.4 Tests and Benchmarks

- Tests and benchmarks follow all the standards above (no abbreviations, descriptive names, no narrative comments).
- **Test method names** are full sentences describing the scenario and expectation: `GetCustomer_WhenCaseDiffers_FindsExistingCustomer`.
- **Benchmark class and method names** match the production symbol they exercise: `UserSessionCacheBenchmarks.Lookup_HotCode_NoAllocation`.
- **Avoid `DateTime.Now` and `DateTime.UtcNow`** — they introduce non-deterministic behavior and timezone dependencies. Use fixed deterministic timestamps such as `new DateTime(2024, 1, 1, 12, 0, 0, DateTimeKind.Utc)` so tests are reproducible regardless of when or where they run.
- **Add or update unit tests** to cover new code and edge cases. Follow existing testing patterns in the codebase.
- **Test project layout — `TestUtils` folder convention.** Every test project in this repo uses a `TestUtils/` folder for shared test infrastructure:
  - Reusable helper classes (factories, fakes, builders, IO/HTTP/compression helpers) live directly under `TestUtils/` as `<Topic>Utils.cs` (e.g., `EventUtils.cs`, `FilterUtils.cs`, `HttpUtils.cs`, `DeploymentUtils.cs`).
  - Shared constants live under `TestUtils/Constants/` as topic-grouped partial-class files named `Constants.<Topic>.cs` (e.g., `Constants.Provider.cs`, `Constants.Resolver.cs`, `Constants.Database.cs`, `Constants.Filter.cs`).
  - Each constants file declares `public sealed partial class Constants` in namespace `<Project>.Tests.TestUtils.Constants` and exposes `public const string` (or other const) members. Tests reference them via `Constants.Foo`.
  - Each test project has its own `TestUtils/` (do not share across projects).
- **Extract duplicated test values into the shared `TestUtils/Constants` location.** When the same non-trivial literal (provider names, task/keyword/message names, descriptions, parameter values, template fragments like `"<template></template>"`, log names, paths) appears in two or more tests — whether in the same file or across files — add it to the appropriate `Constants.<Topic>.cs` partial (creating a new topic file if none fits) and reference via `Constants.Foo`. **Do NOT declare per-test-class `private const` blocks at the top of test files** — keep test files focused on test logic so values are discoverable and reusable by future tests. Trivial values (empty string, single characters, well-known sentinels like `"main"`) and strings that genuinely must differ between tests are exempt.

### 3.5 Performance

- Consider performance implications of every change.
- Avoid unnecessary allocations, prefer efficient algorithms, and use appropriate data structures.

### 3.6 Defaults and Consistency

- **When in doubt, follow Microsoft naming standards and best practices** for the language in question (C#, C++, JavaScript/TypeScript, HTML, CSS). The language-specific sections below codify these.
- **When Microsoft guidance and the existing code in a touched file disagree, prioritize consistency with the existing code in that file.** Don't reformat or rename surrounding code just to match the standard.
- **Comprehensive over sampled.** When the user asks for a review, scan, audit, sweep, or "look across all X" of any noun (sessions, files, PRs, callers, tests), default to **complete coverage** — enumerate the full set first, then process every item. Do not pick a representative subset on your own. If the set is genuinely too large to process in full (cost, time, context budget), surface that explicitly via `ask_user` with the count and propose a sampling strategy *before* starting. "I read 9 of the ~80 sessions" is a failure mode the user will catch every time.
- **Search-first for renames and refactors.** Before declaring any rename, signature change, or moved symbol complete, run a full-repo grep for the old identifier across **every** relevant file type — including `*.razor`, `*.razor.cs`, `*.cshtml`, `*.json`, JSON converter switch cases, `*.xaml`, test projects, doc comments, and trace/log strings. Report "0 matches" before declaring done. "I missed a consumer" is the most common post-refactor regression and almost always means the grep wasn't wide enough.
- **Confirm the user-facing surface before non-trivial implementation.** For any change that introduces or modifies a user-visible surface — new commands, new CLI flags, new menu items, new API endpoints, new file formats, new public types, new dialog flows — sketch that surface (names, signatures, file boundaries, defaults) and confirm via `ask_user` **before** starting implementation, not after. Building the wrong shape and then re-cutting it costs more than asking. Pure internal refactors and bug fixes are exempt.

### 3.7 State predicates and emptiness checks

A "state predicate" is any boolean over a type's fields/properties that means *"this object is empty / equal / fully populated / cleared / serialized / matches X"*. These are notorious for missing fields when new members get added later or when the author only thinks about a subset of the type.

- **Encapsulate state predicates on the type that owns the state.** When you find yourself writing `x.A == 0 && x.B == 0 && !x.C.Any()` from outside the type, add the predicate as a member on the type itself (e.g., `IsEmpty`, `IsDefault`). This forces you to look at *every* field and naturally surfaces ones you'd otherwise miss. A multi-clause boolean over fields of a single type, written from outside that type, should be treated as a refactor smell.
- **Field-completeness justification.** When introducing or modifying any state predicate, enumerate **every** member of the type and justify (in your head, in the PR description, or in a doc comment on the predicate) why each member is included or excluded. "I forgot about it" is the failure mode this rule exists to prevent.
- **Reviewer enforcement.** When sending a diff to the rubber-duck or code-review agent that introduces such a predicate, name the type explicitly in the prompt and require the reviewer to enumerate its members independently. Do not summarize the predicate's scope — let the reviewer derive it from the source.
- **Match / equality predicates need enough fields to be unique in the domain.** A predicate that says *"these two records refer to the same thing"* must include every field required to disambiguate them in the broadest realistic context. Examples that bit us: `(LogName, RecordId)` collides across log sources — needed `OwningLog`; an `IsEmpty` over `Events`/`Messages`/`Parameters` missed `Keywords`/`Opcodes`/`Tasks`. When in doubt, ask: *"could two domain-distinct objects compare equal under this predicate?"* If yes, it is incomplete.

### 3.8 Defer state mutations until after success

When an operation can fail (throws, returns false, awaits a JS call that may not return, etc.), do not record success-implying state until the operation has actually succeeded. This is one of the most common classes of bug flagged by PR review.

- **Membership / dedup sets** (`seen.Add(x)`, `_processed[id] = true`): perform the work first, then record membership. If the work throws, the next attempt should retry, not skip.
- **Registration / initialization flags** (`_registered = true`, `_initialized = true`, `_jsRefAssigned = true`): set only after the underlying call (JS interop, native handle acquisition, network registration) returns successfully.
- **Cache writes**: insert into the cache only on the success path; do not write a partially-populated entry that other callers may read.
- **Error state on success**: on the success path, explicitly clear any prior error fields (`LastErrorCode`, `LastException`, `_warningShown`). A successful run should leave no stale failure breadcrumbs.
- **Idempotency-first ref handoff**: when a method is idempotent (early-returns if already done), assign the long-lived reference (`DotNetObjectReference`, native handle, subscription token) **before** the early-return guard, not after — otherwise the second caller sees `null` and the first caller's reference leaks on dispose.

### 3.9 Async, disposal, and JS interop lifecycle (Blazor / .NET)

These patterns recur in every Blazor + JS-interop PR review. Apply them whenever touching a `.razor.cs`, `IJSRuntime`, `DotNetObjectReference`, `IAsyncDisposable`, or any fire-and-forget async path.

- **`Lazy<Task<T>>` caches fault forever.** If the task throws, the same faulted task is handed to every future caller. Never use `Lazy<Task<T>>` for a cache that must be retryable. Prefer an explicit "produce-then-cache-on-success" pattern that re-runs on failure.
- **`DotNetObjectReference` ownership**: whichever object creates the reference owns disposing it. If you hand it to JS, dispose it in the same scope's tear-down (`DisposeAsync` / `UnregisterAsync`). Do not let it dangle when the component re-renders.
- **Narrow catches around JS interop.** Catch `JSDisconnectedException` and `TaskCanceledException` (and `OperationCanceledException`) specifically — never a bare `catch` or `catch (Exception)`. The first two are expected during teardown / circuit loss; everything else is a real bug and must surface.
- **`AbortController` for JS event listeners.** When wiring `addEventListener` from .NET, pair it with an `AbortController` (or symmetric `removeEventListener`) so listeners detach when the component disposes. Otherwise the page leaks listeners across navigation.
- **Fire-and-forget must be deliberate.** `_ = SomeAsync()` is acceptable only when (a) the call is idempotent or has its own error handling, and (b) you've added `.ConfigureAwait(false)` and a `.catch(...)` / try-catch that logs. Plain `SomeAsync();` without `await` and without a discard is a bug — Copilot reviewer flags it on sight.
- **`invokeMethodAsync` from JS needs `.catch(() => {})`** at minimum (preferably with logging) — otherwise a disconnected circuit produces an unhandled promise rejection in the browser.
- **`DisposeAsync` vs domain-specific tear-down.** If a service has a meaningful "stop using me but stay alive" operation (e.g., `UnregisterAsync`, `CloseAsync`), do not collapse it into `DisposeAsync`. `DisposeAsync` is for terminal cleanup; the domain method is for revocable lifecycle.
- **`[Parameter]` properties are framework-owned — never mutate them.** Compute a derived value or copy into a local field; do not assign to a `[Parameter]` from `OnParametersSetAsync`, `OnInitialized`, or any handler. Blazor will overwrite your value on the next render and the bug surfaces as "value snaps back".

### 3.10 Recurring code smells from past PR reviews

Treat each of these as a hard-stop during self-review and as an explicit thing to look for during the multi-model code-review pass.

- **Constants — single source of truth.** Any literal that constrains a contract (page size, max-in-clause parameter count, default cache size, retention window, file size limit, magic timeout) lives in exactly one named constant. Duplicates across files **will** drift. If the same number appears in two places, extract it before the diff is reviewable.
- **Sibling-constant consistency.** When you add or modify one of a *group* of related constants (default error messages, status labels, retry counts in a tier, timeouts per stage), look at its siblings in the same declaration block and verify formatting/punctuation/casing/units are consistent. Trailing-period-on-one-of-three-strings, `"OK"` vs `"Ok"` vs `"Okay"`, `5000` vs `5_000` — reviewers always spot these because they read sibling constants together. So should you.
- **Test specificity.** Assert exact values, never `Arg.Any<T>()` / `It.IsAny<T>()` / `Mock.Of<T>()` matchers, when the test's purpose is to verify *what was passed*. `Arg.Any<T>()` is appropriate only when the test's contract genuinely doesn't care about the argument (rare). Prefer `Arg.Is<T>(x => x.Property == expected)` or capture-and-assert.
- **Don't materialize streams unnecessarily.** `.ToList()` / `.ToArray()` inside a method that just iterates once is a wasted allocation and a smell that the author is hiding a re-enumeration bug behind it. Materialize only when (a) the result is consumed multiple times, (b) you need indexed access, or (c) you're crossing a boundary that requires a concrete collection. Same goes for eager LINQ in hot paths (`.Where(...).Count()` instead of `.Any()` / `.Count(predicate)`).
- **Lambda parameter shadowing.** Do not name a lambda parameter the same as an in-scope variable (`var filter = ...; filters.Where(filter => filter.X)`). The compiler accepts it; reviewers and humans misread it. Rename the lambda parameter to something distinct.
- **Failure paths must surface user-visible feedback (UI code).** When a `TryCreate`/`TryParse`/parsing operation returns `null`/`false` on the user-action path, do not silently no-op. Show a dialog (`AlertDialogService.ShowAlert`), surface a validation message, or log at warning level — whichever matches the surface. Silent failures are the #1 bug source flagged in UI PRs.
- **Comment / path hygiene.** Never commit a `TODO`, `FIXME`, debug `Console.WriteLine`, or absolute path that references your local machine (`C:\Users\<you>\...`, `Q:\Projects\...`, your Downloads folder). Strip these in self-review before showing the diff.
- **Idempotency / multi-dispatcher guards.** When you add a "have I done this already?" guard to one code path (`if (_done) return;`, `ImmutableDictionary.Add` → `TryAdd`), grep for every other code path that mutates the same state and add the guard there too. Reviewers consistently catch the second/third dispatcher that was missed.

---

## 4. C# / .NET Code Style

### 4.1 Naming Conventions (Microsoft .NET Guidelines)

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

### 4.2 Code Formatting

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

### 4.3 Member Ordering (StyleCop Layout)

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

### 4.4 Expression Preferences

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

### 4.5 Code Block Preferences

- Prefer simple `using` statements (without braces) when possible.
- Prefer top-level statements for `Program.cs`.
- Prefer static local functions when not capturing variables.
- Use the conditional delegate call (`?.Invoke()`).

### 4.6 Field, Parameter, and Modifier Preferences

- Mark fields as `readonly` when possible.
- Treat unused parameters as warnings (do not silently leave them).
- Always specify accessibility modifiers (except for interface members).

### 4.7 Parentheses

- Use parentheses for clarity in arithmetic, binary, and relational operators.
- Omit parentheses only when obviously unnecessary.

### 4.8 Using Directives

- Place `using` directives **outside** the namespace.
- Don't separate import groups.
- Don't prioritize System directives first.

---

## 5. C++ Code Style

### 5.1 Naming Conventions (Microsoft C++ Guidelines)

- **Classes and structs:** PascalCase (`UserRepository`, `CustomerData`).
- **Interfaces:** prefix with `I`, PascalCase (`IRequestHandler`).
- **Functions and methods:** PascalCase (`ProcessRequest`, `GetValue`).
- **Public member variables:** PascalCase (`CustomerId`, `CustomerName`).
- **Private/protected member variables:** `m_` prefix with camelCase (`m_requestCount`, `m_isInitialized`).
- **Static member variables:** `s_` prefix with camelCase (`s_instanceCount`).
- **Global variables:** `g_` prefix with camelCase (`g_configuration`).
- **Constants and macros:** SCREAMING_SNAKE_CASE (`MAX_BUFFER_SIZE`, `DEFAULT_TIMEOUT`).
- **Enums:** PascalCase for type, PascalCase for values (`enum class LogLevel { Info, Warning, Error }`).
- **Namespaces:** PascalCase (`MyApp::Core`).
- **Template parameters:** prefix with `T`, PascalCase (`TResult`, `TAllocator`).
- **Parameters and local variables:** camelCase (`userRecord`, `bufferSize`).
- **Typedefs and using aliases:** PascalCase (`using RequestList = std::vector<Request>`).

### 5.2 Code Formatting

- 4 spaces for indentation (no tabs).
- Opening braces on new lines (Allman style).
- Require braces for `if`, `for`, `while`, `do-while` statements.
- Use `#pragma once` for header guards.
- Sort `#include` directives: standard library first, then third-party, then project headers.
- Use `nullptr` instead of `NULL` or `0`.
- Use `auto` when type is evident from initialization.
- Prefer `enum class` over plain `enum`.
- Use `const` and `constexpr` where applicable.
- Max 1 blank line between declarations.
- Insert a final newline in every file.

### 5.3 Member Ordering

1. Public types (nested classes, enums, typedefs)
2. Public static members
3. Public constructors and destructor
4. Public methods
5. Public member variables (prefer accessors)
6. Protected members (same order as public)
7. Private members (same order as public)

---

## 6. JavaScript / TypeScript Code Style

### 6.1 Naming Conventions

- **Classes:** PascalCase (`UserRepository`, `DataProvider`).
- **Interfaces:** PascalCase, do **NOT** prefix with `I` (`RequestHandler`, `Config`).
- **Type aliases:** PascalCase (`UserList`, `CallbackFn`).
- **Enums:** PascalCase for type and values (`LogLevel.Info`).
- **Functions and methods:** camelCase (`processRequest`, `getValue`).
- **Properties and variables:** camelCase (`userCount`, `isEnabled`).
- **Constants:** SCREAMING_SNAKE_CASE for true constants, camelCase for `const` variables (`MAX_RETRIES` vs `const userName`).
- **Private members:** prefix with `_` (`_internalState`) or use `#` for true private fields.
- **Parameters:** camelCase (`userRecord`, `callbackFn`).
- **Type parameters:** prefix with `T`, PascalCase (`TResult`, `TItem`).
- **File names:** camelCase or kebab-case (`userRepository.ts` or `user-repository.ts`).
- **Abbreviations:** same as C# — two-letter uppercase, three+ letter PascalCase.

### 6.2 Code Formatting

- 4 spaces for indentation (no tabs).
- Opening braces on the same line (K&R style).
- Require braces for `if`, `for`, `while` statements.
- Use single quotes for strings (or template literals).
- Always use semicolons.
- Use `const` by default, `let` when reassignment is needed, never `var`.
- Prefer arrow functions for callbacks.
- Use strict equality (`===` and `!==`).
- Max 1 blank line between declarations.
- Insert a final newline in every file.
- Max line length: 120 characters.

### 6.3 Expression Preferences

- Prefer template literals over string concatenation.
- Prefer destructuring for objects and arrays.
- Prefer the spread operator over `Object.assign` or `Array.concat`.
- Prefer `async/await` over raw Promises.
- Prefer optional chaining (`?.`) and nullish coalescing (`??`).
- Prefer object shorthand properties.
- Prefer arrow functions for inline callbacks.
- Use `Array.map`, `filter`, `reduce` over manual loops when appropriate.

### 6.4 Imports / Exports

- Use ES6 `import`/`export` syntax.
- Group imports: external packages first, then internal modules.
- Prefer named exports over default exports.
- Sort imports alphabetically within groups.

---

## 7. HTML Code Style

### 7.1 Formatting

- 4 spaces for indentation (no tabs).
- Lowercase for element names and attributes.
- Always use double quotes for attribute values.
- Include the `lang` attribute on `<html>`.
- Include a `charset` meta tag.
- Close all elements (use `/>` for self-closing in XHTML, or omit the slash in HTML5).
- Insert a final newline in every file.

### 7.2 Attribute Ordering (Recommended)

1. `class`
2. `id`, `name`
3. `data-*` attributes
4. `src`, `href`, `for`, `type`, `value`
5. `title`, `alt`
6. `role`, `aria-*`
7. Other attributes

### 7.3 Best Practices

- Use semantic elements (`<header>`, `<nav>`, `<main>`, `<article>`, `<section>`, `<footer>`).
- Include appropriate ARIA attributes for accessibility.
- Keep inline styles to a minimum; prefer CSS classes.
- Use meaningful `id` and `class` names (kebab-case: `item-list`, `header-nav`).
- Validate HTML structure.
- Place `<script>` tags at end of `<body>` or use `defer` / `async` attributes.

---

## 8. CSS Code Style

### 8.1 Naming Conventions

- Use kebab-case for class names (`item-list`, `header-navigation`).
- Use BEM methodology when appropriate (`block__element--modifier`).
- Avoid ID selectors for styling; prefer classes.
- Use meaningful, descriptive names.

### 8.2 Formatting

- 4 spaces for indentation (no tabs).
- Opening brace on the same line as the selector.
- One property per line.
- Space after the colon in declarations.
- End all declarations with a semicolon.
- Separate rule sets with a blank line.
- Insert a final newline in every file.

### 8.3 Property Ordering (Recommended)

1. Positioning (`position`, `top`, `right`, `bottom`, `left`, `z-index`)
2. Box model (`display`, `flex`, `grid`, `width`, `height`, `margin`, `padding`, `border`)
3. Typography (`font`, `line-height`, `text-align`, `color`)
4. Visual (`background`, `box-shadow`, `opacity`)
5. Animation (`transition`, `animation`)
6. Misc (`cursor`, `overflow`)
