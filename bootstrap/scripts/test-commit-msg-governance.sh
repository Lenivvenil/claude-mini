#!/usr/bin/env bash
# test-commit-msg-governance.sh — smoke-test for commit-msg-governance.sh
#
# Verifies that the git-level commit-msg hook blocks bad messages (exit 1)
# and passes good messages (exit 0), in a sandboxed temp git repo.
#
# Usage:
#   bash bootstrap/scripts/test-commit-msg-governance.sh
#   bash bootstrap/scripts/test-commit-msg-governance.sh /path/to/commit-msg-governance.sh
#
# Exit codes: 0 = all tests passed, 1 = one or more failures

set -uo pipefail

# Canonicalize to absolute path so cd into sandbox repos doesn't break the
# hook invocation (relative paths resolve against the current directory).
_hook_default="$(cd "$(dirname "$0")/../.." && pwd)/bootstrap/hooks/commit-msg-governance.sh"
HOOK="${1:-$_hook_default}"
unset _hook_default
# Fall back to installed location
if [ ! -f "$HOOK" ]; then
    HOOK="$HOME/.claude/git-hooks/commit-msg"
fi

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

echo "=== commit-msg governance hook smoke-test ==="
echo "Hook: $HOOK"
echo ""

# --- Sandboxed temp repo ---

TMPDIR_REPO=$(mktemp -d /tmp/claude-mini-commit-msg-test-XXXXXX)
TMPDIR_HOME=$(mktemp -d /tmp/claude-mini-commit-msg-home-XXXXXX)
trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME"' EXIT

# Isolated git config so global ~/.gitconfig doesn't interfere
export GIT_CONFIG_GLOBAL="$TMPDIR_HOME/.gitconfig"
git config --global user.email "test@example.com"
git config --global user.name "Test"

git -C "$TMPDIR_REPO" init -q
# Branch 'feat/test-9': has digits (satisfies Rule 2 branch-ref check), not 'main'
git -C "$TMPDIR_REPO" symbolic-ref HEAD refs/heads/feat/test-9

# Initial commit so git diff --cached works
touch "$TMPDIR_REPO/README.md"
git -C "$TMPDIR_REPO" add README.md
GIT_DIR="$TMPDIR_REPO/.git" GIT_WORK_TREE="$TMPDIR_REPO" git commit -q -m "chore: initial (#0)"

# --- Helper: write msg to file and run hook ---

run_hook() {
    local msg="$1"
    local repo="${2:-$TMPDIR_REPO}"
    local msg_file
    msg_file=$(mktemp)
    echo "$msg" > "$msg_file"
    (cd "$repo" && "$HOOK" "$msg_file") 2>/dev/null
    local rc=$?
    rm -f "$msg_file"
    return $rc
}

assert_blocked() {
    local label="$1"
    local msg="$2"
    local repo="${3:-$TMPDIR_REPO}"
    if run_hook "$msg" "$repo"; then
        fail "$label — expected exit 1 (blocked), got exit 0 (passed)"
    else
        pass "$label — correctly blocked"
    fi
}

assert_allowed() {
    local label="$1"
    local msg="$2"
    local repo="${3:-$TMPDIR_REPO}"
    if run_hook "$msg" "$repo"; then
        pass "$label — correctly allowed"
    else
        fail "$label — expected exit 0 (passed), got exit 1 (blocked)"
    fi
}

# ===== RULE 1: Conventional Commits =====
echo "Rule 1: Conventional Commits prefix"

assert_blocked "R1-bad: no prefix" \
    "just did some stuff"

assert_blocked "R1-bad: wrong prefix" \
    "update: something (#9)"

assert_blocked "R1-bad: CC prefix missing colon space" \
    "feat:no space after colon (#9)"

assert_allowed "R1-good: feat type" \
    "feat: add commit-msg hook (#9)"

assert_allowed "R1-good: fix with scope" \
    "fix(hooks): handle empty message (#9)"

