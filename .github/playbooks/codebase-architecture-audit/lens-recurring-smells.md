# Lens: recurring smells (§3.10)

## Purpose

Apply AGENTS.md §3.10 (recurring code smells from past PR reviews) to in-scope code. §3.10 enumerates ~25 high-incidence smell categories from real PR-review history; this lens scans for them. Sub-file of `codebase-architecture-audit.md`.

## Hard gates

- **Read-only**.
- **Per-lens evidence-gate output** before findings (see *Procedure* step 21).
- **Source-grounded**: every finding cites `file:line`; for cross-site smells (constants drift, sibling consistency, list-of-X collections referencing literals) cite all relevant sites.

## Inherits

Scope, risk-tolerance, and output destination from the calling index.

## Procedure

1. **Constant single-source-of-truth** - search for duplicated numeric / string literals that constrain a contract (page sizes, in-clause caps, retention windows, timeouts, magic file paths). When the same literal appears in 2+ places, flag as drift risk and propose extraction to a named constant.
2. **"List of X" referencing constants** - when a collection enumerates the same well-known names that another file builds by literal, flag both sites and propose: literals → named constants → both the collection and the originating site reference the constants.
3. **Sibling-constant consistency** - within a single declaration block of related constants, check formatting / punctuation / casing / units. Common drift: trailing period on one of three error messages, `"OK"` vs `"Ok"` vs `"Okay"`, `5000` vs `5_000`.
4. **Weak test assertions** - `grep` for `Arg.Any<>` / `It.IsAny<>` / `Mock.Of<>` / equivalents and `DoesNotContain` / `NotEqual` when the test's contract is *"value is X"* (negative assertion passes on null / empty / wrong value). Propose property-based matchers or exact equality.
5. **Materialization in hot paths** - `grep` for `.ToList()` / `.ToArray()` inside methods that iterate once; `.Where(...).Count()` instead of `.Any()`. Flag potential allocation smells in hot code.
6. **Lambda parameter shadowing** - `grep` for `(\w+)\s*=>\s*\1\.` patterns where the lambda parameter name equals an in-scope variable name (`filter => filter.X` when `filter` is the outer collection).
7. **Silent failure on user action** - UI / action handlers that no-op on `TryParse` / `TryCreate` failures without surfacing a user-visible message or log. Flag and propose surfacing.
8. **Comment hygiene smells** - `TODO` / `FIXME` / debug `Console.WriteLine` / `console.log` / `print()` / absolute local paths. Flag for cleanup per §3.1.
9. **Idempotency / multi-dispatcher guards missing on second site** - when one code path has `if (_done) return;` but another mutating-the-same-state path lacks the guard.
10. **Empty / hollow exception messages** - exceptions whose `Message` is `string.Empty`, a bare type name, or omits the diagnostic context (resource path, key, operation).
11. **Log-message vs code-path mismatch** - logs that say "Returning null" / "Failed" / "Falling back" when the surrounding method actually returns a sentinel / takes a different branch. `grep` log strings against return statements / branch labels.
12. **Test portability hardcoded paths** - tests that hardcode `C:\Windows`, `C:\Program Files`, `\System32\en-US\`, drive letters, or specific UI culture folder names.
13. **Dead branches inside loops** - `while` / `for` loops with an inner `if (state) break;` that fires on the same state already excluded by the loop condition.
14. **Stale terminology when scope widens** - helper methods whose summary / catch-block log / `[Display]` attribute references the original narrower scope (*"legacy"*, *"registry"*, *"v1"*, *"primary"*, *"single-tenant"*) when the method now serves the broader case.
15. **Hardcoded parameter the caller threads through** - `Outer(bool x)` does `!x` work itself and calls `Inner(..., x: true)` with a literal instead of propagating `x`. Splits parameter meaning between two places; flag for either propagation or rename.
16. **Status / outcome enum ambiguity** - status enums where multiple `return EnumValue;` sites use the same value for distinct semantic outcomes (success / no-op-already-done / failed-with-recovery). Propose splitting values per distinct outcome.
17. **Sibling-producer parity** - when 2+ producers emit instances of a shared record / DTO type, every producer must stamp every metadata field a downstream consumer depends on. Flag any producer that omits a field other producers set.
18. **Missing param null-guard in public extensions** - `public static T This<T>(this T self, ...)` extension methods that don't validate `this` parameter when sibling extensions do.
19. **Planning markers in public-facing comments** - XML doc summary / docstring / godoc / `[Description]` attribute referencing ephemeral planning IDs (`D6`, `Phase 5.5`, `A2`, internal commit-plan section numbers, session file paths).
20. **Tests parking on production timeouts** - test that awaits with `WaitOne(LogCloseTimeout)` / `Task.WaitAsync(productionTimeout)` and depends on the timeout firing rather than the dependency signaling. Slow CI + masks real bugs.
21. **Per-lens evidence-gate output**:

   ```
   Lens recurring-smells audit: scope=<files scanned, method=grep|view>, S smell categories scanned (out of 20+), F findings.
   - by category: <category name>: N findings (citations) - repeat per category found
   - zero-count justification per category that returned 0 (e.g., "constant single-source-of-truth: 0 - every literal in scope appears exactly once per <grep>")
   ```

22. **Findings list** - severity, location, issue, proposal, intent-clarity justification. Returned to index for aggregation.

## Output

Findings list + per-lens evidence-gate audit. Consumed by `codebase-architecture-audit.md` aggregation step.
