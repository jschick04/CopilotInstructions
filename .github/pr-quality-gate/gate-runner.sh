#!/usr/bin/env bash
# PR Quality Gate Runner (Bash twin)
# Spec: ../README.md (PR Quality Gate v5 design doc)
# Parity contract: same output as gate-runner.ps1 for identical inputs.

set -euo pipefail

RUNNER_VERSION='0.1.0'
MODE='full'
BASE_SHA=''
HEAD_SHA=''
ALLOWED_CLONE_URL_PATTERN='^https?://.+/CopilotInstructions(\.git)?$'
AUTO_FETCH_CATALOG=0
LOCK_TIMEOUT_SECONDS=30
PROJECT_ROOT="$(pwd)"
VERIFY=0
PR_REF=''

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/yaml-emit-helpers.sh"

# ===== CLI parsing =====
while [[ $# -gt 0 ]]; do
    case "$1" in
        -BaseSha|--base-sha)               BASE_SHA="$2"; shift 2 ;;
        -HeadSha|--head-sha)               HEAD_SHA="$2"; shift 2 ;;
        -Mode|--mode)                       MODE="$2"; shift 2 ;;
        -AllowedCloneUrlPattern|--allowed-clone-url-pattern) ALLOWED_CLONE_URL_PATTERN="$2"; shift 2 ;;
        -AutoFetchCatalog|--auto-fetch-catalog) AUTO_FETCH_CATALOG=1; shift ;;
        -LockTimeoutSeconds|--lock-timeout-seconds) LOCK_TIMEOUT_SECONDS="$2"; shift 2 ;;
        -ProjectRoot|--project-root)        PROJECT_ROOT="$2"; shift 2 ;;
        -Verify|--verify)                   VERIFY=1; shift ;;
        -PrRef|--pr-ref)                    PR_REF="$2"; shift 2 ;;
        *) echo "[gate-runner ERROR] Unknown flag: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]] && { echo "[gate-runner ERROR] -BaseSha and -HeadSha are required" >&2; exit 2; }
[[ "$MODE" != "full" && "$MODE" != "triage" && "$MODE" != "lint-only" ]] && { echo "[gate-runner ERROR] Invalid mode: $MODE" >&2; exit 2; }

die() { echo "[gate-runner ERROR] $2" >&2; exit "$1"; }
diag() { echo "[gate-runner] $1" >&2; }

# ===== Dependency check =====
command -v git >/dev/null 2>&1 || die 3 'git not found on PATH.'
command -v rg  >/dev/null 2>&1 || die 3 'ripgrep (rg) not found on PATH.'
command -v jq  >/dev/null 2>&1 || die 3 'jq not found on PATH (required for JSON params parsing).'

# ===== Clone validation =====
[[ -z "${COPILOT_INSTRUCTIONS_CLONE:-}" ]] && die 3 'COPILOT_INSTRUCTIONS_CLONE env var not set.'
CLONE="$COPILOT_INSTRUCTIONS_CLONE"
[[ -d "$CLONE" ]] || die 3 "COPILOT_INSTRUCTIONS_CLONE='$CLONE' is not a directory."
[[ -d "$CLONE/.git" ]] || die 3 "'$CLONE' does not contain a .git/ subdirectory."
REMOTE_URL="$(git -C "$CLONE" remote get-url origin 2>/dev/null || true)"
[[ -z "$REMOTE_URL" ]] && die 3 "Cannot read 'origin' remote URL from '$CLONE'."
[[ ! "$REMOTE_URL" =~ $ALLOWED_CLONE_URL_PATTERN ]] && die 3 "Remote URL '$REMOTE_URL' does not match AllowedCloneUrlPattern '$ALLOWED_CLONE_URL_PATTERN'."

# ===== Auto-fetch =====
if [[ $AUTO_FETCH_CATALOG -eq 1 ]]; then
    DIRTY="$(git -C "$CLONE" status --porcelain '.github/pr-quality-gate/' 2>/dev/null || true)"
    [[ -n "$DIRTY" ]] && die 4 "Auto-fetch refused: uncommitted local changes:\n$DIRTY"
    CUR_BRANCH="$(git -C "$CLONE" rev-parse --abbrev-ref HEAD)"
    git -C "$CLONE" fetch origin "$CUR_BRANCH" --depth 1 --quiet
    git -C "$CLONE" checkout "origin/$CUR_BRANCH" -- '.github/pr-quality-gate/' >/dev/null 2>&1
