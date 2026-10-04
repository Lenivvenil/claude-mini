#!/usr/bin/env bash
# tests/setup/run.sh — setup/harness, machine layer and the crash-safe file primitive
# (docs/port/PLAN.md §4 T1–T6, T8, T10; #313).
#
# Runs with PATH limited to a shim directory: python3 and git are the real programs, everything
# else (jq, gh, claude, codex, node, brew, apt-get, sudo) is a fake whose answers come from
# $T/state. HOME is a temp directory. Nothing outside $T is written.
# Exit 0 = all passed.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1  # no __pycache__ in the repository

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
H="$REPO/setup/harness"
BASE="${PORT_RUN_TMP:-$REPO/.port-run/tmp}"
mkdir -p "$BASE"
T=$(mktemp -d "$BASE/setup.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
FAIL=0
ok() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
is() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 — got '$1', expected '$2'"; fi; }
has() { if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else fail "$3 — '$2' not in output"; fi; }

PY=$(command -v python3); GIT=$(command -v git)
SHIM="$T/bin"; STATE="$T/state"
mkdir -p "$SHIM" "$STATE" "$T/home"
ln -s "$PY" "$SHIM/python3"; ln -s "$GIT" "$SHIM/git"

# Fakes use shell builtins only (PATH holds nothing else) and absolute /bin/cp, /bin/rm.
# A fake answers --version with "<name> <state/<name>.ver or 1.0.0>" and "auth|login status"
# with the exit code in state/<name>.auth (default 0).
cat > "$T/proto" <<EOF
#!/bin/sh
n=\${0##*/}; v=1.0.0; a=0
[ -f "$STATE/\$n.ver" ] && read -r v < "$STATE/\$n.ver"
[ -f "$STATE/\$n.auth" ] && read -r a < "$STATE/\$n.auth"
echo "\$n \$1 \${GH_TELEMETRY-unset}" >> "$T/probe.log"
case "\$1" in --version) echo "\$n \$v" ;; auth|login) exit "\$a" ;; esac
exit 0
EOF
/bin/chmod +x "$T/proto"
fake() { /bin/cp "$T/proto" "$SHIM/$1"; }
# Package managers: log every call; install copies the fake in, uninstall removes it.
cat > "$SHIM/brew" <<EOF
#!/bin/sh
echo "brew \$*" >> "$T/pm.log"
case "\$1" in
  install) [ -f "$STATE/fail-install" ] && exit 1; [ -f "$STATE/\$2.installed" ] && exit 0
           /bin/cp "$T/proto" "$SHIM/\$2" ;;
  uninstall) /bin/rm -f "$SHIM/\$2" "$STATE/\$2.installed" ;;
  list) [ -f "$STATE/pm-broken" ] && exit 2
        { [ -x "$SHIM/\$3" ] || [ -f "$STATE/\$3.installed" ]; } && echo "\$3 1.0" && exit 0; exit 1 ;;
esac
EOF
cat > "$SHIM/dpkg-query" <<EOF
#!/bin/sh
[ -f "$STATE/pm-broken" ] && exit 2
{ [ -x "$SHIM/\$3" ] || [ -f "$STATE/\$3.installed" ]; } && echo "installed" && exit 0
exit 1
EOF
cat > "$SHIM/apt-get" <<EOF
#!/bin/sh
echo "apt-get \$*" >> "$T/pm.log"
case "\$1" in
  install) [ -f "$STATE/fail-install" ] && exit 1; [ -f "$STATE/\$3.installed" ] && exit 0
           /bin/cp "$T/proto" "$SHIM/\$3" ;;
  remove) /bin/rm -f "$SHIM/\$3" "$STATE/\$3.installed" ;;
esac
EOF
printf '#!/bin/sh\nexec "$@"\n' > "$SHIM/sudo"
chmod +x "$SHIM/brew" "$SHIM/apt-get" "$SHIM/sudo" "$SHIM/dpkg-query"
for b in jq gh codex node; do fake "$b"; done
# Fake claude: --version, auth status, the four plugin commands setup uses and the two --json lists.
# Like Claude Code, it keeps one machine-wide registry ($STATE/claude.registry.json): marketplaces and
# installs with their project, and removing a marketplace uninstalls its plugins in every project. It edits
# <cwd>/.claude/settings.local.json the way Claude Code does and leaves empty objects on removal.
cat > "$SHIM/claude" <<EOF
#!$PY
import json, os, sys
a = sys.argv[1:]
open("$T/claude.log", "a").write(" ".join(a) + "\\n")
if a[:1] == ["--version"]:
    print("2.1.283 (Claude Code)"); sys.exit(0)
if a[:2] == ["auth", "status"]:
    sys.exit(int(open("$STATE/claude.auth").read()) if os.path.exists("$STATE/claude.auth") else 0)
R = "$STATE/claude.registry.json"
reg = json.load(open(R)) if os.path.exists(R) else {"mkts": [], "installs": []}
here = os.path.realpath(os.getcwd())
def save_reg(): json.dump(reg, open(R, "w"))
if a[:4] == ["plugin", "marketplace", "list", "--json"]:
    if os.path.exists("$STATE/claude.fail-list"): sys.exit(1)
    print(json.dumps([{"name": m} for m in reg["mkts"]])); sys.exit(0)
if a[:3] == ["plugin", "list", "--json"]:
    if os.path.exists("$STATE/claude.fail-list"): sys.exit(1)
    print(json.dumps(reg["installs"])); sys.exit(0)
