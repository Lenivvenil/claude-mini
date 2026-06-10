#!/usr/bin/env bash
# test-mini-preflight.sh — smoke-test for the report_accumulated section of mini-preflight.sh (#257)
#
# Verifies that the "что накопилось за отсутствие" section:
#   - is skipped silently outside a git repo
#   - computes days-since-last-session from session-log filenames
#   - lists proposed ADRs with age
#   - degrades with a warn (not a crash, not an exit-code change) when gh is absent
#
# Network calls are NOT mocked — only degradation paths and local math are tested.
# The env-check half of mini-preflight (keychain, auth, claude) is environment-
# dependent; these tests assert on section output, not on the overall exit code.
# The report-only exit-code invariant is asserted structurally in T4 (the function
# body must never reference the failed counter), because a broken gh also fails
# the env-check half by design and a black-box exit-code comparison cannot
# isolate the section's contribution.
#
# Usage:
#   bash bootstrap/scripts/test-mini-preflight.sh
#
# Exit codes: 0 = all tests passed, 1 = one or more failures

set -uo pipefail

# Canonicalize so cd into sandboxes doesn't break invocation
SCRIPT="$(cd "$(dirname "$0")" && pwd)/mini-preflight.sh"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
pass() { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; FAILURES=$((FAILURES+1)); }

FAILURES=0

if [ ! -f "$SCRIPT" ]; then
    printf "${RED}FATAL:${NC} mini-preflight.sh not found at %s\n" "$SCRIPT" >&2
    exit 1
fi

echo "=== test-mini-preflight ==="
echo "Script: $SCRIPT"
echo ""

# ---- T1: syntax ----
echo "T1: syntax"
if bash -n "$SCRIPT"; then
    pass "bash -n clean"
else
    fail "bash -n reported syntax errors"
fi

# ---- Sandboxes ----
NONGIT_DIR=$(mktemp -d /tmp/claude-mini-preflight-nongit-XXXXXX)
REPO_DIR=$(mktemp -d /tmp/claude-mini-preflight-repo-XXXXXX)
trap 'rm -rf "$NONGIT_DIR" "$REPO_DIR"' EXIT

git -C "$REPO_DIR" init -q
mkdir -p "$REPO_DIR/session-log/2026/01"
# Fixed old date → days-away is large and deterministic (> 7)
touch "$REPO_DIR/session-log/2026/01/2026-01-01.md"
mkdir -p "$REPO_DIR/docs/decisions"
printf '# 0001. Test decision\n\n* Status: proposed\n* Date: 2026-01-01\n' \
    > "$REPO_DIR/docs/decisions/0001-test-decision.md"

# ---- T2: outside a git repo the section is absent ----
echo ""
echo "T2: non-git directory"
out=$(cd "$NONGIT_DIR" && bash "$SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "Что накопилось"; then
    fail "section printed outside a git repo"
else
    pass "section silently skipped outside a git repo"
fi

# ---- T3: days-since-last-session from session-log filename ----
echo ""
echo "T3: days-since-last-session math"
out=$(cd "$REPO_DIR" && bash "$SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "Что накопилось"; then
    pass "section header printed inside a git repo"
else
    fail "section header missing inside a git repo"
fi
if echo "$out" | grep -qE 'дн(ей|\.) с последней сессии \(2026-01-01\)'; then
    pass "days-away computed from session-log filename"
else
    fail "days-away line missing or malformed; got: $(echo "$out" | grep 'сесси' || echo '<none>')"
fi

# ---- T4: gh unusable (offline) → warn + same exit code as with working gh ----
# A broken-gh shim is prepended to PATH instead of stripping gh's directory:
# stripping the directory would also remove unrelated tools (claude, tailscale)
# and change the env-check half's exit code for reasons unrelated to gh.
echo ""
echo "T4: degradation with unusable gh (offline simulation)"
SHIM_DIR=$(mktemp -d /tmp/claude-mini-preflight-shim-XXXXXX)
trap 'rm -rf "$NONGIT_DIR" "$REPO_DIR" "$SHIM_DIR"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$SHIM_DIR/gh"
chmod +x "$SHIM_DIR/gh"
out=$(cd "$REPO_DIR" && PATH="$SHIM_DIR:$PATH" bash "$SCRIPT" 2>/dev/null) || true
if echo "$out" | grep -q "gh недоступен"; then
    pass "unusable gh degrades with warn"
else
    fail "gh-degradation warn missing; got: $(echo "$out" | tail -5 | tr '\n' ' ')"
fi
if echo "$out" | grep -qE 'Готов к сессии|блокирующих проблем'; then
    pass "script reaches final status line despite gh degradation (no mid-section crash)"
else
    fail "script did not reach final status line with broken gh"
fi
# Exit-code invariance is structural: the section must never touch the failed
# counter (a broken gh also fails the env-check half by design, so a black-box
# exit-code comparison cannot isolate the section's contribution).
if awk '/^report_accumulated\(\)/,/^\}/' "$SCRIPT" | grep -qw 'failed'; then
    fail "report_accumulated references the failed counter — section must be report-only"
else
    pass "report_accumulated never touches the failed counter (report-only invariant)"
fi

# ---- T5: proposed ADR listed with age ----
echo ""
echo "T5: proposed ADR listing"
out=$(cd "$REPO_DIR" && bash "$SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "proposed ADR: 0001-test-decision.md"; then
    pass "proposed ADR listed"
else
    fail "proposed ADR not listed; got: $(echo "$out" | grep -i adr || echo '<none>')"
fi

echo ""
echo "=== Summary ==="
if [ "$FAILURES" -eq 0 ]; then
    printf '%sAll tests passed%s\n' "$GREEN" "$NC"
    exit 0
else
    printf '%s%d test(s) failed%s\n' "$RED" "$FAILURES" "$NC"
    exit 1
fi
