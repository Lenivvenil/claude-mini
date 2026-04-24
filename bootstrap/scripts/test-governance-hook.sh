#!/usr/bin/env bash
# test-governance-hook.sh — smoke-test for pre-commit-governance.sh
#
# Verifies all 4 bad-commit patterns are blocked (exit 2) and
# 2 good-commit patterns are allowed (exit 0), without going through Claude.
#
# Usage:
#   bash ~/.claude/scripts/test-governance-hook.sh
#   # or from repo: bash bootstrap/scripts/test-governance-hook.sh
#
# Exit codes: 0 = all tests passed, 1 = one or more failures

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/pre-commit-governance.sh}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
pass() { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; FAILURES=$((FAILURES+1)); }

FAILURES=0

# --- Preflight ---

if [ ! -x "$HOOK" ]; then
    printf "${RED}FATAL:${NC} hook not found or not executable: %s\n" "$HOOK" >&2
    echo "Install with: ./bootstrap/universal-setup.sh --install" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    printf '%sFATAL:%s jq is required but not installed\n' "$RED" "$NC" >&2
    exit 1
fi

echo "=== Governance hook smoke-test ==="
echo "Hook: $HOOK"
echo ""

# --- Temp repo setup ---
# Branch must be 'smoketest' (no digits, not 'main'):
#   - no digits → Rule 2 fires correctly for no-issue-ref cases
#   - not 'main' → Rule 4 (no direct commits to main) doesn't fire, masking other rules

TMPDIR_REPO=$(mktemp -d /tmp/claude-mini-hook-test-XXXXXX)
trap 'rm -rf "$TMPDIR_REPO"' EXIT

git -C "$TMPDIR_REPO" init -q
# Set branch to 'smoketest' (no digits, not 'main') before first commit.
# symbolic-ref is used directly because 'git init --initial-branch' on an
# already-initialized repo may succeed but silently leave the branch unchanged.
git -C "$TMPDIR_REPO" symbolic-ref HEAD refs/heads/smoketest

git -C "$TMPDIR_REPO" config user.email "test@example.com"
git -C "$TMPDIR_REPO" config user.name "Test"

# Create initial commit so 'git diff --cached' works
touch "$TMPDIR_REPO/README.md"
git -C "$TMPDIR_REPO" add README.md
git -C "$TMPDIR_REPO" commit -q -m "chore: initial commit"

# --- Helper ---

run_hook() {
    local cmd="$1"
    local cwd="${2:-$TMPDIR_REPO}"
    # Use jq to build JSON so embedded quotes in cmd are properly escaped
    jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
        '{"tool_input":{"command":$cmd},"cwd":$cwd}' \
        | "$HOOK" 2>/dev/null
    echo "exit=$?"
}

assert_blocked() {
    local label="$1"
    local cmd="$2"
    local expected_reason_substr="$3"
    local cwd="${4:-$TMPDIR_REPO}"

    result=$(run_hook "$cmd" "$cwd")
    exit_code=$(echo "$result" | grep -oE 'exit=[0-9]+' | tail -1 | cut -d= -f2)
    reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")

    if [ "$exit_code" != "2" ]; then
        fail "$label — expected exit 2, got exit $exit_code"
        return
    fi
    if [ -z "$reason" ]; then
        fail "$label — exit 2 but deny reason is empty"
        return
    fi
    if ! echo "$reason" | grep -qi "$expected_reason_substr"; then
        fail "$label — exit 2 but wrong rule fired. Expected reason containing '$expected_reason_substr', got: $reason"
        return
    fi
    pass "$label"
}

assert_allowed() {
    local label="$1"
    local cmd="$2"
    local cwd="${3:-$TMPDIR_REPO}"

    result=$(run_hook "$cmd" "$cwd")
    exit_code=$(echo "$result" | grep -oE 'exit=[0-9]+' | tail -1 | cut -d= -f2)

    if [ "$exit_code" != "0" ]; then
        reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
        fail "$label — expected exit 0, got exit $exit_code. Reason: $reason"
        return
    fi
    pass "$label"
}

# --- Bad commit cases (must be blocked) ---

echo "Bad commits (must be blocked with exit 2):"

# No -m flag — exercises quoted-reason JSON path (issue #20 regression guard)
# Before fix: json_deny emits malformed JSON → jq parse fails → reason="" → test fails
assert_blocked \
    "no -m flag — deny reason is valid JSON" \
    'git commit' \
    "without -m"

# Rule 1: no Conventional Commits prefix
assert_blocked \
    "no CC prefix" \
    'git commit -m "just did some stuff"' \
    "Conventional Commits"

# Rule 2: no issue-ref (branch 'smoketest' has no digits)
assert_blocked \
    "no issue-ref" \
    'git commit -m "feat: add new thing"' \
    "issue"

# Rule 3: decision-type change (docs/domain/ staged) without ADR-ref
# Stages docs/domain/test-entity.md — matches decision_markers but NOT ^docs/decisions/[0-9]+-.*\.md$
# (which would set has_adr_ref=true and falsely allow)
mkdir -p "$TMPDIR_REPO/docs/domain"
echo "test" > "$TMPDIR_REPO/docs/domain/test-entity.md"
git -C "$TMPDIR_REPO" add docs/domain/test-entity.md

assert_blocked \
    "decision change without ADR-ref (docs/domain/ staged)" \
    'git commit -m "chore: update adr (#1)"' \
    "ADR"

# Unstage for subsequent tests
git -C "$TMPDIR_REPO" restore --staged docs/domain/test-entity.md 2>/dev/null \
    || git -C "$TMPDIR_REPO" reset HEAD docs/domain/test-entity.md 2>/dev/null || true

# Rule 2 (indirect): breaking change without '!' and no issue-ref
# NOTE: the hook has no dedicated "must use !" rule. This commit is blocked only because
# the branch 'smoketest' has no issue number → Rule 2 fires. If the branch contained a
# number (e.g. feat/something-2), this commit would pass. Gap tracked: add a dedicated
# breaking-change rule in a follow-up ADR.
assert_blocked \
    "breaking change without '!' (blocked via Rule 2 — no issue-ref)" \
    'git commit -m "feat: rename public API"' \
    "issue"

echo ""

# --- Good commit cases (must be allowed) ---

echo "Good commits (must be allowed with exit 0):"

assert_allowed \
    "valid CC + issue ref" \
    'git commit -m "feat: add X (#1)"'

assert_allowed \
    "breaking change with '!' + issue ref" \
    'git commit -m "feat!: rename public API (#1)"'

# --- Summary ---

echo ""
echo "=== Summary ==="
if [ "$FAILURES" -eq 0 ]; then
    printf '%sAll tests passed.%s Governance hook is working correctly.\n' "$GREEN" "$NC"
    exit 0
else
    printf "${RED}%d test(s) failed.${NC} See output above.\n" "$FAILURES"
    echo "If the hook binary fails but was never invoked, check settings.json:"
    echo "  hook path must be ABSOLUTE (/Users/... not ~/...)"
    echo "  See docs/runbooks/incident-recovery.md for full diagnosis."
    exit 1
fi
