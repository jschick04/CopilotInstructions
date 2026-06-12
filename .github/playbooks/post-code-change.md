# Playbook: Post-code-change phase
<!-- read-receipt-token: d36f8f31 -->

## Purpose

After implementation, run the import/using hygiene pass, the touched-file recurring-pattern sweep, the multi-model reviewer panel (via `multi-model-review.md`), the verify-the-fix-actually-fixed-it check, and the affected builds + tests. Fires immediately after code edits land, before showing the diff to the user. Output: a green build with the panel converged and the diagnosis-verifying metric/test passing.

## Hard gates (also in `AGENTS.md` - repeated here for context)

- Touched-file imports/usings sorted and unused removed.
- **Touched-file least-privilege audit applied** (per `least-privilege-audit.md`, touched-file scope). **Trigger:** the diff has any **visibility/export/mutability surface delta** - adds a public/exported type or member; widens visibility; removes `sealed`/`final`/closed-extension; adds or widens a constructor/member/setter; exposes a field; changes package/module exports. Do NOT trigger on body-only edits to an already-public type that change no surface.
- **Touched-file review-recurring-pattern sweep run with explicit findings count reported** (see step 2.5). MANDATORY on every commit-bound change - silent skip is the failure mode this gate exists to prevent.
- **§3.1 comment audit evidence-gate output emitted** (see step 2.6) before the diff is shown - structured chat block enumerating every NEW comment line with one-line justifications per the §3.1 self-review pass rule.
- Multi-model reviewer panel run via `multi-model-review.md` (utility-called by this phase) with `unanimous` convergence model; cumulative log shows convergence reached with 0 unaddressed blocking findings and `subagent_ask_user_calls=0` per round.
- Diagnosis-verifying benchmark/test re-run; metric moved or test passes.
- Affected builds + tests pass.

## Intake questions

Bundle these in one prompt:

1. Should I run the **active profile's default panel** (full = 6 reviewers; lite = 3 cross-family light-tier; per the loaded `active-profile.instructions.md`, none loaded -> full), or add reviewers? (Default panel below. Add reviewers liberally for risky/cross-cutting/unfamiliar-area changes.)
2. Any specific blind spots you want the reviewers to focus on? (e.g. concurrency safety, allocation hot paths, naming consistency across an interface chain)
3. **Perf work only:** confirm the benchmark from the pre-implementation phase is still the one I should re-run.

## Procedure

### 1. Imports/usings hygiene - whole-solution, scoped diagnostics

Run on every commit, before showing the diff. Scope is the **whole solution/workspace**, not just touched files: a file move or namespace change can leave a `using` orphaned in any consumer.

Restrict to using/qualifier hygiene diagnostics - do **not** run blanket `dotnet format --severity info` (triggers unrelated style fixers producing churn diffs).

| Language | Command |
| --- | --- |
| .NET | `dotnet format style <slnx-or-csproj> --no-restore --severity warn --diagnostics IDE0001 IDE0002 IDE0005 IDE0065` (Simplify name / Simplify member access / Remove unused using / Misplaced using). If the repo's `.editorconfig` does not set these to at least `warning` AND the project lacks `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>`, IDE0005 is silent. Workaround: append temporary `dotnet_diagnostic.IDE000{1,2,5,65}.severity = warning` to `.editorconfig`, run format, restore original, commit cleanup separately. Propose making the severity entries permanent when the workaround fires twice on the same repo. |
| TS / JS | `eslint --fix` plus "Organize Imports" |
| Python | `ruff check --select I --fix` or `isort` |
| Java / Kotlin | IntelliJ "Optimize Imports" |

After cleanup, run the verify-no-changes form (`dotnet format --verify-no-changes` for .NET) - if it reports work, iterate. Then run build + tests; the cleanup should be functionally inert.

Never commit a file with unsorted, duplicated, unused, or over-qualified imports.

### 2. Touched-file least-privilege audit (6-axis)

Run on touched-file scope before showing the diff. Procedure: **`.github/playbooks/least-privilege-audit.md`**, scope = touched files (`git diff --name-only <base>..HEAD`).

