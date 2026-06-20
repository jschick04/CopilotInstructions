# Playbook: Post-PR-review phase
<!-- read-receipt-token: 3ce75448 -->

## Purpose

After a PR exists and review comments arrive, iterate on the comments. Verify each finding against the source before applying it. Route findings outside scope through `ask_user`. Propose an instructions-file delta after each fix to catch the same class of issue earlier next time.

Fires when a PR has been opened and either an automated reviewer (GitHub Copilot PR review, etc.) or a human has left comments.

## Hard gates (also in `AGENTS.md`)

- Each bot finding verified against source before applying / dismissing.
- Sub-agent findings outside scope routed via `ask_user`; never silently dropped.
- Instructions-file delta proposed for each fixed comment (project-agnostic).
- **Per-finding C2-status-enum audit emitted** at the end of the review pass (see step 6) - structured chat block listing each finding with its disposition (`fixed | routed-now | routed-deferred | dismissed-source-grounded`), the citation backing the disposition, and `subagent_ask_user_calls=0` confirmation.

## Intake questions

Bundle these in one prompt:

1. **Which PR?** (URL or repo + number - needed to fetch comments via `pull_request_read`.)
2. **Should I verify findings against source independently** (recommended), or trust the bot for stylistic ones (typos, casing) and only deep-verify the substantive ones?
3. **Triage depth** - address every comment in this session, or pick a subset (e.g. only "must-fix" / "blocking" / specific files)?
4. **Re-review strategy** - should I run the multi-model panel again after the fix round (recommended for non-trivial PRs), or trust the PR-author + reviewer iteration?

## Procedure

### 1. Fetch all PR comments

Pull all comments via `pull_request_read` (methods `get_review_comments`, `get_comments`, `get_reviews`, `get_check_runs`). Build a single list of distinct findings.

### 2. For each finding, verify against the source

GitHub Copilot's PR reviewer (and any external reviewer) is sometimes wrong - it lacks full context, can hallucinate symbol behavior, or propose fixes that would obviously break callers.

For each comment:

- Read the cited code AND the surrounding context (caller sites, interface definitions, related tests).
- Decide:
  - **(a) apply the fix** - the finding is correct.
  - **(b) push back** with a one-line justification on the PR thread and resolve as "won't fix" - the finding is wrong or doesn't apply.
  - **(c) ask the user** when ambiguous.

Do NOT silently apply changes you cannot independently justify.

#### 2.1. Doc-comment / XML-doc accuracy findings - comment-necessity audit first

Before applying a bot's suggested doc-comment rewording or accuracy fix, run the comment-necessity audit per the `pattern-catalog.md` `comment-necessity` slug (and per `AGENTS.md` §3.1 comments policy). The audit short-circuits the most common bot-driven doc-iteration spiral (bot flags wording → reviewer rewords → bot flags the new wording → reviewer re-rewords) by deleting non-load-bearing comments outright rather than wordsmithing them.

Decision tree:

- **(a) Comment is NON-LOAD-BEARING** (narrates what the code does, restates type behavior, references panel artifacts / round numbers, duplicates an XML method summary with an inline comment, multi-line `<remarks>` on an internal type, or restates a contract that the method / test / type NAME already conveys): **delete the comment entirely**; `status=fixed` citing the comment-necessity audit. Do NOT wordsmith.
- **(b) Comment IS LOAD-BEARING** (captures a genuinely non-obvious concurrency invariant, race-safety rationale, BCL quirk with version citation, FP-override citation, spec/standard reference, or other *why* the code cannot self-document via naming or extraction) AND the bot's accuracy concern is correct: apply minimal fix to bring the comment in line with the code; `status=fixed`.
- **(c) Bot's accuracy concern is WRONG** (the comment IS accurate, the bot misread): `status=dismissed-source-grounded` citing the source contradicting the bot's claim.

The mechanical default is **always run the audit first**, never "default to dismiss". The audit's outcome determines the disposition.

### 2.5. Self-similarity sweep BEFORE applying the fix (HARD GATE)

Bot reviewers consistently flag only ONE instance of a recurring pattern in a diff, even when 2+ sister sites have the same shape. The catalog's `multi-model-review/pr-creation-mirror-prompt.md` already mandates a recurring-pattern sweep during the §2D panel, but bot findings on existing PRs bypass that gate: the fix iteration goes directly from "bot flagged site X" → "fix site X" → "amend" → "push", and the next round of bot review re-flags the pattern at site Y, then site Z, then site W.

Before applying any bot fix that matches a known recurring pattern (entry-CT-throw, callback-defensive-catch, lock-syntax convention, doc-staleness, comment-extraction-drift, snapshot-before-mutation, etc.) OR introduces a new pattern shape, the agent MUST emit a one-line-per-site sweep report enumerating every site in the diff that matches the pattern. Format:

```
Self-similarity sweep for <pattern>: <N> sites found, <K> already-fixed, <J> need-fix.
  - file.cs:line - <status: bot-flagged | sister-site-found | already-applies | not-applicable + 1-line rationale>
  - file2.cs:line - ...
```

