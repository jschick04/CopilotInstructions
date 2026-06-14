# PR Quality Gate (v5, lightweight) - Design Spec v2

Status: **DESIGN DOC - pre-implementation panel review (v2 - refined per Slot 1-4 panel feedback)**. Branch: `lightweight-gate-v5`. Parallel to `main` (current heavy system); enables A/B comparison.

## Goal

Reduce the ~1500-line playbook/catalog/FP/schema/Step 2.5/Deltas surface to ~400-600 lines of lightweight, cross-project, session-boundary-friendly enforcement, **without losing the load-bearing structure** that makes the current system enforceable.

## What's preserved (hard requirements)

- **§1B forbidden-tools gate** (PR-creation, draft-state mutation) - still gated by a block in current turn
- **§1A artifact-binding** - `PANEL CONVERGED` block format preserved; slate-mode carve-out added
- **`PRE-COMMIT GATE PASSED` block** - commit-message + staged-set commit-approval; amended to include preferences compliance check
- **User commit-approval on the staged set** for project repos - §1B explicitly enforces `commit_approval: present` (the user stages reviewed code; the agent never auto-stages)
- **Multi-reviewer panel** - auto-invoked for `full` mode (default); `triage` and `lint-only` are user-acknowledged exceptions
- **All coding preferences** - extracted to dedicated `coding-preferences.md`
- **§2B `POST-CODE-CHANGE LEDGER`** equivalents - folded into the QUALITY GATE block's per-finding fields
- **§1B forbidden-tool list preserved verbatim** from current playbook (gh, glab, tea, az, Gerrit `refs/for/*`, MCP, raw curl/Invoke-WebRequest)

## What's NEW

```
CopilotInstructions/.github/pr-quality-gate/
  README.md                  (this file)
  pattern-catalog.md         (~80 lines - 1-line entries; FP registry inline; review-pass-only prompts)
  coding-preferences.md      (~60 lines - extracted prefs with structured metadata)
  panel-policy.md            (~100-150 lines - slate composition, convergence, drops, mode carve-outs)
  quality-gate-block.md      (~30 lines - block format spec)
  gate-runner.ps1            (~150 lines - Windows / cross-platform via pwsh)
  gate-runner.sh             (~120 lines - Linux/macOS bash twin)
  invoke-panel.ps1           (~80 lines - thin launcher; reads panel-policy.md)
  data/
    findings.csv             (global, file-locked, no project identifier)
    findings.csv.lock        (lock-file convention)
    README.md                (~30 lines - schema + locking semantics)
```

## Modes (3 - replaces "caveman with cap")

| Mode | Reviewers | Output cap | rg battery | `§1A` slate carve-out | Use |
|---|---|---|---|---|---|
| `full` (default) | 4-6 (Claude + GPT + Gemini family; rubber-duck + code-review; ≥1 heavy-tier) | none | yes | none - full slate-floor applies | normal PRs |
| `triage` | 1 code-review role, any model | none | yes | `slate-mode: triage; slate-size=1; role=code-review` | mid-cost PRs where full panel is overkill |
| `lint-only` | 0 (no panel invocation) | n/a | yes | `slate-mode: lint-only; no panel invoked → slate-composition NOT applicable` | token-constrained users; PRs touching trivial scope |

**Mode activation** (CLI flag is the ONLY robust mechanism per panel feedback):
- `invoke-panel.ps1 -Mode full|triage|lint-only` (default: `full`)
- Env vars and `plan.md` flags are NOT honored - too persistent, bypass-prone
- For `triage` AND `lint-only`: SAME-TURN `ask_user` receipt required. Prompt MUST name the mode + diff scope. User response MUST contain literal acknowledgment token:
  - `triage`: response must contain `triage-acknowledged`
  - `lint-only`: response must contain `lint-only-acknowledged`
  - Prior-turn `ask_user` calls do NOT satisfy this - per-PR receipt must be fresh
- For `lint-only`, the orchestrator skips `invoke-panel.ps1` entirely and emits QUALITY GATE block with `slate: lint-only - no panel`
- Caveman-with-cap design **explicitly rejected** - 200-word cap suppresses findings, creating self-bypass surface

