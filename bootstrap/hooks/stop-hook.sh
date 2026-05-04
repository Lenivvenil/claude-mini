#!/usr/bin/env bash
# stop-hook.sh — Claude Code Stop hook
#
# Runs at session end. Blocks close if the detected test suite is failing.
#
# Block protocol: stdout {"decision":"block","reason":"..."}, exit 0.
# Claude Code reads stdout; exit code does not control blocking for Stop hooks.
#
# Escape hatch: stop_hook_active=true in stdin JSON payload.
# Claude Code sets this flag when a Stop hook already blocked once, preventing
# infinite-block loops. Exit 0 immediately when this flag is true.
#
# Per-runner detection (first match wins):
#   npm    — package.json with scripts.test not equal to the default stub
#   pytest — pytest.ini, pyproject.toml, or setup.cfg present; collect-only validates
#
# Logs all events (SKIP, OK, BLOCK) to $STOP_HOOK_LOG
# (default: ~/.claude/hooks/stop.log). Override for tests.

set -uo pipefail

LOG_FILE="${STOP_HOOK_LOG:-$HOME/.claude/hooks/stop.log}"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
SESSION_ID="unknown"

log_entry() {
    if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
        echo "[stop-hook] log unavailable: $*" >&2
        return
    fi
    printf '%s session=%s %s\n' "$TIMESTAMP" "$SESSION_ID" "$*" >> "$LOG_FILE" || \
        echo "[stop-hook] log write failed: $*" >&2
}

emit_block() {
    jq -n --arg r "$1" '{"decision":"block","reason":$r}'
    log_entry "BLOCK runner=${runner:-?} $1"
}

# --- jq prerequisite ---
if ! command -v jq >/dev/null 2>&1; then
    log_entry "ERROR jq not found — hook disabled"
    exit 0
fi

# --- Probe for timeout binary (GNU coreutils; on macOS may be absent or gtimeout) ---
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
else
    log_entry "WARN timeout binary not found — running tests without time limit"
fi

run_timed() {
    local secs="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" "$secs" "$@"
    else
        "$@"
    fi
}

# --- Hand-off: session-log append + STATE.md mechanical-field update (ADR-0024) ---
# Called on OK and SKIP paths only (not on BLOCK — session is not ending cleanly).
# Log-first order: if interrupted between steps, log entry exists but STATE.md untouched;
# next run re-updates STATE.md. Reverse order loses log entry with no recovery path.
update_handoff() {
    local reason="${1:-ok}"

    # Mechanical values
    local new_sid new_date new_branch new_sha new_frid
    new_sid=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "unknown")
    new_date=$(date -u '+%Y-%m-%d' 2>/dev/null || echo "unknown")
    new_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    new_sha=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || echo "unknown")

    # Infer active_feature_run_id from trailing -NNN in branch name
    new_frid="null"
    if echo "$new_branch" | grep -qE '[-/]([0-9]+)$'; then
        new_frid="#$(echo "$new_branch" | grep -oE '[0-9]+$')"
    fi

    # Preserve non-null, non-TODO active_feature_run_id from existing STATE.md
    local state_file="$cwd/STATE.md"
    if [ -f "$state_file" ]; then
        local existing_frid
        existing_frid=$(grep -E '^active_feature_run_id:' "$state_file" 2>/dev/null | head -1 \
            | sed 's/^active_feature_run_id:[[:space:]]*//' | sed -E 's/[[:space:]]+#.*//' | tr -d '[:space:]')
        # Validate extracted format — only #NNN or null are valid refs; discard anything else
        if ! echo "$existing_frid" | grep -qE '^(#[0-9]+|null)$'; then existing_frid=""; fi
        if [ -n "$existing_frid" ] && [ "$existing_frid" != "null" ] && [ "$existing_frid" != "TODO" ]; then
            new_frid="$existing_frid"
        fi
    fi

    # Step 1: Append session-log entry (log-first per ADR-0024 sub-decision 4)
    local log_dir log_file
    log_dir="$cwd/session-log/$(date -u '+%Y/%m')"
    log_file="$log_dir/$(date -u '+%Y-%m-%d').md"
    if mkdir -p "$log_dir" 2>/dev/null; then
        if printf '\n## Session %s\n\n- branch: %s\n- commit: %s\n- runner: %s (%s)\n- active_feature_run_id: %s\n- event: session-end\n' \
            "$new_sid" "$new_branch" "$new_sha" "${runner:-none}" "$reason" "$new_frid" >> "$log_file" 2>/dev/null; then
            log_entry "OK session-log appended: $log_file"
        else
            log_entry "WARN session-log write failed: $log_file"
        fi
    else
        log_entry "WARN session-log dir unavailable: $log_dir"
    fi

    # Step 2: Update mechanical fields in STATE.md
    if [ -f "$state_file" ]; then
        # sed in-place via temp file (macOS sed -i requires backup suffix — avoid portability issue)
        local tmp
        tmp=$(mktemp)
        if sed \
            -e "s|^session_id:.*|session_id: $new_sid|" \
            -e "s|^date_iso:.*|date_iso: $new_date|" \
            -e "s|^current_branch:.*|current_branch: $new_branch|" \
            -e "s|^last_commit_sha:.*|last_commit_sha: $new_sha|" \
            -e "s|^active_feature_run_id:.*|active_feature_run_id: $new_frid|" \
            "$state_file" > "$tmp" && mv "$tmp" "$state_file"; then
            log_entry "OK STATE.md updated: session_id=$new_sid branch=$new_branch sha=$new_sha"
        else
            log_entry "WARN STATE.md update failed"
        fi
    else
        # Create minimal STATE.md from scratch
        cat > "$state_file" <<STEOF