**Trigger:** the diff has any **visibility/export/mutability surface delta** - adds a public/exported type or member; widens visibility; removes `sealed`/`final`/closed-extension; adds or widens a constructor/member/setter; exposes a field; changes package/module exports; introduces an exported Go top-level identifier; widens Rust `pub(...)` to bare `pub`. Do NOT trigger on body-only edits to an already-public type that change no surface.

Apply all 6 axes (per the playbook): type access, sealing/final, ctor visibility, member visibility, setter, field hygiene. Use the language's best source-search tool (`rg`, compiler index, language-server symbol search).

Skip when the diff has no visibility/export/mutability surface delta. Record explicitly which condition justified the skip.

### 2.5 Touched-file review-recurring-pattern sweep - MANDATORY, no silent skip

Run on touched files only - fast greps catching patterns that historically appear in PR reviews but are not covered by language-native analyzers or the least-privilege audit. Each item is a single `rg`/grep query; if it returns matches, fix before showing the diff.

**MANDATORY OUTPUT REQUIREMENT.** This step MUST run on every commit-bound change, no matter how small. The agent MUST report findings explicitly:

```
Step 2.5 sweep: ran, <N> findings.
  - Local-var-shadows-type: <N> matches (<files>)
  - Stale-id-after-rename: <N> matches (<files>) - N/A: no rename detected in this diff
  - Test-class-vs-file-name: <N> matches
  - DI-registration-vs-smoke-test-parity: <N> matches - N/A: no DI extension touched
  - Missing-null-guard-in-DI-extension: <N> matches - N/A: no DI extension touched
  - Planning-notation-in-public-comment: <N> matches
  - Test-parks-on-production-timeout: <N> matches - N/A: no test added/changed
  - Stale-symbol-in-comment-after-rename: <N> matches - N/A: no rename detected
```

`N/A` is allowed ONLY when the pattern's trigger condition definitionally cannot apply (e.g., no test files in diff). Do NOT mark N/A because "I don't think it applies" or "the diff is small" - every check is a grep that takes milliseconds. Silent skip is the failure mode this rule exists to prevent.

---

**Universal patterns** (apply to all languages):

- **Local variable name shadows the type name (any casing).** A declaration where LHS identifier matches RHS type ignoring case (`var Filter = new Filter(...)`, `let user = new User()`). Use a distinguishing name.
  - C# rg: `rg --type cs 'var (\w+) = new \1\(' <touched files>`

- **Stale identifier after rename.** When commit contains "Rename X to Y" / file rename, every occurrence of OLD identifier must be renamed. Two queries: (1) `rg '\bX\b' <touched files>` - must be empty; (2) `rg '\bX\b' tests/<feature>/` - flag survivors. **Most-missed categories: test class names, test method names, comment references, log strings, XML doc `<see cref>`.**

- **Test class name does not match test file name.** For each new/renamed `*Tests.{cs,ts,py,go}`, top-level test class must match file basename.

- **DI/IoC registration vs smoke-test parity.** When diff modifies a DI composition extension, the matching smoke test that builds the provider and resolves each registered abstraction must be updated in same commit. Identify DI extension (`rg 'public static.*IServiceCollection ' <diff>`); locate smoke test by convention; for each `services.AddSingleton<IFoo, Foo>` added, smoke test must have matching `[InlineData(typeof(IFoo))]` or equivalent. Smoke test should provide stub instances for every upstream dependency.

- **Missing parameter null guard in public DI extension/factory method.** Any `public static T This<T>(this T self, ...)` extension must validate `this` parameter and reference-typed required parameters with `ArgumentNullException.ThrowIfNull(...)` (or language equivalent). Greppable: `rg 'public static.*this I\w+' <diff>` then verify each method body starts with the guard.

- **Planning/commit-plan notation leaking into public-facing comments.** XML doc, JSDoc, docstrings, `[Description]` strings MUST NOT include ephemeral planning IDs (`D6`, `Phase 5.5`, `step 7c`, `option B-hybrid`, internal plan section numbers). Greppable: `rg --type cs '^\s*///' <diff> | rg -E '(D[0-9]+|A[0-9]+|Phase [0-9]+\.[0-9]+|step [0-9]+[a-z]|option [A-Z]-|F[0-9]+[a-z]*-?[0-9]*)'`