fi

# ===== Drift-safeguard: verify HIGH-TIER-SLUGS.md is in sync with pattern-catalog.md =====
# Panel-time secondary defense (primary is the .githooks/pre-commit hook).
# Pure-bash verify via the sync-critical-rules.sh twin - does NOT shell out to pwsh
# (preserves the bash gate-runner's no-pwsh-required contract).
SYNC_BASH="$CLONE/scripts/sync-critical-rules.sh"
if [[ -f "$SYNC_BASH" ]]; then
    if ! bash "$SYNC_BASH" -Verify \
        -CatalogPath "$CLONE/.github/pr-quality-gate/pattern-catalog.md" \
        -OutputPath "$CLONE/.github/pr-quality-gate/HIGH-TIER-SLUGS.md" >/dev/null 2>&1; then
        die 4 "HIGH-TIER-SLUGS.md is out of sync with pattern-catalog.md in clone '$CLONE'. Run: bash '$SYNC_BASH'"
    fi
else
    diag "sync-critical-rules.sh not found in clone; skipping ack-sync drift check (clone may be at an older revision)."
fi

CATALOG_PATH="$CLONE/.github/pr-quality-gate/pattern-catalog.md"
PREFS_PATH="$CLONE/.github/pr-quality-gate/coding-preferences.md"
[[ -f "$CATALOG_PATH" ]] || die 2 "Catalog not found: $CATALOG_PATH"
[[ -f "$PREFS_PATH" ]]   || die 2 "Preferences not found: $PREFS_PATH"

CATALOG_REVISION="$(git -C "$CLONE" log -1 --format=%H -- '.github/pr-quality-gate/pattern-catalog.md' 2>/dev/null || true)"
PREFS_REVISION="$(git -C "$CLONE" log -1 --format=%H -- '.github/pr-quality-gate/coding-preferences.md' 2>/dev/null || true)"
[[ -z "$CATALOG_REVISION" ]] && die 2 'Cannot resolve catalog revision.'
[[ -z "$PREFS_REVISION" ]]   && die 2 'Cannot resolve preferences revision.'

# ===== Catalog parsing =====
PATTERNS_RUN=0
declare -a SLUGS=()
declare -A SLUG_SEEN=()
declare -a SCOPE_MODES=()
declare -a PARAMS_JSON=()
declare -a REVIEW_PROMPTS=()
declare -a TIERS=()

