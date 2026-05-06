# Copilot Instructions — Core

<!-- CopilotInstructions: SENTINEL core -->

> **READ FIRST:** Before responding to any code-change request, re-read the "Mandatory Workflow for Code Changes" section below. Do not skip it.

This is the always-loaded core. Language-specific guidance (C#/.NET, C++, JS/TS, HTML, CSS) lives in topic files under `.github/instructions/` and loads conditionally based on the files in your working set. See [Topic-specific files](#topic-specific-files) at the bottom for the routing table.

---

## 1. Mandatory Workflow for Code Changes

Apply to ANY code change (no exceptions for "small" changes). Each step is required, not optional. If you believe a change is too trivial to warrant the cycle, ASK before skipping.

1. **Verify the diagnosis first.** Treat any root-cause claim from a prior agent, plan, report, bug, or user prompt as a **hypothesis**. Read the implicated code and confirm the mechanism behaves as described **before** designing a fix.
   - **Perf work:** identify (or write) a benchmark or test that measurably captures the regression. If that number wouldn't move after the proposed fix, the diagnosis is wrong — stop and re-investigate. No fix without a number that changes.
   - **Bug fixes:** write a failing test that reproduces the bug first. If you can't reproduce it, the bug isn't understood yet.
   - **Cleanup of ad-hoc benchmarks/tests:** any benchmark or test created **solely to validate a diagnosis or fix** must be removed before the change is reported complete, unless the user explicitly asks to keep it. Capture the resulting numbers in the task summary or commit body so the evidence is preserved without leaving throwaway code in the tree.

2. **Rubber-duck the plan** with the **rubber-duck** agent before implementing. Always include in the prompt: *"Is the named root cause actually true? Verify against the source before evaluating the fix."* Address findings or explicitly justify dismissal.

3. **Implement.** Then proceed to the multi-model review in step 4 — do NOT do a separate single-model code-review pass first; that would be a serial review and contradicts the "never serialize" rule below.
   - **Sort and clean up imports/usings on every touched file before sending the diff for review.** This is a mandatory hygiene step on any file you've added, modified, or moved — sort imports/usings into the project's canonical order and remove unused ones. Use the language's ecosystem tooling for the whole touched set in one pass (e.g., `dotnet format --severity info --diagnostics IDE0005 IDE0065` for .NET unused/misplaced usings + a sort pass; `eslint --fix` plus the editor's "Organize Imports" for TS/JS; `ruff check --select I --fix` or `isort` for Python; IntelliJ "Optimize Imports" for Java/Kotlin). Never commit a file with unsorted, duplicated, or unused imports — reviewers always flag them, and the noise hides real issues in the diff.

