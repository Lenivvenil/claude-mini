#!/usr/bin/env bash
# adr-retirement-audit.sh — ADR staleness audit
#
# Usage:
#   adr-retirement-audit.sh [--decisions-dir <path>] [--threshold <days>]
#                            [--apply <nums>] [--dry-run]
#
# --decisions-dir  path to ADR directory (default: <repo-root>/docs/decisions)
# --threshold      days for incoming-ref recency check (default: 90)
# --apply          comma-separated ADR numbers to apply recommendations to (e.g. 0004,0013)
# --dry-run        print report to stdout only; do not write files even with --apply
#
# Checks per ADR:
#   (a) incoming refs in last N days (grep across repo .md files via git log)
#   (b) superseded-by chain: target file exists, no cycles
#   (c) dep presence in pyproject.toml/package.json/go.mod (best-effort; N/A if no manifest)
#
# Output: markdown report to stdout

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "adr-retirement-audit: not inside a git repository" >&2
    exit 1
}

DECISIONS_DIR="${ADR_DECISIONS_DIR:-$REPO_ROOT/docs/decisions}"
THRESHOLD_DAYS=90
APPLY_NUMS=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --decisions-dir) DECISIONS_DIR="${2:?'--decisions-dir requires a value'}"; shift ;;
        --threshold)     THRESHOLD_DAYS="${2:?'--threshold requires a value'}"; shift ;;
        --apply)         APPLY_NUMS="${2:?'--apply requires comma-separated ADR numbers'}"; shift ;;
        --dry-run)       DRY_RUN=true ;;
        *)
            echo "adr-retirement-audit: unknown argument '$1'" >&2
            exit 1
            ;;
    esac
    shift
done

if [ ! -d "$DECISIONS_DIR" ]; then
    echo "adr-retirement-audit: decisions directory not found: $DECISIONS_DIR" >&2
    exit 1
fi

# ── Helpers ────────────────────────────────────────────────────────────────────

# Build grep pattern matching all known cross-reference forms for a 4-digit ADR number
adr_ref_pattern() {
    local padded="$1"
    # Covers: ADR-0004, ADR 0004, [0004](...), docs/decisions/0004
    printf 'ADR[-[:space:]]%s[^0-9]|ADR[-[:space:]]%s$|\\[%s\\]|docs/decisions/%s' \
        "$padded" "$padded" "$padded" "$padded"
}

# Count files (excluding the ADR itself) that currently reference padded ADR number
count_current_refs() {
    local adr_file="$1"
    local padded="$2"
    local pattern count
    pattern="$(adr_ref_pattern "$padded")"
    count=0
    while IFS= read -r -d '' f; do
        if [ "$f" = "$adr_file" ]; then
            continue
        fi
        if grep -qEi "$pattern" "$f" 2>/dev/null; then
            count=$((count + 1))
        fi
    done < <(find "$REPO_ROOT" -name "*.md" -not -path "*/.git/*" -print0 2>/dev/null)
    printf '%d' "$count"
}

# Count files modified within THRESHOLD_DAYS that reference padded ADR number
count_recent_refs() {
    local adr_file="$1"
    local padded="$2"
    local pattern threshold_date count changed_files abs
    pattern="$(adr_ref_pattern "$padded")"
    threshold_date="$(date -v -"${THRESHOLD_DAYS}"d '+%Y-%m-%d' 2>/dev/null \
        || date -d "${THRESHOLD_DAYS} days ago" '+%Y-%m-%d' 2>/dev/null \
        || echo "")"
    if [ -z "$threshold_date" ]; then
        printf 'N/A'
        return
    fi
    count=0
    changed_files="$(git -C "$REPO_ROOT" log --after="$threshold_date" --name-only \
        --format="" --diff-filter=AM -- '*.md' 2>/dev/null | grep -v '^$' | sort -u)"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        abs="$REPO_ROOT/$f"
        if [ "$abs" = "$adr_file" ]; then
            continue
        fi
        if [ -f "$abs" ] && grep -qEi "$pattern" "$abs" 2>/dev/null; then
            count=$((count + 1))
        fi
    done <<< "$changed_files"
    printf '%d' "$count"
}

# Extract field value from ADR markdown-bullet frontmatter
get_field() {
    local field="$1"
    local file="$2"
    grep -m1 "^\* ${field}:" "$file" 2>/dev/null | sed "s/^\* ${field}:[[:space:]]*//" | tr -d '\r'
}

