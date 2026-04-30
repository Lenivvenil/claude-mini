#!/usr/bin/env bash
# test-posttooluse-hook.sh — Integration tests for posttooluse-format.sh
#
# Запуск: bash bootstrap/scripts/test-posttooluse-hook.sh
# Требует: jq. Инструменты (ruff, prettier, gofmt) — опциональны;
# если не установлены, соответствующие тесты пропускаются с SKIP.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/posttooluse-format.sh"

PASS=0; FAIL=0; SKIP=0

pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $*"; SKIP=$((SKIP+1)); }

require_tool() {
    command -v "$1" >/dev/null 2>&1
}

# Each test gets a fresh tmpdir + overridden log path
run_hook() {
    local payload="$1"
    local log_path="$2"
    POSTTOOLUSE_LOG="$log_path" bash "$HOOK" <<< "$payload"
}

echo "=== posttooluse-format.sh integration tests ==="
echo ""

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------
# Helper: build payload
# ---------------------------------------------------------------
mk_payload() {
    local file="$1"
    local cwd="$2"
    jq -n --arg f "$file" --arg c "$cwd" \
        '{"tool_name":"Write","tool_input":{"file_path":$f},"cwd":$c}'
}

# ---------------------------------------------------------------
# TEST: empty file_path → exit 0, no additionalContext
# ---------------------------------------------------------------
echo "--- edge: empty file_path ---"
tmplog=$(mktemp)
out=$(POSTTOOLUSE_LOG="$tmplog" bash "$HOOK" <<< '{"tool_name":"Write","tool_input":{}}' 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "exit 0 on empty file_path"; else fail "expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "no output on empty file_path"; else fail "expected no output, got: $out"; fi

# ---------------------------------------------------------------
# TEST: non-existent file → exit 0, no additionalContext
# ---------------------------------------------------------------
echo "--- edge: non-existent file ---"
tmplog=$(mktemp)
out=$(run_hook "$(mk_payload "/tmp/__does_not_exist_xyz.py" "/tmp")" "$tmplog" 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "exit 0 on missing file"; else fail "expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "no output on missing file"; else fail "expected no output, got: $out"; fi

# ---------------------------------------------------------------
# TEST: unknown extension → exit 0, no output
# ---------------------------------------------------------------
echo "--- edge: unknown extension ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
tmpfile="$tmpdir/data.csv"
echo "a,b,c" > "$tmpfile"
tmplog=$(mktemp)
out=$(run_hook "$(mk_payload "$tmpfile" "$tmpdir")" "$tmplog" 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "exit 0 on unknown extension"; else fail "expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "no additionalContext on unknown extension"; else fail "expected no output, got: $out"; fi
if grep -q "unknown extension" "$tmplog"; then pass "log entry for unknown extension"; else fail "log missing 'unknown extension'"; fi

# ---------------------------------------------------------------
# TEST: clean Python file → exit 0, no additionalContext
# ---------------------------------------------------------------
echo "--- Python: clean file ---"
if ! require_tool ruff; then
    skip "ruff not installed — skipping Python tests"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/clean.py" << 'EOF'
x = 1
y = x + 2
print(y)
EOF
    tmplog=$(mktemp)
    out=$(run_hook "$(mk_payload "$tmpdir/clean.py" "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "Python clean: exit 0"; else fail "Python clean: expected exit 0, got $rc"; fi
    if [ -z "$out" ]; then pass "Python clean: no additionalContext"; else fail "Python clean: unexpected output: $out"; fi
    if grep -q "clean:" "$tmplog"; then pass "Python clean: log entry written"; else fail "Python clean: log entry missing"; fi
fi

# ---------------------------------------------------------------
# TEST: Python file with lint error → additionalContext emitted
# ---------------------------------------------------------------
echo "--- Python: lint error ---"
if ! require_tool ruff; then
    skip "ruff not installed — skipping"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/bad.py" << 'EOF'
import os
x = 1
EOF
    tmplog=$(mktemp)
    out=$(run_hook "$(mk_payload "$tmpdir/bad.py" "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "Python lint error: exit 0"; else fail "Python lint error: expected exit 0, got $rc"; fi
    if echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        pass "Python lint error: additionalContext present"
        ctx=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext')
        echo "    context: $ctx"
    else
        fail "Python lint error: no additionalContext in output: $out"
    fi
fi

# ---------------------------------------------------------------
# TEST: Python format violation → log entry written
# ---------------------------------------------------------------
echo "--- Python: format violation ---"
if ! require_tool ruff; then
    skip "ruff not installed — skipping"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    printf 'x=1+2\nprint(x)\n' > "$tmpdir/unformatted.py"
    tmplog=$(mktemp)
    out=$(run_hook "$(mk_payload "$tmpdir/unformatted.py" "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "Python format violation: exit 0"; else fail "Python format violation: expected exit 0, got $rc"; fi
    if grep -qE "py fmt=|py lint=" "$tmplog"; then pass "Python format violation: log entry written"; else fail "Python format violation: log entry missing"; fi
fi

# ---------------------------------------------------------------
# TEST: Go file with format violation → additionalContext emitted
# ---------------------------------------------------------------
echo "--- Go: format violation ---"
if ! require_tool gofmt; then
    skip "gofmt not installed — skipping Go tests"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/bad.go" << 'EOF'
package main

import "fmt"

func main() {
fmt.Println("hello")
}
EOF
    tmplog=$(mktemp)
    out=$(run_hook "$(mk_payload "$tmpdir/bad.go" "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "Go format violation: exit 0"; else fail "Go format violation: expected exit 0, got $rc"; fi
    if echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        pass "Go format violation: additionalContext present"
    else
        fail "Go format violation: no additionalContext in output: $out"
    fi
    if grep -q "go fmt" "$tmplog"; then pass "Go format violation: log entry written"; else fail "Go format violation: log entry missing"; fi
fi

# ---------------------------------------------------------------
# TEST: Go clean file → no additionalContext
# ---------------------------------------------------------------
echo "--- Go: clean file ---"
if ! require_tool gofmt; then
    skip "gofmt not installed — skipping"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/clean.go" << 'EOF'
package main

import "fmt"

func main() {
	fmt.Println("hello")
}
EOF
    tmplog=$(mktemp)
    out=$(run_hook "$(mk_payload "$tmpdir/clean.go" "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "Go clean: exit 0"; else fail "Go clean: expected exit 0, got $rc"; fi
    if [ -z "$out" ]; then pass "Go clean: no additionalContext"; else fail "Go clean: unexpected output: $out"; fi
    if grep -q "clean:" "$tmplog"; then pass "Go clean: log entry written"; else fail "Go clean: log entry missing"; fi
fi

# ---------------------------------------------------------------
# TEST: log file created on first run (no pre-existing log dir)
# ---------------------------------------------------------------
echo "--- log: created if missing ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
echo "a,b" > "$tmpdir/file.csv"
novel_log="$tmpdir/subdir/test.log"
run_hook "$(mk_payload "$tmpdir/file.csv" "$tmpdir")" "$novel_log" >/dev/null 2>&1
if [ -f "$novel_log" ]; then pass "log file created if missing"; else fail "log file not created"; fi

# ---------------------------------------------------------------
# INSTALLER TESTS: universal-setup.sh PostToolUse patching
# Uses a fake HOME + fake settings.json to avoid touching ~/.claude/
# ---------------------------------------------------------------
echo "--- installer: PostToolUse patching ---"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP="$REPO_ROOT/bootstrap/universal-setup.sh"

if [ ! -x "$SETUP" ] && [ -f "$SETUP" ]; then
    chmod +x "$SETUP"
fi

if [ ! -f "$SETUP" ]; then
    skip "universal-setup.sh not found — skipping installer tests"
else
    FAKE_HOME=$(mktemp -d -p "$TMPDIR_BASE")
    mkdir -p "$FAKE_HOME/.claude/hooks" "$FAKE_HOME/.claude/git-hooks"

    cp "$REPO_ROOT/bootstrap/hooks/posttooluse-format.sh" "$FAKE_HOME/.claude/hooks/posttooluse-format.sh" 2>/dev/null || true

    POSTTOOLUSE_HOOK_PATH="$FAKE_HOME/.claude/hooks/posttooluse-format.sh"

    run_patch() {
        local settings_in="$1"
        local cmd_path="$2"
        jq \
            --arg cmd "$cmd_path" \
            '
            .hooks = (.hooks // {})
            | .hooks.PostToolUse = (.hooks.PostToolUse // [])
            | (
                (.hooks.PostToolUse | map(.matcher == "Edit|MultiEdit|Write") | any) as $has_matcher
                | if $has_matcher then
                    .hooks.PostToolUse |= map(
                        if .matcher == "Edit|MultiEdit|Write" then
                            if (.hooks // [] | map(select(.type == "command" and .command == $cmd)) | length) == 0 then
                                .hooks = ((.hooks // []) + [{"type": "command", "command": $cmd}])
                            else . end
                        else . end
                    )
                else
                    .hooks.PostToolUse += [{
                        "matcher": "Edit|MultiEdit|Write",
                        "hooks": [{"type": "command", "command": $cmd}]
                    }]
                end
            )
            ' <<< "$settings_in"
    }

    # --- installer: fresh settings.json (no PostToolUse) → hook added ---
    echo "--- installer: fresh settings, hook added ---"
    base='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/existing/hook.sh"}]}]}}'
    patched=$(run_patch "$base" "$POSTTOOLUSE_HOOK_PATH")
    count=$(echo "$patched" | jq '[.hooks.PostToolUse[]? | select(.matcher=="Edit|MultiEdit|Write") | .hooks[]? | select(.command=="'"$POSTTOOLUSE_HOOK_PATH"'")] | length')
    if [ "$count" = "1" ]; then pass "installer: hook added once"; else fail "installer: expected 1 entry, got $count"; fi

    # --- installer: PreToolUse is byte-identical after patch ---
    pretooluse_before=$(echo "$base" | jq -cS '.hooks.PreToolUse // []')
    pretooluse_after=$(echo "$patched" | jq -cS '.hooks.PreToolUse // []')
    if [ "$pretooluse_before" = "$pretooluse_after" ]; then pass "installer: PreToolUse unchanged"; else fail "installer: PreToolUse was altered"; fi

    # --- installer: idempotency — second patch does not duplicate entry ---
    echo "--- installer: idempotency ---"
    patched2=$(run_patch "$patched" "$POSTTOOLUSE_HOOK_PATH")
    count2=$(echo "$patched2" | jq '[.hooks.PostToolUse[]? | select(.matcher=="Edit|MultiEdit|Write") | .hooks[]? | select(.command=="'"$POSTTOOLUSE_HOOK_PATH"'")] | length')
    if [ "$count2" = "1" ]; then pass "installer: idempotent (no duplicate on second run)"; else fail "installer: expected 1 entry after second run, got $count2"; fi

    # --- installer: matcher is exactly "Edit|MultiEdit|Write" ---
    echo "--- installer: matcher contract ---"
    matcher=$(echo "$patched" | jq -r '.hooks.PostToolUse[]? | select(.hooks[]?.command=="'"$POSTTOOLUSE_HOOK_PATH"'") | .matcher')
    if [ "$matcher" = "Edit|MultiEdit|Write" ]; then pass "installer: matcher is exactly Edit|MultiEdit|Write"; else fail "installer: matcher is '$matcher', expected 'Edit|MultiEdit|Write'"; fi

    # --- installer: grep -Fxq exact match (not substring) ---
    echo "--- installer: exact-path idempotency guard ---"
    superpath="${POSTTOOLUSE_HOOK_PATH}.bak"
    existing_line="$POSTTOOLUSE_HOOK_PATH"
    if printf '%s\n' "$existing_line" | grep -Fxq "$POSTTOOLUSE_HOOK_PATH"; then
        pass "installer: Fxq matches exact path"
    else
        fail "installer: Fxq failed on exact match"
    fi
    if printf '%s\n' "$superpath" | grep -Fxq "$POSTTOOLUSE_HOOK_PATH"; then
        fail "installer: Fxq matched substring (should not)"
    else
        pass "installer: Fxq correctly rejects superstring"
    fi
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
