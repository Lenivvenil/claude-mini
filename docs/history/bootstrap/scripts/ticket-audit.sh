#!/usr/bin/env bash
# ticket-audit.sh — structural quality check for human-authored GitHub issues
#
# Part of the /audit-pass skill (issue #129). Layer-1 deterministic gate for the
# Principle-9 supervisory re-pass workflow. ADR-0023 two-layer pattern: this script
# is Layer 1; the SKILL.md LLM generates diff suggestions in Layer 2.
#
# Usage:
#   bash bootstrap/scripts/ticket-audit.sh <issue-number>    # fetch via gh
#   bash bootstrap/scripts/ticket-audit.sh <path/to/file.md> # local markdown
#
# Output: per-field PASS/FAIL/SKIP table to stdout
#
# Exit-code convention: standard 0/1 (NOT the always-exit-0 of verify.sh).
# This script is called via Claude's Bash tool, not via !-interpolation, so
# conventional exit codes are safe. See plan-lint.sh for the established precedent.
#   0 — all checked fields pass
#   1 — one or more checked fields fail
#
# Requires: bash
# Additional (issue-number mode only): jq, gh CLI

set -uo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'

FAILURES=0

pass() { printf '%sPASS%s %-22s %s\n' "$GREEN" "$NC" "$1" "$2"; }
fail() { printf '%sFAIL%s %-22s %s\n' "$RED" "$NC" "$1" "$2"; FAILURES=$((FAILURES+1)); }
skip() { printf '%sSKIP%s %-22s %s\n' "$YELLOW" "$NC" "$1" "$2"; }

if [ $# -ne 1 ]; then
    printf "Usage: %s <issue-number|file.md>\n" "$0" >&2
    exit 1
fi

ARG="$1"
TITLE=""
BODY=""
FILE_MODE=0
LABEL_COUNT=0

if [[ "$ARG" =~ ^[0-9]+$ ]]; then
    # Issue-number mode: fetch title, body, labels via gh
    if ! command -v jq >/dev/null 2>&1; then
        printf "ERROR: jq not found\n" >&2; exit 1
    fi
    if ! command -v gh >/dev/null 2>&1; then
        printf "ERROR: gh CLI not found\n" >&2; exit 1
    fi
    gh_err=$(mktemp)
    if ! gh_json=$(gh issue view "$ARG" --json title,body,labels 2>"$gh_err"); then
        printf "ERROR: gh issue view %s failed:\n%s\n" "$ARG" "$(cat "$gh_err")" >&2
        rm -f "$gh_err"; exit 1
    fi
    rm -f "$gh_err"
    TITLE=$(printf '%s' "$gh_json" | jq -r '.title // ""')
    BODY=$(printf '%s' "$gh_json" | jq -r '.body // ""')
    LABEL_COUNT=$(printf '%s' "$gh_json" | jq '.labels | length // 0')
else
    # File mode: extract title from first # heading; labels are unavailable
    FILE_MODE=1
    if [ ! -f "$ARG" ]; then
        printf "ERROR: file not found: %s\n" "$ARG" >&2; exit 1
    fi
    TITLE=$(grep -m1 -- '^# ' "$ARG" 2>/dev/null | sed 's/^# //' || true)
    BODY=$(cat -- "$ARG")
fi

# Strip markdown bold markers so "**Priority:** P1" reads as "Priority: P1"
PLAIN_BODY=$(printf '%s\n' "$BODY" | sed 's/\*\*//g')

printf "ticket-audit: %s\n\n" "$ARG"

# --- Check 1: Title — Conventional Commits prefix ---
CC_RE='^(feat|fix|docs|chore|refactor|test|perf|ci|build|revert)(\([^)]+\))?: .+'
if [ -z "$TITLE" ]; then
    fail "title" "empty or not found"
elif printf '%s' "$TITLE" | grep -qE "$CC_RE"; then
    pass "title" "$TITLE"
else
    fail "title" "not CC-compatible: '$TITLE'"
fi

# --- Check 2: Priority — P0/P1/P2/P3 present in body ---
if printf '%s\n' "$PLAIN_BODY" | grep -qE '\bP[0-3]\b'; then
    pass "priority" "found"
else
    fail "priority" "P0/P1/P2/P3 not found in body"
fi

# --- Check 3: Labels — issue mode only; skip in file mode ---
if [ "$FILE_MODE" -eq 1 ]; then
    skip "labels" "file mode — label check unavailable"
elif [ "$LABEL_COUNT" -gt 0 ]; then
    pass "labels" "$LABEL_COUNT label(s)"
else
    fail "labels" "no labels assigned"
fi

# Helper: check if a ## section header exists (case-insensitive)
section_exists() {
    printf '%s\n' "$BODY" | grep -qiE "^## $1"
}

# Helper: extract lines between a ## header and the next ## header
section_content() {
    local hdr_lower
    hdr_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    printf '%s\n' "$BODY" | awk -v hdr="$hdr_lower" '
        BEGIN { in_section=0 }
        /^## / {
            if (tolower($0) ~ ("^## " hdr)) { in_section=1; next }
            else if (in_section) { exit }
        }
        in_section { print }
    '
}

