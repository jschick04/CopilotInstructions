# Known Copilot PR-review false positives

Registry of patterns the GitHub Copilot PR reviewer repeatedly raises across consuming projects that have been dismissed as **source-grounded false positives** — i.e., the dismissal cites a language spec, framework documentation, or runtime fact that Copilot has consistently failed to apply. Project-deidentified: entries are written so any consuming project's agent can recognize and dismiss without re-analysis.

Used by `pre-pr-creation-review.md` Step 2.5 (pattern preflight): if Copilot raises a finding that matches an entry here, the agent dismisses with the registered template + records the recurrence in `pr_review_findings.classification = 'recurring-false-positive'`. Recurrence count is the priority signal for whether to invest in mitigating an FP (e.g., by rewording the surrounding code so Copilot's pattern matcher doesn't trigger).

## Matching policy

The dismissal hinges on the underlying **technical claim**, not Copilot's exact wording. Phrasing in entries is illustrative; the agent matches semantically. If Copilot's model is updated and the phrasing shifts ("not in scope" → "isn't accessible from this namespace"; "won't compile" → "will fail to compile"), the dismissal still applies as long as the underlying claim matches. Wording drift across model updates does NOT invalidate an FP entry.

## Adding to this registry

When a Copilot false positive recurs ≥2 times AND the dismissal can be source-grounded (language spec, framework docs, runtime invariant), add an FP-N entry here with:
1. **Technical claim** (one sentence — what Copilot's underlying assertion is, abstracted from specific phrasing).
2. **Why it's a false positive** — the source-grounded evidence. Cite the spec section, framework docs URL, or runtime invariant. "Build green" alone is necessary but not sufficient — the entry MUST EXPLAIN why the build is green.
3. **Illustrative phrasings** — 1-2 real examples of how Copilot phrased the claim. Useful for pattern recognition; NOT the matching criterion.
4. **Recurrence pattern** — frequency / spread across PRs in the consuming project's history (not a specific count; the count belongs in SQL telemetry).
5. **Canonical dismissal template** — exact text to paste into `pr_review_findings.dismissal_rationale`.
6. **Mitigation candidates** — what could be done to stop the FP at the source (rewording code, configuration). If deferred, explain the cost/benefit.

False positives that DON'T meet the source-grounded bar (subjective style claims, "this looks wrong to me" without a spec citation) DO NOT go in this registry — they go in the per-finding analysis log instead.

---

## FP-1: "Type X is not in scope in namespace Y.Z (where X is declared in Y)"

**Technical claim**: a child namespace requires an explicit `using` directive to reference an identifier declared in its parent namespace.

**Why it's a false positive**:
Per the C# language specification (ECMA-334 § 13.8 "Namespace declarations" / equivalent C# 7 specification § 3.8 "Namespace and type names"), simple-name lookup walks enclosing namespaces from innermost to outermost. A type declared in a parent namespace is visible from any descendant namespace without a `using` directive. The compiler searches enclosing namespaces BEFORE consulting `using` directives. Build evidence: if the code compiles, the lookup succeeded — definitive proof the claim is wrong.

**Illustrative phrasings** (Copilot variants observed):
- "`SomeHelper` is referenced without being in scope. The helper lives in the `Foo` namespace, but this file is in `Foo.Bar`, so `SomeHelper.X(...)` will not compile unless you add `using Foo;` (or fully-qualify the type)."
- "`X` isn't accessible without an explicit `using` for its parent namespace."

**Recurrence pattern**: tends to recur across multiple PRs touching the same parent/child namespace pair. Copilot's pattern matcher doesn't apply the C# language rule consistently. May trigger when the parent namespace is short (1-2 segments) and the child is its direct descendant.

**Canonical dismissal template**:
> "False positive — C# child namespaces have implicit access to parent-namespace identifiers per ECMA-334 § 13.8 / C# 7 spec § 3.8. The file's namespace is a descendant of the target type's namespace; no `using` directive is required. Build green at the cited commit confirms the lookup succeeds. Recurring FP per `known-false-positives.md` FP-1."

**Mitigation candidates** (deferred for low FP cost):
- Add an explicit `using <parent-namespace>;` directive at the top of each affected file. Cost: 1 line per file. Benefit: Copilot stops raising. Trade-off: pollutes the explicit-using list with redundancies the compiler doesn't need.
- Move the referenced type into the descendant namespace if domain semantics permit. Trade-off: forces a namespace where it doesn't semantically belong.
- Status: project-by-project decision. Most projects find the FP cost lower than the mitigation churn.

---

## FP-2: "`await using` on a type that only implements `IDisposable`"

**Technical claim**: the type returned at the use site implements `IDisposable` but NOT `IAsyncDisposable`, so `await using` will not compile.

**Why it's a false positive**:
The agent must verify the actual type at the use site. Some BCL types implement BOTH `IDisposable` AND `IAsyncDisposable` and are common targets for this mis-classification:
- `Microsoft.Extensions.DependencyInjection.ServiceProvider` — both since .NET Core 3.0 (released 2019). See [ServiceProvider class reference](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.dependencyinjection.serviceprovider).
- `System.IO.Stream` — `IAsyncDisposable` added in .NET Core 3.0. See [Stream.DisposeAsync](https://learn.microsoft.com/en-us/dotnet/api/system.io.stream.disposeasync).
- Other BCL types: verify per-type before adding to this list. `System.Threading.SemaphoreSlim` and `System.Net.Http.HttpClient` are `IDisposable`-only as of .NET 8; do NOT add them.

Build evidence: if `await using var x = ...` compiles, the type implements `IAsyncDisposable`. Period. Verify by looking at the type's documented interfaces.

**Illustrative phrasings** (Copilot variants observed):
- "`SomeFactory(...)` returns `SomeType` (IDisposable). `await using` will not compile here unless the returned type implements `IAsyncDisposable`."
- "Use `using var` (or adjust the factory to return an async-disposable type)."

**Recurrence pattern**: Copilot's pattern matcher appears to have stale framework knowledge about which types implement `IAsyncDisposable`. Tends to recur in clusters (all 5 CLI command files in a single PR review batch), suggesting the matcher applies the claim consistently to all uses of a type once it's mis-classified.

**Canonical dismissal template**:
> "False positive — `<TypeName>` implements both `IDisposable` AND `IAsyncDisposable` since `<framework-version>` (cite: `<docs-url>`). Project targets `<consuming-project-tfm>`. `await using` compiles correctly. Build green at the cited commit confirms. Recurring FP per `known-false-positives.md` FP-2."

**Mitigation candidates**:
- None worth pursuing. The fix is on Copilot's side (knowledge base update). The cost of changing the code to use `using var` instead of `await using` would lose async-context benefits (some IAsyncDisposable implementations have legitimately-different async vs sync teardown).
- Alternative: explicit type annotation at the use site (`await using ServiceProvider sp = ...`) makes the interface implementation more obvious to Copilot's matcher. Minor readability cost; may reduce FP recurrence. Optional per-project.

---

## FP-3: "C++ raw-string literal content includes the surrounding parens / starts with `(`"

**Technical claim**: a `R"<delim>(...)<delim>"` (or `LR`/`u8R`/`uR`/`UR` wide/UTF prefixed variant) raw-string literal's *content* includes the `(` and `)` characters that bracket the content — typically rendered as "the string starts with `(` before the quoted exe path" or "wraps the command in parens (e.g., `(%s %s)`)".

**Why it's a false positive**:
Per the C++ standard (ISO/IEC 14882:2020 § 5.13.5 ¶ 4 "String literals", lex.string), a raw-string literal has the syntax `R"<d-char-sequence>(<r-char-sequence>)<d-char-sequence>"`, where:
- `<d-char-sequence>` is a user-chosen delimiter (0–16 characters, excluding parens / backslash / whitespace), often a single hyphen `-` or empty.
- `<r-char-sequence>` is the actual string content.
- The flanking `(` and `)` are part of the SYNTAX, not the content.

So `LR"-(%s %s)-"` produces a wide-string literal of exactly 5 characters (`%s`, space, `%s`) — NOT 7 characters (`(`, `%s`, space, `%s`, `)`). Same for `LR"-("%s")-"` which is 4 characters (`"`, `%s`, `"`), not 6.

**Empirical verification** (compile-and-run):
```cpp
#include <iostream>
int main() {
    std::wcout << L"[" << LR"-("%s")-" << L"] len=" << wcslen(LR"-("%s")-") << std::endl;
    std::wcout << L"[" << LR"-(%s %s)-" << L"] len=" << wcslen(LR"-(%s %s)-") << std::endl;
}
// Output:
// ["%s"] len=4
// [%s %s] len=5
```

Use this snippet (substituting the actual delimiters from the flagged code) when a similar claim recurs — runs in seconds and produces irrefutable evidence.

**Illustrative phrasings** (Copilot variants observed):
- "Because the string currently starts with `(` before the opening quote, paths with spaces will be parsed incorrectly and process creation can fail."
- "These command-line concatenations wrap the whole command in parentheses (e.g., `(%s %s)`), which changes the first token and can break `CreateProcessW` parsing."
- "Wrapping the entire command line in parentheses during argument append can change tokenization."

**Recurrence pattern**: Copilot's pattern matcher appears to treat the raw-string delimiter syntax as literal characters, especially when the delimiter is a single non-alphanumeric (`-`, `=`, `*`) or when the content itself contains `%s` format specifiers (which may confuse the matcher's heuristics). Tends to recur in clusters when one file uses several raw-string literals with the same delimiter (the matcher applies the mis-parse to each).

**Canonical dismissal template**:
> "False positive — `(` and `)` are part of the C++ raw-string-literal delimiter syntax `R\"<delim>(...)<delim>\"` per ISO/IEC 14882:2020 § 5.13.5 ¶ 4, NOT part of the string content. The runtime string is `<actual-content>` (length N), not `<copilot-misread>` (length N+2). Verified by compile+run of `wcslen(<the-literal>)`. Recurring FP per `known-false-positives.md` FP-3."

**Mitigation candidates**:
- Switch the delimiter to a more distinctive sequence (e.g., `LR"==(...)=="` instead of `LR"-(...)-"`) — Copilot's matcher may handle longer delimiters more reliably. Untested across model versions; low confidence.
- Switch from raw-string to escaped-string (`L"\"%s\""` instead of `LR"-("%s")-"`). Loses raw-string readability benefits; only worth it if the same file triggers the FP repeatedly across model updates.
- Add a `// raw-string delimiter: -` comment above the literal — does NOT silence Copilot (the matcher doesn't read context comments) but helps human reviewers verify quickly.
- Status: keep the raw-string syntax; dismiss the FP. The readability win of `LR"-("%s")-"` over `L"\"%s\""` is real and worth the FP cost.

