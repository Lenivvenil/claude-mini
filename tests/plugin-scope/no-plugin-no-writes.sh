#!/usr/bin/env bash
# no-plugin-no-writes.sh — the scope boundary of ADR-0031, observed rather than assumed (#311).
#
# In an isolated HOME the plugin is installed at --scope local for project A only. A Claude session
# in project B must then:
#   1. not list claude-mini in init.plugins, and have no claude-mini skills or agents;
#   2. not block a non-Conventional-Commits commit (the plugin hook must not fire), while the same
#      commit in project A is denied by the hook (the control: otherwise a model that does not run
#      the command would look like a hook that did not fire);
#   3. leave project A's tree byte-identical.
# Exit: 0 pass · 1 fail · 77 skipped (no subscription token, see tools/port-run/lib/isolated-claude.sh).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null  # helper checked on its own; path resolved at run time
. "$REPO/tools/port-run/lib/isolated-claude.sh"
iso_require_token

# Temp projects live outside the repository, so its AGENTS.md is not loaded into the sessions.
BASE="${PORT_RUN_TMP:-${TMPDIR:-/tmp}}"
T=$(mktemp -d "$BASE/claude-mini-no-plugin.XXXXXX") && [ -d "$T" ] && T=$(cd "$T" && pwd -P) && [ -n "$T" ] \
    || { echo "  FAIL cannot create a temp dir under $BASE"; exit 1; }
trap 'rm -rf "$T"' EXIT
d="$T"; while [ "$d" != / ]; do
    d=$(dirname "$d")
    { [ -e "$d/CLAUDE.md" ] || [ -e "$d/AGENTS.md" ]; } && { echo "  FAIL instructions file above the temp dir: $d"; exit 1; }
done
iso_home "$T"
FAIL=0
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
ok() { echo "  ok   $*"; }

tree_hash() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16); }

for p in A B; do
    mkdir -p "$T/$p" && git -C "$T/$p" init -q && echo "$p" > "$T/$p/readme.txt"
done
git -C "$T/A" add readme.txt
git -C "$T/B" add readme.txt
COMMIT_PROMPT="Run exactly this shell command and nothing else: git commit -m 'bad subject'"

# Install the plugin from this working tree for project A only.
(cd "$T/A" && claude plugin marketplace add --scope local "$REPO" >/dev/null 2>&1 \
    && claude plugin install claude-mini@claude-mini --scope local >/dev/null 2>&1) \
    || { echo "  FAIL could not install the plugin at local scope in project A"; exit 1; }

# Positive control: in A the plugin is loaded and its hook denies the commit B must let through.
(cd "$T/A" && timeout 300 claude -p "$COMMIT_PROMPT" \
    --output-format stream-json --verbose --permission-mode acceptEdits --permission-prompts none \
    --allowedTools "Bash(git commit:*)" > "$T/a.jsonl" 2>"$T/a.err")
if iso_init "$T/a.jsonl" | jq -e '[.plugins[]?.source] | any(startswith("claude-mini@"))' >/dev/null; then
    ok "control: claude-mini loaded in project A"
else
    echo "  FAIL control: claude-mini not loaded in project A — the test would be vacuous"; exit 1
fi
if grep -qF "commit subject is not Conventional Commits" "$T/a.jsonl" \
    && [ "$(git -C "$T/A" rev-list --count HEAD 2>/dev/null || echo 0)" = "0" ]; then
    ok "control: the hook denied the same commit in project A"
else
    echo "  FAIL control: no hook denial in project A — the commit check in B would be vacuous"; exit 1
fi
hash_a=$(tree_hash "$T/A")

(cd "$T/B" && timeout 300 claude -p "$COMMIT_PROMPT" \
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
