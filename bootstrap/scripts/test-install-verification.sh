#!/usr/bin/env bash
# test-install-verification.sh — smoke-tests for ADR-0019 fixes
#
# Verifies:
#   Gap #2: --hook-this-repo exits non-zero on cp failure; post-copy cmp -s fires
#   Gap #3: --target exits non-zero (die) on cp failure into read-only dir
#   Gap #1: copy_file() source-missing branch calls drift() not warn() (structural)
#   Regression: test-governance-hook.sh still passes
#
# Uses isolated temp HOME and temp repos — does not touch ~/.claude/ or any live repo.
#
# Usage:
#   bash bootstrap/scripts/test-install-verification.sh
#   # or after install: bash ~/.claude/scripts/test-install-verification.sh
#
# Exit codes: 0 = all tests passed, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/bootstrap/universal-setup.sh"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
pass() { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; FAILURES=$((FAILURES+1)); }
skip() { printf "  ${YELLOW}s${NC} %s\n" "$1"; }

FAILURES=0

# ---- Preflight ----
if [ ! -x "$SETUP" ]; then
    printf "${RED}FATAL:${NC} setup script not found or not executable: %s\n" "$SETUP" >&2
    exit 1
fi

# ---- Temp environment ----
FAKE_HOME=$(mktemp -d /tmp/claude-mini-verify-home-XXXXXX)
FAKE_REPO=$(mktemp -d /tmp/claude-mini-verify-repo-XXXXXX)
FAKE_TARGET=$(mktemp -d /tmp/claude-mini-verify-target-XXXXXX)
trap 'chmod -R u+w "$FAKE_HOME" "$FAKE_REPO" "$FAKE_TARGET" 2>/dev/null; rm -rf "$FAKE_HOME" "$FAKE_REPO" "$FAKE_TARGET"' EXIT

git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.email "test@example.com"
git -C "$FAKE_REPO" config user.name "Test"

echo "=== test-install-verification ==="
echo "Setup: $SETUP"
echo ""

# ---- Gap #2: --hook-this-repo post-copy verification ----
echo "Gap #2: --hook-this-repo post-copy cmp -s"

STAGED_HOOK="$FAKE_HOME/.claude/git-hooks/commit-msg"
DEST_HOOK="$FAKE_REPO/.git/hooks/commit-msg"
mkdir -p "$FAKE_HOME/.claude/git-hooks"
printf '#!/bin/bash\n# test staged hook\nexit 0\n' > "$STAGED_HOOK"
chmod +x "$STAGED_HOOK"

# 2a: clean install — should succeed and install matching hook
if (cd "$FAKE_REPO" && HOME="$FAKE_HOME" bash "$SETUP" --hook-this-repo >/dev/null 2>&1); then
    if [ -f "$DEST_HOOK" ] && cmp -s "$STAGED_HOOK" "$DEST_HOOK"; then
        pass "clean install: hook matches source (cmp -s OK)"
    else
        fail "clean install: hook installed but content differs or missing"
    fi
else
    fail "clean install: --hook-this-repo failed unexpectedly (exit $?)"
fi

# 2b: corrupt installed hook, re-run --force — post-copy cmp -s must fire and pass
if [ -f "$DEST_HOOK" ]; then
    printf '\ncorrupted\n' >> "$DEST_HOOK"
    if (cd "$FAKE_REPO" && HOME="$FAKE_HOME" bash "$SETUP" --hook-this-repo --force >/dev/null 2>&1); then
        if cmp -s "$STAGED_HOOK" "$DEST_HOOK"; then
            pass "--force reinstall: post-copy cmp -s passes (hook restored)"
        else
            fail "--force reinstall: hook content still differs after reinstall"
        fi
    else
        fail "--force reinstall: failed unexpectedly (exit $?)"
    fi
else
    skip "2b skipped: hook not installed by 2a"
fi

# 2c: staged hook absent — should exit non-zero (exit 2)
MISSING_HOME=$(mktemp -d /tmp/claude-mini-verify-missinghome-XXXXXX)
# Append to existing trap rather than overwriting it
trap 'chmod -R u+w "$FAKE_HOME" "$FAKE_REPO" "$FAKE_TARGET" "$MISSING_HOME" 2>/dev/null; rm -rf "$FAKE_HOME" "$FAKE_REPO" "$FAKE_TARGET" "$MISSING_HOME"' EXIT
if (cd "$FAKE_REPO" && HOME="$MISSING_HOME" bash "$SETUP" --hook-this-repo >/dev/null 2>&1); then
    fail "missing staged hook: should have exited non-zero but exited 0"
else
    pass "missing staged hook: exits non-zero (staged hook absent check works)"
fi

# ---- Gap #3: --target cp failure on read-only dir ----
echo ""
echo "Gap #3: --target cp failure on read-only commands dir"

mkdir -p "$FAKE_TARGET/.claude/commands"
chmod 555 "$FAKE_TARGET/.claude/commands"

# Run --target against the real repo (needs VERSION file) with read-only destination
if bash "$SETUP" --target "$FAKE_TARGET" >/dev/null 2>&1; then
    fail "--target should have failed on read-only dir but exited 0"
else
    _exit=$?
    if [ "$_exit" -eq 3 ]; then
        pass "--target exits 3 (die) on cp failure into read-only dir"
    else
        pass "--target exits non-zero ($_exit) on cp failure (acceptable)"
    fi
fi

# Restore perms so trap can clean up
chmod 755 "$FAKE_TARGET/.claude/commands"

# ---- Gap #1: copy_file() source-missing calls drift() (structural) ----
echo ""
echo "Gap #1: copy_file() source-missing structural check"

