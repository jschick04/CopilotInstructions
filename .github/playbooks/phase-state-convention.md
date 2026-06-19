# Phase-state tracking convention

<!-- read-receipt-token: 5f9271a7 -->

At each phase entry, record in **session todos** (canonical mechanism - same as User-skip policy in `workflow-conventions.md`) using a parallel schema so a resumed session can read the evidence back unambiguously:

- **`id`** = `phase-state-<phase>-<yyyymmddHHMMSS>`. Timestamp-suffixed for the same reason skip IDs are: a single phase may be entered multiple times in one session (e.g. multiple commits each running pre-commit). Most recent record per phase wins; older records are kept for audit, not consulted for "ready" checks.
- **`title`** = `Phase state: <phase> @ <yyyymmddHHMMSS>`.
- **`status`** = `'in_progress'` while the phase is active, then `'done'` when all required steps + skips are complete.
- **`description`** carries the phase-state fields below (free-form prose acceptable; structured `key: value` lines preferred for grep-ability):

Required fields in `description`:

- Phase name and time entered.
- Playbook file viewed (or *"not viewed - explicit skip"* with skip reason).
- Intake completion status: complete / pre-filled-from-input / explicitly-skipped.
- User-approved skips of any sub-step.

Same fallback chain as the User-skip policy (in `workflow-conventions.md`) (SQL bootstrap then `<copilot-session-state>` file then per-turn re-ack then hard stop) applies if SQL is unavailable.

**Concrete example record - pre-implementation phase** (illustrates the minimum canonical shape; other phases require additional `key: value` lines beyond this minimum - see *Per-phase additional fields* below):

```sql
-- Entering pre-implementation phase
INSERT INTO todos (id, title, description, status) VALUES (
  'phase-state-pre-implementation-20240115093045',
  'Phase state: pre-implementation @ 20240115093045',
  'phase: pre-implementation
time_entered: 2024-01-15T09:30:45Z
playbook_viewed: .github/playbooks/pre-implementation.md
intake_status: complete
user_approved_skips: none',
  'in_progress'
);

-- Completing the phase
UPDATE todos SET status = 'done',
  description = description || '
time_completed: 2024-01-15T09:42:11Z
hard_gates_satisfied: yes'
WHERE id = 'phase-state-pre-implementation-20240115093045';
```

When SQL is unavailable, write the same field set as a `## phase-state-<phase>-<yyyymmddHHMMSS>` heading with key:value lines under it in `<copilot-session-state>/<session-id>/files/phase-state.md`. **Reader contract** (LLM consuming the record in a resumed session): parse `key: value` lines from the description; treat unknown keys as informational; require `phase`, `time_entered`, `intake_status` (description) AND `status` (read from the SQL `status` column directly, or - in the markdown fallback - from a `status: <value>` line) to consider the record valid. Any phase-specific required fields (e.g. the 11-field pre-PR-push state predicate below) must additionally be present for the readiness check that consumes them.

## Per-phase additional fields

**Pre-implementation phase additional fields** (cycle-3 G6 Playbook offer evaluation) - when running the pre-implementation phase per `pre-implementation.md`, record 14 additional lines per phase-state record mirroring the G6 chat output (7 `trigger-detected-<playbook>:` + 7 `playbook-decision-<playbook>:`). The keys mirror the POST-CODE-CHANGE LEDGER `gates.pre-impl-trigger-detections` + `gates.pre-impl-playbook-decisions` sub-blocks per `review-workflow-gates-sweeps.md` §2B; both surfaces stay in sync (chat-visible LEDGER is the enforcement target; phase-state is the resumed-session continuity target). On G6 re-entry mid-implementation (when scope materially changes per the `pre-implementation.md` *G6 re-entry clause*), both surfaces are updated.

