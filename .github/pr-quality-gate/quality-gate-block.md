# QUALITY GATE block - canonical composite schema

This file is the **single source of truth** for the `QUALITY GATE` block: the unified publish-gate artifact that consolidates the mechanical pattern floor (gate-runner) with the multi-model panel sign-off. It is the G6 forbidden-tools prerequisite for PR-creation / draft-state mutation, emitted in the same turn as the tool call. `.github/pr-quality-gate/README.md` §1B and the `Publish gate` section of `review-workflow-gates-sweeps.md` (§2D anchor) POINT here; they do not redefine the schema.

## Honest ceiling (read first)

The block is a **composite artifact with two provenance regions**:

- The **mechanical region** is emitted by `gate-runner.ps1`/`.sh` from the rg-battery. It is **CI-reproducible**: the `quality-gate-check.yml` workflow re-runs gate-runner headless on every push and re-derives these fields exactly, so a fabricated mechanical value (e.g. a hand-typed `gate_status: READY` while live hits exist) is caught at merge (re-run -> BLOCKED -> mismatch). This region is the **merge-blocking remote backstop** - a mechanical floor, NOT "non-bypassable" (`--no-verify` bypasses the local run; the remote check is the backstop).
- The **agent-appended region** is filled by the agent/panel. It is **ASSERTED, NOT CI-verified**: CI does not re-derive the panel dispositions, the slate, the resolutions, the same-state recheck, or the publish-authorization. An agent that skips the panel can hand-type these fields and CI will not catch it. The detective backstops are the HIGH catalog slug `pr-creation-or-push-without-quality-gate-block` (per-commit `core_rules_acknowledged` enumeration) and the §0 publish SENTINEL + `ask_user`, plus the pre-push publish-gate receipt (`scripts/check-publish-gate-prepush.ps1`) that mechanically blocks a governed branch PUSH lacking a fresh (remote + branch + commit)-bound receipt (local-only; `--no-verify` / pwsh-absent bypass). `gh pr create` is genuinely unhookable - no client-side hook fires at PR creation - so the publish authorization can never be mechanically gated at create time. This mirrors the comment-audit ("SHA binds text, not approval") and identity ("modeled-only") ceilings.

**`gate_status: READY` is the MECHANICAL floor only; it is NOT publish authorization.** Publishing is authorized only when the full G6 AND-list passes (see Publish authorization) - which includes the agent-asserted `pr_creation_status`, `convergence_result`, `must_fix_unresolved: 0`, `rule_coverage_passed: true`, `commit_approval`, and `same_state_recheck`. Reading a green `gate_status` as "ship it" is the overclaim-by-juxtaposition this split exists to prevent.

## Block format