p = os.path.join(os.getcwd(), ".claude", "settings.local.json")
d = json.load(open(p)) if os.path.exists(p) else {}
if a[:3] == ["plugin", "marketplace", "add"]:
    src = a[-1]; name = json.load(open(os.path.join(src, ".claude-plugin", "marketplace.json")))["name"]
    d.setdefault("extraKnownMarketplaces", {})[name] = {"source": {"source": "directory", "path": src}}
    if name not in reg["mkts"]: reg["mkts"].append(name)
elif a[:2] == ["plugin", "install"]:
    if os.path.exists("$STATE/claude.fail-install"): sys.exit(1)
    if a[2].split("@")[1] not in d.get("extraKnownMarketplaces", {}): sys.exit(1)
    d.setdefault("enabledPlugins", {})[a[2]] = True
    reg["installs"].append({"id": a[2], "scope": "local", "projectPath": here})
elif a[:2] == ["plugin", "uninstall"]:
    if os.path.exists("$STATE/claude.fail-uninstall"): sys.exit(1)
    d.setdefault("enabledPlugins", {}).pop(a[2], None)
    reg["installs"] = [e for e in reg["installs"] if not (e["id"] == a[2] and e["projectPath"] == here)]
elif a[:3] == ["plugin", "marketplace", "remove"]:
    if os.path.exists("$STATE/claude.fail-mkt-remove-once"):
        os.unlink("$STATE/claude.fail-mkt-remove-once"); sys.exit(1)
    d.setdefault("extraKnownMarketplaces", {}).pop(a[3], None)
    reg["mkts"] = [m for m in reg["mkts"] if m != a[3]]
    reg["installs"] = [e for e in reg["installs"] if not e["id"].endswith("@" + a[3])]
else:
    sys.exit(0)
save_reg()
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
EOF
chmod +x "$SHIM/claude"
echo 22.14.0 > "$STATE/node.ver"

CHECKLIST='"checklist":{"items":[
 {"id":"git","layer":"machine","handler":"binary-version","binary":"git"},
 {"id":"jq","layer":"machine","handler":"binary-version","binary":"jq","packages":{"brew":"jq","apt":"jq"}},
 {"id":"gh-auth","layer":"machine","handler":"auth-status","tool":"gh"},
 {"id":"codex","layer":"machine","handler":"binary-version","binary":"codex","applies_if":"codex.enabled","optional":true,"purpose":"second opinion"},
 {"id":"node","layer":"machine","handler":"binary-version","binary":"node","min_version":"22.13","applies_if":"codeburn.enabled","optional":true,"manual":"install node by hand"}
]}'
project() {  # project <name> [extra top-level JSON members]
    local d="$T/$1"
    mkdir -p "$d/.claude" && "$GIT" -C "$d" init -q
    printf '{"schema_version":1,%s%s}\n' "$CHECKLIST" "${2:+,$2}" > "$d/.claude/mach.json"
    echo "$d"
}
tree_hash() {  # every path under $1 (.git excluded): type, mode, link target, content
    "$PY" - "$1" <<'PYEOF'
import hashlib, os, stat, sys
root, h = sys.argv[1], hashlib.sha256()
for d, dirs, files in os.walk(root):
    dirs[:] = sorted(x for x in dirs if not (d == root and x == ".git"))
    for name in sorted(dirs + files):
        p = os.path.join(d, name); st = os.lstat(p); rel = os.path.relpath(p, root)
        h.update(f"{rel}\0{stat.S_IFMT(st.st_mode)}\0{stat.S_IMODE(st.st_mode)}\0".encode())
        if stat.S_ISLNK(st.st_mode):
            h.update(os.readlink(p).encode())
        elif stat.S_ISREG(st.st_mode):
            h.update(open(p, "rb").read())
print(h.hexdigest())
PYEOF
}
run() {  # run <args...> ; sets OUT and RC (FAULT=<point> injects a crash, see setup/lib/txn.py)
    OUT=$(cd "$T" && env -i PATH="$SHIM" HOME="$T/home" ${FAULT:+MACH_SETUP_FAULT=$FAULT} "$PY" "$H" "$@" 2>&1); RC=$?
}

# T4 watch list: a sibling project and the files setup must never touch.
mkdir -p "$T/home/.claude" "$T/home/.config/git" "$T/sibling/.claude"
echo 'export A=1' > "$T/home/.zshrc"; echo '[user]' > "$T/home/.gitconfig"
echo '{}' > "$T/home/.claude/settings.json"; echo 'x' > "$T/home/.config/git/ignore"
echo '{}' > "$T/sibling/.claude/settings.json"
watch_before=$(tree_hash "$T/home")$(tree_hash "$T/sibling")

echo "T1 ready host"
p=$(project ready)
h0=$(tree_hash "$p")
run assess --project "$p" --json
is "$RC" 0 "assess exits 0"
is "$(printf '%s' "$OUT" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["delta"])')" "[]" "delta is empty"
run apply --project "$p"
is "$RC" 0 "apply on a ready host exits 0"
is "$(tree_hash "$p")" "$h0" "assess and apply wrote nothing"
is "$([ -e "$T/pm.log" ] && echo called || echo none)" none "no package manager call"

echo "T6 assess --json"
run assess --project "$p" --json
if printf '%s' "$OUT" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
assert d["schema"] == 1 and isinstance(d["delta"], list), "top-level keys"
for r in d["items"]:
    assert r["status"] in ("ready","missing","wrong-version","not-applicable","needs-manual"), r
    for k in ("id","layer","handler","status","detail","optional","fix","rollback","check"):
        assert k in r, (k, r)