assert_allowed "R1-good: breaking change" \
    "feat!: rename public API (#9)"

echo ""

# ===== RULE 2: Issue reference =====
echo "Rule 2: Issue reference"

# Branch 'smoketest' has no digits — tests branch-ref path
TMPDIR_REPO2=$(mktemp -d /tmp/claude-mini-commit-msg-test2-XXXXXX)
git -C "$TMPDIR_REPO2" init -q
git -C "$TMPDIR_REPO2" symbolic-ref HEAD refs/heads/smoketest
git config --global user.email "test@example.com"
touch "$TMPDIR_REPO2/f"
git -C "$TMPDIR_REPO2" add f
GIT_DIR="$TMPDIR_REPO2/.git" GIT_WORK_TREE="$TMPDIR_REPO2" git commit -q -m "chore: init (#0)"
trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME" "$TMPDIR_REPO2"' EXIT

assert_blocked "R2-bad: no issue ref (no-digit branch)" \
    "feat: add thing" "$TMPDIR_REPO2"

assert_allowed "R2-good: issue ref in message" \
    "feat: add thing (#9)" "$TMPDIR_REPO2"

assert_allowed "R2-good: Closes ref in message" \
    "feat: add thing (Closes #9)" "$TMPDIR_REPO2"

assert_allowed "R2-good: issue ref from branch digits (feat/test-9)" \
    "feat: add thing"

assert_allowed "R2-good: adr-commit exempt from issue ref" \
    "adr: add 0011 git-level hook" "$TMPDIR_REPO2"

assert_allowed "R2-good: bootstrap commit exempt" \
    "chore: initial bootstrap setup" "$TMPDIR_REPO2"

echo ""

# ===== RULE 3: ADR reference for decision-type changes =====
echo "Rule 3: ADR reference for decision-type staged changes"

# Stage a decision-type file (go.mod is a recognised decision marker)
echo 'module example.com/test' > "$TMPDIR_REPO/go.mod"
git -C "$TMPDIR_REPO" add "go.mod"

assert_blocked "R3-bad: decision-type staged, no ADR ref" \
    "feat: add go module (#9)"

assert_allowed "R3-good: decision-type staged with ADR ref in message" \
    "feat: add go module (#9) Implements ADR-0011"

assert_allowed "R3-good: decision-type staged with docs/decisions ref" \
    "feat: add go module (#9) docs/decisions/0011-git-level-governance-phase2.md"

# Stage the ADR itself alongside a decision-type file
mkdir -p "$TMPDIR_REPO/docs/decisions"
touch "$TMPDIR_REPO/docs/decisions/0012-test.md"
git -C "$TMPDIR_REPO" add "docs/decisions/0012-test.md"
git -C "$TMPDIR_REPO" add "go.mod"

assert_allowed "R3-good: adr-commit exempted (prefix)" \
    "adr: add 0012 test decision (#9)"

assert_allowed "R3-good: ADR file staged alongside decision-type file" \
    "feat: add module + ADR (#9)"

# Reset staged state
git -C "$TMPDIR_REPO" restore --staged . 2>/dev/null || true

echo ""

# ===== SPECIAL CASES =====
echo "Special cases"

assert_allowed "SC-good: merge commit passes through" \
    "Merge branch 'feat/something' into main"

assert_allowed "SC-good: fixup commit passes through" \
    "fixup! feat: previous commit (#9)"

assert_allowed "SC-good: squash commit passes through" \
    "squash! feat: previous commit (#9)"

assert_blocked "SC-bad: empty message" \
    ""

assert_allowed "SC-good: multi-line message (subject checked, body allowed)" \
    "$(printf 'feat: add hook (#9)\n\nLonger description here.\nMore details.')"

assert_allowed "SC-good: issue ref in body only (multi-line, no-digit branch)" \
    "$(printf 'feat: do thing\n\nCloses #9\n')" "$TMPDIR_REPO2"