```
QUALITY GATE
  # --- gate-runner mechanical, CI-reproducible (CI re-derives these EXACTLY at `-Mode full` [the CI-pinned superset]; a fabricated value is caught at merge) ---
  catalog_revision: <SHA of pattern-catalog.md at HEAD of CopilotInstructions clone>
  prefs_revision: <SHA of coding-preferences.md at HEAD of clone>
  runner_version: <gate-runner self-reported version>
  base_sha: <panelBaseSha = merge-base(base_tip_sha, panelHeadSha)>
  base_remote: <configured remote name>
  base_branch: <approved branch>
  base_url: <configured remote URL>
  base_tip_sha: <ls-remote tip SHA>
  head_remote: <push remote name>
  head_url: <approved push URL>
  head_owner: <case-preserving owner>
  head_nwo: <case-preserving owner/repo>
  base_nwo: <case-preserving owner/repo>
  base_identity: <normalized host/owner/repo>
  head_identity: <normalized host/owner/repo>
  gh_host: <resolved host>
  base_project_path: <URL path for forge>
  head_project_path: <URL path for forge>
  head_sha: <full 40- or 64-hex SHA of current HEAD>
  diff_scope: <N files, +<X>/-<Y> lines>
  patterns_run: <N>                            # 0 mechanically signals empty-battery
  required_rule_ack: [<HIGH-tier review-pass-only slugs that require acknowledgement>]   # gate-runner emits the LIST (mechanical); the per-slug ack (core_rules_acknowledged) is agent-asserted
  rg_flagged_sites:                            # present ONLY when rg matched sites
    <slug>: [<file:line>, ...]
  findings:
    - pattern: <slug>
      scope_mode: diff-scoped | tree-scoped | hybrid | review-pass-only | checker-scoped
      tier: HIGH | MEDIUM | LOW
      hits: <count> | review-required
      sites: [<file:line> - <1-line signature>, ...]
  # --- gate-runner-echoed agent inputs / -PrRef-gated (NOT CI-verified: the CI workflow runs `-Mode full` with no `-PrRef`, so these are not re-derived) ---
  panel_mode: full | triage | lint-only
  pr_ref: <PR ref | empty>
  anti_recidivism_preamble:                    # -PrRef-gated; present ONLY when prior panel-miss slugs apply for the PR ref (the §1A.2 anti-recidivism forcing function)
    pr_ref: <ref>
    prior_slugs: [<slug>, ...]
  # --- agent-appended panel dispositions (ASSERTED, NOT CI-verified) ---
  emission_phase: initial-pending-user-approval | ready-re-emitted-after-user-approval
  invocation_mode: via-publish-gate | direct-invocation-dry-run-only
  re_run_triggers: <[trigger, ...]>
  pattern_preflight_skip_status: ran | catalog: empty-battery | catalog: skipped-no-production-diff
  findings_disposition:                        # one per mechanical findings/sites hit; no entry for a non-hit site
    - pattern: <slug>
      site: <file:line>
      classification: pending | applied | already-applies | not-applicable | dismissed-source-grounded | routed-deferred
      evidence_or_rationale: <file:line-range> for applied; rationale for not-applicable per Delta K rubric
  preferences_compliance:
    - <slug>: ok | violated (<file:line>)
  panel_mode_receipt: <ask_user call-ref + quoted user-response substring>   # required for triage|lint-only; absent for full
  slate:                                       # absent for lint-only; STAYS enumerated (proves the floor)
    - slot 1: <model> <family> <role> [substituted from <requested>: <reason>]
  slate_substitutions: <[] or list>
  convergence_model: unanimous
  convergence_result: passed | failed
  panel_rounds: <N>
  dropped_reviewers: <[] or list>
  replacement_reviewers: <[] or list>
  prior_commit_panel_dispositions: <"none - <reason>" or compacted list>   # anti-anchoring: the audit echo of priors
  panel_coverage:                              # STAYS enumerated (coverage-mode is fakeable as a bare scalar)
    - mode: full-whole-branch | carry-forward-authorized  scope: <panelBaseSha>..<panelHeadSha>  commits: <N>  carry-forward-ref: <ask_user ref | n/a>  carried: <range | n/a>
  resolution:                                  # every finding has a status; STAYS enumerated
    - [<category 1-11>] <severity> [<reviewer>]: <finding>: <status>: <citation>
  must_fix_unresolved: <count>
  rule_coverage_passed: true | false           # true iff every required_rule_ack slug is dispositioned in core_rules_acknowledged
  routed_deferred_with_tracker:                # C2 deferral proof; STAYS enumerated
    - <finding> -> <tracker URL> (ask_user: <call ref>)
    - ... (default: [])
  bootstrap_token_status: <not-applicable | present-in-approved-and-live-body | removed-revokes-P-self-check>
  approved_title_sha256: <SHA-256 of exact approved UTF-8/LF title>
  approved_body_sha256: <SHA-256 of exact approved UTF-8/LF body>
  pr_text_scan: <clean | tier1-fail: <surface:marker,...> | tier2-warn: <surface:marker,...>>
  commit_approval: present
  same_state_recheck: passed | not-yet-rechecked
  subagent_ask_user_calls: 0
  pr_creation_status: READY-pending-user-approval | READY-re-emitted-after-user-approval | DRY-RUN-INFO-ONLY | BLOCKED - <reason>
  # --- mechanical floor verdict (gate-runner) ---
  gate_status: READY | BLOCKED - <reason>
```

