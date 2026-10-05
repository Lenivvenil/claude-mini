#!/usr/bin/env bash
# deploy-bare.sh — acceptance of ADR-0031 (#314): a bare Claude session asked "deploy my harness for
# this project" deploys it by itself, and nothing around the project changes except Claude Code's
# own plugin registry entries for that project.
# Mode A (default): a throw-away HOME, authenticated with the
# subscription token (tools/port-run/lib/isolated-claude.sh). Runs locally, never in CI.
# Mode B (MODE=B, owner go only, docs/port/PLAN.md §5.5): the owner's real HOME and login. HOME is
# too big to hash whole, so B compares the watch list of PLAN §4 T4 and the plugin registries entry
# by entry; entries of other projects (likec4) must stay byte-equal. Credential files: size and mtime.
# The owner's global hooks run too. A hook that rewrites commands (rtk turns `git commit` into
# `rtk git commit`, `ls` into `rtk ls`) changes what the permission rule sees: pass the rewritten
# forms in EXTRA_ALLOW, used by every session, e.g. EXTRA_ALLOW='Bash(rtk ls *),Bash(rtk git commit:*)'.
# Exit: 0 pass · 1 fail · 77 skipped (no subscription token).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null  # helper checked on its own
. "$REPO/tools/port-run/lib/isolated-claude.sh"
MODE="${MODE:-A}"
case "$MODE" in A) iso_require_token ;; B) ;; *) echo "MODE must be A or B" >&2; exit 2 ;; esac

# Temp projects live outside the repository, so no CLAUDE.md or AGENTS.md above them is loaded.
# Physical path: Claude Code records the project by it (/private/var on macOS), and the checks compare.
# Checked before the cleanup trap: an empty T would make the trap remove the current directory.
T=$(mktemp -d "${TMPDIR:-/tmp}/mach-accept.XXXXXX") && [ -d "$T" ] && T=$(cd "$T" && pwd -P) && [ -n "$T" ] \
    || { echo "  FAIL cannot create a temp dir under ${TMPDIR:-/tmp}"; exit 1; }
# A failed run keeps T: in mode B a failed uninstall leaves a registry entry that names it.
FAIL=0
trap '[ -n "${KEEP:-}" ] || [ "$FAIL" -ne 0 ] || rm -rf "$T"' EXIT
d="$T"; while [ "$d" != / ]; do
    d=$(dirname "$d")
    { [ -e "$d/CLAUDE.md" ] || [ -e "$d/AGENTS.md" ]; } && { echo "  FAIL instructions file above the temp dir: $d"; exit 1; }
done
[ "$MODE" = A ] && iso_home "$T"
ok() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
check() {  # check <ok message> <fail message> <command...>
    local good="$1" bad="$2"; shift 2
    if "$@"; then ok "$good"; else fail "$bad"; fi
}
# shellcheck disable=SC2329  # called through check
same() { [ "$1" = "$2" ]; }
echo "mode $MODE; candidate: $REPO @ $(git -C "$REPO" rev-parse --short HEAD)$(git -C "$REPO" diff --quiet HEAD || echo ' +uncommitted')"

