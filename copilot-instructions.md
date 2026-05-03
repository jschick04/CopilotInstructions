# Copilot Instructions

> **READ FIRST:** Before responding to any code-change request, re-read the "Mandatory Workflow for Code Changes" section below. Do not skip it.

---

## 1. Mandatory Workflow for Code Changes

Apply to ANY code change (no exceptions for "small" changes). Each step is required, not optional. If you believe a change is too trivial to warrant the cycle, ASK before skipping.

1. **Verify the diagnosis first.** Treat any root-cause claim from a prior agent, plan, report, bug, or user prompt as a **hypothesis**. Read the implicated code and confirm the mechanism behaves as described **before** designing a fix.
   - **Perf work:** identify (or write) a benchmark or test that measurably captures the regression. If that number wouldn't move after the proposed fix, the diagnosis is wrong — stop and re-investigate. No fix without a number that changes.
   - **Bug fixes:** write a failing test that reproduces the bug first. If you can't reproduce it, the bug isn't understood yet.
   - **Cleanup of ad-hoc benchmarks/tests:** any benchmark or test created **solely to validate a diagnosis or fix** must be removed before the change is reported complete, unless the user explicitly asks to keep it. Capture the resulting numbers in the task summary or commit body so the evidence is preserved without leaving throwaway code in the tree.

2. **Rubber-duck the plan** with the **rubber-duck** agent before implementing. Always include in the prompt: *"Is the named root cause actually true? Verify against the source before evaluating the fix."* Address findings or explicitly justify dismissal.

3. **Implement.** Then run the **code-review** agent on the diff with the default model. Iterate until clean.
   - **Sort and clean up imports/usings on every touched file before sending the diff for review.** This is a mandatory hygiene step on any file you've added, modified, or moved — sort imports/usings into the project's canonical order and remove unused ones. Use the language's ecosystem tooling for the whole touched set in one pass (e.g., `dotnet format --severity info --diagnostics IDE0005 IDE0065` for .NET unused/misplaced usings + a sort pass; `eslint --fix` plus the editor's "Organize Imports" for TS/JS; `ruff check --select I --fix` or `isort` for Python; IntelliJ "Optimize Imports" for Java/Kotlin). Never commit a file with unsorted, duplicated, or unused imports — reviewers always flag them, and the noise hides real issues in the diff.

4. **Multi-model agreement.** Re-run the **code-review** agent on the same diff with at least one model from a different family (default is Claude Opus → also run with `model: "gpt-5.5"` or `gpt-5.3-codex`). Iterate, re-running every model after each fix round, until **all models agree** with no substantive findings. Briefly summarize cross-model agreement before declaring ready.
   - **Do not anchor reviewers on your own framing.** Prompts must instruct the reviewer to treat the description of the fix as a hypothesis and independently read the affected types and call sites. If the diff introduces a predicate over a type's state (see 3.7), the reviewer must open that type's source and enumerate every member before accepting the predicate as complete. If the diff introduces or renames a parameter that crosses an interface/implementation boundary (see 3.6), the reviewer must enumerate every signature in the chain — interface, abstract base, every implementation, every caller, every lambda that closes over it — and verify the name is identical at every layer. If the diff adds or modifies a collection whose members reflect literals used elsewhere in the codebase (see 3.10), the reviewer must open every site that produces those literals and verify each one references the collection's members rather than re-typing the literal.

5. **Verify the fix actually fixed it.** The benchmark/test from step 1 must show the expected delta (perf) or pass (functional). If the metric didn't move, the change is a no-op — revert and re-diagnose.

6. **Run affected builds and tests.** All must pass before proceeding.

7. **Show the diff to the user and wait for explicit approval.** Do not commit before approval.
   - **Ask who commits.** When presenting the diff, ask whether the user will handle the commit/push or wants you to. Default to the user committing — many of their workflows involve manual review, splitting, or amending before push.

8. **Commit.** Stage only touched files (`git add <path>` — never `git add .`). Use a single-line message per the *Commit Messages* rules below.