**Why the enumerations stay enumerated** (not collapsed to bare scalars): `slate`, `resolution`, `routed_deferred_with_tracker`, and `panel_coverage` are the four forcing functions - counts AND coverage-mode are fakeable as bare scalars, so the per-item keys are the forcing function that makes a skipped step visible. The canonical form above is what the orchestrator computes; the caveman chat form (below) keeps these four enumerated even when scalars are pipe-collapsed.

**`gate_status` is binary and mechanical**: gate-runner sets `BLOCKED - <reason>` iff any pattern has `hits > 0`, else `READY` - based on raw rg hits only, never on the agent's classification/resolution. A legitimately `not-applicable` / `routed-deferred` finding still yields mechanical `BLOCKED` + a non-zero gate-runner exit; the agent's `findings_disposition` + `must_fix_unresolved` is the resolved verdict. The CI workflow treats mechanical `BLOCKED` as a hard fail (merge-blocking floor); a disposition that resolves a raw hit is recorded in the agent-appended region, which CI does not read - so disposition reconciliation is an agent + human-review responsibility, and CI is deliberately the stricter mechanical floor.

## BLOCKED-* taxonomy (`pr_creation_status`)

The agent-asserted `pr_creation_status` is the publish-readiness signal (distinct from the mechanical `gate_status`):
Bootstrap-token status tracks only P's self-application; it never changes the §2D panel, publish gate, or mechanical `gate_status`.


- `READY-pending-user-approval` - initial emission, end of synthesis turn.
- `READY-re-emitted-after-user-approval` - PR-creation tool-call turn, after the §0 user-approval `ask_user` returns + same-state re-check passes.
- `DRY-RUN-INFO-ONLY` - direct invocation outside the publish flow; never sufficient to publish.
- `BLOCKED - <N> must-fix unresolved` - must-fix findings still pending.
- `BLOCKED - slate-floor violated` - slate composition fell below the `panel-policy.md` floor.
- `BLOCKED - bootstrap-token-removed` - the approved or live body lacks the token; P's own check is now owed and has not run on the current head. This clears when P's check passes; it never changes §2D `gate_status`.
- `BLOCKED - same-state-check-failed` - HEAD / base / commit-count drifted between initial and re-emission.

## Same-state re-check transition procedure

`same_state_recheck` and `pr_creation_status: READY-re-emitted-after-user-approval` are AGENT-ASSERTED (CI does not re-derive them). gate-runner pre-seeds `same_state_recheck: not-yet-rechecked` in its raw output, but the field sits in the agent-appended region because its meaningful value (`passed`) is set by the agent; the agent overwrites the pre-seed when it assembles the canonical block. Before each G6 call, re-run the shared pre-call checks in the G6 section: local HEAD equals `head_sha` and `panelHeadSha`; the advertised base tip equals the recorded `base_tip_sha`; its merge-base equals `panelBaseSha`; and catalog/preferences still match their recorded revisions. Class A additionally checks the advertised head ref before create. Class B checks the live review before mutation. Class C binds the literal push URL, SHA refspec, target and options instead of checking a not-yet-created head ref. Post-call live verification is mandatory for every supported tool.

## G6 tool binding and verification

Every forbidden publish or review-state mutation tool is classified as Class A, B, or C before invocation. A tool without an explicit row below is unsupported: stop; the user publishes outside the agent or aborts. Do not substitute raw REST, another forge, MCP, or an unlisted command.

### Common pre-call conditions

Before every G6 call:

- `git rev-parse HEAD == head_sha == panelHeadSha`.
- Re-resolve `base_tip_sha` with `git ls-remote <base_url> refs/heads/<base_branch>`, fetch the exact remote and branch if its object is absent locally, verify the fetched tip still matches, and recompute `panelBaseSha = git merge-base <base_tip_sha> <panelHeadSha>`.
- Re-check catalog and preferences currency against `catalog_revision` and `prefs_revision`.
- Every repo, base, head branch, review id, title, body, and draft-state argument the command carries equals its approved literal. The exact command is displayed for approval.
- For title/body calls, bind inline UTF-8/LF variables; their SHA-256 values, shown as 8-hex prefixes in the approval prompt, must match `approved_title_sha256` and `approved_body_sha256`. Do not pass files, stdin, templates, editor sentinels, or environment overrides.
- On Windows, refuse `.cmd`/`.bat` executables and PATHEXT wrappers that run through `cmd.exe` for title/body calls. For Azure CLI use `<CLI2>\python.exe -IBm azure.cli repos pr ...`; otherwise stop. Native binaries and POSIX `#!` wrappers are allowed.

### Tool classes

| Class | Operation | Required pre-call binding | Post-call verification |
| --- | --- | --- | --- |
| A | Create review from pushed branch | `git ls-remote <head_url> refs/heads/<branch> == panelHeadSha`; exact command template below | Parse the review id only from zero-exit captured stdout+stderr; require exactly one id. Fetch live view and verify head SHA, target, source repo/branch, draft, title and body. |
| B-draft | Draft-state transition of an existing review | Live pre-view for the approved id must match head SHA, base branch, head repo and approved title/body; draft state must be opposite the requested final state. Exact command template below. | Live post-view for the same id must match head SHA, base, head repo/branch, requested draft state, title and body. |
| B-text | Title/body update of an existing review | Live pre-view for the approved id must match head SHA, base branch and head repo; draft state must equal the approved (unchanged) state. No title/body pre-check. Exact command template below. | Live post-view for the same id must match head SHA, base, head repo/branch, unchanged draft state, and approved title and body. |
| C | Push that creates/updates a review | No head ls-remote. Bind the literal approved destination URL, SHA source `panelHeadSha`, exact destination ref, exact push-option list, and base target in the approval. | Parse review id from zero-exit captured stdout+stderr where applicable; verify current head SHA, target, and live title/body. Gerrit has no body and cannot grant G7 exemption. |

Argument templates (all bracketed values are approved literals):

For GitHub, resolve `gh_host` from the approved `base_url`: HTTPS uses the lowercased URL host with port stripped; SSH uses the `hostname` from `ssh -G <url-host>` (lowercased, port ignored). Normalize `ssh.github.com` to `github.com`; do not infer hosts from alias names. If SSH resolution fails, ask the user to record `gh_host` or stop. If `gh_host` is not `github.com`, confirm the authenticated GHES host before any `gh` call. Pass `--repo <gh_host>/<base_nwo>` to every `gh pr` call and `--hostname <gh_host>` to every `gh api` call; never depend on ambient `GH_REPO` or `GH_HOST`.

