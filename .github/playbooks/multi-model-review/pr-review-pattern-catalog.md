# Copilot PR-review pattern catalog

Empirical catalog of patterns the GitHub Copilot PR reviewer flags across consuming projects. Each entry abstracts a pattern that has recurred across the multi-PR review history (≥5 hits to qualify for the high-frequency battery; 3-4 hits go to the lower-frequency section below). Used by the §2D pre-PR-creation review panel's pattern preflight gate (`pre-pr-creation-review.md` Step 2.5).

This catalog is **project-deidentified**: signatures, discovery queries, and canonical fixes are written abstractly so any consuming project's agent can run them. Concrete instantiation (specific files, helper names, namespaces) belongs in the project's own implementation, not here.

## How to use

1. §2D pre-PR-creation review enters its Step 2.5 (pattern preflight) BEFORE launching reviewers.
2. For each high-frequency pattern below, run the entry's `discovery_query` against the branch diff (scope-mode noted per entry: `diff-scoped` over `<merge-base>..HEAD` OR `tree-scoped` over the project source tree).
3. For each match, classify with the Delta K enum: `applied` / `already-applies` / `not-applicable`. `not-applicable` requires a rationale citing (a) a code property verifiable from the cited file OR (b) a project-defined invariant — pure runtime-behavior assertions are NOT valid rationale (matches Delta K v4 rubric in `review-workflow-gates.md` §2B `delta-g-sweeps:` row).
4. Cross-check `known-false-positives.md` — if a finding matches FP-N, dismiss with the registered template; do NOT include it in the panel's reviewable findings.
5. Emit a `PATTERN PREFLIGHT` block in the same response that subsequently launches the Step 3 panel — the block precedes the panel-launch tool calls in that response so the reviewers see the preflight as part of their initial context. See `pre-pr-creation-review.md` Step 2.5 for the strict format.

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

**Discovery query** (review-pass-only — no executable `rg`):
- Scope mode: **review-pass-only** — every modified `.cs`, `.razor`, `.razor.cs`, `.md`, `.csproj` file's XML docs and inline comments compared against the surrounding code's behavior at HEAD.
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
- `var Filter = new Filter(...)` — local PascalCase matches type name.
- Test method names that don't match the project's `Method_Scenario_Expected` (or equivalent) shape.
- Helper class without the project's standard test-utility suffix.
- **`Async` suffix on a synchronous `void` method** — e.g., `private void HandleClickAsync(MouseEventArgs args) { /* no await, no Task return */ }`. Convention reserves `Async` for methods returning `Task` / `ValueTask`; sync methods with the suffix mislead readers and grep / refactoring tools.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- 'tests/**/*.cs' | xargs -0 -r rg --line-number --no-heading --color never "^\s+var [A-Z][a-z]"`. PowerShell: `git diff --name-only <merge-base>..HEAD -- 'tests/**/*.cs' | ForEach-Object { rg --line-number --no-heading --color never "^\s+var [A-Z][a-z]" -- $_ }`.
- `Async`-suffix sweep (any source file): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "(private|protected|public|internal)\s+void\s+\w+Async\s*\("` — every match is a candidate violation (sync `void` returning method with `Async` suffix).

**Canonical fix**: rename local to camelCase OR use a domain-specific lower-cased noun (`result`, `subject`, etc.). For `Async`-suffix on sync method: either drop the suffix (`HandleClick`) or make the method genuinely async (`async Task HandleClickAsync(...)` with at least one `await`) — pick based on whether the method should be async per its callers.

**§2D preflight prompt**: "In tests touched by this diff, scan for local variables named with PascalCase that match a type name. In any source file touched by this diff, scan for methods declared `<modifier> void NameAsync(` — the `Async` suffix is reserved for Task/ValueTask returns."

### 4. async-correctness

Sync I/O in async path; fire-and-forget without an outer/inner `_disposed` re-check (see Delta H); `await using` semantics; `.Result` / `.Wait()` blocking; missing `ConfigureAwait` in library code.

**Signatures**:
- `dbContext.SaveChanges()` inside an `async` method that has access to `SaveChangesAsync()`.
- `_ = InvokeAsync(() => { /* mutates UI state */ })` without the inner `if (_disposed) { return; }` re-check (Delta H).
- `await SomeJsCall()` in a `finally` block of an async method that throws if disposed before the await resumes.
- `Progress<T>.Report(...)` in synchronous code that depends on a UI re-render before the next line.

**Discovery query** (hybrid; tree-scoped baseline + diff-scoped enforcement):
- Tree query (run once per project): `rg --line-number --no-heading --color never "SaveChanges\(\)|_ = InvokeAsync|\.Result\b|\.Wait\(\)" <source-tree>` — combined sync-vs-async + fire-and-forget + sync-over-async sweep.
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
- `rg --line-number --no-heading --color never "IProgress<.*>|new Progress<" <source-tree>` — combined sweep of consumer doc-sites + construction sites. For each match, verify the surrounding doc accurately describes the thread the callback fires on given the construction context's `SynchronizationContext`.

**Canonical fix**: clarify doc to say "when constructed in a UI context, callbacks marshal to the UI thread via SC capture; when constructed in a threadpool context, callbacks fire on threadpool." Add `lock` if multi-thread mutation is unavoidable.

**§2D preflight prompt**: "For every `IProgress<T>` field, type, or callback: does the surrounding doc accurately describe which thread the callback fires on given the construction context? For every cross-thread state mutation, is there `lock` / `Interlocked` / `volatile`?"

### 6. bounds-empty-collection

Indexing a collection without an `.Any()` / `.Count > 0` check; `stackalloc` from external input without a clamp; `[0]` after a null-check but no count-check.

