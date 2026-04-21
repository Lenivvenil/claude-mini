#!/usr/bin/env bash
# universal-setup.sh — идемпотентный installer universal-слоя claude-mini.
#
# Что делает:
#   1. Проверяет hardware-layer done-flag (иначе отказывается работать)
#   2. Копирует agents/skills/commands/hooks/scripts в ~/.claude/
#   3. Патчит ~/.claude/settings.json через jq (добавляет PreToolUse hook
#      к existing массиву, не разрушая RTK или другие hooks)
#   4. Добавляет env vars в ~/.zshrc (idempotent)
#   5. Создаёт symlinks ~/bin/mini-* на session-scripts
#   6. Копирует templates в ~/.claude/templates/claude-mini/
#
# Флаги:
#   --check    dry-run: показать diff без применения
#   --install  применить
#   --force    перезаписать существующие файлы
#
# Exit codes:
#   0  ok (включая "no-op — уже установлено")
#   1  hardware layer не пройден, не могу продолжать
#   2  отсутствуют обязательные зависимости (jq, gh, claude)
#   3  ошибка при установке

set -uo pipefail

# --- Colors & helpers ---
RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { printf "${CYN}[setup]${NC} %s\n" "$*"; }
ok()   { printf "  ${GRN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YEL}!${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; }
die()  { err "$*"; exit 3; }

# Drift counter — only incremented inside MODE=check branches
DRIFT=0
drift() { DRIFT=$((DRIFT+1)); warn "$@"; }

# --- Parse args ---
MODE=""
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --install) MODE="install"; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help)
            cat <<HELP
Usage: $0 [--check|--install] [--force]

  --check     dry-run: показать что произойдёт
  --install   применить изменения
  --force     перезаписать существующие файлы (опасно)
HELP
            exit 0
            ;;
        *) die "Unknown flag: $1" ;;
    esac
done

if [ -z "$MODE" ]; then
    die "Specify --check or --install. See $0 --help"
fi

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_HOME="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_HOME/settings.json"
PLATFORM_FLAG="$HOME/.config/claude-mini/platform.done"
ZSHRC="$HOME/.zshrc"
BIN_DIR="$HOME/bin"

# --- Prerequisite checks ---
log "Prerequisite checks..."

for bin in jq claude gh; do
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin: $(command -v "$bin")"
    else
        err "$bin не найден в PATH"
        echo "  Это — hardware-layer step. См. bootstrap/hardware/<platform>.md" >&2
        exit 2
    fi
done

# --- Platform flag ---
log "Hardware layer check..."
if [ -f "$PLATFORM_FLAG" ]; then
    ok "platform.done flag present: $(cat "$PLATFORM_FLAG")"
else
    err "Hardware-layer не пройден: $PLATFORM_FLAG отсутствует"
    cat >&2 <<EOMSG

Universal-setup отказывается работать без подтверждения, что hardware-layer
пройден. Hardware-шаги (Homebrew, mise, LaunchAgents, Keychain, Tailscale
install и т.п.) не автоматизируются этим скриптом намеренно — они требуют
GUI-диалогов, физического доступа, или OS-specific actions.

Действия:
  1. Прочти bootstrap/hardware/<твоя платформа>.md
  2. Пройди все шаги вручную
  3. Создай флаг:
       mkdir -p ~/.config/claude-mini
       echo "mac-mini-2018-sequoia-2026-04-21" > ~/.config/claude-mini/platform.done
  4. Запусти этот скрипт снова

EOMSG
    exit 1
fi

# --- Ensure ~/.claude dirs exist ---
log "Ensuring ~/.claude/ directories..."
for d in agents skills commands hooks scripts templates/claude-mini; do
    if [ "$MODE" = "install" ]; then
        mkdir -p "$CLAUDE_HOME/$d"
    fi
    ok "$CLAUDE_HOME/$d"
done

# --- Copy function with diff support ---
copy_file() {
    local src="$1"
    local dst="$2"
    local name="${dst#$HOME/}"

    if [ ! -f "$src" ]; then
        warn "source missing: $src"
        return
    fi

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        ok "$name (identical, skip)"
        return
    fi

    if [ -f "$dst" ] && [ "$FORCE" != "1" ]; then
        if [ "$MODE" = "check" ]; then
            drift "$name (exists, differs — use --force to overwrite)"
            diff -u "$dst" "$src" 2>/dev/null | head -20 | sed 's/^/    /'
        else
            warn "$name (exists, not overwriting; use --force)"
        fi
        return
    fi

    if [ "$MODE" = "check" ]; then
        if [ -f "$dst" ]; then
            drift "$name (would overwrite with --force)"
        else
            drift "$name (would create)"
        fi
    else
        cp "$src" "$dst"
        if [[ "$dst" == *.sh ]]; then
            chmod +x "$dst"
        fi
        ok "$name (copied)"
    fi
}