`triage` and `lint-only` are user-opted-in exceptions (`caveman_decision=both`). `full` preserves the hard requirement; other modes require fresh per-PR `ask_user` receipts.

## QUALITY GATE block format

Required prerequisite for all G6 forbidden-tools (PR-creation/draft-state mutation). Emitted in same turn as the tool call.

```
QUALITY GATE
  catalog_revision: <SHA of pattern-catalog.md at HEAD of CopilotInstructions clone>
  prefs_revision: <SHA of coding-preferences.md at HEAD of clone>
  runner_version: <gate-runner.ps1 self-reported version>
  panel_mode: full | triage | lint-only
  panel_mode_receipt: <ask_user call-ref + quoted user-response substring>   # required for triage|lint-only; absent for full
  base_sha: <40-char SHA of merge-base origin/<base>..HEAD>
  head_sha: <40-char SHA of current HEAD>
  diff_scope: <N files, +<X>/-<Y> lines>
  patterns_run: <N>
  findings:
    - pattern: <slug>
      hits: <count>
      classification: pending | applied | already-applies | not-applicable | dismissed-source-grounded | routed-deferred
      site: <file:line> - <1-line signature>
      evidence_or_rationale: <file:line-range> for applied; rationale for not-applicable per Delta K rubric
  fps_recognized:
    - fp: <slug>
      site: <file:line>
  preferences_compliance:
    - <slug>: ok | violated (<file:line>)
  panel:                                      # absent for lint-only
    invoked: true | false
    slate_floor_passed: true | false
    reviewers: [<slot>: <model> <family> <role>]
    convergence_model: unanimous | threshold-N% | confidence-weighted-N% | single-reviewer   # single-reviewer required under triage
    convergence_result: passed | failed
    dropped_reviewers: []
    panel_rounds: <N>
    fix_iteration_count: <N>
    must_fix_unresolved: <count>
  commit_approval: present
  same_state_recheck: passed | not-yet-rechecked
  gate_status: READY | BLOCKED - <reason>
```

**Note on `panel_mode: triage`**: `convergence_model` MUST be `single-reviewer` (not `unanimous`). Distinguishes single-voice judgment from multi-model independent verification in the audit trail.

**Same-state re-check transition procedure** (the procedure for moving `same_state_recheck: not-yet-rechecked` → `passed`):

> Before invoking any G6 tool, the agent MUST re-run ALL THREE of the following commands and compare against the values from the prior gate-runner emission:
> 1. `git rev-parse HEAD` → must match `head_sha`
> 2. `git -C <copilot-instructions-clone> log -1 --format=%H -- .github/pr-quality-gate/pattern-catalog.md` → must match `catalog_revision`
> 3. `git -C <copilot-instructions-clone> log -1 --format=%H -- .github/pr-quality-gate/coding-preferences.md` → must match `prefs_revision`
>
> If ALL three match, the agent re-emits the QUALITY GATE block with `same_state_recheck: passed` in the same response as the tool call (literal carry-forward; no recomputation). If ANY of the three drifted, the agent re-runs `gate-runner.ps1` from scratch and re-emits with fresh values (`same_state_recheck: passed` only after this re-run).