**Signatures**:
- `parameter[0]` after `if (parameter is null) return;` without an empty-check.
- `stackalloc char[input.Length]` — no clamp against a constant maximum.
- `Span<T>.CopyTo(dest)` without `if (source.Length <= dest.Length)`.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never "\b\w+\[0\]"` — verify each has a `.Count > 0` / `.Any()` precondition.
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never "stackalloc \w+\[\w+\.Length\]"` — verify each is clamped.

**Canonical fix**: prepend `if (collection.Count == 0) { return; }` or use `collection.FirstOrDefault()`. For `stackalloc` from external input, clamp with `Math.Min(input.Length, MaxStackAlloc)` and handle the overflow path.

**§2D preflight prompt**: "For every `[0]` / `.First()` / `stackalloc T[X.Length]` in the diff, verify the prerequisite (.Count > 0 / clamp)."

### 7. aria-binding

`aria-expanded` / `aria-selected` / `role` attributes bound to a field whose value is inverted vs the actual UI state; missing `preventDefault` on roving-focus arrow keys; `tabindex` mismatched with active state; C# state and JS DOM state drift.

**Signatures**:
- `aria-expanded="@(!_isOpen)"` when `_isOpen` is the true state (inverted polarity).
- Tablist arrow-key navigation handler without `@onkeydown:preventDefault` → page scrolls underneath.
- `aria-selected` driven by a flag mutated by JS without sync via a C# `[JSInvokable]` callback.
- "Is the dropdown open?" — both C# `_isOpen` and JS `data-toggle` track state independently; `Toggle*` paths use one but JS responds to the other.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.razor' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "aria-"` — manual review of each binding's polarity. PowerShell equivalent: `git diff --name-only <merge-base>..HEAD -- '*.razor' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never "aria-" -- $_ }`.
- `git diff --name-only -z <merge-base>..HEAD -- '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "_is[A-Z]\w+\s*=\s*(true|false|!_)"` — cross-check Delta K's `delta-g-sweeps:` from a recent commit.

**Canonical fix**: align polarity at every mutation site; add `@onkeydown:preventDefault` for handled keys (with whitelist if Tab needs to still work — small JS shim is the standard pattern when conditional preventDefault is needed); apply Delta H pattern for fire-and-forget dispatch from JS callbacks.

**§2D preflight prompt**: "For every Razor binding to an aria-* / role / tabindex attribute in the diff: verify polarity. For every JS-driven state-change handler in the diff: verify Delta H (i)(ii)(iii) recipe. For every C#/JS shared state field: are both sides synced through one canonical update path?"

### 8. regex-validation

Regex constructed without `MatchTimeout` (default = infinite, `RegexMatchTimeoutException` never thrown); doc claiming "full match" / "case-insensitive" when `IsMatch` is substring / case sensitivity follows caller's `RegexOptions`; pattern compiled at startup without recompile-on-pathological-input defense.

**Signatures**:
- `new Regex(userInput)` without `TimeSpan.FromSeconds(N)` third argument.
- A `catch (RegexMatchTimeoutException)` arm that's dead because the input regex has `Regex.InfiniteMatchTimeout`.
- "Filters by full match" help text when the impl uses `regex.IsMatch` (substring).
- "Case-insensitive regex" doc claim on a parameter declared as `Regex?` (accepts arbitrary `RegexOptions`).

**Discovery query** (tree-scoped):
- `rg --line-number --no-heading --color never "new Regex\(" <source-tree>` — verify each construction supplies a timeout.
- `rg --line-number --no-heading --color never --glob '*.razor' "filter.*regex|regex.*filter" <source-tree>` — verify help text matches `IsMatch` semantics.

**Canonical fix**: defensive recompile if input regex has `Regex.InfiniteMatchTimeout` — preserves pattern + options + supplies a bounded timeout (project-local helper, typically on the operation base class); reword help text to clarify "matching" semantics (anchor with `^`/`$` for full-string); XML doc says "case sensitivity follows the caller's `RegexOptions`" not unqualified "case-insensitive".

**§2D preflight prompt**: "For every `Regex` field / parameter / construction in the diff: is the `MatchTimeout` bounded? Does surrounding doc accurately describe match semantics (substring vs full vs IgnoreCase)?"

### 9. razor-binding

CSS `:empty` defeated by Razor's whitespace text-node rendering; `StateHasChanged` missing after state mutation that drives a render-bound attribute (especially when the method is callable cross-component); `@onscroll` / `@onkey` handlers wired to no-op methods.

**Signatures**:
- CSS rule like `.outcome:empty { display: none; }` paired with Razor `<span class="outcome">@text</span>` — whitespace between tags makes `:empty` never match.
- Public `Close*` / `Open*` / `Toggle*` methods on a component that mutate `_isOpen` (or equivalent) without calling `StateHasChanged()` — cross-component callers (parent invoking method on child or vice versa) don't get a re-render.
- `@onscroll="OnLogScroll"` wiring an inert handler back into .NET for every scroll event (perf + dead code).

