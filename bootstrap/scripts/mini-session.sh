#!/usr/bin/env bash
# mini-session <project-name> — старт сессии: cd, активация mise, tmux window, claude
#
# Использование:
#   mini-session claude-mini   — открывает в ~/projects/claude-mini
#   mini-session               — в текущей директории

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/projects}"

if [ $# -eq 0 ]; then
    target_dir="$PWD"
    session_name="$(basename "$PWD")"
else
    target_dir="$PROJECT_ROOT/$1"
    session_name="$1"
fi

if [ ! -d "$target_dir" ]; then
    echo "Directory not found: $target_dir" >&2
    exit 1
fi

cd "$target_dir"

# Warm mise
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash 2>/dev/null || mise env -s bash 2>/dev/null || true)"
fi

# Preflight (non-blocking — warn but proceed)
if [ -x "$HOME/.claude/scripts/mini-preflight.sh" ]; then
    "$HOME/.claude/scripts/mini-preflight.sh" || echo "Preflight warnings above — продолжаем."
fi

echo ""
echo "=== Starting claude session for $session_name ==="
echo "Directory: $target_dir"
echo ""

# Если в tmux — переименовать текущее окно; иначе — просто запустить claude
if [ -n "${TMUX:-}" ]; then
    tmux rename-window "$session_name" 2>/dev/null || true
fi

exec claude --model "${CLAUDE_MODEL:-sonnet}"
