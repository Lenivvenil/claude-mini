#!/usr/bin/env bash
# gate-audit-lib.sh — shared event-write helper for gate instrumentation
#
# Source this file after a gate decision is made. It appends one JSONL line to
# docs/gate-audit/events.jsonl and prints the event_id to stderr so the
# operator can tag it with: forge gate-tag <event_id> --real|--false-positive
#
# Caller sets GATE_AUDIT_ENABLED=0 to suppress all writes (e.g. in tests
# that want to isolate the gate under test). Default is enabled.
#
# Safe to source multiple times — guarded by GATE_AUDIT_LIB_LOADED.

[ "${GATE_AUDIT_LIB_LOADED:-0}" = "1" ] && return 0
GATE_AUDIT_LIB_LOADED=1

# _gate_iso_week — portable ISO 8601 week string (YYYY-WNN)
# GNU date: %G-%V works. macOS date: no %V. python3 is the portable fallback.
_gate_iso_week() {
    python3 -c \
        "from datetime import date; d=date.today(); print(str(d.isocalendar()[0])+'-W%02d'%d.isocalendar()[1])" \
        2>/dev/null \
    || date -u +"%Y-W%V" 2>/dev/null \
    || { printf '[gate-audit] WARN: cannot determine ISO week; event skipped\n' >&2; return 0; }
}

# gate_event_write <gate_name> <outcome>
#   gate_name  — identifier string, e.g. "pre-commit-governance"
#   outcome    — "blocked" | "allowed"
#
# Returns 0 always — must never propagate failure to the calling hook.
gate_event_write() {
    local gate_name="${1:-unknown}"
    local outcome="${2:-unknown}"

    [ "${GATE_AUDIT_ENABLED:-1}" = "0" ] && return 0

    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0

    local events_dir="$repo_root/docs/gate-audit"
    [ -d "$events_dir" ] || return 0

    local event_id
    if command -v uuidgen >/dev/null 2>&1; then
        event_id=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-16)
    else
        event_id=$(printf '%s%s' "$(date +%s 2>/dev/null || echo 0)" "${RANDOM:-0}" \
                   | sha256sum 2>/dev/null | head -c 16 \
                   || printf '%016x' "${RANDOM:-0}")
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

    local week_iso
    week_iso=$(_gate_iso_week)

    printf '{"event_id":"%s","gate_name":"%s","timestamp":"%s","week_iso":"%s","outcome":"%s","classification":null,"cost_min":null}\n' \
        "$event_id" "$gate_name" "$timestamp" "$week_iso" "$outcome" \
        >> "$events_dir/events.jsonl" 2>/dev/null || return 0

    printf '[gate-audit] event_id: %s (gate: %s, outcome: %s)\n' \
        "$event_id" "$gate_name" "$outcome" >&2

    return 0
}
