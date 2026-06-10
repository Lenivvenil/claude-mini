#!/usr/bin/env bash
# mini-preflight — утренний чек окружения перед началом работы.
# Выводит зелёный/жёлтый/красный статус по каждому элементу.

set -uo pipefail

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

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
    _tc=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")
    if [ -n "$_tc" ] && "$_tc" 10 codex login status 2>/dev/null | grep -qi "logged in\|authenticated\|ok"; then
        ok "codex login активен"
    elif [ -z "$_tc" ] && codex login status 2>/dev/null | grep -qi "logged in\|authenticated\|ok"; then
        ok "codex login активен"
    else
        warn "codex login статус неясен или startup завис — fix: rm ~/.codex/auth.json && codex login --device-auth"
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

# --- «Ритуал возвращения»: что накопилось, пока оператора не было (#257) ---
# Report-only: секция никогда не меняет exit-код (не трогает $failed) и ничего
# не мутирует. Деградация по Принципу 9: любой сбой gh/jq → warn + пропуск секции.
report_accumulated() {
    local repo_root tc
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0  # вне git-репо секции нет

    echo ""
    echo "Что накопилось за отсутствие ($(basename "$repo_root")):"

    if ! command -v jq >/dev/null 2>&1; then
        warn "jq не найден — секция пропущена"
        return 0
    fi
    # timeout-обёртка: gh без сети может висеть десятки секунд, а preflight интерактивен.
    # Не переиспользуем _tc из codex-блока выше: тот инициализируется только в своей
    # ветке и под set -u здесь был бы unbound.
    tc=$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")
    _gh() {
        # 15s: дольше codex-овых 10s — gh run list на холодном TCP заметно медленнее
        if [ -n "$tc" ]; then "$tc" 15 gh "$@" 2>/dev/null; else gh "$@" 2>/dev/null; fi
    }

    # --- Локальные подсекции (работают и офлайн — до gh-гейта) ---

    # Дней с последней сессии — по имени последнего session-log файла (YYYY-MM-DD)
    local last_log last_date days_away
    last_log=$(find "$repo_root/session-log" -name '*.md' 2>/dev/null | sort | tail -1)
    if [ -n "$last_log" ]; then
        last_date=$(basename "$last_log" .md)
        days_away=$(jq -rn --arg d "$last_date" '((now - (($d + "T00:00:00Z") | fromdate)) / 86400 | floor)' 2>/dev/null || echo "")
        if [ -n "$days_away" ]; then
            if [ "$days_away" -gt 7 ]; then  # неделя: дольше — пауза, а не выходные
                warn "$days_away дней с последней сессии ($last_date)"
            else
                ok "$days_away дн. с последней сессии ($last_date)"
            fi
        fi
    fi

    # Proposed-ADR с возрастом из строки '* Date:' — чисто локальный grep,
    # сознательно ДО gh-гейта: офлайн-оператор должен видеть протухшие ADR
    local adr_file adr_date adr_age
    for adr_file in "$repo_root"/docs/decisions/[0-9]*.md; do
        [ -f "$adr_file" ] || continue
        if grep -q '^\* Status: proposed' "$adr_file"; then
            adr_date=$(grep -m1 '^\* Date:' "$adr_file" | sed 's/^\* Date:[[:space:]]*//')
            adr_age=$(jq -rn --arg d "$adr_date" '((now - (($d + "T00:00:00Z") | fromdate)) / 86400 | floor)' 2>/dev/null || echo "?")
            warn "proposed ADR: $(basename "$adr_file") — $adr_age дн."
        fi
    done

    # --- Сетевые подсекции (gh-гейт) ---

    if ! command -v gh >/dev/null 2>&1 || ! _gh auth status >/dev/null; then
        warn "gh недоступен — CI/issues/PR секции пропущены (офлайн-режим, Принцип 9)"
        return 0
    fi

    # CI: последний прогон каждого workflow; limit 50, чтобы редкие scheduled-прогоны
    # не выпадали из окна в активный день. Красное = любой завершившийся не-success
    # (failure, cancelled, timed_out, startup_failure); in-progress (conclusion == "")
    # не красим. max_by(.createdAt) — не полагаемся на порядок вывода gh.
    local runs red_lines ok_lines line
    if runs=$(_gh run list --limit 50 --json workflowName,status,conclusion,createdAt) && [ -n "$runs" ]; then
        red_lines=$(echo "$runs" | jq -r 'group_by(.workflowName) | map(max_by(.createdAt)) | .[] | select(.conclusion != "success" and .conclusion != "") | "\(.workflowName): \(.conclusion) (\(.createdAt[:10]))"')
        ok_lines=$(echo "$runs" | jq -r 'group_by(.workflowName) | map(max_by(.createdAt)) | .[] | select(.conclusion == "success" or .conclusion == "") | "\(.workflowName): \(if .conclusion == "" then .status else .conclusion end) (\(.createdAt[:10]))"')
        if [ -n "$red_lines" ]; then
            while IFS= read -r line; do warn "CI: $line"; done <<<"$red_lines"
        fi
        if [ -n "$ok_lines" ]; then
            while IFS= read -r line; do ok "CI: $line"; done <<<"$ok_lines"
        fi
    else
        warn "gh run list не ответил — CI-секция пропущена"
    fi

    # Авто-issues (mutation weekly, deferred-review): OR-фильтр через jq —
    # несколько --label у gh issue list означают AND, не OR.
    # gsub: вычищаем control-символы из заголовков (ANSI-смаглинг в терминал).
    local auto_issues
    if auto_issues=$(_gh issue list --state open --limit 100 --json number,title,createdAt,labels); then  # 100: с запасом против дефолтных 30 — в репо уже ~30 открытых
        echo "$auto_issues" | jq -r '.[] | select(.labels | any(.name == "type:mutation-report" or .name == "type:deferred-review")) | "#\(.number) \(.title[:60] | gsub("[\\u0000-\\u001F\\u007F]"; "")) — \((now - (.createdAt | fromdate)) / 86400 | floor) дн."' \
            | while IFS= read -r line; do [ -n "$line" ] && warn "не прочитано: $line"; done
    else
        warn "gh issue list не ответил — auto-issue секция пропущена"
    fi

    # Открытые PR с возрастом (gsub — та же чистка control-символов)
    local prs
    if prs=$(_gh pr list --json number,title,createdAt); then
        echo "$prs" | jq -r '.[] | "#\(.number) \(.title[:60] | gsub("[\\u0000-\\u001F\\u007F]"; "")) — \((now - (.createdAt | fromdate)) / 86400 | floor) дн."' \
            | while IFS= read -r line; do [ -n "$line" ] && warn "открыт PR: $line"; done
    else
        warn "gh pr list не ответил — PR-секция пропущена"
    fi

    return 0
}
report_accumulated

echo ""
if [ $failed -eq 0 ]; then
    printf '%sГотов к сессии.%s\n' "$GREEN" "$NC"
    exit 0
else
    printf '%s%d блокирующих проблем.%s Исправь перед началом работы.\n' "$RED" "$failed" "$NC"
    exit 1
fi