- `trigger-detected-implementation-planning`: `yes` | `no`
- `trigger-detected-library-restructure`: `yes` | `no`
- `trigger-detected-design-exploration`: `yes` | `no`
- `trigger-detected-performance-comparison`: `yes` | `no`
- `trigger-detected-scope-planning`: `yes` | `no`
- `trigger-detected-system-framing`: `yes` | `no`
- `trigger-detected-project-vocabulary`: `yes` | `no`
- `playbook-decision-implementation-planning`: REQUIRED-class - `invoked` | `required-but-skipped ("<re-confirmation>")` | `not-required-trigger-not-detected`. INVALID: `not-applicable` / `offered-and-declined`.
- `playbook-decision-library-restructure`: REQUIRED-class - same valid values as implementation-planning.
- `playbook-decision-design-exploration`: OFFERED-class - `invoked` | `offered-and-declined ("<quote>")` | `not-applicable` | `required-but-skipped ("<reason>")`. `not-applicable` is INVALID when the matching `trigger-detected-*` line is `yes`.
- `playbook-decision-performance-comparison`: OFFERED-class - same valid values as design-exploration.
- `playbook-decision-scope-planning`: OFFERED-class - same valid values.
- `playbook-decision-system-framing`: OFFERED-class - same valid values.
- `playbook-decision-project-vocabulary`: OFFERED-class - same valid values.

`codebase-architecture-audit` is intentionally OMITTED (cycle-3 rule 9 was dropped because `session_files` detection was unreliable; the playbook may still be informally surfaced by G6 but is not catalog-enforced and not phase-state-tracked).

**Pre-PR-push readiness state is a state predicate** (per §3.7) - every required field must be enumerated. Record the following keys in addition to the minimum canonical shape above when running the pre-PR-push phase:

- `baseRef` - what the branch is being merged into (e.g. `origin/main`).
- `baseSha` - resolved SHA at sweep time (NOT later-resolved symbolic ref, which may have advanced).
- `sweepHeadSha` - branch HEAD SHA at sweep time.
- **`isFirstReviewExposurePush`** (boolean) - *Is THIS push the first one intended for review?* (PR-opening, request-for-review, or first push to a shared branch others may pull from.) Drives whether the branch-wide sweep is required. **Per-push, not branch-sticky:** a personal-sandbox / backup push records `false` (a sandbox push is not a review push); the FIRST subsequent review push of the same branch records `true`. Independence from `remoteExposureExists` is the point - prior sandbox pushes do NOT latch this boolean to `false` for the upcoming review push. Named as a verb-shaped predicate so a reader can't misread it as "this branch has never been pushed before".
- **`remoteExposureExists`** (boolean) - has this branch been pushed anywhere before, in any form (including personal sandbox)? **Historical evidence only** - the primary amend-safety force-push gate is `isFirstReviewExposurePush=false` (the branch is already under review on a shared remote). **Sandbox exemption is conditional, not automatic**: when `(isFirstReviewExposurePush=true && remoteExposureExists=true)` (first review push of a previously sandbox-pushed branch), before any operation that rewrites already-pushed history the agent MUST ask a one-question sandbox-privacy confirmation (*"was the prior sandbox push truly personal/unwatched, and are you sure no one else pulled it?"*). On **yes/private/unwatched**: silent amend is safe. On **no/unsure**: do NOT silently amend - use the explicit force-push approval choices from the `(false, true)` *amend-safety subflow only* (the recorded booleans and decision-tree routing are NOT remapped - Step 2 first-review sweep still runs, Step 4 is NOT entered). The question fires **lazily** - only when an amend is about to happen, NOT preemptively at intake. Recorded for audit and as input to the `(false, true)` truth-table row's re-run logic. These two booleans are independent - a branch pushed only to a personal sandbox has `remoteExposureExists=true` AND `isFirstReviewExposurePush=true` on its first subsequent review push.
- `perCommitAuditCoverage` - list of commit SHAs on the branch with audit status (`done` / `skipped-with-reason` / `not-run`). Must be `done` or `skipped-with-reason` for every commit before the branch is "ready". This is the canonical enum - playbooks that produce entries (e.g. `pre-commit.md`, `pre-pr-push/per-commit-micro-hygiene.md`) MUST use one of these three values; if extra detail is needed (e.g. *"audit modified the diff"*), put it in the entry's free-form description text, not in the `status` value.
- `branchWideSweepStatus` - one of:
  - `not-applicable` - push exited at the sandbox pre-check (out of pre-PR-push scope; no sweep applies).
  - `done-clean` - sweep ran in this push cycle, no changes.
  - `done-cleanup-committed` - sweep ran in this push cycle, cleanup commits made (list bucket + SHA per commit).
  - `previously-done-no-rerun-needed` - subsequent review-targeting push; prior sweep evidence present, re-run conditions checked, no re-run required.
  - `rerun-done-clean` - re-run sweep ran in this push cycle, no changes.
  - `rerun-done-cleanup-committed` - re-run sweep ran in this push cycle, cleanup commits made.
  - `rerun-skipped-with-reason` - re-run sweep explicitly skipped during a subsequent push (record reason per User-skip policy).
  - `skipped-with-reason` - initial sweep explicitly skipped during the first review push (record reason per User-skip policy).