# --- Check 4: Problem statement — section with ≥1 non-empty line ---
if ! section_exists "Problem statement"; then
    fail "problem-statement" "## Problem statement section missing"
else
    ps_content=$(section_content "Problem statement")
    ps_nonempty=$(printf '%s\n' "$ps_content" | grep -cv '^[[:space:]]*$' || true)
    if [ "${ps_nonempty:-0}" -ge 1 ]; then
        pass "problem-statement" "present"
    else
        fail "problem-statement" "section exists but has no content"
    fi
fi

# --- Check 5: Acceptance criteria — section with ≥3 "- [ ]" items ---
if ! section_exists "Acceptance criteria"; then
    fail "acceptance-criteria" "## Acceptance criteria section missing"
else
    ac_content=$(section_content "Acceptance criteria")
    ac_count=$(printf '%s\n' "$ac_content" | grep -cE '^[[:space:]]*- \[ \]' || true)
    if [ "${ac_count:-0}" -ge 3 ]; then
        pass "acceptance-criteria" "$ac_count item(s)"
    else
        fail "acceptance-criteria" "found ${ac_count:-0} '- [ ]' item(s); need ≥3"
    fi
fi

# --- Check 6: Non-goals — section present ---
if section_exists "Non-goals"; then
    pass "non-goals" "present"
else
    fail "non-goals" "## Non-goals section missing"
fi

# --- Check 7: References — section with ≥1 "Принцип N" line ---
if ! section_exists "References"; then
    fail "references" "## References section missing"
else
    ref_content=$(section_content "References")
    if printf '%s\n' "$ref_content" | grep -qE 'Принцип[[:space:]]+[0-9]'; then
        pass "references" "principle ref found"
    else
        fail "references" "section present but no 'Принцип N' line found"
    fi
fi

# --- Check 8: Estimate — S, M, or L after "Estimate:" ---
# Handles both "Estimate: S" and "**Estimate:** S" (bold format)
if printf '%s\n' "$PLAIN_BODY" | grep -qiE 'Estimate[^:]*:[[:space:]]*\b[SML]\b'; then
    pass "estimate" "found"
else
    fail "estimate" "Estimate: S/M/L not found (expected 'Estimate: S', 'M', or 'L')"
fi

# --- Summary ---
printf "\n"
if [ "$FAILURES" -eq 0 ]; then
    printf '%sPASS%s ticket-audit: all checks pass\n' "$GREEN" "$NC"
    exit 0
else
    printf '%sFAIL%s ticket-audit: %d field(s) failed\n' "$RED" "$NC" "$FAILURES"
    exit 1
fi