'; then ok "json has the documented keys and statuses"; else fail "json shape"; fi

echo "T3 system install without consent"
rm -f "$SHIM/jq"
p=$(project noconsent)
h0=$(tree_hash "$p")
run apply --project "$p"
is "$RC" 3 "apply exits 3 when jq needs consent"
has "$OUT" "--allow-system jq" "report names the consent flag"
is "$(tree_hash "$p")" "$h0" "nothing written in the project"
is "$([ -e "$T/pm.log" ] && echo called || echo none)" none "package manager not called"
run apply --project "$p" --allow-system gh-auth
is "$RC" 2 "consent for a non-installable item is a usage error"
run apply --project "$p" --allow-system nope
is "$RC" 2 "consent for an unknown item is a usage error"
run apply --project "$p" --allow-system jq --dry-run
is "$RC" 0 "dry run with consent exits 0"
has "$OUT" "would run:" "dry run names the install it would do"
is "$(tree_hash "$p")" "$h0" "dry run writes nothing"
is "$([ -e "$T/pm.log" ] && echo called || echo none)" none "dry run calls no package manager"

echo "T2 apply with consent, then again"
p=$(project consent)
run apply --project "$p" --allow-system jq
is "$RC" 0 "apply --allow-system jq exits 0"
is "$([ -x "$SHIM/jq" ] && echo yes)" yes "jq installed"
has "$(cat "$T/pm.log")" "install" "package manager install was called"
has "$OUT" "report saved" "a report is saved when something changed"
h1=$(tree_hash "$p"); calls=$(wc -l < "$T/pm.log")
run apply --project "$p" --allow-system jq
is "$RC" 0 "the same apply again exits 0"
is "$(tree_hash "$p")" "$h1" "second apply writes nothing"
is "$(wc -l < "$T/pm.log")" "$calls" "second apply calls no package manager"

echo "T5 uninstall only what setup installed"
run uninstall --project "$p"
has "$OUT" "harness uninstall --item jq" "uninstall without --item lists the install"
is "$(wc -l < "$T/pm.log")" "$calls" "uninstall without --item changes nothing"
run uninstall --project "$p" --item git
is "$RC" 2 "a package setup did not install is refused"
run uninstall --project "$p" --item jq
is "$RC" 0 "uninstall --item jq exits 0"
is "$([ -e "$SHIM/jq" ] && echo present || echo gone)" gone "jq removed"
run uninstall --project "$p" --item jq
is "$RC" 2 "a second uninstall of jq is refused"

echo "failed install"
touch "$STATE/fail-install"
p=$(project failing)
run apply --project "$p" --allow-system jq
is "$RC" 4 "a failed install exits 4"
has "$OUT" "exit 1" "Broken names the command and its exit"
rm -f "$STATE/fail-install"
fake jq

echo "T10 reduced mode and manual items"
rm -f "$SHIM/codex"
p=$(project reduced '"codeburn":{"enabled":true,"version":""}')
echo 20.1.0 > "$STATE/node.ver"
echo 1 > "$STATE/gh.auth"
run apply --project "$p"
is "$RC" 0 "missing optional codex and old node: apply exits 0"
has "$OUT" "reduced mode: second opinion" "report names the reduced capability"
has "$OUT" "node 20.1.0 < 22.13" "old node is wrong-version"
has "$OUT" "gh auth login" "gh login is a manual step with its command"
run verify --project "$p"
is "$RC" 5 "verify exits 5 while gh is not logged in"
echo 0 > "$STATE/gh.auth"
run verify --project "$p"
is "$RC" 0 "verify exits 0 when only optional items are not ready"
p=$(project off '"codex":{"enabled":false,"modes":["base"]}')
run assess --project "$p" --json
is "$(printf '%s' "$OUT" | "$PY" -c 'import json,sys; print([r["status"] for r in json.load(sys.stdin)["items"] if r["id"]=="codex"][0])')" \
   not-applicable "a disabled capability is not-applicable, not missing"
fake codex; echo 22.14.0 > "$STATE/node.ver"

echo "probes leave no gh state outside the project"
gh_probes=$(grep '^gh ' "$T/probe.log")
is "$(printf '%s\n' "$gh_probes" | grep -cv ' 0$')" 0 "every gh probe runs with GH_TELEMETRY=0 ($(printf '%s\n' "$gh_probes" | grep -c .) probes)"

echo "probe failures and ownership"
printf '#!/bin/sh\nexit 1\n' > "$SHIM/jq"; chmod +x "$SHIM/jq"
p=$(project brokenjq)
run verify --project "$p"
is "$RC" 5 "a program whose --version fails is not ready"
has "$OUT" "--version\` failed" "the report says the probe failed"
fake jq
rm -f "$SHIM/node"; echo 20.1.0 > "$STATE/node.ver"
p=$(project oldpkg)
printf '{"schema_version":1,"checklist":{"items":[{"id":"node2","layer":"machine","handler":"binary-version","binary":"node","min_version":"22.13","packages":{"brew":"node","apt":"node"}}]}}\n' > "$p/.claude/mach.json"
run apply --project "$p" --allow-system node2
is "$RC" 4 "installed but too old: apply exits 4"
has "$OUT" "installed by setup; remove with: harness uninstall --item node2" "Broken says setup owns it"
run uninstall --project "$p" --item node2
is "$RC" 0 "the package setup installed can be removed although it failed the check"
fake node; echo 22.14.0 > "$STATE/node.ver"