- `cleanupBucketOutcomes` - for each cleanup commit: which bucket was chosen, why, and whether amend-safety required force-push approval.
- `sandboxPriorExposureConfirmation` - informational field, written when the conditional sandbox exemption gate fires (only on `(isFirstReviewExposurePush=true && remoteExposureExists=true)` and only when an amend is actually attempted). One of: `confirmed-private` (sandbox confirmed personal/unwatched, silent amend taken), `denied-or-unsure` (user said no/unsure, fell through to explicit force-push approval), `not-needed` (no amend was attempted in this push cycle, so the gate never fired). Recorded so a resumed session does not re-ask or silently infer safety from memory.
- `rerunConditionsChecked` - for each subsequent push: `true` (re-run conditions checked per `when-to-re-run-sweep.md`) or `false` (not yet checked / pending). Two documented sentinel values are also accepted for the "doesn't apply" case: the literal `n/a-first-push` (this is the first review push - no prior sweep to re-run-check; written by the first-review example) and the literal `n/a-sandbox-exit` (push exited at the sandbox pre-check; written by the sandbox-exit record). Both sentinels are predicate-complete - a strict reader MUST treat them as satisfying the field, not as missing.
- **`pushCredentialsVerified`** - outcome of the §4.2 mechanism-aware push-credential verification (recorded by `pre-pr-push.md` *Pre-check 0*; see §4.2 for the full procedure). One of:
  - `yes` - verification mechanism returned the user's principal (`gh api user --jq .login` matched the user; SSH greeting matched; etc.).
  - `user-confirmed-unverifiable` - verification mechanism couldn't expose the cached principal (e.g., Windows Credential Manager / macOS Keychain / libsecret) and the user confirmed via `ask_user` that the cached credential is theirs (not a Copilot / bot / shared account).
  - `blocked` - verification revealed (or strongly suggested) a non-user principal (e.g., `gh` logged in as a `[bot]` account; ambient `GH_TOKEN` / `GITHUB_TOKEN` / `GIT_ASKPASS` set; `SSH_AUTH_SOCK` pointing at an agent-controlled socket; user could not confirm in the unverifiable case). **A `blocked` value FAILS the readiness gate - the push MUST NOT proceed.**
  
  This is a required predicate field - §4.2 applies to EVERY push including sandbox-exits (no `n/a-sandbox-exit` sentinel; sandbox pushes must verify credentials too). A "ready to push" claim requires `yes` OR `user-confirmed-unverifiable`. The pre-PR-push state predicate is **11 fields** (1-9 above + `pushCredentialsVerified` + `preCreationReviewStatus`); the `sandboxPriorExposureConfirmation` field remains the always-present informational twelfth entry in the read-back block.

**Sandbox-exit record** (used when the pre-PR-push pre-check exits because the current push is personal-sandbox / backup-only): write the standard minimum canonical shape PLUS `branchWideSweepStatus: not-applicable`, the booleans `isFirstReviewExposurePush: false` + `remoteExposureExists: <true|false per actual remote history>`, AND `pushCredentialsVerified: <yes | user-confirmed-unverifiable | blocked>` per §4.2 (NOT a `n/a-sandbox-exit` sentinel - credentials must be verified for sandbox pushes too; record the real verification outcome). Other 11-field-predicate keys (`baseRef`, `baseSha`, `sweepHeadSha`, `perCommitAuditCoverage`, `cleanupBucketOutcomes`, `rerunConditionsChecked`, `preCreationReviewStatus`) may be written as the literal sentinel `n/a-sandbox-exit` (NOT omitted - predicate completeness still requires the keys to appear). The record is a normal `done` phase-state record, not a "skipped" record; it documents that the pre-PR-push playbook explicitly resolved as not-applicable for this push.

