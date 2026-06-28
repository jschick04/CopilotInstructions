---
name: comment-protocol
description: Three-step decision protocol governing every NEW or substantively-rewritten comment in the diff. Clarity check → rename check → ask_user comment-approval gate. Auto-fires before any comment is added or substantively rewritten - not a user-invoked playbook. Referenced from AGENTS.md §3.1, post-code-change.md step 2.6, and pattern-catalog.md `comment-necessity`.
triggers: []
---

# Comment-protocol playbook
<!-- read-receipt-token: 09c08387 -->

## When this fires (no user invocation needed)

Auto-fires as a sub-step the moment the agent is about to introduce a NEW comment line in a code edit, OR substantively rewrite an existing comment, in any language, in any file (production, test, configuration, script). Fresh sessions: AGENTS.md §3.1 carries the always-loaded `STOP. Before adding ANY new comment or substantively rewriting an existing one, view comment-protocol.md.` pointer that brings you here. Resumed-after-`/compact` sessions: the PSProfile `autopilot -Compact` prompt re-anchors the rule and the section reference in the summary.

The trigger is **objective** - it fires on what would end up in the diff, NOT on the agent's subjective sense of "needing" a comment. If the diff contains a new comment line, the protocol applies whether or not the agent consciously "reached for" one.

## Hard gates

- Trigger is objective (every NEW comment line + every substantive comment rewrite in the diff). Subjective "I didn't *feel* I needed it" is NOT a valid skip.
- Step-3 `ask_user` call PRECEDES the `edit` that introduces the comment - never write the comment first and seek approval afterwards.
- Categorical language-level prohibitions (e.g., `csharp.instructions.md` no-XML-doc-on-`private`-members) are NOT reachable via step 3. For categorically-prohibited comments, the answer is *no comment*; you never ask. DEFAULT-OFF rules (e.g., `csharp.instructions.md` new public/internal API XML doc) ARE reachable via step 3 - see *Hard precedence - categorical bans vs default-OFF* below.
- Sub-agents (`general-purpose`, `task`, `research`, etc.) may NOT call `ask_user` for step 3 - sub-agent-emitted comments are PROPOSED only and run through the orchestrator's step 3 on integration.
- One rejection at step 3 → DROP the comment, no reject-loop ping-pong, unless the user explicitly asks you to rework and re-propose.
- Headless / `ask_user` unavailable → DROP the comment. NEVER hard-stop the change for an unapproved comment.
- Post-code-change ledger step 2.6 fails closed if any non-exempt comment lacks an `approval_turn:` citation - the commit is forbidden per `review-workflow-gates-sweeps.md` §2B.

## Scope - what the protocol governs

Every comment syntax in every language, including but not limited to:

