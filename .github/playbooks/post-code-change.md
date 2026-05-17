# Playbook: Post-code-change phase

## Purpose

After implementation, run the import / using hygiene pass, the multi-model reviewer panel, the verify-the-fix-actually-fixed-it check, and the affected builds + tests. Fires immediately after code edits land, before showing the diff to the user. Output: a green build with all reviewers in agreement and the diagnosis-verifying metric / test passing.

## Hard gates (also in `AGENTS.md` — repeated here for context)

- Touched-file imports / usings sorted and unused removed.
- **Touched-file least-privilege audit applied** (per `least-privilege-audit.md`, touched-file scope). **Trigger:** the diff has any **visibility / export / mutability surface delta** — adds a public/exported type or member; widens visibility; removes `sealed`/`final`/closed-extension; adds or widens a constructor/member/setter; exposes a field; changes package/module exports. Do NOT trigger on body-only edits to an already-public type that change no surface.
- **Touched-file review-recurring-pattern sweep run with explicit findings count reported** (see step 2.5). MANDATORY on every commit-bound change — silent skip is the failure mode this gate exists to prevent.
- Multi-model reviewer panel run **in parallel**; consensus reached or all dissents addressed.
- Diagnosis-verifying benchmark / test re-run; metric moved or test passes.
- Affected builds + tests pass.

## Intake questions

Bundle these in one prompt:

