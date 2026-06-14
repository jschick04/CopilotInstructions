# Copilot PR-review pattern catalog

Empirical catalog of patterns the GitHub Copilot PR reviewer flags across consuming projects. Each entry abstracts a pattern that has recurred across the multi-PR review history (≥5 hits to qualify for the high-frequency battery; 3-4 hits go to the lower-frequency section below). Used by the §2D pre-PR-creation review panel's pattern preflight gate (`pre-pr-creation-review.md` Step 2.5).

This catalog is **project-deidentified**: signatures, discovery queries, and canonical fixes are written abstractly so any consuming project's agent can run them. Concrete instantiation (specific files, helper names, namespaces) belongs in the project's own implementation, not here.

## How to use

1. §2D pre-PR-creation review enters its Step 2.5 (pattern preflight) BEFORE launching reviewers.
2. For each high-frequency pattern below, run the entry's `discovery_query` against the branch diff (scope-mode noted per entry: `diff-scoped` over `<merge-base>..HEAD` OR `tree-scoped` over the project source tree).
3. For each match, classify with the Delta K enum: `applied` / `already-applies` / `not-applicable`. `not-applicable` requires a rationale citing (a) a code property verifiable from the cited file OR (b) a project-defined invariant - pure runtime-behavior assertions are NOT valid rationale (matches Delta K v4 rubric in `review-workflow-gates-sweeps.md` §2B `delta-g-sweeps:` row).
4. Cross-check `known-false-positives.md` - if a finding matches FP-N, dismiss with the registered template; do NOT include it in the panel's reviewable findings.
5. Emit a `PATTERN PREFLIGHT` block in the same response that subsequently launches the Step 3 panel - the block precedes the panel-launch tool calls in that response so the reviewers see the preflight as part of their initial context. See `pre-pr-creation-review.md` Step 2.5 for the strict format.

**Catalog parts:**
- Patterns 12-21: [pr-review-pattern-catalog-patterns-12-21.md](pr-review-pattern-catalog-patterns-12-21.md)
- Lower-frequency patterns + SQL telemetry + maintenance: [pr-review-pattern-catalog-lower-frequency.md](pr-review-pattern-catalog-lower-frequency.md)

## Catalog frequency (illustrative seed; replace with the consuming project's own data after maintenance cycles)

| Pattern slug | Seed-corpus hits | Category (per `pr-creation-mirror-prompt.md`) |
|---|---|---|
| doc-impl-mismatch | 26 | 9 (docs) |
| resource-cleanup | 20 | 11 (resource-cleanup-and-lifecycle) |
| naming-convention | 17 | 11 (hygiene / test-local style) |
| async-correctness | 16 | 4 (async/concurrency) |
| thread-safety | 11 | 4 (async/concurrency) |
| bounds-empty-collection | 6 | 3 (argument/input validation) |
| aria-binding | 5 | 7 (UI / framework binding) |
| regex-validation | 5 | 1 (logic) |
| razor-binding | 5 | 7 (UI / framework binding) |
| null-handling | 5 | 1 (logic) |
| aria-disabled-without-disabled | 4 | 7 (UI / framework binding) |
| stale-comment-after-refactor | 3 | 11 (hygiene) |
| n-squared-selection-scan | 2 | 5 (performance / O(N²) on UI thread) |
| loop-invariant-call-in-linq-lambda | 1 | 5 (performance / O(N²) on UI thread) |
| aria-live-on-describedby-target | 2 | 7 (UI / a11y) |
| hashset-iteration-leaks-nondeterministic-order | 2 | 1 (logic / UX) |
| state-mutation-bypasses-canonical-cleanup-helper | 1 | 11 (lifecycle / consistency) |
| bulk-operation-clears-selection-regardless-of-success | 1 | 1 (logic / UX) |
| missing-fast-path-when-input-empty | 1 | 5 (performance / allocation) |
| jsdisconnectedexception-missing-from-js-interop-catch | 1 | 11 (lifecycle / resilience) |
| test-fake-stores-mutable-reference | 1 | 11 (test-infrastructure hygiene) |
| js-interop-lifecycle | 4 | 11 (lifecycle) |
| internals-visibility | 4 | 11 (hygiene / API surface) |
| image-link-broken | 4 | 9 (docs) |
| partial-file-cleanup | 3 | 11 (resource-cleanup) |

(Seed counts from the 229-comment corpus across the catalog's originating project's PR history. The consuming project SHOULD replace these with its own counts via the maintenance protocol after a few PR cycles. The relative ordering is generally stable across .NET / Blazor / EF Core projects with non-trivial UI surface and async I/O.)

