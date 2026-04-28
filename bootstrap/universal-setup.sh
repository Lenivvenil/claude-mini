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
#   7. Stages commit-msg governance hook в ~/.claude/git-hooks/commit-msg
#
# Флаги:
#   --check         dry-run: показать diff без применения
#   --install       применить
#   --force         overwrite files that differ from the repo source (required on drift)
#   --hook-this-repo  install commit-msg hook into .git/hooks/ of current directory
#   --target <dir>  install pipeline commands into <dir>/.claude/commands/ (per-project, ADR-0018)
#
# Exit codes:
#   0  ok (including "no-op — already installed")
#   1  hardware layer not complete
#   2  missing required dependencies (jq, gh, claude)
#   3  install error / jq post-verify failure
#   4  drift detected in --install mode; re-run with --force to overwrite

set -uo pipefail

# Augment PATH for subshell invocations (e.g. Claude Code slash commands) where
# ~/.zshrc has not been sourced. Covers mise/uv user installs, Intel Homebrew,
# and Apple Silicon Homebrew. Idempotent if dirs are already present.
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# --- Colors & helpers ---
RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { printf "${CYN}[setup]${NC} %s\n" "$*"; }
ok()   { printf "  ${GRN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YEL}!${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; }
die()  { err "$*"; exit 3; }

# Drift counter — incremented by copy_file() in both --check and --install modes;
# elsewhere (env vars, symlinks) only in --check mode.
DRIFT=0
drift() { DRIFT=$((DRIFT+1)); warn "$@"; }

# --- Parse args ---
MODE=""
FORCE=0
TARGET_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --install) MODE="install"; shift ;;
        --force) FORCE=1; shift ;;
        --hook-this-repo) MODE="hook-this-repo"; shift ;;
        --target)
            [ $# -gt 1 ] || die "--target requires a path argument"
            TARGET_PATH="$2"
            shift 2
            ;;
        -h|--help)
            cat <<HELP
Usage: $0 [--check|--install|--hook-this-repo|--target <dir>] [--force]

  --check           dry-run: show what would happen (exits 0; drift reported in stdout)
  --install         apply changes (exits 4 if drift detected; re-run with --force to overwrite)
  --force           overwrite files that differ from the repo source (required on drift)
  --hook-this-repo  install commit-msg governance hook into .git/hooks/ of the current repo
                    (ADR-0011: per-project opt-in, requires --install to have been run first)
  --target <dir>    install pipeline commands into <dir>/.claude/commands/ (ADR-0018)
                    can be combined with --check (dry-run) or --force (overwrite)
HELP
            exit 0
            ;;
        *) die "Unknown flag: $1" ;;
    esac
done

# --target defaults to install mode if no explicit mode given
if [ -n "$TARGET_PATH" ] && [ -z "$MODE" ]; then
    MODE="install"
fi

if [ -z "$MODE" ]; then
    die "Specify --check, --install, --hook-this-repo, or --target <dir>. See $0 --help"
fi

# --- Early exit: --hook-this-repo mode ---
# Handled separately before prerequisite checks to keep it lightweight.
if [ "$MODE" = "hook-this-repo" ]; then
    STAGED_HOOK="$HOME/.claude/git-hooks/commit-msg"

    if [ ! -f "$STAGED_HOOK" ]; then
        err "Staged hook not found: $STAGED_HOOK"
        echo "  Run './bootstrap/universal-setup.sh --install' first to stage the hook." >&2
        exit 2
    fi

    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || {
        err "Not a git repository (current directory: $PWD)"
        exit 3
    }
    DEST_HOOK="$GIT_DIR/hooks/commit-msg"

    mkdir -p "$GIT_DIR/hooks"

    if [ -f "$DEST_HOOK" ] && ! cmp -s "$STAGED_HOOK" "$DEST_HOOK"; then
        if [ "$FORCE" != "1" ]; then
            warn "A different commit-msg hook already exists at $DEST_HOOK"
            echo "  Use --force to overwrite, or inspect with: diff $DEST_HOOK $STAGED_HOOK" >&2
            exit 4
        fi
        warn "Overwriting existing commit-msg hook (--force)"
    fi

    if [ -f "$DEST_HOOK" ] && cmp -s "$STAGED_HOOK" "$DEST_HOOK"; then
        ok "commit-msg hook already installed and up-to-date"
        exit 0
    fi

    cp "$STAGED_HOOK" "$DEST_HOOK" || die "cp failed: $DEST_HOOK"
    chmod +x "$DEST_HOOK" || die "chmod failed: $DEST_HOOK"
    cmp -s "$STAGED_HOOK" "$DEST_HOOK" || die "post-copy verification failed: $DEST_HOOK"
    ok "commit-msg governance hook installed → $DEST_HOOK"
    echo "  To verify: git commit -m 'bad message' (should be blocked)"
    echo "  To remove: rm $DEST_HOOK"
    exit 0
