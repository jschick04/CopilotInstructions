# PR Quality Gate — Pattern Catalog

Empirical catalog of patterns the GitHub Copilot PR reviewer flags across consuming projects. Each entry is a single markdown table row + JSON `params` per the schema in `README.md` §"Catalog grammar".

This catalog is **project-deidentified**: signatures and patterns are abstract; consuming projects do not need to customize it. FP entries are inline (no separate file).

<!-- Schema reminder (per README.md §Catalog grammar):
     | slug | scope_mode | params | review_pass_only_prompt | fp_slug |
     Pipe characters inside JSON values escaped as \|. Parser unescapes before JSON.parse. -->

## Patterns (high-frequency battery, ≥5 hits in seed corpus)

| slug | scope_mode | params | review_pass_only_prompt | fp_slug |
|---|---|---|---|---|
| doc-impl-mismatch | review-pass-only | {} | For every modified source file with XML docs, inline comments, PR description text, or README claims: read each prose claim and verify the surrounding code actually does what the prose says. Common failure modes: XML doc claims thread-context that captured SC contradicts; PR description names a feature the markup does not render; `<see cref>` references that won't resolve; "this delegates to X via COM" when X uses procedural API. Flag every prose-vs-code divergence. |  |
| comment-necessity | review-pass-only | {} | For every comment ADDED in the diff (`//` inline, `/* */` block, `///` XML doc — NOT pre-existing comments in the baseline that happen to live in modified files): verify it clarifies genuinely subtle behavior. Flag comments that (a) restate what the code obviously does (e.g., `// Increment counter` above `counter++;`), (b) reference panel artifacts (slot numbers, round numbers, PR-bundle labels like `PR 1+2`, panel-phase names), (c) duplicate XML method summaries with inline comments, (d) include multi-line XML `<remarks>` blocks on internal types, (e) narrate refactor/PR history inline. Acceptable: brief single-line clarifications for non-obvious *why* (concurrency invariants, race-safety rationale, BCL quirks, FP override citations, spec/standard references); brief `///<summary>` on public APIs. Apply the principle: "Only comment code that needs a bit of clarification. Do not comment otherwise." Use the diff to distinguish NEW comments from baseline. |  |
| panel-artifact-leakage | diff-scoped | {"pattern":"\\b(Slot \\d+\|R\\d+ (finding\|fix\|round\|rework\|ready)\|PR \\d+\\+\\d+\|pre-(implementation\|PR-creation) panel)\\b","glob":["*.cs"]} |  |  |
| resource-cleanup | hybrid | {"tree":{"pattern":"new\\s+(CancellationTokenSource\|SqliteConnection\|SqlConnection\|FileStream\|StreamReader\|StreamWriter\|HttpClient\|ProcessStartInfo)\\(","glob":["*.cs"]},"diff":{"pattern":"new\\s+(CancellationTokenSource\|SqliteConnection\|SqlConnection\|FileStream\|StreamReader\|StreamWriter\|HttpClient\|ProcessStartInfo)\\(","glob":["*.cs"]}} |  |  |
| naming-convention | diff-scoped | {"pattern":"^\\s+var [A-Z][a-z]","glob":["tests/**/*.cs"]} |  |  |
| async-correctness | hybrid | {"tree":{"pattern":"SaveChanges\\(\\)\|_ = InvokeAsync\|\\.Result\\b\|\\.Wait\\(\\)","glob":["*.cs"]},"diff":{"pattern":"SaveChanges\\(\\)\|_ = InvokeAsync\|\\.Result\\b\|\\.Wait\\(\\)","glob":["*.cs"]}} |  |  |
| thread-safety | tree-scoped | {"pattern":"IProgress<.*>\|new Progress<","glob":["*.cs"]} |  |  |
| bounds-empty-collection | diff-scoped | {"pattern":"\\b\\w+\\[0\\]\|stackalloc \\w+\\[\\w+\\.Length\\]","glob":["*.cs"]} |  |  |
| aria-binding | diff-scoped | {"pattern":"aria-\|_is[A-Z]\\w+\\s*=\\s*(true\|false\|!_)","glob":["*.razor","*.razor.cs"]} |  |  |
| regex-validation | tree-scoped | {"pattern":"new Regex\\(\|filter.*regex\|regex.*filter","glob":["*.cs","*.razor"]} |  | fp-1 |
| razor-binding | hybrid | {"tree":{"pattern":":empty","glob":["*.css"]},"diff":{"pattern":"@onscroll\|@onkeydown\|@onkeyup\|(public\|protected) (async )?(void\|Task) (Show\|Hide\|Toggle\|Open\|Close)\\w*","glob":["*.razor","*.razor.cs"]}} |  |  |
| null-handling | diff-scoped | {"pattern":"\"\\[.*\\{[^}]*\\}\\]\"","glob":["*.cs"]} |  |  |

## Patterns (lower-frequency, 3-4 hits in seed corpus)

