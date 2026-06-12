# Copilot PR-review pattern catalog - Patterns 12-21

Continuation of `pr-review-pattern-catalog.md`. Contains patterns 12 through 21 of the high-frequency battery.

---
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

### 21. loop-invariant-call-in-linq-lambda

A LINQ predicate/projection lambda (`.Where(e => ...)`, `.Any(e => ...)`, `.Count(e => ...)`, `.First(e => ...)`, etc.) calls a helper that **builds or fetches a collection** and does **not** depend on the lambda parameter — so the call is loop-invariant, yet it is re-evaluated once per element. With N elements and an inner build of size M (or an inner scan), the cost is O(N×M), often O(N²) when the inner call itself scans the same N. The give-away shape is a **nested call**: `Outer(e, Inner(set))` — the *outer* call legitimately uses the lambda parameter `e`, which camouflages the *inner* `Inner(set)` that is constant across the iteration. This is the LINQ-lambda surface of the same O(N²) family as #14 (`n-squared-selection-scan`, the `foreach`-loop surface); the remedy is the same idea (hoist the invariant work out of the per-element path), but the discovery shape differs, so it gets its own query + prompt.

**Signatures**:
- `entries.Where(e => MatchesFilter(e, SelectedKeys(tab)))` — `SelectedKeys(tab)` allocates a list each element; `tab` is loop-invariant.
- `items.Count(x => Lookup(scope).Contains(x.Id))` — `Lookup(scope)` rebuilds a set per element (the method-chain-on-invariant-call variant; caught by the §2D prompt, not the discovery regex).
- The same invariant call appears in 2+ sibling LINQ properties/expressions in one file (e.g. three filtered-view properties on a component), so a single hoist site is rarely the whole fix — sweep the file.

**Discovery query** (diff-scoped) — a *candidate* gate only; every hit requires the mandatory manual triage below (a regex cannot decide loop-invariance):
- Diff (NUL-safe): `git diff --name-only -z <merge-base>..HEAD -- '*.cs' '*.razor.cs' | xargs -0 -r rg --line-number --no-heading --color never '\.(Where|Select|SelectMany|Any|All|First(OrDefault)?|Last(OrDefault)?|Single(OrDefault)?|Count|TakeWhile|SkipWhile)\(.*?=>[^;]*[A-Z]\w*\([^()]*[A-Z]\w*\('`
- PowerShell: `git diff --name-only <merge-base>..HEAD -- '*.cs' '*.razor.cs' | ForEach-Object { rg --line-number --no-heading --color never -H '\.(Where|Select|SelectMany|Any|All|First(OrDefault)?|Last(OrDefault)?|Single(OrDefault)?|Count|TakeWhile|SkipWhile)\(.*?=>[^;]*[A-Z]\w*\([^()]*[A-Z]\w*\(' -- $_ }`
- The query targets the `Outer(... Inner(...))` nested-call shape (a method call appearing as an argument to another method call inside the lambda); on an idiomatic C# tree this is a small candidate set, NOT a per-element fire. **Manual triage per hit (mandatory — the finding is the INNER call, not the outer):** list *every* method invocation in the lambda, including ones nested as arguments to other calls. For each, open the invoked method and judge by code properties, never by guessed cost: (i) does the call's **full invocation expression — receiver/qualifier plus argument list** — reference the lambda parameter? If yes, that call is loop-variant — not this finding (`e.Inner(tab)`, `e.Tags.ToList()`, and `Get(e.Id)` are all variant, via receiver or args). (ii) If it does NOT reference the lambda parameter anywhere (receiver or args) AND its body allocates/returns a collection (or otherwise does non-trivial work), it is the loop-invariant culprit → finding. An enclosing or sibling call that uses the lambda parameter does NOT exempt a nested invariant call (`Outer(e, Inner(tab))`: `Outer` uses `e`, but `Inner(tab)` is recomputed N times).
- **Known regex gaps (rely on the prose §2D prompt as backstop):** multi-line lambdas (rg `.` does not cross newlines); the bare method-chain shape `Build(set).Contains(e.X)` where the invariant call is not nested as an argument; lambdas whose invariant call is the *only* call (no outer wrapper). These are caught by the prompt's read-the-lambda instruction, not by this regex.

**Canonical fix**: hoist the loop-invariant call to a local immediately before the LINQ expression and close over the local in the lambda:
```csharp
var selected = SelectedKeys(tab);              // computed once
var view = entries.Where(e => MatchesFilter(e, selected));
```
For a property whose body is a single `return entries.Where(...)`, switch to a block body to introduce the local. Sweep sibling properties/expressions in the same file for the same invariant call and hoist each (the recompute usually appears at every filtered-view site, not just the flagged one). Severity is highest when the LINQ runs on a UI thread / hot path and M is non-trivial; off the hot path the hoist is still correct but the win is small — prioritize by the inner call's allocation, but do NOT *dismiss* a true invariant-recompute on a cost guess (dismissal must cite a code property per the triage step).

**§2D preflight prompt**: "For every LINQ lambda in the diff (`.Where`/`.Select`/`.SelectMany`/`.Any`/`.All`/`.Count`/`.First*`/`.Single*`/`.Last*`/`TakeWhile`/`SkipWhile`), read the WHOLE lambda body and list every method call in it, including calls nested as arguments to other calls. For each call, does its **full invocation expression — receiver/qualifier plus arguments** — reference the lambda parameter? A call that does NOT (e.g. `Inner(tab)` in `Outer(e, Inner(tab))`) and that builds/returns a collection is loop-invariant and is being recomputed once per element — hoist it to a local before the LINQ expression. A call that references the parameter via its receiver OR its args (`e.Inner(tab)`, `e.Tags.ToList()`, `Get(e.Id)`) is loop-variant — leave it. Judge invariance from the invocation expression and the invoked method's body (a code property), never from a guess about element counts. A sibling/enclosing call that uses the parameter does NOT make a nested invariant call variant."

---

