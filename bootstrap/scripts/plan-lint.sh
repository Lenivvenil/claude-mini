#!/usr/bin/env bash
# plan-lint.sh — verify plan.md ADR-discipline (Session Continuity BC, ADR-0024)
#
# Checks that:
#   1. §3 (Considered approaches) exists.
#   2. §4 (Chosen approach) exists and is non-empty.
#   3. Every line in §3 and §4 that asserts a design decision carries either:
#      - an ADR-ref: docs/decisions/NNNN-*.md  or  ADR-NNNN  or  sub-decision N
#        ("sub-decision N" is accepted because sub-decisions are ADR-internal; they are
#        only meaningful within an ADR context, so citing one implies an ADR exists.)
#      - an explicit exemption: "no ADR" / "no ADR — justification:"
#
# Design assertion keywords (case-insensitive):
#   ADR-ref, Chosen, Approach [A-Z], выбран, отклонён, выбранный,
#   Hotspot.*закрыт, sub-decision, ADR-0, docs/decisions/
#
# Scope: active working tree plan.md only (not git history).
#
# Exit codes:
#   0  — all checks pass (or no plan.md present; not an error)
#   1  — one or more checks fail
#
# Usage:
#   bash bootstrap/scripts/plan-lint.sh [path/to/plan.md]

set -uo pipefail

PLAN="${1:-plan.md}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'

if [ ! -f "$PLAN" ]; then
    printf "${YELLOW}SKIP${NC} plan-lint: %s not found (no active plan)\n" "$PLAN"
    exit 0
fi

FAILURES=0

# Extract §3 and §4 combined content (lines between their headings and the next ## heading)
section_content=""
in_section=0

while IFS= read -r line; do
    if echo "$line" | grep -qiE '^## [34]\.?[[:space:]]'; then
        in_section=1
        continue
    fi
    if echo "$line" | grep -qE '^## [^34]'; then
        in_section=0
    fi
    if [ "$in_section" -eq 1 ]; then
        section_content="${section_content}
${line}"
    fi
done < "$PLAN"

# --- Check 1: §3 exists ---
if ! grep -qiE '^## [3]\.?[[:space:]]' "$PLAN" && ! grep -qiE '^## Considered' "$PLAN"; then
    printf "${RED}FAIL${NC} plan-lint: §3 (Considered approaches) missing in %s\n" "$PLAN"
    printf "     Every plan.md must have §3 with ≥2 options.\n"
    FAILURES=$((FAILURES+1))
fi

# --- Check 2: §4 exists ---
if ! grep -qiE '^## [4]\.?[[:space:]]' "$PLAN" && ! grep -qiE '^## Chosen' "$PLAN"; then
    printf "${RED}FAIL${NC} plan-lint: §4 (Chosen approach) missing in %s\n" "$PLAN"
    printf "     Every plan.md must have §4 (Chosen approach).\n"
    FAILURES=$((FAILURES+1))
fi

if [ -z "$section_content" ]; then
    printf "${RED}FAIL${NC} plan-lint: §3 or §4 content is empty in %s\n" "$PLAN"
    FAILURES=$((FAILURES+1))
    printf "${RED}FAIL${NC} plan-lint: %d issue(s)\n" "$FAILURES"
    exit 1
fi

# --- Check 3: per-line design assertion discipline ---
# A line is a "design assertion" if it matches ASSERTION_RE.
# It passes if it also matches ADRREF_RE (has an ADR-ref or sub-decision cite)
# or EXEMPTION_RE (explicit "no ADR" exemption).
ASSERTION_RE='(ADR-ref|Chosen|Approach [A-Z]|выбран|отклонён|выбранный|Hotspot.*закрыт|sub-decision|ADR-0|docs/decisions/)'
# sub-decision N: accepted as valid ADR-ref because sub-decisions exist only within ADRs.
ADRREF_RE='(docs/decisions/[0-9]{4}-[^[:space:]]+|ADR-[0-9]{4}|adr-[0-9]{4}|sub-decision[[:space:]]*[0-9]+)'
EXEMPTION_RE='(no ADR|no adr|without ADR|без ADR|[Оо]тклон|[Rr]eject)'

while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Skip headings, separators, and blank-equivalent lines
    echo "$line" | grep -qE '^(#{1,4}[[:space:]]|---|[[:space:]]*$)' && continue

    if echo "$line" | grep -qiE "$ASSERTION_RE"; then
        if echo "$line" | grep -qiE "$ADRREF_RE"; then
            : # has ADR-ref — OK
        elif echo "$line" | grep -qiE "$EXEMPTION_RE"; then
            : # explicit exemption — OK
        else
            printf "${RED}FAIL${NC} plan-lint: design assertion without ADR-ref or exemption:\n"
            printf "     %s\n" "$line"
            FAILURES=$((FAILURES+1))
        fi
    fi
done <<< "$section_content"

# Summary
if [ "$FAILURES" -eq 0 ]; then
    printf "${GREEN}PASS${NC} plan-lint: %s — §3 and §4 present; all assertions have ADR-refs or exemptions\n" "$PLAN"
    exit 0
else
    printf "${RED}FAIL${NC} plan-lint: %d issue(s) in %s\n" "$FAILURES" "$PLAN"
    printf "     Add ADR-ref (docs/decisions/NNNN-*.md or sub-decision N), or exemption (\"no ADR — justification: ...\").\n"
    exit 1
fi