- GitHub same-repository Class A: `gh pr create --repo <gh_host>/<base_nwo> --base <base_branch> --head <branch> --title <title> --body <body> [--draft]`.
- GitHub cross-repository Class A: compare `head_identity` and `base_identity`; query `gh api --hostname <gh_host> users/<head_owner> --jq .type`. For a User, use `gh pr create --repo <gh_host>/<base_nwo> --base <base_branch> --head <head_owner>:<branch> --title <title> --body <body> [--draft]`. For an Organization or failed type lookup, use `gh api --hostname <gh_host> -X POST repos/<base_nwo>/pulls -f title=<title> -f body=<body> -f base=<base_branch> -f head=<head_owner>:<branch> -f head_repo=<head_nwo> [-F draft=true]`.
- GitHub Class B-draft: `gh pr ready <id> --repo <gh_host>/<base_nwo> [--undo]`. GitHub Class B-text: `gh api --hostname <gh_host> -X PATCH repos/<base_nwo>/pulls/<id> -f title=<title> -f body=<body>` (REST PATCH has no `draft` field). Pre-view and post-view: `gh pr view <id> --repo <gh_host>/<base_nwo> --json headRefOid,baseRefName,headRepository,headRepositoryOwner,isDraft,title,body`. Require `headRepository.nameWithOwner` to equal `head_nwo` case-insensitively and `headRepositoryOwner.login` to equal `head_owner`.
- GitLab Class A: resolve base and head hosts (including SSH via `ssh -G`) and require equality. Resolve source project id with `glab api --hostname <host> projects/<url-encoded-head-project-path>` and parse `.id` from stdout JSON. Use `glab mr create --repo https://<host>/<base_project_path> --head https://<head_host>/<head_project_path> --source-branch <branch> --target-branch <base_branch> --title <title> --description <body> [--draft]`. View with `glab mr view <id> --repo https://<host>/<base_project_path> --output json`.
- GitLab Class B-draft: pre-view must match reviewed SHA, target, source project id, source branch, approved title/body, and the opposite draft state. Mutate with `glab mr update <id> --repo https://<host>/<base_project_path> --ready|--draft`; post-view must match final state and text.
- GitLab Class C: `git push <approved_url> <panelHeadSha>:refs/heads/<branch> -o merge_request.create -o merge_request.target=<base_branch> -o merge_request.title=<title> -o merge_request.description=<body>`. Allow only when title has no LF and body has no LF or backslash; otherwise refuse before pushing and offer Class A after a normal push.
- Gitea Class A: same-project only. Resolve exactly one `tea login list` login whose URL host equals the base host; use `tea pr create --login <login> --repo <base_project_path> --base <base_branch> --head <branch> --title <title> --description <body>`. Cross-repository Gitea is unsupported. Class B is unsupported unless a pinned update command is verified. View with `tea pr <id> --login <login> --repo <base_project_path> --output json`.
- Gitea AGit Class C: `git push <approved_url> <panelHeadSha>:refs/for/<base_branch> -o topic=<branch> -o title=<title> -o 'description={base64}<base64-utf8-body>'`. Keep the entire description option as one argv element. The topic is an approved literal. View the live PR and require `head.sha == panelHeadSha`, `base.ref == base_branch`, and live title/body equality. On an existing topic, the live body must already equal the approved body because AGit does not update it.
- Azure DevOps Class A: parse only these approved URL forms: `https://dev.azure.com/<org>/<project>/_git/<repo>`, `<org>@vs-ssh.visualstudio.com:v3/<org>/<project>/<repo>`, `git@ssh.dev.azure.com:v3/<org>/<project>/<repo>`, or `https://<org>.visualstudio.com/<project>/_git/<repo>`. Parse failure stops. Same-project only. Use `az repos pr create --org https://dev.azure.com/<org> --project <project> --repository <repo> --source-branch <branch> --target-branch <base_branch> --detect false --title <title> --description <body> [--draft true]`.
- Azure DevOps Class B-draft: pre-view with `az repos pr show --id <id> --org https://dev.azure.com/<org> --detect false` must match reviewed SHA, target, source branch, approved title/body, and opposite draft state. Mutate with `az repos pr update --id <id> --org https://dev.azure.com/<org> --detect false --draft true|false`; post-view must match final state. Check `lastMergeSourceCommit.commitId`, `sourceRefName == refs/heads/<branch>`, `targetRefName == refs/heads/<base_branch>`, title, description, and `isDraft`.
- Gerrit Class C: `git push <approved_url> <panelHeadSha>:refs/for/<base_branch>`. Parse the change number from the successful push's captured stdout and stderr. For SSH, verify with `ssh -p <port> <user>@<host> gerrit query --format=JSON --current-patch-set change:<n>`. For HTTPS, derive `<context>` from the approved URL path and user confirmation (possibly empty), strip one leading `a/` auth marker after it, and derive `base_project_path` from the remainder minus `.git`; query `GET https://<host>/<context>a/changes/<n>?o=CURRENT_REVISION`, stripping the `)]}'` XSSI prefix. Require the current patch set revision to equal `panelHeadSha`, `project == base_project_path`, and `branch == base_branch`. Gerrit has no live PR body; G7 exemption is unavailable.

Class C pushes use the literal approved URL, never a remote name; it must equal `git remote get-url --push <head_remote>`. The refspec source is the literal `panelHeadSha`, never symbolic `HEAD`. Bind the exact push-option list and target in the approval. The target must be explicitly bound to `base_branch`; GitLab uses `merge_request.target`, Gerrit/Gitea use `refs/for/<base_branch>`. GitLab post-view also checks `.source_project_id` against the recorded lookup id and `.source_branch == <branch>`. Gitea Class A post-view checks `.head.ref == <branch>`; Azure Class A post-view checks `sourceRefName == refs/heads/<branch>`. Gerrit change number candidates come from the successful push's captured output; select only the candidate whose current revision is `panelHeadSha` if output is ambiguous. Parse the review id only from that successful publishing command's captured stdout and stderr, after a zero exit code; require exactly one candidate. For ambiguous Gerrit output, select only the change whose current revision equals `panelHeadSha`, otherwise stop. Head SHA and target verification come only from the post-call view stdout.

Only these extras are allowed: GitHub `--title`, `--body`, `--draft`; GitLab `--title`, `--description`, `--yes`, `--draft`, `--remove-source-branch`; Gitea `--title`, `--description`; Azure `--title`, `--description`, `--draft`; REST `-f title=` and `-f body=` (Organization-head Class A `POST` and Class B-text `PATCH`), `-F draft=true` (that `POST` only; `-F draft=` is forbidden on `PATCH`). Refuse `--web`, `--fill*`, `--recover`, `--body-file`, `--description-file`, `--template`, `@file`, stdin/editor sentinels, repeated pinned flags, or environment overrides in the same command, including `GH_REPO`, `GH_HOST`, `GITLAB_HEAD_REPO`, or `AZURE_DEVOPS_EXT_*`. Non-interactive calls supply title and body explicitly.

### Live-state and text comparison

Before every Class B mutation, the live review must match the approved id, `panelHeadSha`, base branch and head repository. Class B-draft also requires the approved title/body already live and the draft state opposite the requested final state; Class B-text requires the draft state equal to the approved (unchanged) state and has no text pre-check. GitLab and Azure DevOps have no pinned Class B-text template; their title/description updates are unsupported. After every successful create, mutation or Class C push, read the forge's live view stdout. Require head SHA, base, source repository/branch (where the operation has them), draft state, title and body to equal their approved values. Gerrit instead verifies the current revision, project and target branch. Normalize CRLF to LF on both text operands, trim the title and remove one trailing newline from the body; otherwise compare exactly. Any mismatch fails and requires user direction; never claim done, ready, or exempt.

At Step 8, show the exact approved title and body and the first eight hex digits of each SHA-256 (UTF-8/LF). Record the full hashes. Bind the strings with non-interpolating literals; immediately before the G6 call, hash the variables and require equality with the recorded full hashes. Pass only those variables as inline arguments. Do not pass files, stdin, templates, editor sentinels, or environment overrides. On Windows, refuse `.cmd`/`.bat` tools and any executable resolved through `cmd.exe`/PATHEXT for title/body calls. For Azure CLI, use `<CLI2>\python.exe -IBm azure.cli repos pr ...`; if unresolved, stop. Native binaries and POSIX `#!` wrappers that forward argv unchanged are allowed.