if grep -A2 '! -f.*src' "$SETUP" | grep -q 'drift'; then
    pass "copy_file() source-missing branch calls drift() not warn()"
elif grep -A2 '! -f.*src' "$SETUP" | grep -q 'warn'; then
    fail "copy_file() source-missing branch still calls warn() — fix not applied"
else
    fail "copy_file() source-missing pattern not found in $SETUP"
fi

# ---- Gap #2 inline structural check ----
echo ""
echo "Gap #2: --hook-this-repo structural check"

if grep -A1 'cp.*STAGED_HOOK.*DEST_HOOK' "$SETUP" | grep -q 'die'; then
    pass "--hook-this-repo cp line has || die guard"
else
    fail "--hook-this-repo cp line missing || die guard"
fi

if grep 'cmp -s.*STAGED_HOOK.*DEST_HOOK.*die' "$SETUP" >/dev/null 2>&1; then
    pass "--hook-this-repo has post-copy cmp -s || die"
else
    fail "--hook-this-repo missing post-copy cmp -s || die"
fi

if grep 'chmod +x.*DEST_HOOK.*die' "$SETUP" >/dev/null 2>&1; then
    pass "--hook-this-repo chmod has || die guard"
else
    fail "--hook-this-repo chmod missing || die guard"
fi

# ---- Gap #3 structural check ----
echo ""
echo "Gap #3: --target cp structural check"

if grep 'cp.*baked.*dst.*die' "$SETUP" >/dev/null 2>&1; then
    pass "--target cp line has || die guard"
else
    fail "--target cp line missing || die guard"
fi

# ---- Gap #4: --target delivers all expected template files ----
echo ""
echo "Gap #4: --target delivers template files (structural + functional)"

for f in "ruff.toml" ".eslintrc.json" ".jscpd.json" "AGENTS.md" "CLAUDE.md" "STATE.md"; do
    if grep -q "\"$f\"" "$SETUP" 2>/dev/null || grep -q "/$f" "$SETUP" 2>/dev/null; then
        pass "--target section references $f"
    else
        fail "--target section missing $f"
    fi
done
if grep -q 'llm-antipatterns.yaml' "$SETUP" 2>/dev/null; then
    pass "--target section references .semgrep/llm-antipatterns.yaml"
else
    fail "--target section missing .semgrep/llm-antipatterns.yaml"
fi
if grep -q 'hedging.yml' "$SETUP" 2>/dev/null; then
    pass "--target section references .semgrep/hedging.yml"
else
    fail "--target section missing .semgrep/hedging.yml"
fi

# Functional: run --target against a temp dir and verify all eight files land
_T=$(mktemp -d /tmp/claude-mini-verify-templates-XXXXXX)
if bash "$SETUP" --target "$_T" >/dev/null 2>&1; then
    for f in "ruff.toml" ".eslintrc.json" ".jscpd.json" ".semgrep/llm-antipatterns.yaml" ".semgrep/hedging.yml" "AGENTS.md" "CLAUDE.md" "STATE.md"; do
        if [ -f "$_T/$f" ]; then
            pass "--target functional: $_T/$f created"
        else
            fail "--target functional: $_T/$f missing"
        fi
    done
    # Idempotent re-run must report no drift — capture once, grep twice (portable ERE)
    _rerun_out=$(bash "$SETUP" --target "$_T" 2>&1)
    if echo "$_rerun_out" | grep -qE "DRIFT=0|no drift"; then
        pass "--target re-run: no drift"
    elif ! echo "$_rerun_out" | grep -q "drift:"; then
        pass "--target re-run: identical skip (no drift output)"
    else
        fail "--target re-run: drift reported on second run"
    fi
else
    fail "--target functional run failed (exit non-zero)"
fi
rm -rf "$_T"

# ---- implement.md verification step present ----
echo ""
echo "AC: implement.md Phase 3 contains verification step"

IMPLEMENT_MD="$REPO_ROOT/bootstrap/commands/implement.md"
if grep -q 'ADR-0019' "$IMPLEMENT_MD" 2>/dev/null; then
    pass "implement.md Phase 3 references ADR-0019"
else
    fail "implement.md Phase 3 missing ADR-0019 verification step"
fi

if grep -q '\-\-check' "$IMPLEMENT_MD" 2>/dev/null; then
    pass "implement.md Phase 3 references --check"
else
    fail "implement.md Phase 3 missing --check verification step"
fi

# ---- Regression: governance hook smoke-test ----
echo ""
echo "Regression: test-governance-hook.sh"

GOVERNANCE_HOOK="$REPO_ROOT/bootstrap/hooks/pre-commit-governance.sh"
TEST_GOVERNANCE="$REPO_ROOT/bootstrap/scripts/test-governance-hook.sh"

if [ -x "$TEST_GOVERNANCE" ] && [ -x "$GOVERNANCE_HOOK" ]; then
    if bash "$TEST_GOVERNANCE" "$GOVERNANCE_HOOK" >/dev/null 2>&1; then
        pass "test-governance-hook.sh passes (no regression)"
    else
        fail "test-governance-hook.sh FAILED — regression in universal-setup.sh changes"
    fi
else
    skip "test-governance-hook.sh or hook not found — skip regression"
fi

# ---- Summary ----
echo ""
echo "=== Summary ==="
if [ "$FAILURES" -eq 0 ]; then
    printf '%sAll tests passed.%s\n' "$GREEN" "$NC"
    exit 0
else
    printf "${RED}%d test(s) failed.${NC}\n" "$FAILURES"
    exit 1
fi
