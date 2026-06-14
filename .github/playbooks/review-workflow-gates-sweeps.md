# Review Workflow Gates - Post-change Sweeps

Companion to `review-workflow-gates.md` (post-change sweep, ledger, DRY, and pre-PR-creation gates).

## 2. PR review comment root-cause analysis

### The problem this solves

Surface-level fixes that leave the underlying pattern in place cause repeat findings across review rounds.

### Hard gate

Every PR review comment must be analyzed through this checklist before marking it resolved:

1. **Root cause identified.** What pattern, assumption, or gap caused the issue? Not "this line was wrong" but "this type of line is consistently missed because X."
2. **Fix addresses root cause.** The change prevents the issue from recurring, not just from appearing at this specific location.
3. **Similar patterns swept.** Search the rest of the diff (and ideally the rest of the changed files) for the same pattern. Fix all instances in one pass, not one at a time across review rounds.
4. **Instructions updated.** If the comment reveals a gap in the instruction set (a pattern the pre-implementation panel should have caught but didn't), propose an instruction-file delta:
   - A new sweep pattern in `post-code-change.md`
   - A new checklist item in the relevant playbook
   - A new hard gate if the issue class is severe enough
5. **Repeat-finding test.** Before re-requesting review, mentally simulate: "If the same reviewer runs the same review pass, will they find the same class of issue anywhere in the diff?" If yes, the fix is incomplete.

### Repeat findings are process failures

When the same issue class recurs across review rounds:
1. Treat as evidence the pre-implementation panel missed something.
2. Identify why (pattern missing from sweep list? angle too narrow? rubber-duck skipped?).
3. Feed back: update instructions, add sweep pattern, or adjust panel angles.

---

## 2A. Prior-PR-review sweep (HARD GATE)

### The problem

PRs frequently get the same class of review comment that prior PRs received. Fetching prior review patterns and sweeping the current diff prevents repeat findings.

### Procedure

Two-scope sweep  -  current branch + recent repo PRs:

**Scope A  -  Current branch PR thread:**
1. If the current branch already has an open PR, fetch all review comments (both inline and review-body) from that PR via `gh api repos/<owner>/<repo>/pulls/<n>/comments` and `gh api repos/<owner>/<repo>/pulls/<n>/reviews`.
2. Extract the pattern from each comment  -  not the specific file/line, but the class of issue (e.g. "empty CompareExchange guard", "ProviderDbContext 2-arg overload defaults ensureCreated=true", "HTML disabled on span tag").
3. Sweep the current uncommitted/staged diff for each pattern.

**Scope B  -  Recent repo PRs:**
1. Fetch the last 10 merged PRs in the repo: `gh pr list --state merged --limit 10 --json number,title`.
2. For each PR, fetch review comments (bot + human) via the same API calls.
3. Extract patterns (same as Scope A).
4. Sweep the current diff for each pattern.

**Output requirement:**

Emit a one-line-per-pattern sweep report before showing the diff to the user:

```
Prior-PR-review sweep: ran, M patterns checked, N findings.
  - <pattern description from PR #X>: matches/no matches
  - ...
```

### When this gate fires

- **`post-code-change.md`**  -  every commit-bound change runs the sweep before the diff is shown.
- **`pre-pr-push.md`**  -  every push intended for review runs the sweep against the full branch diff (`git diff <base>..HEAD`).

### Skip conditions

This sweep may be skipped when:
- The repo has no prior merged PRs (e.g. brand-new repo)  -  skip Scope B; Scope A still applies if a current PR exists.
- The current change has no production-code edits (pure docs / pure CI config change with no code patterns to match)  -  explicitly document this fact.

In every other case, the sweep is mandatory. Silent skip ("I don't think any prior patterns apply") is the failure mode this gate exists to prevent.

### Why both scopes

- **Scope A catches re-pushed fixes**  -  same PR thread, prior round flagged X, fix-up commit re-introduces X elsewhere. Most common in iterative review cycles.
- **Scope B catches "patterns the team has already learned about"**  -  comments from prior PRs reflect what reviewers care about; the current PR should not re-trigger them.

### Cost containment

Fetching review comments for 10 PRs is ~20 API calls. Use `gh api --paginate` only when a PR has >30 comments. Cache the extracted pattern list in the session todo store with a TTL so re-runs within the same session don't refetch.

---

## 2B. Post-code-change ledger (HARD GATE)

### The problem

The pre-implementation phase has a single named certification block (`PANEL CONVERGED` per §1A) whose presence is enforced by §1B  -  implementation tools are forbidden until it appears. The post-code-change phase has no analogous block. Multiple hard gates exist in `AGENTS.md` (`post-code-change.md` step 2.5 sweep, §2A prior-PR-review sweep, touched-file LPA, hygiene cleanup, comment audit, build, tests), but each gate enforces only its own one-liner. There is no single attestation that **all** of them ran for a given commit, so a `git add` / `git commit` pair can execute with one or two gates having silently skipped  -  and the user has no easy way to detect it after the fact.

This is the failure mode that landed on this branch: `PANEL CONVERGED` was emitted once for the plan; subsequent implementation commits proceeded with build + tests + diff-approval but **without** the §2.5 sweep, §2A sweep, LPA, or comment audit running. The user had previously waived the diff-approval `ask_user` step on an earlier commit; that single-step waiver was implicitly carried forward and treated as a blanket post-code-change waiver on later commits.

### Rule

Before ANY `git commit` (incl. `--amend`, or a `git stash pop` / cherry-pick / rebase resolving into a commit), the agent MUST emit a literal `POST-CODE-CHANGE LEDGER` block in the **current turn**. The block enumerates the status of every post-code-change gate that applies to the staged content. Without the ledger, the commit is forbidden  -  extending §1B's hard-stop list to cover the commit boundary, not just the pre-implementation boundary. The user stages code; the agent stages only gate artifacts.

### Ledger format

```
POST-CODE-CHANGE LEDGER
  commit-subject: <one-line subject the agent will use for git commit>
  files-touched: <count + brief shape, e.g. "21 (370+/0-)">
  profile: <full|lite|full-default>
  gates:
    hygiene-cleanup: <ran | N/A: reason>
    touched-file-LPA: <ran (N findings, K unjustified) | N/A: reason>
    vsa-audit: <ran (N placements checked, K misplaced) | N/A: no added/moved/renamed file, no new top-level type in an existing file, no multi-type file introduced, no root-level placement change>
    emdash-scan: <ran, clean | ran, N replaced | N/A: no text changes>
    recurring-pattern-sweep: <ran, N findings>
      - <pattern>: <N matches | no matches>
      - ...
    prior-PR-review-sweep: <ran, M patterns checked, N findings | N/A: no prior merged PRs / no production-code edits>
      - <pattern from PR #X>: <matches | no matches>
      - ...
    dry-audit: <ran, N duplications, K refactored, J waived | N/A: reason>
      - <pattern shape>: <file:line, file:line, ...> → <refactored to <abstraction> | waived ("<user quote>")>
      - ...
    post-code-change-panel: <ran, unanimous | N/A: reason | user-waived: "<quote>">
    intent-driven-testing-audit: <ran: prospective | ran: retrospective | N/A: <reason>>
      # Enforced by catalog rule `intent-driven-testing-required-on-test-or-SUT-delta` (HIGH).
      # Fires when diff contains EITHER (a) NEW or modified test files OR (b) ANY production-source
      # modification that changes the SUT surface: new exported member, signature change, NEW
      # conditional branch (if/switch/?:/when), new state-mutating statement, new method declaration
      # (public OR private), new error-handling branch (try/catch/throw), or new state-transition.
      # `N/A` reason MUST cite a specific carve-out from `intent-driven-testing.md`: rename-only
      # delta (test body byte-equivalent before/after), mechanical-port commit per §3.4, auto-generated
      # test files, pure whitespace/comment/formatting change, pure deletion. Bare `N/A` or
      # `N/A: private-only SUT delta` is NOT a valid carve-out (private branches still need test
      # coverage per §3.4 Direction B).
    delta-g-sweeps: <ran, N patterns swept, M sites enumerated | N/A: reason>
      # Format and semantics defined in `multi-model-review/pr-creation-mirror-prompt.md` Delta K
      # (status enum, evidence/rationale rules, branch_new_files_verified format, falsifiability).
      # Unlike other §2B rows (single-line sub-bullets), `delta-g-sweeps:` uses a richer nested
      # sub-block per pattern. Future grammar-tightening passes must preserve this nesting;
      # falsifiability depends on it.
      - pattern: <slug; lowercase-hyphenated; e.g. "js-import-jsexception-wrap">
        discovery_query: <exact command the agent ran; reviewer can re-run and diff>
        sites:
          - path: <relative path>
            status: applied | already-applies | not-applicable
            evidence: <file:line-range>     # REQUIRED for applied + already-applies; cites
                                             #   the exact line range where P is present at HEAD
            rationale: <one line>            # REQUIRED for not-applicable; (a) code property
                                             #   verifiable from the cited file OR (b) repo invariant
        branch_new_files_verified: yes: merge-base <SHA8>
    pre-impl-trigger-detections:
      # Cycle-3 (`pre-implementation.md` G6). Mirrors G6 chat-visible `trigger-detected-<playbook>:`
      # lines into the LEDGER. Each cycle-3-scope playbook gets one line; this is the audit anchor
      # for OFFERED-class rules 6/7/8/10/11 (silent-downgrade-to-`not-applicable` bypass closure).
      # Updated by G6 re-entry per `pre-implementation.md` if scope changes mid-implementation.
      implementation-planning: <yes | no>
      library-restructure: <yes | no>
      design-exploration: <yes | no>
      performance-comparison: <yes | no>
      scope-planning: <yes | no>
      system-framing: <yes | no>
      project-vocabulary: <yes | no>
    pre-impl-playbook-decisions:
      # Cycle-3 (`pre-implementation.md` G6). Mirrors G6 chat-visible `playbook-decision-<playbook>:`
      # lines into the LEDGER. Enforced by catalog rules 2, 3, 4, 6, 7, 8, 10, 11, 12, 13.
      #
      # **Allowed decision values per playbook class:**
      # - REQUIRED-decision-recorded class (implementation-planning, library-restructure):
      #   VALID = {invoked | required-but-skipped: "<safety-critical re-confirmation per User-skip policy>" | not-required-trigger-not-detected}
      #   INVALID = {offered-and-declined, not-applicable}: these silently bypass the required gate
      #   The `not-required-trigger-not-detected` sentinel is the canonical value when G6 emitted
      #   `trigger-detected: no` (preserves fixed cardinality without omission contradiction).
      # - OFFERED class (design-exploration, performance-comparison, scope-planning, system-framing, project-vocabulary):
      #   VALID when trigger-detected: yes = {invoked | offered-and-declined: "<quote>" | required-but-skipped: "<reason>"}
      #   VALID when trigger-detected: no = {not-applicable}
      #   INVALID when trigger-detected: yes = {not-applicable} (silent-downgrade bypass)
      #
      # User-quoted values use double-quoted YAML strings (RFC YAML) to handle `: ` and special chars
      # in user quotes. Example: `offered-and-declined: "user said 'this is a simple bump'"`
      implementation-planning: <invoked | required-but-skipped: "<re-confirmation>" | not-required-trigger-not-detected>    # REQUIRED class
      library-restructure: <invoked | required-but-skipped: "<re-confirmation>" | not-required-trigger-not-detected>        # REQUIRED class
      design-exploration: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      performance-comparison: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      scope-planning: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      system-framing: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
      project-vocabulary: <invoked | offered-and-declined: "<quote>" | not-applicable | required-but-skipped: "<reason>">
    playbook-invocations:
      # Cycle-3. Evidence each playbook actually ran during implementation. Scope: ONLY the 4
      # playbooks that have a corresponding `pre-impl-playbook-decisions` entry AND produce
      # implementation-phase artifacts. intent-driven-testing-prospective is enforced separately
      # by cycle-2 rule `intent-driven-testing-required-on-test-or-SUT-delta` and is NOT in
      # cycle-3 scope. The 3 decision-only playbooks (scope-planning, system-framing,
      # project-vocabulary) have NO implementation evidence: their decision-line IS the evidence
      # (rules 8/10/11 check the decision sub-block directly).
      implementation-planning: <ran (artifact-path:line) | N/A: <reason>>
      library-restructure: <ran (artifact-path:line) | N/A: <reason>>
      design-exploration: <ran (prototypes/<name>/ citation) | N/A: <reason>>
      performance-comparison: <ran (benchmark citation) | N/A: <reason>>
    comment-audit-§3.1: <ran | N/A: no comments touched | failed: <site list of file:line bullets with invalid/missing approval_turn>>
    build: <passed | failed: ...>
    tests: <passed, N/total | failed: ...>
    diff-shown: <yes (ask_user turn ...) | user-waived: "<quote>">
    commit-message-approved: <PENDING | yes (ask_user turn ...)>
```

Each line is mandatory. If a gate is not applicable, the entry MUST say `N/A: <reason>`, not blank, not omitted, not "skipped". The `profile` field records the active profile (from the loaded `active-profile.instructions.md`; `full-default` if none) and MUST match the `PRE-COMMIT GATE PASSED` and `PANEL CONVERGED` copies.

### Chat-emission form (compressed KV v1)

Chat emits the LEDGER in this frozen grammar; the schema above is canonical/audit-file form. Keys are the forcing function; detail is recoverable.

```
POST-CODE-CHANGE LEDGER (KV v1)
core|profile=<full|lite|full-default>|commit=<json-string>|files=<N>(+<added>/-<removed>)
gates|hygiene=<ran|na:CODE>|lpa=<ran:N/K|na:CODE>|vsa=<ran:N/K|na:CODE>|emdash=<clean|N-replaced|na:CODE>|recurring=ran:N|priorpr=<ran:M/N|na:CODE>|dry=<ran:N/K/J|na:CODE>|panel=<ran:unanimous:rN|na:CODE|user-waived>|itd=<prospective|retrospective|na:CODE>|delta-g=<ran:P/S|na:CODE>|comment=<ran:N|na:CODE>|build=<pass|fail>|tests=<pass:N/M|fail:N/M>|diff=<yes:tN|pending>|msg=<approved:tN|pending>
```

**Rules:**
1. Fields `|`-separated; values are counts/codes/enums EXCEPT `commit`: a JSON-escaped quoted string (`"`->`\"`, `|`->`\u007c`), unambiguous for any subject. Lists `[...]`, no interior spaces.
2. N/A codes name the trigger absence: `na:no-visibility-delta`, etc.
3. Every `gates|` key MUST appear with status+metric (`=none` for empty triggers, never blank).
4. Catalog sub-blocks (`pre-impl-trigger-detections`, `pre-impl-playbook-decisions`, `playbook-invocations`) stay in EXISTING STRUCTURED form below KV (dot-path parsers depend on structure).
5. APPENDIX (only when count>0): emit the canonical structured sub-blocks above (`delta-g-sweeps` site block + `comment-audit` bullets) verbatim, NOT pipe-compressed; else `appendix=none`. `recurring`/`priorpr` collapse to counts.
6. Adopted: full schema to audit file, appendix optional in chat. Non-adopted: when `delta-g` sites or `comment` failed-sites >0 the structured appendix MUST appear in chat (`appendix=none` INVALID then).
7. §0 SENTINEL, `PRE-COMMIT GATE PASSED`, `core_rules_acknowledged`, and `PRE-PR REVIEW COVERAGE` emit the caveman chat-emission form defined in each block's home section, NOT verbose YAML.

### Waiver semantics

A `user-waived` value MUST quote the user's waiver from the **current turn**. Waivers from earlier turns do NOT carry forward to new commits. This is the specific rule that catches the silent-skip failure mode: "the user said staged-means-reviewed on commit N" cannot waive any gate on commit N+1.

Example valid waiver:
```
diff-shown: user-waived: "go ahead and ammend these changes into that commit and pop the stash"
```

Example invalid waiver (previous-turn quote, current-turn approval missing):
```
diff-shown: user-waived: "staged means I reviewed it" [turn 47]
```

### Required outputs per gate

The ledger does NOT replace each gate's own required output (e.g. §2.5 sweep still emits `Step 2.5 sweep: ran, N findings`, §2A still emits its sweep line). The ledger AGGREGATES those into a single signed-off block. Per-gate output must still appear in the same turn  -  the ledger just confirms each gate ran AND attests to its result.

### When this gate fires

Every `git commit` of the user's staged set. Specifically:

1. Fresh commits (user stages -> `git commit`).
2. Amend commits (`git commit --amend`) when files are re-staged after edits.
3. Conflict resolution after `git stash pop` / `git merge` / `git rebase` IF the resolution is committed in the same turn.
4. Cherry-pick / rebase operations that commit a resolved state.

**Carve-outs (no ledger required):**

- A `git add` to mark conflicts resolved when **no commit will follow in the current turn**  -  i.e. the user has explicitly directed leaving the resolved state in the working tree for their own review before any commit.
- `git stash push` (preparing to stash, not commit).
- `git restore --staged <path>` (unstaging  -  no commit pathway).

### Skip conditions

A gate row may be `N/A: <reason>` when:

- **hygiene-cleanup**: the diff contains no consumer files with stale usings or qualifiers that the change could have affected (e.g. the diff only adds new files in new directories).
- **touched-file-LPA**: the diff contains no visibility / export / sealing / mutability surface deltas (per `AGENTS.md` Post-code-change phase). Body-only edits to already-public types do NOT trigger LPA.
- **recurring-pattern-sweep**: no pattern's trigger condition definitionally applies (e.g. no test files in diff for test-name patterns). "I don't think it applies" is NOT acceptable.
- **prior-PR-review-sweep**: the repo has no prior merged PRs AND no current PR thread, OR the change has no production-code edits.
- **post-code-change-panel**: pure re-commit / rebase with zero behavioral delta vs. the previously-panelled artifact (e.g. style-only amendments to an already-reviewed commit). The ledger MUST justify this explicitly: `N/A: pure re-commit of already-reviewed content, 0 behavioral delta`.
- **comment-audit-§3.1**: no comments added, removed, or modified in the diff. `failed: <site list>` is NEVER waivable: any bullet with invalid/missing `approval_turn:` in the §2.6 ledger produces `failed`, which forbids the commit per `comment-protocol.md` §Recording. On **adopted repos** (per `comment-protocol.md` §Persisted audit file, adoption gate), missing `.github/pr-quality-gate/audits/last.md` ALSO produces `failed`. On **non-adopted repos**, the audit file is intentionally absent and tracking happens INLINE via `PRE-COMMIT GATE PASSED`'s `comment_audit` block, missing-file is NOT a failure in that mode.
- **delta-g-sweeps**: N/A only via recorded zero-result `discovery_query` at HEAD. The
  `discovery_query` MUST scope to AT MINIMUM the unique directory parents of every file
  in the commit's diff (extract from `git diff --name-only <merge-base>..HEAD`; repo-root
  files whose dirname is `.` expand to the repo's source roots  -  typically `src/`, `tests/`
   -  and exclude generated/vendored trees such as `node_modules/`, `vendor/`, `obj/`, `bin/`
  per the repo's `.gitignore`). Wider scope is permitted and encouraged for cross-cutting
  patterns; narrower scope is forbidden. If a sister site outside the recorded scope is
  later discovered, the LEDGER is falsified per §2B and the falsified-ledger remediation
  below applies. "No plausible sister sites" is NOT acceptable; the query must be recorded
  so a reviewer can re-run it.
- **pre-impl-trigger-detections** / **pre-impl-playbook-decisions** / **playbook-invocations**: NEVER `N/A` as a whole sub-block; these sub-blocks are mandatory on every commit-bound `POST-CODE-CHANGE LEDGER` and mirror the pre-impl G6 outputs per `pre-implementation.md`. Individual entries within `playbook-invocations` may be `N/A: <reason>` (e.g., `implementation-planning: N/A: playbook-decision was not-required-trigger-not-detected`). Individual entries within `pre-impl-playbook-decisions` MUST use one of the valid decision values for the playbook's class (REQUIRED-class accepts `invoked` / `required-but-skipped` / `not-required-trigger-not-detected`; OFFERED-class accepts the 4 base values per Phase 2 schema). Catalog rules 2, 3, 4, 6, 7, 8, 10, 11, 12, 13 fire on bypass values.

### Why this exists

The asymmetry with §1A produced the failure mode. §1A enforces "no implementation tools without `PANEL CONVERGED`"; the absence of the certification block is itself the enforcement. §2B mirrors that pattern at the commit boundary: "no `git commit` without `POST-CODE-CHANGE LEDGER`". The literal block is the enforcement; absent block = forbidden tool call. This makes the rule self-policing in the same way §1A is.

The ledger is also the audit trail: when a future review (post-merge, retrospective, or PR review on the open PR) discovers that a gate slipped, the ledger explicitly records *which* gate was skipped and *why*. No more reconstructing intent from chat history.

### Repeat failure escalation

If a `POST-CODE-CHANGE LEDGER` block is later found to have falsified a gate status (claimed `ran` for a gate that did not actually run, or quoted a waiver the user never gave), the agent MUST proactively report this to the user as a process violation in the next turn, propose a remediation, and ask the user to re-review. False-positive ledger entries are a higher-severity failure than silent skips because they erode the trust the rule depends on.

---

## 2C. DRY remediation gate (HARD GATE)

### The problem

The agent has repeatedly noticed code duplication during implementation but proceeded to commit without refactoring  -  leaving the user to call it out later. Examples from recent sessions: 5 tab classes sharing 100+ lines of run/cancel/state/log plumbing (caught by user, base class extracted after commit); 3 picker services sharing the WinUI window-init dance (caught by user, shared helper extracted after commit). The pattern is "I saw it, I didn't act." This wastes a re-review round and erodes trust.

### Rule

During the post-code-change phase, the agent MUST run a DRY audit on the staged diff before showing it for approval. If any of the following are detected, the agent MUST either refactor in-place OR present the duplication to the user via `ask_user` with a refactor-or-waive choice:

1. **Cross-file duplication.** Two or more files contain ≥5 lines of substantively-identical logic (member ordering, parameter renames, and trivial whitespace differences do not count as different).
2. **Three-or-more pattern.** A pattern (method shape, field cluster, dispatch wrapper, etc.) appears 3+ times anywhere in the staged diff or in code the staged diff touches.
3. **Copy-paste growth.** A new file is structurally identical to an existing file with only parameterized differences (different request type, different service method).

### Refactor recommendations

The default action is refactor, using the smallest abstraction that captures the duplication:

- 2+ classes sharing fields + methods → base class (abstract for behavior, concrete for shared state).
- 2+ files calling the same 3-10 lines of platform/util code → static helper.
- 2+ methods with same shape but different generic parameter → generic method.
- 2+ types with parallel members → extension method, interface, or partial class.
- 2+ Razor components sharing template + binding → component inheritance or shared `RenderFragment`.

### Waiver semantics

If refactoring is not appropriate, the agent presents the duplication to the user with:

1. The pattern (concrete code or shape).
2. The file paths + line ranges where it appears.
3. The proposed refactor + why the agent is recommending against it (e.g., "premature abstraction  -  only 2 sites today, abstraction would obscure rather than help").
4. A `refactor | waive` choice via `ask_user`.

A `user-waived` entry in the LEDGER's `dry-audit` row MUST quote the user's waiver from the **current turn**.

### Exceptions (no audit needed)

- Test fixtures that intentionally duplicate setup for isolation.
- Trivial 1-2 line guards (`ArgumentNullException.ThrowIfNull(x)`).
- Tool-generated code (EF migrations, Razor compilation output, scaffolding).
- Boilerplate the language requires (e.g., `partial` declarations, attribute decorators).

### Required output

In the post-code-change LEDGER (§2B), add the gate row:

```
dry-audit: ran, N duplications, K refactored, J waived
  - <pattern shape>: <file:line, file:line, ...> → refactored to <abstraction> | waived ("<user quote>")
```

### Repeat-failure escalation

If the same duplication pattern is detected in a subsequent commit (i.e., the user had to call it out after the agent shipped without refactoring), that counts as a §2B "falsified ledger"  -  agent reports the slip proactively and proposes remediation. Two such slips in the same session triggers an explicit pause + plan-correction cycle.

---

## 2D. Pre-PR-creation multi-model review (HARD GATE)

### Rule

Before any PR-creation or review-visibility transition tool call (full list in `pre-pr-creation-review.md` G6), a multi-model heavy panel (≥4 reviewers per slate floor in `pre-pr-creation-review.md` waive matrix) MUST run on the FULL branch diff (`<base>..HEAD`) with the 11-category Copilot-mirror prompt template (`multi-model-review/pr-creation-mirror-prompt.md`). Every reviewer-flagged `blocking` finding MUST be resolved via `fixed` / `dismissed-source-grounded` / `routed-deferred-with-tracker-and-ask_user` (G4 conditions). A `PRE-PR REVIEW COVERAGE` block MUST appear in the same turn as the PR-creation tool call (initial emission at end of synthesis + re-emission after the AGENTS user-approval `ask_user` returns).

Strict mandatory  -  G1 (panel run), G2 (must-fix=0), G3 (block emission), G5 (disposition per finding), G6 (forbidden-tool list), and G7 conditions are NOT user-waivable. Convergence model and slate composition ARE user-waivable within floors (see waive matrix in the consumer playbook).

### LEDGER row format

When §2D is in scope (review-targeting push per `pre-pr-push.md` Step 5), the §2D ledger row appears in `PRE-PR REVIEW COVERAGE` per the playbook's Step 7 / Step 9 emission format. The `pr-creation-status` field is the gate's READY signal  -  values:

- `READY-pending-user-approval` (initial emission, end of synthesis turn).
- `READY-re-emitted-after-user-approval` (PR-creation tool-call turn, after AGENTS user-approval ask_user returns + same-state re-check passes).
- `BLOCKED  -  <N> must-fix unresolved` (must-fix findings still pending).
- `BLOCKED  -  slate-floor violated` (slate composition fell below the waive matrix floor).
- `BLOCKED  -  bootstrap-token-removed` (G7 token removed from PR body after initial emission).
- `BLOCKED  -  same-state-check-failed` (HEAD / base / commit-count changed between initial and re-emission).

The PR-creation tool call is forbidden unless `pr-creation-status` reads `READY-re-emitted-after-user-approval` in the same turn.

### Bootstrap exemption (narrow scope)

The PR that introduces §2D itself (this entire gate, the consumer playbook, the cross-cutting AGENTS.md bullet, this `review-workflow-gates-sweeps.md` §2D section, the `pre-pr-push.md` Step 5 hook, the `multi-model-review/pr-creation-mirror-prompt.md` template, the `pre-pr-creation-review/implementation-roadmap.md` deferred-features document, and the `manifest.yaml` registration) is EXEMPT from §2D for THAT specific PR. The exemption requires ALL of:

1. The PR introduces a NEW mandatory gate that did not exist on `origin/<base>` pre-PR.
2. The PR body contains the literal token `BOOTSTRAP-EXEMPTION: §2D pre-PR-creation review gate`.
3. The PR includes ALL companion edits required for the gate to be operative post-merge (listed above).

PRs that modify, tighten, loosen, or refactor §2D-as-already-shipped are NOT bootstrap-exempt  -  they go through §2D normally. If the bootstrap token is removed from the PR body before merge, the exemption is revoked.

This template applies to any future meta-change introducing a new mandatory gate at the §2-level: the introducing PR is exempt from the gate it introduces; subsequent modification PRs go through the gate normally.

### Full procedure

See `.github/playbooks/pre-pr-creation-review.md` for the full procedure (Step 1 invocation mode, Step 2 ancestry-based re-run-trigger detection, Steps 3-6 panel + synthesis + fix loop, Steps 7-10 LEDGER emissions and user approval flow). Deferred features (capability-tier registry, context-budget circuit breaker, branch-level fix-iteration cap, citation-preserving compaction format, etc.) live in `pre-pr-creation-review/implementation-roadmap.md` for follow-up PRs.

### Why §2D exists

LLM-based PR reviewers (GitHub Copilot's PR-review feature, GitLab Duo Code Review, similar bot reviewers) consistently surface a known set of pattern categories on every PR. Patching the static-pattern catalog reactively after each PR is whack-a-mole. The LLM-judgment patterns (doc-impl divergence, comment-promises-behavior-code-doesn't-deliver, hardcoded ARIA, framework-binding stale-render, attach-without-detach, etc.) need an LLM in the loop to catch. Running our own multi-model panel pre-PR with the same category coverage shifts those findings from "review comment after PR opens" to "blocking finding before PR opens"  -  the work to fix is the same; the visibility cost (reviewer time, PR thread churn, CI cycles, force-push pollution) is dramatically lower.

---

