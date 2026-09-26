#!/usr/bin/env bash
# tests/config/run.sh — config contract of ADR-0031 §4 (#312).
# Exit 0 = all passed.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="$REPO/plugin/bin/config"
HOOK="$REPO/plugin/scripts/commit-msg-check.sh"
BASE="${PORT_RUN_TMP:-$REPO/.port-run/tmp}"
mkdir -p "$BASE"
T=$(mktemp -d "$BASE/config.XXXXXX")
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
expect() {  # expect <rc> <label> <cmd...>
    local want="$1" label="$2"; shift 2
    local got=0; "$@" >/dev/null 2>&1 || got=$?
    if [ "$got" = "$want" ]; then ok "$label"; else fail "$label — exit $got, expected $want"; fi
}
project() {  # project <name> [override-json]
    mkdir -p "$T/$1/.claude" && git -C "$T/$1" init -q
    [ -z "${2:-}" ] || printf '%s\n' "$2" > "$T/$1/.claude/claude-mini.json"
    echo "$T/$1"
}
is() {  # is <got> <want> <label>
    if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 — got '$1', expected '$2'"; fi
}
hook() {  # hook <cwd> <command> -> allow|deny
    local out
    out=$(jq -n --arg c "$2" --arg d "$1" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK" 2>/dev/null)
    if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}

echo "config"
expect 0 "defaults validate" python3 "$CFG" validate "$REPO/plugin/config/defaults.json"
p=$(project unknown '{"commit":{"typez":["feat"]}}')
expect 1 "unknown key rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"
p=$(project wrongtype '{"jev":{"enabled":"yes"}}')
expect 1 "wrong type rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"
p=$(project version '{"schema_version":2}')
expect 1 "schema_version mismatch rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"
p=$(project badenum '{"codex":{"modes":["sometimes"]}}')
expect 1 "enum value rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"
expect 2 "usage error without a command" python3 "$CFG"
p=$(project emptytypes '{"commit":{"types":[]}}')
expect 1 "empty commit.types rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"
p=$(project regextype '{"commit":{"types":["build.ci"]}}')
expect 1 "commit type with regex characters rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"
p=$(project emptytype '{"commit":{"types":["feat",""]}}')
expect 1 "empty commit type rejected" python3 "$CFG" validate "$p/.claude/claude-mini.json"

p=$(project merge '{"commit":{"types":["feat","fix"]}}')
got=$(python3 "$CFG" get commit.types --project "$p" | paste -sd, -)
is "$got" "feat,fix" "arrays are replaced by the override"
got=$(python3 "$CFG" get git.base_branch --project "$p")
is "$got" "main" "objects deep-merge (defaults kept)"
got=$(python3 "$CFG" get commit.scope_pattern --project "$p")
is "$([ -n "$got" ] && echo set)" "set" "sibling keys kept after merge"
expect 1 "unknown key on get" python3 "$CFG" get commit.nope --project "$p"

echo "hook reads config"
p=$(project onlyfeat '{"commit":{"types":["feat"]}}')
is "$(hook "$p" 'git commit -m "fix: x"')" deny "type outside the project list is denied"
is "$(hook "$p" 'git commit -m "feat: x"')" allow "type in the project list is allowed"
p=$(project broken '{"commit":{"types":"feat"}}')
is "$(hook "$p" 'git commit -m "feat: x"')" deny "invalid project config fails closed"
p=$(project plain)
is "$(hook "$p" 'git commit -m "chore: x"')" allow "no override uses defaults"
is "$(hook "$p" 'git commit -m ": x"')" deny "subject without a type is denied"
p=$(project badscope '{"commit":{"scope_pattern":"[a-z"}}')
out=$(jq -n --arg c 'git commit -m "feat(x): y"' --arg d "$p" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK" 2>/dev/null)
is "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -c 'scope_pattern is not a valid ERE')" 1 "invalid scope_pattern names the config, not the subject"
p=$(project brokencfg '{"commit":{"types":"feat"}}')
is "$(hook "$p" 'git log --grep=commit')" allow "broken config does not block commands without a commit"
q=$(project onlyfix '{"commit":{"types":["fix"]}}')
is "$(hook "$p" "git -C $q commit -m 'fix: x'")" allow "git -C uses the target repository's config"
r=$(project plain2)
is "$(hook "$r" "cd $q && git commit -m 'feat: x'")" deny "cd target's config applies (feat not allowed there)"

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