**Discovery query** (hybrid; tree-scoped for CSS, diff-scoped for handlers):
- Tree query: `rg --line-number --no-heading --color never --glob '*.css' ":empty" <source-tree>` — cross-check against the corresponding Razor element each rule targets.
- Diff query (NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.razor' | xargs -0 -r rg --line-number --no-heading --color never "@onscroll|@onkeydown|@onkeyup"` — verify each handler is non-trivial.

**Canonical fix**: replace `:empty` CSS with conditional `@if` block in Razor (no element when empty); factor out a `SetStateAsync(target, jsAction)` helper that mutates + StateHasChanged + JS call; remove dead handlers.

**§2D preflight prompt**: "For every CSS `:empty` rule in the diff: verify the Razor element it targets emits zero text/element children including whitespace. For every public method on a component that mutates a field driving an aria-* / class binding: verify StateHasChanged is called. For every `@on*` event handler: verify the C# method is non-trivial."

### 10. null-handling

User-facing string interpolation with a nullable value silently coerced to empty; missing null-coalesce on display strings; nullable fields exposed without `.HasValue` / `is not null` check at the boundary.

**Signatures**:
- `$"[Failed: {result.FailureSummary}]"` rendering `[Failed: ]` when `FailureSummary` is null — user gets information-free error.
- A status-message string built via interpolation from `record.X ?? record.Y ?? null` — accidentally nullable.
- A `List<string?>` force-cast to `IReadOnlyList<string>` (elements still possibly null).

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never '"\[.*\{[^}]*\}\]"'` — string-interpolation-in-brackets pattern (common for error chips); for each, verify the interpolated value is non-null or null-coalesced.

**Canonical fix**: `result.FailureSummary ?? "(no details)"` — user-friendly fallback. For collection casting, project explicitly: `.Select(s => s ?? string.Empty).ToList()`.

**§2D preflight prompt**: "For every user-facing string interpolation in the diff: is every interpolated value either non-null at the call site or null-coalesced?"

### 11. aria-disabled-without-disabled

A `<button>` carries `aria-disabled="true"` or a Razor binding equivalent, but lacks the real `disabled` HTML attribute. The control therefore APPEARS disabled to assistive tech but remains focusable + clickable, so keyboard users can tab to it and a click handler still runs (or an inline guard early-returns silently). Affects any component with a "blocked while operation in flight" gate.

**Signatures**:
- `<button aria-disabled="@(IsBlocked ? "true" : "false")" @onclick="@(async () => { if (!IsBlocked) await OnX.InvokeAsync(); })">` — guard duplicated in handler; nothing prevents the click from reaching the handler.
- A single bot finding about a "bulk" button typically masks N additional copies on per-row variants of the same action (Upgrade / Retry / Restore / etc.) — sweep ALL action-button sites that share the same `IsBlocked` gate.

**Discovery query** (diff-scoped + tree-scoped sweep):
- Diff: `git diff --name-only -z <merge-base>..HEAD -- '*.razor' | xargs -0 -r rg --line-number --no-heading --color never 'aria-disabled='`. PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.razor' | ForEach-Object { rg --line-number --no-heading --color never 'aria-disabled=' -- $_ }`.
- Tree (verify no sibling instances of the same gate in untouched files): `rg --line-number --no-heading --color never 'aria-disabled=' <razor-source-tree>`.
- For each match: verify a real `disabled="@<boolField>"` attribute is also present. If not → finding.

**Canonical fix**: replace `aria-disabled="@(... ? "true" : "false")"` with `disabled="@<boolField>"`. Keep the handler-side `if (!gate)` early-return as defense-in-depth (bUnit's `ClickAsync` does not always respect `disabled`, so handler-side guards still matter for unit-test stability). Drop `aria-disabled` once `disabled` is set — they're redundant and `disabled` carries the AT semantics implicitly.

**§2D preflight prompt**: "For every `aria-disabled=` binding on a `<button>` in the diff: is there also a real `disabled=` attribute bound to the same gate? If not, raise a finding. When raising one, sweep the rest of the file (and adjacent component files implementing per-row variants of the same action) for sibling instances."

### 12. stale-comment-after-refactor

Comments that referenced removed behavior get left behind as orphan blank `//` lines, dangling sentence fragments, or `// Arrange — <reason that no longer applies>` headers. Recurs when a refactor deletes implementation but the explanatory comment(s) above survive. Single occurrence often hides 2-3 more in the same file (same refactor touched several tests).

**Signatures**:
- Blank single-`//` lines with only whitespace after the comment marker: `\s*//\s*$`.
- A test body that opens with `// Arrange — <X coordinates ... >` followed by a blank `//` line, then code that no longer references X.
- An orphan sentence fragment as the only line in an `// Act` / `// Assert` block (e.g., `// before being able to remove the entry.` with no preceding sentence).

**Discovery query** (diff-scoped + tree-scoped, NUL-safe):
- Tree-scoped (catches survivors across whole project, not just diff): `rg --line-number --no-heading --color never '^\s*//\s*$' <source-tree>` — every blank-`//` line is a candidate.
- Diff-scoped (per-PR enforcement): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' | xargs -0 -r rg --line-number --no-heading --color never '^\s*//\s*$'`. PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.cs' | ForEach-Object { rg --line-number --no-heading --color never '^\s*//\s*$' -- $_ }`.

**Canonical fix**: per the `AGENTS.md` §3.1 rename-first protocol, default DELETE for stale comments. Only rewrite when the comment captures a non-obvious invariant that no rename / refactor can carry.

**§2D preflight prompt**: "For every `*.cs` file in the diff: scan for blank-`//` lines (`^\s*//\s*$`) and short orphan `//` sentence fragments. Stale comments left over from removed code are a recurring bot finding."

### 13. test-fake-stores-mutable-reference

A test fake's "recorded calls" list `Add(arg)`s the CALLER'S list reference (typically an `IReadOnlyList<T>`). If the caller mutates the same list later, the recorded call history changes retroactively, producing flaky assertions that depend on test execution order or post-call cleanup.

**Signatures**:
- `RecordedCalls.Add(fileNames)` where `fileNames` is a method parameter of type `IReadOnlyList<T>` / `List<T>` / `IEnumerable<T>`.
- A field declared `IList<IReadOnlyList<string>> Calls { get; } = []` populated by `Calls.Add(arg)` directly.

**Discovery query** (diff-scoped + tree-scoped):
- Tree-scoped (one-time baseline): `rg --line-number --no-heading --color never -g '*Fake*.cs' -g '*Stub*.cs' -g 'Test*.cs' '\.Add\(\s*[a-z][a-zA-Z]*\s*\)' <tests-tree>` — manual review of each: does the `Add` argument come from a method parameter (vs a local-built value)?
- Diff-scoped (per-PR enforcement, NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- 'tests/**/*.cs' | xargs -0 -r rg --line-number --no-heading --color never '\.Add\(\s*[a-z][a-zA-Z]*\s*\)'`.

**Canonical fix**: store a snapshot copy — `RecordedCalls.Add(fileNames.ToList())` or `RecordedCalls.Add([.. fileNames])`. For value types or immutable types (`string`, `ImmutableList<T>`), no copy needed. Document the choice with a one-line type assertion if the type isn't obvious from context (e.g., `RecordedCalls.Add(args.Snapshot)` when `Snapshot` already returns an immutable copy).

**§2D preflight prompt**: "For every test fake `Add(...)` call in the diff where the argument is a method parameter of a mutable reference type (`List<T>`, `IList<T>`, mutable record): is the argument copied via `.ToList()` / `[..]` / `.ToImmutableArray()` before storage?"

### 14. n-squared-selection-scan

A handler iterates a "selected" set and for EACH element scans an "all entries" collection with `FirstOrDefault` / `Single` / nested `Where(...)`. With N selected × M total entries, the cost is O(N×M). On a UI thread (Blazor `@onclick`, MAUI tap handler) this manifests as visible lag when the user has many selections. Often paired with `Recompute*` helpers that re-run on every state change, multiplying the cost.

**Signatures**:
- `foreach (var x in _selectedSet) { var entry = collection.FirstOrDefault(e => string.Equals(e.Key, x, ...)); ... }`.
- A helper `IsEligibleFor(string key) { return collection.FirstOrDefault(...) is { ... }; }` called from a `foreach` over a selection.
- Same scan repeated in BOTH the handler that runs on click AND a `RecomputeCount`-style helper that runs on every state event.

**Discovery query** (diff-scoped + tree-scoped):
- Tree-scoped: `rg --line-number --no-heading --color never -A 5 'foreach\s*\(\s*var\s+\w+\s+in\s+_?selected' <source-tree>` — for each match, check the next 5 lines for `.FirstOrDefault(` / `.Single(` / `.Where(` on a different collection.
- Diff-scoped (NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never -A 5 'foreach\s*\(\s*var\s+\w+\s+in\s+_?selected'`.

**Canonical fix**: snapshot the "all entries" collection into a `Dictionary<TKey, TValue>` (with the correct comparer) ONCE at the top of the handler; use `TryGetValue` for O(1) lookups inside the loop. Extract a small `SnapshotByKey()` helper if the snapshot is needed in multiple sites. For computations that need a "is eligible + reason" answer, return a tuple `(bool IsEligible, ReasonEnum Reason)` from a per-entry helper so callers don't recompute internals.

**§2D preflight prompt**: "For every `foreach` over a selection set / change set / batch in the diff: is the loop body scanning a separate collection with `FirstOrDefault` / `Single` / `Where`? If yes, snapshot the scanned collection to a dictionary outside the loop. Sweep `Recompute*` and `Refresh*` helpers in the same file for the same pattern."

### 15. aria-live-on-describedby-target

A descriptive text span — typically `<span class="visually-hidden" id="@_helpId">conditional content</span>` — is wired up as the target of an `aria-describedby` attribute on a button/input AND ALSO carries `aria-live="polite"` (or `assertive`). The two roles conflict: `aria-describedby` is for on-demand context fetched when the control gains focus; `aria-live` mutates the same span into a live region whose content changes are announced on every mutation. Result: when the underlying state flips (`IsBlocked` toggles, etc.) the screen reader spuriously announces the help text out of context, mid-task. Often paired with a real `role="status"` live region elsewhere in the same component, which the bot reviewer correctly identifies as the proper announcement surface.

**Signatures**:
- `<span aria-live="polite" class="visually-hidden" id="@_blockedHelpId">@(IsBlocked ? "Cannot ..." : string.Empty)</span>` paired with `<button aria-describedby="@(IsBlocked ? _blockedHelpId : null)" ...>`.
- Conditional-content spans (text appears/disappears based on a `boolField`) that ALSO carry `aria-live` — the conditional flip itself becomes an announcement trigger.
- `role="status"` + `aria-live="polite"` + `aria-atomic="true"` on a span/div that's referenced via `aria-describedby` (over-decoration — `role="status"` already implies `aria-live="polite"`).

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.razor' | xargs -0 -r rg --line-number --no-heading --color never 'aria-live=.*visually-hidden|visually-hidden.*aria-live='`. PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.razor' | ForEach-Object { rg --line-number --no-heading --color never -H 'aria-live=' -- $_ }`.
- For each match: if the span has an `id` referenced by an `aria-describedby` elsewhere in the same file → finding. If the span is a standalone announcer (no `id` referenced by `aria-describedby`) → keep the `aria-live` (correct usage).

**Canonical fix**: remove `aria-live` (and `role="status"` / `aria-atomic` if present) from the `aria-describedby`-target span. Keep the `class="visually-hidden"` and the `id`. When the control gains focus, screen readers will read the description via the `aria-describedby` link without re-announcing on every content flip. Pair the project's separate live region (a single `role="status"` + `aria-live="polite"` announcer at the page/component root, fed by an `IAnnouncementService`-style channel) with explicit `Announce(...)` calls for the state transitions worth announcing.

**§2D preflight prompt**: "For every `<span aria-live=...>` with `class=\"visually-hidden\"` in the diff: is the span's `id` referenced by an `aria-describedby` elsewhere in the same file? If yes, raise a finding (aria-live + aria-describedby on the same span is the anti-pattern). If the span is standalone (no `aria-describedby` link), the `aria-live` is correct — leave it."

### 16. state-mutation-bypasses-canonical-cleanup-helper

A method directly assigns a private state field (`_isInModeX = false`, `_currentY = null`, `_isOpen = false`) when a canonical cleanup helper for that state transition already exists (`ExitModeX()`, `ResetY()`, `Close()`). The direct assignment bypasses the helper's cleanup (clearing collateral collections, recomputing dependent counts, firing announcements, releasing handles). When the helper is later extended (a new collateral collection added, a new accessibility announcement added), the direct-assignment site silently misses the new behavior.

**Signatures**:
- `private void ExitSelectionMode() { _isSelectionMode = false; _selectedItems.Clear(); RecomputeCount(); Announce(...); }` paired with a different method that does `_isSelectionMode = false;` directly without calling the helper (typically an auto-exit triggered by an external state change).
- A `Reset*()` / `Clear*()` / `Close*()` helper that touches 3+ fields, called from some paths but bypassed by a direct field assignment in another path that ostensibly does the same transition.

**Discovery query** (diff-scoped, NUL-safe):
- For each `private void Exit*()` / `Reset*()` / `Close*()` / `Clear*()` method in the diff, identify the FIRST field it assigns. Then `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never "<firstField>\s*=\s*(false|null|default|new)"` and flag every assignment that isn't inside the helper itself.
- PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.cs' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never -H "_isXxx\s*=\s*false" -- $_ }` — substitute the canonical state field name.

**Canonical fix**: replace the direct assignment with a call to the canonical helper (`ExitSelectionMode()`, etc.). If the helper does too much for the auto-exit context, extract the shared cleanup into a smaller private method that both paths call. Sweep the rest of the file for the same direct-assignment idiom on the same field — typically the file has 1-3 sites that drifted from the helper over time.

**§2D preflight prompt**: "For every private cleanup/transition helper (`Exit*`, `Reset*`, `Close*`, `Clear*`) in the diff: scan the rest of the same file for direct assignments to its FIRST field. If any are found OUTSIDE the helper, the assignment site is bypassing the helper's cleanup — raise a finding."

### 17. bulk-operation-clears-selection-regardless-of-success

A bulk operation (`BulkRemove`, `BulkUpgrade`, `BulkDelete`, etc.) that iterates a selection set and invokes per-item operations clears the ENTIRE selection set on completion (`foreach (var x in inputItems) { _selectedSet.Remove(x); }`) regardless of which items actually succeeded. When some items fail, the user loses the selection state for the failed items and cannot immediately retry without re-selecting them. Often paired with an auto-exit selection-mode condition that triggers on `succeeded.Count > 0`, ignoring `failed.Count > 0`.

**Signatures**:
- `foreach (var fileName in <inputParameter>) { _selectedForBulk.Remove(fileName); }` placed AFTER a try/catch loop that records both `succeeded` and `failed`.
- `if (succeeded.Count > 0) { ExitSelectionMode(); }` — auto-exit on any success, no check for partial failure.
- `_selected.Clear()` after a batch operation that can partially fail.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never -B 10 '_selected\w*\.(Remove|Clear)'` — for each match, look back 10 lines for a try/catch loop that builds a `failed` list. If found AND the `Remove`/`Clear` doesn't filter by `succeeded`, raise a finding.
- Sibling check: `rg "if \(.*succeeded\.Count > 0.*ExitSelectionMode|if \(succeeded\.Count > 0\) \{ Exit" <source-tree>` — auto-exit-on-any-success without `failed.Count == 0` check is the paired anti-pattern.

**Canonical fix**: iterate `succeeded` (not the input parameter) when clearing selection. Adjust any "auto-exit on success" condition to require `failed.Count == 0` so partial-failure leaves failed items selected for retry. Add a regression test asserting `IsInSelectionMode == true && HasBulkSelection == true` after a partial-failure scenario.

**§2D preflight prompt**: "For every bulk-operation handler in the diff that iterates a selection set + records succeeded/failed: does the post-loop selection cleanup filter by `succeeded` (not the input parameter)? Does the auto-exit-selection-mode condition require `failed.Count == 0`? If either is missing, raise a finding (partial-failure UX regression)."

### 18. missing-fast-path-when-input-empty

A helper method that allocates a collection / dictionary / array snapshot at the top — typically as a setup for a downstream `foreach` — runs that allocation on every invocation, even when the input collection it iterates is empty. Because the helper is often wired to high-frequency event handlers (`StateChanged`, `Tick`, `Resize`, banner/coordinator notifications), the wasted allocation happens many times per second on a UI thread. The empty-case fast-path (set the output field to its zero value + early return) avoids the allocation in the common case.

**Signatures**:
- `private void RecomputeX() { var snapshot = collection.ToDictionary(...); int count = 0; foreach (var item in _selectedSet) { ... } _xCount = count; }` — no `if (_selectedSet.Count == 0) { _xCount = 0; return; }` early-return.
- A `Refresh*()` / `Recompute*()` / `Recalculate*()` helper that builds a `ToList()` / `ToDictionary()` / `ToArray()` snapshot on every call regardless of whether the downstream loop will execute.
- A `_ = InvokeAsyncSafe()` wired to a coordinator/banner event whose handler calls a recompute-with-allocation helper without the empty-input guard.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never -A 2 'private\s+void\s+Recompute\w+|private\s+void\s+Refresh\w+|private\s+void\s+Recalculate\w+'` — for each match, inspect the first 2 lines of the body: if the FIRST statement is a `.ToDictionary` / `.ToList` / `.ToArray` snapshot AND no preceding `Count == 0` early-return, raise a finding.
- PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.cs' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never -H -A 2 'private\s+void\s+(Recompute|Refresh|Recalculate)\w+' -- $_ }`.

**Canonical fix**: prepend `if (_inputSet.Count == 0) { _outputField = 0; return; }` (or the appropriate zero value: `null`, `ImmutableArray<T>.Empty`, `[]`, etc.). Document — typically with a `// Fast path: <reason>` comment ≤12 words — when the empty-case is the common case (e.g., "not in selection mode"). If the helper has multiple inputs, the fast-path should guard the most-common-empty one.

**§2D preflight prompt**: "For every `Recompute*` / `Refresh*` / `Recalculate*` helper in the diff: does the first statement allocate a collection snapshot? If yes, is there a preceding `Count == 0` early-return for the iteration source? If not, raise a finding (avoidable allocation on every high-frequency event-handler invocation)."

### 19. hashset-iteration-leaks-nondeterministic-order

A bulk handler iterates a `HashSet<T>` (or `Dictionary<K,V>.Keys` / `Dictionary<K,V>.Values` / any unordered collection) and the iteration order leaks into a user-visible artifact: a confirmation-prompt bullet list, a focus-restoration target (e.g., `validFiles[0]`), a batch ordering passed to a downstream operation, an announcement message, or a backend call payload. `HashSet<string>` enumeration order depends on string-hash randomization, so the user gets a different ordering on different runs (and the test suite gets occasional CI flakes from order-sensitive assertions).

**Signatures**:
- `var snapshot = _selectedSet.ToArray();` followed by a flow that displays / focuses / serializes the snapshot in the array's order.
- `foreach (var key in _hashSet) { eligible.Add(key); }` where the `eligible` list is later shown to the user or sent to a backend that orders its output by input.
- `_focusRestorationTarget = (validList[0], target);` where `validList` is `HashSet.ToList()` or `HashSet.Where(...).ToArray()` — the [0] is whichever element happens to enumerate first.

**Discovery query** (diff-scoped + tree-scoped):
- Diff (NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never '_(selected|known|active|pending)\w*\.(ToArray|ToList|First|Single)'` — for each match, trace whether the result feeds a user-visible artifact (prompt text, focus target, batch order). If yes, raise a finding.
- PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.cs' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never -H 'foreach\s*\(\s*var\s+\w+\s+in\s+_[a-z]\w*Set' -- $_ }`.
- Tree-scoped sweep: `rg --line-number --no-heading --color never 'HashSet<.*>\s+_\w+|new HashSet<' <source-tree>` — list all HashSet fields, then check whether each is iterated in a user-visible context.

**Canonical fix**: iterate the ordered source collection (e.g., `DatabaseService.Entries`) and filter by `_selectedSet.Contains(...)`. Snapshot the ordered source with `.ToList()` first to guarantee a stable view in case the underlying collection mutates mid-iteration:
```csharp
foreach (var entry in DatabaseService.Entries.ToList())
{
    if (!_selectedSet.Contains(entry.Key)) { continue; }
    // user-visible work in visible-row order
}
```
Or for the snapshot pattern:
```csharp
var snapshot = DatabaseService.Entries
    .Where(e => _selectedSet.Contains(e.Key))
    .Select(e => e.Key)
    .ToArray(); // ordered same as the visible list
```

**§2D preflight prompt**: "For every iteration over a `HashSet<T>` / `Dictionary<K,V>.Keys` / `Dictionary<K,V>.Values` / similar unordered collection in the diff: does the iteration order influence any user-visible output (prompts, focus, batch ordering, announcements, request payloads)? If yes, switch to iterating the ordered source collection filtered by the set's `Contains`."

### 20. jsdisconnectedexception-missing-from-js-interop-catch

A Blazor focus / JS-interop helper catches `ObjectDisposedException` + `JSException` around an `await rowRef.FocusAsync()` / `await JSRuntime.InvokeVoidAsync(...)` / similar call but omits `JSDisconnectedException`. The latter is the canonical exception thrown when the Blazor circuit is torn down mid-call (component dispose during JS invocation, MAUI WebView disposed, etc.). Without the catch, teardown paths surface the exception up to the modal-close pipeline / state-change handler / `IAsyncDisposable.DisposeAsync` and can wedge the operation. Pattern recurs across helpers: focus restorers, JS module imports, JSObjectReference disposals.

**Signatures**:
- `try { await rowRef.FocusAsync(); } catch (ObjectDisposedException) { } catch (JSException) { }` — missing `catch (JSDisconnectedException) { }`.
- `try { await JSRuntime.InvokeVoidAsync(...); } catch (JSException) { }` — same.
- Helper file has 2-3 similar try-blocks; one or two have the full triplet (`OD` + `JSD` + `JSE`) and one has only 2. The drift exposes the inconsistency.

**Discovery query** (diff-scoped + tree-scoped):
- Diff (NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never -B 1 -A 3 'try\s*\{[^}]*await.*Focus|try\s*\{[^}]*await.*JSRuntime\.InvokeVoidAsync'` — for each match, scan the next 3 lines for the catch chain. Verify `JSDisconnectedException` is present.
- PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.cs' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never -H -B 1 -A 3 'await.*\.(FocusAsync|InvokeVoidAsync)' -- $_ }`.
- Tree-scoped pair sweep: `rg --line-number --no-heading --color never 'catch \(JSException\)' <source-tree>` — for each match, verify the immediately-preceding/following catch is `JSDisconnectedException`. If not, raise a finding.

**Canonical fix**: add `catch (JSDisconnectedException) { }` between the `ObjectDisposedException` and `JSException` catches (or wherever sibling catches land):
```csharp
try { await rowRef.FocusAsync(); }
catch (ObjectDisposedException) { }
catch (JSDisconnectedException) { }
catch (JSException) { }
```
When introducing a new focus helper or JS-interop wrapper, copy-paste the full triplet template from a sibling helper rather than authoring a fresh catch chain — drift originates in fresh-authoring.

**§2D preflight prompt**: "For every `await *.FocusAsync(...)` / `await JSRuntime.InvokeVoidAsync(...)` / `await JSRuntime.InvokeAsync<...>(...)` in the diff: does the surrounding try-block catch `JSDisconnectedException` (or document why the omission is intentional)? Other focus helpers in the same file are the reference template — drift from the project pattern is the finding."

---

## Lower-frequency patterns

These appear 1-4 times in the seed corpus. Treat as "possible to catch on §2D heavy slate, but not part of the preflight `rg` battery — too varied to express as a stable query".

- **internals-visibility** (4): `InternalsVisibleTo` too broad; widens internals to a non-test consumer. Discovery: `rg "InternalsVisibleTo"` per project; inspect each.
- **js-interop-lifecycle** (4): firstRender JS import without `JSDisconnectedException` + `JSException` catch; component closes mid-import. Discovery: `rg "JSRuntime.InvokeAsync<IJSObjectReference>"` — verify both catches present.
- **image-link-broken** (4): docs reference an asset path that doesn't exist. Discovery: `rg "!\[.*\]\("` against `docs/` + `Test-Path` each path.
- **partial-file-cleanup** (3): partial output file left after Create/Diff/etc. failure. Discovery: search for new-context construction paired with `File.Delete` in cancel/error arms.
- **com-out-pointer-null-check** (C++ / shell-extension; 7 hits in single PR): every `IFACEMETHODIMP` / `STDMETHODIMP` taking an `[out]` pointer must `RETURN_HR_IF_NULL(E_POINTER, outParam)` + `*outParam = nullptr` (or type-appropriate sentinel) on entry. Discovery: `rg "IFACEMETHODIMP \w+\([^)]*\*\*\s*\w+" *.cpp *.h` — for every match, verify the function body starts with `RETURN_HR_IF_NULL(E_POINTER, ...)` for each `**` parameter. Canonical fix: WIL `RETURN_HR_IF_NULL` (from `wil/result_macros.h`, transitively included via `wil/win32_helpers.h`); fall back to `if (!ptr) return E_POINTER;` if not using WIL. Rule lives in `cpp.instructions.md` *Defensive COM patterns*.
- **cancellation-token-through-task-run** (1 hit): `Task.Run(work)` inside an async method that has a `CancellationToken` in scope, where neither the `Task.Run` call (`Task.Run(work, ct)`) nor the worker body (`ct.ThrowIfCancellationRequested()`) observes the token. Discovery: `rg "Task\.Run\(" *.cs` — for every match in an `async` method or class taking `CancellationToken`, verify both the second-arg pass AND ≥1 `ThrowIfCancellationRequested` inside the delegate (or token-honoring async call like `httpClient.SendAsync(req, ct)`). Canonical fix: pass token to `Task.Run` + observe at each natural checkpoint. Companion pattern: `catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }` to distinguish clean shutdown from unexpected mid-dispatch cancellation. Rule lives in `csharp.instructions.md` *Async, disposal, and JS interop lifecycle*.
- **msbuild-property-function-quoting** (1 hit): `$(Property.TrimEnd('\'))` (single backslash in a property-function arg) is silently MSBuild-incorrect — needs `'\\'` or, preferably, restructure the property so no trim is needed. Discovery: `rg "\.\w+\('[^']*\\[^\\]" *.csproj *.vcxproj *.targets *.props`. Rule lives in `msbuild.instructions.md` *MSBuild property functions*.
- **exec-consoletomsbuild-trailing-newline** (1 hit): `<Exec ConsoleToMSBuild="true">` captures stdout INCLUDING the trailing newline; downstream `Exists(...)` / string compares silently misbehave. Discovery: `rg "ConsoleToMSBuild=\"true\"" *.csproj *.vcxproj *.targets *.props` — every match must be followed by a `<PropertyGroup>` that does `$(CapturedVar.Trim())`. Rule lives in `msbuild.instructions.md` *Exec output capture*.
- **vcxproj-platformtoolset-hardcode** (2 hits in single PR): hardcoded `<PlatformToolset>v143</PlatformToolset>` / `v145` pins the project to one VS install version and breaks on dev machines or CI runners with only the other toolset. Discovery: `rg "<PlatformToolset>v14[0-9]" *.vcxproj`. Canonical fix: `<PlatformToolset>$(DefaultPlatformToolset)</PlatformToolset>` unless a comment immediately above documents the pin rationale. Same logic for `<WindowsTargetPlatformVersion>10.0.NNNNN.0</WindowsTargetPlatformVersion>` → bare `10.0`. Rules live in `cpp.instructions.md` *vcxproj configuration*.
- **locked-down-env-tool-fetch** (1 hit): build scripts that download tools (`nuget.exe`, `dotnet-coverage`, etc.) from public CDNs at build time silently break in locked-down pipeline envs (1ES, ADO managed agents with restricted egress). Discovery: `rg "DownloadFile|Invoke-WebRequest|wget|curl" *.csproj *.targets *.props eng/*.ps1` — every match must be guarded by PATH-discovery / cached-binary check first. Canonical fix: `where <tool>` PATH discovery first, download as last-resort fallback for dev convenience; honor `$(RestoreConfigFile)` to forward internal-mirror NuGet config. Pair with `NuGetToolInstaller@1` task in ADO pipelines. **Sub-trap — `where` output is newline-delimited, not semicolon-delimited:** the canonical mistake is `$(WhereOutput.Split(';')[0])` which is a no-op (no semicolons in `where`'s output) and returns the entire multi-line blob, failing downstream `Exists(...)`. Use `[System.Text.RegularExpressions.Regex]::Match($(WhereOutput), '^[^\r\n]+').Value` to extract just the first line. Rule lives in `msbuild.instructions.md` *Locked-down build environments*.
- **docs-stale-api-name** (1 hit; an instance of doc-impl-mismatch): docs / README / inline comments reference an API name (`SHGetPathFromIDListW`) that the implementation has since renamed (`SHGetPathFromIDListEx`). The high-frequency `doc-impl-mismatch` slug covers prose-vs-behavior mismatches; this is the narrower "API name in docs is stale" variant. Discovery on any external/Win32/framework API rename in the diff: `rg "<OldApiName>" docs/ *.md src/` — every hit needs updating. Rule lives in `AGENTS.md §3.9` *User-facing text — must match the actual behavior*.
- **try-method-ignored-bool-return** (1 hit): `_channel.Writer.TryWrite(args);` at statement position discards the `bool` return — silent drop when the channel is completed (or any `Try*` method's failure case). Discovery: `rg -t cs "^\s*[\w.]+\.(Try[A-Z]\w+)\([^)]*\);\s*$"` for bare `Try*` statements at statement position; manual review of each (some are deliberate — pair with `_ = ` discard + comment). Canonical fix: branch on the return (`if (!x.TryWrite(...)) _logger.Warning(...);`) for user-initiated paths; `_ = x.TryComplete(); // best-effort during dispose` for genuinely-don't-care paths. Rule lives in `csharp.instructions.md` *Return-value contracts — `Try`-prefix and `bool`-returning APIs*.
- **brittle-exact-string-on-token-list** (1 hit): test asserts `Assert.Contains("uap rescap", content)` (or `Assert.Equal`) on a manifest attribute value / class list / role list / header list — fails on harmless reorder/whitespace/extra-token changes that don't change the contract. Discovery: `rg -t cs "Assert\.(Contains|Equal)\(\"[^\"]*\\s[^\"]*\"" tests/` — every match with internal whitespace is a candidate for the parse+per-token pattern. Canonical fix: regex-extract the token list, split on the delimiter, assert presence / absence per token. Rule lives in `csharp-testing.instructions.md` *Test smells — refactor or delete* (brittle-exact-string bullet).
- **css-isolation-cross-component-class** (Blazor-specific; 1 hit in seed): a Razor component uses CSS class names defined in ANOTHER component's `.razor.css` file. Blazor CSS isolation rewrites scoped class selectors (`<class>[b-<scope-id>]`) per component, so styles defined in `ComponentA.razor.css` do NOT apply when the same class name is referenced from `ComponentB.razor`. Symptom: visual misalignment / missing borders / collapsed widths only in the second component, even though devtools shows the class is present. Discovery: when adding a class name to a `.razor` file, verify it's defined in the SAME component's `.razor.css` (not a different component's). Canonical fix: define the styles locally in the consuming component's `.razor.css` — duplication across components is acceptable per CSS-isolation design.
- **modal-cancel-nested-mode-conflict** (Blazor-specific; 1 hit in seed): a `<dialog>` modal has both a native `@oncancel` handler (Esc-closes-dialog) AND a content-level `@onkeydown` handler that treats Esc as "exit nested mode" (selection mode, edit mode, etc.). Both fire on a single Esc press → modal closes AND nested mode exits simultaneously. Discovery: any `<dialog>` modal whose content has `@onkeydown` handling `args.Key == "Escape"`. Canonical fix: route Esc through the modal's close pipeline (e.g., override the modal-base's `OnRequestCloseAsync` to early-return when the active inner surface is in nested mode + call the surface's `ExitNestedModeAsync()`; remove the in-content `@onkeydown` handler). Single source of truth for Esc avoids the double-handling.
- **logic-inversion**, **dropped-input**, **perf-batching**, **dead-code**, **state-machine-race**, **xmldoc-cref**, **hardcoded-path** (each 1-2 hits): catalogued in the §2D 11-category checklist OR Delta-style sweeps (B for dropped-input, C for bounds, D for dead-storage, F for self-similarity, G for cumulative branch sweep, K for §2B-LEDGER-enforced sweep).

---

## SQL telemetry

The `pr_review_findings` table persists in `.github/data/pr-review-findings.csv` (or `.sqlite`) in the consuming project's repo, NOT in CopilotInstructions itself (per-project data has no place in the shared instruction repo). Schema in `pr-review-findings-schema.md` (in this same `multi-model-review/` directory) — defines columns, classification enum, and per-project storage rationale.

The agent updates this file after each PR convergence (maintenance protocol below).

---

## Catalog maintenance protocol

After each PR final state (converged-to-zero OR merged OR closed-with-deferred-findings-tracker):

1. Pull the round's findings (Copilot review comments + agent's classifications) into the project's `pr_review_findings` file. Per-project storage means no `project: <slug>` column is needed — the file's location uniquely identifies the project. Schema columns in `pr-review-findings-schema.md` are the authoritative list.
2. Re-run the regex classifier against the corpus. If a NEW pattern appears with frequency ≥3 across the project's full history, propose adding it to this catalog (CopilotInstructions PR) with abstract phrasing.
3. If a pattern's hit rate is decaying (occurring less frequently round-over-round), the catalog can demote it from the preflight battery to the "lower-frequency" section. Demotions require ≥2 consecutive rounds of zero-hits to confirm decay.
4. Update `known-false-positives.md` if Copilot raised a new FP worth deterring.
5. Commit the catalog updates to `CopilotInstructions/main` per the §1B instruction-repo gate. Project-specific telemetry stays in the consuming project's repo.

**Catalog stickiness recommendation (advisory; not gate-enforced)**: maintainers should avoid more than one catalog revision per 24-hour window to limit downstream PR-preflight churn. This is advisory — no persistent counter/timestamp store exists. Future enhancement: persist `catalog_revision_published_at` + `catalog_revision_pr_count` in a tracked metadata file on `CopilotInstructions/main` for enforceable throttling.

**Phrase-drift policy** (for the FP registry):
The dismissal in `known-false-positives.md` hinges on the underlying TECHNICAL CLAIM (e.g., "namespace lookup requires explicit `using`", "type doesn't implement `IAsyncDisposable`"), not Copilot's exact wording. Phrasing in entries is illustrative. The agent must extract the technical claim and match SEMANTICALLY against catalogued claims. Wording drift across Copilot model updates does NOT invalidate the dismissal.

The catalog is a living document — its value depends on currency and project-agnosticism, not exhaustive completeness.
