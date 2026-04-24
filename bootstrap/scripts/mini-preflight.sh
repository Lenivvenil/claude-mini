#!/usr/bin/env bash
# mini-preflight — утренний чек окружения перед началом работы.
# Выводит зелёный/жёлтый/красный статус по каждому элементу.

set -uo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; failed=$((failed+1)); }

failed=0

echo "=== mini-preflight ==="
echo ""

echo "Keychain & secrets:"
if security list-keychains 2>/dev/null | grep -q login; then
    # Try to unlock
    if security unlock-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null <<<""; then
        ok "Keychain unlocked (no password needed / cached)"
    else
        warn "Keychain locked — run: security unlock-keychain ~/Library/Keychains/login.keychain-db"
    fi
else
    fail "login.keychain-db не найдена"
fi

if [ -n "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$SOPS_AGE_KEY_FILE" ]; then
    ok "SOPS_AGE_KEY_FILE экспортирована и существует"
else
    warn "SOPS_AGE_KEY_FILE не установлена в env (mise sops reader её не найдёт)"
fi

echo ""
echo "Auth состояние:"
if gh auth status >/dev/null 2>&1; then
    ok "gh auth: $(gh api user --jq .login 2>/dev/null || echo ok)"
else
    fail "gh auth не активна — запусти: gh auth login"
fi

if command -v codex >/dev/null 2>&1; then
    if codex login status 2>/dev/null | grep -qi "logged in\|authenticated\|ok"; then
        ok "codex login активен"
    else
        warn "codex login статус неясен — проверь: codex login status"
    fi
else
    warn "codex CLI не установлен (opt-in; нужен для /codex-review)"
fi

echo ""
echo "Claude Code env:"
if [ -n "${CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL:-}" ]; then
    ok "advisor tool enabled"
else
    warn "CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL не установлена"
fi

if [ -n "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" ] && [ -n "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}" ]; then
    ok "models pinned: sonnet=$ANTHROPIC_DEFAULT_SONNET_MODEL opus=$ANTHROPIC_DEFAULT_OPUS_MODEL"
else
    warn "ANTHROPIC_DEFAULT_{SONNET,OPUS}_MODEL не установлены"
fi

echo ""
echo "Tailscale & network:"
if command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then
        ok "tailscale up, IP: $(tailscale ip -4 2>/dev/null | head -1)"
    else
        warn "tailscale не запущен"
    fi
else
    warn "tailscale CLI не найден"
fi

echo ""
echo "SSH keepalive:"
if grep -rq '^[[:space:]]*ClientAliveInterval[[:space:]]' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null; then
    ok "sshd ClientAliveInterval configured (SSH drops during advisor calls prevented)"
else
    warn "sshd ClientAliveInterval не задан — SSH может обрываться на длинных advisor-вызовах; проверь шаг 19 в mac-mini-2018.md (и ClientAliveCountMax)"
fi

echo ""
echo "Claude Code:"
if command -v claude >/dev/null 2>&1; then
    ok "claude: $(claude --version 2>/dev/null | head -1)"
else
    fail "claude бинарь не найден в PATH"
fi

echo ""
if [ $failed -eq 0 ]; then
    printf "${GREEN}Готов к сессии.${NC}\n"
    exit 0
else
    printf "${RED}$failed блокирующих проблем.${NC} Исправь перед началом работы.\n"
    exit 1
fi
