#!/usr/bin/env bash
# test-commit-msg-check.sh — cases for the plugin's commit-msg-check.sh hook (#308)
# Usage: bash scripts/test-commit-msg-check.sh   (exit 0 = all passed)
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/commit-msg-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'docs: from file\n' > "$T/msg.txt"
printf 'bad file msg\n' > "$T/bad.txt"
FAIL=0

check() {  # check <expect: allow|deny> <label> <command>
    local out got
    out=$(jq -n --arg c "$3" --arg d "$T" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
    if [ -z "$out" ]; then got=allow
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

out=$(echo '{"tool_input":{"command":"git commit -m x"}}' | PATH=/nonexistent /bin/bash "$HOOK")
if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo "  ok   jq missing → deny with valid JSON"
else echo "  FAIL jq missing → expected deny JSON, got: $out"; FAIL=$((FAIL+1)); fi

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