snapshot() {  # snapshot <dir> <out> [dirs]: path<TAB>sha256 of every file (.git excluded); with
    # "dirs" also path/<TAB>dir for every directory, so one left behind empty fails the compare
    python3 - "$1" "${3:-}" > "$2" <<'PYEOF'
import hashlib, os, sys
root = sys.argv[1]
for d, dirs, files in os.walk(root):
    dirs[:] = sorted(x for x in dirs if x != ".git")
    if sys.argv[2] == "dirs" and d != root:
        print(f"{os.path.relpath(d, root)}/\tdir")
    for f in sorted(files):
        p = os.path.join(d, f)
        h = "link:" + os.readlink(p) if os.path.islink(p) else hashlib.sha256(open(p, "rb").read()).hexdigest()
        print(f"{os.path.relpath(p, root)}\t{h}")
PYEOF
}
# watch_state <out>: mode B's view of HOME. One line per watched path (sha256, or size+mtime for
# credential files) and one per registry entry that does not name this test's projects.
watch_state() {
    # a file it cannot read would give a cut snapshot, and two cut snapshots compare equal
    python3 - "$HOME" "$T" > "$1" <<'PYEOF' || { fail "cannot read the HOME watch list into $1"; exit 1; }
import hashlib, json, os, sys
home, t = sys.argv[1], sys.argv[2]
files = [".claude/settings.json", ".claude/CLAUDE.md", ".zshrc", ".zprofile", ".zshenv", ".bashrc",
         ".bash_profile", ".profile", ".gitconfig", ".config/git/ignore", ".codex/config.toml",
         "Projects/likec4/.claude"]
meta_only = [".codex/auth.json", ".config/gh/hosts.yml"]
def walk(rel):
    p = os.path.join(home, rel)
    if os.path.isdir(p) and not os.path.islink(p):
        for d, dirs, fs in os.walk(p):
            dirs.sort()
            for f in sorted(fs):
                yield os.path.relpath(os.path.join(d, f), home)
    else:
        yield rel
for rel in files:
    for r in walk(rel):
        p = os.path.join(home, r)
        if os.path.islink(p):
            print(f"{r}\tlink:{os.readlink(p)}")
        elif os.path.isfile(p):
            print(f"{r}\t{hashlib.sha256(open(p, 'rb').read()).hexdigest()}")
        else:
            print(f"{r}\tabsent")
for r in meta_only:
    p = os.path.join(home, r)
    st = os.stat(p) if os.path.exists(p) else None
    print(f"{r}\t" + (f"size={st.st_size} mtime={st.st_mtime_ns}" if st else "absent"))
reg = os.path.join(home, ".claude/plugins/installed_plugins.json")
plugins = json.load(open(reg)).get("plugins", {}) if os.path.exists(reg) else {}
for name in sorted(plugins):
    for e in plugins[name]:
        if not str(e.get("projectPath") or "").startswith(t):
            print(f"registry:{name}\t{json.dumps(e, sort_keys=True)}")
mk = os.path.join(home, ".claude/plugins/known_marketplaces.json")
for name, e in sorted((json.load(open(mk)) if os.path.exists(mk) else {}).items()):
    # lastUpdated moves when Claude Code refreshes a catalog by itself: session state, not deployment
    e = {k: v for k, v in e.items() if k != "lastUpdated"} if isinstance(e, dict) else e
    print(f"marketplace:{name}\t{json.dumps(e, sort_keys=True)}")
PYEOF
}
commits() { git -C "$1" rev-list --count HEAD; }
session() {  # session <dir> <prompt> <out.jsonl> [extra args]
    local dir="$1" prompt="$2" out="$3"; shift 3
    (cd "$dir" && timeout 900 claude -p "$prompt" --output-format stream-json --verbose \
        --permission-mode acceptEdits --permission-prompts none "$@" > "$out" 2> "$out.err")
}
loaded() { iso_init "$1" | jq -e '[.plugins[]?.source] | any(startswith("mach@"))' >/dev/null; }

for p in proj sibling; do
    mkdir -p "$T/$p" && git -C "$T/$p" init -q && git -C "$T/$p" commit -q --allow-empty -m "chore: start"
done
if [ "$MODE" = A ]; then snapshot "$T/home" "$T/home.before"; else watch_state "$T/home.before"; fi
snapshot "$T/proj" "$T/proj.before" dirs; cp "$T/proj/.git/info/exclude" "$T/exclude.before" 2>/dev/null || : > "$T/exclude.before"
snapshot "$T/sibling" "$T/sibling.before"

echo "deploy"
# The owner would answer the permission prompts; a headless run has nobody to ask. So the session
# gets what the owner grants: the clone as a readable working directory and the harness commands.
session "$T/proj" "deploy my harness for this project. Harness: $REPO" "$T/deploy.jsonl" \
    --add-dir "$REPO" \
    --allowedTools "Read,Glob,Grep,Edit,Write,Bash(ls *),Bash(git *),Bash($REPO/setup/harness *),Bash(python3 $REPO/setup/harness *)${EXTRA_ALLOW:+,$EXTRA_ALLOW}" \
    --disallowedTools "Bash(git push *),Bash(gh *)"
echo "  session exit $?; transcript: $T/deploy.jsonl"

echo "(a) plugin loads in the project"
session "$T/proj" "Reply with: ok" "$T/a.jsonl"
if loaded "$T/a.jsonl"; then ok "mach loaded"; else fail "mach not loaded"; fi
if iso_init "$T/a.jsonl" | jq -e '(.plugin_errors // []) | length == 0' >/dev/null; then ok "no plugin errors"; else fail "plugin errors"; fi

echo "(b) the hook guards commits in the project"
n=$(commits "$T/proj")
session "$T/proj" "Run exactly this command and nothing else: git commit --allow-empty -m 'bad subject'" "$T/b1.jsonl" \
    --allowedTools "Bash(git commit:*)${EXTRA_ALLOW:+,$EXTRA_ALLOW}"
check "bad subject blocked" "bad subject committed" same "$(commits "$T/proj")" "$n"
check "the hook's own reason is in the session" "no mach denial in the session (refusal or crash?)" \
    grep -q 'mach: commit subject is not Conventional Commits' "$T/b1.jsonl"
session "$T/proj" "Run exactly this command and nothing else: git commit --allow-empty -m 'chore: good subject'" "$T/b2.jsonl" \
    --allowedTools "Bash(git commit:*)${EXTRA_ALLOW:+,$EXTRA_ALLOW}"
check "good subject committed" "good subject blocked" same "$(commits "$T/proj")" "$((n + 1))"

echo "(d) the sibling project does not see the harness"
n=$(commits "$T/sibling")
session "$T/sibling" "Run exactly this command and nothing else: git commit --allow-empty -m 'bad subject'" "$T/d.jsonl" \
    --allowedTools "Bash(git commit:*)${EXTRA_ALLOW:+,$EXTRA_ALLOW}"
