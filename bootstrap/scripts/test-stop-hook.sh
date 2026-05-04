#!/usr/bin/env bash
# test-stop-hook.sh — Integration tests for stop-hook.sh
#
# Запуск: bash bootstrap/scripts/test-stop-hook.sh
# Требует: jq. python3/npm — опциональны; тесты без них пропускаются (SKIP).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/stop-hook.sh"

PASS=0; FAIL=0; SKIP=0

pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $*"; SKIP=$((SKIP+1)); }

require_tool() { command -v "$1" >/dev/null 2>&1; }

run_hook() {
    local payload="$1"
    local log_path="$2"
    STOP_HOOK_LOG="$log_path" bash "$HOOK" <<< "$payload"
}

mk_payload() {
    local cwd="$1"
    local stop_active="${2:-false}"
    jq -n --arg c "$cwd" --argjson s "$stop_active" \
        '{"hook_event_name":"Stop","cwd":$c,"stop_hook_active":$s}'
}

echo "=== stop-hook.sh integration tests ==="
echo ""

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------
# TEST: session_id included in log entries
# ---------------------------------------------------------------
echo "--- session_id in log ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
tmplog=$(mktemp -p "$TMPDIR_BASE")
payload=$(jq -n --arg c "$tmpdir" '{"hook_event_name":"Stop","cwd":$c,"stop_hook_active":false,"session_id":"test-sid-42"}')
run_hook "$payload" "$tmplog" >/dev/null 2>&1
if grep -q "session=test-sid-42" "$tmplog" 2>/dev/null; then pass "session_id: present in log"; else fail "session_id: missing from log"; fi

# ---------------------------------------------------------------
# TEST: malformed package.json → SKIP logged, no block
# ---------------------------------------------------------------
echo "--- npm: malformed package.json ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
printf 'THIS IS NOT JSON\n' > "$tmpdir/package.json"
tmplog=$(mktemp -p "$TMPDIR_BASE")
out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "malformed json: exit 0"; else fail "malformed json: expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "malformed json: no block output"; else fail "malformed json: unexpected output: $out"; fi
if grep -q "SKIP npm: package.json invalid" "$tmplog" 2>/dev/null; then pass "malformed json: SKIP logged"; else fail "malformed json: SKIP not in log"; fi

# ---------------------------------------------------------------
# TEST: timeout binary absent → tests run without timeout, no false block
# ---------------------------------------------------------------
echo "--- timeout binary absent ---"
if ! require_tool npm; then
    skip "npm not installed — skipping timeout-absent test"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/package.json" << 'EOF'
{"scripts":{"test":"exit 0"}}
EOF
    tmplog=$(mktemp -p "$TMPDIR_BASE")
    out=$(STOP_HOOK_LOG="$tmplog" PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '/usr/local/bin$\|/opt/homebrew/bin$' | tr '\n' ':' | sed 's/:$//')" bash "$HOOK" <<< "$(mk_payload "$tmpdir")" 2>/dev/null || true)
    # When timeout is available, tests should pass. Key check: exit 0, no block.
    if [ -z "$out" ]; then pass "timeout absent: no false block on passing tests"; else
        if echo "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
            fail "timeout absent: false block emitted: $out"
        else
            pass "timeout absent: no block decision"
        fi
    fi
fi