# Decision-type staged + ADR ref in body (multi-line commit message)
echo "module example.com/test2" > "$TMPDIR_REPO/go.mod"
git -C "$TMPDIR_REPO" add "go.mod"
assert_allowed "SC-good: ADR ref in body of multi-line msg (decision-type staged)" \
    "$(printf 'feat: add module (#9)\n\nImplements ADR-0011\n')"
git -C "$TMPDIR_REPO" restore --staged "go.mod" 2>/dev/null || true

echo ""

# ===== --hook-this-repo INSTALLER MODE =====
echo "--hook-this-repo installer mode"

INSTALLER="$(dirname "$0")/../../bootstrap/universal-setup.sh"
if [ ! -f "$INSTALLER" ]; then
    echo "  (installer not found at $INSTALLER — HTR tests skipped; run from repo root to include them)"
else
    # Isolated HOME so we don't touch real ~/.claude
    FAKE_HOME=$(mktemp -d)
    mkdir -p "$FAKE_HOME/.claude/git-hooks"
    cp "$HOOK" "$FAKE_HOME/.claude/git-hooks/commit-msg"
    chmod +x "$FAKE_HOME/.claude/git-hooks/commit-msg"
    trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME" "$TMPDIR_REPO2" "$FAKE_HOME"' EXIT

    INSTALL_REPO=$(mktemp -d)
    git init -q "$INSTALL_REPO"
    git -C "$INSTALL_REPO" config user.email "test@example.com"
    git -C "$INSTALL_REPO" config user.name "Test"

    # T1: fresh install succeeds
    if (cd "$INSTALL_REPO" && HOME="$FAKE_HOME" bash "$INSTALLER" --hook-this-repo >/dev/null 2>&1); then
        if [ -x "$INSTALL_REPO/.git/hooks/commit-msg" ]; then
            pass "HTR-good: installs hook into fresh repo"
        else
            fail "HTR-good: install exited 0 but hook not executable"
        fi
    else
        fail "HTR-good: install into fresh repo exited non-zero"
    fi

    # T2: idempotent re-install (same content, no --force)
    if (cd "$INSTALL_REPO" && HOME="$FAKE_HOME" bash "$INSTALLER" --hook-this-repo >/dev/null 2>&1); then
        pass "HTR-good: idempotent re-install (identical content)"
    else
        fail "HTR-good: idempotent re-install failed"
    fi

    # T3: different existing hook without --force → exit 4
    echo "#!/bin/sh" > "$INSTALL_REPO/.git/hooks/commit-msg"
    rc=0
    (cd "$INSTALL_REPO" && HOME="$FAKE_HOME" bash "$INSTALLER" --hook-this-repo >/dev/null 2>&1) || rc=$?
    if [ "$rc" -eq 4 ]; then
        pass "HTR-good: refuses to overwrite different hook without --force (exit 4)"
    else
        fail "HTR-bad: expected exit 4, got exit $rc"
    fi

    # T4: --force overwrites
    if (cd "$INSTALL_REPO" && HOME="$FAKE_HOME" bash "$INSTALLER" --hook-this-repo --force >/dev/null 2>&1); then
        if cmp -s "$FAKE_HOME/.claude/git-hooks/commit-msg" "$INSTALL_REPO/.git/hooks/commit-msg"; then
            pass "HTR-good: --force overwrites different hook"
        else
            fail "HTR-good: --force ran but content differs"
        fi
    else
        fail "HTR-good: --force failed"
    fi

    # T5: non-git directory → exit 3
    NONGIT_DIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME" "$TMPDIR_REPO2" "$FAKE_HOME" "$INSTALL_REPO" "$NONGIT_DIR"' EXIT
    rc=0
    (cd "$NONGIT_DIR" && HOME="$FAKE_HOME" bash "$INSTALLER" --hook-this-repo >/dev/null 2>&1) || rc=$?
    if [ "$rc" -eq 3 ]; then
        pass "HTR-good: fails cleanly in non-git directory (exit 3)"
    else
        fail "HTR-bad: expected exit 3 in non-git dir, got exit $rc"
    fi

    # T6: staged hook missing → exit 2
    EMPTY_HOME=$(mktemp -d)
    mkdir -p "$EMPTY_HOME/.claude/git-hooks"
    trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME" "$TMPDIR_REPO2" "$FAKE_HOME" "$INSTALL_REPO" "$NONGIT_DIR" "$EMPTY_HOME"' EXIT
    rc=0
    (cd "$INSTALL_REPO" && HOME="$EMPTY_HOME" bash "$INSTALLER" --hook-this-repo >/dev/null 2>&1) || rc=$?
    if [ "$rc" -eq 2 ]; then
        pass "HTR-good: fails cleanly when staged hook missing (exit 2)"
    else
        fail "HTR-bad: expected exit 2 when staged hook missing, got exit $rc"
    fi
