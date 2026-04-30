#!/usr/bin/env bash
# run.sh — fixture tests for verify.sh (ADR-0023 confirmation check #9)
#
# Tests --full mode to avoid git-state complexity.
# Each test: create a temp dir, install semgrep config, add fixture, run verify.sh --full.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SH="$SCRIPT_DIR/../../scripts/verify.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
SEMGREP_SRC="$SCRIPT_DIR/../../templates/.semgrep"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
pass() { printf "  ${GRN}PASS${NC} %s\n" "$*"; }
fail_test() { printf "  ${RED}FAIL${NC} %s\n" "$*"; FAILURES=$((FAILURES+1)); }
skip() { printf "  ${YEL}SKIP${NC} %s\n" "$*"; }

FAILURES=0

# ── Preflight: check tools ────────────────────────────────────────────────
echo "[run.sh] Checking required tools..."
MISSING=""
for t in ruff eslint radon lizard jscpd semgrep; do
    command -v "$t" >/dev/null 2>&1 || MISSING="${MISSING} $t"
done
if [ -n "$MISSING" ]; then
    skip "Tools not installed:${MISSING} — skipping fixture tests"
    echo "[run.sh] Install missing tools, then re-run."
    exit 0
fi

# ── Helper ────────────────────────────────────────────────────────────────
run_case() {
    local name="$1"
    local fixture="$2"
    local expect_fail="$3"  # "1" if LAYER1_FAILED expected, "0" if not

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # Install semgrep config
    mkdir -p "$tmpdir/.semgrep"
    cp "$SEMGREP_SRC/llm-antipatterns.yaml" "$tmpdir/.semgrep/"

    # Copy fixture
    cp "$fixture" "$tmpdir/"

    local output
    output=$(cd "$tmpdir" && bash "$VERIFY_SH" --full 2>&1)

    if [ "$expect_fail" = "1" ]; then
        if echo "$output" | grep -q "LAYER1_FAILED"; then
            pass "$name (LAYER1_FAILED as expected)"
        else
            fail_test "$name (expected LAYER1_FAILED, got LAYER1_PASSED)"
            echo "    Output: $output" | head -5
        fi
    else
        if echo "$output" | grep -q "LAYER1_FAILED"; then
            fail_test "$name (unexpected LAYER1_FAILED)"
            echo "    Output: $output" | head -10
        else
            pass "$name (no LAYER1_FAILED)"
        fi
    fi
}

# ── Test cases ────────────────────────────────────────────────────────────
echo "[run.sh] Running fixture tests..."

run_case "clean Python file"          "$FIXTURES/clean.py"          "0"
run_case "radon CC violation"         "$FIXTURES/radon_violation.py" "1"
run_case "TODO without ticket (semgrep)" "$FIXTURES/todo_violation.py" "1"

# ── Missing-tool test ─────────────────────────────────────────────────────
echo "[run.sh] Testing missing-tool=fail behaviour..."
tmpdir2=$(mktemp -d)
trap 'rm -rf "$tmpdir2"' EXIT
mkdir -p "$tmpdir2/.semgrep"
cp "$SEMGREP_SRC/llm-antipatterns.yaml" "$tmpdir2/.semgrep/"
cp "$FIXTURES/clean.py" "$tmpdir2/"

# Mask 'semgrep' from PATH and re-run
fake_path=$(mktemp -d)
# Symlink all PATH entries except semgrep
IFS=':' read -ra path_entries <<< "$PATH"
for d in "${path_entries[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] || [ -L "$f" ] || continue
        bn=$(basename "$f")
        [ "$bn" = "semgrep" ] && continue
        [ -e "$fake_path/$bn" ] || ln -s "$f" "$fake_path/$bn" 2>/dev/null || true
    done
done

missing_out=$(cd "$tmpdir2" && PATH="$fake_path" bash "$VERIFY_SH" --full 2>&1) || true
if echo "$missing_out" | grep -q "LAYER1_FAILED" && echo "$missing_out" | grep -q "semgrep"; then
    pass "missing-tool=fail (semgrep masked → LAYER1_FAILED with tool name)"
else
    fail_test "missing-tool=fail (expected LAYER1_FAILED mentioning semgrep)"
    echo "    Output: $missing_out" | head -5
fi
rm -rf "$fake_path"

# ── Diff-detection failure test (GIT_DIFF_OK=0) ───────────────────────────
# Exercises _detect_diff_files() on a brand-new repo with no HEAD.
# Fake tool stubs (exit 0, no output) let us get past the tool-availability
# check so _detect_diff_files() is reached and tested.
echo "[run.sh] Testing diff-detection failure (no-HEAD repo)..."
tmpdir3=$(mktemp -d)
fake_tools=$(mktemp -d)
for t in ruff eslint radon lizard jscpd semgrep; do
    printf '#!/bin/sh\nexit 0\n' > "$fake_tools/$t"
    chmod +x "$fake_tools/$t"
done
mkdir -p "$tmpdir3/.semgrep"
cp "$SEMGREP_SRC/llm-antipatterns.yaml" "$tmpdir3/.semgrep/"
(cd "$tmpdir3" && git init -q 2>/dev/null) || true

nohead_out=$(cd "$tmpdir3" && PATH="$fake_tools:$PATH" bash "$VERIFY_SH" 2>&1) || true
if echo "$nohead_out" | grep -q "LAYER1_FAILED" && echo "$nohead_out" | grep -q "diff-detection"; then
    pass "diff-detection failure → LAYER1_FAILED with [diff-detection] token"
else
    fail_test "diff-detection failure: expected LAYER1_FAILED + [diff-detection]"
    echo "    Output: $nohead_out" | head -5
fi
rm -rf "$tmpdir3" "$fake_tools"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    printf '%bAll tests passed.%b\n' "$GRN" "$NC"
    exit 0
else
    printf '%b%d test(s) failed.%b\n' "$RED" "$FAILURES" "$NC"
    exit 1
fi