- **Test parks on production timeout instead of mocking the waiter.** Any test exercising an async path with `TaskCompletionSource` await, `WaitHandle.WaitOne(timeout)`, `Task.WaitAsync(timeout)` etc. must route/signal the dependency so the test completes in milliseconds. Fix: mock the waiter source. Audit: any new test taking >1s is a smell.

- **Stale identifier inside comments after rename.** After any symbol rename, explicitly grep COMMENTS for old name: `rg --type cs '(//|///|/\*)\s*.*\bOLDNAME\b' <touched files>`. Log message string literals also apply.

- **Null-conditional on non-nullable field or parameter.** Field typed `T` (not `T?`) accessed via `_field?.Method()` is either a nullability lie or unnecessary defensive code. Greppable: collect non-nullable fields (`rg 'private readonly \w+ _\w+' <file>` excluding `?`), check for `_fieldName?.` in same file.

- **IDisposable swap-without-dispose.** When code swaps a field holding `IDisposable` (`oldCts = _field; _field = new CancellationTokenSource()`), the old value must be disposed after the swap. Greppable: `rg '= new CancellationTokenSource|= new SemaphoreSlim|= new Timer' <touched files>` - verify previous value disposed.

- **Double-dispose via `await using` + explicit `DisposeAsync`.** Resource declared `await using var x = ...` AND later explicitly `await x.DisposeAsync()` causes double-dispose. Fix: drop `await using` and manage manually, or keep `await using` and use non-disposing stop mechanism.

- **Duplicate/dead UI menu items.** When adding a menu item, verify action handler is distinct from existing items. Greppable: `rg 'MenuItem\.Item\(' <touched razor.cs files>` - compare action lambdas.

- **Snapshot-then-re-read field inconsistency.** When a method snapshots a volatile/shared field into a local, every subsequent read must use that snapshot - not re-read the field. Greppable: find `var snapshot = _field` patterns, search method body for subsequent `_field` reads.

- **Redundant `using` for own namespace.** A `using X.Y.Z;` in a file whose namespace is `X.Y.Z` is redundant. Greppable: `rg '^using ([\w.]+);' <touched .cs files>` cross-referenced against each file's `namespace` declaration.

- **Internal type leaked to test via IVT when public abstraction exists.** Test constructs an `internal` type directly while a public interface/factory exists. Fix: resolve through the public abstraction via DI.

- **ServiceProvider created but not disposed.** `ServiceCollection.BuildServiceProvider()` returns a disposable `ServiceProvider`. If not disposed, singleton services with disposable dependencies leak. Fix: wrap in `using` or dispose in fixture `Dispose()`.

- **IsNullOrEmpty vs IsNullOrWhiteSpace inconsistency across guard checks.** When multiple files implement the same guard pattern, they must use the same string check. Prefer `IsNullOrWhiteSpace` for env-var and user-input gates.

- **Error/fixture message referencing wrong context.** When an error message directs the user to a script/file/command, verify the referenced path applies to the current context. Greppable: extract file paths from exception messages in diff, verify each exists and applies.

**Language-specific additions** (delegated to per-language instructions):

- **C# (.NET / Razor):** see `csharp.instructions.md` *Recurring code smells* for the catalog of patterns to grep beyond the universal patterns above.

### 2.6 §3.1 Comment audit evidence gate

Run the §3.1 comment-audit evidence gate before the multi-model panel (step 3). The audit happens BEFORE the diff is shown, matching §3.1's "Mandatory self-review pass before showing diff" rule. Procedural detail of WHEN/HOW comments may be added lives in `comment-protocol.md`; this step records the OUTCOME.

**Note on scope**: this evidence gate is chat audit output - NOT §3.1-governed source-code comments. §3.1's hygiene rules apply to comments IN source code; this audit produces a structured report ABOUT those comments. The two never collide.

**MANDATORY OUTPUT REQUIREMENT.** Same discipline as step 2.5: no silent skip. Emit before showing the diff:

```
parent_sha: <git rev-parse HEAD>
commit_subject: <proposed commit subject>
Comment audit: scope=<files in diff>, <N> new-or-substantively-rewritten comment lines in diff, <J> approved, <E> exempt, <DG> degraded-mode-drop, <NR> no-response-drop, <D> deleted.
- <file:line>: approval_turn: <ask_user turn/message ref> | allowed-case: <non-obvious invariant | external constraint | trade-off> | justification: <one-line text>
- <file:line>: approval_turn: n/a - exempt: <category from comment-protocol.md canonical 6 (typo | deletion | stale-comment-fix-per-§3.9/§3.10 | generated | vendored | THROWAWAY-header)>
- <file:line>: approval_turn: n/a - degraded-mode-drop
- <file:line>: approval_turn: n/a - no-response-drop
- <file:line>: deleted (per protocol step-3 rejection or rename-first resolution)
- (one bullet per NEW or substantively-rewritten comment line in the diff)
- Zero-count justification: "scope <files> has 0 new comments per `git diff --unified=0 <base>..HEAD` filtered for added comment syntax (`//`, `#`, `/*`, `<!--`, `--`, `<#`, `;`, `///`, `"""`) by file extension (per `comment-protocol.md` §Scope)" (or equivalent language-specific pattern).
```

**Fail-closed semantics.** Every bullet MUST have a valid `approval_turn:` value - one of: **(i)** a real `ask_user` turn/message ref with paired `allowed-case`, **(ii)** `n/a - exempt: <category>` where `<category>` is from `comment-protocol.md`'s canonical 6, **(iii)** `n/a - degraded-mode-drop`, **(iv)** `n/a - no-response-drop`, or **(v)** `deleted (per protocol step-3 rejection or rename-first resolution)`. Any bullet failing this - missing `approval_turn:`, citing an exempt category not in the canonical 6, or citing an unknown `n/a - <reason>` - fails the gate and blocks `git add` per `review-workflow-gates-sweeps.md` §2B (the `comment-audit-§3.1` ledger row emits `failed - <site list>`). The `parent_sha:` and `commit_subject:` header lines are REQUIRED - `pr-gate-check.yml` uses `parent_sha:` to detect stale audit files (audit written for commit X but commit Y was actually made).

**Persisted audit file (HARD GATE on adopted repos; SKIP on non-adopted repos).** The §2.6 audit block is written to `.github/pr-quality-gate/audits/last.md` ONLY when the consuming repo has adopted the audit-file workflow (see `comment-protocol.md` §Persisted audit file - adoption gate: at least one of `.github/workflows/pr-gate-check.yml`, `scripts/check-comment-audit.ps1`, or pre-existing audit file in main). On **adopted repos**: stage the file alongside the source change in every commit (`git add .github/pr-quality-gate/audits/last.md` - never `git add .` per AGENTS.md §0). The file MUST be present in every commit including no-comment/meta-change commits (use the zero-count template); failure to stage it = failure of this step, blocks `git add`. On **non-adopted repos**: DO NOT create the audit file; tracking happens inline via `comment_audit` block in `PRE-COMMIT GATE PASSED` (per `pre-commit.md`).

**Throwaway-marker exception** (per `design-exploration.md` / `performance-comparison.md`): canonical `THROWAWAY: <prototype-name>` header on a comment-capable file under `prototypes/<name>/` -> record as `approval_turn: n/a - exempt: THROWAWAY-header`.

### 2.7 Per-rule acknowledgement (POST-CODE-CHANGE LEDGER block)

Emit a `POST-CODE-CHANGE LEDGER` block in the current turn BEFORE proceeding to step 3 (panel) or `git add`. This is the post-code-change equivalent of the pre-commit `core_rules_acknowledged` requirement. **Schema and verification semantics are canonical in `review-workflow-gates-sweeps.md` §2B** - that section defines all gate-row formats (`touched-file-LPA`, `intent-driven-testing-audit`, `delta-g-sweeps`, etc.).

**Chat emission**: use the compressed KV v1 form per `review-workflow-gates-sweeps.md` §2B "Chat-emission form". The `pre-impl-trigger-detections`, `pre-impl-playbook-decisions`, and `playbook-invocations` sub-blocks stay in their existing structured form below the KV line (catalog rules parse their dot-paths). The `delta-g-sweeps` sites appendix and `comment-audit` per-site appendix are emitted in chat only when their count>0 (on adopted repos the audit file holds the full detail). Canonical/full form (below) is written to the audit file on adopted repos:

```
POST-CODE-CHANGE LEDGER
  files_changed: [<list of relative paths with brief change description>]
  shown_diff_matches_intent: yes | no
  self_similarity_sweep: clean | <list of sibling sites + dispositions>
  tests_run: <result summary or n/a>
  # ... plus every gate row from review-workflow-gates-sweeps.md §2B
  core_rules_acknowledged:
    - slug: <string>
      status: <applied | not-applicable>
      evidence:
        per_site_citations: [...]
        diff_metric_check: <cross-reference>
      rationale: <≤30 words; required when status=not-applicable>
  rule_coverage_passed: <bool>