9. **Post-commit comment pass — scope = entire branch vs base.** Immediately after every commit (including comment-hygiene commits themselves — they exit the loop when the pass finds nothing), enumerate every NEW or MODIFIED `//`, `///`, and `/* */` comment in `git --no-pager diff <base>..HEAD` (typically `origin/main..HEAD`) and apply the rules in section 3.1 — especially the **rename-first protocol** (every comment must first be tested by asking *"can a better name on the function/parameter/variable/type carry this fact?"* — if yes, rename and delete the comment). Hard-prohibited categories (XML doc on private members, restating the code, "why we're about to do this" narration, multi-line design-decision prose, future-tense forecasting, TODO/FIXME/HACK) must be deleted on sight. The audit step from rule 3.1 ("write a one-line justification matching one of the 3 allowed cases — if you can't, delete it") is non-skippable.
   - **Why branch-scope, not just the just-committed diff:** comments that survived prior commits' reviews under weaker rules — or that drifted as surrounding code evolved across the branch — never get a second look without this sweep. Doing it after every commit catches drift in small increments (one commit's worth of new comments + any prior-commit residue surfaced by the rename pass) instead of compounding into hundreds-to-a-thousand new lines at PR-open time.
   - **Pre-existing comments already in `<base>`: out of scope** unless this branch also touched the surrounding code; in that case re-evaluate them too.
   - **If the pass finds anything to change**, those edits become their own commit cycle (workflow steps 1–9 again, but the "diagnosis" is comment hygiene — skip steps 1, 2, 4, and the per-commit verification of step 5; do still run step 3's import-sort hygiene, step 6 build/test, step 7 diff approval, and step 8 commit). Use a single-line commit message describing the hygiene scope (e.g., `Drop restating-code comments from upgrade pipeline`, `Rename _flag → _hasOpenedRecoveryDialog and drop comment`).
   - **If the pass finds nothing**, the branch is clean for the next feature commit (or for PR open); record that in the session and move on.

10. **After a PR exists,** run the **pr-review** agent and iterate the same multi-model way (step 4).
    - **Verify each bot finding against the source before applying it.** GitHub Copilot's PR reviewer (and any external reviewer) is sometimes wrong — it lacks full context, can hallucinate symbol behavior, or propose fixes that would obviously break callers. For each comment: read the cited code and the surrounding context, then either (a) apply the fix, (b) push back with a one-line justification on the PR thread and resolve the comment as "won't fix", or (c) ask the user when ambiguous. Do not silently apply changes you cannot independently justify.
    - **Propose an instructions-file delta after each fix.** Once a PR comment is resolved, briefly identify what could be added to `~/.copilot/copilot-instructions.md` to catch the same class of issue earlier (in self-review or by the multi-model code-review pass). If something fits, propose the delta in your summary. Skip silently if the comment is genuinely one-off (typo, taste, etc.).
    - **Instructions-file additions must stay project-agnostic.** `~/.copilot/copilot-instructions.md` applies to *every* project the user works on. Any rule, example, code snippet, type name, field name, file path, error message, or "examples that bit us" anecdote you add must be generic — describe the *class* of issue and the *shape* of the fix without naming a real project's symbols, modules, table names, schemas, or domain concepts. Use illustrative placeholder names (`UserSessionCache`, `customerName`, `LoggingMiddleware`) or describe the structure abstractly ("a composite key over `(LocalId, SubId)`"). When you catch yourself about to write a real type name from the current repo, rename it. Same applies to the rubber-duck or code-review prompts you're proposing as templates — strip project specifics before promoting them into the instructions file.

11. **Pre-existing issues:** if you find one that could be or is causing an issue, ask whether to resolve it now. Otherwise add a TODO comment so it can be picked up later.
    - **This includes findings surfaced by sub-agents** (rubber-duck, code-review, etc.) that are tangentially related but **outside the current task or PR scope**. Do NOT silently expand scope to fix them, and do NOT silently drop them. Briefly summarize each finding (1 line each), state your recommendation, and use `ask_user` to choose: address now in this change, defer to a follow-up (you create a TODO or note), or dismiss with reason.
    - **`ask_user` is mandatory, not optional.** Mentioning a sub-agent finding inside your final review summary, the diff walkthrough, the "ready to commit" message, or any other prose without a paired `ask_user` call counts as silently dropping it. Even findings the reviewer itself labels "out of scope," "pre-existing," "not introduced by this change," or "low severity" must go through `ask_user` — those labels are the reviewer's opinion, not your decision to make on the user's behalf. The user owns scope decisions; you surface and they choose.
    - **Audit step before declaring ready.** Immediately before saying any variant of "ready to commit" / "all reviewers agree" / "no remaining issues," re-read every sub-agent response from this task and confirm that every distinct finding (regardless of severity or scope label) has either (a) been fixed in the diff, or (b) been routed through an `ask_user` call this turn. If any finding is in neither bucket, stop and route it through `ask_user` first.

12. **Unintended reverts:** if you see code that was removed, refactored, or renamed that differs from a previous change you made, ASK before reverting.

13. **Do NOT report the task complete** until steps 1–9 are satisfied (style/trivia excepted).

---

## 2. Commit Messages

- **Single line only.** No body, no footers, no trailers of any kind.
- **Explicitly suppress the auto-injected `Co-authored-by: Copilot` trailer.** When invoking `git commit`, use `-m "<message>"` only — do not pass any additional `-m` flags, do not let any tool append a trailer, and do not add a blank line followed by `Co-authored-by:`. The commit message body must contain the single line and nothing else.
- **Describe what the change does**, not which plan item it implements. No `A2`, `(A2)`, plan section numbers, or Conventional-Commit prefixes (`perf:`, `fix:`, `feat:`, etc.).
- **Imperative mood, no trailing period.**

Examples:
- ✅ `Defer TagsDisplayName join until first read`
- ✅ `Add IsEnabled guard to LoggingMiddleware before serializing actions`
- ❌ `perf: defer TagsDisplayName join (A2)`
- ❌ `A2 - lazy tags`
- ❌ Any message followed by `Co-authored-by:` or any other trailer.

---

## 3. General Coding Standards

These standards apply to **every** code change, in every language. They are non-negotiable; reviewers should reject PRs that violate them.

### 3.1 Comments

**This rule is enforced strictly. Over-commenting is the most common style violation across past PRs — assume the reviewer will reject any comment that is not load-bearing. The default answer to "should I add a comment here?" is NO.**

- **Default: no comments.** Code is the primary documentation. Names carry intent. If you find yourself wanting to write a comment, first try renaming the variable/method or extracting a well-named helper.
- **Rename-first protocol (mandatory).** *Every* time you reach for a comment because "the code isn't clear" / "the reader won't know what this does" / "this is subtle," your **first** action is to read the surrounding identifier(s) — function, parameter, variable, type, field — and ask: *"Can a better name carry this fact?"* If yes, rename and drop the comment. Only if no rename can express the fact (genuinely external constraint, true non-obvious algorithmic invariant, or a deliberate trade-off the reader would otherwise question) is the comment allowed — and it still has to pass the hard length caps below. Examples: a comment that says "this method does X for Y reason" almost always means the method name should describe X-for-Y; a comment that says "this flag is true when Z" means the flag should be named `IsZ` or `HasZ`. Do this rename pass on **every** new comment you write, not just ones that feel borderline.
- **Hard prohibitions** (do not commit any of these — no exceptions):
  - **No XML doc comments (`/// <summary>...`) on `private` members.** Period. Not on private fields, not on private methods, not on private nested types. The XML-doc-on-private-field is the most common violation. If the field needs explanation, the *name* needs work.
  - **No comments that restate the code.** `// Bump counter` next to `_counter++`, `// Set flag to true` next to `_flag = true`, `// Loop over items` next to `foreach (var item in items)` — all forbidden. Same applies to XML docs that restate the method signature: `/// <summary>Copies text to the clipboard.</summary>` on `Task CopyTextAsync(string text)` says nothing the signature doesn't.
  - **No "why we're about to do this" narration.** `// We need to clear the buffer here so that...` — if the reason is obvious from the next line, drop the comment; if it isn't, the next line probably needs a better name or a small refactor.
  - **No multi-line `//` blocks explaining a design decision in prose.** That belongs in the PR description, the commit message, or (if it's a true invariant) a *single short* line.
  - **No speculation about future callers, future surfaces, or "this will be used by X later."** Code comments describe what the code IS, not what's coming. Examples to never write: `// callers (banner copy-details, filter export, future surfaces) are typically fire-and-forget`, `// the future BannerHost will need this`, `// once we add Y this will also handle Z`. Future-tense forecasting belongs in the PR description.
  - **No restating contract terms that are already encoded in naming or signature.** `Task CopyTextAsync(string text)` already says async + returns Task + takes a string. Don't add a comment that says "Copies text asynchronously."
  - **No "TODO" / "FIXME" / "HACK" / "XXX" comments.** Use the workflow's "ask user to defer or fix now" path (rule 1.10) instead.
- **Allowed** (rare, and only when ALL three apply: short, load-bearing, not inferable):
  - A non-obvious algorithmic invariant (e.g., `// k-merge requires inputs already sorted by Timestamp ascending`).
  - A workaround for an external constraint (e.g., `// Win32: LoadLibraryEx with DATAFILE flag still maps writable on <Win10`).
  - A deliberate trade-off the reader would otherwise question (e.g., `// Monitor lock — ConcurrentDictionary lost on this benchmark`).
- **Hard length caps:**
  - Inline `//` comments: **one line, ≤ 12 words.** If you can't fit the load-bearing fact in 12 words, the surrounding code needs a better name or a helper extraction — not a longer comment.
  - XML `<summary>` on public/internal members: **one sentence.** No paragraphs. No `<para>`. No bullet lists. If the contract takes more than a sentence, the API is doing too much — split the method.
  - XML `<param>` / `<returns>` / `<exception>`: **one short clause each, only when the param/return/exception name doesn't carry it.**
- **XML doc comments on NEW public/internal API: default OFF.** Only add when the type/method signature genuinely cannot express the contract — e.g., a non-obvious failure mode (`/// <returns>true on success; false if the OS denied the request — caller must surface to the user.</returns>`), or a non-obvious thread-safety guarantee. Method names like `TryGet…` / `…Async` / `Copy…` already encode their contract. Do NOT preemptively document "for future maintainers" — the signature IS the doc.
- **Existing XML doc comments stay** — don't reformat or expand them when touching surrounding code.
- **Mandatory self-review pass before showing diff:** enumerate every NEW comment line and every NEW XML doc in the diff. For each one, write a one-line justification matching one of the 3 allowed cases above ("non-obvious invariant: X" / "external constraint: Y" / "trade-off: Z"). **If you cannot write that justification in one short clause, delete the comment.** This audit is non-skippable — running it sometimes catches 100% of the violations the reviewer would have flagged.
- **Remove existing stale comments** that no longer add value when touching surrounding code. Don't preserve old narration just because it was there before.

**Common failure modes flagged in past reviews:**
- Adding `/// <summary>` to a private field "to explain the race-handling design." Wrong — rename the field or, if a single short line truly is needed, use a single `// ` above the field.
- Adding `// Only commit if we're still the most recent load.` above an `if (gen == _gen)` check. The check + name says it. Delete the comment.
- Adding `// Bump generation so an in-flight Refresh skips its commit` above `_gen++` in a Dispose path. The dispose context + a well-named field carry it. Delete.
- Adding a 3-line XML `<summary>` paragraph on a new public interface explaining "implementations are best-effort, any failure is logged and swallowed so callers can fire-and-forget." This is contract prose that belongs in the PR description; the method signature + a `Task` return + the implementation's try/catch already say it. If "best-effort" really must be in the doc, write `/// <summary>Best-effort copy; failures are logged and swallowed.</summary>` — one sentence.
- Adding `// Same best-effort contract as CopySelectedEvent: callers (banner copy-details, filter export, future surfaces) are typically fire-and-forget UI handlers.` above a try/catch around a clipboard call. Triple violation: speculation about future callers + restating-what-the-code-does + multi-clause prose. Delete the entire comment — the try/catch + the log message ARE the contract.

### 3.2 Naming — clarity over brevity

- Use **descriptive, full-word names**.
  - ✅ `userSessionCache`, `customerName`, `combinedRecords`
  - ❌ `cache`, `cn`, `cr`, `ctx` (don't abbreviate `context`), `tmp`, `data2`
- **Lambdas:** full names unless the parameter is **immediately and unambiguously** clear from the operation. When in doubt, use the full name.
  - ✅ `orders.Where(order => order.Status == OrderStatus.Open)`
  - ✅ `bytes.Sum(b => b.Length)` — single-letter is fine in a tight, obvious scope
  - ❌ `orders.Where(o => o.Status == OrderStatus.Open && (o.Region == "X" || o.Channel == "Y"))` — scope is big enough to deserve `order`
- **Method names:** verb-phrase that describes the *outcome*, not the implementation.
  - ✅ `MergeSortedRecordsIntoCombinedView`, `TryGetCachedErrorMessage`
  - ❌ `Process`, `DoWork`, `Handle`
- Avoid noise prefixes/suffixes (`Helper`, `Manager`, `Util`) unless the type genuinely is one.

### 3.3 When naming is ambiguous → ask first

If, while implementing, a name is not obviously correct or there are two or more reasonable choices that meaningfully differ in intent, **stop and present 2–4 options to the user via `ask_user`** with a one-line rationale per option. Do not invent a name and proceed.

Cases that warrant the ask:
- A new cache type that could be named after its key, its value, or its consumer (`UserSessionCache` vs `LoginTokenCache` vs `AuthRequestCache`).
- A new helper method whose name could imply a stronger or weaker contract (`TryGetMessage` vs `GetMessageOrNull` vs `LookupMessage`).
- A flag whose polarity matters (`IsLazy` vs `IsEager`, `RebuildAlways` vs `RebuildOnChange`).
- A model property where the prior name disagrees with the new behavior (e.g., renaming `TagsDisplayName` to better reflect that it is now lazy / on-demand — options: `TagsDisplayText`, `TagsJoined`, `FormattedTags`, leave-as-is-with-doc-comment).

When choices clearly differ only in style (and not in intent), pick one and move on — do not over-ask.

### 3.4 Tests and Benchmarks

- Tests and benchmarks follow all the standards above (no abbreviations, descriptive names, no narrative comments).
- **Test method names** are full sentences describing the scenario and expectation: `GetCustomer_WhenCaseDiffers_FindsExistingCustomer`.
- **Benchmark class and method names** match the production symbol they exercise: `UserSessionCacheBenchmarks.Lookup_HotCode_NoAllocation`.
- **Avoid `DateTime.Now` and `DateTime.UtcNow`** — they introduce non-deterministic behavior and timezone dependencies. Use fixed deterministic timestamps such as `new DateTime(2024, 1, 1, 12, 0, 0, DateTimeKind.Utc)` so tests are reproducible regardless of when or where they run.
- **Add or update unit tests** to cover new code and edge cases. Follow existing testing patterns in the codebase.
- **Test project layout — `TestUtils` folder convention.** Every test project in this repo uses a `TestUtils/` folder for shared test infrastructure:
  - Reusable helper classes (factories, fakes, builders, IO/HTTP/compression helpers) live directly under `TestUtils/` as `<Topic>Utils.cs` (e.g., `EventUtils.cs`, `FilterUtils.cs`, `HttpUtils.cs`, `DeploymentUtils.cs`).
  - Shared constants live under `TestUtils/Constants/` as topic-grouped partial-class files named `Constants.<Topic>.cs` (e.g., `Constants.Provider.cs`, `Constants.Resolver.cs`, `Constants.Database.cs`, `Constants.Filter.cs`).
  - Each constants file declares `public sealed partial class Constants` in namespace `<Project>.Tests.TestUtils.Constants` and exposes `public const string` (or other const) members. Tests reference them via `Constants.Foo`.
  - Each test project has its own `TestUtils/` (do not share across projects).
- **Extract duplicated test values into the shared `TestUtils/Constants` location.** When the same non-trivial literal (provider names, task/keyword/message names, descriptions, parameter values, template fragments like `"<template></template>"`, log names, paths) appears in two or more tests — whether in the same file or across files — add it to the appropriate `Constants.<Topic>.cs` partial (creating a new topic file if none fits) and reference via `Constants.Foo`. **Do NOT declare per-test-class `private const` blocks at the top of test files** — keep test files focused on test logic so values are discoverable and reusable by future tests. Trivial values (empty string, single characters, well-known sentinels like `"main"`) and strings that genuinely must differ between tests are exempt.

### 3.5 Performance

- Consider performance implications of every change.
- Avoid unnecessary allocations, prefer efficient algorithms, and use appropriate data structures.

### 3.6 Defaults and Consistency

- **When in doubt, follow Microsoft naming standards and best practices** for the language in question (C#, C++, JavaScript/TypeScript, HTML, CSS). The language-specific sections below codify these.
- **When Microsoft guidance and the existing code in a touched file disagree, prioritize consistency with the existing code in that file.** Don't reformat or rename surrounding code just to match the standard.
- **Comprehensive over sampled.** When the user asks for a review, scan, audit, sweep, or "look across all X" of any noun (sessions, files, PRs, callers, tests), default to **complete coverage** — enumerate the full set first, then process every item. Do not pick a representative subset on your own. If the set is genuinely too large to process in full (cost, time, context budget), surface that explicitly via `ask_user` with the count and propose a sampling strategy *before* starting. "I read 9 of the ~80 sessions" is a failure mode the user will catch every time.
- **Search-first for renames and refactors.** Before declaring any rename, signature change, or moved symbol complete, run a full-repo grep for the old identifier across **every** relevant file type — including `*.razor`, `*.razor.cs`, `*.cshtml`, `*.json`, JSON converter switch cases, `*.xaml`, test projects, doc comments, and trace/log strings. Report "0 matches" before declaring done. "I missed a consumer" is the most common post-refactor regression and almost always means the grep wasn't wide enough.
- **Parameter / property names must be consistent across the entire interface chain — not just at the top-level call site.** When introducing or renaming a parameter (especially boolean) that flows through `interface → implementation → caller → lambda capture`, pick the name **once** and apply it from the implementation up to every call site. The most common failure mode: the top-level handler gets the new "good" name, but the interface signature, the impl method signatures, the lambda parameters, and any private helper methods still show a draft/older name. This is greppable, but only if you grep — before declaring done, list every layer (interface, abstract base, every implementation, every caller, every lambda that closes over the argument) and verify the parameter name is identical across all of them. If you renamed a parameter mid-edit, that is also the moment to rerun the rename across the whole chain. Reviewers always spot the mismatch because they read the interface and the impl together; so should you.
- **Confirm the user-facing surface before non-trivial implementation.** For any change that introduces or modifies a user-visible surface — new commands, new CLI flags, new menu items, new API endpoints, new file formats, new public types, new dialog flows — sketch that surface (names, signatures, file boundaries, defaults) and confirm via `ask_user` **before** starting implementation, not after. Building the wrong shape and then re-cutting it costs more than asking. Pure internal refactors and bug fixes are exempt.
- **Match existing structural patterns when introducing new types.** Before creating a new interface, abstract class, exception, model, record, or service, look at how *sibling* types of the same role are organized in the project being edited and mirror that. Things to mirror, not invent:
  - **File layout for interfaces.** Some projects put every interface in a dedicated `Interfaces/` folder and its own file; others co-locate the interface with its sole production implementation in the same file (often `public interface IFoo` immediately above `public sealed class Foo : IFoo`); others put both in a feature folder. Find the dominant pattern for the kind of type you're adding (DI seam vs broader contract) and follow it. If both patterns are in use, prefer the one used by the closest-in-purpose neighbors (a new DI seam should look like the other DI seams, a new contract type should look like the other contract types).
  - **Folder/namespace by role.** Models, options, services, exceptions, abstract bases, etc. each tend to have a dedicated folder/namespace. Place new types in the matching one — do not invent a new folder when a fitting one already exists.
  - **Class shape.** Sealed-with-primary-constructor vs explicit constructor + readonly fields, `partial` only when source generators require it, abstract base classes only where a base-class hierarchy already exists. Match what neighbors do.
  - **Suffixes and prefixes.** `XxxBase` for abstract bases, `XxxService` / `XxxProvider` / `XxxRepository` / `XxxOptions` etc. — use the suffix the project already uses for that role, do not introduce a new vocabulary.
  - **Exposed surface.** If sibling services use NSubstitute-friendly interface seams, do the same; if they expose a sealed concrete with no interface, follow that. Don't add an interface "just in case" if the project's pattern is concrete-only.
  When two reasonable patterns coexist and the choice materially affects the contract or test surface, ask via `ask_user` rather than picking unilaterally. Surveying sibling files takes a minute and prevents a multi-file rewrite during review.

### 3.7 State predicates and emptiness checks

A "state predicate" is any boolean over a type's fields/properties that means *"this object is empty / equal / fully populated / cleared / serialized / matches X"*. These are notorious for missing fields when new members get added later or when the author only thinks about a subset of the type.

- **Encapsulate state predicates on the type that owns the state.** When you find yourself writing `x.A == 0 && x.B == 0 && !x.C.Any()` from outside the type, add the predicate as a member on the type itself (e.g., `IsEmpty`, `IsDefault`). This forces you to look at *every* field and naturally surfaces ones you'd otherwise miss. A multi-clause boolean over fields of a single type, written from outside that type, should be treated as a refactor smell.
- **Field-completeness justification.** When introducing or modifying any state predicate, enumerate **every** member of the type and justify (in your head, in the PR description, or in a doc comment on the predicate) why each member is included or excluded. "I forgot about it" is the failure mode this rule exists to prevent.
- **Reviewer enforcement.** When sending a diff to the rubber-duck or code-review agent that introduces such a predicate, name the type explicitly in the prompt and require the reviewer to enumerate its members independently. Do not summarize the predicate's scope — let the reviewer derive it from the source.
- **Match / equality predicates need enough fields to be unique in the domain.** A predicate that says *"these two records refer to the same thing"* must include every field required to disambiguate them in the broadest realistic context. Common failure modes: a composite key over `(LocalId, SubId)` collides once the records cross their original container — the source/owner field needs to be in the key too; an `IsEmpty` predicate over a few "obviously content-bearing" collections silently returns `true` for objects whose data lives in the *other* collections the author didn't think about. When in doubt, ask: *"could two domain-distinct objects compare equal under this predicate?"* If yes, it is incomplete.

### 3.8 Defer state mutations until after success

When an operation can fail (throws, returns false, awaits a JS call that may not return, etc.), do not record success-implying state until the operation has actually succeeded. This is one of the most common classes of bug flagged by PR review.

- **Membership / dedup sets** (`seen.Add(x)`, `_processed[id] = true`): perform the work first, then record membership. If the work throws, the next attempt should retry, not skip.
- **Registration / initialization flags** (`_registered = true`, `_initialized = true`, `_jsRefAssigned = true`): set only after the underlying call (JS interop, native handle acquisition, network registration) returns successfully.
- **Cache writes**: insert into the cache only on the success path; do not write a partially-populated entry that other callers may read.
- **Don't cache high-cardinality strings.** Before passing a value to a string-interning cache (`ConcurrentDictionary<string, string>`, `GetOrAdd...`, `Intern`), confirm the value comes from a small, bounded set. Strings built by concatenating per-record fields (timestamps, IDs, paths, user input, payload data) are effectively unique per call and will grow the cache without bound. If a code path produces both canned and per-record variants from the same builder, split the cache call so only the canned branch is interned and the per-record branch returns directly.
- **Error state on success**: on the success path, explicitly clear any prior error fields (`LastErrorCode`, `LastException`, `_warningShown`). A successful run should leave no stale failure breadcrumbs.
- **Idempotency-first ref handoff**: when a method is idempotent (early-returns if already done), assign the long-lived reference (`DotNetObjectReference`, native handle, subscription token) **before** the early-return guard, not after — otherwise the second caller sees `null` and the first caller's reference leaks on dispose.

### 3.9 Async, disposal, and JS interop lifecycle (Blazor / .NET)

These patterns recur in every Blazor + JS-interop PR review. Apply them whenever touching a `.razor.cs`, `IJSRuntime`, `DotNetObjectReference`, `IAsyncDisposable`, or any fire-and-forget async path.

- **`Lazy<Task<T>>` caches fault forever.** If the task throws, the same faulted task is handed to every future caller. Never use `Lazy<Task<T>>` for a cache that must be retryable. Prefer an explicit "produce-then-cache-on-success" pattern that re-runs on failure.
- **`DotNetObjectReference` ownership**: whichever object creates the reference owns disposing it. If you hand it to JS, dispose it in the same scope's tear-down (`DisposeAsync` / `UnregisterAsync`). Do not let it dangle when the component re-renders.
- **Narrow catches around JS interop.** Catch `JSDisconnectedException` and `TaskCanceledException` (and `OperationCanceledException`) specifically — never a bare `catch` or `catch (Exception)`. The first two are expected during teardown / circuit loss; everything else is a real bug and must surface.
- **`AbortController` for JS event listeners.** When wiring `addEventListener` from .NET, pair it with an `AbortController` (or symmetric `removeEventListener`) so listeners detach when the component disposes. Otherwise the page leaks listeners across navigation.
- **Fire-and-forget must be deliberate.** `_ = SomeAsync()` is acceptable only when (a) the call is idempotent or has its own error handling, and (b) you've added `.ConfigureAwait(false)` and a `.catch(...)` / try-catch that logs. Plain `SomeAsync();` without `await` and without a discard is a bug — Copilot reviewer flags it on sight.
- **`invokeMethodAsync` from JS needs `.catch(() => {})`** at minimum (preferably with logging) — otherwise a disconnected circuit produces an unhandled promise rejection in the browser.
- **`DisposeAsync` vs domain-specific tear-down.** If a service has a meaningful "stop using me but stay alive" operation (e.g., `UnregisterAsync`, `CloseAsync`), do not collapse it into `DisposeAsync`. `DisposeAsync` is for terminal cleanup; the domain method is for revocable lifecycle.
- **`[Parameter]` properties are framework-owned — never mutate them.** Compute a derived value or copy into a local field; do not assign to a `[Parameter]` from `OnParametersSetAsync`, `OnInitialized`, or any handler. Blazor will overwrite your value on the next render and the bug surfaces as "value snaps back".

### 3.10 Recurring code smells from past PR reviews

Treat each of these as a hard-stop during self-review and as an explicit thing to look for during the multi-model code-review pass.

- **Constants — single source of truth.** Any literal that constrains a contract (page size, max-in-clause parameter count, default cache size, retention window, file size limit, magic timeout) lives in exactly one named constant. Duplicates across files **will** drift. If the same number appears in two places, extract it before the diff is reviewable.
- **A "list of X" collection must reference the same constants used by the code that produces X — not duplicate the literals.** When you create or maintain a collection whose purpose is to *describe* a hardcoded set elsewhere (a "well-known names" set, an "always-shown columns" list, a "system-known schemas" registry, an "allowed origins" array, a "hardcoded menu items" filter), and another file builds those same items by writing the literals directly, the collection silently goes out of sync the moment someone adds, removes, or renames an item at either site. Extract the literals to named constants in one place, have the collection initializer reference the constants, AND have the hardcoded site reference the same constants — never literals on either side. The collection's existence is itself the signal that the literals are a contract; leaving the literals at one of the two sites defeats the collection's entire purpose. When you encounter this pattern in a diff (yours or someone else's), fix both sites in the same change.
- **Sibling-constant consistency.** When you add or modify one of a *group* of related constants (default error messages, status labels, retry counts in a tier, timeouts per stage), look at its siblings in the same declaration block and verify formatting/punctuation/casing/units are consistent. Trailing-period-on-one-of-three-strings, `"OK"` vs `"Ok"` vs `"Okay"`, `5000` vs `5_000` — reviewers always spot these because they read sibling constants together. So should you.
- **Test specificity.** Assert exact values, never `Arg.Any<T>()` / `It.IsAny<T>()` / `Mock.Of<T>()` matchers, when the test's purpose is to verify *what was passed*. `Arg.Any<T>()` is appropriate only when the test's contract genuinely doesn't care about the argument (rare). Prefer `Arg.Is<T>(x => x.Property == expected)` or capture-and-assert.
- **Negative assertions are weak when the contract is "exact value Y".** `Assert.DoesNotContain(forbidden, actual)` / `Assert.NotEqual(forbidden, actual)` pass for `null`, empty string, exception messages, and any random value — including when the code under test broke entirely and returned the wrong answer. Use them only when the contract genuinely is *"X must not be the result"* (e.g., regression tests for "this leaked secret never appears in the rendered output"). When the test's purpose is *"the fallback path produces Y"*, assert `Y` exactly with `Assert.Equal(expectedFallback, actual)`. Same energy as the `Arg.Any<T>()` rule above — assert the contract, not its absence.
- **Don't materialize streams unnecessarily.** `.ToList()` / `.ToArray()` inside a method that just iterates once is a wasted allocation and a smell that the author is hiding a re-enumeration bug behind it. Materialize only when (a) the result is consumed multiple times, (b) you need indexed access, or (c) you're crossing a boundary that requires a concrete collection. Same goes for eager LINQ in hot paths (`.Where(...).Count()` instead of `.Any()` / `.Count(predicate)`).
- **Lambda parameter shadowing.** Do not name a lambda parameter the same as an in-scope variable (`var filter = ...; filters.Where(filter => filter.X)`). The compiler accepts it; reviewers and humans misread it. Rename the lambda parameter to something distinct.
- **Failure paths must surface user-visible feedback (UI code).** When a `TryCreate`/`TryParse`/parsing operation returns `null`/`false` on the user-action path, do not silently no-op. Show a dialog (`AlertDialogService.ShowAlert`), surface a validation message, or log at warning level — whichever matches the surface. Silent failures are the #1 bug source flagged in UI PRs.
- **Comment / path hygiene.** Never commit a `TODO`, `FIXME`, debug `Console.WriteLine`, or absolute path that references your local machine (`C:\Users\<you>\...`, `Q:\Projects\...`, your Downloads folder). Strip these in self-review before showing the diff.
- **Idempotency / multi-dispatcher guards.** When you add a "have I done this already?" guard to one code path (`if (_done) return;`, `ImmutableDictionary.Add` → `TryAdd`), grep for every other code path that mutates the same state and add the guard there too. Reviewers consistently catch the second/third dispatcher that was missed.
- **Exception messages must stay diagnostic.** When you remove or change a parameter that previously fed an exception's message (computer name, file path, key, etc.), do not collapse the call to `string.Empty` or a bare type name. Replace it with whatever diagnostic context the catch site or log will actually need — typically the resource path, key, or operation that was attempted. Empty `Exception.Message` values are unrecoverable in production logs.
- **Native interop return-value validation — audit while you're there.** Whenever you touch a Win32 / P/Invoke call site, validate every native return value that can be `IntPtr.Zero` / `NULL` / `INVALID_HANDLE_VALUE` for the *entire* sequence in that block — not just the one you came to fix. `LoadResource`, `LockResource`, `LoadLibraryEx`, `OpenProcess`, `CreateFile`, `RegOpenKeyEx`, `FindResourceEx`, etc. all return failure sentinels that, if dereferenced (`Marshal.ReadInt32`, `Marshal.PtrToStructure`, `Marshal.PtrToStringUni`), crash the process. PR reviewers always read the surrounding native sequence; do the same in self-review and add `if (handle == IntPtr.Zero) { log; continue/return; }` guards before any Marshal read.
- **Log messages must match the actually-taken code path.** When you add an early return, guard, or branch *between* a "we're about to do X" log and the code that does X, the log becomes a lie. Either move the log past the guards (so it only fires when X actually happens), or split into per-branch logs that name what really occurred ("Skipping fallback because input is rooted" vs "Falling back with leaf name 'foo.dll'"). Unconditional "Falling back to..." / "Retrying..." / "Loading..." messages that fire before a guard suppresses the action are the most common log-vs-behavior mismatch reviewers catch.
- **Log messages must match what the code actually returns.** A log that says "Returning null" / "No result" / "Failed to load" when the surrounding method actually returns a non-null empty/sentinel value (or vice versa) is a stale-text bug that reviewers always catch. When you change a method's return contract (null → empty collection, throw → return false, optional → required), grep every log line in that method for words describing the old contract and update them.
- **Test portability — no hardcoded system paths or locales.** Tests that touch the filesystem, registry, or system binaries must not hardcode `C:\Windows`, `C:\Program Files`, `\System32\en-US\`, drive letters, or specific UI culture folder names. Use `Environment.GetFolderPath(SpecialFolder.Windows / .System / .ProgramFiles)`, `Environment.SystemDirectory`, `CultureInfo.CurrentUICulture`, or probe the available locale subfolders. `Assert.SkipUnless` is fine as a gate, but the *path you build* must adapt to the host. Same applies to environment variables that may not exist in CI.
- **`Path.IsPathRooted` is not enough when reducing to a leaf name.** If your fallback path strips a file path down to its leaf via `Path.GetFileName(file)` and then resolves it against the OS search order (`LoadLibraryEx`, `Process.Start`, `File.Open`, etc.), guarding only with `Path.IsPathRooted` lets relative-but-qualified inputs like `"subdir\foo.dll"` slip through — the directory portion is silently dropped and a *different* same-named binary on the search path can be loaded, producing wrong results that look correct. Whenever you call `Path.GetFileName(x)` to *replace* `x`, gate the fallback with `string.Equals(x, Path.GetFileName(x), StringComparison.Ordinal)` (or equivalent: assert the input has no directory separators) so only true bare leaf names are rewritten. This applies to any path-reducing fallback, not just `LoadLibraryEx`.
- **No dead branches inside loops with the same termination condition.** When a loop's continuation condition already excludes some state (e.g., `while (!string.IsNullOrEmpty(culture.Name))`), an inner `if (state) break;` that fires on the *same* state is dead code — the loop would have terminated next iteration regardless. Either tighten the loop condition to express the full intent, or drop the redundant inner break. Reviewers (human and bot) consistently flag the redundancy and it implies the author hasn't traced the loop's exit conditions end-to-end. The corollary: when adding such an inner break, ask whether the loop condition already covers it; if yes, the break is the wrong fix.
- **Bare `LoadLibraryEx`/`Process.Start`/`CreateFile` on a leaf name is a DLL-planting / wrong-binary risk.** When *any* fallback path resolves a bare filename through the OS default search order (which includes the application directory first), an attacker — or just an unrelated same-named binary on `PATH` — can be loaded instead of the system one you intended. Two acceptable fixes: (a) build a full path via `Path.Combine(Environment.SystemDirectory, leafName)` (or another trusted root) and `File.Exists`-gate before loading, or (b) pass `LOAD_LIBRARY_SEARCH_SYSTEM32` / `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS` (after `SetDefaultDllDirectories`). Never hand a leaf name to `LoadLibraryEx` with `LOAD_LIBRARY_AS_DATAFILE` alone, even for "data only" loads — the system can still map the wrong file and you'll happily read its bytes. This applies to `Process.Start("foo.exe")`, `File.Open("config.json")` from a working directory you don't control, and similar.
- **Brittle exact `Received(N)` counts on log/diagnostic mocks.** Asserting `mockLogger.Received(4).Debug(...)` couples the test to the *current* number of fallback / retry / fix-up steps. The next person who adds a diagnostic log or tightens a fallback gate (legitimate code change) breaks the test for no behavioral reason. For diagnostic / log mocks, prefer one of: (a) `Received(N)` with a content matcher tied to *exactly the contract* you mean to verify, where `N` is derived from the input shape (e.g., `inputs.Length`) and the matcher asserts a substring tied to the contract (e.g., a key phrase plus the input's identifier); (b) `Received().Debug(...)` (at-least-once) when only presence matters. The exact-count rule from 3.10 ("Test specificity") still applies to *behavioral* assertions on argument values — this is its log/diagnostic counterpart: assert the *contract*, not the *current implementation's verbosity*.
- **🚨 CRITICAL — `nameof()` for code symbols inside ANY string, production OR test — mandatory.** This rule has been violated repeatedly; treat every string literal in a diff as suspect until you've confirmed it isn't a symbol name. Any string that embeds the name of a type, method, property, field, parameter, local variable, or enum member MUST use `nameof(...)` (or, when shorter, a member-access form like `nameof(MyClass.Method)`) instead of a hardcoded literal. Pick whichever form is **more compact** at the call site — the goal is rename-safety, not a specific syntax. `nameof()` is a compile-time constant (zero runtime cost) and survives renames; hardcoded names silently rot when the symbol is renamed and the next reader sees a string that names something that no longer exists. **Self-review checklist before declaring any change ready: grep your diff for double-quoted strings and ask of each one — "is this value or is this a name?" If it's a name, it must be `nameof()`.**
    - Log messages: `_logger.Error($"{nameof(FooService)}.{nameof(DoWork)}: failed: {ex}")` — never `$"FooService.DoWork: failed: {ex}"`.
    - `ArgumentNullException` / `ArgumentException` / `ObjectDisposedException` constructors: `nameof(parameter)` / `nameof(MyClass)`.
    - Property-changed and other reflection-style notifications.
    - Exception messages that reference a method or parameter: `throw new InvalidOperationException($"{nameof(Initialize)} must be called first.")`.
    - When you genuinely need both the class name and the method name in one string, prefix with `nameof(EnclosingClass)` once and `nameof(MethodName)` for the method — do not concatenate hardcoded segments with `nameof` segments (a future rename of just the class leaves the string half-stale).
    - **Tests asserting on `ex.ParamName`, `ex.Message`, or log-message content MUST also use `nameof()`.** `Assert.Equal("actionLabel", ex.ParamName)` rots when the production parameter is renamed but the test isn't. The fix pattern when the parameter belongs to *another* type (so a direct `nameof(SomeClass.SomeMethod.actionLabel)` isn't expressible): introduce a local variable with the **same name as the production parameter**, pass it via a **named argument** (`actionLabel: actionLabel`), and assert with `nameof(actionLabel)`. The named-argument call site fails to compile if production renames, prompting the local rename, which propagates to `nameof()` automatically. Same pattern for log substring checks: `h.ToString().Contains(nameof(MyClass))` is rename-safe; `h.ToString().Contains("MyClass")` is not. Sentence-fragment substrings (`Contains("action threw")`) that happen to appear in a log are acceptable only when no symbol is involved — and even then, prefer asserting on a paired symbol (`nameof(MyClass)`) for the rename-safe portion of the contract.
    - **NSubstitute `Received(...).MethodName(...)` calls are already rename-safe** (the method group is a real symbol). But string arguments inside `Arg.Is<T>(x => x.Property == "literal")` matchers are NOT rename-safe if the literal is a property name — use `nameof(MyType.Property)`.
  Exempt: user-facing UI strings (localized/static), serialization keys / JSON property names / SQL column names that intentionally don't track the C# identifier, configuration keys, log category names that are part of an external contract, **and freeform sentence fragments in log messages that aren't symbol names** (e.g., `"connection lost"`, `"retry exhausted"`). When in doubt, prefer `nameof` — it costs nothing and the worst case is a tiny readability hit.

---

## 4. C# / .NET Code Style

### 4.1 Naming Conventions (Microsoft .NET Guidelines)

- **Interfaces:** prefix with `I`, PascalCase (`IUserRepository`).
- **Types** (classes, structs, enums): PascalCase (`UserRepositoryBase`).
- **Public/Internal/Protected members** (properties, methods, events): PascalCase (`GetUser`).
- **Private instance fields:** `_camelCase` (`_logger`, `_cache`).
- **Private static fields:** `s_camelCase` (`s_defaultOptions`).
- **Thread-static fields:** `t_camelCase`.
- **Const fields (class-level):** PascalCase (`DefaultTimeout`).
- **Public/Internal fields:** PascalCase (`CustomerDetails`) — but prefer properties over public fields.
- **Protected fields:** avoid; use protected properties to maintain encapsulation for derived classes.
- **Parameters and local variables:** camelCase (`userRecord`, `returnValue`).
- **Local constants:** camelCase, same as local variables (`maxRetryCount`).
- **Type parameters:** prefix with `T`, PascalCase (`TResult`).
- **Abbreviations:**
  - Two-letter acronyms: UPPERCASE (`IO`, `ID`, `DB`).
  - Three+ letter acronyms: PascalCase (`Xml`, `Json`, `Html`).
  - In camelCase context: `userId`, `xmlParser`, `htmlContent`.

### 4.2 Code Formatting

- 4 spaces for indentation (no tabs).
- File-scoped namespaces.
- Opening braces on new lines (Allman style).
- Use `var` only when the type is evident from the right-hand side.
- Use expression-bodied members when applicable (methods, properties, accessors, constructors, local functions).
- Require braces for `if`, `for`, `foreach`, `while` statements.
- No `this.` qualification unless necessary.
- Use language keywords over BCL types (`string` not `String`).
- Modifier order: `public, private, protected, internal, file, static, extern, new, virtual, abstract, sealed, override, readonly, unsafe, required, volatile, async`.
- Max 1 blank line between declarations and inside code blocks.
- Place `while` on a new line in `do-while` statements.
- Insert a final newline in every file.
- Namespace must match folder structure.

### 4.3 Member Ordering (StyleCop Layout)

1. Constants
2. Static fields
3. Instance fields
4. Constructors and destructors
5. Delegates
6. Events (public first, then interface implementations, then others)
7. Enums
8. Interfaces
9. Properties (public first, then interface implementations, then others)
10. Indexers
11. Methods (public first, then interface implementations, then others)
12. Operators
13. Nested structs
14. Nested classes

### 4.4 Expression Preferences

- Prefer pattern matching over `as`/`is` with null checks.
- Prefer null propagation (`?.`) and coalesce (`??`) operators.
- Prefer object/collection initializers.
- Prefer conditional expressions for simple assignments/returns.
- Prefer switch expressions over switch statements.
- Prefer the `not` pattern (e.g., `is not null`).
- Prefer extended property patterns.
- Prefer `is null` over `ReferenceEquals`.
- Prefer explicit tuple names over `Item1`, `Item2`.
- Prefer inferred tuple and anonymous type member names.
- Prefer simplified boolean expressions.
- Prefer simplified interpolation.
- Prefer auto-properties.
- Prefer compound assignment (`+=`, `-=`, etc.).
- Prefer index operator (`^1`) and range operator (`..`).
- Prefer local functions over anonymous functions.
- Prefer method group conversion.
- Prefer simple `default` expression (`default` not `default(T)`).
- Prefer deconstructed variable declarations.
- Prefer target-typed `new()` when type is evident.
- Prefer inline variable declarations (`out var`).
- Prefer tuple swap.
- Prefer UTF-8 string literals where applicable.
- Prefer throw expressions.
- Use discards for unused values.

### 4.5 Code Block Preferences

- Prefer simple `using` statements (without braces) when possible.
- Prefer top-level statements for `Program.cs`.
- Prefer static local functions when not capturing variables.
- Use the conditional delegate call (`?.Invoke()`).

### 4.6 Field, Parameter, and Modifier Preferences

- Mark fields as `readonly` when possible.
- Treat unused parameters as warnings (do not silently leave them).
- Always specify accessibility modifiers (except for interface members).

### 4.7 Parentheses

- Use parentheses for clarity in arithmetic, binary, and relational operators.
- Omit parentheses only when obviously unnecessary.

### 4.8 Using Directives

- Place `using` directives **outside** the namespace.
- Don't separate import groups.
- Don't prioritize System directives first.

### 4.9 Concurrency Primitives

- **Lock fields: prefer `System.Threading.Lock` (.NET 9+) over `object`.** When a field exists solely to be the target of a `lock` statement, declare it as `private readonly Lock _stateLock = new();` rather than `private readonly object _stateLock = new();`.
  - The `Lock` type uses an internal optimized fast path; the C# 13 compiler recognizes it as the target of a `lock` statement and emits `EnterScope()` / `LockScope.Dispose()` IL instead of `Monitor.Enter` / `Monitor.Exit`. This is measurably faster on hot paths and removes the object header lock-word dependency.
  - The `Lock` type also enforces type-safety: `Lock` instances cannot be accidentally used as general-purpose objects (e.g., passed to `Monitor.Enter` directly, or used as a dictionary key meaningfully). `object`-typed lock fields silently allow these mistakes.
- **Lock syntax: prefer the `lock (lockField) { ... }` keyword over explicit `using (lockField.EnterScope()) { ... }`.** When `lockField` is typed `Lock`, the compiler emits identical IL for both forms, so the keyword form is the more concise and idiomatic choice. Reserve `EnterScope()` for cases where you actually need a `LockScope` value (e.g., conditional acquire stored in a variable for later release).
- **Mutator-side lock + reader-side lock + event-outside-lock** is the standard pattern for a thread-safe service that exposes state via properties and raises change notifications:
  ```csharp
  private readonly Lock _stateLock = new();
  private SomeImmutableState _state = SomeImmutableState.Empty;

  public IReadOnlyList<TItem> Items
  {
      get { lock (_stateLock) { return _state.Items; } }
  }

  public event Action? StateChanged;

  public void Mutate(...)
  {
      lock (_stateLock) { _state = _state.With(...); }
      StateChanged?.Invoke(); // outside the lock to avoid handler re-entrancy deadlocks
  }
  ```
  Property getters MUST acquire the lock — single-field reads are atomic for references, but cross-field reads from the outside can otherwise observe inconsistent snapshots. Raising the change event under the lock is a common bug source: handlers that read properties (and therefore re-acquire the lock) will deadlock if the lock is non-reentrant, and even with a reentrant lock the handler runs while the mutator's logical operation is incomplete.

### 4.10 Null-forgiving operator (`!`) — avoid

- **Do not use the `!` (null-forgiving / "damn-it") operator to silence nullable warnings.** It tells the compiler "trust me" without doing the work to actually prove the value is non-null at the use site. If the assumption is wrong (or becomes wrong after a refactor), the result is a `NullReferenceException` at runtime instead of a compile-time error — exactly the class of bug nullable reference types exist to prevent.
- **Do the actual work to make the value non-null.** In order of preference:
  - **Restructure to remove the nullable**: change a method signature, model field, or carrier type so the value cannot be null at the call site. Examples: parameter typed `Foo` instead of `Foo?`; split a state union so the "has-value" arm carries a non-nullable; surface the value through a constructor instead of a settable property.
  - **Pattern-match into a non-null local with `is { }`** at the narrowest scope that needs it: `if (value is { } nonNull) { ... use nonNull ... }`. Inside the block, `nonNull` is the non-nullable type, including across lambda captures.
  - **`when` clause on a `case` label**: `case Foo when value is { } nonNull:` narrows in the case body and is captured cleanly by lambdas inside that body. This is often the cleanest fix in `switch`/Razor `@switch` blocks where one arm semantically requires a value to be present.
  - **Early-return / early-break narrowing**: `if (value is null) { return; }` then continue with `value` (now narrowed) for non-lambda uses. Note: lambdas capture the *original* nullable type, so for a lambda that needs the value, prefer one of the patterns above OR copy into an explicitly-typed non-nullable local first (`Foo nonNull = value;` after the null check).
  - **Throw with a meaningful message** when reaching the use site without a value is genuinely a contract violation: `var nonNull = value ?? throw new InvalidOperationException("Foo must be set before BarAsync runs.");`. The thrown exception has to name what's missing and why it's required.
- **Particularly avoid sprinkling `!` inconsistently across multiple uses of the same value** (e.g., `@x!.A` followed by `@x.B` in Razor markup, or `x!.Method()` followed by `x.Property` in C#). Either narrow once for the whole scope or change the type.
- **Reviewer enforcement**: when reviewing a diff that contains `!`, ask whether the suppressor could be replaced with one of the patterns above. Only accept `!` after that question has been answered with a specific reason (typically: "this is the absolute last layer of the API and the contract is enforced by upstream tests"). "It compiles" is not a reason.

---

## 5. C++ Code Style

### 5.1 Naming Conventions (Microsoft C++ Guidelines)

- **Classes and structs:** PascalCase (`UserRepository`, `CustomerData`).
- **Interfaces:** prefix with `I`, PascalCase (`IRequestHandler`).
- **Functions and methods:** PascalCase (`ProcessRequest`, `GetValue`).
- **Public member variables:** PascalCase (`CustomerId`, `CustomerName`).
- **Private/protected member variables:** `m_` prefix with camelCase (`m_requestCount`, `m_isInitialized`).
- **Static member variables:** `s_` prefix with camelCase (`s_instanceCount`).
- **Global variables:** `g_` prefix with camelCase (`g_configuration`).
- **Constants and macros:** SCREAMING_SNAKE_CASE (`MAX_BUFFER_SIZE`, `DEFAULT_TIMEOUT`).
- **Enums:** PascalCase for type, PascalCase for values (`enum class LogLevel { Info, Warning, Error }`).
- **Namespaces:** PascalCase (`MyApp::Core`).
- **Template parameters:** prefix with `T`, PascalCase (`TResult`, `TAllocator`).
- **Parameters and local variables:** camelCase (`userRecord`, `bufferSize`).
- **Typedefs and using aliases:** PascalCase (`using RequestList = std::vector<Request>`).

### 5.2 Code Formatting

- 4 spaces for indentation (no tabs).
- Opening braces on new lines (Allman style).
- Require braces for `if`, `for`, `while`, `do-while` statements.
- Use `#pragma once` for header guards.
- Sort `#include` directives: standard library first, then third-party, then project headers.
- Use `nullptr` instead of `NULL` or `0`.
- Use `auto` when type is evident from initialization.
- Prefer `enum class` over plain `enum`.
- Use `const` and `constexpr` where applicable.
- Max 1 blank line between declarations.
- Insert a final newline in every file.

### 5.3 Member Ordering

1. Public types (nested classes, enums, typedefs)
2. Public static members
3. Public constructors and destructor
4. Public methods
5. Public member variables (prefer accessors)
6. Protected members (same order as public)
7. Private members (same order as public)

---

## 6. JavaScript / TypeScript Code Style

### 6.1 Naming Conventions

- **Classes:** PascalCase (`UserRepository`, `DataProvider`).
- **Interfaces:** PascalCase, do **NOT** prefix with `I` (`RequestHandler`, `Config`).
- **Type aliases:** PascalCase (`UserList`, `CallbackFn`).
- **Enums:** PascalCase for type and values (`LogLevel.Info`).
- **Functions and methods:** camelCase (`processRequest`, `getValue`).
- **Properties and variables:** camelCase (`userCount`, `isEnabled`).
- **Constants:** SCREAMING_SNAKE_CASE for true constants, camelCase for `const` variables (`MAX_RETRIES` vs `const userName`).
- **Private members:** prefix with `_` (`_internalState`) or use `#` for true private fields.
- **Parameters:** camelCase (`userRecord`, `callbackFn`).
- **Type parameters:** prefix with `T`, PascalCase (`TResult`, `TItem`).
- **File names:** camelCase or kebab-case (`userRepository.ts` or `user-repository.ts`).
- **Abbreviations:** same as C# — two-letter uppercase, three+ letter PascalCase.

### 6.2 Code Formatting

- 4 spaces for indentation (no tabs).
- Opening braces on the same line (K&R style).
- Require braces for `if`, `for`, `while` statements.
- Use single quotes for strings (or template literals).
- Always use semicolons.
- Use `const` by default, `let` when reassignment is needed, never `var`.
- Prefer arrow functions for callbacks.
- Use strict equality (`===` and `!==`).
- Max 1 blank line between declarations.
- Insert a final newline in every file.
- Max line length: 120 characters.

### 6.3 Expression Preferences

- Prefer template literals over string concatenation.
- Prefer destructuring for objects and arrays.
- Prefer the spread operator over `Object.assign` or `Array.concat`.
- Prefer `async/await` over raw Promises.
- Prefer optional chaining (`?.`) and nullish coalescing (`??`).
- Prefer object shorthand properties.
- Prefer arrow functions for inline callbacks.
- Use `Array.map`, `filter`, `reduce` over manual loops when appropriate.

### 6.4 Imports / Exports

- Use ES6 `import`/`export` syntax.
- Group imports: external packages first, then internal modules.
- Prefer named exports over default exports.
- Sort imports alphabetically within groups.

---

## 7. HTML Code Style

### 7.1 Formatting

- 4 spaces for indentation (no tabs).
- Lowercase for element names and attributes.
- Always use double quotes for attribute values.
- Include the `lang` attribute on `<html>`.
- Include a `charset` meta tag.
- Close all elements (use `/>` for self-closing in XHTML, or omit the slash in HTML5).
- Insert a final newline in every file.

### 7.2 Attribute Ordering (Recommended)

1. `class`
2. `id`, `name`
3. `data-*` attributes
4. `src`, `href`, `for`, `type`, `value`
5. `title`, `alt`
6. `role`, `aria-*`
7. Other attributes

### 7.3 Best Practices

- Use semantic elements (`<header>`, `<nav>`, `<main>`, `<article>`, `<section>`, `<footer>`).
- Include appropriate ARIA attributes for accessibility.
- Keep inline styles to a minimum; prefer CSS classes.
- Use meaningful `id` and `class` names (kebab-case: `item-list`, `header-nav`).
- Validate HTML structure.
- Place `<script>` tags at end of `<body>` or use `defer` / `async` attributes.

---

## 8. CSS Code Style

### 8.1 Naming Conventions

- Use kebab-case for class names (`item-list`, `header-navigation`).
- Use BEM methodology when appropriate (`block__element--modifier`).
- Avoid ID selectors for styling; prefer classes.
- Use meaningful, descriptive names.

### 8.2 Formatting

- 4 spaces for indentation (no tabs).
- Opening brace on the same line as the selector.
- One property per line.
- Space after the colon in declarations.
- End all declarations with a semicolon.
- Separate rule sets with a blank line.
- Insert a final newline in every file.

### 8.3 Property Ordering (Recommended)

1. Positioning (`position`, `top`, `right`, `bottom`, `left`, `z-index`)
2. Box model (`display`, `flex`, `grid`, `width`, `height`, `margin`, `padding`, `border`)
3. Typography (`font`, `line-height`, `text-align`, `color`)
4. Visual (`background`, `box-shadow`, `opacity`)
5. Animation (`transition`, `animation`)
6. Misc (`cursor`, `overflow`)
