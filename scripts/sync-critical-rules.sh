#!/usr/bin/env bash
# Bash twin of scripts/sync-critical-rules.ps1.
#
# REQUIRES bash, not sh - uses bash arrays. Invoke as `bash scripts/sync-critical-rules.sh`,
# NEVER `sh scripts/sync-critical-rules.sh` (some systems have /bin/sh = dash).
#
# Must produce BYTE-IDENTICAL output to the PowerShell version. CI parity job
# (.github/workflows/catalog-sync-check.yml) runs both and asserts equality.
# Cross-platform invariants:
#   - Content hash via `git hash-object` (canonical normalized blob SHA-1).
#   - All emitted lines LF-only (printf with explicit \n; no echo -e).
#   - utf8 output, no BOM, no trailing newline.
#
# Modes:
#   default:     regenerate HIGH-TIER-SLUGS.md
#   -Verify:     compare in-memory generation to on-disk; exit non-zero if drift
#   -StagedMode: read both files via `git show :<path>` instead of working tree

set -eu

# ---- args -----------------------------------------------------------------
CATALOG_PATH=""
OUTPUT_PATH=""
VERIFY=0
STAGED_MODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        -CatalogPath) CATALOG_PATH="$2"; shift 2 ;;
        -OutputPath) OUTPUT_PATH="$2"; shift 2 ;;
        -Verify) VERIFY=1; shift ;;
        -StagedMode) STAGED_MODE=1; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ---- repo paths -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
    echo "ERROR: not in a git repo (cannot resolve repo root from $SCRIPT_DIR)" >&2
    exit 1
fi

if [ -z "$CATALOG_PATH" ]; then
    CATALOG_PATH="$REPO_ROOT/.github/pr-quality-gate/pattern-catalog.md"
fi
if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="$REPO_ROOT/.github/pr-quality-gate/HIGH-TIER-SLUGS.md"
fi

CATALOG_REL=".github/pr-quality-gate/pattern-catalog.md"
OUTPUT_REL=".github/pr-quality-gate/HIGH-TIER-SLUGS.md"

# ---- read catalog content + compute hash ----------------------------------
if [ "$STAGED_MODE" = "1" ]; then
    CATALOG_CONTENT="$(git -C "$REPO_ROOT" show ":$CATALOG_REL" 2>/dev/null)" || {
        echo "ERROR: cannot read staged content of $CATALOG_REL. Is it staged?" >&2
        exit 1
    }
    CATALOG_HASH="$(git -C "$REPO_ROOT" rev-parse ":$CATALOG_REL" 2>/dev/null)"
else
    if [ ! -f "$CATALOG_PATH" ]; then
        echo "ERROR: Catalog not found: $CATALOG_PATH" >&2
        exit 1
    fi
    CATALOG_CONTENT="$(cat "$CATALOG_PATH")"
    CATALOG_HASH="$(git -C "$REPO_ROOT" hash-object "$CATALOG_REL" 2>/dev/null)"
fi
if [ -z "$CATALOG_HASH" ]; then
    CATALOG_HASH="unknown"
fi

# ---- extract HIGH-tier review-pass-only slugs ----------------------------
# Logic mirrors PowerShell version: parse table rows where cell[5]=HIGH AND cell[1]=review-pass-only.
# Pipe inside JSON params is escaped as \| in the source - split on (?<!\\)\| in pwsh; in awk we'll
# use a placeholder-substitution trick.
parse_slugs() {
    printf '%s\n' "$CATALOG_CONTENT" | awk '
    BEGIN { FS = "|"; OFS = "|" }
    # Skip non-table lines
    /^[^|]/ { next }
    # Skip header and divider rows
    /^\|[[:space:]]*slug[[:space:]]*\|/ { next }
    /^\|[[:space:]]*-+[[:space:]]*\|/ { next }
    /^\|[[:space:]]*tier[[:space:]]*\|/ { next }
    {
        # Substitute escaped pipes \| with a placeholder so split-on-| works
        gsub(/\\\|/, "\001")
        n = split($0, cells, "|")
        # Drop leading + trailing empty cells from outer |
        if (n < 3) next
        # cells[1] is "" (leading), cells[n] is "" (trailing). Real cells are 2..n-1.
        # Trim each cell.
        for (i = 2; i <= n - 1; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[i])
        }
        ncells = n - 2
        if (ncells < 6) next
        slug = cells[2]
        scope = cells[3]
        prompt = cells[5]
        tier = cells[7]
        if (tier != "HIGH") next
        if (scope != "review-pass-only") next
        # Restore escaped pipes in prompt
        gsub(/\001/, "|", prompt)
        # Find the first REAL sentence break (a ". " that is not the trailing period of a known
        # abbreviation or a numeric list marker); kept byte-identical to the PowerShell twin.
        sentence_end = 0
        search_from = 1
        while (1) {
            rel = index(substr(prompt, search_from), ". ")
            if (rel == 0) break
            abs = search_from + rel - 1
            if (abs == 1) { search_from = abs + 2; continue }
            last = substr(prompt, abs - 1, 1)
            pre3 = substr(prompt, abs - 3, 3)
            pre2 = substr(prompt, abs - 2, 2)
            if (last ~ /[0-9]/ || pre3 == "e.g" || pre3 == "i.e" || pre3 == "etc" || pre2 == "vs" || pre2 == "cf") {
                search_from = abs + 2
                continue
            }
            sentence_end = abs
            break
        }
        if (sentence_end > 0) {
            trigger = substr(prompt, 1, sentence_end - 1)
        } else {
            trigger = prompt
        }
        if (length(trigger) > 200) {
            trigger = substr(trigger, 1, 197) "..."
        }
        print slug "\t" scope "\t" trigger
    }
    '
}