```

**Worked example** (chat KV v1 emission; canonical compressed rendering of the block above):

```
POST-CODE-CHANGE LEDGER (KV v1)
core|commit="Guard against null tag list in filter dropdown"|files=2(+31/-6)
gates|hygiene=ran|lpa=na:no-visibility-delta|vsa=na:no-placement-change|emdash=clean|recurring=ran:0|priorpr=ran:3/0|dry=ran:1/1/0|panel=ran:unanimous:r2|itd=prospective|delta-g=ran:4/0|comment=na:no-comments-touched|build=pass|tests=pass:247/247|diff=yes:t41|msg=approved:t42
appendix=none
```

Here `appendix=none` is valid because `delta-g` sites (the value after `/`) and `comment` failed-sites are both 0. When either is >0, `appendix=none` is INVALID (§2B rule 6): emit the canonical structured `delta-g-sweeps` site sub-block + `comment` failed-site bullets (from the schema above) in its place, NOT pipe-compressed. The `pre-impl-trigger-detections`/`pre-impl-playbook-decisions`/`playbook-invocations` sub-blocks always follow in their structured form.

**Catalog rule cross-references**: `least-privilege-audit-required-on-visibility-delta` (HIGH) checks `touched-file-LPA` field when diff has a visibility delta; `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH) checks `intent-driven-testing-audit` field when diff has test files OR any production-source SUT modification (new exported member, signature change, new conditional branch, new method declaration public OR private, new error-handling branch). Private-only SUT branches DO trigger the ITD rule. See `pr-quality-gate/pattern-catalog.md` for full audit methods.

The pre-commit gate (step 4 in `pre-commit.md`) consumes `core_rules_acknowledged` and re-validates against the staged diff before commit. The two emissions can differ if the agent edits between post-code-change and pre-commit; the pre-commit version is authoritative.

### 3. Multi-model reviewer panel (via `multi-model-review.md`)

Run the panel via `multi-model-review.md` with these invocation parameters:

- **target**: `diff` (staged or branch-vs-base).
- **convergence-model**: `unanimous` (default for post-code-change; do not relax without explicit user direction).
- **max-loop**: 5.
- **prior-round-findings sharing**: enabled.
- **reviewer count + model selection**: default per the active profile (full = 6-reviewer slate; lite = 3 cross-family light-tier) from `multi-model-review/intake.md` (tier -> model via `current-model-registry.md`):
  - `heavy-claude-xhigh` (Claude, extra-high reasoning) - `code-review`.
  - `heavy-gpt-premium` (GPT, premium reasoning) - `code-review`.
  - `heavy-gpt-codex` (GPT, codex-tuned) - `code-review`.
  - `heavy-gpt-cross-version` (GPT, cross-version) - `code-review`.
  - `heavy-gemini-premium` (Gemini, premium reasoning) - `code-review`.
  - **rubber-duck** at `heavy-claude-standard` (critique angle complementing line-level review).
  Add reviewers liberally for risky/cross-cutting/unfamiliar-area changes.
- **critique focus areas** - see *Anti-anchoring focus areas* below.

Panel procedure (parallel launch, synthesis, loop-vs-escalate, evidence-gate output) lives in `multi-model-review/procedure.md` + `multi-model-review/evidence-gate-spec.md`. Do not duplicate here.

