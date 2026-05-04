#!/usr/bin/env bash
# test-hedging-lint.sh — test suite for hedging-lint.sh and .semgrep/hedging.yml
#
# Usage:
#   bash bootstrap/scripts/test-hedging-lint.sh
#   bash bootstrap/scripts/test-hedging-lint.sh /path/to/hedging-lint.sh
#
# Exit codes: 0 = all tests passed, 1 = one or more failures

set -uo pipefail

SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hedging-lint.sh}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"
CONFIG="$REPO_ROOT/.semgrep/hedging.yml"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
FAILURES=0

pass() { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; FAILURES=$((FAILURES+1)); }

# --- Preflight ---

if [ ! -x "$SCRIPT" ]; then
    printf "${RED}FATAL:${NC} script not found or not executable: %s\n" "$SCRIPT" >&2
    exit 1
fi

if ! command -v semgrep >/dev/null 2>&1; then
    printf "${RED}FATAL:${NC} semgrep not installed\n" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    printf "${RED}FATAL:${NC} config not found: %s\n" "$CONFIG" >&2
    exit 1
fi

echo "=== hedging-lint smoke-test ==="
echo "Script: $SCRIPT"
echo "Config: $CONFIG"
echo ""

# --- Temp repo with .semgrep/hedging.yml ---

TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

mkdir -p "$TDIR/.semgrep" "$TDIR/docs/decisions"
cp "$CONFIG" "$TDIR/.semgrep/hedging.yml"

run_lint() {
    local file="$1"
    (cd "$TDIR" && bash "$SCRIPT" "./$file" > /dev/null 2>&1)
    echo $?
}

# --- Tests ---

echo "Banned-terms rule (hedging-banned-terms):"

echo "maybe we should" > "$TDIR/plan.md"
[ "$(run_lint plan.md)" = "1" ] \
    && pass "plan.md with banned term → exit 1" \
    || fail "plan.md with banned term — expected exit 1"

echo "clean content here" > "$TDIR/plan.md"
[ "$(run_lint plan.md)" = "0" ] \
    && pass "plan.md without hedging → exit 0" \
    || fail "plan.md without hedging — expected exit 0"

echo "we might want to do this" > "$TDIR/STATE.md"
[ "$(run_lint STATE.md)" = "1" ] \
    && pass "STATE.md with banned term → exit 1" \
    || fail "STATE.md with banned term — expected exit 1"

echo "perhaps we should reconsider" > "$TDIR/docs/decisions/0042-foo.md"
[ "$(run_lint docs/decisions/0042-foo.md)" = "1" ] \
    && pass "docs/decisions/*.md with banned term → exit 1" \
    || fail "docs/decisions/*.md with banned term — expected exit 1"

echo "maybe we should" > "$TDIR/AGENTS.md"
[ "$(run_lint AGENTS.md)" = "0" ] \
    && pass "AGENTS.md (non-target) with banned term → exit 0 (ignored)" \
    || fail "AGENTS.md (non-target) — expected exit 0 (not scanned)"

echo ""
echo "Inline nosemgrep suppression:"

echo "inline suppressed <!-- nosemgrep: hedging-banned-terms --> maybe" > "$TDIR/plan.md"
[ "$(run_lint plan.md)" = "0" ] \
    && pass "nosemgrep inline on plan.md → exit 0" \
    || fail "nosemgrep inline — expected exit 0"

echo ""
echo "depends-without-branch rule (hedging-depends-without-branch):"

echo "this depends on context" > "$TDIR/plan.md"
[ "$(run_lint plan.md)" = "1" ] \
    && pass "'depends' without branch → exit 1" \
    || fail "'depends' without branch — expected exit 1"

echo "this depends when X then Y, when Z then W" > "$TDIR/plan.md"
[ "$(run_lint plan.md)" = "0" ] \
    && pass "'depends when X then Y' → exit 0 (allowed)" \
    || fail "'depends when X then Y' — expected exit 0"

echo "this depends если X то Y otherwise Z" > "$TDIR/plan.md"
[ "$(run_lint plan.md)" = "0" ] \
    && pass "'depends если X то Y' → exit 0 (allowed)" \
    || fail "'depends если X то Y' — expected exit 0"

echo ""
echo "Setup-error cases (fail-closed):"

echo "clean content" > "$TDIR/plan.md"
# Test missing config
TDIR2=$(mktemp -d)
cp "$TDIR/plan.md" "$TDIR2/plan.md"
# No .semgrep/ in TDIR2 — config missing
lint_exit=$(cd "$TDIR2" && bash "$SCRIPT" ./plan.md > /dev/null 2>&1; echo $?)
[ "$lint_exit" = "2" ] \
    && pass "missing config → exit 2 (fail-closed)" \
    || fail "missing config — expected exit 2, got $lint_exit"
rm -rf "$TDIR2"

echo ""
echo "Empty input:"

result=$(cd "$TDIR" && bash "$SCRIPT" > /dev/null 2>&1; echo $?)
[ "$result" = "0" ] \
    && pass "no args → exit 0 (nothing to scan)" \
    || fail "no args — expected exit 0, got $result"

# --- Summary ---

echo ""
if [ "$FAILURES" -eq 0 ]; then
    printf "${GREEN}PASS${NC} hedging-lint: all tests passed\n"
    exit 0
else
    printf "${RED}FAIL${NC} hedging-lint: %d test(s) failed\n" "$FAILURES"
    exit 1
fi