**Enforcement** (§1B amendment):
- G6 forbidden tools (`gh pr create`, `gh pr ready`, `gh api .../pulls`, and the full enumeration from current §1B preserved verbatim) blocked unless QUALITY GATE block is present in current turn with `gate_status: READY` AND ALL of:
  - `head_sha` matches `git rev-parse HEAD` at tool-call time (same-state re-check - Slot 1/2 B-2)
  - `catalog_revision` matches current catalog SHA at tool-call time (currentness - Slot 1 NB-V4)
  - `prefs_revision` matches current prefs SHA at tool-call time (currentness - Slot 2/3/4 v6 finding; same hole the catalog re-check closes)
  - `same_state_recheck: passed` (per the transition procedure above)
  - `must_fix_unresolved: 0` (or all findings have `routed-deferred` with `ask_user` evidence)
  - For `panel_mode: full|triage`: `panel.convergence_result: passed` AND `panel.dropped_reviewers: []` (or replacements present)
  - For `panel_mode: triage|lint-only`: `panel_mode_receipt` MUST be present, with `ask_user` call-ref and quoted user-response containing the literal mode-acknowledgment token
  - For `panel_mode: lint-only`: `panel` section absent (consistent with no-panel-invoked carve-out)
  - `preferences_compliance` has no `violated` entries with `severity: blocking` (waived via `ask_user` if needed)
  - **`commit_approval: present` is REQUIRED in ALL repos** - the §0 commit-approval gate applies everywhere, including the instruction repo; only the extra §1B diff-review is waived for panel-certified instruction-repo edits (Slot 2 #5)

## findings.csv schema (global, file-locked, no project identifier)

```
timestamp,revision,pattern_slug,classification,finding_brief,slate_mode,finding_type
```

- `timestamp`: ISO-8601 UTC (`2026-05-24T22:30:00Z`) - deterministic, no timezone variation
- `revision`: SHA of the relevant config file for this row's finding type - catalog SHA for `finding_type=pattern`, prefs SHA for `finding_type=preference`. (Renamed from `gate_revision` for clarity per Slot 4 NB-1; same column holds either depending on row type.)
- `pattern_slug`: from `pattern-catalog.md` or `coding-preferences.md`
- `classification`: `real | false-positive | recurring-false-positive | dismissed-out-of-scope | routed-deferred`
- `finding_brief`: generic 1-line description (e.g., "XML doc mismatch on volatile field"; NOT "DatabaseToolsTabBase _disposed claim" - no project leakage)
- `slate_mode`: `full | triage | lint-only` (trend analysis stratification)
- `finding_type`: `pattern | preference` (separates rg pattern hits from prefs violations)

**Project agnosticism**: NO repo URL, NO `project_hash`, NO file paths, NO `branch` column. `finding_brief` uses generic phrasings only. Per-PR specifics stay in the QUALITY GATE block (ephemeral; not persisted).

**Why `branch` was removed**: branch names contain user identity (`<username>/...`) and project intent, re-introducing leakage. Session recovery uses `plan.md`. If branch-type stratification is needed later, a categorical `branch_type` (feature/hotfix/bugfix/release) can be added without re-introducing identity.

**Trade-off**: without `project_hash`, cannot distinguish noisy-project clusters. Aggregate-only; per-project trends require manual export.

**File locking** (Slot 1 B-4, Slot 2 #4, Slot 3 E):

Lock file: `data/findings.csv.lock`. Contains JSON with:
```
{"pid": <integer>, "host": "<hostname>", "session_id": "<uuid>", "acquired_at": "<ISO-8601 UTC>"}
```

PowerShell acquisition:
```
$lock = "$dataDir/findings.csv.lock"
$timeout = 30                                           # seconds, configurable via -LockTimeoutSeconds
$jitterMs = Get-Random -Minimum 50 -Maximum 250         # avoid thundering-herd
$deadline = (Get-Date).AddSeconds($timeout)
while ((Get-Date) -lt $deadline) {
    try {
        $fs = [System.IO.File]::Open($lock, 'CreateNew', 'Write', 'None')
        # write metadata JSON, then close. CreateNew is atomic; throws if exists.
        ...
        break
    } catch [System.IO.IOException] {
        # Lock held; check for stale
        $age = (Get-Date) - (Get-Item $lock).CreationTimeUtc
        if ($age.TotalMinutes -gt 5) {
            # Read lock metadata; verify owner process alive
            $meta = Get-Content $lock | ConvertFrom-Json
            $alive = Get-Process -Id $meta.pid -ErrorAction SilentlyContinue
            if (-not $alive -and $meta.host -eq $env:COMPUTERNAME) {
                # Stale lock from dead process on this host
                Write-Warning "Stale lock from pid $($meta.pid) ($($meta.acquired_at)); breaking"
                Remove-Item $lock
                continue
            }
        }
        Start-Sleep -Milliseconds $jitterMs
        $jitterMs = [Math]::Min($jitterMs * 2, 5000)  # exponential backoff cap at 5s
    }
}
# If $deadline reached without acquire: emit ask_user with lock holder details + STOP
```

Bash twin (`gate-runner.sh`) uses compatible atomic creation (Slot 4 NB-2):
```
LOCK="$DATA_DIR/findings.csv.lock"
DEADLINE=$(($(date +%s) + ${LOCK_TIMEOUT_SECONDS:-30}))
while [ $(date +%s) -lt $DEADLINE ]; do
    if (set -C; printf '{"pid":%d,"host":"%s","session_id":"%s","acquired_at":"%s"}\n' \
        "$$" "$(hostname)" "$SESSION_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$LOCK") 2>/dev/null; then
        break
    fi
    # Stale-lock check (same heuristic as PS): age > 5min + owner process not alive on this host
    ...
    sleep "0.$(( RANDOM % 200 + 50 ))"  # jitter 50-250ms; double on retry, cap 5s
done
```

The `(set -C; ...)` idiom in bash makes file creation atomic (equivalent to PowerShell `CreateNew`). Both scripts honor the same lock file format, so cross-platform mixed-runner scenarios (CI runs bash, dev runs PS) don't corrupt the CSV.

**Stale-lock heuristic**: lock age > 5 minutes AND lock metadata says owner pid is dead on owner host → break the lock (emit warning). Locks from a different host always treated as live (don't try to probe a remote process).

## Catalog grammar (`pattern-catalog.md` formal spec - Slot 3 #1)

Each pattern entry is a single line in a markdown table:

```
| slug | scope_mode | params | review_pass_only_prompt | fp_slug |
```

- `slug`: lowercase ASCII identifier (`[a-z0-9-]+`), UNIQUE across the catalog. Parser MUST exit 2 with `catalog parse error: duplicate slug '<slug>' at line N` on duplicate.
- `scope_mode`: enum `diff-scoped | tree-scoped | hybrid | review-pass-only | checker-scoped`. Other values → exit 2.
- `params`: JSON object inline in the markdown table cell (parallels `coding-preferences.md` schema). Pipe characters inside JSON values MUST be escaped as `\|` per markdown table cell rules. Parser unescapes before JSON parse. Schema depends on `scope_mode` - see cross-field constraints below.
- `review_pass_only_prompt`: for `scope_mode=review-pass-only`, this is the §2D-style reviewer instruction that `invoke-panel.ps1` forwards to reviewer prompts. Empty string for other scope_modes.
- `fp_slug`: optional cross-reference to inline FP entry (`fp-1`, `fp-2`, ...); empty if none.

Comments: lines starting with `<!--` and ending with `-->` (markdown HTML comments) are ignored by the parser.

Parse failures (duplicate slug, invalid scope_mode, malformed JSON in `params`, malformed glob, malformed table row) → gate-runner exits 2 with stderr message naming line + cause.

**Cross-field validity constraints** (Slot 3 v6+v7 finding - prevent silently-misconfigured or ambiguous rows):

Single-row representation (no implicit row-pairing); `params` JSON shape determined by `scope_mode`:

| `scope_mode` | required `params` shape | `review_pass_only_prompt` |
|---|---|---|
| `diff-scoped` | `{"pattern":"<rg-regex>","glob":["<glob1>","<glob2>",...]}` (`glob` non-empty array required for diff-scoped - empty → exit 2) | MUST be empty |
| `tree-scoped` | `{"pattern":"<rg-regex>","glob":["<glob1>",...]}` (`glob` may be empty array; falls back to `<source-tree>`) | MUST be empty |
| `hybrid` | `{"tree":{"pattern":"...","glob":[...]},"diff":{"pattern":"...","glob":[...]}}` (BOTH `tree` and `diff` sub-objects required; sub-rules: `tree.pattern` non-empty + `tree.glob` MAY be empty (falls back to `<source-tree>`, matches `tree-scoped` semantics); `diff.pattern` non-empty + `diff.glob` MUST be non-empty (matches `diff-scoped` semantics; empty → exit 2 with `params.diff.glob` named in stderr)) | MUST be empty |
| `review-pass-only` | `{}` (empty object - no rg discovery) | MUST be non-empty |
| `checker-scoped` | `{"checker_id":"<id>"}` (script-mechanized; not rg-scanned or lens-forwarded; parity-gated by `check-checker-registry.ps1`) | MUST be empty |

`fp_slug` non-empty → catalog file MUST contain a corresponding `### FP-<slug>` section; orphan = exit 2.

Violations of any cross-field constraint → exit 2 with stderr message naming line + which constraint failed.

**No implicit row pairing**: every pattern is one row. Hybrid patterns carry their tree-scoped and diff-scoped queries in a single `params` JSON object (the `tree` and `diff` sub-objects). This eliminates the v7 ambiguity where "hybrid" could mean "two rows" OR "one row with scope_mode=hybrid" - only the latter is valid in v8.

FP entries are sub-sections in the same catalog file, NOT a separate file. Format: `### FP-<N>: <slug>` with `Technical claim`, `Why FP`, `Recurrence pattern`, `Canonical dismissal template`, `Mitigation candidates` subsections (mirrors current v4 `known-false-positives.md` content, condensed inline).

## Idempotency contract (Slot 3 #2)

For identical inputs `(base_sha, head_sha, catalog_revision, prefs_revision, panel_mode)`, `gate-runner.ps1` (and `.sh` twin) produce byte-stable output EXCEPT for the `timestamp` field (which varies by invocation). Specifically:

- Findings sorted by `(path, line, slug)` in ordinal byte-order (NOT culture-sensitive; use `[StringComparer]::Ordinal` in PS, `LC_ALL=C sort` in bash)
- File paths normalized to repo-relative forward-slash (`src/Foo/Bar.cs`, never backslashes, never absolute paths)
- Output encoding: UTF-8 without BOM
- Line endings in emitted block: `\n` (LF), regardless of platform
- Timestamps: UTC ISO-8601 with `Z` suffix, no fractional seconds (`2026-05-24T22:30:00Z`)
- CSV row order: append-only chronological; no in-place sort
- Block field order: as documented in QUALITY GATE format above; no platform-specific reordering

This is the **byte-stable contract** - automated tests (parity test matrix below) MUST verify it.

## Cross-runtime parity (Slot 3 #5 - PS + bash twin)

`gate-runner.ps1` and `gate-runner.sh` MUST produce identical output for identical inputs. Verified via a golden-output test matrix in `tests/`:

```
tests/golden/
  case-01-clean-diff/                 # zero findings expected
    input/diff-files.txt              # list of files in diff
    input/diff-content/               # actual diff content
    expected.block                    # QUALITY GATE block expected output
  case-02-doc-impl-mismatch/          # one pattern hit
  case-03-multi-pattern-multi-site/   # complex case
  case-04-lint-only-mode/             # mode-specific block format
  case-05-triage-mode/
  case-06-fp-dismissal/
  case-07-preferences-violation/
  case-08-stale-catalog-revision/     # exit 5 path
```

Test runner: simple bash/PS that invokes both runners against each case + diffs output against `expected.block`. CI MUST run both PS-on-Windows AND bash-on-Linux AND pwsh-on-Linux configurations.

## Exit codes (gate-runner.ps1 + .sh)

- `0` - no findings (`gate_status: READY`)
- `1` - findings present, action required
- `2` - catalog/preferences parse error (config bug)
- `3` - missing dependency (git, rg)
- `4` - runtime I/O failure (file lock timeout, write failure)
- `5` - same-state re-check failed (HEAD or catalog SHA drifted mid-run)

Stderr carries diagnostic detail; stdout is the QUALITY GATE block.

**Exit 5 recovery state transition** (Slot 3 #3):

On exit 5, the orchestrator's recovery is:
1. **First exit 5 on this attempt**: auto-rerun `gate-runner.ps1` once. If second run also exits 5, escalate to step 2.
2. **Second consecutive exit 5**: emit `ask_user` quoting both invocations' stderr (showing which SHA drifted between runs); STOP. User decides whether to commit the in-flight edit, discard it, or branch.

Auto-retry is bounded to ONE attempt to prevent infinite re-run loops on a runaway edit-script. The `ask_user` is mandatory before any further action.

## panel-policy.md (slate + convergence + drops; ~100-150 lines)

Single file; orchestrator reads it before invoking `invoke-panel.ps1`. Contents (one-sentence summary per section; full prose in the actual file):

1. **Slate composition floor** by mode:
   - `full`: ≥4 reviewers; ≥1 Claude family + ≥2 GPT family + ≥1 Gemini family; ≥1 rubber-duck + ≥2 code-review; ≥1 heavy-tier
   - `triage`: 1 code-review reviewer, any model; `convergence_model: single-reviewer` (not `unanimous`); fresh `ask_user` mode-receipt required per PR
   - `lint-only`: no panel; `ask_user` mode-receipt required per PR
2. **Convergence model**: default `unanimous` for `full`. Waive floor: `threshold ≥75%` or `confidence-weighted ≥80%`. `triage` MUST use `single-reviewer`.
3. **Drop handling** (`full` mode only; `triage` and `lint-only` have no drops): 0 drops → proceed; 1 drop → launch replacement (same family, highest-capability successor); 2 drops → `ask_user`; ≥3 → hard escalate.
4. **Fix-iteration cap**: default 3 cycles. `cap-with-regressions` vs `cap-with-new-clean-categories` classification on cap-exceeded; user authorizes override or routes via G4 `routed-deferred-with-tracker-and-ask_user`.
5. **Reviewer same-state re-checks**: each reviewer's prompt MUST re-fetch `git rev-parse HEAD` at start and abort if drifted from launch SHA.
6. **Review-pass-only pattern forwarding**: `invoke-panel.ps1` reads catalog entries with `scope_mode: review-pass-only` and appends each entry's `review_pass_only_prompt` to the reviewer system prompt. Without this, doc-impl-mismatch (26/229 hits historically) is undetectable by rg alone.

## coding-preferences.md (declarative metadata - NOT arbitrary shell)

To prevent RCE (Slot 2 #2), checks are declarative - `gate-runner.ps1` has hardcoded implementations per `check_type`, with structured parameters per type. Catalog never specifies executable strings.

```
| slug | check_type | params | scope | severity |
|---|---|---|---|---|
| lock-not-object | rg | {"pattern":"private (readonly )?object _\\w+Lock","globs":["*.cs"]} | diff | blocking |
| no-coauthored-by | commit-message-rg | {"pattern":"^Co-authored-by:","target":"HEAD"} | commit | blocking |
| single-line-commit | commit-message-line-count | {"max_lines":1,"target":"HEAD"} | commit | blocking |
| sorted-usings | analyzer | {"tool":"dotnet","subcommand":"format","args":["--verify-no-changes","--include-generated","false"]} | diff | blocking |
| file-scoped-namespaces | rg-negative | {"pattern":"^namespace \\S+ \\{","globs":["*.cs"]} | diff | blocking |
| no-conventional-commit-prefix | commit-message-rg-negative | {"pattern":"^(feat|fix|chore|docs|test|refactor|style|perf|ci)(\\(.+\\))?: ","target":"HEAD"} | commit | blocking |
```

**`params` format**: JSON object inline in the markdown table cell. JSON arrays for `args` and `globs` ensure unambiguous argv element parsing (Slot 1 V7) - no string-splitting subtleties, no shell-quoting hazards. Pipe characters inside JSON values escaped as `\|` per markdown table rules; parser unescapes before JSON parse.

**`check_type` enumeration** (hardcoded in gate-runner; new types require code change, not catalog change):
- `rg`: ripgrep with `pattern` + `globs[]` → exit non-zero on match = violation
- `rg-negative`: ripgrep → expect zero hits; non-zero hits = violation
- `commit-message-rg`: rg against `git log -1 --format=%B`
- `commit-message-rg-negative`: rg-negative against same
- `commit-message-line-count`: line count of commit message body must be ≤ `max_lines`
- `analyzer`: invokes a WHITELISTED binary + WHITELISTED subcommand with `args[]` array

**RCE mitigation**:
- `params` JSON contains TYPED values per `check_type`, validated at parse time against expected schema per type (unknown keys / wrong types → exit 2)
- gate-runner has switch/case on `check_type` and constructs the invocation with explicit argument arrays (PowerShell `&` operator with array, NOT string concatenation; bash `"$@"` arrays)
- `analyzer` binary + subcommand whitelist (Slot 1 NB-V6 expanded per Slot 2 NB):

  | tool | allowed subcommands |
  |---|---|
  | `dotnet` | `format`, `build`, `test`, `restore` |
  | `eslint` | (no subcommand; flags only) |
  | `rubocop` | (no subcommand) |
  | `flake8` | (no subcommand) |
  | `mypy` | (no subcommand) |
  | `shellcheck` | (no subcommand) |
  | `clang-tidy` | (no subcommand) |

  Extend by amending gate-runner.ps1 + .sh + this list TOGETHER. Unknown tool name OR unknown subcommand → exit 2 at parse time (before any invocation).
- Glob patterns and rg patterns ARE passed through (they're regex / glob, not shell); but gate-runner treats them as data, never `Invoke-Expression`s. PowerShell `&` operator with array argument list bypasses shell parsing entirely; bash uses `"${args[@]}"` array expansion.

## Cross-project usability (bootstrap)

Consumer project does NOT clone CopilotInstructions per-project. Consumer points to a clone path via env var:
```
$env:COPILOT_INSTRUCTIONS_CLONE = "C:\Projects\CopilotInstructions"   # or ~/Projects/CopilotInstructions
& "$env:COPILOT_INSTRUCTIONS_CLONE/.github/pr-quality-gate/gate-runner.ps1" -BaseSha <sha> -HeadSha <sha> -Mode full
```

Bootstrap recovery (Slot 3 A): if clone missing OR `$env:COPILOT_INSTRUCTIONS_CLONE` not set → orchestrator emits `ask_user` with the exact clone command:
```
git clone --branch lightweight-gate-v5 https://github.com/<owner>/CopilotInstructions.git C:\Projects\CopilotInstructions
[Environment]::SetEnvironmentVariable("COPILOT_INSTRUCTIONS_CLONE", "C:\Projects\CopilotInstructions", "User")
```
+ STOP. Agent does NOT auto-clone (security: clone URL should be user-confirmed).

**Clone-path validation** (Slot 1 NB-V6 - runtime precondition):

Before reading anything from `$env:COPILOT_INSTRUCTIONS_CLONE`, `gate-runner.ps1` (and `.sh` twin) MUST verify:
1. Path exists and is a directory
2. Path contains a `.git/` subdirectory
3. `git -C <path> remote get-url origin` returns a URL matching an allowlist regex (default: `^https?://.+/CopilotInstructions(\.git)?$`; configurable via `-AllowedCloneUrlPattern`)

Any check failure → exit 3 (missing dependency / misconfigured) with stderr naming the failed check + the resolved path. Prevents misconfigured/malicious env var from pointing gate-runner at an attacker repo.

Default pattern matches any host (enterprise forks, self-hosted Gitea/Forgejo). Defenses: user-controlled env var, user-confirmed clone URL at bootstrap, `-AllowedCloneUrlPattern` for locked-down environments.

**Catalog freshness** (Slot 1 NB-V5):
- Default: `gate-runner.ps1 -Mode <mode>` does NOT auto-fetch; consumer owns clone freshness via their own `git pull` cadence
- Opt-in: `gate-runner.ps1 -AutoFetchCatalog` performs `git -C $env:COPILOT_INSTRUCTIONS_CLONE fetch origin lightweight-gate-v5 --depth 1 --quiet && git -C ... checkout origin/lightweight-gate-v5 -- .github/pr-quality-gate/` before reading catalog SHA
- **Dirty-state guard** (Slot 1 NB-V8): before any `-AutoFetchCatalog` `git checkout`, gate-runner runs `git -C <clone> status --porcelain .github/pr-quality-gate/`. If output is non-empty (uncommitted local changes in the gate folder), gate-runner refuses to auto-fetch and emits `ask_user` naming the dirty files. User must commit, stash, or discard before `-AutoFetchCatalog` proceeds. Catalog maintainers iterating on local drafts cannot lose work to a consumer auto-fetch.
- Either way, the resolved `catalog_revision` field is `git -C $env:COPILOT_INSTRUCTIONS_CLONE log -1 --format=%H -- .github/pr-quality-gate/pattern-catalog.md` (reads the clone's HEAD per Slot 4 NB-4, NOT literal `main` - works for any branch)

PowerShell + bash twins for cross-platform (Slot 1 NB-3). pwsh on Linux/macOS works for `.ps1`; pure-bash `.sh` for consumers without pwsh.

**macOS version floor**: bash twin's `sleep 0.N` requires macOS 12+ / FreeBSD 9+. Older versions truncate to `sleep 0` (functional, less efficient jitter).

## Session-boundary recovery (Slot 2 G, Slot 4 F)

Recovery model: **rerun-only**. After any session boundary (compression, restart):
1. Read `plan.md`: which PR/branch, what task
2. Read latest commit on branch: state of code
3. Run `gate-runner.ps1`: regenerate QUALITY GATE block from current state
4. If a panel was mid-flight at compression time: discard. Re-invoke via `invoke-panel.ps1` with fresh agents (no persisted in-flight panel state)

Gate-runner is fast (seconds); panel re-invocation via `invoke-panel.ps1` with fresh agents. Branch from `plan.md` (not CSV).

## Validation plan (post-build)

1. Run `gate-runner.ps1` against a known-noisy PR's HEAD from your own project (first record that PR's baseline historical-finding + false-positive counts so you have something to compare against)
2. Compare to v4 catalog recall (~89%); v5 rg-battery alone should match or exceed
3. Run `invoke-panel.ps1 -Mode full` against the same diff; verify multi-panel reviews emit `PANEL CONVERGED` block correctly
4. Run `invoke-panel.ps1 -Mode triage`; verify single-reviewer record format
5. Run `invoke-panel.ps1 -Mode lint-only` (skips panel); verify QUALITY GATE block accepts the slate carve-out
6. Stress-test file locking: 2 concurrent gate-runner sessions; verify no row corruption

## What's RETIRED on this branch (kept on `main` for A/B compare)

- `multi-model-review/pr-review-pattern-catalog.md` 252-line version → 80-line condensed catalog
- `multi-model-review/known-false-positives.md` separate file → inline FP entries in catalog
- `multi-model-review/pr-review-findings-schema.md` 97-line schema → 30-line data/README.md
- `pre-pr-creation-review.md` Step 2.5 strict format → `gate-runner.ps1` script
- `pre-pr-creation-review.md` 10-step flow → 3-step (scan → fix → commit) + same-state re-check at PR creation
- Deltas A-K accumulated in `pr-creation-mirror-prompt.md` → consolidated into catalog entries
- §2B `POST-CODE-CHANGE LEDGER` ceremony → fields folded into QUALITY GATE block
- Per-project `.github/data/` → global locked CSV at CopilotInstructions

## What's AMENDED on this branch

- `review-workflow-gates.md` §1A: add `slate-mode: full | triage | lint-only` carve-out documented in `panel-policy.md`
- `review-workflow-gates.md` §1B: forbidden-tools gate references QUALITY GATE block name + `gate_status: READY` requirement
- `review-workflow-gates-sweeps.md` §2B: LEDGER pointer says "see QUALITY GATE block in `pr-quality-gate/quality-gate-block.md`"
- `review-workflow-gates.md` PRE-COMMIT GATE PASSED: adds `preferences_compliance: <slug>: passed|violated` for every machine-checkable pref

## Open items pre-implementation panel verification

This README is the design spec; before building the other files, the 4-reviewer panel will verify:
- All 6 blockers closed (B-1 through B-6)
- All 7 NBs addressed or acknowledged
- No new bypass surfaces introduced
- Cross-document references all resolve
- Exit code contract complete
- File locking semantics correct
- Cross-platform portability adequate

Verdict required: 4/4 READY before implementation proceeds.