LINE_NUM=0
while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM+1))
    [[ "$line" =~ ^[[:space:]]*\<!-- ]] && continue
    [[ "$line" =~ ^\| ]] || continue
    [[ "$line" =~ ^\|[[:space:]]*slug[[:space:]]*\| ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*-+ ]] && continue

    # Parse cells, splitting on un-escaped pipe; reverse \| → |. Trim each cell but DO NOT filter empty trailing cells (review_pass_only_prompt and fp_slug are commonly empty).
    inner="${line:1}"; inner="${inner%|}"
    inner_escaped="$(echo "$inner" | sed 's/\\|/__PIPE__/g')"
    IFS='|' read -ra raw_cells <<< "$inner_escaped"
    cells=()
    for c in "${raw_cells[@]}"; do
        trimmed="$(echo "$c" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/__PIPE__/|/g')"
        cells+=("$trimmed")
    done

    [[ ${#cells[@]} -lt 5 ]] && die 2 "Malformed catalog row at line $LINE_NUM: expected at least 5 cells, got ${#cells[@]}: $line"
    slug="${cells[0]}"
    scope="${cells[1]}"
    params="${cells[2]}"
    review_prompt="${cells[3]}"
    fp_slug="${cells[4]:-}"
    if [[ ${#cells[@]} -ge 6 && -n "${cells[5]}" ]]; then
        tier="${cells[5]}"
        case "$tier" in HIGH|MEDIUM|LOW) ;; *) die 2 "Invalid tier '$tier' at line $LINE_NUM: expected HIGH | MEDIUM | LOW" ;; esac
    else
        echo "[gate-runner WARNING] Catalog row '$slug' at line $LINE_NUM uses legacy 5-cell schema (no tier column); defaulting to tier=MEDIUM. Add explicit tier in next catalog edit (sunset by next lightweight-gate-v5 catalog edit)." >&2
        tier='MEDIUM'
    fi

    [[ -n "${SLUG_SEEN[$slug]:-}" ]] && die 2 "Duplicate slug '$slug' at line $LINE_NUM"
    SLUG_SEEN[$slug]=1
    case "$scope" in diff-scoped|tree-scoped|hybrid|review-pass-only|checker-scoped) ;; *) die 2 "Invalid scope_mode '$scope' at line $LINE_NUM" ;; esac
    echo "$params" | jq empty 2>/dev/null || die 2 "Malformed JSON in params at line $LINE_NUM"

    case "$scope" in
        review-pass-only) [[ -z "$review_prompt" ]] && die 2 "scope_mode=review-pass-only requires non-empty review_pass_only_prompt at line $LINE_NUM" ;;
        checker-scoped)
            cid="$(echo "$params" | jq -r '.checker_id // ""')"
            [[ -z "$cid" ]] && die 2 "scope_mode=checker-scoped requires params.checker_id at line $LINE_NUM"
            [[ -n "$review_prompt" ]] && die 2 "scope_mode=checker-scoped MUST have empty review_pass_only_prompt at line $LINE_NUM"
            ;;
        diff-scoped)
            pat="$(echo "$params" | jq -r '.pattern // ""')"; gcount="$(echo "$params" | jq -r '.glob | length')"
            [[ -z "$pat" || "$gcount" -eq 0 ]] && die 2 "scope_mode=diff-scoped requires params.pattern and non-empty params.glob at line $LINE_NUM"
            [[ -n "$review_prompt" ]] && die 2 "scope_mode=diff-scoped MUST have empty review_pass_only_prompt at line $LINE_NUM"
            ;;
        tree-scoped)
            pat="$(echo "$params" | jq -r '.pattern // ""')"
            [[ -z "$pat" ]] && die 2 "scope_mode=tree-scoped requires params.pattern at line $LINE_NUM"
            [[ -n "$review_prompt" ]] && die 2 "scope_mode=tree-scoped MUST have empty review_pass_only_prompt at line $LINE_NUM"
            ;;
        hybrid)
            tpat="$(echo "$params" | jq -r '.tree.pattern // ""')"; dpat="$(echo "$params" | jq -r '.diff.pattern // ""')"; dgcount="$(echo "$params" | jq -r '.diff.glob | length')"
            [[ -z "$tpat" ]] && die 2 "scope_mode=hybrid requires params.tree.pattern at line $LINE_NUM"
            [[ -z "$dpat" || "$dgcount" -eq 0 ]] && die 2 "scope_mode=hybrid requires params.diff.pattern AND non-empty params.diff.glob at line $LINE_NUM"
            [[ -n "$review_prompt" ]] && die 2 "scope_mode=hybrid MUST have empty review_pass_only_prompt at line $LINE_NUM"
            ;;
    esac

    SLUGS+=("$slug"); SCOPE_MODES+=("$scope"); PARAMS_JSON+=("$params"); REVIEW_PROMPTS+=("$review_prompt"); TIERS+=("$tier")
    PATTERNS_RUN=$((PATTERNS_RUN+1))
done < "$CATALOG_PATH"

# ===== Diff file list =====
DIFF_FILES="$(git -C "$PROJECT_ROOT" -c core.quotePath=false diff --name-only "$BASE_SHA..$HEAD_SHA" 2>/dev/null || true)"
FILE_COUNT="$(echo "$DIFF_FILES" | grep -c '^' || true)"

