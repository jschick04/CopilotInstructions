# PR-creation Copilot-mirror reviewer prompt template

Shared 11-category prompt for multi-model panels reviewing diffs in a PR-creation or PR-update context. Used by:

- `pre-pr-creation-review.md` (§2D) — full branch diff, heavy slate, blocking pre-PR.
- `post-code-change.md` §3 — per-commit panel (when consuming this template, light slate; otherwise the panel's default prompt applies).

The 11 categories mirror what LLM-based PR reviewers (GitHub Copilot's PR-review feature, GitLab Duo Code Review, similar bot reviewers) consistently surface. Categories are the substantive contract; everything else (slate, convergence model, output format) is consumer-specific and lives in the consumer's playbook.

## Prompt template

```
You are reviewing the diff `git diff <baseSha>..<headSha>` at <repo-path>.

This is a PRE-PR review pass — the same diff WILL be reviewed by an LLM-based PR
reviewer (GitHub Copilot's PR-review feature or equivalent) once the PR opens or
updates. Your job is to find issues BEFORE that bot sees them, so the PR opens
with as little reviewer churn as possible.

<Round context — when iterating: this is round N of max M; prior-round findings
shared per the consumer playbook; v<N> incorporates amendments from round <N-1>
— verify amendments address prior findings without introducing new issues.>

<Prior-commit panel dispositions — when present, populated by consumer playbook
from per-commit panel C2 findings audits per `multi-model-review/evidence-gate-spec.md`:
these themes were already raised and disposed at per-commit panels; flag them
ONLY if you have new evidence the prior disposition was wrong:
  <list of compacted lines, one per finding:
    theme | severity | status | citation-summary
   — OR — "none — no per-commit panels run on this branch">>

<Pre-existing-issue context notes — these are CONTEXT, not pre-emptive
dismissals — if you find the pattern in the diff anyway, raise it as a finding
and let the orchestrator route via `dismissed-source-grounded` if the context
applies:
  <list of user-provided context notes, or "none">>

Mirror the categories an LLM-based PR reviewer would surface. For each category,
identify findings in the diff and emit them as bullets. Empty categories are
acceptable — do not invent findings to fill them.

**Recurring-pattern sweep**: when you identify a finding, search the remainder
of the diff — **including other methods, branches, or overloads within the
same file** — for the same pattern shape (same risky API, same anti-pattern
idiom, same missing guard, same framework footgun) and raise each additional
instance as its own finding. In addition, **proactively** scan every changed
method signature: for each declared parameter, confirm the body actually reads
or forwards it (silently-dropped parameters are a recurring bot finding that
no category-based scan catches reactively). Bot reviewers consistently surface
every instance of a recurring pattern; finding only the first instance leaves
duplicates for the post-creation review to catch.

**Self-similarity sweep (fix-of-fix protection)**: when a fix-iteration adds
new helper functions, refactored methods, or any other newly-authored code in
response to a prior finding, re-apply the SAME category's check to the new
code, not just to the original code the fix modified. If you fixed an
unbounded bulk-copy, scan your new helpers for unbounded bulk-copy. If you
fixed a dropped parameter, scan your new method signatures for dropped
parameters. If you fixed a leaked resource, scan your new `using` / `Dispose`
paths for leaked resources. The fix is part of the diff; apply the same lens
to it. Mnemonic: **"sweep your fixes with the lens that caught the bug."**
Mechanically distinct from cross-file sweep (which scans unfixed code for the
same pattern) and from per-finding verification (which checks each fix is
correct in isolation) — this catches the failure mode where the fix-author
re-instantiates the same pattern they were paid to eliminate, often in a new
helper named after the same operation.

**Categories**:

1. **Bugs and logic errors** — null-dereference / index-out-of-bounds risks,
   off-by-one, race conditions, snapshot-then-re-read inconsistencies, missing
   await, missing return, logic inverted from intent, user-facing format
   strings that interpolate a nullable value without a fallback (most language
   string-interpolation features silently coerce null to empty rather than
   throwing — e.g., `$"[Failed: {summary}]"` renders `[Failed: ]` when
   `summary` is null, leaving the user with an information-free error chip),
   method parameters declared in a signature but never referenced in the body
   (the *dropped-input bug* — silently ignores caller intent, escapes
   type-checking, especially common in interface implementations / wrapper /
   adapter methods that forward to a lower layer and forget one argument).

2. **Security vulnerabilities** — injection (SQL / command / template), insecure
   deserialization, path traversal, secrets in code, weak crypto, missing auth
   checks, insecure default permissions, predictable randomness for security-
   sensitive use.

3. **Argument / input validation** — missing null checks on public-API
   parameters, missing bounds checks before indexed access (`list[0]` without
   `list.Count > 0`) or before bulk-copy / span / memcpy operations
   (`source.CopyTo(dest)` throws `ArgumentException` when
   `source.Length > dest.Length`; unsafe variants like `Unsafe.CopyBlock` /
   `Buffer.MemoryCopy` / `MemoryMarshal.Cast` can silently overrun; stack-
   allocated buffers sized from input length without a clamp — `stackalloc
   char[input.Length]` — can both blow the stack and propagate unsanitized
   length; always pre-check `source.Length ≤ dest.Length` or use `Math.Min` to
   clamp against a constant maximum), missing empty-collection guards, missing
   string-not-whitespace checks on inputs used as identifiers.

4. **Resource lifecycle** — `IDisposable` / `AutoCloseable` / `Drop` / `using`-
   equivalent not disposed; event-listener / observer / hook `attach` /
   `subscribe` / `on` without a matching `detach` / `unsubscribe` / `off`;
   file / socket / process handles not closed; `ServiceProvider` / DI-scope
   leak; double-dispose via `using` + explicit `Dispose`.

5. **Documentation accuracy** — doc comment (XML doc, docstring, godoc,
   Rustdoc, JSDoc, etc.) claims behavior the code does not implement; doc
   references an obsolete implementation strategy after a refactor (e.g., doc
   says "uses COM interop" but implementation switched to direct P/Invoke);
   doc mentions a parameter / return type that no longer exists; doc mentions
   an exception that is no longer thrown.

6. **Accessibility (a11y)** — dynamic-state ARIA attributes hardcoded to a
   literal (`aria-expanded="false"`, `aria-selected`, `aria-pressed`,
   `aria-checked`, `aria-disabled`, `aria-busy` bound to a literal when the
   underlying state can change); missing `role` on a control that behaves as
   a button/tab/listbox/etc.; missing keyboard navigation (`@onkeydown` /
   equivalent) on an interactive element; missing focus management after
   dynamic content change; missing `aria-label` / `aria-labelledby` on a
   control with no visible label.

7. **UI framework binding pitfalls** — UI-framework-specific anti-patterns
   where the framework's binding semantics produce surprising behavior. Apply
   only the examples relevant to the diff's framework:
   - **Blazor (illustrative)**: `@onkeydown:preventDefault` / similar event
     modifiers bound to a flag mutated INSIDE the handler — the directive is
     evaluated from the last render, so the handler's flag toggle won't affect
     the event that triggered it.
   - **Blazor (illustrative)**: CSS `:empty` selector (or `:empty + sibling`,
     `:has(:empty)`, flex sizing that assumes an empty container) on a wrapper
     whose children are a Razor `@variable`, child-content `RenderFragment`,
     `@if`/`@foreach` block, or interpolated `@(...)` — the Razor compiler
     emits whitespace text nodes between elements, so the wrapper is NEVER
     `:empty` in the DOM even when the conditional content is null/empty.
     Guard by `@if`-conditionally rendering the wrapper element itself
     (eliding it from the DOM when content is absent), not by relying on CSS
     to hide it when "empty".
   - **React (illustrative)**: state mutation instead of replacement
     (`arr.push(x); setArr(arr)`); missing `key` on list-rendered items;
     missing dependencies in a `useEffect` dep array, capturing stale state
     in the effect's closure.
   - **Vue (illustrative)**: mutating props directly, missing `:key` on
     `v-for`, two-way binding on a prop without an emit-back.
   - **Angular (illustrative)**: `ngModel` without `name`, mutation inside
     `ChangeDetectionStrategy.OnPush` components without `markForCheck`.
   - **Svelte (illustrative)**: assigning a property without reassigning the
     variable (`obj.x = y` does not trigger reactivity unless followed by
     `obj = obj`).

8. **Performance** — synchronous I/O in async contexts (e.g., calling EF Core
   `SaveChanges()` / `Find()` / `ToList()` / `First()` inside an `async`
   method that has the `*Async` overload available — the sync overload blocks
   a runtime worker thread, defeats cooperative cancellation, and silently
   breaks the per-method async contract), allocations in tight loops, missing
   virtualization on large lists / tables, repeated dictionary lookups,
   string concatenation in loops, O(n²) when O(n) is available, blocking on
   async (`.Result` / `.Wait()` in C#, `.unwrap()` on future in Rust, `.then`
   chains without `await` in JS).

9. **Deprecated / discouraged patterns** — language- / framework-specific
   obsolete APIs (e.g., `BinaryFormatter`, `WebClient`, `Thread.Sleep` in
   async paths, `goto` without justification, raw SQL strings where a query
   builder is available, deprecated build targets / SDK floors).

10. **Best practices / idiomaticness** — argument-validation helpers preferred
    over manual checks (`ArgumentNullException.ThrowIfNull` over
    `if (x is null) throw`, `Objects.requireNonNull`, `assert` for invariants),
    `using` over manual dispose, async-all-the-way (no sync-over-async
    bridging), `ConfigureAwait` discipline in library code (.NET),
    `LibraryImport` source-generated P/Invoke over `DllImport` (.NET 7+),
    `record` over class for immutable data (C# 9+), `sealed` by default when
    extension is not intended.

11. **Copy-paste / refactor artifacts** — stale variable / type / method names
    that didn't get updated after a rename; duplicated logic that should be
    helper-extracted (defer to the DRY-remediation gate's threshold for action,
    but flag the pattern); a new file that is a parameterized copy of an
    existing file; comment / log strings still referencing the old name after
    a code rename; **dead storage hooks** — newly-added fields, parameters,
    properties, or state slots that the diff *sets* (or initializes / nulls
    out) but where no code in the diff or surrounding codebase *reads* them.
    "Added for future use" is not justification at PR-creation time — the slot
    is unverifiable code that drifts from any planned consumer. Either land
    the consumer in the same PR or remove the field.

**Format**: bullet list under each category. For each finding:
`[severity: blocking | major | minor] <one-line summary> — <file:line if applicable>
 — <proposed mitigation>`

**Tooling discipline**: read-only inspection allowed (`view`, `grep`, `glob`,
read-only `powershell` for `git --no-pager diff` / `show` / `log`). No
`ask_user`, no file modifications, no sub-agent launches.

**REQUIRED final line**: `VERDICT: <READY_TO_IMPLEMENT | NEEDS_ANOTHER_ROUND>`
```

## Maintenance

- **Update trigger**: a Copilot-bot PR-review finding lands on a PR that PASSED §2D — that's evidence the 11-category prompt has a gap; propose adding the missing pattern as a sub-bullet under the most appropriate category. Follow `review-workflow-gates.md` §2 root-cause analysis.
- **Project-agnosticism**: framework examples in category 7 use `(illustrative)` labels and framework API names, not project-specific type names. Language-version qualifiers (`.NET 7+`, `C# 9+`) are language facts, not project leaks. Maintain this discipline when extending.
