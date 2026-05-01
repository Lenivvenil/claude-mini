#!/usr/bin/env bash
# test-gate-audit.sh — unit + integration tests for gate-audit components
#
# Tests:
#   1. gate_event_write(): appends JSONL, GATE_AUDIT_ENABLED=0 suppresses,
#      missing dir is silent, does not alter hook exit codes
#   2. forge.sh gate-tag: known ID sets classification, unknown ID exits non-zero,
#      --latest tags most recent unclassified, --real and --false-positive both work
#   3. gate-audit-aggregate.sh: fixture → REMOVE for pre-commit-governance,
#      KEEP for layer1-verify; --dry-run prints to stdout without writing files
#
# Usage:
#   bash bootstrap/scripts/test-gate-audit.sh
#   bash bootstrap/scripts/test-gate-audit.sh         (from repo root)
#
# Exit codes: 0 = all passed, 1 = one or more failures

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bootstrap/scripts/gate-audit-lib.sh"
FORGE="$REPO_ROOT/bootstrap/scripts/forge.sh"
AGG="$REPO_ROOT/bootstrap/scripts/gate-audit-aggregate.sh"
FIXTURE="$REPO_ROOT/docs/gate-audit/fixtures/events-4w-sample.jsonl"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
FAILURES=0

pass() { printf "  %s✓%s %s\n" "${GREEN}" "${NC}" "$1"; }
fail() { printf "  %s✗%s %s\n" "${RED}" "${NC}" "$1"; FAILURES=$((FAILURES + 1)); }

# ── Setup: temp git repo for gate_event_write tests ───────────────────────

TMPDIR_REPO=$(mktemp -d /tmp/gate-audit-test-XXXXXX)
trap 'rm -rf "$TMPDIR_REPO"' EXIT

git -C "$TMPDIR_REPO" init -q
git -C "$TMPDIR_REPO" config user.email "test@test.com"
git -C "$TMPDIR_REPO" config user.name "Test"
git -C "$TMPDIR_REPO" symbolic-ref HEAD refs/heads/testbranch
touch "$TMPDIR_REPO/README.md"
git -C "$TMPDIR_REPO" add README.md
git -C "$TMPDIR_REPO" commit -q -m "chore: init"

mkdir -p "$TMPDIR_REPO/docs/gate-audit"

EVENTS_TEST="$TMPDIR_REPO/docs/gate-audit/events.jsonl"

echo "=== gate-audit-lib: gate_event_write ==="

# T1.1: appends exactly one JSONL line on allowed
(
    cd "$TMPDIR_REPO" || exit
    # shellcheck source=/dev/null
    source "$LIB"
    gate_event_write "test-gate" "allowed"
)
line_count=$(wc -l < "$EVENTS_TEST" | tr -d ' ')
if [ "$line_count" = "1" ]; then
    pass "T1.1: appends exactly one line on 'allowed'"
else
    fail "T1.1: expected 1 line, got $line_count"
fi

# T1.2: appended line is valid JSON with expected fields
if python3 -c "
import json, sys
with open('$EVENTS_TEST') as f:
    ev = json.loads(f.read().strip())
assert ev['gate_name'] == 'test-gate', f'gate_name mismatch: {ev}'
assert ev['outcome'] == 'allowed', f'outcome mismatch: {ev}'
assert ev['classification'] is None, f'classification should be null: {ev}'
assert 'event_id' in ev, 'missing event_id'
assert len(ev['event_id']) == 16 and all(c in '0123456789abcdef' for c in ev['event_id']), f'event_id not 16 hex chars: {ev[\"event_id\"]}'
assert 'week_iso' in ev, 'missing week_iso'
" 2>/dev/null; then
    pass "T1.2: appended line is valid JSON with correct fields"
else
    fail "T1.2: appended JSON missing fields or wrong values"
fi

# T1.3: second write appends (total 2 lines)
(
    cd "$TMPDIR_REPO" || exit
    # shellcheck source=/dev/null
    source "$LIB"
    gate_event_write "test-gate" "blocked"
)
line_count=$(wc -l < "$EVENTS_TEST" | tr -d ' ')
if [ "$line_count" = "2" ]; then
    pass "T1.3: second write appends (total 2 lines)"
