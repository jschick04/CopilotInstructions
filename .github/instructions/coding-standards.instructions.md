---
applyTo: "**/*"
---

# General Coding Standards - Universal (extracted from AGENTS.md)

<!-- read-receipt-token: 947ffd0e -->

> **Scope:** auto-loaded on every edit. Contains universal standards (naming, ambiguous-naming-ask, opportunistic rename, defaults/consistency, user-facing text) that apply to docs, config, prose, and code alike. Code-specific standards (tests, perf, state predicates, deferred mutations, recurring smells, project structure) live in `coding-standards-code.instructions.md`, auto-loaded on code edits only. Section 3.1 (Comments) and section 3.14 (No em-dashes) remain in the always-loaded core (`AGENTS.md`).

---

### 3.2 Naming - clarity over brevity

- Use **descriptive, full-word names**.
  - OK: `userSessionCache`, `customerName`, `combinedRecords`
  - BAD: `cache`, `cn`, `cr`, `ctx` (don't abbreviate `context`), `tmp`, `data2`
- **Lambdas:** full names unless the parameter is **immediately and unambiguously** clear from the operation. When in doubt, use the full name.
  - OK: `orders.Where(order => order.Status == OrderStatus.Open)`
  - OK: `bytes.Sum(b => b.Length)` - single-letter is fine in a tight, obvious scope
  - BAD: `orders.Where(o => o.Status == OrderStatus.Open && (o.Region == "X" || o.Channel == "Y"))` - scope is big enough to deserve `order`
- **Method names:** verb-phrase that describes the *outcome*, not the implementation.
  - OK: `MergeSortedRecordsIntoCombinedView`, `TryGetCachedErrorMessage`
  - BAD: `Process`, `DoWork`, `Handle`
- Avoid noise prefixes/suffixes (`Helper`, `Manager`, `Util`) unless the type genuinely is one.

### 3.3 When naming is ambiguous - ask first

If, while implementing, a name is not obviously correct or there are two or more reasonable choices that meaningfully differ in intent, **stop and present 2-4 options to the user via `ask_user`** with a one-line rationale per option. Do not invent a name and proceed.

Cases that warrant the ask:
- A new cache type that could be named after its key, its value, or its consumer (`UserSessionCache` vs `LoginTokenCache` vs `AuthRequestCache`).
- A new helper method whose name could imply a stronger or weaker contract (`TryGetMessage` vs `GetMessageOrNull` vs `LookupMessage`).
- A flag whose polarity matters (`IsLazy` vs `IsEager`, `RebuildAlways` vs `RebuildOnChange`).
- A model property where the prior name disagrees with the new behavior (e.g., renaming `TagsDisplayName` to better reflect that it is now lazy / on-demand - options: `TagsDisplayText`, `TagsJoined`, `FormattedTags`, leave-as-is-with-doc-comment).

When choices clearly differ only in style (and not in intent), pick one and move on - do not over-ask.

### 3.3.1 Opportunistic rename suggestions for existing symbols

When working in or touching a file (any reason - bug fix, feature, refactor, review), if you encounter an **existing** type / method / property / parameter / record / class / interface name that doesn't describe its intent well or has a clearly better name available, **stop and ask the user via `ask_user`** before renaming. Phrase it as: *"While here I noticed `OldName` doesn't describe its intent well - proposing `NewName` because [one-line rationale]. Rename now / leave / propose alternative?"*

When to surface a rename:
- Name is generic where a domain term applies (`Manager`, `Processor`, `Helper`, `Util`, `Data`, `Info` for non-`xxxInfo` types).
- Name describes implementation, not intent (`StringDictionary` vs `UserPreferences`, `IntList` vs `RetryDelays`).
- Name disagrees with current behavior because the type evolved (`SyncCache` that's now async, `ReadOnlyList` that exposes mutation).
- Name uses an outdated abbreviation or one that conflicts with project terminology (`Pkg` vs `Package`, `Auth` ambiguous between authentication / authorization).
- Name shadows a type (PascalCase local / parameter `LogPathType LogPathType`) - flag as a code-quality rename even if it currently compiles.
- Name uses pre-rename terminology that survived only because the rename pass missed it (e.g., a member named `XLogNames` on a class renamed to `LogChannelNames` should probably become `XLogChannels`).
- An interface name doesn't communicate the role (`IDatabaseCollectionProvider` for what's really an "active databases" provider).

When NOT to surface a rename:
- Name is locally consistent with project conventions even if it's not your preferred name (style-only).
- Rename would touch many unrelated files and the user is mid-flight on a different scope (defer to a follow-up via `ask_user` per the *Pre-existing issues* cross-cutting rule in `AGENTS.md`).
- The "better" name is only marginally better and the cost of churn (PR diff noise, blame loss, downstream breakage) outweighs the clarity gain.
- Public API surface that's already shipped to external consumers - needs explicit deprecation strategy, not a silent rename.

The same `ask_user` choice template as section 3.3 applies: present 2-4 candidates with one-line rationale each, let the user pick. Bundle multiple rename candidates in one prompt when reviewing a single file, but ask one prompt per file (don't bundle across files - the user loses track of context).

### 3.6 Defaults and Consistency

- **When in doubt, follow the platform-standard naming guidelines** for the language in question (Microsoft for C#, C++, JS/TS, HTML, CSS; PEP 8 for Python; etc.). The language-specific topic files codify these.
- **When platform guidance and the existing code in a touched file disagree, prioritize consistency with the existing code in that file.** Don't reformat or rename surrounding code just to match the standard.
- **Comprehensive over sampled.** When the user asks for a review, scan, audit, sweep, or "look across all X" of any noun (sessions, files, PRs, callers, tests), default to **complete coverage** - enumerate the full set first, then process every item. Do not pick a representative subset on your own. If the set is genuinely too large to process in full (cost, time, context budget), surface that explicitly via `ask_user` with the count and propose a sampling strategy *before* starting. "I read 9 of the ~80 sessions" is a failure mode the user will catch every time.
- **Search-first for renames and refactors.** Before declaring any rename, signature change, or moved symbol complete, run a full-repo grep for the old identifier across **every** relevant file type - including `*.razor`, `*.razor.cs`, `*.cshtml`, `*.json`, JSON converter switch cases, `*.xaml`, test projects, doc comments, and trace/log strings. Report "0 matches" before declaring done. "I missed a consumer" is the most common post-refactor regression and almost always means the grep wasn't wide enough.

### 3.9 User-facing text - match the runtime behavior

- **Audit every user-facing string when a call's shape changes.** When a diff changes a method's signature, parameter list, return type, or observable behavior AND that method participates in a user-visible flow (UI text, log message, exception message, HTTP response, CLI output, toast, dialog, tooltip, accessibility label, notification payload, status-bar text), re-read every string literal in the touched method AND in every direct caller that formats / logs / renders the method's result. Update any text whose wording no longer matches what the user will experience.
- **Re-evaluate inherited literals when you move or refactor code.** A string literal that read correctly in its old context may not read correctly after a `git mv`, an extract-method, or a parameter rename. Pre-existing copy that the diff makes visible is fair game to fix in the same change - see *"directly caused by or tightly coupled to the code you're changing"* in the global rules.
- **Be specific and contextual, not generic.** Prefer wording that names the actual operation, the scope, and what the user is being asked to do: "Please select database files to import" beats "Please select files" beats "Please select a file." Avoid generic placeholders left from scaffolding (`"Open"`, `"Choose..."`, `"OK"`) when the surface is a real user dialog with a specific intent.
- **Match plurality, tense, and voice to the runtime behavior.** Multi-select pickers / batch operations / list-returning APIs use plural noun forms ("files", "items", "results"). Idempotent re-runs use neutral phrasing ("Up to date") rather than action verbs ("Updated"). Async operations that may take time use progressive forms ("Importing...") not past-tense.
- **Aria-label / alt / tooltip text describes the control's behavior, not its appearance.** A button labeled "X" with `aria-label="Close dialog"` is correct; `aria-label="X icon"` is wrong. When the behavior changes, the accessibility text changes with it.
- **Reviewer enforcement.** When sending a diff that changes a call's shape, behavior, or scope to the rubber-duck or code-review agent, ask it to enumerate every user-facing string in the touched scope and verify each one still matches what the user will actually experience.
- **API names referenced in docs / READMEs / inline comments must mirror the code.** When you rename or replace an API at the call site (`SHGetPathFromIDListW` to `SHGetPathFromIDListEx`, `GetPathAsync` to `TryGetPathAsync`, `OldHelper` to `NewHelperV2`, `Newtonsoft.Json` to `System.Text.Json`), grep `docs/`, `README.md`, every `*.md` in the touched module, and inline `// see <ApiName>` / XML `<see cref="ApiName"/>` comments for the old name and update each occurrence in the same change. The reviewer (human or Copilot bot) catches stale API names in docs on sight - the doc says "calls `SHGetPathFromIDListW`" but the impl now calls `SHGetPathFromIDListEx`, and the reader spends 30 seconds confused about which is authoritative. **Audit lens**: when a diff changes any external/Win32/framework API name at a call site, run `rg "<OldApiName>" docs/ *.md src/` over the repo and fix every hit in the same PR. Treat this with the same priority as the user-facing-text re-audit when call shape changes - both are "docs/text fossilize when code moves".
