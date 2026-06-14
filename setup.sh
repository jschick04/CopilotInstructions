#!/usr/bin/env bash
# One-time setup for Copilot CLI custom instructions hosted in this repo (Unix).
#
# Configures the COPILOT_CUSTOM_INSTRUCTIONS_DIRS environment variable (shell-profile
# append) AND sets `git config --local core.hooksPath .githooks` so the catalog-sync
# drift safeguard runs on every commit.
#
# Windows users: use setup.ps1 instead.

set -eu

PROFILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --profile=*) PROFILE="${1#*=}" ;;
        --profile) if [ $# -ge 2 ]; then PROFILE="$2"; shift; fi ;;
        *) echo "ERROR: unknown argument '$1'. Usage: ./setup.sh --profile <full|lite>" >&2; exit 2 ;;
    esac
    shift
done
if [ "$PROFILE" != "full" ] && [ "$PROFILE" != "lite" ]; then
    echo "ERROR: required argument --profile <full|lite> was not supplied (got '$PROFILE'). Re-run, e.g.: ./setup.sh --profile full" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_VAR_NAME="COPILOT_CUSTOM_INSTRUCTIONS_DIRS"

echo "=== Copilot CLI custom instructions setup (Unix) ==="
echo "Repo root: $REPO_ROOT"
echo ""

# --- Validate repo layout --------------------------------------------------
if [ ! -f "$REPO_ROOT/AGENTS.md" ]; then
    echo "ERROR: AGENTS.md not found at $REPO_ROOT/AGENTS.md. Run setup.sh from the repo root." >&2
    exit 1
fi
if [ ! -d "$REPO_ROOT/.github/instructions" ]; then
    echo "ERROR: .github/instructions/ directory not found. Repo layout looks wrong." >&2
    exit 1
fi

TOPIC_COUNT="$(find "$REPO_ROOT/.github/instructions" -name '*.instructions.md' -type f | wc -l | tr -d ' ')"
echo "Found AGENTS.md and $TOPIC_COUNT topic file(s) in .github/instructions/"
echo ""

# --- Configure env var -----------------------------------------------------
echo "=== Configuring $ENV_VAR_NAME ==="

PROFILE_FILE=""
SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
case "$SHELL_NAME" in
    bash) PROFILE_FILE="$HOME/.bashrc" ;;
    zsh)  PROFILE_FILE="$HOME/.zshrc" ;;
    *)
        echo "WARNING: shell '$SHELL_NAME' not recognized. You will need to manually set $ENV_VAR_NAME=$REPO_ROOT in your shell profile."
        PROFILE_FILE=""
        ;;
esac

if [ -n "$PROFILE_FILE" ]; then
    EXPORT_LINE="export $ENV_VAR_NAME=\"$REPO_ROOT\""
    if [ -f "$PROFILE_FILE" ] && grep -q "$ENV_VAR_NAME" "$PROFILE_FILE"; then
        echo "$ENV_VAR_NAME already referenced in $PROFILE_FILE. Skipping append (review manually if needed)."
    else
        echo "" >> "$PROFILE_FILE"
        echo "# Copilot CLI custom instructions (added by setup.sh)" >> "$PROFILE_FILE"
        echo "$EXPORT_LINE" >> "$PROFILE_FILE"
        echo "Appended to $PROFILE_FILE:"
        echo "  $EXPORT_LINE"
        echo ""
        echo "Source the profile or open a new shell to pick up the change."
    fi
fi
echo ""

# --- Configure active profile (full | lite) --------------------------------
echo "=== Configuring active profile: $PROFILE ==="

PROFILE_TEMPLATE="$REPO_ROOT/profiles/$PROFILE/profile.instructions.md"
ACTIVE_PROFILE_FILE="$REPO_ROOT/.github/instructions/active-profile.instructions.md"

if [ ! -f "$PROFILE_TEMPLATE" ]; then
    echo "ERROR: profile template not found: $PROFILE_TEMPLATE" >&2
    exit 1
fi

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

if [ -f "$ACTIVE_PROFILE_FILE" ] && [ "$(sha256 "$ACTIVE_PROFILE_FILE")" = "$(sha256 "$PROFILE_TEMPLATE")" ]; then
    echo "Active profile already '$PROFILE' and current. No change."
else
    cp "$PROFILE_TEMPLATE" "$ACTIVE_PROFILE_FILE"
    echo "Active profile set to '$PROFILE'."
fi
echo "  Wrote $ACTIVE_PROFILE_FILE (gitignored; per-machine; never committed)."
echo "  After 'git pull', re-run this script to refresh the active file if the template changed."
echo "  To revert to full-default, delete it: rm '$ACTIVE_PROFILE_FILE'"
echo ""

# --- Configure git hooks path (catalog-sync drift safeguard) ---------------
echo "=== Configuring git hooks path ==="

if [ ! -d "$REPO_ROOT/.git" ]; then
    echo "WARNING: .git directory not found at $REPO_ROOT/.git. Skipping hooks config - not running inside a git clone."
elif [ ! -d "$REPO_ROOT/.githooks" ]; then
    echo "WARNING: .githooks/ directory not found. Skipping hooks config - the committed hook directory is missing."
else
    # `git config --get core.hooksPath` walks system → global → local → worktree,
    # so it returns whatever scope wins. Using --local-only would miss global / system shadowing.
    CURRENT_HOOKS_PATH="$(git -C "$REPO_ROOT" config --get core.hooksPath 2>/dev/null || echo "")"
    HOOKS_SCOPE=""
    if [ -n "$CURRENT_HOOKS_PATH" ]; then
        HOOKS_SCOPE="$(git -C "$REPO_ROOT" config --show-scope --get core.hooksPath 2>/dev/null | awk '{print $1}' || echo "")"
    fi
    if [ -n "$CURRENT_HOOKS_PATH" ] && [ "$CURRENT_HOOKS_PATH" != ".githooks" ]; then
        echo "WARNING: core.hooksPath is already set:"
        echo "  Current value: $CURRENT_HOOKS_PATH"
        [ -n "$HOOKS_SCOPE" ] && echo "  Set at scope:  $HOOKS_SCOPE"
        echo "  Repo expects:  .githooks"
        echo ""
        printf "Overwrite via --local (other scopes preserved but shadowed for this repo)? [y/N] "
        read -r REPLY
        case "$REPLY" in
            [Yy]*)
                git -C "$REPO_ROOT" config --local core.hooksPath .githooks
                echo "Set core.hooksPath = .githooks (local scope)."
                ;;
            *)
                echo "Skipped. CI workflow catalog-sync-check.yml will still verify on PR."
                ;;
        esac
    else
        git -C "$REPO_ROOT" config --local core.hooksPath .githooks
        echo "Set core.hooksPath = .githooks (local scope)."
        echo "  Pre-commit hook will verify HIGH-TIER-SLUGS.md stays in sync with pattern-catalog.md."
    fi
    # Defensive: ensure every hook is executable. On Unix, Git skips non-executable hooks
    # silently - without this chmod the safeguard appears configured but never fires.
    for HOOK_FILE in "$REPO_ROOT/.githooks"/*; do
        if [ -f "$HOOK_FILE" ] && [ ! -x "$HOOK_FILE" ]; then
            chmod +x "$HOOK_FILE"
            echo "  Set executable bit on $HOOK_FILE."
        fi
    done
fi

echo ""
echo "=== Done ==="
