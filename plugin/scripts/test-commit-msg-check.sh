#!/usr/bin/env bash
# test-commit-msg-check.sh — cases for the plugin's commit-msg-check.sh hook (#308)
# Usage: bash scripts/test-commit-msg-check.sh   (exit 0 = all passed)
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/commit-msg-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'docs: from file\n' > "$T/msg.txt"
printf 'bad file msg\n' > "$T/bad.txt"
mkdir -p "$T/dir with space" && printf 'docs: spaced\n' > "$T/dir with space/m.txt"
mkdir -p "$T/sub" && printf 'docs: in sub\n' > "$T/sub/m.txt" && printf 'nope in sub\n' > "$T/sub/bad.txt"
FAIL=0

check() {  # check <expect: allow|deny> <label> <command>
    local out got
    local rc=0
    out=$(jq -n --arg c "$3" --arg d "$T" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK" 2>/dev/null) || rc=$?
    if [ "$rc" -ne 0 ]; then got="script-error(rc=$rc)"
    elif [ -z "$out" ]; then got=allow
    elif printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then got=deny
    else got="invalid-output"; fi
    if [ "$got" = "$1" ]; then echo "  ok   $2"; else echo "  FAIL $2 — expected $1, got $got"; FAIL=$((FAIL+1)); fi
}

echo "commit-msg-check.sh"
check allow "CC subject via -m"              'git commit -m "fix(core): keep zoom capped"'
check deny  "non-CC subject"                 'git commit -m "just did stuff"'
check allow "breaking change, single quotes" "git commit -m 'feat!: break api'"
check allow "chained after git add"          'git add a.txt && git commit -m "chore(deps): bump x"'
check allow "heredoc -F - with CC subject"   $'git commit -q -F - <<\'EOF\'\nfix(hooks): boundary #303\n\nbody\nEOF'
check deny  "heredoc -F - with bad subject"  $'git commit -F - <<EOF\nnope this is bad\nEOF'
check allow "-F file with CC subject"        'git commit -F msg.txt'
check deny  "-F file with bad subject"       'git commit -F bad.txt'
check allow "--amend --no-edit"              'git commit --amend --no-edit'
check allow "fixup! subject"                 'git commit -m "fixup! something"'
check deny  "no message source (editor)"     'git commit'
check allow "-am combined flag"              'git commit -am "fix(core): msg"'
check deny  "-am with bad subject"           'git commit -am "stuff"'
check allow "-C reuse message"               'git commit -C HEAD'
check allow "-c reedit message"              'git commit -c HEAD~1'
check allow "-F quoted path with spaces"     'git commit -F "dir with space/m.txt"'
check deny  "blank subject after type"       'git commit -m "fix(s):    "'
# shellcheck disable=SC2016  # literal $PATH: the hook must see the unexpanded text
check allow "not a commit: echo \$PATH"       'echo "$PATH"'
check allow "not a commit: quoted mention"   'echo "git commit -m x"'
check allow "Claude style -m \$(cat heredoc)" $'git commit -m "$(cat <<\'EOF\'\nfeat(plugin): add hook\n\nbody line\n\nCo-Authored-By: X <x@y>\nEOF\n)"'
check deny  "-m \$(cat heredoc) bad subject"  $'git commit -m "$(cat <<\'EOF\'\nsome stuff\n\nbody\nEOF\n)"'
check allow "multi-line -m with body"        $'git commit -m "fix: subject\n\nbody text"'
check deny  "first -m bad, second -m CC"     $'git commit -m \'bad subject\' -m "fix: body"'
check deny  "git -C dir commit, bad subject" 'git -C sub commit -m "nope"'
check allow "-F quoted relative path"        'git commit -F "msg.txt"'
check deny  "git -c opt=val commit, bad"     'git -c user.name=T commit -m "bad subject"'
check deny  "second commit in chain is bad"  'git commit --allow-empty -m "fix: first" && git commit --allow-empty -m "bad subject"'
check deny  "second commit on next line bad" $'git commit -m "fix: first"\ngit commit -m "bad subject"'
check allow "cd sub && -F relative to sub"   'cd sub && git commit -F m.txt'
check deny  "cd sub && -F bad file in sub"   'cd sub && git commit -F bad.txt'
check allow "script heredoc then commit heredoc" $'cat > s.sh <<\'EOF\'\n#!/usr/bin/env bash\necho hi\nEOF\ngit commit -F - <<\'EOF\'\nfix: add script\nEOF'
check allow "--fixup with -m body"           'git commit --fixup=HEAD -m "extra explanation"'
check allow "-am attached value"             'git commit -am"fix: subject"'
check deny  "-am attached bad value"         'git commit -am"bad subject"'
check allow "not git: plain ls"              'ls -la'

out=$(echo '{"tool_input":{"command":"git commit -m x"}}' | PATH=/nonexistent /bin/bash "$HOOK")
if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo "  ok   jq missing → deny with valid JSON"
else echo "  FAIL jq missing → expected deny JSON, got: $out"; FAIL=$((FAIL+1)); fi

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
