#!/usr/bin/env bash
# deploy-bare.sh — acceptance of ADR-0031 (#314): a bare Claude session asked "deploy my harness for
# this project" deploys it by itself, and nothing around the project changes except Claude Code's
# own plugin registry entries for that project. Mode A: a throw-away HOME, authenticated with the
# subscription token (tools/port-run/lib/isolated-claude.sh). Runs locally, never in CI.
# Exit: 0 pass · 1 fail · 77 skipped (no subscription token).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null  # helper checked on its own
. "$REPO/tools/port-run/lib/isolated-claude.sh"
iso_require_token

# Temp projects live outside the repository, so no CLAUDE.md or AGENTS.md above them is loaded.
T=$(mktemp -d "${TMPDIR:-/tmp}/claude-mini-accept.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
d="$T"; while [ "$d" != / ]; do
    d=$(dirname "$d")
    { [ -e "$d/CLAUDE.md" ] || [ -e "$d/AGENTS.md" ]; } && { echo "  FAIL instructions file above the temp dir: $d"; exit 1; }
done
iso_home "$T"
FAIL=0
ok() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
check() {  # check <ok message> <fail message> <command...>
    local good="$1" bad="$2"; shift 2
    if "$@"; then ok "$good"; else fail "$bad"; fi
}
# shellcheck disable=SC2329  # called through check
same() { [ "$1" = "$2" ]; }
echo "candidate: $REPO @ $(git -C "$REPO" rev-parse --short HEAD)$(git -C "$REPO" diff --quiet HEAD || echo ' +uncommitted')"

snapshot() {  # snapshot <dir> <out>: path<TAB>sha256 of every file (.git excluded)
    python3 - "$1" > "$2" <<'PYEOF'
import hashlib, os, sys
root = sys.argv[1]
for d, dirs, files in os.walk(root):
    dirs[:] = sorted(x for x in dirs if x != ".git")
    for f in sorted(files):
        p = os.path.join(d, f)
        h = "link:" + os.readlink(p) if os.path.islink(p) else hashlib.sha256(open(p, "rb").read()).hexdigest()
        print(f"{os.path.relpath(p, root)}\t{h}")
PYEOF
}
commits() { git -C "$1" rev-list --count HEAD; }
session() {  # session <dir> <prompt> <out.jsonl> [extra args]
    local dir="$1" prompt="$2" out="$3"; shift 3
    (cd "$dir" && timeout 900 claude -p "$prompt" --output-format stream-json --verbose \
        --permission-mode acceptEdits --permission-prompts none "$@" > "$out" 2> "$out.err")
}
loaded() { iso_init "$1" | jq -e '[.plugins[]?.source] | any(startswith("claude-mini@"))' >/dev/null; }

for p in proj sibling; do
    mkdir -p "$T/$p" && git -C "$T/$p" init -q && git -C "$T/$p" commit -q --allow-empty -m "chore: start"
done
snapshot "$T/home" "$T/home.before"
snapshot "$T/proj" "$T/proj.before"; cp "$T/proj/.git/info/exclude" "$T/exclude.before" 2>/dev/null || : > "$T/exclude.before"
snapshot "$T/sibling" "$T/sibling.before"

echo "deploy"
session "$T/proj" "deploy my harness for this project. Harness: $REPO" "$T/deploy.jsonl" \
    --allowedTools "Read,Edit,Write,Bash(git *),Bash($REPO/setup/harness *),Bash(python3 $REPO/setup/harness *)" \
    --disallowedTools "Bash(git push *),Bash(gh *)"
echo "  session exit $?; transcript: $T/deploy.jsonl"

echo "(a) plugin loads in the project"
session "$T/proj" "Reply with: ok" "$T/a.jsonl"
if loaded "$T/a.jsonl"; then ok "claude-mini loaded"; else fail "claude-mini not loaded"; fi
if iso_init "$T/a.jsonl" | jq -e '(.plugin_errors // []) | length == 0' >/dev/null; then ok "no plugin errors"; else fail "plugin errors"; fi

echo "(b) the hook guards commits in the project"
n=$(commits "$T/proj")
session "$T/proj" "Run exactly this command and nothing else: git commit --allow-empty -m 'bad subject'" "$T/b1.jsonl" \
    --allowedTools "Bash(git commit:*)"
check "bad subject blocked" "bad subject committed" same "$(commits "$T/proj")" "$n"
session "$T/proj" "Run exactly this command and nothing else: git commit --allow-empty -m 'chore: good subject'" "$T/b2.jsonl" \
    --allowedTools "Bash(git commit:*)"
check "good subject committed" "good subject blocked" same "$(commits "$T/proj")" "$((n + 1))"

echo "(d) the sibling project does not see the harness"
n=$(commits "$T/sibling")
session "$T/sibling" "Run exactly this command and nothing else: git commit --allow-empty -m 'bad subject'" "$T/d.jsonl" \
    --allowedTools "Bash(git commit:*)"
if loaded "$T/d.jsonl"; then fail "claude-mini loaded in the sibling"; else ok "not loaded in the sibling"; fi
check "sibling commit not blocked" "sibling commit blocked" same "$(commits "$T/sibling")" "$((n + 1))"

echo "(e) HOME: only Claude Code's own state and this project's plugin entries changed"
snapshot "$T/home" "$T/home.after"
bad=$(diff <(sort "$T/home.before") <(sort "$T/home.after") | sed -n 's/^[<>] //p' | cut -f1 | sort -u \
    | grep -vE '^\.claude/' | grep -vE '^\.gitconfig$' || true)
check "nothing changed outside HOME/.claude" "changed outside HOME/.claude: $bad" same "$bad" ""
changed=$(diff <(sort "$T/home.before") <(sort "$T/home.after") | sed -n 's/^[<>] //p' | cut -f1 | grep -cx '.claude/settings.json')
check "HOME/.claude/settings.json untouched" "HOME/.claude/settings.json changed" same "$changed" 0
reg="$T/home/.claude/plugins/installed_plugins.json"
if [ -f "$reg" ] && jq -e --arg p "$T/proj" '[.. | objects | select(has("projectPath")) | .projectPath] | all(. == $p or (. | startswith($p)))' "$reg" >/dev/null; then
    ok "plugin registry entries name only this project"
else fail "plugin registry missing or names another project"; fi
snapshot "$T/sibling" "$T/sibling.after"
check "sibling files unchanged" "sibling files changed" cmp -s "$T/sibling.before" "$T/sibling.after"

echo "(f) the saved report has nothing Broken"
r=$(find "$T/proj/.claude/claude-mini/reports" -name '*.md' 2>/dev/null | sort | tail -1)
if [ -n "$r" ] && python3 - "$r" <<'PYEOF'
import sys
text = open(sys.argv[1]).read()
broken = text.split("\n## ", 1)[0]
sys.exit(0 if broken.strip().splitlines()[1:] in ([], ["- nothing"], ["- ничего"]) else 1)
PYEOF
then ok "Broken is empty ($r)"; else fail "report missing or Broken not empty"; fi

echo "(g) uninstall returns the project"
python3 "$REPO/setup/harness" uninstall --project "$T/proj" > "$T/uninstall.out" 2>&1 || fail "uninstall exit $?"
git -C "$T/proj" reset -q --hard HEAD~1  # drop the test's own good commit from (b)
snapshot "$T/proj" "$T/proj.after"
check "project files back to their bytes" "project files differ after uninstall" cmp -s "$T/proj.before" "$T/proj.after"
check "exclude file restored" "exclude file differs" cmp -s "$T/exclude.before" "$T/proj/.git/info/exclude"
if [ ! -f "$reg" ] || jq -e --arg p "$T/proj" '[.. | objects | select(has("projectPath")) | .projectPath] | all(. != $p)' "$reg" >/dev/null; then
    ok "no registry entry left for the project"
else fail "registry still names the project"; fi

[ "$FAIL" -eq 0 ] && echo "Acceptance passed." || echo "$FAIL failed; KEEP=1 keeps $T"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