# --- Copy agents ---
log "Copying agents..."
for f in "$REPO_ROOT"/bootstrap/agents/*.md; do
    [ -f "$f" ] || continue
    copy_file "$f" "$CLAUDE_HOME/agents/$(basename "$f")"
done

# --- Copy skills ---
log "Copying skills..."
for dir in "$REPO_ROOT"/bootstrap/skills/*/; do
    [ -d "$dir" ] || continue
    skill_name=$(basename "$dir")
    if [ "$MODE" = "install" ]; then
        mkdir -p "$CLAUDE_HOME/skills/$skill_name"
    fi
    # SKILL.md
    copy_file "$dir/SKILL.md" "$CLAUDE_HOME/skills/$skill_name/SKILL.md"
    # scripts/ если есть
    if [ -d "$dir/scripts" ]; then
        if [ "$MODE" = "install" ]; then
            mkdir -p "$CLAUDE_HOME/skills/$skill_name/scripts"
        fi
        for s in "$dir/scripts"/*; do
            [ -f "$s" ] || continue
            copy_file "$s" "$CLAUDE_HOME/skills/$skill_name/scripts/$(basename "$s")"
        done
    fi
done

# --- Copy commands ---
log "Copying slash commands..."
for f in "$REPO_ROOT"/bootstrap/commands/*.md; do
    [ -f "$f" ] || continue
    copy_file "$f" "$CLAUDE_HOME/commands/$(basename "$f")"
done

# --- Copy hooks ---
log "Copying hooks..."
for f in "$REPO_ROOT"/bootstrap/hooks/*.sh; do
    [ -f "$f" ] || continue
    copy_file "$f" "$CLAUDE_HOME/hooks/$(basename "$f")"
done

# --- Copy scripts ---
log "Copying scripts..."
for f in "$REPO_ROOT"/bootstrap/scripts/*.sh; do
    [ -f "$f" ] || continue
    copy_file "$f" "$CLAUDE_HOME/scripts/$(basename "$f")"
done

# --- Copy templates ---
log "Copying templates..."
for f in "$REPO_ROOT"/bootstrap/templates/*; do
    [ -f "$f" ] || continue
    copy_file "$f" "$CLAUDE_HOME/templates/claude-mini/$(basename "$f")"
done

# --- Patch settings.json via jq ---
log "Patching $CLAUDE_SETTINGS..."

# Абсолютный путь к hook
HOOK_PATH="$CLAUDE_HOME/hooks/pre-commit-governance.sh"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    if [ "$MODE" = "install" ]; then
        echo '{}' > "$CLAUDE_SETTINGS"
        ok "settings.json created (empty)"
    else
        warn "settings.json would be created (empty)"
    fi
fi

# Проверка что hook уже прописан
if [ -f "$CLAUDE_SETTINGS" ]; then
    existing=$(jq -r '.hooks.PreToolUse // [] | .[] | select(.matcher == "Bash") | .hooks[]?.command' "$CLAUDE_SETTINGS" 2>/dev/null || echo "")
    if echo "$existing" | grep -qF "$HOOK_PATH"; then
        ok "governance hook already in settings.json"
    else
        if [ "$MODE" = "check" ]; then
            drift "governance hook NOT in settings.json (would be added)"
            echo "    Would add to PreToolUse[matcher=Bash]: $HOOK_PATH"
        else
            # Patch: добавить hook к существующему PreToolUse Bash matcher,
            # или создать matcher если нет. Используем jq с тонкой логикой.
            if ! jq -e 'type == "object"' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
                err "Pre-verify: settings.json is not valid JSON — refusing to patch"
                exit 3
            fi
            before_cmds=$(jq -r '.hooks.PreToolUse[]? | select(.matcher=="Bash") | .hooks[]?.command' "$CLAUDE_SETTINGS" 2>/dev/null | sort -u)
            tmp=$(mktemp)
            jq \
                --arg cmd "$HOOK_PATH" \
                '
                .hooks = (.hooks // {})
                | .hooks.PreToolUse = (.hooks.PreToolUse // [])
                | (
                    (.hooks.PreToolUse | map(.matcher == "Bash") | any) as $has_bash_matcher
                    | if $has_bash_matcher then
                        .hooks.PreToolUse |= map(
                            if .matcher == "Bash" then
                                .hooks = ((.hooks // []) + [{"type": "command", "command": $cmd}])
                                | .hooks |= unique_by(.command)
                            else . end
                        )
                    else
                        .hooks.PreToolUse += [{
                            "matcher": "Bash",
                            "hooks": [{"type": "command", "command": $cmd}]
                        }]
                    end
                )
                ' \
                "$CLAUDE_SETTINGS" > "$tmp"
            # Post-verify: shape + all pre-existing commands preserved + governance present + no collateral damage
            post_ok=1
            if ! jq -e 'type == "object" and (.hooks.PreToolUse | type == "array")' "$tmp" >/dev/null 2>&1; then
                err "Post-verify: output is not a valid settings object"
                post_ok=0
            fi
            while IFS= read -r cmd; do
                [ -z "$cmd" ] && continue
                if ! jq -e --arg c "$cmd" '.hooks.PreToolUse[]? | select(.matcher=="Bash") | .hooks[]?.command | select(. == $c)' "$tmp" >/dev/null 2>&1; then
                    err "Post-verify: pre-existing command missing from output: $cmd"
                    post_ok=0
                fi
            done <<< "$before_cmds"
            if ! jq -e --arg h "$HOOK_PATH" '.hooks.PreToolUse[]? | select(.matcher=="Bash") | .hooks[]?.command | select(. == $h)' "$tmp" >/dev/null 2>&1; then
                err "Post-verify: governance hook missing from output"
                post_ok=0
            fi
            # Non-hooks keys must be unchanged (guards against filter accidentally dropping .mcpServers etc.)
            if ! diff <(jq -S 'del(.hooks)' "$CLAUDE_SETTINGS") <(jq -S 'del(.hooks)' "$tmp") >/dev/null 2>&1; then
                err "Post-verify: non-hooks settings were altered — settings.json не изменён"
                post_ok=0
            fi
            if [ "$post_ok" = "1" ]; then
                cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%s).$$"
                mv "$tmp" "$CLAUDE_SETTINGS"
                ok "governance hook added to PreToolUse[Bash]"
            else
                err "jq patch failed post-verification — settings.json не изменён"
                rm -f "$tmp"
                exit 3
            fi
        fi
    fi
fi

# --- Env vars в ~/.zshrc ---
log "Checking ~/.zshrc env vars..."
declare -a ENV_LINES=(
    'export CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL=1'
    'export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6'
    'export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-7'
    'export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"'
)

for line in "${ENV_LINES[@]}"; do
    key="${line#export }"; key="${key%%=*}"
    if [ -f "$ZSHRC" ] && grep -qE "^\s*export\s+${key}=" "$ZSHRC"; then
        ok "$key already in ~/.zshrc"
    else
        if [ "$MODE" = "check" ]; then
            drift "$key missing (would append to ~/.zshrc)"
        else
            echo "$line" >> "$ZSHRC"
            ok "$key appended to ~/.zshrc"
        fi
    fi
done

# --- Symlinks ~/bin/mini-* ---
log "Symlinks in ~/bin/..."
if [ "$MODE" = "install" ]; then
    mkdir -p "$BIN_DIR"
fi

declare -a SCRIPT_LINKS=(
    "mini-preflight:mini-preflight.sh"
    "mini-session:mini-session.sh"
    "mini-bootstrap-project:mini-bootstrap-project.sh"
    "mini-health:mini-health.sh"
)

for pair in "${SCRIPT_LINKS[@]}"; do
    name="${pair%%:*}"
    src_rel="${pair##*:}"
    src="$CLAUDE_HOME/scripts/$src_rel"
    dst="$BIN_DIR/$name"

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        ok "~/bin/$name (symlink OK)"
        continue
    fi

    if [ -e "$dst" ] && [ "$FORCE" != "1" ]; then
        warn "~/bin/$name exists (not a symlink or points elsewhere; --force to replace)"
        continue
    fi

    if [ "$MODE" = "check" ]; then
        drift "~/bin/$name (would create symlink → $src)"
    else
        ln -sf "$src" "$dst"
        ok "~/bin/$name → $src"
    fi
done

# --- Path check ---
if [ "$MODE" = "check" ] || [ "$MODE" = "install" ]; then
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
        warn "$BIN_DIR не в PATH. Добавь: export PATH=\"\$HOME/bin:\$PATH\" в ~/.zshrc"
    fi
fi

# --- Final summary ---
echo ""
log "Done ($MODE mode)"
if [ "$MODE" = "check" ]; then
    if [ "$DRIFT" -eq 0 ]; then
        ok "no drift — idempotent ✓"
    else
        warn "drift: $DRIFT item(s) need attention — запусти с --install чтобы применить."
        exit 1
    fi
else
    echo "  Перезапусти shell или выполни: source ~/.zshrc"
    echo "  Проверь статус: mini-health"
fi
