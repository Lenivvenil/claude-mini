#!/usr/bin/env bash
# isolated-claude.sh — sourced helper: run Claude Code in a throw-away HOME (docs/port/PLAN.md, S4).
#
# An isolated CLAUDE_CONFIG_DIR is "Not logged in" (verified 2026-09-26, 2.1.283), so isolated
# runs authenticate with a long-lived subscription token from `claude setup-token`. The token is
# read from $CLAUDE_CODE_OAUTH_TOKEN or from the macOS Keychain item named by
# $CLAUDE_MINI_TOKEN_ITEM (default claude-mini-test-oauth). It is never printed or logged.
#
# Functions:
#   iso_require_token   exports CLAUDE_CODE_OAUTH_TOKEN or exits 77 (SKIPPED, never a pass)
#   iso_home <dir>      creates <dir>/home and exports HOME and CLAUDE_CONFIG_DIR into it
#   iso_init <stream>   prints the system/init JSON line of a stream-json file

ISO_SKIP=77

iso_require_token() {
    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        export CLAUDE_CODE_OAUTH_TOKEN
        return 0
    fi
    local item="${CLAUDE_MINI_TOKEN_ITEM:-claude-mini-test-oauth}" tok=""
    if command -v security >/dev/null 2>&1; then
        tok=$(security find-generic-password -s "$item" -w 2>/dev/null) || tok=""
    fi
    if [ -z "$tok" ]; then
        echo "SKIPPED: no subscription token for isolated Claude runs." >&2
        echo "  Owner: run 'claude setup-token', then: security add-generic-password -s $item -a \"\$USER\" -w" >&2
        exit "$ISO_SKIP"
    fi
    export CLAUDE_CODE_OAUTH_TOKEN="$tok"
}

iso_home() {
    mkdir -p "$1/home/.claude"
    export HOME="$1/home"
    export CLAUDE_CONFIG_DIR="$1/home/.claude"
    # git identity for commits made inside the sandbox, without touching the real ~/.gitconfig
    export GIT_CONFIG_GLOBAL="$1/home/.gitconfig"
    git config --global user.name "claude-mini test"
    git config --global user.email "test@example.invalid"
}

iso_init() {
    python3 -c '
import json, sys
for line in open(sys.argv[1]):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "system" and d.get("subtype") == "init":
        print(json.dumps(d))
        break
' "$1"
}
