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

pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
fail() { printf '  %s✗%s %s\n' "$RED"   "$NC" "$1"; FAILURES=$((FAILURES+1)); }

# --- Preflight ---

if [ ! -x "$SCRIPT" ]; then
    printf '%sFATAL:%s script not found or not executable: %s\n' "$RED" "$NC" "$SCRIPT" >&2
    exit 1
fi

if ! command -v semgrep >/dev/null 2>&1; then
    printf '%sFATAL:%s semgrep not installed\n' "$RED" "$NC" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    printf '%sFATAL:%s config not found: %s\n' "$RED" "$NC" "$CONFIG" >&2
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
    printf '%s\n' "$?"
}

assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label — expected exit $expected, got $actual"
    fi
}

# --- Tests ---

echo "Banned-terms rule (hedging-banned-terms):"

echo "maybe we should" > "$TDIR/plan.md"
assert_exit "plan.md with banned term → exit 1" "1" "$(run_lint plan.md)"

echo "clean content here" > "$TDIR/plan.md"
assert_exit "plan.md without hedging → exit 0" "0" "$(run_lint plan.md)"

echo "we might want to do this" > "$TDIR/STATE.md"
assert_exit "STATE.md with banned term → exit 1" "1" "$(run_lint STATE.md)"

echo "perhaps we should reconsider" > "$TDIR/docs/decisions/0042-foo.md"
assert_exit "docs/decisions/*.md with banned term → exit 1" "1" "$(run_lint docs/decisions/0042-foo.md)"

echo "maybe we should" > "$TDIR/AGENTS.md"
assert_exit "AGENTS.md (non-target) with banned term → exit 0 (ignored)" "0" "$(run_lint AGENTS.md)"

echo ""
echo "Inline nosemgrep suppression:"

echo "inline suppressed <!-- nosemgrep: hedging-banned-terms --> maybe" > "$TDIR/plan.md"
assert_exit "nosemgrep inline on plan.md → exit 0" "0" "$(run_lint plan.md)"

echo ""
echo "depends-without-branch rule (hedging-depends-without-branch):"

echo "this depends on context" > "$TDIR/plan.md"
assert_exit "'depends' without branch → exit 1" "1" "$(run_lint plan.md)"

echo "this depends when X then Y, when Z then W" > "$TDIR/plan.md"
assert_exit "'depends when X then Y' → exit 0 (allowed)" "0" "$(run_lint plan.md)"

echo "this depends если X то Y otherwise Z" > "$TDIR/plan.md"
assert_exit "'depends если X то Y' → exit 0 (allowed)" "0" "$(run_lint plan.md)"

echo ""
echo "Setup-error cases (fail-closed):"

echo "clean content" > "$TDIR/plan.md"
TDIR2=$(mktemp -d)
cp "$TDIR/plan.md" "$TDIR2/plan.md"
lint_exit=$(cd "$TDIR2" && bash "$SCRIPT" ./plan.md > /dev/null 2>&1; echo $?)
assert_exit "missing config → exit 2 (fail-closed)" "2" "$lint_exit"
rm -rf "$TDIR2"

echo ""
echo "Empty input:"

result=$(cd "$TDIR" && bash "$SCRIPT" > /dev/null 2>&1; echo $?)
assert_exit "no args → exit 0 (nothing to scan)" "0" "$result"

# --- Summary ---

echo ""
if [ "$FAILURES" -eq 0 ]; then
    printf '%sPASS%s hedging-lint: all tests passed\n' "$GREEN" "$NC"
    exit 0
else
    printf '%sFAIL%s hedging-lint: %d test(s) failed\n' "$RED" "$NC" "$FAILURES"
    exit 1
fi