The bootstrap token is valid only when BOTH the Step 8 approved body and live body contain the exact `BOOTSTRAP-EXEMPTION: <name>` token. Body drift invalidates the exemption and requires P's own check. Gerrit cannot satisfy this condition.

### Publish authorization

G6 forbidden tools (`gh pr create`, `gh pr ready`, `gh api .../pulls`, and the full §1B enumeration) are blocked unless a QUALITY GATE block is present in the current turn with **ALL** of the following. The publish authorization is the FULL AND-list, NOT the bare mechanical `gate_status`:

- `gate_status: READY` (mechanical floor passed) **AND**
- `pr_creation_status: READY-re-emitted-after-user-approval` (the publish authorization)
- `head_sha` equals the approved `panelHeadSha` at tool-call time (same-state)
- `catalog_revision` and `prefs_revision` match the current SHAs at tool-call time (currentness)
- `same_state_recheck: passed` (per the transition procedure)
- `must_fix_unresolved: 0` (or all such findings have `routed_deferred_with_tracker` with `ask_user` evidence), with every required disposition present
- `rule_coverage_passed: true` (every HIGH-tier review-pass-only slug dispositioned)
- For `panel_mode: full|triage`: unanimous `convergence_result: passed` on the final artifact AND `dropped_reviewers: []` (or replacements present)
- For `panel_mode: triage|lint-only`: `panel_mode_receipt` present, with `ask_user` call-ref + quoted user-response containing the literal mode-acknowledgment token (`triage` is unavailable for instruction-set changes; `lint-only` runs no panel and is unavailable for instruction-set changes)
- For `panel_mode: lint-only`: the slate / panel disposition fields absent (no-panel carve-out)
- `pr_text_scan: clean` (`tier1-fail` BLOCKS creation until markers are stripped + re-emitted clean; `tier2-warn` is surfaced, not blocking; the `pr-text-check.yml` CI job is the merge-blocking backstop)
- `preferences_compliance` has no `violated` entries with `severity: blocking` (waived via `ask_user` if needed)
- `commit_approval: present` (the §0 commit-approval gate applies in ALL repos)
- The operation-specific pre-call and post-call row above is satisfied. Missing live verification is FAIL, never a pass.