fi

echo ""

# ===== ANTI-PATTERNS REMINDER =====
# Tests for the non-blocking reminder that fires when code is staged but
# docs/anti-patterns.md has never been touched on the current HEAD.
echo "Anti-patterns reminder (non-blocking)"

# Helper: run hook, capture stderr, return exit code via global AP_STDERR
AP_STDERR=""
run_hook_capture_stderr() {
    local msg="$1"
    local repo="${2:-$TMPDIR_REPO}"
    local msg_file stderr_file
    msg_file=$(mktemp)
    stderr_file=$(mktemp)
    echo "$msg" > "$msg_file"
    (cd "$repo" && "$HOOK" "$msg_file") 2>"$stderr_file"
    local rc=$?
    AP_STDERR=$(cat "$stderr_file")
    rm -f "$msg_file" "$stderr_file"
    return $rc
}

assert_stderr_contains() {
    local label="$1"
    local pattern="$2"
    if echo "$AP_STDERR" | grep -qF "$pattern"; then
        pass "$label — stderr contains expected pattern"
    else
        fail "$label — expected stderr to contain '$pattern'; got: $AP_STDERR"
    fi
}

assert_stderr_lacks() {
    local label="$1"
    local pattern="$2"
    if echo "$AP_STDERR" | grep -qF "$pattern"; then
        fail "$label — expected stderr NOT to contain '$pattern'; got: $AP_STDERR"
    else
        pass "$label — stderr correctly lacks '$pattern'"
    fi
}

# Sandboxed repo for reminder tests — no prior commits touching anti-patterns.md
AP_REPO=$(mktemp -d /tmp/claude-mini-ap-reminder-test-XXXXXX)
trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME" "$TMPDIR_REPO2" "$AP_REPO"' EXIT
git -C "$AP_REPO" init -q
git -C "$AP_REPO" symbolic-ref HEAD refs/heads/feat/ap-124
export GIT_CONFIG_GLOBAL="$TMPDIR_HOME/.gitconfig"
# Initial commit (README only — not touching anti-patterns.md)
echo "readme" > "$AP_REPO/README.md"
git -C "$AP_REPO" add README.md
GIT_DIR="$AP_REPO/.git" GIT_WORK_TREE="$AP_REPO" git commit -q -m "chore: initial (#0)"

# T1: code staged, anti-patterns.md never touched on HEAD → reminder fires
echo "fix-something.sh" > "$AP_REPO/fix-something.sh"
git -C "$AP_REPO" add fix-something.sh
run_hook_capture_stderr "fix: patch something (#124)" "$AP_REPO"
assert_stderr_contains \
    "AP-T1: reminder fires when .sh staged and anti-patterns.md untouched" \
    "REMINDER"

# T2: exit code is still 0 (non-blocking)
run_hook_capture_stderr "fix: patch something (#124)" "$AP_REPO"
if [ $? -eq 0 ]; then
    pass "AP-T2: reminder is non-blocking (exit 0)"
else
    fail "AP-T2: expected exit 0, reminder must not block"
fi