4. **Multi-model agreement — run all reviewers in parallel, no token-limit concerns.** The user has no token budget caps, so always launch the full reviewer panel in parallel (background agents) rather than serially. Iterate, re-running the panel after each fix round, until **all models agree** with no substantive findings. Briefly summarize cross-model agreement before declaring ready.
   - **Default reviewer panel** (launch all of these as background agents in the **same response** — three as `code-review`, one as `rubber-duck`; at least one model from each family):
     - `claude-opus-4.7-xhigh` (default Claude family, extra-high reasoning) — `code-review`
     - `gpt-5.5` (OpenAI family, premium reasoning) — `code-review`
     - `gpt-5.3-codex` (OpenAI family, codex-tuned — different perspective from gpt-5.5) — `code-review`
     - **rubber-duck** agent (independent critique angle — not a code-review reviewer per se, but provides design/blind-spot feedback that complements line-level review)
   - **Add reviewers liberally** when a change is risky, cross-cutting, or touches an unfamiliar area: `claude-sonnet-4.6` for a faster second-Claude opinion, `gpt-5.5` re-run with a different prompt framing, etc. There is no "too many reviewers" — parallel agents are cheap and the marginal cost of one more independent reading is approximately zero.
   - **Do NOT serialize the panel** ("run Claude first, then if it finds nothing run GPT") — that wastes wall-clock time and lets early reviewer framing leak into your assessment of later reviews. Launch all reviewers in one tool-call batch, wait for completions, then synthesize.
   - **Do not anchor reviewers on your own framing.** Prompts must instruct the reviewer to treat the description of the fix as a hypothesis and independently read the affected types and call sites. If the diff introduces a predicate over a type's state (see [Core / State predicates and emptiness checks](#37-state-predicates-and-emptiness-checks)), the reviewer must open that type's source and enumerate every member before accepting the predicate as complete. If the diff introduces or renames a parameter that crosses an interface/implementation boundary (see [Core / Defaults and Consistency](#36-defaults-and-consistency)), the reviewer must enumerate every signature in the chain — interface, abstract base, every implementation, every caller, every lambda that closes over it — and verify the name is identical at every layer. If the diff adds or modifies a collection whose members reflect literals used elsewhere in the codebase (see [Core / Recurring code smells](#310-recurring-code-smells-from-past-pr-reviews)), the reviewer must open every site that produces those literals and verify each one references the collection's members rather than re-typing the literal.
   - **Same parallel-panel rule applies to PR reviews** (workflow rule 10 below): when running `pr-review` after a PR exists, launch the same panel in parallel.

5. **Verify the fix actually fixed it.** The benchmark/test from step 1 must show the expected delta (perf) or pass (functional). If the metric didn't move, the change is a no-op — revert and re-diagnose.

6. **Run affected builds and tests.** All must pass before proceeding.

7. **Show the diff to the user and wait for explicit approval.** Do not commit before approval.
   - **Ask who commits.** When presenting the diff, ask whether the user will handle the commit/push or wants you to. Default to the user committing — many of their workflows involve manual review, splitting, or amending before push.

8. **Commit.** Stage only touched files (`git add <path>` — never `git add .`). Use a single-line message per the *Commit Messages* rules below.

9. **Pre-PR-push comment pass — runs once on the assembled branch, before the first push intended for review** (PR-opening, request-for-review, or pushing to a shared branch others may pull from). Scope is the entire branch vs base (`git --no-pager diff <base>..HEAD`, typically `origin/main..HEAD`). Enumerate every NEW or MODIFIED `//`, `///`, and `/* */` comment and apply the rules in [Core / Comments](#31-comments) (and, when C# files are touched, the additional XML-doc rules in `csharp.instructions.md`) — especially the **rename-first protocol** (every comment must first be tested by asking *"can a better name on the function/parameter/variable/type carry this fact?"* — if yes, rename and delete the comment). Hard-prohibited categories (restating the code, "why we're about to do this" narration, multi-line design-decision prose, future-tense forecasting, TODO/FIXME/HACK — plus, in C#, XML doc on private members per `csharp.instructions.md`) must be deleted on sight. The audit step from the Comments rule ("write a one-line justification matching one of the 3 allowed cases — if you can't, delete it") is non-skippable.
   - **Why the branch-wide sweep happens pre-push:** comments compound across many WIP commits; running the branch-wide rename-first sweep once on the assembled branch produces a clean surface for reviewers from turn one and avoids tagging every commit with its own hygiene amend. Per-commit hygiene also burned context re-evaluating comments that prior commits' reviews had already approved — folding the branch-wide sweep into one pre-push pass is cheaper. (Both passes are mandatory; this is not a choice between them — see the next bullet for the per-commit/pre-push split.)
   - **Audit scope is different per-commit vs at pre-push.** Two non-overlapping passes:
     - **Per-commit micro-hygiene (every commit):** the [Core / Comments](#31-comments) per-comment audit covers ONLY comments added or modified in **the current commit's diff**. Each must have a one-line allowed-case justification or be deleted before the diff is shown to the user. Non-skippable per commit cycle.
     - **Pre-push branch-wide sweep (once):** enumerates ALL comments added or modified in `<base>..HEAD` (across every commit on the branch) and re-applies the Comments rules — especially rename-first, which often only becomes obvious after later commits add context that earlier WIP comments don't reflect. **When this sweep runs, record the resolved base SHA, sweep HEAD SHA, and base ref name in the session** so the "out of scope at initial sweep" set can be reconstructed in later amend cycles (see "When to re-run the branch-wide sweep" rules below).
     - **Together, not interchangeable:** the pre-push sweep is for branch-wide drift and rename-first opportunities surfaced by later commits, NOT a substitute for the per-commit audit. Letting obvious violations through every commit and planning to "clean them all up at the end" fails both rules.
   - **Pre-existing comments already in `<base>`: out of scope** unless this branch also touched the surrounding code; in that case re-evaluate them too.
   - **Cleanup commit strategy** (three buckets, pick the strictest that applies):
     - **Small, no renames** (≤ a handful of touched comments, no symbol renames at all): amend it into the final work commit and run step 3's import-sort hygiene, step 6 build/test, and step 7 diff approval before pushing.
     - **Local single-scope rename** (rename stays inside one file or a small same-package cluster, does NOT cross an interface/implementation boundary, does NOT change any signature): may be amended into the final work commit, but you MUST also run a full-repo grep for the old identifier across every relevant file type per [§3.6 Defaults and Consistency](#36-defaults-and-consistency) (search-first for renames and refactors) and confirm "0 matches" before amending. **Any non-zero grep hit disqualifies this bucket — escalate to the "Large or cross-boundary" bucket below (or ask the user).** Then run step 3 / step 6 / step 7 as above.
     - **Large or cross-boundary** (spans many files OR the rename-first protocol triggered any symbol rename that crosses an interface/implementation boundary, affects a signature, or otherwise has cross-file caller implications): commit it separately and run the **full** workflow (steps 1–8) — including step 4's multi-model review, since the cross-file rename consistency questions [§3.6](#36-defaults-and-consistency) covers are exactly what step 4 catches.
     - **Commit-message examples** (apply to whichever bucket): `Drop restating-code comments from upgrade pipeline` (hygiene-only), `Rename _flag → _hasOpenedRecoveryDialog and drop comment` (rename-driven).
   - **Amend-safety invariant.** "Amend the final work commit" above assumes the branch has NOT yet been pushed (or has been pushed only to a personal sandbox no one else watches). If you've already pushed in any form that exposes the branch — a backup push to a feature branch, a draft PR push, a push to a shared branch others may pull from, or a request-for-review push — do NOT amend silently. Ask the user whether to (a) force-push the amend, (b) add a separate hygiene commit instead, or (c) defer the hygiene to the next push cycle. The pre-push pass is designed to run BEFORE the first push intended for review (PR-opening, request-for-review, or pushing to a shared branch others may pull from).
   - **If the pass finds nothing**, the branch is clean to push; record that in the session and move on.
   - **Force-push amends in response to PR review do NOT re-trigger the branch-wide sweep.** The per-comment Comments-rule audit is still non-skippable for every new comment line you add during review-response amends. **Rename-first also still applies** to any new/modified comment and its immediately surrounding identifiers — but if satisfying rename-first would widen scope beyond the immediate amend (e.g., the "better name" affects callers, an interface signature, or an implementation in another file), STOP treating it as an ordinary review-response amend. Either ask the user how to proceed, OR widen the change to cover every file in the rename chain (interface, abstract base, every implementation, every caller, every lambda that closes over the symbol — per [§3.6](#36-defaults-and-consistency)) and run the **full** workflow (steps 1–8) on that widened diff. A partial re-sweep limited to the file(s) in the immediate amend is NOT sufficient when the rename has cross-file caller implications.
   - **When to re-run the branch-wide sweep before another push:**
     - **Re-run** if you add new feature/scope work beyond the original PR scope, new files, or non-review-driven commits.
     - **Re-run** if conflict resolution from a merge/rebase added or modified comments, OR if it changed any hunk in a file that already appeared in the branch-wide comment set.
     - **Re-run** if any post-sweep change (merge, rebase, OR ordinary amend) changed code in the same hunk or immediate surrounding declaration/block/function as any pre-existing comment that was out of scope during the initial sweep — whether because the comment lives in a previously-untouched file, OR in a previously-untouched region of an already-touched file. The branch now touches the surrounding code, putting those pre-existing comments back in scope per the "out of scope unless this branch also touched the surrounding code" rule above.
       - **Definition:** "Out of scope during the initial sweep" means the comment's surrounding code does NOT appear in the diff `<sweep-base-SHA>..<sweep-HEAD-SHA>` (the resolved SHAs recorded at sweep time per the "Pre-push branch-wide sweep" step above — NOT later-resolved symbolic refs like `origin/main`, which may have advanced). Per-comment metadata is not required. **If the recorded sweep SHAs are unavailable** (older branches, operator miss, session loss), treat reconstruction as impossible and conservatively re-run the branch-wide sweep (or ask the user).
     - **Do NOT re-run** for ordinary review-response amends — provided they do NOT add new files, do NOT expand scope beyond the original PR, and do NOT meet any Re-run condition above. (Per-commit audit + rename-first on the new comment + its immediate surroundings suffices for the ordinary case.)
     - **Do NOT re-run** for a clean merge/rebase from main with no comment touches and no scope expansion.

10. **After a PR exists,** run the **pr-review** agent and iterate the same multi-model way (step 4).
    - **Verify each bot finding against the source before applying it.** GitHub Copilot's PR reviewer (and any external reviewer) is sometimes wrong — it lacks full context, can hallucinate symbol behavior, or propose fixes that would obviously break callers. For each comment: read the cited code and the surrounding context, then either (a) apply the fix, (b) push back with a one-line justification on the PR thread and resolve the comment as "won't fix", or (c) ask the user when ambiguous. Do not silently apply changes you cannot independently justify.
    - **Propose an instructions-file delta after each fix.** Once a PR comment is resolved, briefly identify what could be added to the appropriate instructions file (this `AGENTS.md` core, or the matching topic file under `.github/instructions/`) to catch the same class of issue earlier (in self-review or by the multi-model code-review pass). If something fits, propose the delta in your summary. Skip silently if the comment is genuinely one-off (typo, taste, etc.).
    - **Instructions-file additions must stay project-agnostic.** These instructions apply to *every* project the user works on. Any rule, example, code snippet, type name, field name, file path, error message, or "examples that bit us" anecdote you add must be generic — describe the *class* of issue and the *shape* of the fix without naming a real project's symbols, modules, table names, schemas, or domain concepts. Use illustrative placeholder names (`UserSessionCache`, `customerName`, `LoggingMiddleware`) or describe the structure abstractly ("a composite key over `(LocalId, SubId)`"). When you catch yourself about to write a real type name from the current repo, rename it. Same applies to the rubber-duck or code-review prompts you're proposing as templates — strip project specifics before promoting them into an instructions file.

11. **Pre-existing issues:** if you find one that could be or is causing an issue, ask whether to resolve it now. Otherwise record it as a follow-up — log it in the session, file an issue, or add it to the user's tracker. **Do NOT add a `TODO`/`FIXME`/`HACK` comment in code** (per [§3.1 Comments](#31-comments) hard prohibitions); use the user-facing escalation path described in this rule instead.
    - **This includes findings surfaced by sub-agents** (rubber-duck, code-review, etc.) that are tangentially related but **outside the current task or PR scope**. Do NOT silently expand scope to fix them, and do NOT silently drop them. Briefly summarize each finding (1 line each), state your recommendation, and use `ask_user` to choose: address now in this change, defer to a follow-up (record it externally — session note, issue, or tracker — never as a `TODO`/`FIXME`/`HACK` comment in code), or dismiss with reason.
    - **`ask_user` is mandatory, not optional.** Mentioning a sub-agent finding inside your final review summary, the diff walkthrough, the "ready to commit" message, or any other prose without a paired `ask_user` call counts as silently dropping it. Even findings the reviewer itself labels "out of scope," "pre-existing," "not introduced by this change," or "low severity" must go through `ask_user` — those labels are the reviewer's opinion, not your decision to make on the user's behalf. The user owns scope decisions; you surface and they choose.
    - **Audit step before declaring ready.** Immediately before saying any variant of "ready to commit" / "all reviewers agree" / "no remaining issues," re-read every sub-agent response from this task and confirm that every distinct finding (regardless of severity or scope label) has either (a) been fixed in the diff, or (b) been routed through an `ask_user` call this turn. If any finding is in neither bucket, stop and route it through `ask_user` first.

12. **Unintended reverts:** if you see code that was removed, refactored, or renamed that differs from a previous change you made, ASK before reverting.

13. **Do NOT report the task ready to push / ready to open the PR** until steps 1–8 have been completed for every committed work cycle AND step 9 has been run once on the final assembled branch state. (The preamble's "ASK before skipping" rule is the only escape hatch — never self-judge a change as exempt.)

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

Language-specific additions live in the topic files under `.github/instructions/`. Examples: XML-doc comment rules and `nameof()` apply only when C# files are in the working set — see `csharp.instructions.md`.

### 3.1 Comments

**This rule is enforced strictly. Over-commenting is the most common style violation across past PRs — assume the reviewer will reject any comment that is not load-bearing. The default answer to "should I add a comment here?" is NO.**

- **Default: no comments.** Code is the primary documentation. Names carry intent. If you find yourself wanting to write a comment, first try renaming the variable/method or extracting a well-named helper.
- **Rename-first protocol (mandatory).** *Every* time you reach for a comment because "the code isn't clear" / "the reader won't know what this does" / "this is subtle," your **first** action is to read the surrounding identifier(s) — function, parameter, variable, type, field — and ask: *"Can a better name carry this fact?"* If yes, rename and drop the comment. Only if no rename can express the fact (genuinely external constraint, true non-obvious algorithmic invariant, or a deliberate trade-off the reader would otherwise question) is the comment allowed — and it still has to pass the hard length caps below. Examples: a comment that says "this method does X for Y reason" almost always means the method name should describe X-for-Y; a comment that says "this flag is true when Z" means the flag should be named `IsZ` or `HasZ`. Do this rename pass on **every** new comment you write, not just ones that feel borderline.
- **Hard prohibitions** (do not commit any of these — no exceptions):
  - **No comments that restate the code.** `// Bump counter` next to `_counter++`, `// Set flag to true` next to `_flag = true`, `// Loop over items` next to `foreach (var item in items)` — all forbidden.
  - **No "why we're about to do this" narration.** `// We need to clear the buffer here so that...` — if the reason is obvious from the next line, drop the comment; if it isn't, the next line probably needs a better name or a small refactor.
  - **No multi-line `//` blocks explaining a design decision in prose.** That belongs in the PR description, the commit message, or (if it's a true invariant) a *single short* line.
  - **No speculation about future callers, future surfaces, or "this will be used by X later."** Code comments describe what the code IS, not what's coming. Examples to never write: `// callers (banner copy-details, filter export, future surfaces) are typically fire-and-forget`, `// the future BannerHost will need this`, `// once we add Y this will also handle Z`. Future-tense forecasting belongs in the PR description.
  - **No restating contract terms that are already encoded in naming or signature.** A method named `CopyTextAsync(string text)` already says async + takes a string. Don't add a comment that says "Copies text asynchronously."
  - **No "TODO" / "FIXME" / "HACK" / "XXX" comments.** Use the workflow's "ask user to defer or fix now" path (rule 1.11) instead.
- **Allowed** (rare, and only when ALL three apply: short, load-bearing, not inferable):
  - A non-obvious algorithmic invariant (e.g., `// k-merge requires inputs already sorted by Timestamp ascending`).
  - A workaround for an external constraint (e.g., `// Win32: LoadLibraryEx with DATAFILE flag still maps writable on <Win10`).
  - A deliberate trade-off the reader would otherwise question (e.g., `// Monitor lock — ConcurrentDictionary lost on this benchmark`).
- **Hard length cap on inline comments:**
  - Inline `//` and `#` comments: **one line, ≤ 12 words.** If you can't fit the load-bearing fact in 12 words, the surrounding code needs a better name or a helper extraction — not a longer comment.
- **Mandatory self-review pass before showing diff:** enumerate every NEW comment line in the diff. For each one, write a one-line justification matching one of the 3 allowed cases above ("non-obvious invariant: X" / "external constraint: Y" / "trade-off: Z"). **If you cannot write that justification in one short clause, delete the comment.** This audit is non-skippable — running it sometimes catches 100% of the violations the reviewer would have flagged.
- **Remove existing stale comments** that no longer add value when touching surrounding code. Don't preserve old narration just because it was there before.

**Common failure modes flagged in past reviews:**
- Adding `// Only commit if we're still the most recent load.` above an `if (gen == _gen)` check. The check + name says it. Delete the comment.
- Adding `// Bump generation so an in-flight Refresh skips its commit` above `_gen++` in a Dispose path. The dispose context + a well-named field carry it. Delete.
- Adding `// Same best-effort contract as CopySelectedEvent: callers (banner copy-details, filter export, future surfaces) are typically fire-and-forget UI handlers.` above a try/catch around a clipboard call. Triple violation: speculation about future callers + restating-what-the-code-does + multi-clause prose. Delete the entire comment — the try/catch + the log message ARE the contract.

> **C# adds:** XML doc comment rules (no XML doc on `private` members, length caps on `<summary>` / `<param>` / `<returns>`, default-OFF for new public/internal API). See `csharp.instructions.md`.

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
- **Avoid wall-clock time sources in tests** (`DateTime.Now`, `DateTime.UtcNow`, `Date.now()`, `time.time()`, etc.) — they introduce non-deterministic behavior and timezone dependencies. Use fixed deterministic timestamps (e.g. `new DateTime(2024, 1, 1, 12, 0, 0, DateTimeKind.Utc)`) so tests are reproducible regardless of when or where they run.
- **Add or update unit tests** to cover new code and edge cases. Follow existing testing patterns in the codebase.

> **C# adds:** the `TestUtils/` folder convention and the `Constants` partial-class convention for shared test values. See `csharp.instructions.md`.

### 3.5 Performance

- Consider performance implications of every change.
- Avoid unnecessary allocations, prefer efficient algorithms, and use appropriate data structures.

### 3.6 Defaults and Consistency

- **When in doubt, follow the platform-standard naming guidelines** for the language in question (Microsoft for C#, C++, JS/TS, HTML, CSS; PEP 8 for Python; etc.). The language-specific topic files codify these.
- **When platform guidance and the existing code in a touched file disagree, prioritize consistency with the existing code in that file.** Don't reformat or rename surrounding code just to match the standard.
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

When an operation can fail (throws, returns false, awaits a remote call that may not return, etc.), do not record success-implying state until the operation has actually succeeded. This is one of the most common classes of bug flagged by PR review.

- **Membership / dedup sets** (`seen.Add(x)`, `_processed[id] = true`): perform the work first, then record membership. If the work throws, the next attempt should retry, not skip.
- **Registration / initialization flags** (`_registered = true`, `_initialized = true`): set only after the underlying call (interop, native handle acquisition, network registration) returns successfully.
- **Cache writes**: insert into the cache only on the success path; do not write a partially-populated entry that other callers may read.
- **Don't cache high-cardinality strings.** Before passing a value to a string-interning cache, confirm the value comes from a small, bounded set. Strings built by concatenating per-record fields (timestamps, IDs, paths, user input, payload data) are effectively unique per call and will grow the cache without bound. If a code path produces both canned and per-record variants from the same builder, split the cache call so only the canned branch is interned and the per-record branch returns directly.
- **Error state on success**: on the success path, explicitly clear any prior error fields (`LastErrorCode`, `LastException`, `_warningShown`). A successful run should leave no stale failure breadcrumbs.
- **Idempotency-first ref handoff**: when a method is idempotent (early-returns if already done), assign the long-lived reference (interop reference, native handle, subscription token) **before** the early-return guard, not after — otherwise the second caller sees `null` and the first caller's reference leaks on dispose.

> **C# / Blazor adds:** lifecycle patterns for `IJSRuntime`, `DotNetObjectReference`, `Lazy<Task<T>>`, `IAsyncDisposable`, `[Parameter]` properties, narrow JS-interop catches, and `AbortController` pairing. See `csharp.instructions.md`.

### 3.10 Recurring code smells from past PR reviews

Treat each of these as a hard-stop during self-review and as an explicit thing to look for during the multi-model code-review pass.

- **Constants — single source of truth.** Any literal that constrains a contract (page size, max-in-clause parameter count, default cache size, retention window, file size limit, magic timeout) lives in exactly one named constant. Duplicates across files **will** drift. If the same number appears in two places, extract it before the diff is reviewable.
- **A "list of X" collection must reference the same constants used by the code that produces X — not duplicate the literals.** When you create or maintain a collection whose purpose is to *describe* a hardcoded set elsewhere (a "well-known names" set, an "always-shown columns" list, a "system-known schemas" registry, an "allowed origins" array, a "hardcoded menu items" filter), and another file builds those same items by writing the literals directly, the collection silently goes out of sync the moment someone adds, removes, or renames an item at either site. Extract the literals to named constants in one place, have the collection initializer reference the constants, AND have the hardcoded site reference the same constants — never literals on either side. The collection's existence is itself the signal that the literals are a contract; leaving the literals at one of the two sites defeats the collection's entire purpose. When you encounter this pattern in a diff (yours or someone else's), fix both sites in the same change.
- **Sibling-constant consistency.** When you add or modify one of a *group* of related constants (default error messages, status labels, retry counts in a tier, timeouts per stage), look at its siblings in the same declaration block and verify formatting/punctuation/casing/units are consistent. Trailing-period-on-one-of-three-strings, `"OK"` vs `"Ok"` vs `"Okay"`, `5000` vs `5_000` — reviewers always spot these because they read sibling constants together. So should you.
- **Test specificity.** Assert exact values, never `Arg.Any<T>()` / `It.IsAny<T>()` / `Mock.Of<T>()` (or equivalents in your test framework) when the test's purpose is to verify *what was passed*. Such matchers are appropriate only when the test's contract genuinely doesn't care about the argument (rare). Prefer property-based matchers (e.g. `Arg.Is<T>(x => x.Property == expected)`) or capture-and-assert.
- **Negative assertions are weak when the contract is "exact value Y".** `Assert.DoesNotContain(forbidden, actual)` / `Assert.NotEqual(forbidden, actual)` pass for `null`, empty string, exception messages, and any random value — including when the code under test broke entirely and returned the wrong answer. Use them only when the contract genuinely is *"X must not be the result"* (e.g., regression tests for "this leaked secret never appears in the rendered output"). When the test's purpose is *"the fallback path produces Y"*, assert `Y` exactly with `Assert.Equal(expectedFallback, actual)`. Same energy as the test-specificity rule above — assert the contract, not its absence.
- **Don't materialize streams unnecessarily.** `.ToList()` / `.ToArray()` (and equivalents) inside a method that just iterates once is a wasted allocation and a smell that the author is hiding a re-enumeration bug behind it. Materialize only when (a) the result is consumed multiple times, (b) you need indexed access, or (c) you're crossing a boundary that requires a concrete collection. Same goes for eager collection ops in hot paths (`.Where(...).Count()` instead of `.Any()` / `.Count(predicate)`).
- **Lambda parameter shadowing.** Do not name a lambda parameter the same as an in-scope variable (`var filter = ...; filters.Where(filter => filter.X)`). The compiler accepts it; reviewers and humans misread it. Rename the lambda parameter to something distinct.
- **Failure paths must surface user-visible feedback (UI code).** When a `TryCreate`/`TryParse`/parsing operation returns `null`/`false` on the user-action path, do not silently no-op. Show a dialog, surface a validation message, or log at warning level — whichever matches the surface. Silent failures are the #1 bug source flagged in UI PRs.
- **Comment / path hygiene.** Never commit a `TODO`, `FIXME`, debug `Console.WriteLine` / `console.log` / `print()`, or absolute path that references your local machine (`C:\Users\<you>\...`, `/Users/<you>/...`, your Downloads folder). Strip these in self-review before showing the diff.
- **Idempotency / multi-dispatcher guards.** When you add a "have I done this already?" guard to one code path (`if (_done) return;`, `Add` → `TryAdd`), grep for every other code path that mutates the same state and add the guard there too. Reviewers consistently catch the second/third dispatcher that was missed.
- **Exception messages must stay diagnostic.** When you remove or change a parameter that previously fed an exception's message (computer name, file path, key, etc.), do not collapse the call to `string.Empty` or a bare type name. Replace it with whatever diagnostic context the catch site or log will actually need — typically the resource path, key, or operation that was attempted. Empty exception messages are unrecoverable in production logs.
- **Log messages must match the actually-taken code path.** When you add an early return, guard, or branch *between* a "we're about to do X" log and the code that does X, the log becomes a lie. Either move the log past the guards (so it only fires when X actually happens), or split into per-branch logs that name what really occurred ("Skipping fallback because input is rooted" vs "Falling back with leaf name 'foo.dll'"). Unconditional "Falling back to..." / "Retrying..." / "Loading..." messages that fire before a guard suppresses the action are the most common log-vs-behavior mismatch reviewers catch.
- **Log messages must match what the code actually returns.** A log that says "Returning null" / "No result" / "Failed to load" when the surrounding method actually returns a non-null empty/sentinel value (or vice versa) is a stale-text bug that reviewers always catch. When you change a method's return contract (null → empty collection, throw → return false, optional → required), grep every log line in that method for words describing the old contract and update them.
- **Test portability — no hardcoded system paths or locales.** Tests that touch the filesystem, registry, or system binaries must not hardcode `C:\Windows`, `C:\Program Files`, `\System32\en-US\`, drive letters, or specific UI culture folder names. Use the platform's standard "well-known folder" API or probe the available locale subfolders. Skip-gates are fine as a guard, but the *path you build* must adapt to the host. Same applies to environment variables that may not exist in CI.
- **No dead branches inside loops with the same termination condition.** When a loop's continuation condition already excludes some state (e.g., `while (!string.IsNullOrEmpty(culture.Name))`), an inner `if (state) break;` that fires on the *same* state is dead code — the loop would have terminated next iteration regardless. Either tighten the loop condition to express the full intent, or drop the redundant inner break. Reviewers (human and bot) consistently flag the redundancy and it implies the author hasn't traced the loop's exit conditions end-to-end. The corollary: when adding such an inner break, ask whether the loop condition already covers it; if yes, the break is the wrong fix.

> **C# adds (high-impact):** the **`nameof()` for code symbols inside ANY string** rule (including the test-mirror-via-named-argument pattern), brittle `Received(N)` count assertions on log/diagnostic mocks, **native interop / Win32 / P/Invoke return-value validation**, and **`LoadLibraryEx` / `Path.IsPathRooted` DLL-planting / wrong-binary risk**. See `csharp.instructions.md`. These bullets are the single highest-incidence smell class in the C# review history — read them once when first opening a C# file in a session.

---

## 9. Repository & Worktree Layout Preference

When you need to create a git worktree (e.g., to work on a PR branch in parallel with the main checkout), use the **single-root + hidden-bare-repo + sibling-checkouts** layout. For a repo named `RepoName` under a `<projects-root>`:

- `<projects-root>\RepoName\.git\` — the bare repo (created with `git clone --bare <origin-url> <some-temp-path>` then moved into `.git`, or by initializing the parent and cloning bare directly into `.git`). This is the single source of truth for all refs; all worktrees share its object database. Despite being named `.git`, this is a **bare** repo (`core.bare = true`).
- `<projects-root>\RepoName\main\` — worktree of the default branch.
- `<projects-root>\RepoName\<branch-leaf>\` — one folder per additional worktree, named for the **leaf segment** of the branch (the part after the last `/`, e.g., `feature-x` for branch `user/feature-x`).

The `<projects-root>\RepoName\` directory contains exactly: the hidden `.git` bare repo plus one subfolder per worktree — no loose files, no nested checkouts.

**Why hidden `.git` and not a sibling `RepoName.git\`:** the user prefers a single-root layout so that `RepoName` remains the one project folder visible to file managers, IDE workspace lists, and recent-folder menus. The hidden `.git` keeps the bare data discoverable to git but out of the way visually.

**Setup notes when introducing this layout to an existing non-bare clone:**

1. Verify the existing checkout is clean: no uncommitted changes, no stashes, no local-only branches that aren't pushed, no in-progress rebase/merge/cherry-pick. If anything is unclean, ASK before proceeding.
2. Check for custom hooks (`.git/hooks/*` that aren't `*.sample`) and non-standard config in `.git/config`. If anything custom is present, surface it to the user and ask whether to migrate it to the new bare repo before destroying the old `.git`.
3. Clone bare from the origin URL (not from the local `.git`) — a fresh clone produces correct refspecs and remote tracking out of the box. Clone to a temporary sibling location (e.g., `<projects-root>\RepoName.git`) first; you'll move it into the final `.git` location after the parent folder exists.
4. After the bare clone, confirm `remote.origin.fetch` is the standard `+refs/heads/*:refs/remotes/origin/*` (set it explicitly if not), then run `git fetch origin` so `refs/remotes/origin/*` exists for `git worktree add`.
5. Move the existing checkout aside to a `.old` sibling (do NOT delete it yet), create the new `<projects-root>\RepoName\` parent folder, add the worktrees against the temporary bare repo (`git -C <projects-root>\RepoName.git worktree add <projects-root>\RepoName\<branch-leaf> <branch-or-ref>`), then verify each worktree.
6. Move the temporary bare repo into its final location: `Move-Item <projects-root>\RepoName.git <projects-root>\RepoName\.git`. The worktrees' `.git` files now contain stale gitdir paths.
7. Run `git -C <projects-root>\RepoName\.git worktree repair <each-worktree-path>` to rewrite the per-worktree `.git` gitdir links to the new bare location. Verify with `git -C <worktree> status` from each worktree.
8. Optionally set per-branch upstream tracking (`git -C <worktree> branch --set-upstream-to=origin/<branch> <branch>`) so plain `git push` / `git pull` work without `-u`.
9. Verify with `git worktree list` from inside the bare (or any worktree) and `git status` from each worktree.
10. Only after end-to-end verification, delete the `.old` folder.

**`git worktree add` from a bare repo and existing local branches:** when the bare repo is freshly cloned, the initial fetch sometimes auto-creates local branches that mirror remote-tracking refs. If `git worktree add <path> -b <branch> origin/<branch>` fails with `a branch named '<branch>' already exists`, drop the `-b` flag and check it out directly: `git worktree add <path> <branch>`. Then set upstream tracking explicitly per step 8.

**When NOT to apply the layout automatically:** if the existing repo has local-only branches, custom hooks, uncommitted work, in-progress operations, or non-standard config that the user hasn't explicitly agreed to discard, ASK before restructuring. Don't silently re-clone over a checkout that may carry state the user cares about.

**Per-worktree shell sessions:** when starting work in a worktree, `cd` into the worktree subfolder before running git commands. The bare repo at `<projects-root>\RepoName\.git` is for `git worktree add`/`remove`/`repair` operations only — daily work happens inside the worktree subfolder. Note that `<projects-root>\RepoName\` itself is **not** a worktree — running `git status` from there will error because the folder's `.git` is a bare repo with no working tree.

**Caveat — tools that auto-detect `.git`:** some tooling (file watchers, search indexers, some IDE git integrations) walks up to find `.git` and assumes a non-bare repo. With this layout, `<projects-root>\RepoName` has a `.git` directory but no working tree. If a tool misbehaves when opened against the parent folder (rather than against a specific worktree), open it against the worktree subfolder instead.

---

## 10. Software Installation & Upgrades — Prefer the Platform Package Manager

When installing, upgrading, or uninstalling software on the user's machine, **prefer the platform package manager** over hand-rolled downloads, vendor bootstrappers, or web-installer EXEs:

- **Windows:** `winget` (Microsoft Store + community manifests). Check availability with `winget --version`.
- **macOS:** `brew` (and `brew install --cask` for GUI apps). Check with `brew --version`.
- **Linux:** the distro's native manager (`apt`, `dnf`, `pacman`, `zypper`, etc.) before reaching for `snap`/`flatpak`/curl-bash.

**Why this is the default**: package managers verify signatures, track installed versions, support clean upgrade and uninstall, are idempotent, and don't require chasing the right download URL (which often rots — `aka.ms` shortlinks redirect to Bing search pages when the slug doesn't exist, vendor sites move bootstrappers between releases, etc.). They also write to standard locations and integrate with the OS uninstall surface, so a future "remove this" request is a one-liner instead of an archaeology project.

**Mandatory pre-flight before any install/upgrade/uninstall**:
1. **Confirm the manager is installed** (`winget --version` / `brew --version` / `which apt`).
2. **Confirm the package exists in the manager** with an exact ID search (`winget search --id <Vendor.Product> --exact`, `brew info <name>`, `apt-cache show <name>`). If the search hangs or returns no exact match, do not guess — surface the result to the user and decide together whether to (a) try a different ID, (b) fall back to the vendor bootstrapper, or (c) abort.
3. **Confirm the version/edition matches what the user asked for**. Package-manager IDs sometimes pin to a specific edition (`Microsoft.VisualStudio.2026.Enterprise` vs `...Community`) — re-read the ID before invoking install.

**When to fall back to the vendor's bootstrapper / installer**:
- The package isn't published in the manager (or only an outdated version is).
- The install requires options the manager wrapper doesn't expose (e.g., complex workload/component selection that needs a `--config <file>.vsconfig`, custom MSI properties, license-server configuration).
- The user explicitly asks for the vendor installer.
- An offline/air-gapped install is required.

In these cases, **download the bootstrapper from a URL you've verified resolves to a real signed binary** — fetch with `Invoke-WebRequest` / `curl`, check the magic bytes (`MZ` for PE, `7F 45 4C 46` for ELF, `CF FA ED FE` for Mach-O), and run the platform's signature check (`Get-AuthenticodeSignature` on Windows, `codesign -dv` on macOS, `gpg --verify` on Linux). An HTML page saved as `.exe` is a recurring failure mode when shortlinks rot — always validate before executing.

**Verify the bootstrapper's embedded version metadata BEFORE execution.** A signed Microsoft binary from a working URL can still be the *wrong product version* — vendor download endpoints often accept query parameters like `?version=...` and silently ignore unknown values, falling back to a default that may be many releases old. Before launching any bootstrapper / installer / setup binary you downloaded, read its embedded version (`(Get-Item <path>).VersionInfo.FileVersion` on Windows; `mdls -name kMDItemVersion` or `defaults read .../Info CFBundleShortVersionString` on macOS; `--version` flag on Linux), and assert it matches the major version of the product the user actually asked for. The user-facing `ProductName` / `ProductVersion` strings are sometimes friendly labels (e.g. "Visual Studio 2026") that don't sort numerically — prefer the numeric `FileVersion` for the assertion. If the version doesn't match, abort and re-source the bootstrapper from a different URL — never run it "to see what happens." A wrong-version install can silently overwrite, downgrade, or sit alongside the user's existing install and waste 30+ minutes of cleanup. The rule of thumb: **if you can't print the bootstrapper's major version and confirm it matches before launching, you're not ready to launch.**

**Locating the right URL when shortlinks fail:** vendor download portals usually expose a "thank you for downloading" intermediate page (e.g., `https://visualstudio.microsoft.com/thank-you-downloading-visual-studio/?sku=...&version=...`) that contains the actual signed bootstrapper URL with the correct query-parameter values for the current release. Scrape that page (regex out the real download URL) rather than guessing slugs. The query parameters that matter (e.g., `version=VS18` vs `version=VS2026`, `channel=stable` vs `channel=Release`) often differ from what the marketing material implies — read them from the page that the official "Download" button submits to, not from your own assumptions.

**Idempotency note**: `winget install`, `brew install`, and `apt install` are all safe to re-run when a package is already installed (they no-op or upgrade). Don't add bespoke "is it already installed?" checks unless you need to branch on the result — let the manager handle it.

---

## Topic-specific files

The following files live under `.github/instructions/` and are loaded automatically by the Copilot CLI when files matching their `applyTo:` glob are in the working set. They extend the rules above with language-specific guidance.

| File | Loads when working with files matching | Adds |
|---|---|---|
| `csharp.instructions.md` | `**/*.cs`, `**/*.csx`, `**/*.csproj`, `**/*.razor`, `**/*.razor.cs`, `**/*.cshtml`, `**/*.aspx` | C# / .NET style, XML-doc comment rules, `nameof()` requirement, NSubstitute / native-interop / `LoadLibraryEx` smells, Blazor + JS interop lifecycle, `TestUtils` folder + `Constants` partial-class convention |
| `cpp.instructions.md` | `**/*.cpp`, `**/*.h`, `**/*.hpp`, `**/*.cc`, `**/*.cxx`, `**/*.c` | C++ naming, formatting, member ordering |
| `javascript-typescript.instructions.md` | `**/*.ts`, `**/*.tsx`, `**/*.mts`, `**/*.cts`, `**/*.js`, `**/*.jsx`, `**/*.mjs`, `**/*.cjs` | JS/TS naming, formatting, expression preferences, imports |
| `html.instructions.md` | `**/*.html`, `**/*.htm`, `**/*.razor`, `**/*.cshtml` | HTML formatting, attribute order, semantic / accessibility best practices |
| `css.instructions.md` | `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less` | CSS naming (kebab-case / BEM), formatting, property order |

**To add a new topic file:** create `<topic>.instructions.md` under `.github/instructions/`, add a YAML frontmatter block with an `applyTo:` glob (comma-separated patterns), then write the rules. The CLI picks it up on the next session start. See `README.md` at the repo root for setup details.