echo "interrupted install is reconciled"
p=$(project interrupted)
mkdir -p "$p/.claude/mach" && : > "$p/.claude/mach/.mach-run"
mgr=brew; [ "$(uname)" = Linux ] && mgr=apt
printf '{"op":"install","item":"jq","path":null,"manager":"%s","package":"jq","state":"started","present_before":false}\n' "$mgr" > "$p/.claude/mach/intent.jsonl"
run apply --project "$p"
is "$RC" 0 "apply closes the open install and exits 0"
has "$OUT" "closed as done" "the report names the reconciliation"
run uninstall --project "$p"
has "$OUT" "harness uninstall --item jq" "the reconciled install is owned by setup"
p=$(project interrupted2)
mkdir -p "$p/.claude/mach" && : > "$p/.claude/mach/.mach-run"
printf '{"op":"install","item":"jq","path":null,"manager":"%s","package":"jq","state":"started"}\n' "$mgr" > "$p/.claude/mach/intent.jsonl"
run apply --project "$p"
has "$OUT" "closed as not done" "without proof of absence before, the install is not claimed"

echo "a package that was already there is never taken over"
rm -f "$SHIM/jq"; touch "$STATE/jq.installed"
p=$(project preexisting)
run apply --project "$p" --allow-system jq
is "$RC" 4 "installed-but-not-on-PATH package: apply exits 4"
has "$OUT" "is installed but its program is not on PATH" "Broken explains why"
run uninstall --project "$p" --item jq
is "$RC" 2 "and setup refuses to remove it"
rm -f "$STATE/jq.installed"; fake jq

echo "an unreadable package state keeps the operation open"
p=$(project pmbroken)
mkdir -p "$p/.claude/mach" && : > "$p/.claude/mach/.mach-run"
printf '{"op":"uninstall","item":"jq","path":null,"manager":"%s","package":"jq","state":"started"}\n' "$mgr" > "$p/.claude/mach/intent.jsonl"
touch "$STATE/pm-broken"
run apply --project "$p"
is "$RC" 4 "a failed package query is Broken, exit 4"
has "$OUT" "cannot tell its state" "and says so"
is "$(grep -c '"state"' "$p/.claude/mach/intent.jsonl")" 1 "the interrupted record stays open"
rm -f "$STATE/pm-broken"

echo "symlinks cannot lead writes outside the project"
rm -f "$SHIM/jq"
p=$(project linklog)
mkdir -p "$p/.claude/mach"; : > "$T/outside.log"
ln -s "$T/outside.log" "$p/.claude/mach/intent.jsonl"
run apply --project "$p" --allow-system jq
is "$RC" 1 "a symlinked intent log is refused"
is "$(wc -c < "$T/outside.log" | tr -d ' ')" 0 "the file outside is untouched"
p=$(project linkreports)
mkdir -p "$p/.claude/mach" "$T/outside-reports"
ln -s "$T/outside-reports" "$p/.claude/mach/reports"
run apply --project "$p" --allow-system jq
is "$(find "$T/outside-reports" -mindepth 1 | wc -l | tr -d ' ')" 0 "a symlinked reports directory gets no report"
p=$(project linkrun)
mkdir -p "$T/outside-run"; ln -s "$T/outside-run" "$p/.claude/mach"
run apply --project "$p" --allow-system jq
is "$RC" 1 "a symlinked run directory is refused"
is "$(find "$T/outside-run" -mindepth 1 | wc -l | tr -d ' ')" 0 "nothing written through it"
fake jq

echo "one run at a time"
rm -f "$SHIM/jq"
p=$(project locked)
mkdir -p "$p/.claude/mach" && : > "$p/.claude/mach/.mach-run"
"$PY" -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(20)' \
    "$p/.claude/mach/lock" "$T/locked.ready" &
holder=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$T/locked.ready" ] && break; sleep 0.5; done
run apply --project "$p" --allow-system jq
is "$RC" 1 "a second apply while one holds the lock exits 1"
has "$OUT" "holds the lock" "and says why"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
fake jq

echo "config and usage errors"
p=$(project badcfg)
printf '{"schema_version":1,"checklist":{"items":[{"id":"x","layer":"machine","handler":"shell"}]}}\n' > "$p/.claude/mach.json"
run assess --project "$p"
is "$RC" 1 "an unknown handler in config exits 1"
run frobnicate
is "$RC" 2 "an unknown command exits 2"

echo "T8 crash-safe file primitive"
p=$(project txn)
t8() {  # t8 <fault point> -> runs one write under the fault, then recovery in a new process
    env MACH_SETUP_FAULT="$1" "$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
t = txn.Txn(sys.argv[2], ".claude/mach")
t.write_file("demo", "target.txt", b"new\n")
PYEOF
    echo "exit $?"
}
recover() {
    "$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
t = txn.Txn(sys.argv[2], ".claude/mach")
rec, broken = t.recover()
print(len(rec), len(broken))
PYEOF
}
for point in after-intent before-swap after-swap; do
    printf 'old\n' > "$p/target.txt"
    is "$(t8 "$point")" "exit 99" "$point: the process died at the fault"
    is "$(recover)" "1 0" "$point: recovery resolved one interrupted change"
    is "$(cat "$p/target.txt")" "old" "$point: target is byte-identical to the original"
    is "$(find "$p" -maxdepth 1 -name '.*mach-*.tmp' | wc -l | tr -d ' ')" 0 "$point: no temp file left"