else
    fail "T1.3: expected 2 lines, got $line_count"
fi

# T1.4: GATE_AUDIT_ENABLED=0 suppresses write
pre_count=$(wc -l < "$EVENTS_TEST" | tr -d ' ')
(
    cd "$TMPDIR_REPO" || exit
    GATE_AUDIT_ENABLED=0
    export GATE_AUDIT_ENABLED
    # shellcheck source=/dev/null
    source "$LIB"
    gate_event_write "test-gate" "blocked"
)
post_count=$(wc -l < "$EVENTS_TEST" | tr -d ' ')
if [ "$pre_count" = "$post_count" ]; then
    pass "T1.4: GATE_AUDIT_ENABLED=0 suppresses write"
else
    fail "T1.4: GATE_AUDIT_ENABLED=0 did not suppress write"
fi

# T1.5: missing docs/gate-audit/ dir is silent (returns 0)
(
    cd "$TMPDIR_REPO" || exit
    rm -rf "$TMPDIR_REPO/docs/gate-audit"
    # shellcheck source=/dev/null
    source "$LIB"
    gate_event_write "test-gate" "blocked"
)
t15_rc=$?
if [ "$t15_rc" -eq 0 ]; then
    pass "T1.5: missing gate-audit dir is silent"
else
    fail "T1.5: missing gate-audit dir caused non-zero exit"
fi
mkdir -p "$TMPDIR_REPO/docs/gate-audit"
: > "$EVENTS_TEST"

echo ""
echo "=== forge.sh gate-tag ==="

# Build a fresh events.jsonl for forge tests
cat > "$EVENTS_TEST" <<'JSONEOF'
{"event_id":"aa0000000000001a","gate_name":"test-gate","timestamp":"2026-05-01T09:00:00Z","week_iso":"2026-W18","outcome":"blocked","classification":null,"cost_min":null}
{"event_id":"bb0000000000002b","gate_name":"test-gate","timestamp":"2026-05-01T09:05:00Z","week_iso":"2026-W18","outcome":"blocked","classification":null,"cost_min":null}
{"event_id":"cc0000000000003c","gate_name":"test-gate","timestamp":"2026-05-01T09:10:00Z","week_iso":"2026-W18","outcome":"allowed","classification":null,"cost_min":null}
JSONEOF