- `//` (C, C++, C#, Java, JavaScript, TypeScript, Rust, Go, Swift, Kotlin, Bicep, Dart)
- `#` (Python, Ruby, Bash, PowerShell, YAML, HCL/Terraform, Dockerfile, Makefile)
- `/* */` block comments (C-family, CSS, SCSS, Java, Rust, Go)
- `<!-- -->` (HTML, XML, Markdown, Razor markup)
- `--` (SQL, Lua, Haskell, Ada, Elm)
- `<# #>` block comments (PowerShell)
- `;` (Lisp, Clojure, INI)
- Docstrings (Python `"""..."""`, Elixir `@moduledoc` / `@doc`)
- JSDoc / TSDoc `/** */`
- XML doc / `///` (C#, F#)
- Godoc (`//` line preceding declaration)
- Rustdoc (`///` outer, `//!` inner)

*Substantive rewrite* = any change beyond pure whitespace, spelling fix, or line wrapping. Specifically substantive: word substitution (even synonym swap), clause reordering, punctuation change beyond a spelling fix, format-syntax change (e.g., `//` to `/* */`), case change beyond proper-noun correction. When in doubt, default to substantive (gate applies).

**For an ALREADY-APPROVED comment, nothing is non-substantive.** Because the byte-exact `comment_sha` governs (per-line trim, join LF, SHA-256), ANY change beyond per-line leading/trailing (indentation) whitespace - interior whitespace, line-wrap, spelling, words, punctuation, or format-syntax (`//` to `/* */`) - re-keys the sha, invalidates the prior approval, and re-enters step 3. The whitespace / line-wrap / spelling exemptions above (and the `typo` exempt category) apply ONLY to comments that were NEVER individually approved.

## Scope - exempt categories (record on the ledger, no step-3 ask)

These 6 canonical machine tokens are the ONLY valid `approval_turn: n/a - exempt:` values. The ledger fails closed on any other label. Inventing a new category at audit time is itself a violation - propose a new category via an instruction-repo edit, run it through the panel, then use it.

- **`typo`** - spelling-only correction (single misspelled word replaced with its correct form, or pure whitespace / line-wrapping fix). NO word substitution beyond the misspelling. NO punctuation change beyond the spelling fix. NO clause reordering. If ANY change goes beyond strict spelling/whitespace, the edit is substantive and the protocol applies. `typo` does NOT apply to editing an ALREADY-APPROVED comment: any edit there re-keys the `comment_sha` and re-enters step 3. `typo` is only for fixing comments that were never individually approved.
- **`deletion`** - removing a comment entirely. Governed by AGENTS.md §3.1 *Remove existing stale comments* rule.
- **`stale-comment-fix-per-§3.9/§3.10`** - correcting a comment that has become false because of your code change. §3.9 / §3.10 REQUIRE these fixes. Apply rename-first / delete-default; do NOT route through step 3. Recorded on the ledger with this exact category label.
- **`generated`** - comments inside files with an explicit `<auto-generated>` / `// <auto-generated>` / `/* THIS FILE IS AUTO-GENERATED */` / `# AUTO-GENERATED` header at the top of the file, OR matching a known generated-output path pattern (e.g., `**/obj/**`, `**/bin/**`, `**/Generated/**`, `**/__generated__/**`, `**/node_modules/**`, `**/*.g.cs`, `**/*.g.ts`, `**/*.pb.go`). Semi-generated files where the agent is editing the hand-maintained side of a partial (e.g., `*.Designer.cs` paired with a hand-edited `*.cs`) are NOT exempt - the hand-maintained file is treated as fully agent-authored.
- **`vendored`** - comments inside vendored third-party code the agent did not author (e.g., `vendor/`, `third_party/`, code copied verbatim under a third-party license header).
- **`THROWAWAY-header`** - the canonical `THROWAWAY: <prototype-name>` header on a comment-capable file under `prototypes/<name>/`, per `design-exploration.md` / `performance-comparison.md`.

## The three steps

### Step 1 - Clarity check

Re-read the surrounding code: the function or method you're inside, its parameters, the variable being assigned, the type involved, the field being touched.

Ask:

> *"Is the code already clear AND is every relevant function / method / parameter / variable / type / field / property name clear about what it does and why?"*

If YES → **no comment**. Stop here. The protocol concludes with no further action and no ledger entry (the comment was never written).

### Step 2 - Rename check

If step 1 identified unclear code, ask:

> *"Can a better function / method / parameter / variable / type / field / property name (or a small extraction into a well-named helper) carry the fact I want to comment?"*

Apply AGENTS.md §3.3 / §3.3.1 - when 2+ reasonable rename candidates exist that differ in intent, present them via `ask_user` with a one-line rationale each. (This is the existing naming-ambiguity ask, not a new gate.)

If a rename or small helper extraction makes the code clear → **rename, drop the comment**. Stop here.

Examples of rename-first wins:
- *"This method does X for Y reason"* → method name describes X-for-Y.
- *"This flag is true when Z"* → flag named `IsZ` / `HasZ`.
- A multi-line comment narrating a code block → extract block into a named helper; let the helper name carry the intent.
- *"We're about to clear the buffer because..."* → if the *because* is the load-bearing fact, the next line probably needs a better name or a small refactor; the comment is the symptom.

Do this pass on **every** new comment, not just borderline ones.

### Step 3 - Comment-approval gate (`ask_user` REQUIRED)

Only when a comment is still required after steps 1 and 2 - AND it satisfies one of the three AGENTS.md §3.1 *Allowed* cases (non-obvious algorithmic invariant / external-constraint workaround / deliberate trade-off):

1. **Decide the exact comment text** in full (no placeholders).
2. **Call `ask_user`** with these form fields (one prompt per change - see *Batching* below for multi-comment changes):
   - **(a) Exact text verbatim** - the proposed comment, character-for-character.
   - **(b) Surrounding code snippet** (≤ 10 lines) that the comment would attach to.
   - **(c) Justification** - one sentence explaining why a rename, extraction, or restructure cannot carry the fact.
   - **(d) Allowed case** - which of the three §3.1 *Allowed* cases applies: `non-obvious invariant` | `external constraint` | `trade-off`.
3. **Add the comment ONLY on explicit user approval.** The `ask_user` call PRECEDES the `edit` that introduces the comment.
4. **On rejection → DROP the comment.** No reject-loop ping-pong. Loop back to step 2 only if the user explicitly asks you to rework and re-propose.
5. **If `ask_user` returns no response** within the runtime's blocking-prompt window (timeout, cancel, "no response" status, or capability error returned mid-call): treat as rejection → DROP. Record on the ledger as `approval_turn: n/a - no-response-drop`. This is distinct from degraded mode: degraded mode = `ask_user` unavailable from the start; no-response = `ask_user` was attempted but the user didn't answer.

### Batching multiple comments

When a single change produces multiple proposed comments, present them ALL in ONE `ask_user` call (one form field per comment with its proposed text + snippet + justification + allowed-case). Do NOT make one `ask_user` call per comment - per-comment prompts annoy the user and induce blanket approval, which defeats the gate.

**Hard cap: 5 comments per `ask_user` call.** A batch larger than 5 induces blanket approval. If a single change proposes more than 5 comments, chunk into multiple `ask_user` rounds of ≤ 5 each. If a single change proposes more than 15 total, that's a signal the change has too many proposed comments - re-run the rename-check on the surplus and consider whether the diff has scope creep.

## Hard precedence - categorical bans vs default-OFF

**TRULY CATEGORICAL (step 3 unreachable - the answer is *no comment*, you never ask):**

- **C#** (per `csharp.instructions.md`): No XML doc on `private` members. EVER. Drop without asking.

**DEFAULT-OFF (step 3 IS reachable but the agent's bar is HIGH - only propose when the language file's narrow allowed scenarios genuinely apply):**

- **C#** (per `csharp.instructions.md`): NEW public / internal API XML doc is DEFAULT-OFF. Agent does NOT unilaterally propose XML doc on new public/internal API. Only when the type/method signature genuinely cannot express the contract - non-obvious failure mode, non-obvious thread-safety guarantee, BCL quirk with version citation, spec/standard reference, or similar narrow case from `csharp.instructions.md`'s allowed list - the agent runs step 3 like any other comment, citing the specific scenario in justification field (c).

If you find yourself wanting to ask the user to approve a comment that hits a TRULY CATEGORICAL ban, stop. The rule is hard NO; the user's "yes" cannot authorize it. Drop the comment without asking.

## Sub-agent rule

Per AGENTS.md cross-cutting rule *"Sub-agents must NEVER prompt the user"*, sub-agents (`general-purpose`, `task`, `research`, `code-review`, etc.) may not call `ask_user`. They cannot independently run this protocol.

Procedure when a code-writing sub-agent emits a comment:

1. The sub-agent's output containing a comment is treated as PROPOSED only.
2. The orchestrator (you) runs the three-step protocol on integration: clarity check → rename check → step-3 `ask_user` for any comment that survives.
3. Sub-agent comments that reach the working tree without orchestrator step-3 approval are deleted before the diff is shown to the user.

When prompting a code-writing sub-agent, include in the prompt: *"You may propose comments only as suggestions in your return value. Do NOT introduce comments directly in any `edit` calls - the orchestrator runs the §3.1 / `comment-protocol.md` three-step gate on integration."*

## Degraded mode (no `ask_user` available)

**Concrete headless predicate** - the ONLY valid grounds for invoking degraded mode:

- `ask_user` tool call returns a "capability not available" / "tool not registered" / "unsupported" error from the runtime, OR
- The runtime explicitly indicates non-interactive mode via an environment signal (`CI=true`, `GITHUB_ACTIONS=true`, `TF_BUILD=true`, `JENKINS_URL` set, equivalent CI/pipeline markers), OR
- The runtime has explicitly disabled user prompts for this session (config flag, headless launch mode).

**Agent uncertainty about whether the user will respond is NOT headless.** When uncertain (long-running session, user might be AFK), attempt `ask_user` first and treat no-response within the timeout window as the *no-response-drop* path in Step 3. The agent MAY NOT claim "I think the user is away" as grounds for degraded mode - the predicate is mechanical, not judgmental.

**Behavior when the headless predicate matches:**

- **Default action for a step-3-required comment: DROP the comment.**
- NEVER hard-stop the change because a comment cannot be approved.
- The post-code-change step 2.6 ledger records `approval_turn: n/a - degraded-mode-drop` on the dropped-comment bullet (this is NOT an exempt category - it's a degraded-mode disposition; the ledger explicitly distinguishes the two so post-hoc review can tell why a comment was dropped).

This is a deliberate asymmetry vs the User-skip policy's hard-stop default. Gates that require user input for *load-bearing* decisions (commit approval, commit identity, push credentials) remain hard-stop in headless mode per their own rules. A comment is never load-bearing enough to block the change.

## Recording - post-code-change ledger interaction

The `post-code-change.md` step 2.6 comment-audit evidence gate enumerates every NEW or substantively-rewritten comment line in the diff. For each one:

```
- <file:line>: approval_turn: <ask_user turn/message ref> | allowed-case: <non-obvious invariant | external constraint | trade-off> | justification: <one-line text> | comment_sha: <64-hex>
```

Approved bullets REQUIRE `comment_sha`: the gate hashes the committed comment block byte-exact (per-line trim, join LF, SHA-256). Compute it via the shared `Get-CommentBlockSha` (never by hand); a `<...>` placeholder or a missing sha fails closed. Exempt bullets carry NO sha, but their `<file:line>` must key to a real detected comment block.

For exempt comments:

```
- <file:line>: approval_turn: n/a - exempt: <typo | deletion | stale-comment-fix-per-§3.9/§3.10 | generated | vendored | THROWAWAY-header>
```

For comments dropped in degraded mode (headless predicate matched):

```
- <file:line>: approval_turn: n/a - degraded-mode-drop
```

For comments dropped because `ask_user` was attempted but the user didn't respond:

```
- <file:line>: approval_turn: n/a - no-response-drop
```

For comments dropped via step-3 rejection or step-2 rename-first resolution (audit-trail entry):

```
- <file:line>: deleted (per protocol step-3 rejection | rename-first resolution)
```

A bullet missing the `approval_turn:` field, citing an exempt category not in the canonical 6, or citing an unknown `n/a - <reason>` value fails the step-2.6 gate and forbids the commit per `review-workflow-gates-sweeps.md` §2B (`comment-audit-§3.1: failed - <site list>`).

## Persisted audit record - a LOCAL git note (this instructions repo only)

**Where the record lives (READ THIS FIRST).** In THIS instructions repo the comment audit is persisted as a LOCAL git note on `refs/notes/copilot-audit-comment` - never staged, never committed, never pushed (zero remote footprint). The agent authors the §2.6 block to a GITIGNORED worktree receipt at `.github/pr-quality-gate/audits/last.md`; the `post-commit` hook (`scripts/flush-audits.ps1`) reads that receipt, writes it as the note on the new commit (prepending an `audited_tree:` line that binds the note to the commit's tree), and deletes the receipt. The `pre-push` hook (`scripts/check-audit-notes-prepush.ps1`) validates the note for every pushed commit. All of this is IDENTITY-GATED to this repo (`Test-IsInstructionsRepo`); on any other repo the machinery no-ops.

**Do NOT stage or commit the receipt.** `.github/pr-quality-gate/audits/last.md` is gitignored - `git add` will refuse it, and that is correct: the comment audit is recorded as a note by the hook, not as a tracked file. The agent stages NOTHING for the comment audit. `git add .` / `-A` / `--all` remain forbidden per AGENTS.md §0.

**On a consuming repo (audit machinery absent / identity gate off):**
- DO NOT create `.github/pr-quality-gate/audits/last.md`. It is an instruction-set artifact that must not pollute the consuming project.
- The §3.1 comment-protocol DISCIPLINE still applies - every NEW or substantively rewritten comment in the diff must still pass clarity-check → rename-check → step-3 `ask_user` approval (or fall under one of the canonical 6 exempt categories).
- Comment-audit tracking happens INLINE via the `comment_audit` block in `PRE-COMMIT GATE PASSED` (see `pre-commit.md` `comment_audit.audit_record: inline - consuming repo`). The block records counts + per-comment dispositions via approval-turn citations from the session's `ask_user` history. No file artifact, no note.

---

Each commit's receipt at `.github/pr-quality-gate/audits/last.md` contains the §2.6 comment-audit block plus `parent_sha:` and `commit_subject:` header lines.

**Format** (literal text, with no leading prose):

```
parent_sha: <git rev-parse HEAD at write time - the SHA the about-to-be-created commit will be a child of. MUST be the full 40-char hex SHA. For TRUE root commits (no parent), use the literal `EMPTY_TREE`. Template placeholders like `<git rev-parse HEAD>` are REJECTED by the CI script.>
commit_subject: <the proposed commit subject for the about-to-be-created commit; recommended ≤72 chars (not enforced by CI - `Test-AuditFile` checks presence + rejects template placeholders but does not verify length or content match against the actual commit subject)>
Comment audit: scope=<files in diff>, <N> new-or-substantively-rewritten comment lines in diff, <J> approved, <E> exempt, <DG> degraded-mode-drop, <NR> no-response-drop, <D> deleted.
- <file:line>: approval_turn: <ask_user turn/message ref> | allowed-case: <case> | justification: <one-line text> | comment_sha: <64-hex>
- <file:line>: approval_turn: n/a - exempt: <category>
- <file:line>: approval_turn: n/a - degraded-mode-drop
- <file:line>: approval_turn: n/a - no-response-drop
- <file:line>: deleted (per protocol step-3 rejection | rename-first resolution)
(one bullet per NEW or substantively-rewritten comment line; OR the zero-count justification when scope has no comment changes)
```

**`parent_sha:` field is REQUIRED and STRICTLY VALIDATED** - the local note gate (`Read-CommentNoteValidated`, reusing `Test-AuditFile` from `scripts/check-comment-audit.ps1`) matches it against the commit's actual parent (via `git rev-parse <commit>^`) to detect a stale record. Accepted values:
- The full 40-character hex SHA that exactly matches the commit's actual parent (the validator requires an exact 40-char match - no prefixes accepted)
- The literal `EMPTY_TREE` for true root commits (no parent) - the script verifies the commit has no parent before accepting this
- Template placeholders like `<git rev-parse HEAD>` or `<.+>` are EXPLICITLY REJECTED (forces the agent to actually run the command and substitute the value)

Use `git rev-parse HEAD` AT RECEIPT-WRITE TIME (immediately before the commit). Verification is local + post-commit: the `pre-push` note gate compares the note's `parent_sha:` against the commit's `<commit>^`, and its `audited_tree:` against the commit's tree (a stale carry onto an amended / rebased commit is rejected).

**Always present, even when the commit has no comments:** write the zero-count justification line per §2.6's template, so every commit carries a valid note.

**Meta-changes that don't trigger §2.6** (no source-code edits): still author the receipt with `Comment audit: scope=<no source files>, 0 new comment lines, zero-count justification: meta-change (no source edits)`.

**Not staged - flushed to a note.** `.github/pr-quality-gate/audits/last.md` is a GITIGNORED authoring receipt, not a tracked artifact: the agent NEVER runs `git add` on it (the gitignore refuses it). After the commit, the `post-commit` hook flushes the receipt into the commit's note and deletes it. The note IS the persistent audit record; the local `pre-push` gate (`scripts/check-audit-notes-prepush.ps1`) fails the push if a comment-bearing commit lacks a fresh valid note. The note is local-only (never pushed); there is no CI comment-audit job (CI cannot read a local note - the public-diff Layer-A detectors cover emdash / structural-conformance / duplication).

**Identity-gated record:** the receipt-to-note flush + the pre-push validation run ONLY in this instructions repo (`Test-IsInstructionsRepo`, by remote identity). On any consuming repo the machinery no-ops and tracking is inline (above) - nothing is written or committed to the consuming project.

**Single authority (which record the machine trusts when):** before commit the on-disk receipt `.github/pr-quality-gate/audits/last.md` is the machine authority (validated by `check-comment-audit.ps1 -StagedMode` in the pre-commit hook); after commit the git note `refs/notes/copilot-audit-comment` is the persistent authority (flushed by `post-commit`, validated by `pre-push`). The inline `comment_audit` block in `PRE-COMMIT GATE PASSED` is summary-only, and the `review-workflow-gates-sweeps.md` §2B `comment-audit-§3.1` line is a status row only - neither is the validated record.

**No bootstrap skip (hardened):** every non-merge commit in the push range is validated against its parent, INCLUDING the first commit that introduces a file. The first-add and never-existed exemptions were removed so an introducing commit cannot bundle un-audited comment-bearing changes.

**Known limitations** (acknowledged v1 ceiling - these are forcing-function speed-bumps backed by the user's local manual review, NOT cryptographic enforcement):

- **Site + exact-wording bound (no longer count-based).** The validator (`Test-CommentCoverage` in `scripts/check-comment-audit.ps1`, reused by the staged gate and the local note gate) enforces a bijection: every detected new-comment BLOCK must have a covering approved/exempt bullet at its exact `file:StartLine` - no count-padding, no orphan bullets, no two cover bullets at one site. Approved blocks are additionally byte-exact hash-bound: the bullet's `comment_sha` must equal the SHA of the committed block (catches a forgotten re-run or any divergence between receipt and committed text). **Honest ceiling** (do not overclaim): the sha binds the receipt text to the committed text; it does NOT prove the user actually approved it - `approval_turn:<ref>` stays unverified (the irreducible ceiling), and a DELIBERATE re-hash of the shipped text still passes. EXEMPT-dispositioned sites are NOT sha-bound. Comments the detector MISSES (tight trailing tokens, unknown extensions, docstring bodies) generate no site and still escape. The diff-alongside-review remains the human wording check.
- **String-literal false-positives** include both line-tokens and tight block-tokens. The agent must route through step 3 (the false-positive IS a real new comment-looking line, so propose it as a comment and let the user approve / reject); there is NO canonical exempt category for "regex false-positive" - invoking `n/a - exempt: <category>` requires one of the 6 canonical tokens.
  - **Line-token case:** `var x = "a // b";` matches because of the spaced `//` token inside the string.
  - **Block-token case (introduced by the R5 no-whitespace fix for `code;/*tight*/`):** `var s = "code/*x*/";`, `<div title="x<!--y-->z"></div>`, and `$s = "a<#b#>c";` all flag because the block-token regex uses `\s*` (zero or more whitespace), so it matches inside string-literal content. The false-positive rate is bounded and acceptable.
- **Tight trailing line comments are NOT detected** (false-NEGATIVE). `return x; //done` and `SELECT 1 --note` return `false` because inline detection requires whitespace before AND after the token (or token at end-of-line). The leading `\s+` is intentional (avoids `://` URL false-positives); the gap is an accepted v1 ceiling backed by local review.
- **Multi-line docstrings counted at delimiter lines, NOT body lines.** Per-language detail:
  - **Python** `"""..."""` blocks: both the opening `"""` and closing `"""` register as comment sites (because `"""` is in the `py` token list and matches at either end). A 5-line docstring registers 2 audit-required sites, not 1 or 5.
  - **Elixir** `@moduledoc`/`@doc`/`@typedoc` blocks: only the `@`-prefixed opener line registers (the closing `"""` is NOT in the `ex`/`exs` token list). A 5-line `@moduledoc """..."""` block registers 1 site.
  - Body lines (between delimiters) are not counted in either case. The per-PR human review remains the backstop for multi-line docstring content.
- **`NONE` accepted as alias for `EMPTY_TREE`.** Both are recognized by `Test-AuditFile` for true root commits; `EMPTY_TREE` is preferred, `NONE` kept for backward compatibility.
- **Mid-file `#!/` and `#Requires -` directives still excluded.** The exclusions are content-prefix-based (`^#!/`, `^#Requires\s+-` for `.ps1`/`.psm1`), so they fire anywhere in a polyglot script. The exclusion is intentional; abuse is conspicuous in human PR review.
- **Spaced shebangs (`#! /bin/bash`) are NOT excluded.** `^#!/` requires no whitespace between `#!` and `/`; spaced forms are treated as regular comments. Real shebangs overwhelmingly use the no-space form.
- **Merge commits are skipped by the history walk.** `check-comment-audit.ps1` uses `git log --no-merges`, so merge commits are NOT individually audited. The merged feature commits carry their own audits; conflict-resolution that adds NEW comments should land in a follow-up feature commit.
- **Unknown file extensions silently skip comment detection.** `$ExtensionPatterns` covers ~50 common extensions but not niche ones (`.proto`, `.jsonc`, `.vue`, `.svelte`, `.astro`, `.zig`, `.nim`). Comments there generate no site. Fix per project: add the extension to `$ExtensionPatterns` (+ a regression test), or document it out-of-scope.
- **Catalog files are path-excluded (deliberate policy).** `Test-IsNewCommentLine` returns `$false` for `pattern-catalog.md`, the markdown under `pattern-catalog.sources/`, and the generated `HIGH-TIER-SLUGS.md` (a projection of the catalog): they enumerate comment tokens a flat regex cannot tell from real comments, so ANY real comment there is NOT audited (backstop: human review of the catalog, regeneration byte-identity for it). A non-markdown file under `pattern-catalog.sources/` is still audited.
- **Filenames with literal `"` / `\` / control characters are REJECTED (fail-closed).** The diff gates run `git -c core.quotePath=false diff`, so non-ASCII (UTF-8) filenames emit raw and ARE detected. A path with a literal `"`, `\`, tab, or newline is still C-quoted by git (`+++ "b/we\"ird.sql"`); rather than silently miss its comments, `Get-UnparseableDiffPaths` detects the quoted header and the gate fails closed with a "comment coverage cannot be verified" violation (rename the file to proceed). Pathological + conspicuous; the gate refuses rather than skips.
- **`commit_subject:` is presence-checked, not content-verified.** `Test-AuditFile` requires the line to exist and rejects template placeholders (`<.+>`), but does NOT compare it against the actual commit subject. An agent could write `commit_subject: x` and pass. The 72-char cap is advisory. Acceptable for v1 forcing-function purposes.

## Catalog enforcement

`pattern-catalog.md` slug `comment-necessity` (HIGH-tier) audits the same protocol at PR review time. Every NEW comment in the PR diff must carry a step-3 approval citation (via the ledger record) OR a valid exempt-category citation. Comments without either are catalog violations and surface as review-pass-only findings.

## Common failure modes

1. **Subjective trigger interpretation** - agent skips the protocol because "I didn't reach for the comment, the template/sub-agent did." The trigger is OBJECTIVE; if the comment is in the diff, the protocol applies.
2. **Writing the comment first, asking afterwards** - defeats the gate (the user is now reviewing a fait accompli rather than approving a proposal). The `ask_user` call MUST precede the `edit`.
3. **Inventing exempt categories at audit time** - only the categories enumerated above are valid. `approval_turn: n/a - exempt: it-was-obvious` is a violation.
4. **One `ask_user` per comment** - defeats batching, induces blanket approval. Always batch per-change.
5. **Sub-agent emitting comments directly** - the sub-agent prompt must instruct it to propose comments as suggestions in the return value, not introduce them in `edit` calls. Audit the sub-agent output on integration.
6. **Re-proposing after rejection** - one rejection → DROP. Do not bounce the same comment off the user multiple times.
7. **Hard-stopping in headless mode** - degraded mode is DROP-the-comment, never block-the-change.
8. **Asking `ask_user` to approve a categorically-banned comment** - a user "yes" cannot authorize what `csharp.instructions.md` flatly forbids. Drop without asking.

## Output

A diff containing only comments that either (a) passed the three-step protocol with documented step-3 approval, or (b) fall under a documented exempt category recorded on the step-2.6 ledger. Any other comment in the diff is a process violation and must be deleted before the commit.