---

## Patterns (high-frequency battery)

### 1. doc-impl-mismatch

XML doc / remarks / inline comment / PR description / README claims X but the code does Y. Most common Copilot category.

**Signatures**:
- XML doc on a public API claims a behavior (e.g., "case-insensitive regex", "thread-safe callback") that the implementation doesn't enforce.
- PR description references a UI feature that the markup doesn't render.
- README image-link path that doesn't exist in the repo.
- Inline comment claims an effect (e.g., "fires on threadpool threads") that the surrounding code contradicts.
- `<see cref>` with partial qualification that won't resolve without an additional `using`.

**Discovery query** (review-pass-only - no executable `rg`):
- Scope mode: **review-pass-only** - every modified `.cs`, `.razor`, `.razor.cs`, `.md`, `.csproj` file's XML docs and inline comments compared against the surrounding code's behavior at HEAD.
- No automation: this is a discipline pattern, not a regex pattern. The §2D panel reviewers are the verification layer. The `PATTERN PREFLIGHT` block records this pattern with `hits: review-required` per `pre-pr-creation-review.md` Step 2.5.2 review-only-pattern handling.

**Canonical fix**: update prose to match implementation. Implementation changes need their own review cycle.

**§2D preflight prompt** (to reviewers): "For every modified source file with XML docs or inline comments: read each comment. Does the prose accurately describe the surrounding code's behavior at HEAD? Are there `<see cref>` references that won't resolve? Does the PR description match the code shipped?"

### 2. resource-cleanup

Missing `Dispose` / `using` / `await using`, undisposed `CancellationTokenSource`, file/DB handle leaks, DB connection pool blocking `File.Delete` on Windows.

**Signatures**:
- `new CancellationTokenSource()` without a corresponding `Dispose` in a finalizer / Dispose path.
- `File.Delete` on a SQLite / DB file without first closing the connection pool (Windows file-sharing semantics).
- `IDisposable` field assigned via `??=` but never disposed.
- `using` swap (`var x = ...; using var y = ...; x.Use()`) where the older instance is leaked.
- A partially-created file (DB, output, temp) left on disk after a fatal exception in the create path.

