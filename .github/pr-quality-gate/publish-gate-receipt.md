# Publish-gate receipt - canonical schema

Single source of truth for the pre-push **publish-gate receipt** and the **PUBLISH BOUNDARY SENTINEL**.
`pre-pr-push.md` and `pre-pr-creation-review.md` POINT here (do not redefine the schema). Enforced by
`scripts/check-publish-gate-prepush.ps1` (step 3 of `.githooks/pre-push`).

## What it is

A gitignored worktree receipt at `.github/pr-quality-gate/audits/publish-gate-receipt` that authorizes a
push which publishes reviewable code. It mirrors the `check-signoff.ps1` pattern: object-bound, identity-gated
(no-op on any consuming repo), honest (bypassable - see ceiling). It is the mechanical backstop the RCA
identified as missing: the branch-level publish/sweep boundary had NO hookable enforcement, so a compound
"push + PR" crossed it on execution momentum.

## Honest ceiling (read first)

The gate mechanically requires a FRESH, push-specific (remote + destination-ref + tip-commit) attestation to
EXIST at push time. It does NOT prove the panel / sweeps actually ran - the receipt is agent-authored (same
ceiling as the `QUALITY GATE` block; see `quality-gate-block.md`). Value = forcing function + hard stop +
recall lift, not proof-of-panel. Bypass ceiling (documented, not closed): `git push --no-verify`,
`git -c core.hooksPath=`, `git send-pack`, forge REST/MCP ref-creation, non-hook clients, and **`pwsh`
absent** (every local pwsh gate skips; CI cannot reproduce this local-only receipt). `gh pr create` from an
already-pushed tip is still NOT hook-gated (that boundary stays modeled: the SENTINEL below + the detective
slug `pr-creation-or-push-without-quality-gate-block` + the CI `quality-gate-check.yml` rg-floor). The
identity gate keys on repo identity (`Test-IsInstructionsRepo`), not the remote alias; the receipt binds to
the normalized `-RemoteUrl` push destination, falling back to `-RemoteName` (default `origin`).

## Which pushes are governed

Per pre-push ref-update line `<local-ref> <local-sha> <remote-ref> <remote-sha>`:

- **Governed** (needs a receipt row): `local-sha` is non-zero AND `remote-ref` matches `^refs/(heads|for)/`
  (a branch, or a Gerrit `refs/for/*` review ref). New-branch pushes (`remote-sha` all-zero) are governed.
- **Exempt** (no row): branch deletes (`local-sha` all-zero), tags (`refs/tags/*`), notes (`refs/notes/*`),
  any other namespace.
- **Multi-ref**: a push containing MORE THAN ONE governed update is REJECTED ("push branches separately") -
  the publish gate + panel + phase-state attest ONE branch.

## Receipt schema

Exactly one authorizing row for the governed update, plus one `reads=` line per required playbook:

```
publish_gate_ready: <turn-ref> remote:<normalized-remote-identity> dst:<remote-ref> sha:<40-hex tip commit>
reads=.github/playbooks/pre-pr-push.md@<token>
reads=.github/playbooks/pre-pr-creation-review.md@<token>
```

or (sandbox path):

```
sandbox_push_declared: <turn-ref> remote:<normalized-remote-identity> dst:<remote-ref> sha:<40-hex tip commit>
reads=.github/playbooks/pre-pr-push.md@<token>
```

Field rules:

- **marker kind** - `publish_gate_ready` (the review-path publish gate ran) or `sandbox_push_declared` (the
  user classified this push sandbox-only at the `pre-pr-push.md` sandbox pre-check). The sandbox marker
  merely DECLARES the push sandbox-only; it is NOT the §0 push approval.
- **`<turn-ref>`** - PROVENANCE ONLY: the turn that WROTE the receipt (after the gate converged / after the
  sandbox classification). It is NOT the §0 push-approval turn (that control is separate and unmechanized).
  The checker verifies only that the field is present.
- **`remote:`** - the normalized identity of the ACTUAL push URL: lowercase `host/owner/repo` (git URL with
  `.git` / trailing slash stripped; scp- and scheme-style both reduce to this). Compute it from
  `git remote get-url --push <remote>` normalized the same way `Get-NormalizedRemoteIdentity` does; e.g.
  `github.com/jschick04/copilotinstructions`. Use `--push` (NOT the bare fetch-URL form): the pre-push hook
  passes the PUSH URL as its `$2` and the checker normalizes that, so a repo with a distinct
  `remote.<name>.pushurl` would otherwise produce a receipt that never matches. Case-sensitive match. Binding
  the URL (not the alias name) stops a retargeted remote from reusing a receipt.
- **`dst:`** - the exact `remote-ref` of the governed update (e.g. `refs/heads/main`). Case-sensitive.
- **`sha:`** - the full 40-hex pushed TIP COMMIT (`local-sha`). Commit-bound, NOT tree-bound: a message-only
  amend / rebase / any new commit invalidates the receipt (re-run the gate). A prefix / short SHA never matches.
- **`reads=` lines** - one per required playbook, using the shared `reads=<file>@<token>` format. The `<token>`
  must equal the playbook's `read-receipt-token` AT THE PUSHED TIP (`git show <local-sha>:<path>`). Required
  set: `publish_gate_ready` -> both playbooks; `sandbox_push_declared` -> `pre-pr-push.md`. A malformed
  `reads=` line, a duplicate citation, or a stale/missing token is a violation.

Authorization is TUPLE(remote, dst, sha)-bound and reusable for the IDENTICAL state (re-pushing the same tip
to the same ref is idempotent). The receipt is NOT consumed. Any change to the tip requires a fresh row.

## Who writes it, and when

- **Review path** (`pre-pr-push.md` Step 5, after the publish gate per `pre-pr-creation-review.md` converged):
  write the `publish_gate_ready` row for the pushed tip. This happens at Step 5, BEFORE the §0 push `ask_user`.
- **Sandbox path** (`pre-pr-push.md` sandbox pre-check): after classifying the push sandbox-only, write the
  `sandbox_push_declared` row BEFORE returning to the ordinary push flow (i.e. before the §0 push `ask_user`).
- Both flows record `publishGateReceiptWritten` in the pre-PR-push state read-back.

Overwrite the file each time (one governed push = one authorizing row + its reads lines).

## PUBLISH BOUNDARY SENTINEL

A terse in-turn tripwire, emitted BEFORE every review-targeting `git push` AND every PR-creation tool, with
the same salience as the §0 `PRE-GIT SENTINEL` (not inherited - re-emit; emitting it does NOT satisfy
`ask_user`; panel convergence does NOT clear it). It POINTS to the pre-PR-push state read-back + the
`QUALITY GATE` block; it does not re-derive them.

```
PUBLISH BOUNDARY SENTINEL
intent=<first-review-push|review-response-push|pr-create> | branch=<name> | quality_gate_block=<pending|initial:tN|re-emitted:tN|blocked> | whole_branch_panel=<pending|ran:unanimous|ran:convergence-waived> | sweeps=<done|n/a|pending> | publish_gate_receipt=<written:sha<8>@<dst>|pending> | next_action=<run-publish-gate|write-receipt|ask_user-approve|push|create-pr>
```
