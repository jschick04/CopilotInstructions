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

**Reviewer scope discipline** (REQUIRED — this constraint trumps thoroughness):
when invoked, you focus EXCLUSIVELY on the findings, fixes, or diff scope the
consumer prompt names. You do NOT:

- Propose new instruction-file / prompt-template deltas unless a genuinely NEW
  pattern (not in the current 11-category list + sweep instructions) emerges
  from THIS round's findings. Convergence rounds late in a feedback loop
  almost never warrant new deltas — the prompt already covers what's relevant.
- Meta-comment on the §2D feedback loop, the gate's convergence trajectory,
  the prompt's evolution, or other reviewers' prior verdicts.
- Flag pre-existing concerns in code adjacent to the diff. The diff is the
  scope; "pre-existing" findings are out of scope per the consumer playbook's
  Intake Q4 framing. (Caveat per Delta J below: a file matching a
  pre-existing pattern is NOT automatically pre-existing — verify the file's
  provenance against the merge-base before invoking this exemption.)
- Re-raise findings the consumer prompt explicitly states were already
  addressed in this turn.
- Propose follow-up refactors, future-hardening passes, or "consider in a
  separate PR" suggestions unless they're load-bearing for the current
  finding's correctness.

Stay within the consumer prompt's stated scope. If the consumer prompt says
"verify the X fix is correct + complete + introduces no new findings", that's
your entire job. Producing more output isn't more value — it's noise that the
orchestrator must filter, and noise eventually gets confused for signal.

If you genuinely cannot find any issues within scope, your output should be
short. A clean verdict is a clean verdict; padding it with adjacent observations
inverts the signal-to-noise.

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

**Cumulative branch remediation sweep**: build a list of every *remediation
pattern* applied anywhere in the branch diff against the base ref — not only
patterns introduced in the current commit. Examples: SQLite-pool-clear before
file delete, bounds-clamped bulk-copy, null-coalesced display strings,
dropped-input guards, dead-storage cleanup, async-all-the-way `*Async`
conversion. For each remediation pattern P enumerated, scan every site in the
branch's modified files (across ALL prior commits on the branch) where P's
triggering precondition holds. Each enumerated site must either:
(a) already apply P,
(b) carry a documented one-line reason P does not apply (e.g., "read-only
operation, no partial-file risk"; "modifies pre-existing user file, deletion
would be data-destructive"), or
(c) be flagged as a missing-sister-site finding.
This complements the cross-file sweep (which is anchored on the CURRENT fix's
category) and the self-similarity sweep (which is anchored on the FIX'S new
code) — the cumulative-branch sweep fills the gap where remediation patterns
from earlier commits on the branch were never re-engaged in later panel runs.
Optimization: if the prior panel round flagged a missing-sister-site for any
pattern, ALWAYS run the cumulative sweep in this round; if the prior round
had no missing-sister-site findings, the cumulative sweep is a one-time
re-check that may be skipped on subsequent same-branch panels where no new
patterns were introduced.

**Dispatch-shape discrimination when applying disposal-guard patterns**: when
the remediation pattern is a `_disposed`-flag guard for callbacks that
dispatch UI work via a renderer's dispatcher (Blazor `InvokeAsync`, WPF
`Dispatcher.Invoke`, WinForms `Control.Invoke`, equivalent on other UI
frameworks), distinguish two dispatch shapes — each needs a different guard
recipe:

- **Await-inline dispatch** (`await InvokeAsync(StateHasChanged)` called from
  an `async` context): the outer `if (_disposed) { return; }` check before
  the await + a try/catch around the await is sufficient. The dispatcher
  runs the lambda synchronously-from-the-await's-perspective; there's no
  detached lambda that can outlive disposal.

- **Fire-and-forget dispatch** (`_ = InvokeAsync(() => StateHasChanged())`
  from a sync callback context — typical for `[JSInvokable]` methods,
  `IProgress<T>` sinks, or any threadpool callback): the outer check +
  try/catch around the queueing call is NOT sufficient. The lambda is
  queued, and `Dispose()` can run on the dispatcher BETWEEN the successful
  return from `InvokeAsync` and the lambda body actually executing. The
  fire-and-forget shape needs ALL of: (i) outer `if (_disposed) { return; }`
  check, (ii) try/catch around the queueing call, AND (iii) inner
  `if (_disposed) { return; }` check at the top of the lambda body. Without
  (iii), `StateHasChanged()` on a disposed renderer throws an unobserved
  exception into the fire-and-forget task. The canonical Blazor reference
  patterns (e.g., a `SettingsModal`-style component) often show only the
  await-inline shape; do NOT copy that shape into a fire-and-forget site
  without adding (iii).