done
printf 'old\n' > "$p/target.txt"
is "$(t8 after-done)" "exit 99" "after-done: died after the change was recorded"
is "$(recover)" "0 0" "after-done: nothing to recover"
is "$(cat "$p/target.txt")" "new" "after-done: the finished change stays"
printf 'old\n' > "$p/target.txt"; printf 'keep\n' > "$p/target.txt.mach-restore"
t8 after-swap >/dev/null; recover >/dev/null
is "$(cat "$p/target.txt.mach-restore")" "keep" "recovery never overwrites an unrelated file"
is "$(cat "$p/target.txt")" "old" "and still restores the target"
rm -f "$p/fresh.txt"
env MACH_SETUP_FAULT=after-swap "$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
txn.Txn(sys.argv[2], ".claude/mach").write_file("demo", "fresh.txt", b"x\n")
PYEOF
recover >/dev/null
is "$([ -e "$p/fresh.txt" ] && echo present || echo absent)" absent "a new file interrupted after the swap is removed"
printf 'old\n' > "$p/target.txt"
"$PY" - "$REPO/setup/lib" "$p" <<'PYEOF' || true
import sys; sys.path.insert(0, sys.argv[1]); import txn
try:
    txn.Txn(sys.argv[2], ".claude/mach").write_file("demo", "target.txt", b"bad\n", validate=lambda p: "rejected")
except txn.TxnError:
    pass
PYEOF
is "$(cat "$p/target.txt")" "old" "a rejected candidate leaves the target unchanged"
out=$("$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
try:
    txn.Txn(sys.argv[2], ".claude/mach").write_file("demo", "../escape.txt", b"x")
    print("written")
except txn.TxnError:
    print("refused")
PYEOF
)
is "$out" refused "a path outside the project is refused"
is "$([ -e "$T/escape.txt" ] && echo present || echo absent)" absent "nothing written outside the project"

echo "project layer"
PROJECT_ITEMS='"checklist":{"items":[
 {"id":"git-exclude","layer":"project","handler":"git-exclude","patterns":[".claude/settings.local.json",".claude/mach/"]},
 {"id":"plugin","layer":"project","handler":"plugin-local"}]}'
pproject() {  # a project whose override holds only the project items
    local d="$T/$1"
    mkdir -p "$d/.claude" && "$GIT" -C "$d" init -q
    printf '{"schema_version":1,%s}\n' "$PROJECT_ITEMS" > "$d/.claude/mach.json"
    echo "$d"
}
full_hash() { echo "$(tree_hash "$1") $(cksum < "$1/.git/info/exclude" 2>/dev/null)"; }
p=$(pproject proj)
h0=$(full_hash "$p")
run apply --project "$p"
is "$RC" 0 "apply sets up the project layer"
is "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["enabledPlugins"]["mach@mach"])' "$p/.claude/settings.local.json")" \
   True "plugin enabled in the project's local settings"
has "$(cat "$p/.git/info/exclude")" ".claude/mach/" "exclude file lists setup's state"
h1=$(full_hash "$p"); calls=$(wc -l < "$T/claude.log")
run apply --project "$p"
is "$RC" 0 "second apply exits 0"
is "$(full_hash "$p")" "$h1" "second apply writes nothing"
is "$(wc -l < "$T/claude.log")" "$calls" "second apply runs no claude plugin command"
run verify --project "$p" --layer project
is "$RC" 0 "verify passes"
run uninstall --project "$p"
is "$RC" 0 "uninstall exits 0"
is "$(full_hash "$p")" "$h0" "T9: after uninstall the project and its exclude file are byte-identical"

p=$(pproject keepsettings)
printf '{\n  "permissions": {"allow": ["Bash(ls)"]}\n}\n' > "$p/.claude/settings.local.json"
h0=$(full_hash "$p")
run apply --project "$p"; run uninstall --project "$p"
is "$(full_hash "$p")" "$h0" "existing local settings come back byte for byte"

p=$(pproject disabledbefore)
printf '{\n  "enabledPlugins": {"mach@mach": false}\n}\n' > "$p/.claude/settings.local.json"
h0=$(full_hash "$p")
run apply --project "$p"; run uninstall --project "$p"
is "$(full_hash "$p")" "$h0" "a plugin entry that was false before setup comes back as false"

p=$(pproject declaredbefore)
printf '{"extraKnownMarketplaces": {"mach": {"source": {"source": "directory", "path": "%s"}}}}\n' "$REPO" > "$p/.claude/settings.local.json"
run apply --project "$p"
"$PY" - "$p/.claude/settings.local.json" <<'EOP'
import json, sys
d = json.load(open(sys.argv[1])); d["extraKnownMarketplaces"]["mach"]["note"] = "mine"; json.dump(d, open(sys.argv[1], "w"))
EOP
run uninstall --project "$p"
is "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["extraKnownMarketplaces"]["mach"].get("note"))' "$p/.claude/settings.local.json")" \
   mine "a user edit to a marketplace declared before setup survives uninstall"

p=$(pproject npmcache)
h0=$(full_hash "$p")
run apply --project "$p"
mkdir -p "$p/.claude/mach/npm-cache/_npx" && echo x > "$p/.claude/mach/npm-cache/_npx/pkg"
run uninstall --project "$p"
is "$RC" 0 "uninstall exits 0 with the npm cache of project-health in the run directory"
is "$(full_hash "$p")" "$h0" "and removes the run directory with the cache"