# Check if an ADR number is in the apply list (accepts both "4" and "0004" forms)
in_apply_list() {
    local num="$1"
    if [ -z "$APPLY_NUMS" ]; then
        return 1
    fi
    # Strip leading zeros from num to build a bare integer pattern (e.g. "0004" → "4")
    local bare
    bare="${num#"${num%%[!0]*}"}"
    [ -z "$bare" ] && bare="0"
    # Match entry if it equals the padded form or the bare integer form
    echo "$APPLY_NUMS" | tr ',' '\n' | grep -qE "^(0*${bare}|${num})$"
}

# Apply status update to ADR file (append-only: only touches Status and Superseded-by lines)
apply_recommendation() {
    local file="$1"
    local rec="$2"
    local sup_target="$3"

    if [ "$DRY_RUN" = true ]; then
        echo "[dry-run] would update $(basename "$file"): $rec" >&2
        return
    fi

    case "$rec" in
        mark-deprecated)
            sed -i.bak "s/^\* Status: .*/\* Status: deprecated/" "$file"
            rm -f "${file}.bak"
            ;;
        mark-superseded)
            sed -i.bak "s/^\* Status: .*/\* Status: superseded/" "$file"
            rm -f "${file}.bak"
            if [ -n "$sup_target" ] && [ "$sup_target" != "~" ]; then
                if grep -q "^\* Superseded-by:" "$file"; then
                    sed -i.bak "s|^\* Superseded-by:.*|\* Superseded-by: $sup_target|" "$file"
                    rm -f "${file}.bak"
                else
                    # Insert Superseded-by after Status line (awk is portable across BSD/GNU)
                    awk -v val="$sup_target" \
                        '/^\* Status:/{print; print "* Superseded-by: " val; next} {print}' \
                        "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
                fi
            fi
            ;;
    esac
}

# ── ADR age in days (from first git commit of that file) ──────────────────────

adr_age_days() {
    local file="$1"
    local creation_date now_ts then_ts
    creation_date=$(git -C "$REPO_ROOT" log --follow --format="%ci" -- "$file" 2>/dev/null \
        | tail -1 | cut -c1-10)
    if [ -z "$creation_date" ]; then
        printf '0'
        return
    fi
    now_ts=$(date '+%s' 2>/dev/null || echo 0)
    then_ts=$(date -j -f '%Y-%m-%d' "$creation_date" '+%s' 2>/dev/null \
        || date -d "$creation_date" '+%s' 2>/dev/null \
        || echo 0)
    if [ "$now_ts" -le 0 ] || [ "$then_ts" -le 0 ]; then
        printf '0'
        return
    fi
    printf '%d' $(( (now_ts - then_ts) / 86400 ))
}

# ── Dep presence check (best-effort) ──────────────────────────────────────────

check_dep_presence() {
    local title="$1"
    local m found_manifests keyword
    found_manifests=false
    for m in pyproject.toml package.json go.mod; do
        if [ -f "$REPO_ROOT/$m" ]; then
            found_manifests=true
            break
        fi
    done
    if [ "$found_manifests" = false ]; then
        printf 'N/A'
        return
    fi
    # Extract longest meaningful keyword from title (≥4 chars, skip common words)
    keyword=$(echo "$title" | tr '[:upper:]' '[:lower:]' \
        | grep -oE '[a-z]{4,}' \
        | grep -vxE 'this|that|with|from|into|over|under|when|then|have|been|will|shall|must|should|could|would|adopt|install|enforce|baseline|state|takeover|feature|branch|pipeline|read|only|critic|agents|decision|record|hardware|universal|split|flow|layer|review|gate|weekly|drift|behaviour|level|governance|phase|scope|surface|domain|invariants|placement|worktree|isolation|project|command|installation|post|verification|aggregate|extraction|principle|hardened|revision|integration|installer|template|voice|plus' \
        | head -1)
    if [ -z "$keyword" ]; then
        printf 'N/A'
        return
    fi
    for m in pyproject.toml package.json go.mod; do
        if [ -f "$REPO_ROOT/$m" ] && grep -qi "$keyword" "$REPO_ROOT/$m" 2>/dev/null; then
            printf 'present'
            return
        fi
    done
    printf 'absent'
}

# ── Superseded-by chain check ─────────────────────────────────────────────────

