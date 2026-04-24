#!/usr/bin/env bash
# mini-health — weekly health-check всего стека:
# LaunchAgents, disk, Claude Code auth, MCP servers, governance hook.

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

# --- Governance hook smoke-test ---
echo ""
echo "Governance hook (все 6 паттернов из ADR-0004):"
test_script="$HOME/.claude/scripts/test-governance-hook.sh"
hook_path="$HOME/.claude/hooks/pre-commit-governance.sh"
if [ ! -x "$hook_path" ]; then
    warn "Governance hook не установлен: $hook_path"
elif [ ! -x "$test_script" ]; then
    warn "Hook test script не установлен: $test_script"
else
    if bash "$test_script" >/dev/null 2>&1; then
        ok "Hook smoke-test: все 6 паттернов прошли"
    else
        fail "Hook smoke-test упал — запусти: bash $test_script"
    fi
fi

# --- Commit-msg governance hook (ADR-0011, per-project) ---
echo ""
echo "Commit-msg governance hook:"
staged_hook="$HOME/.claude/git-hooks/commit-msg"
if [ ! -x "$staged_hook" ]; then
    warn "Staged hook not found: $staged_hook (run universal-setup.sh --install)"
else
    ok "Staged hook present: $staged_hook"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        repo_hook="$(git rev-parse --git-dir)/hooks/commit-msg"
        if [ ! -f "$repo_hook" ]; then
            warn "commit-msg hook not installed in this repo (run: ./bootstrap/universal-setup.sh --hook-this-repo)"
        elif cmp -s "$staged_hook" "$repo_hook"; then
            ok "Repo hook up-to-date: $repo_hook"
        else
            warn "Repo hook differs from staged version (run: ./bootstrap/universal-setup.sh --hook-this-repo --force)"
        fi
    fi
fi

# --- gh & codex auth ---
echo ""
echo "Auth:"
gh auth status >/dev/null 2>&1 && ok "gh auth" || warn "gh auth inactive"
command -v codex >/dev/null 2>&1 && \
    (codex login status 2>/dev/null | grep -qi "ok\|logged" && ok "codex auth" || warn "codex auth uncertain") || \
    warn "codex not installed"

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
