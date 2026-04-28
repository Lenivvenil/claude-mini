#!/usr/bin/env bash
# lint-prompts.sh — structural linter for bootstrap prompt artifacts
#
# Usage: ./scripts/lint-prompts.sh [file ...]
# Dispatch: rules applied based on file path, not content heuristics.
# Exit 0: all files clean (including zero-args). Exit 1: one or more findings.
#
# Artifact types and rules:
#   bootstrap/agents/*.md      — frontmatter, Protocol/Output/Hard rules sections,
#                                fenced output block if pure critic (NEVER writes files)
#   bootstrap/commands/*.md    — Your task + Hard rules sections
#   bootstrap/skills/*/SKILL.md — Output + Hard rules sections
#   anything else              — skipped silently
#
# NOTE: file arguments must be relative paths from the repo root
# (e.g. bootstrap/agents/foo.md). Absolute paths silently skip dispatch.

set -uo pipefail

ERRORS=0

# Banned term patterns (keep in sync with docs/runbooks/banned-terms.md)
BANNED_TERMS=("employer-owned repositories")

check_banned() {
    local file="$1"
    local ok=1
    for term in "${BANNED_TERMS[@]}"; do
        if grep -qi "$term" "$file"; then
            echo "$file: FAIL — contains banned term '$term'" >&2
            ok=0
        fi
    done
    return $((1 - ok))
}

lint_agent() {
    local file="$1"
    local ok=1

    # Frontmatter fields — must be present and non-empty
    for field in name description tools model; do
        if ! grep -qE "^${field}:[[:space:]]+[^[:space:]]" "$file"; then
            echo "$file: FAIL — missing or empty '${field}:' in frontmatter" >&2
            ok=0
        fi
    done

    # Tool/claim consistency: pure read-only critics claim "NEVER writes files"
    if grep -qi "NEVER writes files" "$file"; then
        if grep -qE "^tools:.*\bWrite\b" "$file" || grep -qE "^tools:.*\bEdit\b" "$file"; then
            echo "$file: FAIL — description says 'NEVER writes files' but tools includes Write or Edit" >&2
            ok=0
        fi
        # Pure critics must have a fenced output block (literal or escaped backticks) with a placeholder
        # shellcheck disable=SC2016
        if ! grep -qE '^```|^\\`\\`\\`' "$file"; then
            echo "$file: FAIL — pure critic requires a fenced output block (none found)" >&2
            ok=0
        elif ! grep -q '{' "$file"; then
            echo "$file: FAIL — pure critic output block must contain at least one {placeholder}" >&2
            ok=0
        fi
    fi

    # Required sections
    for section in "## Protocol" "## Hard rules"; do
        if ! grep -qF "$section" "$file"; then
            echo "$file: FAIL — missing '${section}' section" >&2
            ok=0
        fi
    done
    # Output section: accept both '## Output format' and '## Output'
    if ! grep -qE "^## Output" "$file"; then
        echo "$file: FAIL — missing '## Output' or '## Output format' section" >&2
        ok=0
    fi

    check_banned "$file" || ok=0
    return $((1 - ok))
}

lint_command() {
    local file="$1"
    local ok=1

    for section in "## Your task" "## Hard rules"; do
        if ! grep -qF "$section" "$file"; then
            echo "$file: FAIL — missing '${section}' section" >&2
            ok=0
        fi
    done

    check_banned "$file" || ok=0
    return $((1 - ok))
}

lint_skill() {
    local file="$1"
    local ok=1

    if ! grep -qF "## Hard rules" "$file"; then
        echo "$file: FAIL — missing '## Hard rules' section" >&2
        ok=0
    fi
    if ! grep -qE "^## Output" "$file"; then
        echo "$file: FAIL — missing '## Output' section" >&2
        ok=0
    fi

    check_banned "$file" || ok=0
    return $((1 - ok))
}

if [ $# -eq 0 ]; then
    exit 0
fi

for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "$file: SKIP — not a file" >&2
        continue
    fi

    case "$file" in
        bootstrap/agents/*.md)
            lint_agent "$file" || ERRORS=$((ERRORS + 1))
            ;;
        bootstrap/commands/*.md)
            lint_command "$file" || ERRORS=$((ERRORS + 1))
            ;;
        bootstrap/skills/*/SKILL.md)
            lint_skill "$file" || ERRORS=$((ERRORS + 1))
            ;;
        *)
            # Not a prompt artifact — skip gracefully
            ;;
    esac
done

if [ "$ERRORS" -gt 0 ]; then
    echo "" >&2
    echo "lint-prompts: ${ERRORS} file(s) failed" >&2
    exit 1
fi

exit 0