SLUGS_DATA="$(parse_slugs)"

# ---- generate output (LF-only via printf) --------------------------------
generate_output() {
    printf '# HIGH-TIER catalog slugs\n'
    printf '\n'
    printf 'GENERATED FILE - do not hand-edit. Regenerated by `scripts/sync-critical-rules.ps1` or its bash twin `scripts/sync-critical-rules.sh` from `pattern-catalog.md`.\n'
    printf '\n'
    printf 'Catalog content hash: `%s`\n' "$CATALOG_HASH"
    printf '\n'
    printf 'Every HIGH-tier `review-pass-only` slug below MUST appear in `core_rules_acknowledged` on every commit with per-site `file:line:disposition` citations (see `panel-policy.md` §Per-rule acknowledgement for full schema).\n'
    printf '\n'
    printf '## Slugs requiring acknowledgement\n'
    printf '\n'
    if [ -n "$SLUGS_DATA" ]; then
        printf '%s\n' "$SLUGS_DATA" | while IFS=$'\t' read -r slug scope trigger; do
            printf '### `%s`\n' "$slug"
            printf '\n'
            case "$trigger" in
                *.) printf '%s\n' "$trigger" ;;
                *)  printf '%s.\n' "$trigger" ;;
            esac
            printf '\n'
            printf 'Canonical rule definition: see `pattern-catalog.md` row `%s`.\n' "$slug"
            printf '\n'
        done
    fi
    printf '## Acknowledgement template (per-slug)\n'
    printf '\n'
    printf '```yaml\n'
    printf 'core_rules_acknowledged:\n'
    printf '  - slug: <slug>\n'
    printf '    status: <applied | not-applicable>\n'
    printf '    evidence:\n'
    printf '      per_site_citations:\n'
    printf '        - file: <path>\n'
    printf '          line: <int or range>\n'
    printf '          disposition: <rename | extract | remove | restore | keep-because>\n'
    printf '          keep_reason: <rationale; MUST add information beyond comment text>\n'
    printf '      diff_metric_check: <rg-violation count vs per_site_citations count>\n'
    printf '    rationale: <≤30 words; required for not-applicable>\n'
    printf '```'
}

GENERATED="$(generate_output)"

# ---- verify or write ------------------------------------------------------
if [ "$VERIFY" = "1" ]; then
    if [ "$STAGED_MODE" = "1" ]; then
        EXISTING="$(git -C "$REPO_ROOT" show ":$OUTPUT_REL" 2>/dev/null)" || {
            echo "ERROR: HIGH-TIER-SLUGS.md missing from staged index. Run scripts/sync-critical-rules.sh (no flags) and stage the result." >&2
            exit 1
        }
        MODE_DESC="staged index"
    else
        if [ ! -f "$OUTPUT_PATH" ]; then
            echo "ERROR: HIGH-TIER-SLUGS.md missing at $OUTPUT_PATH; run scripts/sync-critical-rules.sh (without -Verify) to generate." >&2
            exit 1
        fi
        EXISTING="$(cat "$OUTPUT_PATH")"
        MODE_DESC="working tree"
    fi
    # Normalize CRLF→LF on both sides for comparison.
    EXISTING_NORM="$(printf '%s' "$EXISTING" | tr -d '\r')"
    GENERATED_NORM="$(printf '%s' "$GENERATED" | tr -d '\r')"
    if [ "$EXISTING_NORM" != "$GENERATED_NORM" ]; then
        echo "ERROR: HIGH-TIER-SLUGS.md ($MODE_DESC) is OUT OF SYNC with pattern-catalog.md. Run scripts/sync-critical-rules.sh to regenerate, then stage the result." >&2
        exit 1
    fi
    echo "HIGH-TIER-SLUGS.md is in sync."
    exit 0
fi

# Atomic write: temp file then rename. utf8, no BOM, no trailing newline.
TEMP_PATH="${OUTPUT_PATH}.tmp"
printf '%s' "$GENERATED" > "$TEMP_PATH"
mv "$TEMP_PATH" "$OUTPUT_PATH"

SLUG_COUNT="$(printf '%s\n' "$SLUGS_DATA" | grep -c . || echo 0)"
echo "Generated $OUTPUT_PATH with $SLUG_COUNT HIGH-tier review-pass-only slugs (content hash: $CATALOG_HASH)."
