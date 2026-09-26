#!/usr/bin/env bash
# sprint.sh — sprint orchestrator (ADR-0030, design doc docs/architecture/sprint-orchestrator.md)
#
# Usage:
#   sprint.sh [--sprint-label <label>] [--budget <tokens>] [--dry-run] [--resume] [--ticket <N>]
#
# Runs claude -p "/feature <N>" per-ticket, verifies outcome via gh, escalates on failures.
# Source of truth: GitHub. .sprint-state is a restart-recovery cache only.

set -uo pipefail
# Note: -e deliberately omitted — gh calls capture exit codes explicitly (see escalate/T1 pattern).

# ── Constants ─────────────────────────────────────────────────────────────────

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
GH_BIN="${GH_BIN:-gh}"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
BUDGET_SPIKE_THRESHOLD="${BUDGET_SPIKE_THRESHOLD:-600000}"
CONSECUTIVE_FAILURE_THRESHOLD="${CONSECUTIVE_FAILURE_THRESHOLD:-3}"
MAX_TURNS="${MAX_TURNS:-200}"
NOTIFY_SH="$(cd "$(dirname "$0")" && pwd)/notify.sh"

SPRINT_LABEL="Sprint"
BUDGET=""
DRY_RUN=0
RESUME=0
SINGLE_TICKET=""

# ── Helpers ───────────────────────────────────────────────────────────────────

# Ensure needs-human label exists (idempotent).
ensure_label() {
    "$GH_BIN" label create "needs-human" \
        --color "d73a4a" \
        --description "Requires human review" \
        2>/dev/null || true
}

# push_notify <severity> <title> <url>
push_notify() {
    local severity="$1" title="$2" url="${3:-https://github.com}"
    if [ -x "$NOTIFY_SH" ]; then
        "$NOTIFY_SH" "$severity" "$title" "$url" 2>/dev/null || true
    fi
}

state_set() {
    local ticket_number="$1"
    local new_state="$2"
    local reason="$3"
    local tokens="${4:-0}"
    local state_file="${REPO_ROOT}/.sprint-state"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [ ! -f "$state_file" ]; then
        printf '{"sweep_id":"%s","label":"%s","started_at":"%s","last_updated":"%s","tickets":{},"summary":{"total":0,"merged":0,"escalated":0,"failed":0}}\n' \
            "${SWEEP_ID:-$now}" "$SPRINT_LABEL" "${SWEEP_STARTED_AT:-$now}" "$now" > "$state_file"
    fi

    local updated
    updated=$(jq \
        --arg n "$ticket_number" \
        --arg s "$new_state" \
        --arg r "$reason" \
        --arg t "$tokens" \
        --arg ts "$now" \
        '.last_updated = $ts | .tickets[$n] = ((.tickets[$n] // {}) + {state: $s, reason: $r, tokens_used: ($t | tonumber), updated_at: $ts})' \
        "$state_file")
    printf '%s\n' "$updated" > "$state_file"
}