**Discovery query** (hybrid; tree-scoped baseline + diff-scoped enforcement):
- Tree query (baseline, run once per project to identify all IDisposable construction sites): `rg --line-number --no-heading --color never "new\s+(CancellationTokenSource|SqliteConnection|SqlConnection|FileStream|StreamReader|StreamWriter|HttpClient|ProcessStartInfo)\(" <source-tree>`.
- Diff query (enforcement, run per PR, NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never "new\s+(CancellationTokenSource|SqliteConnection|SqlConnection|FileStream|StreamReader|StreamWriter|HttpClient|ProcessStartInfo)\("`.

**Canonical fix**: `using var` or `await using var` for stack-scoped instances; `IDisposable.Dispose()` chain for fields; extract a project-local "partial-file cleanup" helper for partial-file cleanup paths (the project's `Operation` base class or equivalent).

**§2D preflight prompt**: "For every `new` of an IDisposable in the diff, trace to its disposal. For every `File.Delete` on a managed file, confirm a project-appropriate pool-flush / handle-close precedes it. For every cancellation arm in an operation that creates a new file, confirm cleanup."

### 3. naming-convention

Test files with PascalCase locals that match a type name; private fields without project's standard prefix; method names that don't follow project conventions.

**Signatures** (almost always in tests, but the `Async`-suffix signature applies broadly):
- `var Filter = new Filter(...)` - local PascalCase matches type name.
- Test method names that don't match the project's `Method_Scenario_Expected` (or equivalent) shape.
- Helper class without the project's standard test-utility suffix.
- **`Async` suffix on a synchronous `void` method** - e.g., `private void HandleClickAsync(MouseEventArgs args) { /* no await, no Task return */ }`. Convention reserves `Async` for methods returning `Task` / `ValueTask`; sync methods with the suffix mislead readers and grep / refactoring tools.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- 'tests/**/*.cs' | xargs -0 -r rg --line-number --no-heading --color never "^\s+var [A-Z][a-z]"`. PowerShell: `git diff --name-only <merge-base>..HEAD -- 'tests/**/*.cs' | ForEach-Object { rg --line-number --no-heading --color never "^\s+var [A-Z][a-z]" -- $_ }`.
- `Async`-suffix sweep (any source file): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "(private|protected|public|internal)\s+void\s+\w+Async\s*\("` - every match is a candidate violation (sync `void` returning method with `Async` suffix).

**Canonical fix**: rename local to camelCase OR use a domain-specific lower-cased noun (`result`, `subject`, etc.). For `Async`-suffix on sync method: either drop the suffix (`HandleClick`) or make the method genuinely async (`async Task HandleClickAsync(...)` with at least one `await`) - pick based on whether the method should be async per its callers.

**§2D preflight prompt**: "In tests touched by this diff, scan for local variables named with PascalCase that match a type name. In any source file touched by this diff, scan for methods declared `<modifier> void NameAsync(` - the `Async` suffix is reserved for Task/ValueTask returns."

### 4. async-correctness

Sync I/O in async path; fire-and-forget without an outer/inner `_disposed` re-check (see Delta H); `await using` semantics; `.Result` / `.Wait()` blocking; missing `ConfigureAwait` in library code.

**Signatures**:
- `dbContext.SaveChanges()` inside an `async` method that has access to `SaveChangesAsync()`.
- `_ = InvokeAsync(() => { /* mutates UI state */ })` without the inner `if (_disposed) { return; }` re-check (Delta H).
- `await SomeJsCall()` in a `finally` block of an async method that throws if disposed before the await resumes.
- `Progress<T>.Report(...)` in synchronous code that depends on a UI re-render before the next line.

**Discovery query** (hybrid; tree-scoped baseline + diff-scoped enforcement):
- Tree query (run once per project): `rg --line-number --no-heading --color never "SaveChanges\(\)|_ = InvokeAsync|\.Result\b|\.Wait\(\)" <source-tree>` - combined sync-vs-async + fire-and-forget + sync-over-async sweep.
- Diff query (run per PR, NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never "SaveChanges\(\)|_ = InvokeAsync|\.Result\b|\.Wait\(\)"`.
- Per match: verify async-context `SaveChanges()` uses `SaveChangesAsync`; verify `_ = InvokeAsync` matches the Delta H (i)(ii)(iii) recipe; verify any `.Result`/`.Wait()` is a documented sync-over-async deviation.

**Canonical fix**: `await SaveChangesAsync(ct)`; for fire-and-forget, apply Delta H's three-step recipe; for sync-over-async, refactor caller to be async or document the deadlock-safe deviation.

**§2D preflight prompt**: "For every `async` method in the diff: do all I/O operations use the `*Async` variant? For every fire-and-forget `_ = InvokeAsync(...)`, is the Delta H three-step (outer `_disposed` check, try/catch around the queueing call, inner `_disposed` re-check in the lambda body) present?"

### 5. thread-safety

`Progress<T>` callback context misclassified in docs; `ConcurrentQueue` vs `List<T>` choice; missing `lock` on cross-thread mutation; `volatile` vs `Interlocked` usage; `SynchronizationContext` capture errors.

**Signatures**:
- XML doc on an `IProgress<T>` consumer claims "thread-safe" without qualifying that only `Progress<T>` provides the guarantee.
- A field touched from both UI and threadpool without `lock` / `volatile` / `Interlocked`.
- A class doc that says "callbacks fire on the threadpool" when the captured `SynchronizationContext` actually marshals to a specific thread (e.g., UI thread when constructed in a Razor component).

**Discovery query** (tree-scoped):
- `rg --line-number --no-heading --color never "IProgress<.*>|new Progress<" <source-tree>` - combined sweep of consumer doc-sites + construction sites. For each match, verify the surrounding doc accurately describes the thread the callback fires on given the construction context's `SynchronizationContext`.

**Canonical fix**: clarify doc to say "when constructed in a UI context, callbacks marshal to the UI thread via SC capture; when constructed in a threadpool context, callbacks fire on threadpool." Add `lock` if multi-thread mutation is unavoidable.

**§2D preflight prompt**: "For every `IProgress<T>` field, type, or callback: does the surrounding doc accurately describe which thread the callback fires on given the construction context? For every cross-thread state mutation, is there `lock` / `Interlocked` / `volatile`?"

### 6. bounds-empty-collection

Indexing a collection without an `.Any()` / `.Count > 0` check; `stackalloc` from external input without a clamp; `[0]` after a null-check but no count-check.

**Signatures**:
- `parameter[0]` after `if (parameter is null) return;` without an empty-check.
- `stackalloc char[input.Length]` - no clamp against a constant maximum.
- `Span<T>.CopyTo(dest)` without `if (source.Length <= dest.Length)`.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never "\b\w+\[0\]"` - verify each has a `.Count > 0` / `.Any()` precondition.
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never "stackalloc \w+\[\w+\.Length\]"` - verify each is clamped.

**Canonical fix**: prepend `if (collection.Count == 0) { return; }` or use `collection.FirstOrDefault()`. For `stackalloc` from external input, clamp with `Math.Min(input.Length, MaxStackAlloc)` and handle the overflow path.

**§2D preflight prompt**: "For every `[0]` / `.First()` / `stackalloc T[X.Length]` in the diff, verify the prerequisite (.Count > 0 / clamp)."

### 7. aria-binding

`aria-expanded` / `aria-selected` / `role` attributes bound to a field whose value is inverted vs the actual UI state; missing `preventDefault` on roving-focus arrow keys; `tabindex` mismatched with active state; C# state and JS DOM state drift.

**Signatures**:
- `aria-expanded="@(!_isOpen)"` when `_isOpen` is the true state (inverted polarity).
- Tablist arrow-key navigation handler without `@onkeydown:preventDefault` → page scrolls underneath.
- `aria-selected` driven by a flag mutated by JS without sync via a C# `[JSInvokable]` callback.
- "Is the dropdown open?" - both C# `_isOpen` and JS `data-toggle` track state independently; `Toggle*` paths use one but JS responds to the other.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.razor' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "aria-"` - manual review of each binding's polarity. PowerShell equivalent: `git diff --name-only <merge-base>..HEAD -- '*.razor' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never "aria-" -- $_ }`.
- `git diff --name-only -z <merge-base>..HEAD -- '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "_is[A-Z]\w+\s*=\s*(true|false|!_)"` - cross-check Delta K's `delta-g-sweeps:` from a recent commit.

**Canonical fix**: align polarity at every mutation site; add `@onkeydown:preventDefault` for handled keys (with whitelist if Tab needs to still work - small JS shim is the standard pattern when conditional preventDefault is needed); apply Delta H pattern for fire-and-forget dispatch from JS callbacks.

**§2D preflight prompt**: "For every Razor binding to an aria-* / role / tabindex attribute in the diff: verify polarity. For every JS-driven state-change handler in the diff: verify Delta H (i)(ii)(iii) recipe. For every C#/JS shared state field: are both sides synced through one canonical update path?"

### 8. regex-validation

Regex constructed without `MatchTimeout` (default = infinite, `RegexMatchTimeoutException` never thrown); doc claiming "full match" / "case-insensitive" when `IsMatch` is substring / case sensitivity follows caller's `RegexOptions`; pattern compiled at startup without recompile-on-pathological-input defense.

**Signatures**:
- `new Regex(userInput)` without `TimeSpan.FromSeconds(N)` third argument.
- A `catch (RegexMatchTimeoutException)` arm that's dead because the input regex has `Regex.InfiniteMatchTimeout`.
- "Filters by full match" help text when the impl uses `regex.IsMatch` (substring).
- "Case-insensitive regex" doc claim on a parameter declared as `Regex?` (accepts arbitrary `RegexOptions`).

**Discovery query** (tree-scoped):
- `rg --line-number --no-heading --color never "new Regex\(" <source-tree>` - verify each construction supplies a timeout.
- `rg --line-number --no-heading --color never --glob '*.razor' "filter.*regex|regex.*filter" <source-tree>` - verify help text matches `IsMatch` semantics.

**Canonical fix**: defensive recompile if input regex has `Regex.InfiniteMatchTimeout` - preserves pattern + options + supplies a bounded timeout (project-local helper, typically on the operation base class); reword help text to clarify "matching" semantics (anchor with `^`/`$` for full-string); XML doc says "case sensitivity follows the caller's `RegexOptions`" not unqualified "case-insensitive".

**§2D preflight prompt**: "For every `Regex` field / parameter / construction in the diff: is the `MatchTimeout` bounded? Does surrounding doc accurately describe match semantics (substring vs full vs IgnoreCase)?"

### 9. razor-binding

CSS `:empty` defeated by Razor's whitespace text-node rendering; `StateHasChanged` missing after state mutation that drives a render-bound attribute (especially when the method is callable cross-component); `@onscroll` / `@onkey` handlers wired to no-op methods.

**Signatures**:
- CSS rule like `.outcome:empty { display: none; }` paired with Razor `<span class="outcome">@text</span>` - whitespace between tags makes `:empty` never match.
- Public `Close*` / `Open*` / `Toggle*` methods on a component that mutate `_isOpen` (or equivalent) without calling `StateHasChanged()` - cross-component callers (parent invoking method on child or vice versa) don't get a re-render.
- `@onscroll="OnLogScroll"` wiring an inert handler back into .NET for every scroll event (perf + dead code).

**Discovery query** (hybrid; tree-scoped for CSS, diff-scoped for handlers):
- Tree query: `rg --line-number --no-heading --color never --glob '*.css' ":empty" <source-tree>` - cross-check against the corresponding Razor element each rule targets.
- Diff query (NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.razor' | xargs -0 -r rg --line-number --no-heading --color never "@onscroll|@onkeydown|@onkeyup"` - verify each handler is non-trivial.

**Canonical fix**: replace `:empty` CSS with conditional `@if` block in Razor (no element when empty); factor out a `SetStateAsync(target, jsAction)` helper that mutates + StateHasChanged + JS call; remove dead handlers.

**§2D preflight prompt**: "For every CSS `:empty` rule in the diff: verify the Razor element it targets emits zero text/element children including whitespace. For every public method on a component that mutates a field driving an aria-* / class binding: verify StateHasChanged is called. For every `@on*` event handler: verify the C# method is non-trivial."

### 10. null-handling

User-facing string interpolation with a nullable value silently coerced to empty; missing null-coalesce on display strings; nullable fields exposed without `.HasValue` / `is not null` check at the boundary.

**Signatures**:
- `$"[Failed: {result.FailureSummary}]"` rendering `[Failed: ]` when `FailureSummary` is null - user gets information-free error.
- A status-message string built via interpolation from `record.X ?? record.Y ?? null` - accidentally nullable.
- A `List<string?>` force-cast to `IReadOnlyList<string>` (elements still possibly null).

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never '"\[.*\{[^}]*\}\]"'` - string-interpolation-in-brackets pattern (common for error chips); for each, verify the interpolated value is non-null or null-coalesced.

**Canonical fix**: `result.FailureSummary ?? "(no details)"` - user-friendly fallback. For collection casting, project explicitly: `.Select(s => s ?? string.Empty).ToList()`.

**§2D preflight prompt**: "For every user-facing string interpolation in the diff: is every interpolated value either non-null at the call site or null-coalesced?"

### 11. aria-disabled-without-disabled

A `<button>` carries `aria-disabled="true"` or a Razor binding equivalent, but lacks the real `disabled` HTML attribute. The control therefore APPEARS disabled to assistive tech but remains focusable + clickable, so keyboard users can tab to it and a click handler still runs (or an inline guard early-returns silently). Affects any component with a "blocked while operation in flight" gate.

**Signatures**:
- `<button aria-disabled="@(IsBlocked ? "true" : "false")" @onclick="@(async () => { if (!IsBlocked) await OnX.InvokeAsync(); })">` - guard duplicated in handler; nothing prevents the click from reaching the handler.
- A single bot finding about a "bulk" button typically masks N additional copies on per-row variants of the same action (Upgrade / Retry / Restore / etc.) - sweep ALL action-button sites that share the same `IsBlocked` gate.

**Discovery query** (diff-scoped + tree-scoped sweep):
- Diff: `git diff --name-only -z <merge-base>..HEAD -- '*.razor' | xargs -0 -r rg --line-number --no-heading --color never 'aria-disabled='`. PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.razor' | ForEach-Object { rg --line-number --no-heading --color never 'aria-disabled=' -- $_ }`.
- Tree (verify no sibling instances of the same gate in untouched files): `rg --line-number --no-heading --color never 'aria-disabled=' <razor-source-tree>`.
- For each match: verify a real `disabled="@<boolField>"` attribute is also present. If not → finding.

**Canonical fix**: replace `aria-disabled="@(... ? "true" : "false")"` with `disabled="@<boolField>"`. Keep the handler-side `if (!gate)` early-return as defense-in-depth (bUnit's `ClickAsync` does not always respect `disabled`, so handler-side guards still matter for unit-test stability). Drop `aria-disabled` once `disabled` is set - they're redundant and `disabled` carries the AT semantics implicitly.

**§2D preflight prompt**: "For every `aria-disabled=` binding on a `<button>` in the diff: is there also a real `disabled=` attribute bound to the same gate? If not, raise a finding. When raising one, sweep the rest of the file (and adjacent component files implementing per-row variants of the same action) for sibling instances."

---

> **Catalog continues in part-files:** patterns 12-21 in `pr-review-pattern-catalog-patterns-12-21.md`; lower-frequency patterns, SQL telemetry, and maintenance protocol in `pr-review-pattern-catalog-lower-frequency.md`.