1. Should I run the **default 4-reviewer panel**, or add reviewers? (Default panel below. Add reviewers liberally for risky / cross-cutting / unfamiliar-area changes — there's no "too many reviewers".)
2. Any specific blind spots you want the reviewers to focus on? (e.g. concurrency safety, allocation hot paths, naming consistency across an interface chain)
3. **Perf work only:** confirm the benchmark from the pre-implementation phase is still the one I should re-run.

## Procedure

### 1. Imports / usings hygiene — whole-solution, scoped diagnostics

Run on every commit, before showing the diff. Scope is the **whole solution / workspace**, not just touched files: a file move or namespace change can leave a `using` orphaned or a fully-qualified prefix simplifiable in any consumer of the moved type — including consumers the current diff doesn't list. Skipping unchanged files leaves stale hygiene that the next commit's grep / reviewer will flag.

Restrict the cleanup to the using / qualifier hygiene diagnostics — do **not** run a blanket `dotnet format --severity info` (whole-solution), because it triggers unrelated style fixers (collection-initializer simplification, expression preferences, member ordering, ...) that produce a churn diff and can crash the formatter on unrelated workspace edges.

Use the language's ecosystem tooling for the whole solution / workspace in one pass:

| Language | Command |
| --- | --- |
| .NET | `dotnet format style <slnx-or-csproj> --no-restore --severity warn --diagnostics IDE0001 IDE0002 IDE0005 IDE0065` (Simplify name / Simplify member access / Remove unused using / Misplaced using). If the repo's `.editorconfig` does not set these to at least `warning` AND the project does not set `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>`, IDE0005 in particular is silent and the cleanup is a no-op. Workaround: append a temporary `dotnet_diagnostic.IDE000{1,2,5,65}.severity = warning` block to `.editorconfig`, run `dotnet format`, restore the original `.editorconfig`, then commit the cleanup separately from the override revert. The proper fix is to add the severity entries (or `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>`) to the repo permanently — propose that to the user when the workaround fires twice on the same repo. |
| TS / JS | `eslint --fix` plus the editor's "Organize Imports" |
| Python | `ruff check --select I --fix` or `isort` |
| Java / Kotlin | IntelliJ "Optimize Imports" |

After the cleanup, run the language's verify-no-changes form (`dotnet format --verify-no-changes` for .NET) — if it reports work, the cleanup was incomplete; iterate. Then run build + tests; the cleanup should be functionally inert.

Never commit a file with unsorted, duplicated, unused, or over-qualified imports — reviewers always flag them, and the noise hides real issues in the diff.

### 2. Touched-file least-privilege audit (6-axis)

Run the least-privilege audit on the touched-file scope before showing the diff. Procedure: **`.github/playbooks/least-privilege-audit.md`**, scope = touched files (`git diff --name-only <base>..HEAD`).

**Trigger:** the diff has any **visibility / export / mutability surface delta** — adds a public / exported type or member; widens visibility; removes `sealed` / `final` / closed-extension; adds or widens a constructor / member / setter; exposes a field; changes package / module exports; introduces an exported Go top-level identifier; widens Rust `pub(...)` to bare `pub`. Do NOT trigger on body-only edits to an already-public type that change no surface.

Goal: catch any new visibility / export / mutability surface introduced by this change that lacks a real consumer justifying the elevated visibility, before a reviewer flags it. The audit is fast at this scope (only the diff files); the highest-leverage moment is when the change is fresh.

Apply all 6 axes (per the playbook): type access, sealing/final, ctor visibility, member visibility, setter, field hygiene. "Fresh grep" beats every cached classification (use the language's best source-search tool — `rg`, compiler index, language-server symbol search — not literally `grep(1)`).

Skip when the diff has no visibility / export / mutability surface delta. When skipped, record explicitly which condition justified the skip ("diff touched only test fixtures + resource files, no production code", "diff was a body-only edit inside an already-public method").

### 2.5 Touched-file review-recurring-pattern sweep — MANDATORY, no silent skip

Run on touched files only — fast greps catching patterns that historically appear in PR reviews (GitHub Copilot, human reviewers) but aren't covered by language-native analyzers or the least-privilege audit. Each item is a single `rg` / grep query; if it returns matches, fix before showing the diff. The point is to make the recurring patterns *deterministically caught*, not encoded as rules the agent has to remember.

**MANDATORY OUTPUT REQUIREMENT.** This step MUST run on every commit-bound change, no matter how small. The agent MUST report findings explicitly in the message before showing the diff, in this exact format:

```
Step 2.5 sweep: ran, <N> findings.
  - Local-var-shadows-type: <N> matches (<files>)
  - Stale-id-after-rename: <N> matches (<files>) — N/A: no rename detected in this diff
  - Test-class-vs-file-name: <N> matches
  - DI-registration-vs-smoke-test-parity: <N> matches — N/A: no DI extension touched
  - Missing-null-guard-in-DI-extension: <N> matches — N/A: no DI extension touched
  - Planning-notation-in-public-comment: <N> matches
  - Test-parks-on-production-timeout: <N> matches — N/A: no test added/changed
  - Stale-symbol-in-comment-after-rename: <N> matches — N/A: no rename detected
```

`N/A` is allowed ONLY when the pattern's trigger condition definitionally cannot apply (e.g., no test files in the diff for "test-class-vs-file-name"). Do NOT mark as N/A because "I don't think it applies" or "the diff is small" — every check is a grep that takes milliseconds. Silent skip is the failure mode this rule exists to prevent.

---

**Universal patterns** (apply to all languages):

- **Local variable name shadows the type name (any casing).** Pattern: a single-statement declaration where the LHS identifier matches the RHS type identifier ignoring case (`var Filter = new Filter(...)`, `let user = new User(...)`, `result := Result{...}` when `result` is reused as a variable name within Result's scope). The locals make assertions ambiguous (`Filter.IsX` reads as type access) and shadow the type token. Use a distinguishing name (`filter`, `appliedFilter`, `sut`).
  - C# rg: `rg --type cs 'var (\w+) = new \1\(' <touched files>` (case-sensitive ASCII match is enough; review the hit manually for the camelCase variant).
- **Stale identifier after rename.** When a commit message contains "Rename X to Y" / "Rename X → Y" / `X→Y` / file rename `X.* → Y.*`, every occurrence of the OLD identifier in the diff and in same-feature consumer files (tests, comments, log strings, doc crefs) must be renamed too. Two queries: (1) on the touched files, `rg '\bX\b' <files>` — must be empty (or each remaining match must be intentional and commented); (2) on the language's same-feature test directory, `rg '\bX\b' tests/<feature>/` — flag any survivors. Apply to: type names, method names, action / record names, property names, slice / namespace tokens, comment references, log message symbols. **Test class names, test method names, comment references, log strings, and XML doc `<see cref>` are the four most-missed categories.**
- **Test class name does not match test file name.** For each new or renamed `*Tests.{cs,ts,py,go}` (or language-equivalent test convention), the top-level test class / suite identifier must match the file basename. Catches "FilterModelTests in SavedFilterTests.cs" drift after a type rename.
- **DI / IoC registration vs smoke-test parity.** When the diff modifies a DI composition extension method (`RegisterUiLibrary`, `AddServices`, `ConfigureServices`, language-equivalent), the matching smoke test that builds the provider and resolves each registered abstraction must be updated in the same commit. Without this, a missing or incorrect registration compiles fine and fails only at app startup.
  - Procedure: identify the DI extension touched (`rg 'public static.*IServiceCollection ' <diff>` or grep for `services.AddSingleton<` lines added/removed); locate its smoke test by name convention (`<ExtensionMethodName>Tests.cs` or co-located `Tests/DependencyInjection/*Tests.cs`); for each `services.AddSingleton<IFoo, Foo>` line added, the smoke test must have an `[InlineData(typeof(IFoo))]` (xUnit), `@ParameterizedTest` source (JUnit), `pytest.mark.parametrize` value (pytest), table-test entry (Go), etc.
  - The smoke test should provide stub instances for every *upstream* dependency the registered services need (mock factories / `Substitute.For<...>` / fakes), not just `IDispatcher` / `IServiceProvider`. Letting the provider actually build each abstraction is the whole point of the smoke test — otherwise it only proves the registration line compiles, not that DI can produce an instance.
  - If a registered abstraction transitively depends on a framework-scoped runtime type (e.g., Fluxor's auto-discovered `Effects`), document the exclusion in a comment next to the test and rely on the framework-init test (or production launch) to cover it.
- **Missing parameter null guard in public DI extension / factory method.** Any `public static T This<T>(this T self, ...)` extension method (composition-root DI extensions, builder extensions, fluent-API extensions) should validate its `this` parameter and any reference-typed required parameters with `ArgumentNullException.ThrowIfNull(...)` (or language equivalent — Java `Objects.requireNonNull`, Kotlin `requireNotNull`, Python explicit `if x is None: raise TypeError`, Go nil-check + return error). The smell: a sibling extension method in the same project already does the guard but the new one doesn't — readers infer inconsistency means one of them is wrong. Greppable by: `rg 'public static.*this I\w+' <diff>` then verify each matching method body starts with the guard.
- **Planning / commit-plan notation leaking into public-facing comments.** Any XML doc summary, `///` C# doc comment, JSDoc `/** */`, Python docstring, Go godoc, public method comment, or `[Description]` / `[Summary]` attribute string referenced by external consumers MUST NOT include ephemeral planning IDs (`D6`, `D9`, `A2`, `Phase 5.5`, `step 7c`, `option B-hybrid`, `(per F16e-2 cascade)`, internal commit-plan section numbers). Future readers don't have the plan and can't dereference the ID. Either inline the explanation, link to a permanent issue/PR URL, or remove the reference entirely. Greppable by: `rg --type cs '^\s*///' <diff> | rg -E '(D[0-9]+|A[0-9]+|Phase [0-9]+\.[0-9]+|step [0-9]+[a-z]|option [A-Z]-|F[0-9]+[a-z]*-?[0-9]*)'` — any hit is a planning leak.
- **Test parks on production timeout instead of mocking the waiter.** Any test that exercises an async code path with a `TaskCompletionSource` await, `WaitHandle.WaitOne(timeout)`, `Task.WaitAsync(timeout)`, `await ... .WaitAsync(LogCloseTimeout)`, `await ... .WaitAsync(TimeSpan.FromSeconds(N))`, or similar production-timeout-bounded wait, must route or signal the dependency so the test completes in milliseconds. Tests that allow the production timeout to fire turn a unit test into a 30s integration test, slow down CI, and mask correctness bugs (the test "passes" because the wait expires, not because the code worked). The fix is to mock the waiter source (NSubstitute `.When(...).Do(...)`, JUnit Mockito `doAnswer`, pytest monkeypatch) so the TCS signals quickly. Greppable on the test diff by: identify the production class's named timeout constants (`rg 'public static.*Timeout = TimeSpan' src/` to enumerate); for each new test that calls a method using one, verify the test has a mocked routing path that resolves the await source. Audit lens: any new `[Fact]` / `@Test` / `def test_` that takes >1 second to run is a smell — measure with `--verbosity normal` per-test duration.
- **Stale identifier inside comments after rename.** A sub-pattern of "stale identifier after rename" that reviewers keep flagging separately because grep over CODE often misses comment text. After any symbol rename, explicitly grep COMMENTS (`//`, `///`, `/*`, `#`, doc comments, attribute strings) for the old name: `rg --type cs '(//|///|/\*)\s*.*\bOLDNAME\b' <touched files>`. The diff's code edits typically renamed the call sites; the human-written explanations *next to* those call sites often retain the old name. Same applies to log message string literals.

**Language-specific additions** (delegated to per-language instructions):

- **C# (.NET / Razor):** see `csharp.instructions.md` *Recurring code smells* for the catalog of patterns to grep beyond the universal patterns above (e.g., `using NamespaceName;` inside a file whose namespace is `NamespaceName` — `rg '^using ([\w.]+);' <touched .cs files>` cross-referenced against each file's `namespace X;` declaration).

### 3. Multi-model reviewer panel — run all in parallel

The user has no token-budget caps on this work, so always launch the full reviewer panel **in parallel** (background agents) rather than serially. Iterate, re-running the panel after each fix round, until **all models agree** with no substantive findings.

**Default reviewer panel** (launch all of these as background agents in the **same response** — three as `code-review`, one as `rubber-duck`; at least one model from each family):

- `claude-opus-4.7-xhigh` (default Claude family, extra-high reasoning) — `code-review`
- `gpt-5.5` (OpenAI family, premium reasoning) — `code-review`
- `gpt-5.3-codex` (OpenAI family, codex-tuned — different perspective from gpt-5.5) — `code-review`
- **rubber-duck** agent (independent critique angle — not a code-review reviewer per se, but provides design / blind-spot feedback that complements line-level review)

**Add reviewers liberally** when a change is risky, cross-cutting, or touches an unfamiliar area: `claude-sonnet-4.6` for a faster second-Claude opinion, `gpt-5.5` re-run with a different prompt framing, etc. There is no "too many reviewers" — parallel agents are cheap and the marginal cost of one more independent reading is approximately zero.

**Do NOT serialize the panel** ("run Claude first, then if it finds nothing run GPT") — that wastes wall-clock time and lets early reviewer framing leak into your assessment of later reviews. Launch all reviewers in one tool-call batch, wait for completions, then synthesize.

**Sub-agents must NEVER prompt the user.** Reviewer / rubber-duck agents run autonomously in the background — the user is typically away from the keyboard. Every panel-prompt must include the explicit instruction: *"Do not call `ask_user` or any other tool that prompts the user. If the task is ambiguous, make a reasonable assumption, document it in your output, and continue. Return findings only."* Sub-agents that block on user input deadlock the panel, defeat the parallel-launch design, and leave the user with no way to make progress when they return. The orchestrator (you) is the only agent allowed to call `ask_user` — collect findings from all sub-agents, then surface decisions to the user yourself.

### 4. Anti-anchoring rules for reviewer prompts

Do not anchor reviewers on your own framing. Prompts must instruct the reviewer to treat the description of the fix as a hypothesis and independently read the affected types and call sites.

Specific reviewer-prompt requirements (from recurring failure modes in past PR history):

- **State predicates** (see `AGENTS.md` §3.7): if the diff introduces a predicate over a type's state (`IsEmpty`, `IsDefault`, equality / match check), the reviewer must open that type's source and enumerate every member before accepting the predicate as complete.
- **Cross-boundary parameter / property names** (see `AGENTS.md` §3.6 "Defaults and Consistency"): if the diff introduces or renames a parameter that crosses an interface / implementation boundary, the reviewer must enumerate every signature in the chain — interface, abstract base, every implementation, every caller, every lambda that closes over it — and verify the name is identical at every layer.
- **Literals-in-collections** (see `AGENTS.md` §3.10): if the diff adds or modifies a collection whose members reflect literals used elsewhere in the codebase, the reviewer must open every site that produces those literals and verify each one references the collection's members rather than re-typing the literal.
- **Public surface additions** (see `least-privilege-audit.md`): if the diff adds a new `public` / exported type or member, the reviewer must independently verify there's a real cross-asm consumer; no speculative public surface.
- **Test intent and coverage gaps** (see `AGENTS.md` §3.4 and `csharp.instructions.md` "Test purpose" / "Test gap audit"): when the diff touches tests OR adds/modifies a SUT branch, the reviewer must run a *two-direction* audit. Direction A — judge whether each present test pins a real regression; flag tautological / coverage-driven / mock-only / framework-testing tests for deletion. Direction B — enumerate the SUT's behaviors in scope and call out behaviors that have *no* test (failure paths, boundary conditions, reverse/descending modes, null-valued inputs, each branch of each `switch`/`if`, integration seams). Missing tests for these are defects of the same severity as filler tests. Reviewers must NOT accept "tests pass and coverage didn't drop" as evidence of correctness — that only proves the existing one-direction tests still hold. For mechanical port / decompose commits the panel should not demand new tests in the same commit, but it MUST surface the gap list as a follow-up commit candidate.

### 5. Synthesize and iterate

After all reviewers complete, briefly summarize cross-model agreement. Iterate the panel after each fix round until no substantive findings remain. **Same parallel-panel rule applies to PR reviews** (post-PR-review playbook): when running `pr-review` after a PR exists, launch the same panel in parallel.

Route any sub-agent finding outside the immediate scope through `ask_user` (per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule in `AGENTS.md` §1): address now / defer to a follow-up (record externally — session note, issue, tracker — never as TODO comment) / dismiss with reason.

### 6. Verify the fix actually fixed it

The benchmark / test from `pre-implementation.md` must show the expected delta (perf) or pass (functional). If the metric didn't move, the change is a no-op — revert and re-diagnose. Do not paper over a no-op fix with reviewer agreement.

### 7. Run affected builds and tests

All must pass before proceeding to `pre-commit.md`. If a test fails:

- If the test is a regression caused by your change: fix it (return to step 3).
- If the test was failing before your change (pre-existing): route via `ask_user` per the *Pre-existing issues* cross-cutting rule in `AGENTS.md` §1 — never silently fix it as part of this change.

### 7. Audit before declaring done

Immediately before reporting "ready for diff review" / "all reviewers agree" / "no remaining issues," re-read every sub-agent response from this task and confirm that every distinct finding (regardless of severity or scope label) has either (a) been fixed in the diff, or (b) been routed through an `ask_user` call this turn. If any finding is in neither bucket, stop and route it through `ask_user` first.

## Next phase

Once builds + tests + reviewer consensus + verification all clear, proceed to `pre-commit.md`.
