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

**Signatures** (almost always in tests):
- `var Filter = new Filter(...)` — local PascalCase matches type name.
- Test method names that don't match the project's `Method_Scenario_Expected` (or equivalent) shape.
- Helper class without the project's standard test-utility suffix.

**Discovery query** (diff-scoped, NUL-safe):
- `git diff --name-only -z <merge-base>..HEAD -- 'tests/**/*.cs' | xargs -0 -r rg --line-number --no-heading --color never "^\s+var [A-Z][a-z]"`. PowerShell: `git diff --name-only <merge-base>..HEAD -- 'tests/**/*.cs' | ForEach-Object { rg --line-number --no-heading --color never "^\s+var [A-Z][a-z]" -- $_ }`.

**Canonical fix**: rename local to camelCase OR use a domain-specific lower-cased noun (`result`, `subject`, etc.).

**§2D preflight prompt**: "In tests touched by this diff, scan for local variables named with PascalCase that match a type name."

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

---

## Lower-frequency patterns

These appear 1-4 times in the seed corpus. Treat as "possible to catch on §2D heavy slate, but not part of the preflight `rg` battery — too varied to express as a stable query".

- **internals-visibility** (4): `InternalsVisibleTo` too broad; widens internals to a non-test consumer. Discovery: `rg "InternalsVisibleTo"` per project; inspect each.
- **js-interop-lifecycle** (4): firstRender JS import without `JSDisconnectedException` + `JSException` catch; component closes mid-import. Discovery: `rg "JSRuntime.InvokeAsync<IJSObjectReference>"` — verify both catches present.
- **image-link-broken** (4): docs reference an asset path that doesn't exist. Discovery: `rg "!\[.*\]\("` against `docs/` + `Test-Path` each path.
- **partial-file-cleanup** (3): partial output file left after Create/Diff/etc. failure. Discovery: search for new-context construction paired with `File.Delete` in cancel/error arms.
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