# ===== Pattern execution =====
# Run rg with stderr captured: exit 0 = matches (emit to stdout), exit 1 = no matches (normal), exit >1 = a real rg
# error -> die with the captured stderr (mirrors gate-runner.ps1 Get-RgHits -> Exit-Runner 4) instead of letting set -e
# abort with no diagnostic. Relies on `set -o pipefail` so the die propagates through the `run_rg | sort` callers.
_rg_capture() {  # args: pattern-for-diagnostic, then the full rg argv
    local pat="$1"; shift
    local errf out rc=0
    if ! errf="$(mktemp "${TMPDIR:-/tmp}/gate-runner-rg.XXXXXX")"; then
        die 4 "could not create a temp file for rg stderr capture (mktemp failed)"
    fi
    out="$(rg "$@" 2>"$errf")" || rc=$?
    if [[ $rc -gt 1 ]]; then
        local err; err="$(cat "$errf" 2>/dev/null || true)"; rm -f "$errf"
        die 4 "rg exited with code $rc for pattern '$pat': $err"
    fi
    rm -f "$errf"
    [[ $rc -eq 0 && -n "$out" ]] && printf '%s\n' "$out"
    return 0
}
run_rg() {  # args: pattern, globs-json-array, file-list-or-empty (newline-separated)
    local pat="$1" globs_json="$2" file_list="$3"
    local rg_args=(--line-number --no-heading --color never)
    if [[ -n "$file_list" ]]; then
        # Filter files by glob match AND by file-still-exists-at-HEAD (git diff lists deleted files).
        local globs; globs="$(echo "$globs_json" | jq -r '.[]')"
        local matched=()
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            [[ ! -e "$PROJECT_ROOT/$f" ]] && continue   # skip deleted files
            for g in $globs; do
                case "$f" in $g) matched+=("$PROJECT_ROOT/$f"); break ;; esac
                case "$f" in **/$g) matched+=("$PROJECT_ROOT/$f"); break ;; esac
            done
        done <<< "$file_list"
        [[ ${#matched[@]} -eq 0 ]] && return 0
        _rg_capture "$pat" "${rg_args[@]}" --regexp "$pat" -- "${matched[@]}"
    else
        while IFS= read -r g; do rg_args+=(--glob "$g"); done < <(echo "$globs_json" | jq -r '.[]')
        rg_args+=(--regexp "$pat" -- "$PROJECT_ROOT")
        _rg_capture "$pat" "${rg_args[@]}"
    fi
}

declare -a FINDING_SLUGS=()
declare -a FINDING_HITS=()
declare -a FINDING_SCOPES=()
declare -a FINDING_TIERS=()
declare -A FINDING_SITES=()
TOTAL_REAL_FINDINGS=0

for i in "${!SLUGS[@]}"; do
    slug="${SLUGS[$i]}"; scope="${SCOPE_MODES[$i]}"; params="${PARAMS_JSON[$i]}"; tier="${TIERS[$i]}"
    # Tier filter applies to ALL rule types: full runs everything; triage skips LOW; lint-only keeps HIGH only.
    case "$MODE" in
        lint-only) [[ "$tier" != 'HIGH' ]] && continue ;;
        triage)    [[ "$tier" == 'LOW' ]] && continue ;;
    esac
    hits=''
    case "$scope" in
        review-pass-only) hits='review-required'; sites='' ;;
        checker-scoped) hits='checker-mechanized'; sites='' ;;
        diff-scoped)
            pat="$(echo "$params" | jq -r '.pattern')"; gj="$(echo "$params" | jq -c '.glob')"
            sites="$(run_rg "$pat" "$gj" "$DIFF_FILES" | LC_ALL=C sort -u)" ;;
        tree-scoped)
            pat="$(echo "$params" | jq -r '.pattern')"; gj="$(echo "$params" | jq -c '.glob')"
            sites="$(run_rg "$pat" "$gj" '' | LC_ALL=C sort -u)" ;;
        hybrid)
            tpat="$(echo "$params" | jq -r '.tree.pattern')"; tgj="$(echo "$params" | jq -c '.tree.glob')"
            dpat="$(echo "$params" | jq -r '.diff.pattern')"; dgj="$(echo "$params" | jq -c '.diff.glob')"
            tsites="$(run_rg "$tpat" "$tgj" '' )"
            dsites="$(run_rg "$dpat" "$dgj" "$DIFF_FILES" )"
            sites="$(printf '%s\n%s\n' "$tsites" "$dsites" | grep -v '^$' | LC_ALL=C sort -u || true)" ;;
    esac
    [[ -z "${hits:-}" ]] && hits="$(echo "$sites" | grep -c '^' 2>/dev/null || echo 0)"
    [[ -z "$sites" ]] && hits=0
    FINDING_SLUGS+=("$slug"); FINDING_HITS+=("$hits"); FINDING_SCOPES+=("$scope"); FINDING_TIERS+=("$tier"); FINDING_SITES[$slug]="$sites"
    [[ "$hits" != 'review-required' && "$hits" -gt 0 ]] && TOTAL_REAL_FINDINGS=$((TOTAL_REAL_FINDINGS + hits))