p=$(pproject disabledplusedit)
printf '{\n  "enabledPlugins": {"mach@mach": false}\n}\n' > "$p/.claude/settings.local.json"
run apply --project "$p"
"$PY" - "$p/.claude/settings.local.json" <<'EOP'
import json, sys
d = json.load(open(sys.argv[1])); d["permissions"] = {"allow": ["Bash(ls)"]}; json.dump(d, open(sys.argv[1], "w"))
EOP
run uninstall --project "$p"
is "$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("permissions"))' "$p/.claude/settings.local.json")" \
   "{'allow': ['Bash(ls)']}" "a user edit after apply keeps the local settings as they are"

p=$(pproject useredit)
run apply --project "$p"
echo "my-own-line" >> "$p/.git/info/exclude"
run uninstall --project "$p"
has "$(cat "$p/.git/info/exclude")" "my-own-line" "T11: a user edit after apply survives uninstall"
has "$OUT" "was edited after setup; left as is" "and uninstall says so"
is "$([ -d "$p/.claude/mach" ] && echo kept)" kept "the log is kept while something is left undone"

echo "a marketplace shared with another project"
# Claude Code's marketplace list is machine-wide: removing it from one project uninstalled the
# plugin in every other project (seen on a real machine). Uninstall must leave it to the others.
mkts() { "$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["mkts"]) or "-")' "$STATE/claude.registry.json"; }
users() { "$PY" -c 'import json,os,sys; print(" ".join(sorted(os.path.basename(e["projectPath"]) for e in json.load(open(sys.argv[1]))["installs"])) or "-")' "$STATE/claude.registry.json"; }
rm -f "$STATE/claude.registry.json"
pa=$(pproject shared-a); pb=$(pproject shared-b)
ha0=$(full_hash "$pa"); hb0=$(full_hash "$pb")
run apply --project "$pa"; run apply --project "$pb"
is "$(users)" "shared-a shared-b" "both projects have the plugin"
run uninstall --project "$pa"
is "$RC" 0 "uninstall of the first project exits 0"
is "$(users)" "shared-b" "the other project keeps its plugin"
is "$(mkts)" "mach" "the marketplace stays while another project uses it"
has "$OUT" "marketplace mach kept: another project uses it" "the report says why it stays"
is "$(full_hash "$pa")" "$ha0" "the first project is back to its bytes"
run uninstall --project "$pb"
has "$OUT" "kept: it was on this machine before setup" "a marketplace that was there before setup stays"
is "$(full_hash "$pb")" "$hb0" "the second project is back to its bytes"
rm -f "$STATE/claude.registry.json"
pc=$(pproject alone)
run apply --project "$pc"; run uninstall --project "$pc"
is "$(mkts)" "-" "the only project removes the marketplace it added"
pd=$(pproject shared-d); pe=$(pproject shared-e)
run apply --project "$pd"
touch "$STATE/claude.fail-install"
run apply --project "$pe"
rm -f "$STATE/claude.fail-install"
is "$RC" 4 "a failed install next to a shared marketplace exits 4"
is "$(find "$pe/.claude" -maxdepth 1 -name '*.local.json' | wc -l | tr -d ' ')" 0 "and leaves no marketplace declaration in the project"
is "$(users)" "shared-d" "while the other project keeps its plugin"
run uninstall --project "$pd"
pc=$(pproject nolist)
run apply --project "$pc"
touch "$STATE/claude.fail-list"
run uninstall --project "$pc"
rm -f "$STATE/claude.fail-list"
is "$(mkts)" "mach" "when other projects cannot be checked the marketplace stays"
has "$OUT" "could not check whether other projects use it" "and the report says so"
rm -f "$STATE/claude.registry.json"

p=$(pproject foreign)
printf '{"extraKnownMarketplaces":{"mach":{"source":{"source":"github","repo":"x/y"}}}}\n' > "$p/.claude/settings.local.json"
before=$(cksum < "$p/.claude/settings.local.json")
run assess --project "$p" --layer project
has "$OUT" "setup does not replace it" "a marketplace declared from elsewhere is left to a person"
run apply --project "$p" --layer project
is "$(cksum < "$p/.claude/settings.local.json")" "$before" "and apply does not touch the settings"

p=$(pproject failing-plugin)
touch "$STATE/claude.fail-install"
run apply --project "$p"
is "$RC" 4 "a failed plugin install exits 4"
is "$([ -e "$p/.claude/settings.local.json" ] && echo left || echo clean)" clean "a failed install leaves no half-registered marketplace"
rm -f "$STATE/claude.fail-install"
run apply --project "$p"
is "$RC" 0 "the next apply finishes the job"

echo "project layer: rollback edge cases"
p=$(pproject rootrun)
printf '{"schema_version":1,%s,"paths":{"run_dir":"."}}\n' "$PROJECT_ITEMS" > "$p/.claude/mach.json"
h0=$(full_hash "$p")
run apply --project "$p"
is "$RC" 1 "run_dir at the project root is refused"
run uninstall --project "$p"
is "$([ -d "$p/.git" ] && echo intact)" intact "uninstall with run_dir . does not delete the project"
p=$(pproject foreignrun)
printf '{"schema_version":1,%s,"paths":{"run_dir":".claude"}}\n' "$PROJECT_ITEMS" > "$p/.claude/mach.json"
run apply --project "$p"
is "$RC" 1 "an existing directory setup did not create is not taken over"

p=$(pproject crash)
h0=$(full_hash "$p")
FAULT=after-swap run apply --project "$p"
is "$RC" 99 "apply died right after swapping the exclude file"
run uninstall --project "$p"
is "$(full_hash "$p")" "$h0" "uninstall after the crash recovers first and returns the bytes"
p=$(pproject crash2)
FAULT=after-swap run apply --project "$p"
run apply --project "$p"
is "$RC" 0 "the next apply recovers and then sets the item up"
has "$(cat "$p/.git/info/exclude")" ".claude/mach/" "and the exclude lines are there"

p=$(pproject renamed)
h0=$(full_hash "$p")
run apply --project "$p"
printf '{"schema_version":1,"checklist":{"items":[]}}\n' > "$p/.claude/mach.json"
run uninstall --project "$p"
printf '{"schema_version":1,%s}\n' "$PROJECT_ITEMS" > "$p/.claude/mach.json"
is "$(full_hash "$p")" "$h0" "items dropped from the checklist are still undone (from the log)"

p=$(pproject twice)
h0=$(full_hash "$p")
printf '{"schema_version":1,"checklist":{"items":[{"id":"git-exclude","layer":"project","handler":"git-exclude","patterns":["a"]}]}}\n' > "$p/.claude/mach.json"
run apply --project "$p"
printf '{"schema_version":1,"checklist":{"items":[{"id":"git-exclude","layer":"project","handler":"git-exclude","patterns":["a","b"]}]}}\n' > "$p/.claude/mach.json"
run apply --project "$p"
run uninstall --project "$p"
printf '{"schema_version":1,%s}\n' "$PROJECT_ITEMS" > "$p/.claude/mach.json"
is "$(full_hash "$p")" "$h0" "two successive changes unwind to the file before setup"

p=$(pproject between)
printf '{"schema_version":1,"checklist":{"items":[{"id":"git-exclude","layer":"project","handler":"git-exclude","patterns":["a"]}]}}\n' > "$p/.claude/mach.json"
run apply --project "$p"
echo "users-rule" >> "$p/.git/info/exclude"
printf '{"schema_version":1,"checklist":{"items":[{"id":"git-exclude","layer":"project","handler":"git-exclude","patterns":["a","b"]}]}}\n' > "$p/.claude/mach.json"
run apply --project "$p"
run uninstall --project "$p"
has "$(cat "$p/.git/info/exclude")" "users-rule" "a user rule added between two applies survives uninstall"
has "$OUT" "edited between two setup runs" "and uninstall says why it left the file"

p=$(pproject premarker)
run apply --project "$p"
rm -f "$p/.claude/mach/.mach-run"
run uninstall --project "$p"
is "$RC" 0 "a run directory from before the marker is adopted by its valid log"
is "$([ -d "$p/.claude/mach" ] && echo kept || echo removed)" removed "and uninstall completes"

p=$(pproject nativefail)
run apply --project "$p"
touch "$STATE/claude.fail-uninstall"
run uninstall --project "$p"
is "$RC" 4 "a failed native plugin removal exits 4"
is "$([ -d "$p/.claude/mach" ] && echo kept)" kept "and the log is kept for the next try"
rm -f "$STATE/claude.fail-uninstall"
run uninstall --project "$p"
is "$RC" 0 "the next uninstall finishes"

echo "move from the names before ADR-0034"
# A copy of this harness with the old names stands in for a setup made before the rename.
OLD="$T/oldharness"; mkdir -p "$OLD"
/bin/cp -R "$REPO/setup" "$REPO/plugin" "$REPO/.claude-plugin" "$OLD/"
sed -i.bak 's#marker=".mach-run"#marker=".claude-mini-run"#' "$OLD/setup/lib/txn.py"
sed -i.bak 's#"\.claude/mach"#".claude/claude-mini"#; s#"\.claude/mach/"#".claude/claude-mini/"#' "$OLD/plugin/config/defaults.json"
sed -i.bak 's#"mach.json"#"claude-mini.json"#' "$OLD/plugin/bin/config"
sed -i.bak 's#"mach"#"claude-mini"#g' "$OLD/.claude-plugin/marketplace.json"
sed -i.bak 's#^LEGACY_CONFIG = .*#LEGACY_CONFIG = os.path.join(".claude", "none.json")#; s|"\# mach (setup/harness)|"\# claude-mini (setup/harness)|' "$OLD/setup/harness"
run_old() { OUT=$(cd "$T" && env -i PATH="$SHIM" HOME="$T/home" "$PY" "$OLD/setup/harness" "$@" 2>&1); RC=$?; }
# The run directory pattern lives in the project's own override here, so it is left out: what the
# move must prove is that the old setup is undone and redone, not what the override says.
LEGACY_ITEMS="${PROJECT_ITEMS//,\".claude\/mach\/\"/}"
lproject() {  # a project set up by the old harness
    local d="$T/$1"
    mkdir -p "$d/.claude" && "$GIT" -C "$d" init -q
    printf '{"schema_version":1,%s}\n' "$LEGACY_ITEMS" > "$d/.claude/claude-mini.json"
    echo "$d"
}
setting() { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], {}).get(sys.argv[3]))' "$1/.claude/settings.local.json" "$2" "$3"; }