This block MUST be emitted in the same turn as the proposed fix, BEFORE the `ask_user` commit-approval gate fires. If the sweep finds 0 sister sites, the report is still emitted with `0 sister sites; pattern is single-instance in this diff` - explicit-by-design, not implied. Skipping the sweep on the rationale "the bot flagged only one site so probably just one site needs fixing" is a process violation tracked under `self-similarity-sweep-incomplete-after-bot-finding` in `pr-quality-gate/data/panel-misses.csv`.

**Pattern recognition primer**: the most common recurring shapes bot reviewers flag in this corpus are: (a) entry-`ThrowIfCancellationRequested` missing at one method of N CT-accepting methods; (b) defensive catch missing at one callback of N callbacks; (c) lock convention mismatch at some sites but not others; (d) XML doc staleness when interface gets new members; (e) comment-vs-code drift after method extraction. Always sweep for these patterns regardless of which single instance the bot cited.

### 3. Run the multi-model reviewer panel in parallel - same parallel rule as `post-code-change.md`

Same default panel as `post-code-change.md` §3 (profile-aware: full = the 6-reviewer heavy slate `heavy-claude-xhigh` + `heavy-gpt-premium` + `heavy-gpt-codex` + `heavy-gpt-cross-version` + `heavy-gemini-premium` + rubber-duck at `heavy-claude-standard`; lite = 3 cross-family light-tier; tier -> model via `current-model-registry.md`), same parallel-launch rule, same anti-anchoring rules.

For PR-review work specifically, instruct the panel to:

- Independently re-read the PR diff (don't trust your summary of it).
- Check whether the bot findings being applied actually resolve the cited issue and don't introduce a regression.
- Flag any new findings of their own that the bot missed.

**Panel scope = the whole branch, re-invoked end-to-end on every review-response push.** The panel reviews the FULL whole-branch diff `panelBaseSha..HEAD` (per `pre-pr-creation-review.md` Step 2 default-full policy), NOT just the review-response fix diff. A review-response push is a pre-PR update op: re-invoke the §2D `pre-pr-creation-review.md` panel END-TO-END - including its Step 7 `PRE-PR REVIEW COVERAGE` emission with the `panel-coverage` field - so whole-branch coverage is provably re-attested for THIS push. The §6 `PR review audit` block below is findings-only (no base..head / coverage scope) and does NOT satisfy that §2D COVERAGE requirement. Carry-forward of prior dispositions is allowed only as the explicit user-authorized exception recorded in `panel-coverage` (default is a full re-read).

### 4. Propose an instructions-file delta after each fix

Once a PR comment is resolved, briefly identify what could be added to the appropriate instructions file (the always-loaded `AGENTS.md` core, or the matching topic file under `.github/instructions/`) to catch the same class of issue earlier (in self-review or by the multi-model code-review pass).

If something fits, propose the delta in your summary. Skip silently if the comment is genuinely one-off (typo, taste, etc.).

### 4.5. RCA the miss + (opt-in) file a process-gap issue

A bot/human finding that our OWN process should have caught is a panel/gate MISS, not just a code fix. For each such finding - status `fixed`, `routed-now`, OR `routed-deferred` (exclude ONLY `dismissed-source-grounded`, the bot-was-wrong case) - that is generalizable beyond this one site:

1. **RCA (forcing function).** Name the SPECIFIC existing-or-derivable coverage that should have surfaced it - a `pattern-catalog` slug (and its `discovery_query`), a deterministic gate, or the §2D panel prompt - and WHY it slipped (slug gap, missing slug, panel anti-anchoring miss, scope-not-whole-branch, etc.). If NO such gate / slug / prompt can be named, the finding is a genuine one-off (typo / taste) and is EXEMPT - no RCA issue.
2. **ask_user (opt-in-to-file).** Present the one-line RCA and propose filing a tracking issue in the instruction-set repo. The user approves or declines. On decline OR no response, do NOT file - log to `panel-misses.csv` only (per Step 2.5 / the anti-recidivism ledger). NEVER auto-file.
3. **On approve.** `gh issue create --repo <instruction-set-repo> --title "<generic miss-class>" --body "<RCA + proposed fix>"` - resolve `<instruction-set-repo>` from the instruction-set clone's `origin` remote (where these playbooks live), NOT the current project repo: the issue MUST land in the governance repo, never the consuming project. Use a GENERIC, no-project-specifics title / body per §5 (the same project-agnostic rule that governs instruction deltas) - describe the CLASS of miss and the shape of the gate / slug fix, never a real symbol / path / PR number. Suggested label: `panel-miss`.
4. **Always** record the miss in the instruction-set repo's `.github/pr-quality-gate/data/panel-misses.csv` (the governance repo, NOT the consuming project) regardless of the ask_user outcome - the CSV is the local anti-recidivism ledger; the issue (when filed) is the durable, actionable tracker.

**Evidence-gate interaction (§6):** the process-gap issue is a DISTINCT meta-entry, NOT a change to the original finding's own disposition. A `fixed` finding stays `fixed`; the miss is logged as a separate `routed-deferred` meta-row whose external record is the issue URL when one is filed, OR - when the user DECLINES / does not respond (no issue) - the `panel-misses.csv` entry (file path + the appended row). Both satisfy §6's "no deferral without an external record". Do not downgrade the original finding's status because a process-gap meta-row was logged.

### 5. Instructions-file additions must stay project-agnostic

These instructions apply to *every* project the user works on. Any rule, example, code snippet, type name, field name, file path, error message, or "examples that bit us" anecdote you add must be **generic** - describe the *class* of issue and the *shape* of the fix without naming a real project's symbols, modules, table names, schemas, or domain concepts.

Use illustrative placeholder names (`UserSessionCache`, `customerName`, `LoggingMiddleware`) or describe the structure abstractly ("a composite key over `(LocalId, SubId)`"). When you catch yourself about to write a real type name from the current repo, rename it.

Same applies to the rubber-duck or code-review prompts you're proposing as templates - strip project specifics before promoting them into an instructions file.

### 6. Audit before declaring done - evidence-gate output

Re-read every sub-agent response and PR comment in this iteration. Confirm every distinct finding has either (a) been fixed in the diff, (b) been pushed back on with justification, or (c) been routed through an `ask_user` call this turn.

If any finding is in none of those buckets, route it via `ask_user` before reporting "ready to push the review-response commit".

**MANDATORY EVIDENCE-GATE OUTPUT** (same C2 status enum as `multi-model-review/evidence-gate-spec.md` *C2 findings audit format*). Emit before claiming ready:

```
PR review audit: <N> findings total this iteration.
- <source bot / reviewer + comment id>: <finding summary>: status=<fixed | routed-now | routed-deferred | dismissed-source-grounded>: <citation per status>.
- (one bullet per finding)
- subagent_ask_user_calls=0 (orchestrator-only routing verified per AGENTS.md cross-cutting rule).
```

**Status definitions** (canonical in `multi-model-review/evidence-gate-spec.md`; reproduced here for context):

- `fixed` - finding addressed by an edit in the response commit. **Citation**: `file:line` of the change.
- `routed-now` - finding routed via `ask_user`; user decided in this turn. **Citation**: `ask_user` call ref + user decision summary.
- `routed-deferred` - finding deferred to a future PR / session / external work item. **Citation**: issue tracker URL / session note path / external record id. NOT acceptable: deferral with no external record.
- `dismissed-source-grounded` - finding refuted by evidence from source. **Citation**: source location (`file:line`, doc URL, RFC, ADR) refuting the finding. NOT acceptable: *"out of scope per reviewer"* without source grounding.

### 7. Apply pre-PR-push rules to the review-response push

The review-response push is itself another push that may need pre-PR-push handling.

> **The when-to-re-run-sweep rules below govern the mechanical branch-wide SWEEP (rename / least-privilege / VSA) ONLY - NOT the §2D multi-model panel.** The multi-model panel's SCOPE is the WHOLE branch on every review-response push (default full re-read; carry-forward only as the §2D-authorized `panel-coverage` exception), independent of the sweep decision (per §3 above + `pre-pr-creation-review.md`); a "per-commit audit only" sweep outcome never bounds the panel's whole-branch scope.

For the mechanical sweep, per `pre-pr-push/when-to-re-run-sweep.md`:

- Ordinary review-response amends: per-commit audit only, no branch-wide sweep re-run.
- Review-response amend that introduces a cross-boundary rename: widen the amend OR ask user.
- Conflict resolution / new files / scope expansion as part of the review response: re-run the branch-wide sweep.

## Sub-agent findings outside scope

Per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule in `AGENTS.md` §1: findings surfaced by sub-agents (rubber-duck, code-review, etc.) that are tangentially related but outside the current PR's scope must be routed via `ask_user`. Do NOT silently expand scope to fix them, and do NOT silently drop them.

Briefly summarize each finding (1 line each), state your recommendation, and use `ask_user` to choose:

- Address now in this PR (expanding scope - get explicit approval).
- Defer to a follow-up (record externally - session note, issue, tracker - never as a `TODO` / `FIXME` / `HACK` comment in code).
- Dismiss with reason.

`ask_user` is mandatory, not optional. Mentioning a sub-agent finding inside your final review summary, the diff walkthrough, the "ready to push" message, or any other prose without a paired `ask_user` call counts as silently dropping it.

Even findings the reviewer itself labels "out of scope," "pre-existing," "not introduced by this change," or "low severity" must go through `ask_user` - those labels are the reviewer's opinion, not your decision to make on the user's behalf.

## After all comments are resolved

Push the review-response commit per `pre-commit.md` (and `pre-pr-push.md` if conditions warrant a re-sweep). Wait for the next round of review or for the PR to merge.
