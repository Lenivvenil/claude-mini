#!/usr/bin/env bash
# test-notify.sh — smoke tests for bootstrap/scripts/notify.sh
#
# Usage:
#   bash bootstrap/tests/verify/test-notify.sh
#   bash bootstrap/tests/verify/test-notify.sh /path/to/notify.sh
#
# Exit codes: 0 = all tests passed, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY="${1:-$SCRIPT_DIR/../../scripts/notify.sh}"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

pass() { printf "  ${GREEN}PASS${NC} %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC} %s\n" "$1"; FAILURES=$((FAILURES+1)); }

FAILURES=0

if [ ! -f "$NOTIFY" ]; then
    printf "${RED}FATAL:${NC} notify.sh not found at %s\n" "$NOTIFY" >&2
    exit 1
fi

echo "=== notify.sh smoke-test ==="
echo "Script: $NOTIFY"
echo ""

# ── Helper ────────────────────────────────────────────────────────────────────
# make_fake_bin <name> <log-path>
# Creates a temporary directory with a fake binary that records $* to log-path.
# Prints the directory path.
make_fake_bin() {
    local name="$1"
    local log_path="$2"
    local fake_dir
    fake_dir=$(mktemp -d)
    printf '#!/bin/sh\nprintf '"'"'%%s\\n'"'"' "$*" >> "%s"\nexit 0\n' \
        "$log_path" > "$fake_dir/$name"
    chmod +x "$fake_dir/$name"
    printf '%s' "$fake_dir"
}

# ── Test 1: info severity, no NTFY_TOPIC → osascript called, curl not called ─

test_1() {
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    local osa_log="$tmpdir/osascript.log"
    local curl_log="$tmpdir/curl.log"
    local osa_dir curl_dir
    osa_dir=$(make_fake_bin "osascript" "$osa_log")
    curl_dir=$(make_fake_bin "curl" "$curl_log")
    trap 'rm -rf "$tmpdir" "$osa_dir" "$curl_dir"' RETURN

    local exit_code=0
    PATH="$osa_dir:$curl_dir:$PATH" NTFY_TOPIC="" \
        bash "$NOTIFY" info "hello world" "https://example.com" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "1: info without NTFY_TOPIC → exit 0"
    else
        fail "1: expected exit 0, got $exit_code"
    fi

    if [ -f "$osa_log" ]; then
        pass "1: osascript was invoked"
    else
        fail "1: osascript was NOT invoked"
    fi

    if [ ! -f "$curl_log" ]; then
        pass "1: curl NOT invoked (NTFY_TOPIC empty)"
    else
        fail "1: curl invoked unexpectedly"
    fi
}

# ── Test 2: warn + NTFY_TOPIC set → both transports called ───────────────────

test_2() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local osa_log="$tmpdir/osascript.log"
    local curl_log="$tmpdir/curl.log"
    local osa_dir curl_dir
    osa_dir=$(make_fake_bin "osascript" "$osa_log")
    curl_dir=$(make_fake_bin "curl" "$curl_log")
    trap 'rm -rf "$tmpdir" "$osa_dir" "$curl_dir"' RETURN

    local exit_code=0
    PATH="$osa_dir:$curl_dir:$PATH" NTFY_TOPIC="test-topic" \
        bash "$NOTIFY" warn "alert" "https://example.com" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "2: warn with NTFY_TOPIC → exit 0"
    else
        fail "2: expected exit 0, got $exit_code"
    fi

    if [ -f "$osa_log" ]; then
        pass "2: osascript invoked"
    else
        fail "2: osascript NOT invoked"
    fi

    if [ -f "$curl_log" ]; then
        pass "2: curl invoked (ntfy transport)"
    else
        fail "2: curl NOT invoked despite NTFY_TOPIC being set"
    fi

    if grep -q "ntfy.sh/test-topic" "$curl_log" 2>/dev/null; then
        pass "2: curl targeted correct ntfy.sh topic"
    else
        fail "2: curl did not target ntfy.sh/test-topic (log: $(cat "$curl_log" 2>/dev/null || echo empty))"
    fi
}

# ── Test 3: no transports available → exit 0 + stderr WARNING ────────────────

test_3() {
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # Use absolute bash path so PATH="$tmpdir" (hiding osascript/curl) doesn't
    # prevent bash itself from being found.
    local bash_bin
    bash_bin="$(command -v bash)"

    local stderr_out exit_code=0
    stderr_out=$(PATH="$tmpdir" NTFY_TOPIC="" \
        "$bash_bin" "$NOTIFY" critical "disaster" "https://example.com" 2>&1) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "3: no transports → exit 0"
    else
        fail "3: expected exit 0, got $exit_code"
    fi

    if printf '%s' "$stderr_out" | grep -q "WARNING"; then
        pass "3: stderr contains WARNING"
    else
        fail "3: stderr missing WARNING (got: $stderr_out)"
    fi
}

# ── Test 4: bad severity → exit 1 + stderr mentions severity ─────────────────

test_4() {
    local stderr_out exit_code=0
    stderr_out=$(bash "$NOTIFY" bad "title" "https://example.com" 2>&1) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "4: bad severity → exit 1"
    else
        fail "4: expected exit 1, got $exit_code"
    fi

    if printf '%s' "$stderr_out" | grep -q "bad"; then
        pass "4: stderr mentions the bad severity value"
    else
        fail "4: stderr does not mention 'bad' (got: $stderr_out)"
    fi
}