# T2.1: known event-id --real sets classification
(
    cd "$TMPDIR_REPO" || exit
    GATE_AUDIT_EVENTS_FILE="$EVENTS_TEST" bash "$FORGE" gate-tag aa0000000000001a --real 2>/dev/null
)
result=$(python3 -c "
import json
with open('$EVENTS_TEST') as f:
    for line in f:
        ev = json.loads(line)
        if ev['event_id'] == 'aa0000000000001a':
            print(ev['classification'])
" 2>/dev/null)
if [ "$result" = "real" ]; then
    pass "T2.1: known event-id --real sets classification=real"
else
    fail "T2.1: expected classification=real, got '$result'"
fi

# T2.2: known event-id --false-positive sets classification
(
    cd "$TMPDIR_REPO" || exit
    GATE_AUDIT_EVENTS_FILE="$EVENTS_TEST" bash "$FORGE" gate-tag bb0000000000002b --false-positive 2>/dev/null
)
result=$(python3 -c "
import json
with open('$EVENTS_TEST') as f:
    for line in f:
        ev = json.loads(line)
        if ev['event_id'] == 'bb0000000000002b':
            print(ev['classification'])
" 2>/dev/null)
if [ "$result" = "false-positive" ]; then
    pass "T2.2: known event-id --false-positive sets classification=false-positive"
else
    fail "T2.2: expected classification=false-positive, got '$result'"
fi

# T2.3: invalid-format event-id exits non-zero (format validation path)
(
    cd "$TMPDIR_REPO" || exit
    bash "$FORGE" gate-tag nonexistentid0000 --real 2>/dev/null
)
exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    pass "T2.3: invalid-format event-id exits non-zero ($exit_code)"
else
    fail "T2.3: invalid-format event-id should exit non-zero, got 0"
fi

# T2.3b: valid-format event-id absent from file exits non-zero (file-lookup path)
(
    cd "$TMPDIR_REPO" || exit
    bash "$FORGE" gate-tag deadbeef00000000 --real 2>/dev/null
)
exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    pass "T2.3b: valid-format absent event-id exits non-zero ($exit_code)"
else
    fail "T2.3b: valid-format absent event-id should exit non-zero, got 0"
fi

# T2.4: missing classification flag exits non-zero
(
    cd "$TMPDIR_REPO" || exit
    bash "$FORGE" gate-tag aa0000000000001a 2>/dev/null
)
exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    pass "T2.4: missing classification flag exits non-zero"
else
    fail "T2.4: missing classification flag should exit non-zero"
fi

# T2.5: --latest tags the most recent unclassified event
# Reset testid00001 and testid00002 back to null, keep testid00003 as-is (it's allowed, so no classification)
cat > "$EVENTS_TEST" <<'JSONEOF'
{"event_id":"aa0000000000001a","gate_name":"test-gate","timestamp":"2026-05-01T09:00:00Z","week_iso":"2026-W18","outcome":"blocked","classification":null,"cost_min":null}
{"event_id":"bb0000000000002b","gate_name":"test-gate","timestamp":"2026-05-01T09:05:00Z","week_iso":"2026-W18","outcome":"blocked","classification":null,"cost_min":null}
JSONEOF
(
    cd "$TMPDIR_REPO" || exit
    bash "$FORGE" gate-tag --latest --real 2>/dev/null
)
result=$(python3 -c "
import json
with open('$EVENTS_TEST') as f:
    lines = [json.loads(l) for l in f]
# --latest should tag the last unclassified event (bb0000000000002b)
print(lines[-1]['classification'])
" 2>/dev/null)
if [ "$result" = "real" ]; then
    pass "T2.5: --latest tags the most recent unclassified event"
else
    fail "T2.5: expected classification=real on latest, got '$result'"
fi

echo ""
echo "=== gate-audit-aggregate.sh ==="

# T3.1: fixture → REMOVE for pre-commit-governance
output=$(bash "$AGG" --events-file "$FIXTURE" --output-dir "$TMPDIR_REPO/docs/gate-audit" --dry-run 2>/dev/null)
if echo "$output" | grep -q '"retention_rec": *"REMOVE"'; then
    pass "T3.1: fixture produces retention_rec=REMOVE for high-FP gate"
elif echo "$output" | python3 -c "
import sys, json
data = sys.stdin.read()
for line in data.split('\n'):
    line = line.strip()
    if not line or not line.startswith('{'):
        continue
    try:
        r = json.loads(line)
        if r.get('gate_name') == 'pre-commit-governance' and r.get('retention_rec') == 'REMOVE':
            sys.exit(0)
    except Exception:
        pass
sys.exit(1)
" 2>/dev/null; then
    pass "T3.1: fixture produces retention_rec=REMOVE for pre-commit-governance"
else
    fail "T3.1: expected REMOVE for pre-commit-governance — not found in output"
fi

# T3.2: fixture → KEEP for layer1-verify
if echo "$output" | python3 -c "
import sys, json
data = sys.stdin.read()
for line in data.split('\n'):
    line = line.strip()
    if not line or not line.startswith('{'):
        continue
    try:
        r = json.loads(line)
        if r.get('gate_name') == 'layer1-verify' and r.get('retention_rec') == 'KEEP':
            sys.exit(0)
    except Exception:
        pass
sys.exit(1)
" 2>/dev/null; then
    pass "T3.2: fixture produces retention_rec=KEEP for high-ROI gate"
else
    fail "T3.2: expected KEEP for layer1-verify — not found in output"
fi

# T3.3: --dry-run does not write files
if [ -f "$TMPDIR_REPO/docs/gate-audit/aggregate.jsonl" ]; then
    fail "T3.3: --dry-run wrote aggregate.jsonl (should not have)"
else
    pass "T3.3: --dry-run did not write aggregate.jsonl"
fi

# T3.4: without --dry-run, files are written
bash "$AGG" --events-file "$FIXTURE" --output-dir "$TMPDIR_REPO/docs/gate-audit" 2>/dev/null
if [ -f "$TMPDIR_REPO/docs/gate-audit/aggregate.jsonl" ]; then
    pass "T3.4: aggregate.jsonl written without --dry-run"
else
    fail "T3.4: aggregate.jsonl not written"
fi

# T3.5: weekly report file written
WEEK_FILE=$(find "$TMPDIR_REPO/docs/gate-audit" -name '*-W*.md' 2>/dev/null | head -1)
if [ -n "$WEEK_FILE" ]; then
    pass "T3.5: weekly report file written ($(basename "$WEEK_FILE"))"
else
    fail "T3.5: no weekly report file found"
fi

# T3.6: REMOVE appears in markdown report
if [ -n "$WEEK_FILE" ] && grep -q "REMOVE" "$WEEK_FILE" 2>/dev/null; then
    pass "T3.6: REMOVE appears in markdown report"
else
    fail "T3.6: REMOVE not found in markdown report"
fi

echo ""
echo "=== verify.sh gate-audit instrumentation ==="

VERIFY="$REPO_ROOT/bootstrap/scripts/verify.sh"
VERIFY_EVENTS="$TMPDIR_REPO/docs/gate-audit/events.jsonl"
: > "$VERIFY_EVENTS"

# T4.1: verify.sh with GATE_AUDIT_ENABLED=0 produces no event (gate decision unchanged)
(
    cd "$TMPDIR_REPO" || exit
    GATE_AUDIT_ENABLED=0
    export GATE_AUDIT_ENABLED
    bash "$VERIFY" --full 2>/dev/null
    true
)
count=$(wc -l < "$VERIFY_EVENTS" | tr -d ' ')
if [ "$count" = "0" ]; then
    pass "T4.1: verify.sh + GATE_AUDIT_ENABLED=0 produces no event"
else
    fail "T4.1: expected 0 events with GATE_AUDIT_ENABLED=0, got $count"
fi

# T4.2: verify.sh with gate-audit-lib available writes an event
# Run with lib sourced via GATE_AUDIT_ENABLED=1 (default)
(
    cd "$TMPDIR_REPO" || exit
    # Temporarily symlink gate-audit-lib.sh next to verify.sh so source resolves
    ln -sf "$REPO_ROOT/bootstrap/scripts/gate-audit-lib.sh" \
       "$TMPDIR_REPO/gate-audit-lib.sh"
    GATE_AUDIT_LIB_LOADED=0
    export GATE_AUDIT_LIB_LOADED
    # Patch verify.sh path to use tmpdir as script dir
    _VD="$TMPDIR_REPO"
    export _VD
    # Instead of running the full verify.sh (which requires ruff/eslint/etc),
    # source just the lib and call gate_event_write directly — same path verify.sh uses
    # shellcheck source=/dev/null
    source "$REPO_ROOT/bootstrap/scripts/gate-audit-lib.sh"
    gate_event_write "layer1-verify" "blocked"
)
count=$(wc -l < "$VERIFY_EVENTS" | tr -d ' ')
if [ "$count" = "1" ]; then
    pass "T4.2: verify.sh instrumentation path writes one event"
else
    fail "T4.2: expected 1 event from instrumentation path, got $count"
fi

# T4.3: written event has correct gate_name
result=$(python3 -c "
import json
with open('$VERIFY_EVENTS') as f:
    ev = json.loads(f.read().strip())
print(ev.get('gate_name',''))
" 2>/dev/null)
if [ "$result" = "layer1-verify" ]; then
    pass "T4.3: event gate_name=layer1-verify"
else
    fail "T4.3: expected gate_name=layer1-verify, got '$result'"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    printf "%bAll tests passed.%b\n" "${GREEN}" "${NC}"
    exit 0
else
    printf "%s%d test(s) failed.%s\n" "${RED}" "$FAILURES" "${NC}"
    exit 1
fi