check_chain() {
    local padded="$1"
    local visited="$2"
    local file sup next_padded

    if echo " $visited " | grep -qw "$padded"; then
        printf 'cycle'
        return
    fi

    file=$(find "$DECISIONS_DIR" -maxdepth 1 -name "${padded}-*.md" 2>/dev/null | head -1)
    if [ -z "$file" ]; then
        printf 'target-missing'
        return
    fi

    sup=$(get_field "Superseded-by" "$file")
    if [ -z "$sup" ] || [ "$sup" = "~" ]; then
        printf 'ok'
        return
    fi

    next_padded=$(echo "$sup" | grep -oE '[0-9]{4}' | head -1)
    if [ -z "$next_padded" ]; then
        printf 'ok'
        return
    fi

    check_chain "$next_padded" "${visited} ${padded}"
}

# ── Main loop ─────────────────────────────────────────────────────────────────

TODAY="$(date '+%Y-%m-%d')"
KEEP_COUNT=0
DEPRECATED_COUNT=0
SUPERSEDED_COUNT=0

printf "# ADR Retirement Audit — %s\n\n" "$TODAY"
printf "Threshold: %d days | Decisions: %s\n\n" "$THRESHOLD_DAYS" "$DECISIONS_DIR"
printf "| ADR | Title | Status | Superseded-by | Age(d) | Refs(cur) | Refs(%dd) | Dep | Chain | Recommendation |\n" "$THRESHOLD_DAYS"
printf "|-----|-------|--------|---------------|--------|-----------|-----------|-----|-------|----------------|\n"

APPLIED_LOG=""

while IFS= read -r adr_file; do
    filename="$(basename "$adr_file")"
    padded="${filename:0:4}"

    title_line=$(head -1 "$adr_file")
    title="${title_line#"# ${padded}. "}"
    if [ "${#title}" -gt 50 ]; then
        title="${title:0:47}..."
    fi

    status=$(get_field "Status" "$adr_file")
    sup=$(get_field "Superseded-by" "$adr_file")
    [ -z "$sup" ] && sup="~"

    current_refs=$(count_current_refs "$adr_file" "$padded")
    recent_refs=$(count_recent_refs "$adr_file" "$padded")
    chain_status=$(check_chain "$padded" "")
    dep=$(check_dep_presence "$title")
    age=$(adr_age_days "$adr_file")

    # ── Recommendation logic ────────────────────────────────────────────────
    rec="keep"

    if [ "$status" = "deprecated" ] || [ "$status" = "superseded" ]; then
        rec="keep (already-${status})"
    elif [ "$sup" != "~" ] && [ -n "$sup" ]; then
        if [ "$chain_status" = "ok" ]; then
            rec="mark-superseded"
        elif [ "$chain_status" = "cycle" ]; then
            rec="keep (chain-cycle-error)"
        elif [ "$chain_status" = "target-missing" ]; then
            rec="keep (chain-target-missing)"
        fi
    elif [ "$current_refs" -eq 0 ] 2>/dev/null; then
        # Only flag for deprecation if ADR is older than the threshold
        if [ "$age" -ge "$THRESHOLD_DAYS" ]; then
            # Treat N/A (date computation failed) as unknown — skip recommendation
            if [ "$recent_refs" != "N/A" ] && [ "$recent_refs" -eq 0 ] 2>/dev/null; then
                rec="mark-deprecated"
            fi
        fi
    fi

    case "$rec" in
        keep*)            KEEP_COUNT=$((KEEP_COUNT + 1)) ;;
        mark-deprecated)  DEPRECATED_COUNT=$((DEPRECATED_COUNT + 1)) ;;
        mark-superseded)  SUPERSEDED_COUNT=$((SUPERSEDED_COUNT + 1)) ;;
    esac

    printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | **%s** |\n" \
        "$padded" "$title" "$status" "$sup" "$age" "$current_refs" "$recent_refs" "$dep" "$chain_status" "$rec"

    # ── Inline apply ───────────────────────────────────────────────────────
    if in_apply_list "$padded"; then
        case "$rec" in
            mark-deprecated|mark-superseded)
                apply_recommendation "$adr_file" "$rec" "$sup"
                APPLIED_LOG="${APPLIED_LOG}- ${padded}: applied **${rec}**\n"
                ;;
            *)
                APPLIED_LOG="${APPLIED_LOG}- ${padded}: skipped (recommendation is '${rec}')\n"
                ;;
        esac
    fi

done < <(find "$DECISIONS_DIR" -maxdepth 1 -name '[0-9]*.md' | sort)

printf "\n## Summary\n\n"
echo "- keep: ${KEEP_COUNT}"
echo "- mark-deprecated: ${DEPRECATED_COUNT}"
echo "- mark-superseded: ${SUPERSEDED_COUNT}"

if [ -n "$APPLIED_LOG" ]; then
    printf "\n## Applied updates\n\n"
    printf '%b' "$APPLIED_LOG"
fi