**Adversarial dispatch-ordering enumeration when reviewing async / queued /
concurrent fixes**: when verifying a fix that involves async, queued, or
otherwise concurrent operations (state-management dispatchers with queued
reducers, message-queue handlers, multi-thread state updates, callback
chains, awaited-then-mutated state, framework event-then-completion
sequences, etc.), ADVERSARIALLY enumerate dispatch / arrival / commit
orderings. If your verification argument hinges on the phrase "X may not
have happened yet" / "Y is not yet committed" / "Z is in-flight but not
landed", you MUST ALSO verify the case where X HAS already happened / Y HAS
already committed / Z HAS already landed. Both orderings are typically
reachable in real concurrent code; defaulting to the "has not yet"
assumption hides real bugs that surface only when the reviewer-overlooked
ordering arises in production.

Escape hatch: a single-ordering analysis is sufficient ONLY when the
impossibility of the other ordering is grounded in (a) framework source /
documentation that the orderings are serialized at the framework level
(cite the file + line / doc URL / version), (b) a project-defined
synchronization invariant (cite the source where it's enforced — `lock`
scope, single-threaded dispatcher contract, etc.), OR (c) a strict
happens-before relationship the language model guarantees (e.g., `await`
sequencing within a single async method body in C#, sequenced-before in
C++). Mere assertion that "this shouldn't happen" or "the other case is
unlikely" without one of those three groundings does NOT clear the bar.

Mnemonic: **"enumerate both orderings, or cite why one is unreachable."**

Mechanically distinct from cross-file sweep (which scans for the same
pattern shape in unfixed code) and from self-similarity sweep (which
checks fix-introduced code for the original pattern) — this catches the
failure mode where the reviewer's verification argument only considers
ONE possible interleaving and silently treats it as definitive. Common
symptom: a panel finding is "verified clean" in iter N, then the bot
reviewer flags the OTHER ordering as a real bug in the post-PR review.

**Verify "pre-existing" claims before exempting from sweeps (Delta J)**:
before dismissing a sister-site finding as "pre-existing pattern, not introduced
by this PR" (and therefore exempt from the cumulative-branch remediation sweep
above), VERIFY the file is in fact present on the merge-base. Pattern
recognition is not provenance: a file authored on the branch can match a
pre-existing pattern shape without itself being pre-existing.

Verification mechanism (any one):
- `git ls-tree <merge-base> -- <path>` — empty output means the file is
  branch-new (NOT pre-existing); fall back to the cumulative sweep above.
- `git log <merge-base>..HEAD -- <path> --reverse --pretty=format:%H` — if
  the file's first commit is on this branch, the file is branch-new.
- `<merge-base>` here is `git merge-base origin/main HEAD` or the equivalent
  base ref the consumer playbook names.

When to apply: any time a finding is about to be dismissed with rationale
containing "pre-existing", "already in main", "not introduced by this PR",
"out of scope", or equivalent waiver-by-provenance language. Skip verification
ONLY when:
- The file's path is in the diff's deletion set (no sister-site can exist), OR
- You have already verified the file's provenance via merge-base lookup within
  the current review round.

Failure mode if skipped: the sister site stays unfixed → the downstream
review bot (Copilot, CodeRabbit, internal reviewer) re-flags it on the next
round → fix-iteration count inflates → the gate escalates to manual
adjudication. This is the same mechanism that allows surface pattern-matching
to "agree with itself" while quietly missing real branch-introduced
regressions.

**Enforce Delta G's sweep via §2B's POST-CODE-CHANGE LEDGER (Delta K)**:
when a commit applies a remediation pattern P that has at least one branch-existing
or branch-new sister site (per Delta G + Delta J), the commit's POST-CODE-CHANGE
LEDGER's `delta-g-sweeps:` row (defined in `review-workflow-gates.md` §2B's LEDGER
format) MUST be `ran, N patterns swept, M sites enumerated` with a structurally-valid
entry per pattern. Absence or structural invalidity of the row blocks `git add` per
§2B's existing `git add` block — no new tool-gate is introduced.

`sites:` membership: the site(s) where the current commit APPLIES P MUST be listed
under `sites:` with `status: applied`, alongside any branch-existing or branch-new
sister sites discovered by `discovery_query`. The originating-site entry is the
minimum evidence the falsifiability check #2 (evidence-range re-open) can verify on
every commit. A row with `sites: []` is only valid when the discovery_query at HEAD
returned zero sister sites AND no originating site exists — which together imply
the Delta K trigger did not fire (the row should be `N/A — discovery <command>
returned zero matches`, not `ran`).

