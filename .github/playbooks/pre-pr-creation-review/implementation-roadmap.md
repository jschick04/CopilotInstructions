# Implementation roadmap — pre-PR-creation review gate

This file captures design decisions DEFERRED from the initial §2D introduction PR. Each section below describes a feature that was reviewed and approved in design panels but deferred from the first ship to keep the introducing PR within context budget. Each feature ships in a follow-up PR triggered by either (a) the first real-world failure that section addresses, or (b) an explicit prioritization decision by a maintainer.

Deferred features ranked by priority (1 = most urgent based on panel review). Each has a **ship-trigger predicate** — a concrete, detectable condition that promotes the feature from "deferred" to "needs to ship now". This is the anti-graveyard mechanism: items don't sit in the roadmap waiting for someone to remember them; they ship when the predicate fires.

1. **Capability-tier registry indirection (model-fragility insurance)**
   - **Ship trigger**: any model named in `multi-model-review/current-model-registry.md` is deprecated or removed from runtime catalog, OR `slateSubstitutions` recorded in any §2D session ≥2 within a 30-day window, OR a new model tier is added that the playbook slate doesn't address.

2. **Context-budget circuit breaker (1M-context-cap protection)**
   - **Ship trigger**: any §2D session hits >700K orchestrator-context usage, OR a panel is aborted due to context exhaustion, OR the orchestrator OOMs mid-panel-round.

3. **Branch-level fix-iteration cap (unbounded-fix-loop protection)**
   - **Ship trigger**: any branch undergoes ≥3 fix-iterations in one §2D session (`fixIterationCount` field tracks this in v4; once the field starts firing the >3 escalation, automating the cap escalation is the next step), OR the manual escalation rule is bypassed in any session.

4. **Compaction format with citation preservation (per-commit dedup integrity)**
   - **Ship trigger**: any heavy panel re-raises a theme already disposed at the per-commit gate (indicates dedup integrity loss — the prior-commit-panel-dispositions field is being ignored or its citations are insufficient), OR a per-commit-panel output exceeds 50K tokens (compaction becomes necessary regardless of session budget).

5. **Forge-agnostic state field via pre-pr-push.md (non-GitHub forge support)**
   - **Ship trigger**: any user invokes §2D on a non-GitHub forge (GitLab, ADO, Gitea, Forgejo, Codeberg, Bitbucket, SourceHut, Radicle) AND the v4 inline forge-specific commands at Step 1 fail or produce ambiguous output, OR the inline forge enumeration becomes ≥5 entries (the inline approach gets unwieldy).

6. **Slate-floor automated re-check infrastructure**
   - **Ship trigger**: any session has slate-floor break detected at synthesis (after the panel has already run for some time), OR a §2D session emits `READY-*` with a slate-floor violation that wasn't caught until post-emission audit.

7. **Same-state re-check infrastructure (post-user-approval drift detection)**
   - **Ship trigger**: any §2D session emits `READY-re-emitted-after-user-approval` but the actual G6 tool call lands on a different branch state than recorded (detectable via post-hoc audit comparing `panelHeadSha` to the actual commit referenced by the PR), OR the Step 9 same-state check produces a false-negative.

Ship triggers are NOT exhaustive — a maintainer prioritization decision can promote any item without a triggered predicate. But absent maintainer initiative, the predicates ensure deferred items don't stay deferred forever.

---

# DEFERRED DESIGN — kept here for follow-up PRs

# Playbook: Pre-PR-creation review (heavy multi-model panel)

## Purpose