done

# ===== File locking + CSV append =====
acquire_lock() {
    local lock="$1" deadline=$(( $(date +%s) + LOCK_TIMEOUT_SECONDS )) jitter=100
    while [[ $(date +%s) -lt $deadline ]]; do
        if (set -C; printf '{"pid":%d,"host":"%s","session_id":"%s","acquired_at":"%s"}\n' \
                "$$" "$(hostname)" "${SESSION_ID:-$(uuidgen 2>/dev/null || echo "session-$$-$(date +%s)")}" \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$lock") 2>/dev/null; then
            return 0
        fi
        if [[ -f "$lock" ]]; then
            age=$(( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null) ))
            if [[ $age -gt 300 ]]; then
                meta_pid=$(jq -r '.pid' < "$lock" 2>/dev/null || echo 0)
                meta_host=$(jq -r '.host' < "$lock" 2>/dev/null || echo '')
                if [[ "$meta_host" == "$(hostname)" ]] && ! kill -0 "$meta_pid" 2>/dev/null; then
                    diag "Stale lock from pid $meta_pid; breaking"
                    rm -f "$lock"
                    continue
                fi
            fi
        fi
        sleep "0.$(printf '%03d' $jitter)" 2>/dev/null || sleep 1
        jitter=$(( jitter * 2 )); [[ $jitter -gt 5000 ]] && jitter=5000
    done
    return 1
}

DATA_DIR="$CLONE/.github/pr-quality-gate/data"
CSV="$DATA_DIR/findings.csv"
LOCK="$CSV.lock"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ $VERIFY -eq 0 && $TOTAL_REAL_FINDINGS -gt 0 ]]; then
    mkdir -p "$DATA_DIR"
    acquire_lock "$LOCK" || die 4 "Could not acquire findings.csv lock within ${LOCK_TIMEOUT_SECONDS}s"
    trap 'rm -f "$LOCK"' EXIT
    [[ ! -f "$CSV" ]] && printf 'timestamp,revision,pattern_slug,classification,finding_brief,slate_mode,finding_type\n' > "$CSV"
    for i in "${!FINDING_SLUGS[@]}"; do
        slug="${FINDING_SLUGS[$i]}"; hits="${FINDING_HITS[$i]}"
        [[ "$hits" == 'review-required' || "$hits" -eq 0 ]] && continue
        sites="${FINDING_SITES[$slug]}"
        while IFS= read -r s; do
            [[ -z "$s" ]] && continue
            printf '%s,%s,%s,pending,"%s",%s,pattern\n' "$TS" "$CATALOG_REVISION" "$slug" "${slug} hit" "$MODE" >> "$CSV"
        done <<< "$sites"
    done
    rm -f "$LOCK"; trap - EXIT
fi

# ===== Emit QUALITY GATE block =====
GATE_STATUS='READY'
[[ $TOTAL_REAL_FINDINGS -gt 0 ]] && GATE_STATUS='BLOCKED - findings present'

cat <<EOF
QUALITY GATE
  catalog_revision: $CATALOG_REVISION
  prefs_revision: $PREFS_REVISION
  runner_version: $RUNNER_VERSION
  panel_mode: $MODE
  base_sha: $BASE_SHA
  head_sha: $HEAD_SHA
  diff_scope: $BASE_SHA..$HEAD_SHA ($FILE_COUNT files)
  patterns_run: $PATTERNS_RUN
  pr_ref: $(yaml_sq "$PR_REF")
EOF