# ---------------------------------------------------------------
# TEST: stop_hook_active=true → exit 0, no block, SKIP in log
# ---------------------------------------------------------------
echo "--- escape hatch: stop_hook_active=true ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
tmplog=$(mktemp -p "$TMPDIR_BASE")
out=$(run_hook "$(mk_payload "$tmpdir" true)" "$tmplog" 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "escape: exit 0"; else fail "escape: expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "escape: no block output"; else fail "escape: unexpected output: $out"; fi
if grep -q "SKIP stop_hook_active" "$tmplog" 2>/dev/null; then pass "escape: log entry written"; else fail "escape: log entry missing"; fi

# ---------------------------------------------------------------
# TEST: no test runner in empty dir → exit 0, SKIP in log
# ---------------------------------------------------------------
echo "--- no test runner ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
tmplog=$(mktemp -p "$TMPDIR_BASE")
out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "no runner: exit 0"; else fail "no runner: expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "no runner: no block output"; else fail "no runner: unexpected output: $out"; fi
if grep -q "SKIP no test runner" "$tmplog" 2>/dev/null; then pass "no runner: log entry written"; else fail "no runner: log entry missing"; fi

# ---------------------------------------------------------------
# TEST: npm default stub ("no test specified") → exit 0, SKIP
# ---------------------------------------------------------------
echo "--- npm: default stub test script ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
printf '{"scripts":{"test":"echo \\\"Error: no test specified\\\" && exit 1"}}\n' > "$tmpdir/package.json"
tmplog=$(mktemp -p "$TMPDIR_BASE")
out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
rc=$?
if [ $rc -eq 0 ]; then pass "npm stub: exit 0"; else fail "npm stub: expected exit 0, got $rc"; fi
if [ -z "$out" ]; then pass "npm stub: no block output"; else fail "npm stub: unexpected output: $out"; fi
if grep -q "SKIP" "$tmplog" 2>/dev/null; then pass "npm stub: SKIP logged"; else fail "npm stub: SKIP not in log"; fi

# ---------------------------------------------------------------
# TEST: npm with passing tests → exit 0, no block
# ---------------------------------------------------------------
echo "--- npm: passing tests ---"
if ! require_tool npm; then
    skip "npm not installed — skipping npm pass test"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/package.json" << 'EOF'
{"scripts":{"test":"exit 0"}}
EOF
    tmplog=$(mktemp -p "$TMPDIR_BASE")
    out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "npm pass: exit 0"; else fail "npm pass: expected exit 0, got $rc"; fi
    if [ -z "$out" ]; then pass "npm pass: no block output"; else fail "npm pass: unexpected output: $out"; fi
    if grep -q "^.* OK npm" "$tmplog" 2>/dev/null; then pass "npm pass: OK logged"; else fail "npm pass: OK not in log"; fi
fi

# ---------------------------------------------------------------
# TEST: npm with failing tests → block output, exit 0
# ---------------------------------------------------------------
echo "--- npm: failing tests ---"
if ! require_tool npm; then
    skip "npm not installed — skipping npm fail test"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/package.json" << 'EOF'
{"scripts":{"test":"exit 1"}}
EOF
    tmplog=$(mktemp -p "$TMPDIR_BASE")
    out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "npm fail: exit 0"; else fail "npm fail: expected exit 0, got $rc"; fi
    if echo "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "npm fail: block decision present"
        reason=$(echo "$out" | jq -r '.reason')
        echo "    reason: $reason"
    else
        fail "npm fail: no block decision in output: $out"
    fi
    if grep -q "BLOCK" "$tmplog" 2>/dev/null; then pass "npm fail: BLOCK logged"; else fail "npm fail: BLOCK not in log"; fi
fi

# ---------------------------------------------------------------
# TEST: pytest no tests collected (exit 5) → exit 0, SKIP
# ---------------------------------------------------------------
echo "--- pytest: no tests collected ---"
if ! require_tool python3; then
    skip "python3 not installed — skipping pytest tests"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    touch "$tmpdir/pytest.ini"
    tmplog=$(mktemp -p "$TMPDIR_BASE")
    out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "pytest no tests: exit 0"; else fail "pytest no tests: expected exit 0, got $rc"; fi
    if [ -z "$out" ]; then pass "pytest no tests: no block output"; else fail "pytest no tests: unexpected output: $out"; fi
    if grep -q "SKIP pytest" "$tmplog" 2>/dev/null; then pass "pytest no tests: SKIP logged"; else fail "pytest no tests: SKIP not in log"; fi
fi

# ---------------------------------------------------------------
# TEST: pytest passing tests → exit 0, no block
# ---------------------------------------------------------------
echo "--- pytest: passing tests ---"
if ! require_tool python3; then
    skip "python3 not installed — skipping"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/pytest.ini" << 'EOF'
[pytest]
EOF
    cat > "$tmpdir/test_pass.py" << 'EOF'
def test_ok():
    assert True
EOF
    tmplog=$(mktemp -p "$TMPDIR_BASE")
    out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "pytest pass: exit 0"; else fail "pytest pass: expected exit 0, got $rc"; fi
    if [ -z "$out" ]; then pass "pytest pass: no block output"; else fail "pytest pass: unexpected output: $out"; fi
    if grep -q "OK pytest" "$tmplog" 2>/dev/null; then pass "pytest pass: OK logged"; else fail "pytest pass: OK not in log"; fi
fi

# ---------------------------------------------------------------
# TEST: pytest failing tests → block output, exit 0
# ---------------------------------------------------------------
echo "--- pytest: failing tests ---"
if ! require_tool python3; then
    skip "python3 not installed — skipping"
else
    tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
    cat > "$tmpdir/pytest.ini" << 'EOF'
[pytest]
EOF
    cat > "$tmpdir/test_fail.py" << 'EOF'
def test_fail():
    assert False
EOF
    tmplog=$(mktemp -p "$TMPDIR_BASE")
    out=$(run_hook "$(mk_payload "$tmpdir")" "$tmplog" 2>/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then pass "pytest fail: exit 0"; else fail "pytest fail: expected exit 0, got $rc"; fi
    if echo "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "pytest fail: block decision present"
        reason=$(echo "$out" | jq -r '.reason')
        echo "    reason: $reason"
    else
        fail "pytest fail: no block decision in output: $out"
    fi
    if grep -q "BLOCK" "$tmplog" 2>/dev/null; then pass "pytest fail: BLOCK logged"; else fail "pytest fail: BLOCK not in log"; fi
fi

# ---------------------------------------------------------------
# TEST: log file created if dir is missing
# ---------------------------------------------------------------
echo "--- log: created if dir missing ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
novel_log="$tmpdir/nested/subdir/stop.log"
STOP_HOOK_LOG="$novel_log" bash "$HOOK" <<< "$(mk_payload "$tmpdir")" >/dev/null 2>&1
if [ -f "$novel_log" ]; then pass "log: created if dir missing"; else fail "log: not created"; fi

# ---------------------------------------------------------------
# TEST: STATE.md created on SKIP (no runner), mechanical fields set
# ---------------------------------------------------------------
echo "--- handoff: STATE.md created on SKIP (no runner) ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
git -C "$tmpdir" init -q
git -C "$tmpdir" config user.email "test@example.com"
git -C "$tmpdir" config user.name "Test"
echo "init" > "$tmpdir/file.txt"
git -C "$tmpdir" add .
git -C "$tmpdir" commit -q -m "test: initial #1" 2>/dev/null
tmplog=$(mktemp -p "$TMPDIR_BASE")
run_hook "$(mk_payload "$tmpdir")" "$tmplog" >/dev/null 2>&1
state="$tmpdir/STATE.md"
if [ -f "$state" ]; then
    pass "handoff: STATE.md created on SKIP"
    if grep -qE '^session_id: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$state"; then
        pass "handoff: session_id is UTC ISO-8601 timestamp"
    else
        fail "handoff: session_id format wrong or missing: $(grep 'session_id' "$state" 2>/dev/null)"
    fi
    expected_sha=$(git -C "$tmpdir" rev-parse --short HEAD 2>/dev/null)
    if grep -q "last_commit_sha: $expected_sha" "$state"; then
        pass "handoff: last_commit_sha correct ($expected_sha)"
    else
        fail "handoff: last_commit_sha wrong (expected $expected_sha); got: $(grep 'last_commit_sha' "$state" 2>/dev/null)"
    fi
else
    fail "handoff: STATE.md not created on SKIP"
fi

# ---------------------------------------------------------------
# TEST: STATE.md idempotency — operator-asserted fields preserved, mechanical fields updated
# ---------------------------------------------------------------
echo "--- handoff: idempotency (operator fields preserved, mechanical updated) ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
git -C "$tmpdir" init -q
git -C "$tmpdir" config user.email "test@example.com"
git -C "$tmpdir" config user.name "Test"
echo "init" > "$tmpdir/file.txt"
git -C "$tmpdir" add .
git -C "$tmpdir" commit -q -m "test: first commit #1" 2>/dev/null
tmplog=$(mktemp -p "$TMPDIR_BASE")
# First hook run: creates STATE.md with TODO placeholders
run_hook "$(mk_payload "$tmpdir")" "$tmplog" >/dev/null 2>&1
state="$tmpdir/STATE.md"
sha1=$(git -C "$tmpdir" rev-parse --short HEAD 2>/dev/null)
if [ -f "$state" ]; then
    # Simulate operator filling in next_3_actions (replace first TODO)
    sed 's/  - TODO/  - Run \/qa/' "$state" > "${state}.tmp" && mv "${state}.tmp" "$state" 2>/dev/null || true
    # Advance the repo by one commit
    echo "change" >> "$tmpdir/file.txt"
    git -C "$tmpdir" add .
    git -C "$tmpdir" commit -q -m "test: second commit #1" 2>/dev/null
    sha2=$(git -C "$tmpdir" rev-parse --short HEAD 2>/dev/null)
    # Second hook run: mechanical fields should advance, operator field should survive
    run_hook "$(mk_payload "$tmpdir")" "$tmplog" >/dev/null 2>&1
    if grep -q "last_commit_sha: $sha2" "$state" && [ "$sha2" != "$sha1" ]; then
        pass "handoff idempotent: last_commit_sha advanced from $sha1 to $sha2"
    elif grep -q "last_commit_sha: $sha2" "$state"; then
        pass "handoff idempotent: last_commit_sha set to $sha2"
    else
        fail "handoff idempotent: last_commit_sha not updated (expected $sha2); got: $(grep 'last_commit_sha' "$state" 2>/dev/null)"
    fi
    if grep -q "Run /qa" "$state"; then
        pass "handoff idempotent: operator-asserted next_3_actions preserved"
    else
        fail "handoff idempotent: operator-asserted next_3_actions lost"
    fi
else
    fail "handoff idempotent: STATE.md missing after first run"
fi

# ---------------------------------------------------------------
# TEST: session-log entry created on SKIP (no runner)
# ---------------------------------------------------------------
echo "--- handoff: session-log entry appended on SKIP ---"
tmpdir=$(mktemp -d -p "$TMPDIR_BASE")
git -C "$tmpdir" init -q
git -C "$tmpdir" config user.email "test@example.com"
git -C "$tmpdir" config user.name "Test"
echo "init" > "$tmpdir/file.txt"
git -C "$tmpdir" add .
git -C "$tmpdir" commit -q -m "test: initial #1" 2>/dev/null
tmplog=$(mktemp -p "$TMPDIR_BASE")
run_hook "$(mk_payload "$tmpdir")" "$tmplog" >/dev/null 2>&1
today_path=$(date -u '+%Y/%m/%Y-%m-%d')
log_file="$tmpdir/session-log/${today_path}.md"
if [ -f "$log_file" ]; then
    pass "handoff: session-log file created ($log_file)"
    if grep -qE '^## Session [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$log_file"; then
        pass "handoff: session-log entry has ISO-8601 session header"
    else
        fail "handoff: session-log entry missing Session header"
    fi
else
    fail "handoff: session-log file not created (expected $log_file)"
fi

# ---------------------------------------------------------------
# INSTALLER TESTS: Stop hook jq patch (inline, no real ~/.claude/)
# ---------------------------------------------------------------
echo "--- installer: Stop hook jq patching ---"

STOP_PATH="$HOME/.claude/hooks/stop-hook.sh"

run_stop_patch() {
    local settings_in="$1"
    local cmd_path="$2"
    jq \
        --arg cmd "$cmd_path" \
        '
        .hooks = (.hooks // {})
        | .hooks.Stop = (.hooks.Stop // [])
        | (
            (.hooks.Stop | map(.hooks[]?.command) | flatten | any(. == $cmd)) as $already
            | if $already then .
              else .hooks.Stop += [{"hooks": [{"type": "command", "command": $cmd}]}]
              end
          )
        ' <<< "$settings_in"
}

# --- fresh settings → hook added ---
echo "--- installer: fresh settings, hook added ---"
base='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/existing.sh"}]}],"PostToolUse":[{"matcher":"Edit|MultiEdit|Write","hooks":[{"type":"command","command":"/ptu.sh"}]}]}}'
patched=$(run_stop_patch "$base" "$STOP_PATH")
count=$(echo "$patched" | jq --arg p "$STOP_PATH" '[.hooks.Stop[]? | .hooks[]? | select(.command == $p)] | length')
if [ "$count" = "1" ]; then pass "installer: Stop hook added once"; else fail "installer: expected 1 entry, got $count"; fi

# --- PreToolUse and PostToolUse unchanged after patch ---
pretooluse_before=$(echo "$base" | jq -cS '.hooks.PreToolUse // []')
pretooluse_after=$(echo "$patched" | jq -cS '.hooks.PreToolUse // []')
if [ "$pretooluse_before" = "$pretooluse_after" ]; then
    pass "installer: PreToolUse unchanged"
else
    fail "installer: PreToolUse was altered"
fi
ptu_before=$(echo "$base" | jq -cS '.hooks.PostToolUse // []')
ptu_after=$(echo "$patched" | jq -cS '.hooks.PostToolUse // []')
if [ "$ptu_before" = "$ptu_after" ]; then
    pass "installer: PostToolUse unchanged"
else
    fail "installer: PostToolUse was altered"
fi

# --- idempotency: second patch does not duplicate ---
echo "--- installer: idempotency ---"
patched2=$(run_stop_patch "$patched" "$STOP_PATH")
count2=$(echo "$patched2" | jq --arg p "$STOP_PATH" '[.hooks.Stop[]? | .hooks[]? | select(.command == $p)] | length')
if [ "$count2" = "1" ]; then pass "installer: idempotent (no duplicate)"; else fail "installer: expected 1 after second run, got $count2"; fi

# --- no matcher field on Stop entries ---
echo "--- installer: no matcher on Stop entries ---"
matcher=$(echo "$patched" | jq -r '.hooks.Stop[]? | .matcher // "absent"')
if [ "$matcher" = "absent" ]; then
    pass "installer: Stop entries have no matcher field"
else
    fail "installer: unexpected matcher: $matcher"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
