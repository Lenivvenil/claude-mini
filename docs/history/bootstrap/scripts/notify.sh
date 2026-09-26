#!/usr/bin/env bash
# notify.sh — push-notification wrapper (osascript + ntfy.sh).
#
# Usage: notify.sh <severity> <title> <url>
#   severity ∈ {info, warn, critical}
#   title    — short human-readable message
#   url      — context link (issue / PR / dashboard)
#
# Transports attempted in order, both independently, best-effort:
#   1. macOS osascript — local Notification Center alert with severity sound
#   2. ntfy.sh         — phone push via NTFY_TOPIC env var
#
# Exit codes: 0 = sent or gracefully suppressed, 1 = bad arguments

# set -uo pipefail without -e: transports are best-effort; we check return codes
# explicitly rather than aborting on first failure.
set -uo pipefail

# ── Arg validation ────────────────────────────────────────────────────────────

if [ $# -ne 3 ]; then
    printf 'Usage: %s <severity> <title> <url>\n' "$(basename "$0")" >&2
    printf '  severity ∈ {info, warn, critical}\n' >&2
    exit 1
fi

severity="$1"
title="$2"
url="$3"

sound=""
ntfy_priority="default"

case "$severity" in
    info)
        sound=""
        ntfy_priority="default"
        ;;
    warn)
        sound="Ping"
        ntfy_priority="high"
        ;;
    critical)
        sound="Sosumi"
        ntfy_priority="urgent"
        ;;
    *)
        printf 'notify: unknown severity %s — must be info, warn, or critical\n' \
            "'${severity}'" >&2
        exit 1
        ;;
esac

# ── Input sanitisation ────────────────────────────────────────────────────────
# Remove characters that would break an AppleScript double-quoted string literal.
title="${title//\\/}"
title="${title//\"/}"
title="${title//$'\n'/ }"
title="${title//$'\r'/}"
url="${url//\\/}"
url="${url//\"/}"
url="${url//$'\n'/}"    # collapse to empty, not space — spaces are invalid in URLs
url="${url//$'\r'/}"

# ── Transport 1: macOS osascript ──────────────────────────────────────────────

_sent_local=0
if command -v osascript >/dev/null 2>&1; then
    if [ -n "$sound" ]; then
        osascript <<EOF
display notification "${title}
${url}" with title "claude-mini" sound name "${sound}"
EOF
    else
        osascript <<EOF
display notification "${title}
${url}" with title "claude-mini"
EOF
    fi
    _sent_local=1
fi

# ── Transport 2: ntfy.sh ──────────────────────────────────────────────────────

_sent_ntfy=0
if [ -n "${NTFY_TOPIC:-}" ]; then
    if [[ "$NTFY_TOPIC" =~ ^[A-Za-z0-9_-]+$ ]]; then
        if command -v curl >/dev/null 2>&1; then
            if curl -s -f \
                    --max-time 5 --connect-timeout 3 \
                    --data-raw "$title" \
                    -H "Click: $url" \
                    -H "Priority: $ntfy_priority" \
                    "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1; then
                _sent_ntfy=1
            else
                printf 'notify: WARNING: ntfy.sh delivery failed (curl error)\n' >&2
            fi
        else
            printf 'notify: WARNING: curl not found — ntfy.sh transport skipped\n' >&2
        fi
    else
        printf 'notify: WARNING: NTFY_TOPIC contains invalid characters — ntfy.sh skipped\n' >&2
    fi
fi

# ── Fallback: no transport available ─────────────────────────────────────────

if [ "$_sent_local" -eq 0 ] && [ "$_sent_ntfy" -eq 0 ]; then
    printf 'notify: WARNING: no transport available (severity=%s title=%s)\n' \
        "$severity" "$title" >&2
fi

exit 0