## Disclosed narrowings vs the retired multi-model-review (§2D) system

This unified gate replaces the older `multi-model-review` PATTERN PREFLIGHT + PRE-PR REVIEW COVERAGE blocks. Two coverage deltas are disclosed honestly (neither is a silent loss):

1. **Catalog narrowing.** `pattern-catalog.md` (generated from `pattern-catalog.sources/`) is a leaner CROSS-PROJECT battery, NOT a 1:1 carry of the deleted project-specific seed (`pr-review-pattern-catalog*.md`). Project-specific patterns belong in the *consuming project's own* catalog, not CopilotInstructions.
2. **FP-registry narrowing (distinct from #1).** The retired `known-false-positives.md` held SITE-LEVEL FP memory (`fps_recognized: FP-N -> paths`) so known-good sites were not re-flagged run-over-run. gate-runner's FP mechanism is a PER-PATTERN `fp_slug` catalog column, NOT a site-level registry. So deleting the registry drops durable site-level FP memory: the panel now re-dismisses known-good sites per-run against the catalog's inline `FP-N` entries (agent-asserted). This is a separate, disclosed delta.

## Chat-emission form (caveman)

Chat emits `QUALITY GATE` with scalars collapsed to pipe-KV; the FOUR enumerations - `slate` (proves the floor), `resolution` (per-finding status+citation), `routed_deferred_with_tracker` (C2 deferral proof), and `panel_coverage` (cited `full-whole-branch` vs `carry-forward-authorized` + `ask_user` ref) - STAY enumerated (counts and coverage-mode are fakeable as bare scalars). The canonical form above is the form the orchestrator computes; the keys are the forcing function. On re-emission, the compressed form is sufficient if the SHAs are unchanged.
