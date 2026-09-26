#!/usr/bin/env bash
# mini-health — weekly health-check всего стека:
# LaunchAgents, disk, Claude Code auth, MCP servers, gh and codex auth.

set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; warnings=$((warnings+1)); }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; failures=$((failures+1)); }

warnings=0; failures=0

echo "=== mini-health ==="
date
echo ""

# --- LaunchAgents (macOS) ---
echo "LaunchAgents:"
if [ "$(uname)" = "Darwin" ]; then
    for agent in "tmux" "plex" "transmission" "caffeinate"; do
        if launchctl list 2>/dev/null | grep -qi "$agent"; then
            ok "$agent running"
        else
            warn "$agent not loaded"
        fi
    done
else
    warn "Not macOS — skip LaunchAgents check"
fi

# --- Disk space ---
echo ""
echo "Disk:"
used=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$used" -lt 80 ]; then
    ok "Disk usage: $used%"
elif [ "$used" -lt 90 ]; then
    warn "Disk usage: $used% (approaching limit)"
else
    fail "Disk usage: $used% (critical)"
fi

# --- Claude Code ---
echo ""
echo "Claude Code:"
if command -v claude >/dev/null 2>&1; then
    ver=$(claude --version 2>/dev/null | head -1)
    ok "claude $ver"
else
    fail "claude binary not found"
fi

# --- MCP servers health ---
echo ""
echo "MCP:"
if [ -f ~/.claude.json ] || [ -f ~/.claude/settings.json ]; then
    # Парсим mcpServers
    settings_file=~/.claude/settings.json
    [ -f ~/.claude.json ] && settings_file=~/.claude.json
    mcp_count=$(jq -r '.mcpServers // {} | keys | length' "$settings_file" 2>/dev/null || echo 0)
    if [ "$mcp_count" -gt 0 ]; then
        ok "MCP servers configured: $mcp_count"
    else
        warn "No MCP servers configured"
    fi
else
    warn "No Claude Code settings file"
fi

# The commit hook is part of the claude-mini plugin, enabled per project; `setup/harness verify`
# checks it there, not here.

# --- gh & codex auth ---
echo ""
echo "Auth:"
if gh auth status >/dev/null 2>&1; then
    ok "gh auth"
else
    warn "gh auth inactive"
fi
if command -v codex >/dev/null 2>&1; then
    _tc=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")
    if [ -n "$_tc" ] && "$_tc" 10 codex login status 2>/dev/null | grep -qi "ok\|logged"; then
        ok "codex auth"
    elif [ -z "$_tc" ] && codex login status 2>/dev/null | grep -qi "ok\|logged"; then
        ok "codex auth"
    else
        warn "codex auth uncertain or startup slow — fix: rm ~/.codex/auth.json && codex login --device-auth"
    fi
else
    warn "codex not installed"
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
printf "Warnings: ${YELLOW}%d${NC}, Failures: ${RED}%d${NC}\n" "$warnings" "$failures"

if [ "$failures" -gt 0 ]; then
    exit 1
elif [ "$warnings" -gt 3 ]; then
    exit 2
else
    exit 0
fi
