# Playbook: Post-PR-review phase

## Purpose

After a PR exists and review comments arrive, iterate on the comments. Verify each finding against the source before applying it. Route findings outside scope through `ask_user`. Propose an instructions-file delta after each fix to catch the same class of issue earlier next time.

Fires when a PR has been opened and either an automated reviewer (GitHub Copilot PR review, etc.) or a human has left comments.

## Hard gates (also in `AGENTS.md`)

- Each bot finding verified against source before applying / dismissing.
- Sub-agent findings outside scope routed via `ask_user`; never silently dropped.
- Instructions-file delta proposed for each fixed comment (project-agnostic).
- **Per-finding C2-status-enum audit emitted** at the end of the review pass (see step 6) — structured chat block listing each finding with its disposition (`fixed | routed-now | routed-deferred | dismissed-source-grounded`), the citation backing the disposition, and `subagent_ask_user_calls=0` confirmation.

## Intake questions

Bundle these in one prompt:

1. **Which PR?** (URL or repo + number — needed to fetch comments via `pull_request_read`.)
2. **Should I verify findings against source independently** (recommended), or trust the bot for stylistic ones (typos, casing) and only deep-verify the substantive ones?
3. **Triage depth** — address every comment in this session, or pick a subset (e.g. only "must-fix" / "blocking" / specific files)?
4. **Re-review strategy** — should I run the multi-model panel again after the fix round (recommended for non-trivial PRs), or trust the PR-author + reviewer iteration?

## Procedure

### 1. Fetch all PR comments

Pull all comments via `pull_request_read` (methods `get_review_comments`, `get_comments`, `get_reviews`, `get_check_runs`). Build a single list of distinct findings.

### 2. For each finding, verify against the source

GitHub Copilot's PR reviewer (and any external reviewer) is sometimes wrong — it lacks full context, can hallucinate symbol behavior, or propose fixes that would obviously break callers.

For each comment:

- Read the cited code AND the surrounding context (caller sites, interface definitions, related tests).
- Decide:
  - **(a) apply the fix** — the finding is correct.
  - **(b) push back** with a one-line justification on the PR thread and resolve as "won't fix" — the finding is wrong or doesn't apply.
  - **(c) ask the user** when ambiguous.

Do NOT silently apply changes you cannot independently justify.

### 3. Run the multi-model reviewer panel in parallel — same parallel rule as `post-code-change.md`

Same default panel (`claude-opus-4.7-xhigh` + `gpt-5.5` + `gpt-5.3-codex` + rubber-duck), same parallel-launch rule, same anti-anchoring rules.

For PR-review work specifically, instruct the panel to:

- Independently re-read the PR diff (don't trust your summary of it).
- Check whether the bot findings being applied actually resolve the cited issue and don't introduce a regression.
- Flag any new findings of their own that the bot missed.

### 4. Propose an instructions-file delta after each fix

Once a PR comment is resolved, briefly identify what could be added to the appropriate instructions file (the always-loaded `AGENTS.md` core, or the matching topic file under `.github/instructions/`) to catch the same class of issue earlier (in self-review or by the multi-model code-review pass).

If something fits, propose the delta in your summary. Skip silently if the comment is genuinely one-off (typo, taste, etc.).

### 5. Instructions-file additions must stay project-agnostic

These instructions apply to *every* project the user works on. Any rule, example, code snippet, type name, field name, file path, error message, or "examples that bit us" anecdote you add must be **generic** — describe the *class* of issue and the *shape* of the fix without naming a real project's symbols, modules, table names, schemas, or domain concepts.

Use illustrative placeholder names (`UserSessionCache`, `customerName`, `LoggingMiddleware`) or describe the structure abstractly ("a composite key over `(LocalId, SubId)`"). When you catch yourself about to write a real type name from the current repo, rename it.

Same applies to the rubber-duck or code-review prompts you're proposing as templates — strip project specifics before promoting them into an instructions file.

### 6. Audit before declaring done — evidence-gate output

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

- `fixed` — finding addressed by an edit in the response commit. **Citation**: `file:line` of the change.
- `routed-now` — finding routed via `ask_user`; user decided in this turn. **Citation**: `ask_user` call ref + user decision summary.
- `routed-deferred` — finding deferred to a future PR / session / external work item. **Citation**: issue tracker URL / session note path / external record id. NOT acceptable: deferral with no external record.
- `dismissed-source-grounded` — finding refuted by evidence from source. **Citation**: source location (`file:line`, doc URL, RFC, ADR) refuting the finding. NOT acceptable: *"out of scope per reviewer"* without source grounding.

### 7. Apply pre-PR-push rules to the review-response push

The review-response push is itself another push that may need pre-PR-push handling. Per `pre-pr-push/when-to-re-run-sweep.md`:

- Ordinary review-response amends: per-commit audit only, no branch-wide sweep re-run.
- Review-response amend that introduces a cross-boundary rename: widen the amend OR ask user.
- Conflict resolution / new files / scope expansion as part of the review response: re-run the branch-wide sweep.

## Sub-agent findings outside scope

Per the *Pre-existing issues / `ask_user` is mandatory* cross-cutting rule in `AGENTS.md` §1: findings surfaced by sub-agents (rubber-duck, code-review, etc.) that are tangentially related but outside the current PR's scope must be routed via `ask_user`. Do NOT silently expand scope to fix them, and do NOT silently drop them.

Briefly summarize each finding (1 line each), state your recommendation, and use `ask_user` to choose:

- Address now in this PR (expanding scope — get explicit approval).
- Defer to a follow-up (record externally — session note, issue, tracker — never as a `TODO` / `FIXME` / `HACK` comment in code).
- Dismiss with reason.

`ask_user` is mandatory, not optional. Mentioning a sub-agent finding inside your final review summary, the diff walkthrough, the "ready to push" message, or any other prose without a paired `ask_user` call counts as silently dropping it.

Even findings the reviewer itself labels "out of scope," "pre-existing," "not introduced by this change," or "low severity" must go through `ask_user` — those labels are the reviewer's opinion, not your decision to make on the user's behalf.

## After all comments are resolved

Push the review-response commit per `pre-commit.md` (and `pre-pr-push.md` if conditions warrant a re-sweep). Wait for the next round of review or for the PR to merge.