# STATE.md — session continuity snapshot
<!-- Principle 9 hand-off artifact. Replaced (not appended) on each session end. -->
<!-- Five-minute cold-start: read this + latest session-log entry, start in 5 min. (ADR-0024) -->

session_id: $new_sid
date_iso: $new_date
current_branch: $new_branch
last_commit_sha: $new_sha
active_feature_run_id: $new_frid

next_3_actions:
  - TODO
  - TODO
  - TODO

blocked_on: null

open_questions: []

risk_flags: []
STEOF
        log_entry "OK STATE.md created: session_id=$new_sid branch=$new_branch sha=$new_sha"
    fi

    # Step 3: Warn if operator-asserted fields still contain TODO-placeholders
    local todo_count
    todo_count=$(grep -c 'TODO' "$state_file" 2>/dev/null || echo "0")
    if [ "$todo_count" -gt 0 ]; then
        log_entry "WARN STATE.md has ${todo_count} TODO placeholder(s) in operator-asserted fields — Human Resume Test may fail"
    fi
}

# --- Parse stdin payload ---
input=$(cat)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")

# --- Escape hatch: Claude Code sets stop_hook_active=true to prevent infinite loops ---
if [ "$stop_hook_active" = "true" ]; then
    log_entry "SKIP stop_hook_active=true"
    update_handoff "skip-escape-hatch"
    exit 0
fi

# --- Resolve working directory ---
[ -z "$cwd" ] && cwd="$PWD"

# --- Detect test runner ---
runner=""
test_cmd=""

# npm: package.json with a non-default scripts.test
if [ -f "$cwd/package.json" ] && command -v jq >/dev/null 2>&1; then
    test_script=""
    jq_rc=0
    test_script=$(jq -r '.scripts.test // empty' "$cwd/package.json" 2>/dev/null) || jq_rc=$?
    if [ "$jq_rc" -ne 0 ]; then
        log_entry "SKIP npm: package.json invalid or unreadable"
    elif [ -n "$test_script" ] && ! echo "$test_script" | grep -qF "no test specified"; then
        runner="npm"
        test_cmd="npm test --silent"
    fi
fi

# pytest: presence of any standard config marker
if [ -z "$runner" ] && command -v python3 >/dev/null 2>&1; then
    pytest_marker=0
    [ -f "$cwd/pytest.ini" ] && pytest_marker=1
    [ -f "$cwd/pyproject.toml" ] && pytest_marker=1
    [ -f "$cwd/setup.cfg" ] && pytest_marker=1
    if [ "$pytest_marker" = "1" ]; then
        collect_rc=0
        run_timed 30 python3 -m pytest --collect-only -q --no-header "$cwd" >/dev/null 2>&1 || collect_rc=$?
        case "$collect_rc" in
            0)  runner="pytest"; test_cmd="python3 -m pytest --quiet" ;;
            5)  log_entry "SKIP pytest: no tests collected (exit 5)"; exit 0 ;;
            *)  log_entry "SKIP pytest: collect-only failed (exit $collect_rc)"; exit 0 ;;
        esac
    fi
fi

if [ -z "$runner" ]; then
    log_entry "SKIP no test runner detected in $cwd"
    update_handoff "skip-no-runner"
    exit 0
fi

# --- Run tests with 300s timeout ---
if ! cd "$cwd" 2>/dev/null; then
    log_entry "ERROR could not cd to $cwd"
    exit 0
fi

test_rc=0
run_timed 300 bash -c "$test_cmd" >/dev/null 2>&1
test_rc=$?

case "$test_rc" in
    0)
        log_entry "OK $runner tests passed in $cwd"
        update_handoff "ok"
        ;;
    124)
        emit_block "$runner test suite exceeded 300s in $cwd — fix hang or use stop_hook_active escape"
        ;;
    *)
        emit_block "Tests failing in $cwd ($runner exit $test_rc) — fix before ending session"
        ;;
esac

exit 0
