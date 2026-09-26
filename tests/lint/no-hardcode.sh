#!/usr/bin/env bash
# no-hardcode.sh — values that belong in config must not be hardcoded (ADR-0031 §4, #311).
#
# Scans tracked files under the delivered surfaces (plugin/, setup/, tools/) for a narrow set of
# patterns. Prose is not the target: the patterns match code and frontmatter shapes. Every
# legitimate exception is listed in no-hardcode.allow as "<path>|<pattern id>|<reason>".
# Exit 0 clean · 1 findings · 2 usage/config error.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOW="$(dirname "${BASH_SOURCE[0]}")/no-hardcode.allow"
SURFACES=(plugin setup tools)

# id|extended regex
PATTERNS=(
    'model-pin|^model: *(opus|sonnet|haiku|fable)([^A-Za-z0-9_-]|$)'
    'model-name|(gpt-[0-9]|claude-(opus|sonnet|haiku|fable)-[0-9])'
    'owner-id|Lenivvenil'
    'board-id|PVT_[A-Za-z0-9]'
    'home-path|/Users/[A-Za-z]'
    'base-branch|(:-|=)["'"'"']?main["'"'"']?([^A-Za-z0-9_-]|$)'
)

[ -f "$ALLOW" ] || { echo "no-hardcode: allow file missing: $ALLOW" >&2; exit 2; }

existing=()
for s in "${SURFACES[@]}"; do [ -d "$REPO/$s" ] && existing+=("$s"); done

findings=0
for entry in "${PATTERNS[@]}"; do
    id=${entry%%|*}
    re=${entry#*|}
    # git grep: 0 = hits, 1 = none, anything else = the check itself failed (fail closed)
    hits=$(git -C "$REPO" grep -nE "$re" -- "${existing[@]}") ; rc=$?
    [ "$rc" -le 1 ] || { echo "no-hardcode: git grep failed (exit $rc) on pattern $id" >&2; exit 2; }
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        path=${hit%%:*}
        # the lint itself and its allow file describe the patterns
        case "$path" in tests/lint/*) continue ;; esac
        if grep -qF "$path|$id|" "$ALLOW"; then continue; fi
        echo "  $id  $hit"
        findings=$((findings + 1))
    done <<< "$hits"
done

# Allow entries must still match something, so the list only shrinks.
while IFS='|' read -r path id reason; do
    case "$path" in ''|'#'*) continue ;; esac
    [ -n "$reason" ] || { echo "  allow entry without a reason: $path|$id" ; findings=$((findings + 1)); continue; }
    re=""
    for entry in "${PATTERNS[@]}"; do [ "${entry%%|*}" = "$id" ] && re=${entry#*|}; done
    [ -n "$re" ] || { echo "  allow entry with unknown pattern id: $path|$id"; findings=$((findings + 1)); continue; }
    git -C "$REPO" grep -qE "$re" -- "$path" 2>/dev/null \
        || { echo "  stale allow entry (no longer matches): $path|$id"; findings=$((findings + 1)); }
done < "$ALLOW"

if [ "$findings" -eq 0 ]; then echo "no-hardcode: clean"; else echo "no-hardcode: $findings finding(s)"; fi
[ "$findings" -eq 0 ]