`discovery_query` MUST scope to AT MINIMUM the unique directory parents of every
file in the commit's diff. Concretely: take `git diff --name-only <merge-base>..HEAD`,
extract the unique directory parents (a file at repo root with dirname `.` expands
to the repo's source roots — typically `src/`, `tests/` — and excludes generated/
vendored trees such as `node_modules/`, `vendor/`, `obj/`, `bin/` per the repo's
`.gitignore`), and pass them as the query's path arguments. Wider scope is
permitted and encouraged for cross-cutting patterns; narrower scope is forbidden.
If a sister site outside the recorded scope is later discovered, the LEDGER is
falsified per §2B.

The `delta-g-sweeps:` row uses N/A ONLY when the `discovery_query` executed at HEAD
returned zero sister sites (record the executed query in the reason). "No plausible
sister sites" or "single-file branch-new" without a recorded zero-result query is
NOT a valid N/A — the row must show `N/A — discovery <command> returned zero matches`.

**Status enum values** (consistent across LEDGER row, N/A reasons, and falsifiability
rules):
- `applied` — P has been applied to this site in the current change. Requires
  `evidence: <file:line-range>`.
- `already-applies` — P was already present at this site (no change). Requires
  `evidence: <file:line-range>`.
- `not-applicable` — site is exempt. Requires `rationale:` citing (a) a code property
  verifiable from the cited file OR (b) a contract/invariant defined elsewhere in
  the repo. Pure assertions about runtime behavior without code evidence are NOT
  valid rationale.

**branch_new_files_verified** — must cite the merge-base SHA used for the Delta J
check. Form: `yes — merge-base <SHA8>`. Reviewer can verify by running
`git ls-tree <SHA8> -- <paths>` for each branch-new site. A bare `yes` is not
sufficient.

**Falsifiability** (two independent checks; reviewer or future panel runs them at
the LEDGER's commit SHA, NOT current HEAD):
1. Re-execute every `discovery_query` at the LEDGER's commit SHA. If the output
   includes paths NOT listed in that pattern's `sites:`, the sweep is falsified
   per §2B's falsified-ledger remediation.
2. Open each site's `evidence: <file:line-range>` at the LEDGER's commit SHA. If
   the range does not contain P, the sweep is falsified per §2B.
3. Run `git merge-base origin/main <commit-SHA>` and verify it matches
   `branch_new_files_verified: yes — merge-base <SHA8>`. Mismatches trigger
   §2B falsified-ledger remediation.

Falsified sweeps are §2B falsification-level process violations: the agent MUST
proactively self-report in the next turn, re-run the sweep, amend the LEDGER, and
re-emit the commit.

**Reviewer-side verification hook** (in-scope per the Delta J precedent at lines
149-177 above — Delta I scope-discipline does NOT preclude this kind of mechanical
verification of agent-emitted artifacts): when reviewing PR-creation panels on
subsequent §2D rounds, panel reviewers MUST verify prior-commit LEDGER
`delta-g-sweeps:` entries by running the three falsifiability checks above on each
commit's LEDGER. Mismatches surfaced by the reviewer are blocking findings (not
meta-commentary), routed through the §2D standard finding-resolution flow.

**Rationale review (judgment surface)**: the `rationale:` field for `status:
not-applicable` is the ONE field in `delta-g-sweeps:` that cannot be mechanically
falsified — it is judgment text. The §2D heavy-slate panel substantively reviews
these rationales as part of its normal coverage; thin or boilerplate rationales
(e.g., "no risk", "doesn't apply", "not relevant") are panel-rejectable as blocking
findings per §2B falsification semantics. Per-commit panels in §3 see Delta K's
prompt only when their consumer prompt includes the mirror template; their default
posture is to flag suspicious rationales as findings but NOT to block (the §2D
gate is the substantive review).

**Examples of remediation patterns P** (illustrative; the rule applies regardless
of language or framework):
- Resource-cleanup symmetry (adding `Dispose`/`Drop`/`AutoCloseable` to mirror a
  sister type's cleanup behavior).
- Bounds-clamp before bulk copy (span/memcpy/slice writes from external input —
  applies in C#, C++, Rust, Go).
- Null/None coalesce in user-facing display strings (`??` in C#, `or` in Python,
  default-arg in Rust).
- Exception-catch around side-effecting interop calls in component lifecycle
  (e.g., `JSException` on JS module import in Blazor firstRender; equivalent in
  React error boundaries, Vue mounted-hooks).
- Pool-flush before file-handle-touching operations (e.g.,
  `SqliteConnection.ClearAllPools()` before `File.Delete` on Windows; equivalent
  in any DB driver with connection pooling).

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