state_update_summary() {
    local state_file="${REPO_ROOT}/.sprint-state"
    [ -f "$state_file" ] || return 0
    local updated
    updated=$(jq '
        .summary = {
            total:     (.tickets | length),
            merged:    ([.tickets[] | select(.state == "merged")] | length),
            escalated: ([.tickets[] | select(.state == "escalated" or .state == "escalation_failed")] | length),
            failed:    ([.tickets[] | select(.state == "failed")] | length)
        }
    ' "$state_file")
    printf '%s\n' "$updated" > "$state_file"
}

check_state_integrity() {
    local state_file="${REPO_ROOT}/.sprint-state"
    [ -f "$state_file" ] || return 0
    if ! jq . < "$state_file" > /dev/null 2>&1; then
        printf 'ERROR: .sprint-state is corrupt (not valid JSON). Delete it and rerun with --resume to recover.\n' >&2
        return 1
    fi
    return 0
}

parse_usage() {
    local session_log="$1"
    local input_tokens output_tokens cache_read cache_write total
    # -R reads each line as raw string; try fromjson skips non-JSON lines (e.g. stderr text from 2>&1)
    input_tokens=$(jq -Rr '(try fromjson // null) | select(. != null and .type == "result") | .usage.input_tokens // "0"' "$session_log" 2>/dev/null | tail -1)
    output_tokens=$(jq -Rr '(try fromjson // null) | select(. != null and .type == "result") | .usage.output_tokens // "0"' "$session_log" 2>/dev/null | tail -1)
    cache_read=$(jq -Rr '(try fromjson // null) | select(. != null and .type == "result") | .usage.cache_read_input_tokens // "0"' "$session_log" 2>/dev/null | tail -1)
    cache_write=$(jq -Rr '(try fromjson // null) | select(. != null and .type == "result") | .usage.cache_creation_input_tokens // "0"' "$session_log" 2>/dev/null | tail -1)
    input_tokens="${input_tokens:-0}"
    output_tokens="${output_tokens:-0}"
    cache_read="${cache_read:-0}"
    cache_write="${cache_write:-0}"
    total=$(( input_tokens + output_tokens + cache_read + cache_write ))
    if [ "${total:-0}" -le 0 ]; then
        printf 'WARN: usage parse returned 0 tokens — schema may have changed\n' >&2
    fi
    printf '%d' "$total"
}

# ── Queue ─────────────────────────────────────────────────────────────────────

read_queue() {
    local sprint_label="$1"
    local queue_file="$2"
    local state_file="${REPO_ROOT}/.sprint-state"

    local terminal_json="{}"
    if [ -f "$state_file" ]; then
        terminal_json=$(jq '
            .tickets | to_entries |
            map(select(.value.state == "merged" or .value.state == "escalated"
                or .value.state == "escalation_failed" or .value.state == "failed")) |
            map({(.key): true}) | add // {}
        ' "$state_file" 2>/dev/null || printf '{}')
    fi

    # Pipe gh output through standalone jq so --argjson is a jq flag, not a gh flag.
    # $n and $terminal_states below are jq variables, not shell variables.
    # shellcheck disable=SC2016
    if ! "$GH_BIN" issue list \
            --label "$sprint_label" \
            --state open \
            --json "number,title,labels,createdAt" 2>&1 \
        | jq -r --argjson terminal_states "$terminal_json" '
            map(select((.labels | map(.name) | any(. == "needs-human")) | not))
            | map(select((.labels | map(.name) | any(. == "blocked")) | not))
            | map(select(
                (.number | tostring) as $n | ($terminal_states | has($n)) | not
            ))
            | sort_by([
                (if (.labels | map(.name) | any(. == "P0-critical")) then 0
                 elif (.labels | map(.name) | any(. == "P1-high")) then 1
                 elif (.labels | map(.name) | any(. == "P2-medium")) then 2
                 else 3 end),
                .createdAt
            ])
            | .[].number' \
        > "$queue_file"
    then
        printf 'ERROR: gh issue list or jq filter failed\n' >&2
        return 1
    fi

    if [ ! -s "$queue_file" ]; then
        printf 'INFO: Sprint queue is empty (no open issues with label '"'"'%s'"'"')\n' "$sprint_label"
        return 0
    fi

    printf 'INFO: Queue ready (%d tickets)\n' "$(wc -l < "$queue_file" | tr -d ' ')"
}

# ── Core ──────────────────────────────────────────────────────────────────────

escalate() {
    local ticket_number="$1"
    local trigger="$2"
    local severity="$3"
    local detail="${4:-}"
    local comment_body

    comment_body="sprint.sh escalation: trigger=${trigger} severity=${severity} sweep_id=${SWEEP_ID:-unknown}"
    if [ -n "$detail" ]; then
        comment_body="${comment_body} detail=$(printf '%s' "$detail" | head -c 200)"
    fi

    local gh_label_exit gh_comment_exit
    if "$GH_BIN" issue edit "$ticket_number" --add-label "needs-human" > /dev/null 2>&1; then
        gh_label_exit=0
    else
        gh_label_exit=$?
    fi
    # TODO(#238): capture gh_comment_id from response and write to .sprint-state (v1.0 schema field).
    if "$GH_BIN" issue comment "$ticket_number" --body "$comment_body" > /dev/null 2>&1; then
        gh_comment_exit=0
    else
        gh_comment_exit=$?
    fi

    if [ "$gh_label_exit" -ne 0 ] || [ "$gh_comment_exit" -ne 0 ]; then
        printf 'ERROR: gh escalation write failed for #%s (label=%d comment=%d)\n' \
            "$ticket_number" "$gh_label_exit" "$gh_comment_exit" >&2
        state_set "$ticket_number" "escalation_failed" "$trigger"
        return 1
    fi

    state_set "$ticket_number" "escalated" "$trigger"
    printf '[TICKET #%s] escalated: %s (%s)\n' "$ticket_number" "$trigger" "$severity"
    push_notify "$severity" "sprint.sh: #${ticket_number} escalated (${trigger})" \
        "https://github.com/Lenivvenil/claude-mini/issues/${ticket_number}"
}

notify() {
    local ticket_number="$1"
    local trigger="$2"
    local detail="${3:-}"
    local comment_body

    comment_body="sprint.sh warn: trigger=${trigger} sweep_id=${SWEEP_ID:-unknown}"
    if [ -n "$detail" ]; then
        comment_body="${comment_body} detail=$(printf '%s' "$detail" | head -c 200)"
    fi

    "$GH_BIN" issue edit "$ticket_number" --add-label "needs-human" > /dev/null 2>&1 || \
        printf 'WARN: gh label add failed for #%s trigger=%s\n' "$ticket_number" "$trigger" >&2
    "$GH_BIN" issue comment "$ticket_number" --body "$comment_body" > /dev/null 2>&1 || \
        printf 'WARN: gh comment failed for #%s trigger=%s\n' "$ticket_number" "$trigger" >&2

    printf '[TICKET #%s] warn: %s\n' "$ticket_number" "$trigger"
    push_notify "warn" "sprint.sh: #${ticket_number} warn (${trigger})" \
        "https://github.com/Lenivvenil/claude-mini/issues/${ticket_number}"
}

check_consecutive_failures() {
    local state_file="${REPO_ROOT}/.sprint-state"
    local threshold="${CONSECUTIVE_FAILURE_THRESHOLD:-3}"

    [ -f "$state_file" ] || return 1

    local count=0
    local state
    while IFS= read -r state; do
        if [ "$state" = "failed" ] || [ "$state" = "escalated" ] || [ "$state" = "escalation_failed" ]; then
            count=$((count + 1))
        fi
    done < <(jq -r --argjson t "$threshold" '
        [.tickets | to_entries[] | {s: .value.state, ts: .value.updated_at}]
        | sort_by(.ts) | reverse | .[:$t] | .[].s
    ' "$state_file" 2>/dev/null)

    [ "$count" -ge "$threshold" ]
}

# ── Session ───────────────────────────────────────────────────────────────────

verify_outcome() {
    local ticket_number="$1"
    local tokens_used="$2"
    local issue_state pr_exists pr_num

    issue_state=$("$GH_BIN" issue view "$ticket_number" --json state --jq '.state' 2>/dev/null || printf '')

    # Guard against transient GitHub outage — empty state means we cannot verify.
    # Leave ticket as "running" so --resume can retry; do not escalate on network blip.
    if [ -z "$issue_state" ]; then
        printf 'WARN: [TICKET #%s] could not reach GitHub to verify outcome — leaving as running for --resume\n' \
            "$ticket_number" >&2
        return 1
    fi

    if [ "$issue_state" = "CLOSED" ]; then
        pr_num=$("$GH_BIN" pr list \
            --search "Closes #${ticket_number}" \
            --state merged \
            --json number \
            --jq '.[0].number // empty' 2>/dev/null || printf '')
        if [ -n "$pr_num" ]; then
            # Atomic: write pr_number + merged state in one jq pass (no partial-write window).
            local now
            now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            local updated
            updated=$(jq \
                --arg n "$ticket_number" \
                --arg t "$tokens_used" \
                --argjson pr "$pr_num" \
                --arg ts "$now" \
                '.last_updated = $ts | .tickets[$n] = ((.tickets[$n] // {}) + {state: "merged", reason: "", tokens_used: ($t | tonumber), pr_number: $pr, updated_at: $ts})' \
                "${REPO_ROOT}/.sprint-state" 2>/dev/null)
            if [ -n "$updated" ]; then
                printf '%s\n' "$updated" > "${REPO_ROOT}/.sprint-state"
            fi
            printf '[TICKET #%s] merged OK (%s tokens)\n' "$ticket_number" "$tokens_used"
            push_notify "info" "sprint.sh: #${ticket_number} merged" \
                "https://github.com/Lenivvenil/claude-mini/pull/${pr_num}"
            return 0
        fi
    fi

    # T3: issue_not_closed — PR exists but issue still open
    pr_exists=$("$GH_BIN" pr list --search "Closes #${ticket_number}" --json number --jq 'length' 2>/dev/null || printf '0')
    if [ "${pr_exists:-0}" -gt 0 ]; then
        escalate "$ticket_number" "issue_not_closed" "warn"
        return 0
    fi

    # T2: no_pr_after_session
    escalate "$ticket_number" "no_pr_after_session" "critical"
    return 1
}

run_ticket() {
    local ticket_number="$1"

    if ! printf '%s' "$ticket_number" | grep -qE '^[0-9]+$'; then
        printf 'ERROR: invalid ticket_number '"'"'%s'"'"' (must be numeric)\n' "$ticket_number" >&2
        return 1
    fi

    # T7: pre_existing needs-human label
    local pre_labels
    pre_labels=$("$GH_BIN" issue view "$ticket_number" --json labels \
        --jq '[.labels[].name]' 2>/dev/null || printf '[]')
    if printf '%s' "$pre_labels" | jq -e 'any(. == "needs-human")' > /dev/null 2>&1; then
        printf '[TICKET #%s] T7 pre_existing_needs_human — skipping\n' "$ticket_number" >&2
        state_set "$ticket_number" "escalated" "pre_existing_needs_human"
        return 0
    fi

    local session_log_dir session_log
    session_log_dir="${REPO_ROOT}/.sprint-logs/${SWEEP_ID:-unknown}"
    mkdir -p "$session_log_dir"
    session_log="${session_log_dir}/${ticket_number}-session.json"
    local session_start session_end session_duration
    session_start=$(date +%s)

    printf '[TICKET #%s] starting /feature session\n' "$ticket_number"
    state_set "$ticket_number" "running" ""

    local claude_exit=0
    # --verbose required: stream-json emits usage events only in verbose mode
    "$CLAUDE_BIN" -p "/feature ${ticket_number}" \
        --output-format stream-json \
        --verbose \
        --max-turns "${MAX_TURNS}" \
        > "$session_log" 2>&1 || claude_exit=$?

    session_end=$(date +%s)
    session_duration=$(( session_end - session_start ))

    if [ "$claude_exit" -ne 0 ]; then
        printf '[TICKET #%s] T1 process_error: claude exited %d\n' "$ticket_number" "$claude_exit" >&2
        local t1_label_exit=0 t1_comment_exit=0
        if "$GH_BIN" issue edit "$ticket_number" --add-label "needs-human" > /dev/null 2>&1; then
            t1_label_exit=0
        else
            t1_label_exit=$?
        fi
        if "$GH_BIN" issue comment "$ticket_number" \
                --body "sprint.sh: T1 process_error — claude exit ${claude_exit}" > /dev/null 2>&1; then
            t1_comment_exit=0
        else
            t1_comment_exit=$?
        fi
        if [ "$t1_label_exit" -ne 0 ] || [ "$t1_comment_exit" -ne 0 ]; then
            printf 'ERROR: gh write failed for T1 on #%s (label=%d comment=%d)\n' \
                "$ticket_number" "$t1_label_exit" "$t1_comment_exit" >&2
            state_set "$ticket_number" "escalation_failed" "process_error"
        else
            state_set "$ticket_number" "failed" "claude exit ${claude_exit}"
        fi
        push_notify "critical" "sprint.sh: #${ticket_number} T1 process_error (exit ${claude_exit})" \
            "https://github.com/Lenivvenil/claude-mini/issues/${ticket_number}"
        return 1
    fi

    local tokens_used
    tokens_used=$(parse_usage "$session_log")

    # T4: governance_block (warn, non-terminal)
    if grep -q "governance hook blocked\|commit rejected" "$session_log" 2>/dev/null; then
        local t4_detail
        t4_detail=$(grep -m1 "governance hook blocked\|commit rejected" "$session_log" | head -c 200)
        notify "$ticket_number" "governance_block" "$t4_detail"
    fi

    # T5: budget_spike (warn, non-terminal)
    if [ "${tokens_used:-0}" -gt "${BUDGET_SPIKE_THRESHOLD:-600000}" ]; then
        notify "$ticket_number" "budget_spike" "${tokens_used} tokens"
    fi

    # Record session duration
    local updated
    updated=$(jq \
        --arg n "$ticket_number" \
        --argjson dur "$session_duration" \
        '.tickets[$n].session_duration_sec = $dur' \
        "${REPO_ROOT}/.sprint-state" 2>/dev/null || printf '')
    if [ -n "$updated" ]; then
        printf '%s\n' "$updated" > "${REPO_ROOT}/.sprint-state"
    fi

    verify_outcome "$ticket_number" "$tokens_used"
    return $?
}

# ── Main loop ─────────────────────────────────────────────────────────────────

process_sprint_queue() {
    local sprint_label="$1"
    local queue_file
    queue_file=$(mktemp)

    if ! read_queue "$sprint_label" "$queue_file"; then
        rm -f "$queue_file"
        return 1
    fi

    if [ ! -s "$queue_file" ]; then
        rm -f "$queue_file"
        return 0
    fi

    local ticket_number sweep_aborted=0
    while IFS= read -r ticket_number; do
        [ -n "$ticket_number" ] || continue

        # CheckBudget (T5 gate): stop starting new tickets when cumulative spend exceeds --budget.
        if [ -n "${BUDGET:-}" ] && [ -f "${REPO_ROOT}/.sprint-state" ]; then
            local spent
            spent=$(jq '[.tickets[].tokens_used] | add // 0' "${REPO_ROOT}/.sprint-state" 2>/dev/null || printf '0')
            if [ "${spent:-0}" -ge "${BUDGET}" ]; then
                printf 'INFO: Budget %s tokens exhausted (spent %s). Stopping new tickets.\n' "$BUDGET" "$spent" >&2
                break
            fi
        fi

        if ! run_ticket "$ticket_number"; then
            printf 'WARN: run_ticket %s returned non-zero\n' "$ticket_number" >&2
        fi

        if check_consecutive_failures; then
            # T6: abort sweep — individual tickets carry their terminal states.
            printf 'CRITICAL: consecutive failures threshold reached — aborting sweep (T6)\n' >&2
            push_notify "critical" "sprint.sh: T6 consecutive failures — sweep aborted" \
                "https://github.com/Lenivvenil/claude-mini"
            sweep_aborted=1
            break
        fi
    done < "$queue_file"

    rm -f "$queue_file"
    [ "$sweep_aborted" -eq 0 ]
}

# ── Dry-run ───────────────────────────────────────────────────────────────────

dry_run() {
    local sprint_label="$1"
    printf 'DRY-RUN: reading Sprint queue (label: %s)\n' "$sprint_label"
    local queue_file
    queue_file=$(mktemp)
    if ! read_queue "$sprint_label" "$queue_file"; then
        rm -f "$queue_file"
        return 1
    fi
    if [ ! -s "$queue_file" ]; then
        rm -f "$queue_file"
        push_notify "info" "sprint.sh dry-run: sprint complete (empty queue)" \
            "https://github.com/Lenivvenil/claude-mini"
        return 0
    fi
    printf 'DRY-RUN: would process tickets in order:\n'
    local n=1
    local ticket_number
    while IFS= read -r ticket_number; do
        [ -n "$ticket_number" ] || continue
        local title
        title=$("$GH_BIN" issue view "$ticket_number" --json title --jq '.title' 2>/dev/null || printf '(unknown)')
        printf '  %d. #%s — %s\n' "$n" "$ticket_number" "$title"
        n=$((n + 1))
    done < "$queue_file"
    rm -f "$queue_file"
    push_notify "info" "sprint.sh dry-run: sprint complete (would process $((n - 1)) tickets)" \
        "https://github.com/Lenivvenil/claude-mini"
    return 0
}

# ── Entry point ───────────────────────────────────────────────────────────────

main() {
    # Parse args
    while [ $# -gt 0 ]; do
        case "$1" in
            --sprint-label)
                SPRINT_LABEL="$2"; shift 2 ;;
            --budget)
                BUDGET="$2"; shift 2 ;;
            --dry-run)
                DRY_RUN=1; shift ;;
            --resume)
                RESUME=1; shift ;;
            --ticket)
                SINGLE_TICKET="$2"; shift 2 ;;
            -h|--help)
                grep '^#' "$0" | head -10 | sed 's/^# \?//'
                exit 0 ;;
            *)
                printf 'ERROR: unknown argument: %s\n' "$1" >&2
                exit 1 ;;
        esac
    done

    # REPO_ROOT guard
    if [ -z "${REPO_ROOT:-}" ]; then
        printf 'ERROR: REPO_ROOT not resolved — run from inside a git repository or set REPO_ROOT\n' >&2
        exit 1
    fi

    # Preflight: required binaries
    if ! command -v jq > /dev/null 2>&1; then
        printf 'ERROR: jq is required but not found on PATH\n' >&2
        exit 1
    fi
    if ! command -v "$GH_BIN" > /dev/null 2>&1; then
        printf 'ERROR: gh CLI is required but not found on PATH (GH_BIN=%s)\n' "$GH_BIN" >&2
        exit 1
    fi

    # BUDGET numeric validation
    if [ -n "${BUDGET:-}" ]; then
        if ! printf '%s' "$BUDGET" | grep -qE '^[0-9]+$'; then
            printf 'ERROR: --budget value must be a non-negative integer, got: %s\n' "$BUDGET" >&2
            exit 1
        fi
    fi

    # T9: state integrity check
    if ! check_state_integrity; then
        exit 1
    fi

    # Ensure needs-human label exists
    ensure_label

    # Initialise sweep metadata
    SWEEP_ID=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    SWEEP_STARTED_AT="$SWEEP_ID"
    export SWEEP_ID SWEEP_STARTED_AT

    # Dry-run mode
    if [ "$DRY_RUN" -eq 1 ]; then
        dry_run "$SPRINT_LABEL"
        exit $?
    fi

    # Single-ticket debug mode
    if [ -n "$SINGLE_TICKET" ]; then
        run_ticket "$SINGLE_TICKET"
        state_update_summary
        exit $?
    fi

    if [ "$RESUME" -eq 1 ]; then
        printf 'INFO: --resume mode: pre-verifying running tickets against GitHub (design doc B.6 §Scenario 1)\n'
        # Pre-verify tickets stuck in "running" state from a previous crashed sweep.
        if [ -f "${REPO_ROOT}/.sprint-state" ]; then
            local running_ticket
            while IFS= read -r running_ticket; do
                [ -n "$running_ticket" ] || continue
                local rv_state rv_pr_num
                rv_state=$("$GH_BIN" issue view "$running_ticket" --json state --jq '.state' 2>/dev/null || printf '')
                if [ "$rv_state" = "CLOSED" ]; then
                    rv_pr_num=$("$GH_BIN" pr list \
                        --search "Closes #${running_ticket}" \
                        --state merged \
                        --json number \
                        --jq '.[0].number // empty' 2>/dev/null || printf '')
                    if [ -n "$rv_pr_num" ]; then
                        state_set "$running_ticket" "merged" "resume-pre-verified" "0"
                        printf 'INFO: --resume: #%s pre-verified as merged (PR #%s)\n' "$running_ticket" "$rv_pr_num"
                    else
                        # Issue closed without merged PR — escalate (unknown terminal state).
                        escalate "$running_ticket" "no_pr_after_session" "critical" \
                            "resume pre-verify: issue closed but no merged PR found"
                        printf 'INFO: --resume: #%s escalated (closed issue, no merged PR)\n' "$running_ticket"
                    fi
                else
                    # Issue still open — leave as running so read_queue re-queues it.
                    printf 'INFO: --resume: #%s still open, will be re-queued\n' "$running_ticket"
                fi
            done < <(jq -r '.tickets | to_entries[] | select(.value.state == "running") | .key' \
                "${REPO_ROOT}/.sprint-state" 2>/dev/null)
        fi
    fi

    # Full sweep
    if ! process_sprint_queue "$SPRINT_LABEL"; then
        state_update_summary
        push_notify "critical" "sprint.sh: sweep ended with critical failure" \
            "https://github.com/Lenivvenil/claude-mini"
        exit 1
    fi

    state_update_summary
    push_notify "info" "sprint.sh: sprint complete" \
        "https://github.com/Lenivvenil/claude-mini"
    printf 'INFO: Sprint sweep complete.\n'
    exit 0
}

main "$@"