Mandatory multi-model code-review panel on the FULL branch diff (`<base>..HEAD`) before any PR is created or made review-visible. Mirrors the categories an LLM-based PR reviewer (GitHub Copilot's PR-review feature, GitLab Duo Code Review, similar bot reviewers) would surface — but runs locally pre-push so findings are caught and fixed before reviewers see them, not after.

Sister to `post-code-change.md` §3 (per-commit panel, lightweight): this is the **branch-wide heavy panel** that runs once per PR-creation transition. Per-commit reviews see one slice; the pre-PR review sees the assembled work and catches cross-commit emergent issues that no individual commit panel could see.

## Hard gates

### G1. Mandatory panel run — not user-waivable

The panel MUST run. The user cannot waive the panel via `ask_user` quote. The only exit from this gate is convergence with all must-fix findings resolved.

### G2. Must-fix=0 to proceed — not user-waivable

Every finding flagged `blocking` by any reviewer in the final round MUST be resolved via one of exactly three paths (matches the G5 enum):

- **`fixed`** — applied as a change in the branch.
- **`dismissed-source-grounded`** — refuted by source evidence (file:line, doc URL, RFC, ADR, spec section) that specifically addresses the finding's claim.
- **`routed-deferred-with-tracker-and-ask_user`** — deferred to an external tracker issue per G4's strict conditions. **This is the ONLY form of deferral accepted on a blocking finding.** A plain `routed-deferred` without G4 conditions is invalid for blocking findings.

No "ship it anyway" path; no user-quote that bypasses G2. The user can `ask_user`-route an individual finding via G4 conditions to `routed-deferred-with-tracker-and-ask_user`, but not waive the gate itself.

### G3. `PRE-PR REVIEW COVERAGE` block required in the actual PR-creation turn — not user-waivable

The mandatory output block (format below) MUST appear in the same chat turn as the PR-creation tool call from G6.

**Two-turn flow with re-emission**: because `AGENTS.md`'s `gh pr create` section requires an intervening `ask_user` for PR title/body/base approval (which breaks the chat turn), the block is emitted twice:

1. **Initial emission** at the end of Step 10 below (turn N) with status `READY-pending-user-approval`.
2. **Re-emission** in the actual PR-creation turn (turn N+1, after user approval), with same-state re-check:
   - `git rev-parse HEAD` matches the recorded `panelHeadSha` (no new commits).
   - `git merge-base --is-ancestor <panelHeadSha> HEAD` returns true (no force-push).
   - `git rev-parse <baseRef>` matches the recorded `panelBaseSha` (no base shift).
   - If any check fails, the gate restarts at Step 2; the block from turn N is invalid.
3. **Re-emission status**: `READY-re-emitted-after-user-approval`. PR-creation tool call follows in the same turn.

**Enforcement**: absence of the appropriate block in the PR-creation turn → all G6 tools are forbidden. The block being present in an earlier turn does NOT satisfy this gate (mirrors §2B "waivers from earlier turns do not carry forward").

### G4. `routed-deferred-with-tracker-and-ask_user` requires both conditions

Every finding routed via this status requires BOTH:

1. An actual external tracker issue (GitHub issue, ADO work item, Linear ticket, etc.) created in this same turn with a citable URL — NOT a session-todo, NOT a `TODO` / `FIXME` comment in code, NOT a "tracked internally" hand-wave.
2. Explicit `ask_user` approval in the same turn naming the issue URL and confirming deferral.

This preserves `dismissed-source-grounded`'s integrity (the citation must refute the finding's correctness; do NOT hand-wave to "out of scope"). It also prevents the user-muting failure mode: Intake Q4 supplies pre-existing-context as context-only notes (see Intake §11 and the reviewer prompt's CONTEXT NOTES instruction) — reviewers raise findings anyway, and the orchestrator routes via the G5 enum AFTER the panel completes.

### G5. C2 disposition enum (per finding)

`fixed | dismissed-source-grounded | routed-deferred-with-tracker-and-ask_user | routed-now-via-ask_user`. Every finding has a status; no orphans. `routed-now-via-ask_user` is for non-blocking findings the orchestrator chooses to surface in the current turn for user decision; `routed-deferred-with-tracker-and-ask_user` is the only deferral form per G4.

### G6. Forbidden-tool enumeration (mirrors §1B)

Until the appropriate `PRE-PR REVIEW COVERAGE` block from G3 has been emitted in the current turn AND its `pr-creation-status` line reads `READY-pending-user-approval` (initial emission) or `READY-re-emitted-after-user-approval` (PR-creation turn), the agent MUST NOT call any of:

- `gh pr create` (any flags including `--draft`)
- `gh pr ready` (draft → ready transition)
- `gh pr ready --undo` (ready → draft transition, when used to escape this gate)
- `gh api` POST / PATCH / PUT targeting `/repos/*/pulls`, `/repos/*/pullrequests`, or any equivalent PR-creation / PR-state-change / draft-state-mutation endpoint
- `glab mr create`, `glab mr update --ready`, `glab mr update --draft`
- `tea pr create`
- `az repos pr create`, `az repos pr update` (toggling draft state)
- `git push` with merge-request / pull-request push options (`-o merge_request.create=*`, `-o pull_request.create=*`, `-o topic=*` that auto-creates an MR, etc.)
- `git push <remote> HEAD:refs/for/*` (Gerrit-style review push)
- Any MCP-server tool whose intent is PR / MR creation, review-visibility transition, or draft-state mutation on any forge
- Raw `curl` / `Invoke-WebRequest` calls to forge REST/GraphQL APIs that POST/PATCH PR-creation or draft-state endpoints
- Any equivalent on any other forge (Bitbucket, Gitea, SourceHut, Forgejo, Codeberg, Radicle, etc.) that creates a PR / MR / patchset or transitions one to review-visible state

Pattern: the absence of the block IS the enforcement. New PR-creation pathways extend the list by INTENT (PR-creation / review-visibility / draft-state-mutation), not by literal name match. When a future tool surfaces that's not on the list, flag the gap and propose adding it explicitly.

### G7. Bootstrap exemption — narrow scope

A PR is BOOTSTRAP-EXEMPT from §2D only if ALL of:

1. The PR introduces a NEW mandatory gate that did not exist on `origin/<base>` pre-PR (verifiable: `git show origin/<base>:.github/playbooks/<gate-file>.md` does not exist or doesn't contain the gate definition).
2. The PR body includes the literal token `BOOTSTRAP-EXEMPTION: <gate-name>` enumerating WHICH gate is exempt by name (e.g., `BOOTSTRAP-EXEMPTION: §2D pre-PR-creation review gate`).
3. The PR includes ALL companion edits required for the new gate to be operative post-merge (gates with declared cross-file hooks must land hooks + definition together; partial introduction is invalid).

**PRs that modify, tighten, loosen, or refactor an EXISTING gate are NOT bootstrap-exempt.** Modifications go through the gate they're modifying. The "modifies" interpretation that earlier draft language permitted is explicitly forbidden — only the introducing PR of a NEW gate is exempt, not subsequent change PRs.

**Token re-validation**: the bootstrap token MUST remain in the PR body until the introducing PR merges. If the PR body is edited to remove the token (`gh pr edit --body`), the exemption is revoked; subsequent push triggers §2D normally (the PR is no longer the introducing PR — it's a post-introduction modification). Track this via the `bootstrapTokenStatus` field in the LEDGER (one of `not-applicable | present-in-body | removed-revokes-exemption`).

**All other gates STILL APPLY**: §1A panel still applies, §1B tool list still applies, §2A prior-PR-review sweep still applies, §2B LEDGER still applies, §2C DRY remediation still applies. G7 exempts ONLY from §2D itself, not from sibling gates.

## What is user-waivable at this gate (and what isn't)

Explicit matrix to defeat "well, the user said proceed" rationalization:

| Item | Waivable with `ask_user` quote? | Conditions / floor |
| --- | --- | --- |
| Panel must run (G1) | **NO** | — |
| Must-fix=0 to proceed (G2) | **NO** | Individual blocking findings may use G4 `routed-deferred-with-tracker-and-ask_user`; the gate-level requirement that must-fix=0 stands. |
| `PRE-PR REVIEW COVERAGE` block emitted in PR-creation turn (G3) | **NO** | — |
| C2 disposition per finding (G5) | **NO** | — |
| Forbidden-tool list (G6) | **NO** | — |
| Bootstrap exemption (G7) | **NO** | The G7 conditions themselves are non-waivable; the exemption EITHER applies (all 3 conditions met) or doesn't. |
| Convergence model (default: `unanimous`) | **YES** | Floor: `threshold ≥75%`. `confidence-weighted ≥80%` also allowed. User quote recorded under `convergence-waive`. Must-fix=0 still applies regardless. |
| Reviewer slate composition | **YES** | Floor (all must hold simultaneously): ≥4 reviewers total; ≥1 Claude family + ≥2 GPT family (at least one premium-tier + at least one cross-version-or-codex tier) + ≥1 Gemini family; ≥1 `rubber-duck` role + ≥2 `code-review` role; ≥1 heavy-tier (per `current-model-registry.md`). User quote recorded under `slate-waive`. The floor is re-checked after every drop/replacement; an in-flight slate that falls below floor escalates per Step 7. |
| `routed-deferred-with-tracker-and-ask_user` per individual finding | **YES with G4 conditions** | External tracker URL + same-turn `ask_user` approval naming the URL. |

Items NOT in the matrix are NOT waivable. If the agent is uncertain whether an item is waivable, treat as NOT waivable and escalate via `ask_user`.

## Intake questions

Bundle in one prompt before launching the panel:

1. **Confirm base ref.** Default: `origin/main` (or the parent branch for stacked PRs). Resolve to a SHA now and record as `panelBaseSha`.
2. **Convergence model.** Default `unanimous`. User MAY downgrade to `threshold ≥75%` or `confidence-weighted ≥80%` with explicit quote (see waive matrix); downgrade is captured under `convergence-waive`.
3. **Reviewer slate confirmation.** Default heavy slate (below). User MAY adjust within the slate-floor in the waive matrix.
4. **Pre-existing-issue context** (CONTEXT-ONLY — does NOT preempt findings). User may surface notes about the branch's broader context (e.g., "the legacy module already has this anti-pattern, not introduced in this PR"). **Reviewers receive these as CONTEXT NOTES alongside the diff. The reviewer prompt explicitly instructs: "if you still find the pattern in the diff, raise it as a finding; the orchestrator may then route via `dismissed-source-grounded` with the cited context — but the finding goes through the normal G5 flow first."** This prevents the user-muting failure mode of pre-empting findings before they reach the panel.

## Reviewer slate — capability-tier definition

The slate is defined by capability tier + family + role, NOT by hardcoded model name. Tier → current model mapping lives in `multi-model-review/current-model-registry.md` (sibling file). When the registry is missing or a tier has no mapping, the orchestrator falls back to its runtime catalog and selects the highest-capability successor from the requested family; log the fallback under `slate-substitutions` per the registry's fallback rule.

**Default heavy slate (6 reviewers, ≥3 families, satisfies slate-floor including ≥2 code-review + ≥1 rubber-duck and within-family GPT triangulation)**:

| Slot | Tier id (from registry) | Family | Role | Purpose |
| --- | --- | --- | --- | --- |
| 1 | `heavy-claude-xhigh` | Claude | `code-review` | Anchor reviewer; deep reasoning; cross-family diversity vs. GPT slots. |
| 2 | `heavy-gpt-premium` | GPT | `code-review` | Cross-family fresh eyes. |
| 3 | `heavy-gpt-codex` | GPT | `code-review` | Code-specialized angle (different reasoning angle within GPT family). |
| 4 | `heavy-gpt-cross-version` | GPT | `code-review` | Within-family version triangulation. |
| 5 | `heavy-gemini-premium` | Gemini | `code-review` | Third-vendor cross-family diversity (non-Claude, non-GPT). |
| 6 | `heavy-claude-standard` | Claude | `rubber-duck` | Design / blind-spot critique angle. |

**Substitution rule**: if a named tier's current model is unavailable (API down, deprecated, removed from runtime catalog), substitute the highest-capability successor from the same family per the registry's substitution rule. Record under `slate-substitutions: [{slot, requested-tier, requested-model, substituted-model, reason}]` in the LEDGER.

**Slate-floor enforcement**: regardless of waivers and substitutions, the actually-launched slate must satisfy the floor at every check-point (initial launch, after each drop, after each replacement, at synthesis). If the floor breaks at any check-point, escalate via `ask_user` BEFORE proceeding. Slate-floor re-check timestamps are recorded under `slate-floor-rechecks: [{checkpoint, satisfied, ...}]`.

**Liberal expansion is encouraged** for risky / cross-cutting / unfamiliar-area branches — there's no "too many reviewers" at this gate.

## Reviewer prompt template (11-category Copilot-mirror)

Every reviewer receives this prompt template. The category list mirrors what LLM-based PR reviewers consistently surface in practice — derived from the published Copilot-code-review category set plus accumulated review-comment patterns across multiple repos.

```
You are reviewing the BRANCH DIFF at <repo-path>: `git diff <baseSha>..<headSha>`.

This is a PRE-PR-CREATION review pass — your findings gate whether the PR can be
opened. The same diff WILL be reviewed by GitHub Copilot's PR-review feature (or
equivalent LLM-based PR reviewer) once the PR opens. Your job is to find issues
BEFORE that bot sees them, so the PR opens with as little reviewer churn as possible.

**Prior-commit panel dispositions** (read these BEFORE reviewing — these themes
were already raised and disposed at per-commit panels per `evidence-gate-spec.md`'s
C2 findings audit format; flag them ONLY if you have new evidence the prior
disposition was wrong):

<list of compacted lines, one per finding:
  theme | severity | status | citation-summary
   — OR — "none — no per-commit panels run on this branch">

**Pre-existing-issue context notes** (these are CONTEXT, not pre-emptive dismissals
— if you find the pattern in the diff anyway, raise it as a finding and let the
orchestrator route via `dismissed-source-grounded` if the context applies):

<list of user-provided context notes from Intake Q4, or "none">

Mirror the categories an LLM-based PR reviewer would surface. For each category,
identify findings in the diff and emit them as bullets. Empty categories are
acceptable — do not invent findings to fill them.

**Categories**:

1. **Bugs and logic errors** — null-dereference / index-out-of-bounds risks,
   off-by-one, race conditions, snapshot-then-re-read inconsistencies, missing
   await, missing return, logic inverted from intent.

2. **Security vulnerabilities** — injection (SQL / command / template), insecure
   deserialization, path traversal, secrets in code, weak crypto, missing auth
   checks, insecure default permissions, predictable randomness for security-
   sensitive use.

3. **Argument / input validation** — missing null checks on public-API parameters,
   missing bounds checks before indexed access (`list[0]` without `list.Count > 0`),
   missing empty-collection guards, missing string-not-whitespace checks on inputs
   used as identifiers.

4. **Resource lifecycle** — `IDisposable` / `AutoCloseable` / `Drop` / `using`-
   equivalent not disposed; event-listener / observer / hook `attach` / `subscribe`
   / `on` without a matching `detach` / `unsubscribe` / `off`; file / socket /
   process handles not closed; `ServiceProvider` / DI-scope leak; double-dispose
   via `using`+explicit `Dispose`.

5. **Documentation accuracy** — doc comment (XML doc, docstring, godoc, Rustdoc,
   JSDoc, etc.) claims behavior the code does not implement; doc references an
   obsolete implementation strategy after a refactor (e.g., doc says "uses COM
   interop" but implementation switched to direct P/Invoke); doc mentions a
   parameter / return type that no longer exists; doc mentions an exception that
   is no longer thrown.

6. **Accessibility (a11y)** — dynamic-state ARIA attributes hardcoded to a literal
   (`aria-expanded="false"`, `aria-selected`, `aria-pressed`, `aria-checked`,
   `aria-disabled`, `aria-busy` bound to a literal when the underlying state can
   change); missing `role` on a control that behaves as a button/tab/listbox/etc.;
   missing keyboard navigation (`@onkeydown` / equivalent) on an interactive
   element; missing focus management after dynamic content change; missing
   `aria-label` / `aria-labelledby` on a control with no visible label.

7. **UI framework binding pitfalls** — UI-framework-specific anti-patterns where
   the framework's binding semantics produce surprising behavior. Apply only the
   examples relevant to the diff's framework:
   - **Blazor (illustrative)**: `@onkeydown:preventDefault` / similar event
     modifiers bound to a flag mutated INSIDE the handler — the directive is
     evaluated from the last render, so the handler's flag toggle won't affect
     the event that triggered it.
   - **React (illustrative)**: state mutation instead of replacement
     (`arr.push(x); setArr(arr)`); missing `key` on list-rendered items; missing
     dependencies in a `useEffect` dep array, capturing stale state in the
     effect's closure.
   - **Vue (illustrative)**: mutating props directly, missing `:key` on `v-for`,
     two-way binding on a prop without an emit-back.
   - **Angular (illustrative)**: `ngModel` without `name`, mutation inside
     `ChangeDetectionStrategy.OnPush` components without `markForCheck`.
   - **Svelte (illustrative)**: assigning a property without reassigning the
     variable (`obj.x = y` does not trigger reactivity unless followed by
     `obj = obj`).

8. **Performance** — synchronous I/O in async contexts, allocations in tight loops,
   missing virtualization on large lists / tables, repeated dictionary lookups,
   string concatenation in loops, O(n²) when O(n) is available, blocking on async
   (`.Result` / `.Wait()` in C#, `.unwrap()` on future in Rust, `.then` chains
   without `await` in JS).

9. **Deprecated / discouraged patterns** — language- / framework-specific obsolete
   APIs (e.g., `BinaryFormatter`, `WebClient`, `Thread.Sleep` in async paths,
   `goto` without justification, raw SQL strings where a query builder is
   available, deprecated build targets / SDK floors).

10. **Best practices / idiomaticness** — argument-validation helpers preferred
    over manual checks (`ArgumentNullException.ThrowIfNull` over
    `if (x is null) throw`, `Objects.requireNonNull`, `assert` for invariants),
    `using` over manual dispose, async-all-the-way (no sync-over-async bridging),
    `ConfigureAwait` discipline in library code (.NET), `LibraryImport`
    source-generated P/Invoke over `DllImport` (.NET 7+), `record` over class for
    immutable data (C# 9+), `sealed` by default when extension is not intended.

11. **Copy-paste / refactor artifacts** — stale variable / type / method names
    that didn't get updated after a rename; duplicated logic that should be
    helper-extracted (defer to the DRY-remediation gate's threshold for action,
    but flag the pattern); a new file that is a parameterized copy of an
    existing file; comment / log strings still referencing the old name after a
    code rename.

**Format**: bullet list under each category. For each finding:
`[severity: blocking | major | minor] <one-line summary> — <file:line if applicable>
 — <proposed mitigation>`

**Tooling discipline**: read-only inspection allowed (`view`, `grep`, `glob`,
read-only `powershell` for `git --no-pager diff` / `show` / `log`). No `ask_user`,
no file modifications, no sub-agent launches.

**REQUIRED final line**: `VERDICT: <READY_TO_IMPLEMENT | NEEDS_ANOTHER_ROUND>`
```

## Procedure

### Step 1. Determine invocation mode

This gate does NOT classify whether the push is review-targeting — that's `pre-pr-push.md`'s job. Read the canonical phase-state record:

```
invocation-mode:
  if pre-pr-push.md phase-state record present AND its Step 5 hook fires this gate:
    → "via-pre-pr-push-step-5"
    read isFirstReviewExposurePush, remoteExposureExists, baseRef from that record
  else (self-fire fallback — playbook invoked directly, no pre-pr-push state):
    → "self-fire-fallback"
    run an inline open-PR check forge-agnostically:
      - GitHub: gh pr list --head <branch> --state open --json number,isDraft
      - GitLab: glab mr list --source-branch <branch> --state opened
      - Gitea/Forgejo: tea pr list --state open --head <branch>
      - ADO: az repos pr list --source-branch <branch> --status active
      - other forges: equivalent command, fall through to "intent-based" if no command
    AND ask the user via ask_user: "Is this push intended for PR review on <forge>?"
    if no open PR AND user says no-review → exit gate (not in scope)
    if yes (either condition) → continue with self-fire mode
```

Record `invocationMode` in the LEDGER. `self-fire-fallback` is the safety net for cases where the new gate landed without (or before) the companion `pre-pr-push.md` Step 5 hook — the gate stays operative.

### Step 2. Re-run-trigger detection (ancestry-based)

Before launching the panel, compare the current branch state against any prior §2D panel run on this branch. Detect re-run triggers using ancestry semantics, NOT reflog:

```powershell
# History-rewrite detection (ancestor test catches force-push AND git commit --amend)
$priorHeadSha = <recorded prior-run headSha, or "none" for first run>
$currentHead = git rev-parse HEAD
$baseRef = <recorded prior-run baseRef, or current intake baseRef>
$currentBase = git rev-parse $baseRef
$priorBase = <recorded prior-run panelBaseSha, or "none" for first run>
$priorCommitCount = <recorded prior-run commit count, or 0 for first run>
$currentCommitCount = (git rev-list --count "$currentBase..HEAD")

# Detect each trigger independently — they CAN co-occur
$triggers = @()
if ($priorHeadSha -eq "none") {
    $triggers += "first-run"
} else {
    # Use git merge-base --is-ancestor for ancestry semantics
    $isPriorAncestor = (git merge-base --is-ancestor $priorHeadSha HEAD 2>$null; $LASTEXITCODE -eq 0)
    if (-not $isPriorAncestor) {
        $triggers += "history-rewrite"   # covers force-push, amend, interactive-rebase-that-rewrites
    }
    if ($priorBase -ne "none" -and $priorBase -ne $currentBase) {
        $triggers += "base-shift"
    }
    if ($priorCommitCount -gt 0 -and $currentCommitCount -lt $priorCommitCount) {
        $triggers += "commit-squash"     # commit count decreased without base shift
    }
    if ($priorHeadSha -ne $currentHead -and $isPriorAncestor) {
        $triggers += "net-new-commits"   # current is descendant of prior, with new commits
    }
}
```

Record `reRunTriggers: [...]` in the LEDGER (list, not single value — triggers CAN co-occur). When ≥2 triggers fire, the panel runs on the current branch state regardless of which triggers; the trigger list is informational.

**Prior-commit-panel-dispositions carry-forward rule**: dispositions from the previous run carry forward IF AND ONLY IF the trigger set is exactly `["net-new-commits"]` (no rewrite, no base shift, no squash). Any rewrite / squash / base shift invalidates prior dispositions; the prior-commit-panel-dispositions field becomes `"none — prior run invalidated by <trigger list>"`.

### Step 3. Context-budget circuit breaker

Before launching the panel, estimate total session context usage. Express thresholds as percentages of the **orchestrator's runtime context window** (detected via the orchestrator runtime API; if unavailable, default to a conservative 200K-token window):

```
window      = orchestrator's max context window
sessionUsed = current orchestrator context usage (includes intake, turns,
              diff approvals, fix reasoning, prior panel outputs, LEDGER
              blocks — NOT just panel output)
projected   = sessionUsed + 75K (heavy panel output estimate)
triggerPct  = projected / window
```

Thresholds:

- **`triggerPct ≥ 0.60`** → invoke compaction step (Step 3a).
- **`triggerPct ≥ 0.85`** → escalate via `ask_user` (Step 3b).
- **Mid-loop re-check**: between panel rounds, re-compute `triggerPct`. If a mid-loop re-check crosses the 0.85 threshold, escalate immediately (do not start round N+1).

#### Step 3a. Compaction

Summarize all per-commit panel outputs into a compact `panel-history.md` artifact:

- **Location**: `<session-state-folder>/panel-history-<branchName>.md` (per the runtime's session-state folder convention; this is a session artifact, NOT a repo file — does not require a separate `§1B` certification for the write because it's preparation, not implementation).
- **Format**: one structured line per finding, preserving citation:
  ```
  theme | severity | status | citation-summary
  ```
  Example:
  ```
  null-check-param-X | major | dismissed-source-grounded | "IFoo.cs documents non-null"
  attach-without-detach | blocking | fixed | "src/foo.js:42-58 adds matching detach()"
  ```
- The `citation-summary` is lossy (truncated to ~80 chars) but MUST be present so the heavy panel's "new evidence" predicate is verifiable. Stripping citations defeats the dedup mechanism.
- Replace full per-commit outputs in the orchestrator context with the compacted summary.
- Pass the compacted summary as `prior-commit-panel-dispositions` in the reviewer prompt.
- Record `compactionApplied: true`, `compactionArtifactPath: <path>`, `compactionFindingCount: <N>` in the LEDGER.

#### Step 3b. Escalation

If post-compaction `triggerPct ≥ 0.85`, escalate via `ask_user` with three options:

1. Abort the gate and start a fresh session to run the gate cleanly (recommended for very large branches).
2. Accept a degraded panel: drop to slate-floor minimum (4 reviewers per floor), record `degradedDueToContext: true`. Floor must still hold.
3. Split the branch into a smaller stacked PR first.

### Step 4. Resolve and record sweep SHAs

```powershell
$BaseRef = <from Step 1 invocation-mode>
$BaseSha = git rev-parse $BaseRef
$HeadSha = git rev-parse HEAD
$CommitCount = (git rev-list --count "$BaseSha..HEAD")
```

Record `panelBaseRef`, `panelBaseSha`, `panelHeadSha`, `panelCommitCount` in the §2D phase-state record. These are read by Step 2 on subsequent invocations.

### Step 5. Launch the panel in parallel

Per `multi-model-review/procedure.md` parallel-launch protocol. All N reviewers launched in the same response (background mode), with the 11-category Copilot-mirror prompt populated with: diff range, prior-commit-panel-dispositions (per Step 3a's structured format), pre-existing-issue context notes from Intake Q4.

Slate selection draws from `current-model-registry.md` per the slate-floor and substitution rule. Record `slateActuallyRun` and `slateSubstitutions` in the LEDGER.

**Slate-floor checkpoint #1**: BEFORE launching, verify the slate satisfies floor. If a substitution broke floor, escalate via `ask_user` immediately.

### Step 6. Wait for reviewers (with per-reviewer scheduled timeout)

Notification-driven wait per `multi-model-review.md` Hard gates. Per-reviewer scheduled timeout: **10 minutes** measured against the orchestrator's wall clock from launch time. The timeout is NOT implemented via polling — it's a scheduled check at launch+10min using runtime scheduling.

If a reviewer notification does NOT arrive by launch+10min:

1. Send `write_agent` with "Status check — emit your current findings and VERDICT now".
2. Wait an additional 2 minutes (single scheduled check at launch+12min, not continuous polling).
3. If still no response: treat as dropped reviewer (proceed to Step 7).

### Step 7. Reviewer-failure handling (cumulative-drops semantics)

The "Dropped reviewers" column counts CUMULATIVE drop EVENTS across the panel round (including ones whose replacements succeeded), not the count of currently-unfilled slots. This makes the gate sensitive to instability across multiple events.

| Cumulative dropped slots (events) | Action |
| --- | --- |
| 0 | Proceed to synthesis. |
| 1 | Launch replacement per the Step 5 substitution rule (highest-capability successor from same family + same tier). If the replacement also drops → treat as 2-drop. |
| 2 | Escalate via `ask_user`: options are (a) wait additional 10 min, (b) proceed degraded with `degradedDueToReviewerLoss: true` IF slate-floor still satisfied, (c) abort the gate. |
| ≥3 | Hard escalate; cannot proceed without user explicitly authorizing degraded mode AND slate-floor still satisfied. |

**Slate-floor checkpoint #2-N**: re-verify floor AFTER every drop and AFTER every replacement. If floor breaks at any checkpoint, escalate immediately regardless of drop-count row.

If the substitution rule cannot find a successor (same family + tier exhausted), escalate via `ask_user` BEFORE retrying the same dead model.

Record `droppedReviewers`, `replacementReviewers`, and `slateFloorRechecks` in the LEDGER.

### Step 8. Synthesize + apply convergence + C2 routing

Standard `multi-model-review/procedure.md` synthesis (dedup by theme, rank severity, agreement count). Apply chosen convergence model (from waive matrix). C2-route every finding per the G5 enum.

`routed-deferred-with-tracker-and-ask_user` requires G4 conditions to be satisfied IN THIS TURN — external tracker URL + same-turn `ask_user`. If G4 conditions are NOT met, the finding is NOT routed-deferred; it must be `fixed` or `dismissed-source-grounded`.

### Step 9. Apply fixes for must-fix findings (with branch-level iteration cap)

Every finding flagged `blocking` by any reviewer must be resolved per G2's three paths: `fixed`, `dismissed-source-grounded`, or G4-compliant `routed-deferred-with-tracker-and-ask_user`.

For `fixed` findings: apply the change in this turn, re-stage, re-run build + tests, re-emit `POST-CODE-CHANGE LEDGER` per `review-workflow-gates-sweeps.md` §2B. After the fix commit, re-run the panel from Step 2.

**Branch-level iteration cap (separate from `multi-model-review.md` round-level max-loop)**: track `fixIterationCount` in the §2D phase-state record. Increment by 1 on each Step 9 fix-then-re-run cycle.

| `fixIterationCount` | Action |
| --- | --- |
| ≤ 3 | Proceed with re-run. |
| 4+ | Hard escalate via `ask_user` with options: (a) authorize N more iterations with an explicit new cap (`fixIterationCountCap`), (b) accept remaining blocking findings as G4-compliant `routed-deferred-with-tracker-and-ask_user`, (c) split branch / reduce scope. |

This prevents the pathological case where each fix introduces a new finding and the panel iterates unboundedly. The round-level max-loop (5 rounds per `multi-model-review/procedure.md`) covers within-panel-invocation cycling; the branch-level `fixIterationCount` cap covers across-panel-invocation cycling.

### Step 10. Emit the `PRE-PR REVIEW COVERAGE` block (initial emission)

Mandatory at the end of synthesis, BEFORE the AGENTS `gh pr create` user-approval flow. Format (fields with `[default: X]` use X when the underlying condition is empty):

```
PRE-PR REVIEW COVERAGE
  emission-phase: initial-pending-user-approval
  invocation-mode: <via-pre-pr-push-step-5 | self-fire-fallback>
  re-run-triggers: <[trigger, ...] — [default: ["first-run"]] >
  panel-base-ref: <baseRef>
  panel-base-sha: <40-char SHA>
  panel-head-sha: <40-char SHA>
  panel-commit-count: <N>
  diff-scope: <baseSha>..<headSha> (<N> files, +<X>/-<Y> lines)
  slate:
    - slot 1: <tier-id> <family> <role>: <model> [substituted from <requested-model>: <reason>] OR [no substitution]
    - ...
  slate-substitutions: <[] — [default: []]>
  slate-floor-rechecks: <[{checkpoint, satisfied, ...}] — [default: [{launch, true}, {synthesis, true}]]>
  slate-waive: <"no waive" — [default: "no waive"]>
  convergence-model: <unanimous | threshold-N% | confidence-weighted-N%>
  convergence-waive: <"no waive" — [default: "no waive"]>
  rounds: <K>
  dropped-reviewers: <[] — [default: []]>
  replacement-reviewers: <[] — [default: []]>
  degraded-due-to-reviewer-loss: <true | false — [default: false]>
  degraded-due-to-context: <true | false — [default: false]>
  context-budget:
    window-size: <orchestrator window in tokens>
    session-used-at-panel-launch: <tokens>
    trigger-pct-at-launch: <0.0-1.0>
    compaction-applied: <true | false>
    compaction-artifact-path: <path or "n/a">
    mid-loop-rechecks: <[{round, trigger-pct}] — [default: []]>
  prior-commit-panel-dispositions: <"none — <reason>" or compacted theme|severity|status|citation-summary list>
  fix-iteration-count: <N — [default: 0]>
  fix-iteration-cap: <3 or user-authorized override>
  findings: <total raw>, dedupe'd to <M unique themes>
  resolution (every finding has a status):
    - [<category 1-11>] <severity> [<reviewer model>]: <finding summary>: <status>: <citation>
    - ...
  must-fix-blocking-findings-resolved: <K of K>
  routed-deferred-with-tracker-and-ask_user:
    - <finding> → <tracker URL> (ask_user approval: <call ref>)
    - ... — [default: []]
  bootstrap-token-status: <not-applicable | present-in-body | removed-revokes-exemption — [default: not-applicable]>
  pr-creation-status: <READY-pending-user-approval | BLOCKED — <N> must-fix unresolved | BLOCKED — slate-floor violated | BLOCKED — context-budget exceeded>
  subagent_ask_user_calls=0 (orchestrator-only routing verified per AGENTS.md cross-cutting rule)
```

`pr-creation-status: READY-pending-user-approval` is required to proceed to the AGENTS user-approval step.

### Step 11. AGENTS `gh pr create` user-approval flow

Per `AGENTS.md` `gh pr create` section: present PR title + body + target branch via `ask_user`. User approves / edits / rejects.

For non-GitHub forges, mirror the same user-approval flow before invoking the equivalent tool from G6.

### Step 12. Re-emit the `PRE-PR REVIEW COVERAGE` block in the PR-creation turn

After Step 11's user approval AND BEFORE invoking the G6 tool, re-emit the block with:

- `emission-phase: ready-re-emitted-after-user-approval`
- Same-state re-check:
  - Run the Step 2 trigger detection. If `re-run-triggers` returns anything other than `[first-run]` or matches the prior-run's recorded triggers exactly, the state has changed since initial emission → restart at Step 2.
  - Verify `git rev-parse HEAD` still matches the recorded `panelHeadSha`.
  - Verify `git rev-parse <baseRef>` still matches the recorded `panelBaseSha`.
- `pr-creation-status: READY-re-emitted-after-user-approval`

If any same-state check fails, the gate restarts at Step 2 with the new state.

### Step 13. Invoke the G6 tool

Only after Step 12 emits `pr-creation-status: READY-re-emitted-after-user-approval` in the same turn. Then call the appropriate G6 tool.

## State to record in canonical session todos

Per `AGENTS.md` *Phase-state tracking convention*, the §2D phase-state record contains:

- `invocationMode` — from Step 1.
- `reRunTriggers` — list from Step 2.
- `panelBaseRef` / `panelBaseSha` / `panelHeadSha` / `panelCommitCount` — from Step 4.
- `slateActuallyRun` — list of `{slot, tier-id, family, role, model}` after substitutions.
- `slateSubstitutions` — list of `{slot, requested-tier, requested-model, substituted-model, reason}`.
- `slateFloorRechecks` — list of `{checkpoint, satisfied, ...}`.
- `slateWaive` — `"no waive"` or user-quote from waive matrix.
- `convergenceModelUsed` — `unanimous | threshold-N | confidence-weighted-N`.
- `convergenceWaive` — `"no waive"` or user-quote from waive matrix.
- `panelRounds` — number of rounds before convergence.
- `panelConvergence` — `converged-unanimous | converged-threshold | converged-confidence-weighted | escalated-to-user-after-max-loop`.
- `droppedReviewers` / `replacementReviewers` — from Step 7.
- `degradedDueToReviewerLoss` / `degradedDueToContext` — booleans.
- `contextBudget` — record of `{windowSize, sessionUsedAtPanelLaunch, triggerPctAtLaunch, compactionApplied, compactionArtifactPath, midLoopRechecks}`.
- `priorCommitPanelDispositions` — compacted summary string or `"none — <reason>"`.
- `fixIterationCount` / `fixIterationCountCap` — from Step 9.
- `mustFixFindings` — total count.
- `mustFixResolved` — count resolved as `fixed` or `dismissed-source-grounded` or G4-compliant `routed-deferred-with-tracker-and-ask_user`. Must equal `mustFixFindings` for `pr-creation-status: READY-*`.
- `bootstrapTokenStatus` — from G7 (`not-applicable | present-in-body | removed-revokes-exemption`).
- `prCreationStatus` — `READY-pending-user-approval | READY-re-emitted-after-user-approval | BLOCKED-*`.

Read these back from canonical session todos when emitting the `PRE-PR REVIEW COVERAGE` block; never infer from memory.

## §2B carve-out forward-reference

When the future `review-workflow-gates-sweeps.md` §2B edit lands (the one tightening `post-code-change-panel` from `ran | N/A — reason | user-waived` to `ran | N/A — reason`), preserve the existing N/A carve-out for pure-recommit / rebase with zero behavioral delta vs. previously-panelled artifact (existing carve-out at `review-workflow-gates-sweeps.md` ~line 297). Removing `user-waived` is correct; removing the N/A carve-out would be a regression.

## Cross-cutting fit — companion edits required for §2D to be operative

Per G7's "ALL companion edits required" rule, the introducing PR for §2D MUST include ALL of the following landed together:

- **`AGENTS.md` `gh pr create` section** — extended to require the `PRE-PR REVIEW COVERAGE` block emission per G3 (initial + re-emission) before the existing user-approval step.
- **`AGENTS.md` cross-cutting hard-gate bullets** — new bullet referencing §2D.
- **`pre-pr-push.md` Step 5** — invokes this playbook (single source of truth for "should §2D fire now?"). Adds `preCreationReviewStatus` field to the pre-PR-push state predicate.
- **`review-workflow-gates-sweeps.md` §2D** — the hard-gate spec (LEDGER row format, mandatory-output rules, G1-G7 enforcement summary).
- **`multi-model-review/current-model-registry.md`** — created with current capability-tier mappings.
- **This playbook** (`pre-pr-creation-review.md`).

If any of the above are missing from the introducing PR, §2D is non-operative post-merge — and the bootstrap-exemption is invalid (G7 condition 3 not met).

## Cross-cutting fit — gates §2D plugs alongside

- **`multi-model-review.md` + sub-files** — this playbook USES the multi-model-review procedure with a specific slate, convergence model, prompt template, and the extended timeout / N-failure-ceiling rules in Step 6-7. The `current-model-registry.md` sibling decouples the slate-slot tier ids from the current model names.
- **`post-code-change.md` §3** — the per-commit panel is the SISTER gate (lighter, runs every commit). This gate is the heavy branch-wide pass before PR creation and consumes per-commit-panel dispositions via Step 3a compaction.

## Why this gate exists

LLM-based PR reviewers (GitHub Copilot's PR-review feature and similar bot reviewers) consistently surface a known set of pattern categories on every PR. Patching the static-pattern catalog reactively after each PR is whack-a-mole — the deterministic patterns get caught faster, but the LLM-judgment patterns (doc-impl divergence, comment-promises-behavior-code-doesn't-deliver, hardcoded ARIA, framework-binding stale-render, attach-without-detach, etc.) need an LLM in the loop to catch.

Running our own multi-model panel pre-PR with the same category coverage shifts those findings from "review comment after PR opens" to "blocking finding before PR opens". The work to fix is the same; the visibility cost (reviewer time, PR thread churn, CI cycles, force-push pollution) is dramatically lower.

When a Copilot-bot PR-review finding lands on a PR that PASSED §2D, treat it as evidence the 11-category prompt or the per-commit catalog has a gap. Follow `review-workflow-gates-sweeps.md` §2 root-cause analysis and propose an addition to the §2.5 catalog or the 11-category prompt in the next `post-pr-review.md` cycle. The §2D gate improves via this feedback loop, not via static perfection.

The cost is panel context (≥4 reviewers × ~10-15K tokens each ≈ 40-75K tokens per gate run). Acceptable for the safety value at PR-creation time. The per-commit sister gate runs a lighter panel to keep cumulative context manageable across many commits; Step 3's context-budget circuit-breaker (parameterized to the orchestrator's runtime window size) prevents the gate from blowing memory on large branches.