p=$(lproject legacy)
x0=$(cksum < "$p/.git/info/exclude")
run_old apply --project "$p"
is "$RC" 0 "the old harness sets the project up under the old names"
is "$(setting "$p" enabledPlugins claude-mini@claude-mini)" True "old plugin id enabled"
has "$(cat "$p/.git/info/exclude")" "# claude-mini (setup/harness)" "old exclude block written"
run apply --project "$p" --dry-run
has "$OUT" "would move .claude/claude-mini.json to .claude/mach.json" "dry-run names the config move"
is "$([ -d "$p/.claude/claude-mini" ] && echo kept)" kept "dry-run moves nothing"
/bin/mv "$OLD" "$OLD.gone"  # DEPLOY.md moves the clone first: the old marketplace folder is gone
run apply --project "$p"
/bin/mv "$OLD.gone" "$OLD"
is "$RC" 0 "apply moves the project to the new names"
is "$([ -f "$p/.claude/mach.json" ] && [ ! -e "$p/.claude/claude-mini.json" ] && echo moved)" moved "config file renamed"
is "$([ -d "$p/.claude/mach" ] && [ ! -e "$p/.claude/claude-mini" ] && echo moved)" moved "run directory renamed"
is "$([ -e "$p/.claude/mach/.claude-mini-run" ] && echo stale || echo clean)" clean "old marker removed"
is "$(setting "$p" enabledPlugins claude-mini@claude-mini)" None "old plugin id gone from local settings"
is "$(setting "$p" extraKnownMarketplaces claude-mini)" None "old marketplace gone from local settings"
is "$(setting "$p" enabledPlugins mach@mach)" True "new plugin id enabled"
is "$(grep -c '^# mach (setup/harness)' "$p/.git/info/exclude") $(grep -c 'claude-mini' "$p/.git/info/exclude")" "1 0" \
   "exclude: the old setup's block reverted, the new one written"
