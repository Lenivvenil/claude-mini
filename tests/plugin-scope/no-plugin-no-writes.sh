#!/usr/bin/env bash
# no-plugin-no-writes.sh — the scope boundary of ADR-0031, observed rather than assumed (#311).
#
# In an isolated HOME the plugin is installed at --scope local for project A only. A Claude session
# in project B must then:
#   1. not list claude-mini in init.plugins, and have no claude-mini skills or agents;
#   2. not block a non-Conventional-Commits commit (the plugin hook must not fire);
#   3. leave project A's tree byte-identical.
# Exit: 0 pass · 1 fail · 77 skipped (no subscription token, see tools/port-run/lib/isolated-claude.sh).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null  # helper checked on its own; path resolved at run time
. "$REPO/tools/port-run/lib/isolated-claude.sh"
iso_require_token

BASE="${PORT_RUN_TMP:-$REPO/.port-run/tmp}"
mkdir -p "$BASE"
T=$(mktemp -d "$BASE/no-plugin.XXXXXX")
trap 'rm -rf "$T"' EXIT
iso_home "$T"
FAIL=0
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
ok() { echo "  ok   $*"; }

tree_hash() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16); }

for p in A B; do
    mkdir -p "$T/$p" && git -C "$T/$p" init -q && echo "$p" > "$T/$p/readme.txt"
done
git -C "$T/B" add readme.txt

# Install the plugin from this working tree for project A only.
(cd "$T/A" && claude plugin marketplace add --scope local "$REPO" >/dev/null 2>&1 \
    && claude plugin install claude-mini@claude-mini --scope local >/dev/null 2>&1) \
    || { echo "  FAIL could not install the plugin at local scope in project A"; exit 1; }
hash_a=$(tree_hash "$T/A")

# Positive control: the plugin really is loaded in A, otherwise the checks in B prove nothing.
(cd "$T/A" && timeout 300 claude -p "Reply with exactly: ok" --output-format stream-json --verbose \
    > "$T/a.jsonl" 2>"$T/a.err")
if iso_init "$T/a.jsonl" | jq -e '[.plugins[]?.source] | any(startswith("claude-mini@"))' >/dev/null; then
    ok "control: claude-mini loaded in project A"
else
    echo "  FAIL control: claude-mini not loaded in project A — the test would be vacuous"; exit 1
fi
hash_a=$(tree_hash "$T/A")

(cd "$T/B" && timeout 300 claude -p "Run exactly this shell command and nothing else: git commit -m 'bad subject'" \
    --output-format stream-json --verbose --permission-mode acceptEdits --permission-prompts none \
    --allowedTools "Bash(git commit:*)" > "$T/b.jsonl" 2>"$T/b.err")
init=$(iso_init "$T/b.jsonl")
[ -n "$init" ] || { echo "  FAIL no init message; stderr: $(tail -3 "$T/b.err")"; exit 1; }

if printf '%s' "$init" | jq -e '[.plugins[]?.source] | any(startswith("claude-mini@"))' >/dev/null; then
    fail "claude-mini is loaded in project B"
else ok "claude-mini not loaded in project B"; fi
if printf '%s' "$init" | jq -e '[(.skills // [])[], (.agents // [])[]] | any(startswith("claude-mini:"))' >/dev/null; then
    fail "claude-mini skills or agents visible in project B"
else ok "no claude-mini skills or agents in project B"; fi
if [ "$(git -C "$T/B" rev-list --count HEAD 2>/dev/null || echo 0)" = "1" ]; then
    ok "non-CC commit went through in project B (hook did not fire)"
else fail "commit did not happen in project B (hook fired or the session failed)"; fi
if [ "$(tree_hash "$T/A")" = "$hash_a" ]; then ok "project A unchanged"; else fail "project A changed"; fi

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