fi

# --- Early exit: --target mode (ADR-0018) ---
# Installs pipeline commands per-project; does NOT require platform.done.
if [ -n "$TARGET_PATH" ]; then
    SCRIPT_DIR_T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT_T="$(cd "$SCRIPT_DIR_T/.." && pwd)"
    VERSION_FILE="$REPO_ROOT_T/bootstrap/VERSION"

    [ -f "$VERSION_FILE" ] || die "bootstrap/VERSION not found — run from the claude-mini repo root"
    PIPELINE_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
    [ -z "$PIPELINE_VERSION" ] && die "bootstrap/VERSION is empty"
    echo "$PIPELINE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
        || die "bootstrap/VERSION must be X.Y.Z semver, got: $PIPELINE_VERSION"

    TARGET_DIR=$(cd "$TARGET_PATH" 2>/dev/null && pwd) \
        || die "Target directory not found: $TARGET_PATH"

    COMMANDS_DST="$TARGET_DIR/.claude/commands"
    VERSION_DST="$TARGET_DIR/.claude/pipeline-version"

    log "Target: $TARGET_DIR (pipeline v$PIPELINE_VERSION)"

    [ "$MODE" = "install" ] && mkdir -p "$COMMANDS_DST"

    # Temp dir for baked copies — cleaned on any exit
    BAKE_TMP=$(mktemp -d)
    trap 'rm -rf "$BAKE_TMP"' EXIT

    for f in "$REPO_ROOT_T"/bootstrap/commands/*.md; do
        [ -f "$f" ] || continue
        fname=$(basename "$f")
        dst="$COMMANDS_DST/$fname"
        baked="$BAKE_TMP/$fname"

        # Bake @@PIPELINE_VERSION@@ → actual version (| delimiter avoids issues with . in version)
        sed "s|@@PIPELINE_VERSION@@|$PIPELINE_VERSION|g" "$f" > "$baked"

        if [ -f "$dst" ] && cmp -s "$baked" "$dst"; then
            ok "$fname (identical, skip)"
        elif [ "$MODE" = "check" ]; then
            if [ -f "$dst" ]; then
                drift "$fname (would overwrite with --force)"
            else
                drift "$fname (would create)"
            fi
        elif [ -f "$dst" ] && [ "$FORCE" != "1" ]; then
            drift "$fname (exists, differs — use --force)"
            diff -u "$dst" "$baked" 2>/dev/null | head -10 | sed 's/^/    /'
        else
            cp "$baked" "$dst" || die "cp failed: $dst"
            ok "$fname → $COMMANDS_DST/"
        fi
    done

    # pipeline-version file
    if [ -f "$VERSION_DST" ] && [ "$(cat "$VERSION_DST")" = "$PIPELINE_VERSION" ]; then
        ok "pipeline-version $PIPELINE_VERSION (identical, skip)"
    elif [ "$MODE" = "check" ]; then
        if [ -f "$VERSION_DST" ]; then
            drift "pipeline-version (would update $(cat "$VERSION_DST") → $PIPELINE_VERSION)"
        else
            drift "pipeline-version (would create: $PIPELINE_VERSION)"
        fi
    elif [ -f "$VERSION_DST" ] && [ "$FORCE" != "1" ]; then
        drift "pipeline-version (installed: $(cat "$VERSION_DST"), source: $PIPELINE_VERSION — use --force)"
    else
        echo "$PIPELINE_VERSION" > "$VERSION_DST"
        ok "pipeline-version $PIPELINE_VERSION → $VERSION_DST"
    fi

    echo ""
    log "Done (target mode, pipeline v$PIPELINE_VERSION)"
    if [ "$DRIFT" -gt 0 ]; then
        if [ "$MODE" = "check" ]; then
            warn "drift: $DRIFT item(s) differ — run: ./bootstrap/universal-setup.sh --target $TARGET_DIR [--force]"
        else
            warn "drift: $DRIFT file(s) not updated — re-run with --force: ./bootstrap/universal-setup.sh --target $TARGET_DIR --force"
            exit 4
        fi
    else
        ok "no drift — idempotent ✓"
    fi
    exit 0
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
for d in agents skills commands hooks git-hooks scripts templates/claude-mini; do
    if [ "$MODE" = "install" ]; then
        mkdir -p "$CLAUDE_HOME/$d"
    fi
    ok "$CLAUDE_HOME/$d"
done

# --- Copy function with diff support ---
copy_file() {
    local src="$1"
    local dst="$2"
    local name="${dst#"$HOME"/}"

    if [ ! -f "$src" ]; then
        drift "$name (source missing — not in repo source tree)"
        return
    fi

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        ok "$name (identical, skip)"
        return
    fi

    if [ -f "$dst" ] && [ "$FORCE" != "1" ]; then
        drift "$name (exists, differs — use --force to overwrite)"
        diff -u "$dst" "$src" 2>/dev/null | head -20 | sed 's/^/    /'
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

# --- Slash commands are per-project (ADR-0018) ---
log "Slash commands: per-project install only."
log "  Run: ./bootstrap/universal-setup.sh --target <repo> to install commands into a project."

# --- Copy hooks ---
log "Copying hooks..."
for f in "$REPO_ROOT"/bootstrap/hooks/*.sh; do
    [ -f "$f" ] || continue
    copy_file "$f" "$CLAUDE_HOME/hooks/$(basename "$f")"
done

# --- Stage commit-msg governance hook for per-project install (ADR-0011) ---
# Copies commit-msg-governance.sh → ~/.claude/git-hooks/commit-msg (no extension — git convention).
# The hook is NOT installed into any repo here. Use --hook-this-repo inside a target repo.
log "Staging commit-msg governance hook..."
COMMIT_MSG_SRC="$REPO_ROOT/bootstrap/hooks/commit-msg-governance.sh"
COMMIT_MSG_DST="$CLAUDE_HOME/git-hooks/commit-msg"
if [ -f "$COMMIT_MSG_SRC" ]; then
    copy_file "$COMMIT_MSG_SRC" "$COMMIT_MSG_DST"
    if [ "$MODE" = "install" ] && [ -f "$COMMIT_MSG_DST" ]; then
        chmod +x "$COMMIT_MSG_DST"
    fi
else
    warn "commit-msg-governance.sh not found in bootstrap/hooks/ — skipping"
fi

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
    "export SOPS_AGE_KEY_FILE=\"\$HOME/.config/sops/age/keys.txt\""
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
        ok "$HOME/bin/$name (symlink OK)"
        continue
    fi

    if [ -e "$dst" ] && [ "$FORCE" != "1" ]; then
        warn "$HOME/bin/$name exists (not a symlink or points elsewhere; --force to replace)"
        continue
    fi

    if [ "$MODE" = "check" ]; then
        drift "$HOME/bin/$name (would create symlink → $src)"
    else
        ln -sf "$src" "$dst"
        ok "$HOME/bin/$name → $src"
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
if [ "$DRIFT" -gt 0 ] && [ "$MODE" = "install" ]; then
    warn "drift: $DRIFT file(s) differ from repo source — re-run with --force to apply: ./bootstrap/universal-setup.sh --install --force"
    exit 4
fi
if [ "$MODE" = "check" ]; then
    if [ "$DRIFT" -eq 0 ]; then
        ok "no drift — idempotent ✓"
    else
        warn "drift: $DRIFT item(s) differ — run '--install' to see diffs, '--install --force' to apply."
    fi
else
    echo "  Перезапусти shell или выполни: source ~/.zshrc"
    echo "  Проверь статус: mini-health"
fi
