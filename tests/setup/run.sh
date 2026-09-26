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
  install) [ -f "$STATE/fail-install" ] && exit 1; /bin/cp "$T/proto" "$SHIM/\$2" ;;
  uninstall) /bin/rm -f "$SHIM/\$2" ;;
esac
EOF
cat > "$SHIM/apt-get" <<EOF
#!/bin/sh
echo "apt-get \$*" >> "$T/pm.log"
case "\$1" in
  install) [ -f "$STATE/fail-install" ] && exit 1; /bin/cp "$T/proto" "$SHIM/\$3" ;;
  remove) /bin/rm -f "$SHIM/\$3" ;;
esac
EOF
printf '#!/bin/sh\nexec "$@"\n' > "$SHIM/sudo"
chmod +x "$SHIM/brew" "$SHIM/apt-get" "$SHIM/sudo"
for b in jq gh claude codex node; do fake "$b"; done
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
    printf '{"schema_version":1,%s%s}\n' "$CHECKLIST" "${2:+,$2}" > "$d/.claude/claude-mini.json"
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
run() {  # run <args...> ; sets OUT and RC
    OUT=$(cd "$T" && env -i PATH="$SHIM" HOME="$T/home" "$PY" "$H" "$@" 2>&1); RC=$?
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

echo "config and usage errors"
p=$(project badcfg)
printf '{"schema_version":1,"checklist":{"items":[{"id":"x","layer":"machine","handler":"shell"}]}}\n' > "$p/.claude/claude-mini.json"
run assess --project "$p"
is "$RC" 1 "an unknown handler in config exits 1"
run frobnicate
is "$RC" 2 "an unknown command exits 2"

echo "T8 crash-safe file primitive"
p=$(project txn)
t8() {  # t8 <fault point> -> runs one write under the fault, then recovery in a new process
    env CLAUDE_MINI_SETUP_FAULT="$1" "$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
t = txn.Txn(sys.argv[2], ".claude/claude-mini")
t.write_file("demo", "target.txt", b"new\n")
PYEOF
    echo "exit $?"
}
recover() {
    "$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
t = txn.Txn(sys.argv[2], ".claude/claude-mini")
rec, broken = t.recover()
print(len(rec), len(broken))
PYEOF
}
for point in after-intent before-swap after-swap; do
    printf 'old\n' > "$p/target.txt"
    is "$(t8 "$point")" "exit 99" "$point: the process died at the fault"
    is "$(recover)" "1 0" "$point: recovery resolved one interrupted change"
    is "$(cat "$p/target.txt")" "old" "$point: target is byte-identical to the original"
    is "$(find "$p" -maxdepth 1 -name '.*claude-mini-*.tmp' | wc -l | tr -d ' ')" 0 "$point: no temp file left"
done
printf 'old\n' > "$p/target.txt"
is "$(t8 after-done)" "exit 99" "after-done: died after the change was recorded"
is "$(recover)" "0 0" "after-done: nothing to recover"
is "$(cat "$p/target.txt")" "new" "after-done: the finished change stays"
rm -f "$p/fresh.txt"
env CLAUDE_MINI_SETUP_FAULT=after-swap "$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
txn.Txn(sys.argv[2], ".claude/claude-mini").write_file("demo", "fresh.txt", b"x\n")
PYEOF
recover >/dev/null
is "$([ -e "$p/fresh.txt" ] && echo present || echo absent)" absent "a new file interrupted after the swap is removed"
printf 'old\n' > "$p/target.txt"
"$PY" - "$REPO/setup/lib" "$p" <<'PYEOF' || true
import sys; sys.path.insert(0, sys.argv[1]); import txn
try:
    txn.Txn(sys.argv[2], ".claude/claude-mini").write_file("demo", "target.txt", b"bad\n", validate=lambda p: "rejected")
except txn.TxnError:
    pass
PYEOF
is "$(cat "$p/target.txt")" "old" "a rejected candidate leaves the target unchanged"
out=$("$PY" - "$REPO/setup/lib" "$p" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[1]); import txn
try:
    txn.Txn(sys.argv[2], ".claude/claude-mini").write_file("demo", "../escape.txt", b"x")
    print("written")
except txn.TxnError:
    print("refused")
PYEOF
)
is "$out" refused "a path outside the project is refused"
is "$([ -e "$T/escape.txt" ] && echo present || echo absent)" absent "nothing written outside the project"

echo "T4 watch list"
is "$(tree_hash "$T/home")$(tree_hash "$T/sibling")" "$watch_before" "HOME files and the sibling project are unchanged"

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