| slug | scope_mode | params | review_pass_only_prompt | fp_slug |
|---|---|---|---|---|
| js-interop-lifecycle | diff-scoped | {"pattern":"JSRuntime\\.InvokeAsync<IJSObjectReference>\|catch \\(JSException\|catch \\(JSDisconnectedException","glob":["*.cs","*.razor.cs"]} |  |  |
| internals-visibility | diff-scoped | {"pattern":"InternalsVisibleTo","glob":["*.cs"]} |  |  |
| image-link-broken | diff-scoped | {"pattern":"!\\[.*\\]\\(","glob":["*.md"]} |  |  |
| partial-file-cleanup | diff-scoped | {"pattern":"new\\s+(ProviderDbContext\|FileStream\|StreamWriter).*new","glob":["*.cs"]} |  |  |
| perf-batching | review-pass-only | {} | For every operation/component in the diff that emits per-row, per-entry, or per-iteration UI updates (`StateHasChanged`, `Progress<T>.Report`, `InvokeAsync(StateHasChanged)`, event-handler chains): verify the update is batched/throttled — not called on every loop iteration that may run thousands of times. For every data-source enumeration (provider list, log entries, EF Core query results): verify single-pass — flag patterns like "load names first, then load details in a second pass" that imply N+1 or double-scan. For every async-foreach loop: verify the loop body doesn't await per-item if the workload is independent (consider `Task.WhenAll` + batching). |  |
| logic-inversion | review-pass-only | {} | For every early-return / short-circuit guard in modified `.cs`/`.razor.cs` files with predicates involving `!=`, `!`, `!=!`, or double-negatives: re-read the guard and verify it exits when state is the desired state, not when state is the OPPOSITE. Common bug: `if (_show != !isPinned) return;` — when `_show == !isPinned` (desired-state-already-set), this DOES exit; otherwise it doesn't. Verify the polarity matches intent. Ternary expressions returning the wrong branch (`condition ? badValue : goodValue`) and cross-method state flips where state is inverted twice and end up wrong are also caught here. |  |
| iasyncdisposable-fp | review-pass-only | {} | For every `await using` over a BCL type: verify the type implements `IAsyncDisposable` per Microsoft docs. Common FP: `ServiceProvider` (does implement both since .NET Core 3.0); `Stream` (does since .NET Core 3.0). Confirmed IDisposable-only: `SemaphoreSlim`, `HttpClient` (per .NET 8 docs). Cross-reference fp-2 below. | fp-2 |

---

## FP-1: parent-namespace-not-in-scope

**Technical claim**: a child namespace requires an explicit `using` directive to reference an identifier declared in its parent namespace.

**Why FP**: Per C# spec ECMA-334 § 13.8 (Namespace declarations) / C# 7 spec § 3.8 (Namespace and type names), simple-name lookup walks enclosing namespaces from innermost to outermost. A type declared in a parent namespace is visible from any descendant namespace without a `using` directive. Build green = lookup succeeded = claim is wrong.

**Recurrence pattern**: tends to recur across multiple PRs touching the same parent/child namespace pair; Copilot's pattern matcher doesn't apply the C# language rule consistently. Phrasing varies ("isn't in scope", "won't compile", "requires explicit using") — match on technical claim, not exact wording.

**Canonical dismissal template**:
> False positive — C# child namespaces have implicit access to parent-namespace identifiers per ECMA-334 § 13.8 / C# 7 spec § 3.8. The file's namespace is a descendant of the target type's namespace; no `using` directive is required. Build green at the cited commit confirms the lookup succeeds. Recurring FP per `pattern-catalog.md` FP-1.

**Mitigation candidates** (deferred for low FP cost): add explicit `using <parent-namespace>;` per file (1 line per file; reduces FP but pollutes the using list); move type into descendant namespace if domain semantics permit (forces a namespace where it doesn't semantically belong). Status: project-by-project decision.

## FP-2: await-using-on-idisposable-only-type

**Technical claim**: the type returned at the use site implements `IDisposable` but NOT `IAsyncDisposable`, so `await using` will not compile.

**Why FP**: agent must verify the actual type at the use site. Specifically:
- `Microsoft.Extensions.DependencyInjection.ServiceProvider` — implements BOTH `IDisposable` AND `IAsyncDisposable` since .NET Core 3.0 (2019). See [ServiceProvider class reference](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.dependencyinjection.serviceprovider).
- `System.IO.Stream` — implements BOTH since .NET Core 3.0. See [Stream.DisposeAsync](https://learn.microsoft.com/en-us/dotnet/api/system.io.stream.disposeasync).
- `System.Threading.SemaphoreSlim` and `System.Net.Http.HttpClient` are `IDisposable`-only as of .NET 8; do NOT add them to the dismissal list.

Build evidence: if `await using var x = ...` compiles, the type implements `IAsyncDisposable`. Period.

**Recurrence pattern**: Copilot's pattern matcher appears to have stale framework knowledge about which BCL types implement `IAsyncDisposable`. Tends to recur in clusters (all N CLI command files in a single review batch).

**Canonical dismissal template**:
> False positive — `<TypeName>` implements both `IDisposable` AND `IAsyncDisposable` since `<framework-version>` (cite: `<docs-url>`). Project targets `<consuming-project-tfm>`. `await using` compiles correctly. Build green at the cited commit confirms. Recurring FP per `pattern-catalog.md` FP-2.

**Mitigation candidates**: none worth pursuing. Fix is on Copilot's side. Optional: explicit type annotation at the use site (`await using ServiceProvider sp = ...`) makes the interface implementation more obvious to Copilot's matcher — may reduce FP recurrence.

---

## Catalog maintenance

After each PR final state (converged-to-zero OR merged OR closed-with-deferred-findings-tracker):

1. Append findings to the global `data/findings.csv` (per its schema).
2. Re-run the regex classifier against the corpus. If a NEW pattern appears with frequency ≥3 across the corpus, propose adding to this catalog (PR to CopilotInstructions) with abstract phrasing.
3. If a pattern's hit rate is decaying (fewer hits round-over-round), demote it from high-frequency battery to lower-frequency section. Demotions require ≥2 consecutive rounds of zero-hits to confirm decay.
4. Update FP entries if Copilot raises a new FP worth deterring (≥2 recurrences + source-grounded dismissal).
5. Commit catalog updates to `CopilotInstructions/<branch>`. Catalog is project-deidentified; no per-project data ever lands here.
