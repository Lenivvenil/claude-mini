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
# The command is parsed by parse-commit.py (a small Bash-aware tokenizer: quoting,
# comments, command boundaries, heredocs; git commit options with their argument
# boundaries). Every `git ... commit`
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
# Cheap pre-filter on the raw JSON: `git`, later a separate word `commit`
# (not commit-tools, not .../commit-msg-check.sh). The parser decides the rest.
_commit_re='git.*[[:space:]]commit([[:space:]"\\]|$)'
[[ $input =~ $_commit_re ]] || exit 0

for bin in jq python3; do
    command -v "$bin" >/dev/null 2>&1 \
        || deny "claude-mini: $bin not found — install it to check commit messages (brew install $bin)."
done

command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$command" ] || exit 0

# Parser output: one line per commit invocation — ALLOW | NOMSG | SUBJECT<TAB><subject>;
# empty when the command runs no `git ... commit`.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
result=$(CMD="$command" CWD="${cwd:-.}" python3 "$_self_dir/parse-commit.py") \
    || deny "claude-mini: commit message parser failed — see stderr."

CC_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr)(\([a-z0-9_.-]+\))?!?:[[:space:]]+[^[:space:]]'

# One line per commit invocation; every commit in the command must pass.
while IFS= read -r line; do
    case "$line" in
        ""|ALLOW) continue ;;
        NOMSG) deny "claude-mini: git commit without -m / -F would open an editor. Use: git commit -m \"type(scope): subject\"" ;;
    esac
    subject=${line#SUBJECT$'\t'}
    case "$subject" in fixup!*|squash!*|amend!*) continue ;; esac
    if ! printf '%s' "$subject" | grep -qE "$CC_REGEX"; then
        deny "claude-mini: commit subject is not Conventional Commits. Expected: type(scope?)!?: subject, types feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr. Got: '$subject'"
    fi
done <<< "$result"
exit 0