### 4. Anti-anchoring focus areas to pass to the panel

Instruct reviewers to treat the description of the fix as a hypothesis and independently read affected types and call sites.

Specific reviewer-prompt requirements (from recurring failure modes):

- **State predicates** (see `AGENTS.md` §3.7): if diff introduces a predicate over a type's state, reviewer must open that type's source and enumerate every member before accepting the predicate as complete.
- **Cross-boundary parameter/property names** (see `AGENTS.md` §3.6): if diff introduces or renames a parameter crossing an interface/implementation boundary, reviewer must enumerate every signature in the chain and verify the name is identical at every layer.
- **Literals-in-collections** (see `AGENTS.md` §3.10): if diff adds/modifies a collection whose members reflect literals used elsewhere, reviewer must open every site producing those literals and verify each references the collection's members.
- **Public surface additions** (see `least-privilege-audit.md`): if diff adds a new `public`/exported type or member, reviewer must verify a real cross-asm consumer exists; no speculative public surface.
- **Test intent and coverage gaps** (see `AGENTS.md` §3.4 and `csharp.instructions.md`): when diff touches tests OR adds/modifies a SUT branch, reviewer runs a *two-direction* audit. Direction A - judge whether each test pins a real regression; flag tautological/mock-only/framework-testing tests. Direction B - enumerate SUT behaviors in scope, call out behaviors with no test (failure paths, boundary conditions, each branch). Missing tests = same severity as filler tests. Do NOT accept "tests pass and coverage didn't drop" as evidence. For mechanical port/decompose commits, do not demand new tests same commit but MUST surface gap list as follow-up candidate.

### 5. Done when panel converges

When `multi-model-review.md` returns CONVERGED, the multi-model hard gate is passed. Verify the cumulative log per `multi-model-review/evidence-gate-spec.md` *Verification* section (>=1 round; convergence outcome emitted; 0 unaddressed blocking findings; `subagent_ask_user_calls=0` on every round). Proceed to step 6+.

Sub-agent findings outside immediate scope are routed via `ask_user` per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule - `multi-model-review/evidence-gate-spec.md` `C2 findings audit format` is the canonical disposition format.

### 6. Verify the fix actually fixed it

The benchmark/test from `pre-implementation.md` must show the expected delta (perf) or pass (functional). If the metric didn't move, the change is a no-op - revert and re-diagnose.

**Intent-driven testing retrospective dispatch**: if the diff contains new test files OR a production SUT branch/public API delta vs the prior commit, `intent-driven-testing.md` (retrospective mode) fires as a phase sub-step - produces the Test-loop audit evidence-gate output (Direction A + Direction B gap list). Surfaces gaps as C2 follow-up candidates; does NOT fail this phase for missing tests on a mechanical-port commit. **Record the result in the POST-CODE-CHANGE LEDGER's `intent-driven-testing-audit` field** (per `review-workflow-gates-sweeps.md` §2B); the catalog rule `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH) enforces the field is populated when the trigger fires.

### 7. Run affected builds and tests

All must pass before proceeding to `pre-commit.md`. If a test fails:

- If the test is a regression caused by your change: fix it (return to step 3).
- If the test was failing before your change (pre-existing): route via `ask_user` per the *Pre-existing issues* cross-cutting rule in `AGENTS.md` §1 - never silently fix it as part of this change.

### 8. Audit before declaring done

Before reporting "ready for diff review" / "all reviewers agree" / "no remaining issues," re-read every sub-agent response and confirm every distinct finding has been routed via the canonical C2 status enum per `multi-model-review/evidence-gate-spec.md`: (a) `fixed` (citation: file:line), (b) `routed-now` (citation: `ask_user` call ref + decision summary), (c) `routed-deferred` (citation: external record - session-todo id / issue URL), or (d) `dismissed-source-grounded` (citation: source location refuting the finding). Emit the C2 audit output with `subagent_ask_user_calls=0` confirmation. If any finding is in none of the four C2 buckets, stop and route it via `ask_user` first.

## Next phase

Once builds + tests + reviewer consensus + verification all clear, proceed to `pre-commit.md`.
