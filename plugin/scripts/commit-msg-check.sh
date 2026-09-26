#!/usr/bin/env bash
# commit-msg-check.sh — claude-mini plugin PreToolUse hook (#308)
#
# Wired by hooks/hooks.json with "if": "Bash(git *)" (git global options such as -C sit
# between git and commit, so a narrower pattern misses them), only in projects where
# the plugin is enabled (project/local scope). The `if` match is conservative —
# Claude Code also runs the hook when it cannot resolve shell expansions (e.g.
# `echo "$PATH"`) — so the script first checks that the command really runs
# `git ... commit` and exits 0 otherwise.
#
# Checks Rule 1: the commit subject follows Conventional Commits (v1 regex from
# bootstrap/hooks/governance-rules-lib.sh plus a non-blank subject). Rules 2-3
# (issue-ref, ADR-ref) are not applied: projects like likec4 add the PR number at
# squash time, and file-name heuristics for "architectural" changes proved unreliable
# (audit 2026-09-25).
#
# The command is parsed by parse-commit.py (heredoc bodies cut out as data, shlex
# tokens, git commit options with their argument boundaries). Every `git ... commit`
# in the command is checked; the subject is the first line of its first message
# source: -m/--message (also -am, -mVALUE, --message=VALUE, "$(cat <<'EOF' ...)"),
# -F/--file <path> relative to the effective directory (cd, subshells, git -C), or
# -F - with the commit's own heredoc.
# Allowed without a subject: -c/-C/--reuse-message/--reedit-message, --amend or
# --no-edit, --fixup/--squash, --dry-run; fixup!/squash!/amend! subjects.
# No message source at all would open an editor, which Claude cannot use — denied.
#
# Contract: stdin = hook JSON; deny = hookSpecificOutput JSON on stdout, exit 0.

set -uo pipefail

deny() {
    local reason="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg r "$reason" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    else
        reason=${reason//\\/\\\\}; reason=${reason//\"/\\\"}
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
    fi
    exit 0
}

IFS= read -r -d '' input || true  # builtin: works even with a broken PATH
# Most `git *` calls are not commits: leave them alone even without jq/python3.
[[ $input == *commit* ]] || exit 0

for bin in jq python3; do
    command -v "$bin" >/dev/null 2>&1 \
        || deny "claude-mini: $bin not found — install it to check commit messages (brew install $bin)."
done

command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$command" ] || exit 0

# Parser output: one line per commit invocation — ALLOW | NOMSG | BADDIR |
# SUBJECT<TAB><dir><TAB><subject>; empty when the command runs no `git ... commit`.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! result=$(CMD="$command" CWD="${cwd:-.}" python3 "$_self_dir/parse-commit.py" 2>/dev/null); then
    err=$(CMD="$command" CWD="${cwd:-.}" python3 "$_self_dir/parse-commit.py" 2>&1 >/dev/null | tail -1)
    deny "claude-mini: commit message parser failed: ${err:-no error text}"
fi
# No commit in the command: nothing to check, and a broken project config must not block it.
[[ $result == *SUBJECT* || $result == *NOMSG* || $result == *BADDIR* ]] || exit 0

# Commit rules come from config (ADR-0031 §4): plugin defaults merged with the
# .claude/claude-mini.json of the repository that receives the commit (git top level of the
# commit's effective directory). The validator keeps types to plain words, so they are
# literal in the regex; scope_pattern is an ERE by contract and is checked before use.
cfg="$_self_dir/../bin/config"
rules_root=""
load_rules() {  # load_rules <dir>: sets types_alt, scope, skips for that repository
    local root
    root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || root="$1"
    [ "$root" = "$rules_root" ] && return 0
    local types
    types=$(python3 "$cfg" get commit.types --project "$root" 2>&1) \
        || deny "claude-mini: project config is invalid — fix $root/.claude/claude-mini.json: $types"
    scope=$(python3 "$cfg" get commit.scope_pattern --project "$root" 2>&1) \
        || deny "claude-mini: project config is invalid: $scope"
    skips=$(python3 "$cfg" get commit.skip_prefixes --project "$root" 2>&1) \
        || deny "claude-mini: project config is invalid: $skips"
    types_alt=$(printf '%s' "$types" | paste -sd'|' -)
    [ -n "$types_alt" ] || deny "claude-mini: commit.types is empty in $root — no subject can pass."
    local rc=0
    printf '' | grep -qE "(${scope})" 2>/dev/null || rc=$?
    [ "$rc" -le 1 ] || deny "claude-mini: commit.scope_pattern is not a valid ERE in $root: '$scope'"
    rules_root=$root
}

# One line per commit invocation; every commit in the command must pass.
while IFS= read -r line; do
    case "$line" in
        ""|ALLOW) continue ;;
        NOMSG) deny "claude-mini: git commit without -m / -F would open an editor. Use: git commit -m \"type(scope): subject\"" ;;
        BADDIR) deny "claude-mini: commit directory contains a tab or newline — cannot resolve its config." ;;
    esac
    rest=${line#SUBJECT$'\t'}
    dir=${rest%%$'\t'*}
    subject=${rest#*$'\t'}
    load_rules "$dir"
    skipped=0
    while IFS= read -r prefix; do
        [ -n "$prefix" ] && case "$subject" in "$prefix"*) skipped=1 ;; esac
    done < <(printf '%s\n' "$skips")
    [ "$skipped" -eq 1 ] && continue
    rc=0
    printf '%s' "$subject" | grep -qE "^(${types_alt})(\\((${scope})\\))?!?:[[:space:]]+[^[:space:]]" || rc=$?
    case "$rc" in
        0) ;;
        1) deny "claude-mini: commit subject is not Conventional Commits. Expected: type(scope?)!?: subject, types ${types_alt}. Got: '$subject'" ;;
        *) deny "claude-mini: subject check failed (grep exit $rc) — commit not allowed." ;;
    esac
done < <(printf '%s\n' "$result")
exit 0