if loaded "$T/d.jsonl"; then fail "mach loaded in the sibling"; else ok "not loaded in the sibling"; fi
check "sibling commit not blocked" "sibling commit blocked" same "$(commits "$T/sibling")" "$((n + 1))"

if [ "$MODE" = A ]; then
    echo "(e) HOME: only Claude Code's own state, this project's plugin entries and the Codex scratch dir changed"
    # ADR-0032: the one path allowed outside ~/.claude besides p. 3 of ADR-0031. Codex creates its
    # per-run scratch dir there on `codex --version`; codex config and auth files still fail the check.
    CODEX_SCRATCH='^\.codex/tmp/arg0/'
    snapshot "$T/home" "$T/home.after"
    bad=$(diff <(sort "$T/home.before") <(sort "$T/home.after") | sed -n 's/^[<>] //p' | cut -f1 | sort -u \
        | grep -vE '^\.claude/' | grep -vE "$CODEX_SCRATCH" || true)
    check "nothing changed outside HOME/.claude" "changed outside HOME/.claude: $bad" same "$bad" ""
    changed=$(diff <(sort "$T/home.before") <(sort "$T/home.after") | sed -n 's/^[<>] //p' | cut -f1 | grep -cx '.claude/settings.json')
    check "HOME/.claude/settings.json untouched" "HOME/.claude/settings.json changed" same "$changed" 0
    reg="$T/home/.claude/plugins/installed_plugins.json"
    if [ -f "$reg" ] && jq -e --arg p "$T/proj" '[.. | objects | select(has("projectPath")) | .projectPath] | all(. == $p or (. | startswith($p)))' "$reg" >/dev/null; then
        ok "plugin registry entries name only this project"
    else fail "plugin registry missing or names another project"; fi
else
    echo "(e) real HOME: the watch list and other projects' registry entries unchanged"
    watch_state "$T/home.after"
    # this deployment may add its own marketplace entry (ADR-0031 §3); a change to one that existed
    # before is still a failure, and (g) compares everything after uninstall
    mkt=$(jq -r .name "$REPO/.claude-plugin/marketplace.json")
    added_own=""
    grep -q "^marketplace:$mkt	" "$T/home.before" || added_own="marketplace:$mkt"
    bad=$(diff "$T/home.before" "$T/home.after" | sed -n 's/^[<>] //p' | cut -f1 | sort -u \
        | grep -vxF "${added_own:-//none//}" || true)
    check "watch list and other registry entries unchanged" "changed: $bad" same "$bad" ""
    reg="$HOME/.claude/plugins/installed_plugins.json"
    if jq -e --arg p "$T/proj" '[.plugins[][] | select(.projectPath == $p)] | length > 0' "$reg" >/dev/null; then
        ok "the registry has an entry for this project"
    else fail "no registry entry for this project"; fi
fi
snapshot "$T/sibling" "$T/sibling.after"
check "sibling files unchanged" "sibling files changed" cmp -s "$T/sibling.before" "$T/sibling.after"

echo "(f) the saved report has nothing Broken"
r=$(find "$T/proj/.claude/mach/reports" -name '*.md' 2>/dev/null | sort | tail -1)
if [ -n "$r" ] && python3 - "$r" <<'PYEOF'
import sys
text = open(sys.argv[1]).read()
broken = text.split("\n## ")[1]  # [0] is the project header
sys.exit(0 if broken.strip().splitlines()[1:] in ([], ["- nothing"], ["- ничего"]) else 1)
PYEOF
then ok "Broken is empty ($r)"; else fail "report missing or Broken not empty"; fi

echo "(g) uninstall returns the project"
python3 "$REPO/setup/harness" uninstall --project "$T/proj" > "$T/uninstall.out" 2>&1 || fail "uninstall exit $?"
# drop the commits from (b), history only: files uninstall left behind stay visible to the snapshot
git -C "$T/proj" reset -q --soft "$(git -C "$T/proj" rev-list --max-parents=0 HEAD)"
snapshot "$T/proj" "$T/proj.after" dirs
check "project files back to their bytes" "project files differ after uninstall" cmp -s "$T/proj.before" "$T/proj.after"
check "exclude file restored" "exclude file differs" cmp -s "$T/exclude.before" "$T/proj/.git/info/exclude"
if [ ! -f "$reg" ] || jq -e --arg p "$T/proj" '[.. | objects | select(has("projectPath")) | .projectPath] | all(. != $p)' "$reg" >/dev/null; then
    ok "no registry entry left for the project"
else fail "registry still names the project"; fi

if [ "$MODE" = B ]; then
    watch_state "$T/home.final"
    check "watch list and registries as before the test" "differs after uninstall: $(diff "$T/home.before" "$T/home.final" | sed -n 's/^[<>] //p' | cut -f1 | sort -u | tr '\n' ' ')" \
        cmp -s "$T/home.before" "$T/home.final"
fi

[ "$FAIL" -eq 0 ] && echo "Acceptance passed." || echo "$FAIL failed; kept $T"
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
