#!/usr/bin/env bash
# test-adr-retirement-audit.sh — unit + integration tests for adr-retirement-audit.sh
#
# Tests:
#   T1: ADR older than threshold with 0 refs → mark-deprecated
#   T2: ADR with Superseded-by field and valid target → mark-superseded
#   T3: Superseded-by chain forms a cycle → keep (chain-cycle-error)
#   T4: Superseded-by points to missing file → keep (chain-target-missing)
#   T5: ADR with incoming refs → keep (even if old)
#   T6: --apply writes Status: deprecated (mark-deprecated path)
#   T7: --apply writes Status: superseded and preserves content
#   T9: Already-deprecated ADR → keep (already-deprecated)
#   T10: Real repo run — no errors, output is valid markdown, idempotent, no writes
#
# Usage: bash bootstrap/scripts/test-adr-retirement-audit.sh
# Exit: 0 = all passed, 1 = one or more failures

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bootstrap/scripts/adr-retirement-audit.sh"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

FAIL_FILE=$(mktemp /tmp/adr-test-failures-XXXXXX)
TMPDIRS=()
# shellcheck disable=SC2329
cleanup() {
    rm -f "$FAIL_FILE"
    for d in "${TMPDIRS[@]:-}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

pass() { printf "  %s✓%s %s\n" "${GREEN}" "${NC}" "$1"; }
fail() { printf "  %s✗%s %s\n" "${RED}" "${NC}" "$1"; echo "FAIL" >> "$FAIL_FILE"; }

# ── Temp repo factory ──────────────────────────────────────────────────────────

# Creates a temp git repo with docs/decisions/ and initial commit.
# Prints the repo path. Caller owns cleanup.
make_repo() {
    local d
    d=$(mktemp -d /tmp/adr-test-XXXXXX)
    TMPDIRS+=("$d")
    git -C "$d" init -q
    git -C "$d" config user.email "t@t.com"
    git -C "$d" config user.name "T"
    git -C "$d" symbolic-ref HEAD refs/heads/main
    mkdir -p "$d/docs/decisions"
    printf '%s' "$d"
}

# Adds an ADR file to a repo and commits it with optional backdated date.
# Usage: add_adr <repo> <num> <title> <status> <sup> [<commit_date>]
add_adr() {
    local repo="$1" num="$2" title="$3" status="$4" sup="$5"
    local commit_date="${6:-}"
    local file
    file="$repo/docs/decisions/${num}-$(echo "$title" | tr ' ' '-').md"
    {
        printf "# %s. %s\n\n" "$num" "$title"
        printf "* Status: %s\n" "$status"
        printf "* Superseded-by: %s\n" "$sup"
        printf "* Date: 2026-01-01\n"
        printf "\n## Context\n\nSome context.\n"
    } > "$file"
    git -C "$repo" add .
    if [ -n "$commit_date" ]; then
        GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
            git -C "$repo" commit -q -m "chore: add adr ${num}"
    else
        git -C "$repo" commit -q -m "chore: add adr ${num}"
    fi
}

# ── Unit tests ─────────────────────────────────────────────────────────────────

echo "=== adr-retirement-audit: recommendation logic ==="

# T1: old ADR, 0 refs → mark-deprecated
R1=$(make_repo)
add_adr "$R1" "0001" "Orphan ADR" "accepted" "~" "2025-01-01T00:00:00"
out=$(cd "$R1" && bash "$SCRIPT" --threshold 90 2>&1)
if echo "$out" | grep '0001' | grep -q 'mark-deprecated'; then
    pass "T1: old ADR with 0 refs → mark-deprecated"
else
    fail "T1: expected mark-deprecated, got: $(echo "$out" | grep '0001')"
fi

# T2: ADR with Superseded-by set and valid target → mark-superseded
R2=$(make_repo)
add_adr "$R2" "0001" "Old Decision" "accepted" "[0002](0002-New-Decision.md)"
add_adr "$R2" "0002" "New Decision" "accepted" "~"
out=$(cd "$R2" && bash "$SCRIPT" 2>&1)
if echo "$out" | grep '0001' | grep -q 'mark-superseded'; then
    pass "T2: ADR with valid Superseded-by → mark-superseded"
else
    fail "T2: expected mark-superseded for 0001, got: $(echo "$out" | grep '0001')"
fi

# T3: Superseded-by chain forms a cycle → keep (chain-cycle-error)
R3=$(make_repo)
add_adr "$R3" "0001" "ADR A" "accepted" "[0002](0002-ADR-B.md)"
add_adr "$R3" "0002" "ADR B" "accepted" "[0001](0001-ADR-A.md)"
out=$(cd "$R3" && bash "$SCRIPT" 2>&1)
if echo "$out" | grep '0001' | grep -q 'chain-cycle-error'; then
    pass "T3: cyclic Superseded-by chain → keep (chain-cycle-error)"
else
    fail "T3: expected chain-cycle-error for 0001, got: $(echo "$out" | grep '0001')"
fi

# T4: Superseded-by points to missing file → keep (chain-target-missing)
R4=$(make_repo)
add_adr "$R4" "0001" "Old" "accepted" "[0099](0099-does-not-exist.md)"
out=$(cd "$R4" && bash "$SCRIPT" 2>&1)
if echo "$out" | grep '0001' | grep -q 'chain-target-missing'; then
    pass "T4: missing Superseded-by target → keep (chain-target-missing)"
else
    fail "T4: expected chain-target-missing for 0001, got: $(echo "$out" | grep '0001')"
fi

# T5: ADR with incoming refs → keep (even if old)
R5=$(make_repo)
add_adr "$R5" "0001" "Referenced ADR" "accepted" "~" "2025-01-01T00:00:00"
# 0002 references 0001 via canonical ADR-0001 pattern
{
    printf "# 0002. Another ADR\n\n* Status: accepted\n* Superseded-by: ~\n* Date: 2025-01-01\n"
    printf "\n## Context\n\nSee ADR-0001 for context.\n"
} > "$R5/docs/decisions/0002-Another-ADR.md"
git -C "$R5" add .
GIT_AUTHOR_DATE="2025-01-01T00:00:00" GIT_COMMITTER_DATE="2025-01-01T00:00:00" \
    git -C "$R5" commit -q -m "chore: add adr 0002"
out=$(cd "$R5" && bash "$SCRIPT" --threshold 90 2>&1)
if echo "$out" | grep '0001' | grep -qv 'mark-deprecated'; then
    pass "T5: referenced ADR → keep (not mark-deprecated even if old)"
else
    fail "T5: expected keep for referenced 0001, got: $(echo "$out" | grep '0001')"
fi

# T6: --apply writes Status: deprecated
R6=$(make_repo)
add_adr "$R6" "0001" "Old Orphan" "accepted" "~" "2025-01-01T00:00:00"
f6="$R6/docs/decisions/0001-Old-Orphan.md"
(cd "$R6" && bash "$SCRIPT" --threshold 90 --apply 0001 >/dev/null 2>&1)
if grep -q '^\* Status: deprecated' "$f6"; then
    pass "T6: --apply writes 'deprecated' to Status field"
else
    fail "T6: Status not updated; contains: $(grep '^\* Status' "$f6")"
fi

# T7: --apply mark-superseded writes Status, preserves body content
R7=$(make_repo)
f7="$R7/docs/decisions/0001-Old.md"
{
    printf "# 0001. Old\n\n* Status: accepted\n* Superseded-by: [0002](0002-New.md)\n* Date: 2025-01-01\n"
    printf "\n## Body text must not change.\n\nThis content is load-bearing.\n"
} > "$f7"
{
    printf "# 0002. New\n\n* Status: accepted\n* Superseded-by: ~\n* Date: 2025-01-02\n\n## New context.\n"
} > "$R7/docs/decisions/0002-New.md"
git -C "$R7" add .
git -C "$R7" commit -q -m "chore: add adrs"
body_before=$(grep 'load-bearing' "$f7")
(cd "$R7" && bash "$SCRIPT" --apply 0001 >/dev/null 2>&1)
status_after=$(grep '^\* Status:' "$f7")
body_after=$(grep 'load-bearing' "$f7")
if [ "$status_after" = "* Status: superseded" ] && [ "$body_before" = "$body_after" ]; then
    pass "T7: --apply mark-superseded writes Status, preserves content"
else
    fail "T7: status='$status_after' body_match: before='$body_before' after='$body_after'"
fi

# T9: Already-deprecated ADR → keep (already-deprecated)
R9=$(make_repo)
add_adr "$R9" "0001" "Already Gone" "deprecated" "~" "2025-01-01T00:00:00"
out=$(cd "$R9" && bash "$SCRIPT" --threshold 90 2>&1)
if echo "$out" | grep '0001' | grep -q 'already-deprecated'; then
    pass "T9: already-deprecated ADR → keep (already-deprecated)"
else
    fail "T9: expected already-deprecated, got: $(echo "$out" | grep '0001')"
fi

# ── Integration tests on real repo ────────────────────────────────────────────

echo ""
echo "=== adr-retirement-audit: real repo integration ==="

out1=$(bash "$SCRIPT" 2>&1)
if echo "$out1" | grep -q '# ADR Retirement Audit'; then
    pass "T10.1: real repo run produces markdown report"
else
    fail "T10.1: expected markdown report header"
fi

if echo "$out1" | grep -q '| ADR |'; then
    pass "T10.2: report contains table header"
else
    fail "T10.2: missing table header"
fi

if echo "$out1" | grep -q '## Summary'; then
    pass "T10.3: report contains Summary section"
else
    fail "T10.3: missing Summary section"
fi

# Idempotency: run twice, compare summary
out2=$(bash "$SCRIPT" 2>&1)
sum1=$(echo "$out1" | grep -E '^- (keep|mark-)' | sort)
sum2=$(echo "$out2" | grep -E '^- (keep|mark-)' | sort)
if [ "$sum1" = "$sum2" ]; then
    pass "T10.4: audit is idempotent (two runs produce same summary)"
else
    fail "T10.4: runs differ — run1='$sum1' run2='$sum2'"
fi

# Report-only run must not modify any ADR
first_adr="docs/decisions/0001-baseline-state-at-takeover.md"
if git diff --quiet "$first_adr" 2>/dev/null; then
    pass "T10.5: report-only run does not modify ADR files"
else
    fail "T10.5: ADR was modified by report-only run"
fi

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
FAILURES=$(wc -l < "$FAIL_FILE" | tr -d ' ')
if [ "$FAILURES" -eq 0 ]; then
    printf "%s✓ All tests passed%s\n" "${GREEN}" "${NC}"
    exit 0
else
    printf "%s✗ %d test(s) failed%s\n" "${RED}" "$FAILURES" "${NC}"
    exit 1
fi