# T3: docs/anti-patterns.md also staged → no reminder
mkdir -p "$AP_REPO/docs"
echo "# Anti-patterns" > "$AP_REPO/docs/anti-patterns.md"
git -C "$AP_REPO" add docs/anti-patterns.md
run_hook_capture_stderr "fix: patch something (#124)" "$AP_REPO"
assert_stderr_lacks \
    "AP-T3: no reminder when docs/anti-patterns.md is staged" \
    "REMINDER"
git -C "$AP_REPO" restore --staged docs/anti-patterns.md 2>/dev/null || true

# T4: anti-patterns.md previously committed on HEAD → no reminder
GIT_DIR="$AP_REPO/.git" GIT_WORK_TREE="$AP_REPO" git add docs/anti-patterns.md
GIT_DIR="$AP_REPO/.git" GIT_WORK_TREE="$AP_REPO" git commit -q -m "docs: seed anti-patterns (#124)"
echo "another-fix.sh" > "$AP_REPO/another-fix.sh"
git -C "$AP_REPO" add another-fix.sh
run_hook_capture_stderr "fix: another fix (#124)" "$AP_REPO"
assert_stderr_lacks \
    "AP-T4: no reminder after anti-patterns.md committed on HEAD" \
    "REMINDER"

# T5: docs-only staged (*.md in docs/) → no reminder
git -C "$AP_REPO" restore --staged . 2>/dev/null || true
echo "# updated" >> "$AP_REPO/README.md"
git -C "$AP_REPO" add README.md
run_hook_capture_stderr "docs: update readme (#124)" "$AP_REPO"
assert_stderr_lacks \
    "AP-T5: no reminder for docs-only commit (no code files staged)" \
    "REMINDER"

# T6: anti-patterns.md committed on main but NOT on current branch → reminder fires
# (validates that merge-base scoping works — prior commits on main must not suppress)
AP_REPO2=$(mktemp -d /tmp/claude-mini-ap-reminder-t6-XXXXXX)
trap 'rm -rf "$TMPDIR_REPO" "$TMPDIR_HOME" "$TMPDIR_REPO2" "$AP_REPO" "$AP_REPO2"' EXIT
git -C "$AP_REPO2" init -q
export GIT_CONFIG_GLOBAL="$TMPDIR_HOME/.gitconfig"
git -C "$AP_REPO2" symbolic-ref HEAD refs/heads/main
# Seed docs/anti-patterns.md on main
mkdir -p "$AP_REPO2/docs"
echo "# Anti-patterns" > "$AP_REPO2/docs/anti-patterns.md"
git -C "$AP_REPO2" add docs/anti-patterns.md
GIT_DIR="$AP_REPO2/.git" GIT_WORK_TREE="$AP_REPO2" git commit -q -m "docs: seed anti-patterns on main (#0)"
# Branch off — new branch has no AP commits of its own
git -C "$AP_REPO2" update-ref refs/heads/feat/new-feature refs/heads/main
git -C "$AP_REPO2" symbolic-ref HEAD refs/heads/feat/new-feature
# Set refs/remotes/origin/main directly — avoids fetching from a non-bare repo
# (fetching from self is unreliable; direct update-ref is deterministic)
git -C "$AP_REPO2" update-ref refs/remotes/origin/main refs/heads/main
# Stage a code file without anti-patterns.md
echo "fix.sh" > "$AP_REPO2/fix.sh"
git -C "$AP_REPO2" add fix.sh
run_hook_capture_stderr "fix: something (#124)" "$AP_REPO2"
assert_stderr_contains \
    "AP-T6: reminder fires on branch even when anti-patterns.md committed on main" \
    "REMINDER"

echo ""

# ===== SUMMARY =====
echo "=== Summary ==="
if [ "$FAILURES" -eq 0 ]; then
    printf '  %sAll tests passed%s\n' "$GREEN" "$NC"
    exit 0
else
    printf '  %s%d test(s) failed%s\n' "$RED" "$FAILURES" "$NC"
    exit 1
fi
