#!/usr/bin/env bash
# test-mutation-summary.sh — unit tests for mutation-summary.sh
#
# Usage:
#   bash bootstrap/scripts/test-mutation-summary.sh
#
# Exit codes: 0 = all passed, 1 = one or more failures

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUMMARY="$REPO_ROOT/bootstrap/scripts/mutation-summary.sh"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
FAILURES=0

pass() { printf "  %s✓%s %s\n" "${GREEN}" "${NC}" "$1"; }
fail() { printf "  %s✗%s %s\n" "${RED}" "${NC}" "$1"; FAILURES=$((FAILURES + 1)); }

echo "=== mutation-summary.sh: status icons ==="

# T1: Python score 85% → 🟢 in output
body=$(bash "$SUMMARY" --week 2026-W01 --python-score 85 --python-killed 17 --python-survived 3 2>/dev/null)
if echo "$body" | grep -q "🟢"; then
    pass "T1: score 85% → 🟢"
else
    fail "T1: score 85% should produce 🟢"
fi

if echo "$body" | grep -q "85%"; then
    pass "T2: score 85% appears in output"
else
    fail "T2: score 85% not found in output"
fi

# T3: Python score 70% → 🟡
body=$(bash "$SUMMARY" --week 2026-W01 --python-score 70 --python-killed 14 --python-survived 6 2>/dev/null)
if echo "$body" | grep -q "🟡"; then
    pass "T3: score 70% → 🟡"
else
    fail "T3: score 70% should produce 🟡"
fi

if echo "$body" | grep -q "70%"; then
    pass "T4: score 70% appears in output"
else
    fail "T4: score 70% not found in output"
fi

# T5: Python score 45% → 🔴
body=$(bash "$SUMMARY" --week 2026-W01 --python-score 45 --python-killed 9 --python-survived 11 2>/dev/null)
if echo "$body" | grep -q "🔴"; then
    pass "T5: score 45% → 🔴"
else
    fail "T5: score 45% should produce 🔴"
fi

if echo "$body" | grep -q "45%"; then
    pass "T6: score 45% appears in output"
else
    fail "T6: score 45% not found in output"
fi

echo ""
echo "=== mutation-summary.sh: language absence ==="

# T7: No Python data → Python section absent from table row
body=$(bash "$SUMMARY" --week 2026-W01 --js-score 75 --js-killed 15 --js-survived 5 2>/dev/null)
if ! echo "$body" | grep -q "mutmut"; then
    pass "T7: No Python args → Python row absent"
else
    fail "T7: Python row should be absent when no --python-score given"
fi

if echo "$body" | grep -q "Stryker"; then
    pass "T8: JS row present when --js-score given"
else
    fail "T8: JS row should be present"
fi

# T9: No languages detected → skip notice
body=$(bash "$SUMMARY" --week 2026-W01 --no-languages-detected 2>/dev/null)
if echo "$body" | grep -q "не обнаружено"; then
    pass "T9: --no-languages-detected → skip notice"
else
    fail "T9: --no-languages-detected should produce skip notice"
fi

if ! echo "$body" | grep -q "mutation score"; then
    pass "T10: skip notice has no results table"
else
    fail "T10: results table should be absent on skip"
fi

echo ""
echo "=== mutation-summary.sh: uninitiated-reader preamble ==="

body=$(bash "$SUMMARY" --week 2026-W01 --python-score 80 --python-killed 20 --python-survived 0 2>/dev/null)

# T11: Preamble explaining mutation testing present
if echo "$body" | grep -qi "mutation testing"; then
    pass "T11: preamble contains 'mutation testing' explanation"
else
    fail "T11: preamble missing"
fi

# T12: Metric explanation present
if echo "$body" | grep -q "Mutation score"; then
    pass "T12: metric explanation table present"
else
    fail "T12: metric explanation missing"
fi

# T13: anti-patterns.md reference present
if echo "$body" | grep -q "anti-patterns.md"; then
    pass "T13: docs/anti-patterns.md reference present"
else
    fail "T13: anti-patterns.md reference missing"
fi

echo ""
echo "=== mutation-summary.sh: multi-language output ==="

# T14: all three languages in one report
body=$(bash "$SUMMARY" --week 2026-W01 \
    --python-score 82 --python-killed 41 --python-survived 9 \
    --js-score 65 --js-killed 26 --js-survived 14 \
    --rust-score 55 --rust-killed 11 --rust-survived 9 2>/dev/null)

if echo "$body" | grep -q "mutmut" && echo "$body" | grep -q "Stryker" && echo "$body" | grep -q "cargo-mutants"; then
    pass "T14: all three language rows present"
else
    fail "T14: not all three language rows found"
fi

# T15: threshold boundary — score exactly 60% → 🟡 (not 🔴)
body=$(bash "$SUMMARY" --week 2026-W01 --python-score 60 --python-killed 12 --python-survived 8 2>/dev/null)
if echo "$body" | grep -q "🟡"; then
    pass "T15: score exactly 60% → 🟡 (boundary)"
else
    fail "T15: score 60% should be 🟡"
fi

# T16: threshold boundary — score exactly 80% → 🟢 (not 🟡)
body=$(bash "$SUMMARY" --week 2026-W01 --python-score 80 --python-killed 16 --python-survived 4 2>/dev/null)
if echo "$body" | grep -q "🟢"; then
    pass "T16: score exactly 80% → 🟢 (boundary)"
else
    fail "T16: score 80% should be 🟢"
fi

echo ""
echo "=== mutation-summary.sh: survivors file ==="

TMPFILE=$(mktemp /tmp/survivors-XXXXXX.txt)
trap 'rm -f "$TMPFILE"' EXIT
printf "src/foo.py:42 - survived: x > 0 → x >= 0\nsrc/bar.py:7 - survived: return True → return False\n" > "$TMPFILE"

body=$(bash "$SUMMARY" --week 2026-W01 \
    --python-score 70 --python-killed 14 --python-survived 2 \
    --python-survivors-file "$TMPFILE" 2>/dev/null)

if echo "$body" | grep -q "src/foo.py"; then
    pass "T17: survivors file content appears in output"
else
    fail "T17: survivors file content missing"
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    printf "%sAll tests passed%s\n" "${GREEN}" "${NC}"
else
    printf "%s%d test(s) failed%s\n" "${RED}" "$FAILURES" "${NC}"
    exit 1
fi