**Concrete example record - pre-PR-push first review push, sweep ran clean:**

```sql
-- Entering pre-PR-push phase (intake done, booleans set, sweep not yet run)
INSERT INTO todos (id, title, description, status) VALUES (
  'phase-state-pre-pr-push-20240115140312',
  'Phase state: pre-pr-push @ 20240115140312',
  'phase: pre-pr-push
time_entered: 2024-01-15T14:03:12Z
playbook_viewed: .github/playbooks/pre-pr-push.md
intake_status: complete
user_approved_skips: none
baseRef: origin/main
baseSha: a1b2c3d4e5f6...
sweepHeadSha: 9z8y7x6w5v4...
isFirstReviewExposurePush: true
remoteExposureExists: false',
  'in_progress'
);

-- Completing the phase after sweep + per-commit audit run clean
UPDATE todos SET status = 'done',
  description = description || '
time_completed: 2024-01-15T14:11:48Z
perCommitAuditCoverage: [{sha: 9z8y7x6w5v4, status: done}]
branchWideSweepStatus: done-clean
cleanupBucketOutcomes: none
rerunConditionsChecked: n/a-first-push
pushCredentialsVerified: yes'
WHERE id = 'phase-state-pre-pr-push-20240115140312';
```

The INSERT captures intake-time state (booleans + sweep-input SHAs); the UPDATE captures completion-time state (sweep outcome, audit map, cleanup outcomes, push-credential verification) and flips `status` to `'done'`. The `n/a-first-push` value on `rerunConditionsChecked` is the documented sentinel for "no prior sweep to re-run-check" (see field definition above); `pushCredentialsVerified: yes` records the §4.2 outcome.

Before declaring any variant of *"ready to commit / push / open PR"*, read the recorded state back and confirm every required phase has either run (per its hard gates) OR been explicitly skipped (per User-skip policy). Do not infer state from memory.

## Phase-chain predecessor links (skip-resistance)

Three phase-state records form a chain; each later record CITES its predecessor by id so a resumed / post-compaction session can RECONSTRUCT the chain instead of inferring from a dropped summary:

- `phase-state-pre-implementation-<ts>` - the DESIGN node (chain root; the pre-implementation phase where the design panel converges `DESIGN_READY`). No predecessor ref.
- `phase-state-implementation-<ts>` - the IMPLEMENTATION node, written at the `IMPLEMENTATION CHECKPOINT` (`post-code-change.md` §2.8). Carries `design_ready_ref: phase-state-pre-implementation-<ts>` plus `status: complete` and `diff_matches_design: <yes | diverged:"...">`.
- `phase-state-post-code-change-<ts>` - the CODE-REVIEW node (the post-code-change phase where the panel converges `CODE_REVIEW_READY`). Carries `implementation_ready_ref: phase-state-implementation-<ts>`.

**Reader contract (predecessor read-back):** before emitting a later phase token (`IMPLEMENTATION_READY`, then `CODE_REVIEW_READY`), READ BACK the predecessor record by its `*_ref` id and confirm it is `done`; do NOT infer from memory. A summary-only checkpoint is NOT inherited - reconstruct from the durable record or re-run the missing gate. **Honest ceiling:** records are agent-authored, so this ENABLES reconstruction and raises forge cost; it does NOT mechanically prove temporal order. The committed `implementation-checkpoint:` LEDGER sub-block (`review-workflow-gates-sweeps.md` §2B) is the commit-time CO-PRESENCE backstop (a lossy summary - it carries the `design_ready` boolean, not this `_ref`).

## Output-write ordering for documentation playbooks

For playbooks that produce a document (`design-spec.md`, `ado-task-planning.md`):

1. Intake determines the *intended* final destination.
2. The draft is rendered in chat first, regardless of intended destination.
3. The user reviews and approves (or requests revisions) on the draft.
4. Only after approval does the agent write to the chosen destination (file / save / paste-ready output).

Never write to a file before the user has approved the content.