# ── Test 5: wrong arg count → exit 1 ─────────────────────────────────────────

test_5() {
    local exit_code=0
    bash "$NOTIFY" info "only-two-args" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "5: wrong arg count → exit 1"
    else
        fail "5: expected exit 1, got $exit_code"
    fi
}

# ── Test 6: invalid NTFY_TOPIC → ntfy skipped, exit 0 ───────────────────────

test_6() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local curl_log="$tmpdir/curl.log"
    local osa_log="$tmpdir/osa.log"
    local curl_dir osa_dir
    curl_dir=$(make_fake_bin "curl" "$curl_log")
    osa_dir=$(make_fake_bin "osascript" "$osa_log")
    trap 'rm -rf "$tmpdir" "$curl_dir" "$osa_dir"' RETURN

    local stderr_out exit_code=0
    stderr_out=$(PATH="$osa_dir:$curl_dir:$PATH" NTFY_TOPIC="bad topic!" \
        bash "$NOTIFY" info "test" "https://example.com" 2>&1) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "6: invalid NTFY_TOPIC → exit 0"
    else
        fail "6: expected exit 0, got $exit_code"
    fi

    if [ ! -f "$curl_log" ]; then
        pass "6: curl NOT invoked (invalid NTFY_TOPIC)"
    else
        fail "6: curl invoked despite invalid NTFY_TOPIC"
    fi

    if printf '%s' "$stderr_out" | grep -q "WARNING"; then
        pass "6: stderr contains WARNING about invalid topic"
    else
        fail "6: stderr missing WARNING (got: $stderr_out)"
    fi
}

# ── Test 7: @-prefix in title must NOT cause curl to read a file ─────────────
# Regression for security finding: curl -d "@/path" reads file from disk.
# --data-raw must be used instead of -d so "@..." is treated as literal text.

test_7() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local curl_log="$tmpdir/curl.log"
    local osa_log="$tmpdir/osa.log"
    local curl_dir osa_dir
    curl_dir=$(make_fake_bin "curl" "$curl_log")
    osa_dir=$(make_fake_bin "osascript" "$osa_log")
    trap 'rm -rf "$tmpdir" "$curl_dir" "$osa_dir"' RETURN

    local exit_code=0
    PATH="$osa_dir:$curl_dir:$PATH" NTFY_TOPIC="test-topic" \
        bash "$NOTIFY" warn "@/etc/passwd" "https://example.com" >/dev/null 2>&1 \
        || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "7: @-prefix title → exit 0"
    else
        fail "7: expected exit 0, got $exit_code"
    fi

    if [ -f "$curl_log" ]; then
        if grep -q "\-\-data-raw" "$curl_log" 2>/dev/null || \
           ! grep -q "/etc/passwd" "$curl_log" 2>/dev/null; then
            pass "7: curl log does not contain file path (data-raw used)"
        else
            fail "7: curl log contains /etc/passwd — @-prefix was NOT neutralised"
        fi
    else
        fail "7: curl was not invoked (NTFY_TOPIC was set — expected curl call)"
    fi
}

# ── Test 8: newline in url collapses to empty (not space) ───────────────────
# Regression for asymmetric sanitisation: title \n → space, url \n → empty.
# Spaces in URLs break the Click: header sent to ntfy.sh.

test_8() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local curl_log="$tmpdir/curl.log"
    local osa_log="$tmpdir/osa.log"
    local curl_dir osa_dir
    curl_dir=$(make_fake_bin "curl" "$curl_log")
    osa_dir=$(make_fake_bin "osascript" "$osa_log")
    trap 'rm -rf "$tmpdir" "$curl_dir" "$osa_dir"' RETURN

    local exit_code=0
    # Pass a URL with an embedded newline
    PATH="$osa_dir:$curl_dir:$PATH" NTFY_TOPIC="test-topic" \
        bash "$NOTIFY" info "title" $'https://example.com\ninjected' \
        >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "8: newline in url → exit 0"
    else
        fail "8: expected exit 0, got $exit_code"
    fi

    if [ -f "$curl_log" ]; then
        # If the newline was preserved in url, the Click: header value splits across
        # lines in the curl args, producing >1 line in the log. After stripping, the
        # args fit on a single line.
        local line_count
        line_count=$(wc -l < "$curl_log")
        if [ "$line_count" -le 1 ]; then
            pass "8: curl args are single-line (newline stripped from url)"
        else
            fail "8: curl log has $line_count lines — newline NOT stripped from url (header injection risk)"
        fi
    else
        fail "8: curl not invoked (NTFY_TOPIC set — expected curl call)"
    fi
}

# ── Run all tests ─────────────────────────────────────────────────────────────

test_1
test_2
test_3
test_4
test_5
test_6
test_7
test_8

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [ "$FAILURES" -eq 0 ]; then
    printf '%bAll tests passed.%b\n' "$GREEN" "$NC"
    exit 0
else
    printf '%b%d test(s) failed.%b\n' "$RED" "$FAILURES" "$NC"
    exit 1
fi
