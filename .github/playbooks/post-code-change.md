# Playbook: Post-code-change phase

## Purpose

After implementation, run the import / using hygiene pass, the multi-model reviewer panel, the verify-the-fix-actually-fixed-it check, and the affected builds + tests. Fires immediately after code edits land, before showing the diff to the user. Output: a green build with all reviewers in agreement and the diagnosis-verifying metric / test passing.

## Hard gates (also in `AGENTS.md` — repeated here for context)

- Touched-file imports / usings sorted and unused removed.
- Multi-model reviewer panel run **in parallel**; consensus reached or all dissents addressed.
- Diagnosis-verifying benchmark / test re-run; metric moved or test passes.
- Affected builds + tests pass.

## Intake questions

Bundle these in one prompt:

1. Should I run the **default 4-reviewer panel**, or add reviewers? (Default panel below. Add reviewers liberally for risky / cross-cutting / unfamiliar-area changes — there's no "too many reviewers".)
2. Any specific blind spots you want the reviewers to focus on? (e.g. concurrency safety, allocation hot paths, naming consistency across an interface chain)
3. **Perf work only:** confirm the benchmark from the pre-implementation phase is still the one I should re-run.

## Procedure

### 1. Imports / usings hygiene

Sort and clean up imports / usings on every touched file before sending the diff for review. Mandatory hygiene step on any file added, modified, or moved — sort imports / usings into the project's canonical order and remove unused ones.

Use the language's ecosystem tooling for the whole touched set in one pass:

| Language | Command |
| --- | --- |
| .NET | `dotnet format --severity info --diagnostics IDE0005 IDE0065` (unused / misplaced usings) plus a sort pass |
| TS / JS | `eslint --fix` plus the editor's "Organize Imports" |
| Python | `ruff check --select I --fix` or `isort` |
| Java / Kotlin | IntelliJ "Optimize Imports" |

Never commit a file with unsorted, duplicated, or unused imports — reviewers always flag them, and the noise hides real issues in the diff.

### 2. Multi-model reviewer panel — run all in parallel

The user has no token-budget caps on this work, so always launch the full reviewer panel **in parallel** (background agents) rather than serially. Iterate, re-running the panel after each fix round, until **all models agree** with no substantive findings.

**Default reviewer panel** (launch all of these as background agents in the **same response** — three as `code-review`, one as `rubber-duck`; at least one model from each family):

- `claude-opus-4.7-xhigh` (default Claude family, extra-high reasoning) — `code-review`
- `gpt-5.5` (OpenAI family, premium reasoning) — `code-review`
- `gpt-5.3-codex` (OpenAI family, codex-tuned — different perspective from gpt-5.5) — `code-review`
- **rubber-duck** agent (independent critique angle — not a code-review reviewer per se, but provides design / blind-spot feedback that complements line-level review)

**Add reviewers liberally** when a change is risky, cross-cutting, or touches an unfamiliar area: `claude-sonnet-4.6` for a faster second-Claude opinion, `gpt-5.5` re-run with a different prompt framing, etc. There is no "too many reviewers" — parallel agents are cheap and the marginal cost of one more independent reading is approximately zero.

**Do NOT serialize the panel** ("run Claude first, then if it finds nothing run GPT") — that wastes wall-clock time and lets early reviewer framing leak into your assessment of later reviews. Launch all reviewers in one tool-call batch, wait for completions, then synthesize.

### 3. Anti-anchoring rules for reviewer prompts

Do not anchor reviewers on your own framing. Prompts must instruct the reviewer to treat the description of the fix as a hypothesis and independently read the affected types and call sites.

Specific reviewer-prompt requirements (from recurring failure modes in past PR history):

- **State predicates** (see `AGENTS.md` §3.7): if the diff introduces a predicate over a type's state (`IsEmpty`, `IsDefault`, equality / match check), the reviewer must open that type's source and enumerate every member before accepting the predicate as complete.
- **Cross-boundary parameter / property names** (see `AGENTS.md` §3.6 "Defaults and Consistency"): if the diff introduces or renames a parameter that crosses an interface / implementation boundary, the reviewer must enumerate every signature in the chain — interface, abstract base, every implementation, every caller, every lambda that closes over it — and verify the name is identical at every layer.
- **Literals-in-collections** (see `AGENTS.md` §3.10): if the diff adds or modifies a collection whose members reflect literals used elsewhere in the codebase, the reviewer must open every site that produces those literals and verify each one references the collection's members rather than re-typing the literal.

### 4. Synthesize and iterate

After all reviewers complete, briefly summarize cross-model agreement. Iterate the panel after each fix round until no substantive findings remain. **Same parallel-panel rule applies to PR reviews** (post-PR-review playbook): when running `pr-review` after a PR exists, launch the same panel in parallel.

Route any sub-agent finding outside the immediate scope through `ask_user` (per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule in `AGENTS.md` §1): address now / defer to a follow-up (record externally — session note, issue, tracker — never as TODO comment) / dismiss with reason.

### 5. Verify the fix actually fixed it

The benchmark / test from `pre-implementation.md` must show the expected delta (perf) or pass (functional). If the metric didn't move, the change is a no-op — revert and re-diagnose. Do not paper over a no-op fix with reviewer agreement.

### 6. Run affected builds and tests

All must pass before proceeding to `pre-commit.md`. If a test fails:

- If the test is a regression caused by your change: fix it (return to step 2).
- If the test was failing before your change (pre-existing): route via `ask_user` per the *Pre-existing issues* cross-cutting rule in `AGENTS.md` §1 — never silently fix it as part of this change.

### 7. Audit before declaring done

Immediately before reporting "ready for diff review" / "all reviewers agree" / "no remaining issues," re-read every sub-agent response from this task and confirm that every distinct finding (regardless of severity or scope label) has either (a) been fixed in the diff, or (b) been routed through an `ask_user` call this turn. If any finding is in neither bucket, stop and route it through `ask_user` first.

## Next phase

Once builds + tests + reviewer consensus + verification all clear, proceed to `pre-commit.md`.