has "$OUT" "setup state moved: .claude/claude-mini → .claude/mach" "the report says what moved"
is "$(grep -c '"backup": ".claude/claude-mini/' "$p/.claude/mach/intent.jsonl")" 0 "backup paths in the log follow the move"
run apply --project "$p"
is "$RC" 0 "a second apply after the move exits 0"
run uninstall --project "$p"
is "$RC" 0 "uninstall after the move exits 0"
is "$([ -e "$p/.claude/mach" ] || [ -e "$p/.claude/settings.local.json" ] && echo left || echo clean)" clean \
   "uninstall leaves no run directory and no local settings"
is "$(cksum < "$p/.git/info/exclude")" "$x0" "exclude file back to its bytes before the old setup"

p=$(lproject legacyuninstall)
x0=$(cksum < "$p/.git/info/exclude")
run_old apply --project "$p"
run uninstall --project "$p"
is "$RC" 0 "uninstall of a project still under the old names exits 0"
is "$([ -e "$p/.claude/claude-mini" ] || [ -e "$p/.claude/mach" ] || [ -e "$p/.claude/settings.local.json" ] && echo left || echo clean)" \
   clean "it undoes the old setup completely"
is "$(cksum < "$p/.git/info/exclude")" "$x0" "and restores the exclude file"

p=$(lproject legacyretry)
run_old apply --project "$p"
touch "$STATE/claude.fail-mkt-remove-once"
run apply --project "$p"
is "$RC" 4 "a failed marketplace removal stops the move with exit 4"
is "$(setting "$p" enabledPlugins claude-mini@claude-mini)" None "the old plugin was already disabled"
run apply --project "$p"
is "$RC" 0 "the next apply finishes the move without a second native uninstall"
is "$(setting "$p" enabledPlugins mach@mach)" True "and sets up the new plugin"
run uninstall --project "$p"

p=$(lproject legacyitem)
run_old apply --project "$p"
run uninstall --project "$p" --item jq
is "$RC" 2 "uninstall --item on a project under the old names is refused"
has "$OUT" "run apply first" "and says what to do"
run apply --project "$p"; run uninstall --project "$p"

p=$(lproject legacyrundir)
"$PY" - "$p/.claude/claude-mini.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["paths"] = {"run_dir": ".claude/claude-mini"}; json.dump(d, open(sys.argv[1], "w"))
PYEOF
run_old apply --project "$p"
run apply --project "$p"
is "$RC" 0 "a project that set paths.run_dir to the old directory is moved"
is "$(setting "$p" enabledPlugins claude-mini@claude-mini) $(setting "$p" enabledPlugins mach@mach)" "None True" \
   "old plugin undone, new one set up"
is "$([ -e "$p/.claude/claude-mini/.mach-run" ] && [ ! -e "$p/.claude/claude-mini/.claude-mini-run" ] && echo swapped)" swapped \
   "the run directory stays where the config says, with the new marker"
has "$OUT" "still names claude-mini" "the report points at the old value left in the config"
run uninstall --project "$p"
is "$RC" 0 "and it uninstalls cleanly"

p=$(lproject legacyboth)
run_old apply --project "$p"
mkdir -p "$p/.claude/mach"
run apply --project "$p"
is "$RC" 4 "two run directories: apply stops with exit 4"
has "$OUT" "both exist" "and says why"
is "$(setting "$p" enabledPlugins claude-mini@claude-mini)" True "nothing of the old setup is undone"

echo "T4 watch list"
is "$(tree_hash "$T/home")$(tree_hash "$T/sibling")" "$watch_before" "HOME files and the sibling project are unchanged"

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