# Build required_rule_ack list (review-pass-only HIGH-tier slugs filtered by mode)
case "$MODE" in
    full)      ALLOWED_TIERS='HIGH MEDIUM LOW' ;;
    triage)    ALLOWED_TIERS='HIGH MEDIUM' ;;
    lint-only) ALLOWED_TIERS='HIGH' ;;
esac
REQ_ACK=()
for i in "${!SLUGS[@]}"; do
    [[ "${SCOPE_MODES[$i]}" != 'review-pass-only' ]] && continue
    case " $ALLOWED_TIERS " in *" ${TIERS[$i]} "*) REQ_ACK+=("${SLUGS[$i]}") ;; esac
done
IFS=','; echo "  required_rule_ack: [$(echo "${REQ_ACK[*]}" | sed 's/,/, /g')]"; IFS=$' \t\n'

# Anti-recidivism preamble (when PR_REF supplied)
if [[ -n "$PR_REF" ]]; then
    PANEL_MISSES_CSV="$CLONE/.github/pr-quality-gate/data/panel-misses.csv"
    if [[ -f "$PANEL_MISSES_CSV" ]]; then
        PRIOR_SLUGS="$(python3 -c '
import csv, sys
seen=set()
with open(sys.argv[1], newline="", encoding="utf-8") as f:
    r = csv.DictReader(f)
    for row in r:
        if row.get("pr_ref","") == sys.argv[2]:
            slug = row.get("proposed_catalog_slug","").strip()
            if slug: seen.add(slug)
print("\n".join(sorted(seen)))
' "$PANEL_MISSES_CSV" "$PR_REF" 2>/dev/null || true)"
        if [[ -n "$PRIOR_SLUGS" ]]; then
            echo "  anti_recidivism_preamble:"
            echo "    pr_ref: $(yaml_sq "$PR_REF")"
            echo "    prior_slugs:"
            while IFS= read -r s; do [[ -n "$s" ]] && echo "      - $(yaml_sq "$s")"; done <<< "$PRIOR_SLUGS"
            echo "    reviewer_action_required: 'For each prior_slug, emit verified-no-recurrence: <slug> with fix_evidence (commit_sha or diff_hunk).'"
        fi
    fi
fi

# rg_flagged_sites: per-slug sites for reviewers' cross-reference
RG_SITES_HEADER_EMITTED=0
for i in "${!FINDING_SLUGS[@]}"; do
    slug="${FINDING_SLUGS[$i]}"; hits="${FINDING_HITS[$i]}"; scope="${FINDING_SCOPES[$i]}"
    [[ "$scope" == 'review-pass-only' ]] && continue
    [[ "$hits" == '0' || -z "${FINDING_SITES[$slug]:-}" ]] && continue
    if [[ $RG_SITES_HEADER_EMITTED -eq 0 ]]; then
        echo "  rg_flagged_sites:"
        RG_SITES_HEADER_EMITTED=1
    fi
    echo "    ${slug}:"
    while IFS= read -r s; do [[ -n "$s" ]] && echo "      - $s"; done <<< "${FINDING_SITES[$slug]}"
done

echo "  findings:"

for i in "${!FINDING_SLUGS[@]}"; do
    slug="${FINDING_SLUGS[$i]}"; hits="${FINDING_HITS[$i]}"; scope="${FINDING_SCOPES[$i]}"; tier="${FINDING_TIERS[$i]:-MEDIUM}"
    [[ "$scope" == 'review-pass-only' ]] && hits='review-required'
    [[ "$scope" == 'checker-scoped' ]] && hits='checker-mechanized'
    cat <<EOF
    - pattern: $slug
      scope_mode: $scope
      tier: $tier
      hits: $hits
EOF
    sites="${FINDING_SITES[$slug]:-}"
    if [[ -n "$sites" && "$hits" != 'review-required' && "$hits" != '0' ]]; then
        echo "      sites:"
        while IFS= read -r s; do [[ -n "$s" ]] && echo "        - $s"; done <<< "$sites"
    fi
done

cat <<EOF
  same_state_recheck: not-yet-rechecked
  gate_status: $GATE_STATUS
EOF

[[ "$GATE_STATUS" == 'READY' ]] && exit 0 || exit 1
