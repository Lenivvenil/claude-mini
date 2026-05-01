#!/usr/bin/env bash
# forge.sh — Subcommand dispatch pattern: forge.sh <subcommand> [args]
#
# Currently implements: gate-tag
#
# Future subcommands (issue, pr, release) will be added here when the full
# vendor-agnostic wrapper is delivered (synthesis §4 / ADR-0009 forge-lock-in surface).
#
# Usage:
#   forge.sh gate-tag <event-id> --real|--false-positive
#   forge.sh gate-tag --latest  --real|--false-positive
#
# events.jsonl must be committed to the repo for the weekly CI aggregation to
# read it. Include docs/gate-audit/events.jsonl in your next git commit after
# tagging events.

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "forge: not inside a git repository" >&2
    exit 1
}
# GATE_AUDIT_EVENTS_FILE env var overrides the default path (used in tests).
EVENTS_FILE="${GATE_AUDIT_EVENTS_FILE:-$REPO_ROOT/docs/gate-audit/events.jsonl}"

# ── gate-tag subcommand ────────────────────────────────────────────────────

forge_gate_tag() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "forge gate-tag: jq is required but not found" >&2
        exit 1
    fi

    local event_id=""
    local classification=""
    local use_latest=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --real)           classification="real" ;;
            --false-positive) classification="false-positive" ;;
            --latest)         use_latest=1 ;;
            -*)
                echo "forge gate-tag: unknown flag '$1'" >&2
                echo "Usage: forge gate-tag <event-id>|--latest --real|--false-positive" >&2
                exit 1
                ;;
            *)
                if [ -n "$event_id" ]; then
                    echo "forge gate-tag: unexpected argument '$1'" >&2
                    exit 1
                fi
                event_id="$1"
                ;;
        esac
        shift
    done

    if [ -z "$classification" ]; then
        echo "forge gate-tag: --real or --false-positive is required" >&2
        echo "Usage: forge gate-tag <event-id>|--latest --real|--false-positive" >&2
        exit 1
    fi

    if [ "$use_latest" = "1" ] && [ -n "$event_id" ]; then
        echo "forge gate-tag: --latest and <event-id> are mutually exclusive" >&2
        exit 1
    fi

    if [ ! -f "$EVENTS_FILE" ]; then
        echo "forge gate-tag: events file not found: $EVENTS_FILE" >&2
        exit 1
    fi

    if [ "$use_latest" = "1" ]; then
        event_id=$(jq -r 'select(.classification == null) | .event_id' "$EVENTS_FILE" 2>/dev/null \
                   | tail -1 || true)
        if [ -z "$event_id" ] || [ "$event_id" = "null" ]; then
            echo "forge gate-tag: no unclassified events found" >&2
            exit 1
        fi
        echo "forge gate-tag: targeting latest unclassified event: $event_id" >&2
    fi

    if [ -z "$event_id" ]; then
        echo "forge gate-tag: <event-id> or --latest is required" >&2
        echo "Usage: forge gate-tag <event-id>|--latest --real|--false-positive" >&2
        exit 1
    fi

    # Reject event_id values outside the canonical hex-16 form emitted by gate_event_write.
    if ! printf '%s' "$event_id" | grep -qE '^[0-9a-f]{16}$'; then
        echo "forge gate-tag: invalid event_id '$event_id' (must be 16 lowercase hex chars)" >&2
        exit 1
    fi

    # Verify the event exists
    if ! grep -qF "\"event_id\":\"${event_id}\"" "$EVENTS_FILE" 2>/dev/null; then
        echo "forge gate-tag: event_id '$event_id' not found in $EVENTS_FILE" >&2
        exit 1
    fi

    # Update classification in-place using a temp file (POSIX-safe, no sed -i portability issues)
    local tmpfile
    tmpfile=$(mktemp "${EVENTS_FILE}.tmp.XXXXXX") || {
        echo "forge gate-tag: failed to create temp file" >&2
        exit 1
    }

    local matched=0
    while IFS= read -r line; do
        if echo "$line" | grep -qF "\"event_id\":\"${event_id}\""; then
            line=$(printf '%s' "$line" \
                   | jq -c --arg c "$classification" '.classification = $c' 2>/dev/null \
                   || echo "$line")
            matched=1
        fi
        printf '%s\n' "$line"
    done < "$EVENTS_FILE" > "$tmpfile"

    if [ "$matched" = "0" ]; then
        rm -f "$tmpfile"
        echo "forge gate-tag: event_id '$event_id' matched on grep but failed jq parse" >&2
        exit 1
    fi

    # NOTE: read-modify-write is non-atomic. schema.md §single-writer-invariant applies.
    # Do not run forge gate-tag concurrently with hook invocations on the same file.
    mv "$tmpfile" "$EVENTS_FILE"
    echo "forge gate-tag: event $event_id → classification=$classification" >&2
    echo "Hint: commit docs/gate-audit/events.jsonl to persist this tag."
}

# ── Dispatch ───────────────────────────────────────────────────────────────

case "${1:-}" in
    gate-tag)
        shift
        forge_gate_tag "$@"
        ;;
    "")
        echo "forge: subcommand required" >&2
        echo "Available: gate-tag" >&2
        exit 1
        ;;
    *)
        echo "forge: unknown subcommand '${1}'" >&2
        echo "Available: gate-tag" >&2
        exit 1
        ;;
esac
