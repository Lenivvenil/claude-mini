#!/usr/bin/env bash
# commit-msg-check.sh — claude-mini plugin PreToolUse hook (#308)
#
# Runs only for `git commit` (hooks/hooks.json: "if": "Bash(git commit *)") and only in
# projects where the plugin is enabled (project/local scope). No repo marker, no global
# settings: the plugin scope is the boundary (ADR-0011 intent, Principle 5).
#
# Checks Rule 1 (Conventional Commits subject).
# Rules 2-3 (issue-ref, ADR-ref) are not applied: projects like likec4 add the PR number
# at squash time, and file-name heuristics for "architectural" changes proved unreliable
# (audit 2026-09-25).
#
# Message sources understood: -m "..." / -m '...' / --message=..., -F <file>,
# -F - with a heredoc in the same command. --amend/--no-edit without a new message and
# fixup!/squash! subjects are allowed. A commit with no message source would open an
# editor, which Claude cannot use — denied with a hint.
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

if ! command -v jq >/dev/null 2>&1; then
    deny "claude-mini: jq not found — install jq (brew install jq) to check commit messages."
fi

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$command" ] || exit 0

# Rule 1 — same regex as bootstrap/hooks/governance-rules-lib.sh (v1 git hook). The plugin
# cannot source files outside its own directory once installed, so the rule lives here.
CC_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr)(\([a-z0-9_.-]+\))?!?:[[:space:]].+'

subject=""
# 1. -m "..." / -m '...' / --message="..." (first occurrence)
subject=$(printf '%s' "$command" | grep -oE -- "(-m|--message)(=|[[:space:]]+)\"[^\"]*\"" | head -1 \
    | sed -E 's/^(-m|--message)(=|[[:space:]]+)"(.*)"$/\3/')
if [ -z "$subject" ]; then
    subject=$(printf '%s' "$command" | grep -oE -- "(-m|--message)(=|[[:space:]]+)'[^']*'" | head -1 \
        | sed -E "s/^(-m|--message)(=|[[:space:]]+)'(.*)'$/\3/")
fi
# 2. -F - / --file=- with a heredoc: first line after the heredoc opener
if [ -z "$subject" ] && printf '%s' "$command" | grep -qE -- '(-F|--file)(=|[[:space:]]+)-([[:space:]]|$)'; then
    subject=$(printf '%s\n' "$command" | awk '
        found { print; exit }
        /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/ { found=1 }')
fi
# 3. -F <file> / --file=<file>
if [ -z "$subject" ]; then
    file=$(printf '%s' "$command" | grep -oE -- '(-F|--file)(=|[[:space:]]+)[^[:space:]-][^[:space:]]*' | head -1 \
        | sed -E 's/^(-F|--file)(=|[[:space:]]+)//')
    if [ -n "$file" ]; then
        case "$file" in /*) path="$file" ;; *) path="${cwd:-.}/$file" ;; esac
        [ -f "$path" ] && subject=$(head -1 "$path")
    fi
fi
# 4. amend / no-edit without a new message: nothing to check
if [ -z "$subject" ] && printf '%s' "$command" | grep -qE -- '--amend|--no-edit'; then
    exit 0
fi

if [ -z "$subject" ]; then
    deny "claude-mini: git commit without -m / -F would open an editor. Use: git commit -m \"type(scope): subject\""
fi

subject=${subject%%$'\n'*}
case "$subject" in fixup!*|squash!*|amend!*) exit 0 ;; esac

if ! printf '%s' "$subject" | grep -qE "$CC_REGEX"; then
    deny "claude-mini: commit subject is not Conventional Commits. Expected: type(scope?)!?: subject, types feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr. Got: '$subject'"
fi
exit 0
