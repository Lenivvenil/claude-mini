#!/usr/bin/env bash
# posttooluse-format.sh — Claude Code PostToolUse hook
#
# Запускается после Edit|MultiEdit|Write. Проверяет отформатирован ли файл
# и нет ли lint-ошибок. Результат — additionalContext в JSON (виден Claude).
# Всегда exit 0: PostToolUse не может заблокировать инструмент.
#
# Per-language:
#   Python (.py)     → ruff format --check + ruff check
#   JS/TS (.js/.ts)  → prettier --check + eslint (если конфиг есть)
#   Go (.go)         → gofmt -l + go vet
#
# Логирует в $POSTTOOLUSE_LOG (default: ~/.claude/hooks/posttooluse.log).
# POSTTOOLUSE_LOG=<path> переопределяет путь (для тестов).

set -uo pipefail

LOG_FILE="${POSTTOOLUSE_LOG:-$HOME/.claude/hooks/posttooluse.log}"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

log_entry() {
    if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
        echo "[posttooluse-format] log unavailable (mkdir failed): $*" >&2
        return
    fi
    echo "$TIMESTAMP $TOOL_NAME $*" >> "$LOG_FILE" || \
        echo "[posttooluse-format] log write failed: $*" >&2
}

emit_context() {
    local msg="$1"
    jq -n --arg ctx "$msg" '{
        hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: $ctx
        }
    }'
}

# --- jq prerequisite ---
if ! command -v jq >/dev/null 2>&1; then
    log_entry "ERROR jq not found — hook disabled"
    exit 0
fi

# --- Parse payload ---
input=$(cat)
TOOL_NAME=$(echo "$input" | jq -r '.tool_name // "?"' 2>/dev/null || echo "?")
file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

if [ -z "$file" ]; then
    log_entry "SKIP no file_path in payload"
    exit 0
fi

if [ ! -f "$file" ]; then
    log_entry "SKIP file not found: $file"
    exit 0
fi

ext="${file##*.}"
findings=""

# --- Python ---
if [ "$ext" = "py" ]; then
    if ! command -v ruff >/dev/null 2>&1; then
        log_entry "SKIP ruff not found: $file"
        exit 0
    fi

    fmt_out=$(ruff format --check -- "$file" 2>&1); fmt_rc=$?
    lint_out=$(ruff check --output-format=concise -- "$file" 2>&1); lint_rc=$?

    if [ $fmt_rc -ne 0 ]; then
        findings="${findings}[ruff format] $file would be reformatted. "
    fi
    if [ $lint_rc -ne 0 ]; then
        findings="${findings}[ruff check] $lint_out "
    fi

    log_entry "py fmt=$fmt_rc lint=$lint_rc: $file"

# --- JavaScript / TypeScript ---
elif [ "$ext" = "js" ] || [ "$ext" = "ts" ] || [ "$ext" = "jsx" ] || [ "$ext" = "tsx" ]; then
    if ! command -v prettier >/dev/null 2>&1; then
        log_entry "SKIP prettier not found: $file"
        exit 0
    fi

    fmt_out=$(prettier --check -- "$file" 2>&1); fmt_rc=$?
    if [ $fmt_rc -ne 0 ]; then
        findings="${findings}[prettier] $file is not formatted. "
    fi

    # eslint только если конфиг есть в cwd
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
    eslint_config_found=false
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
        for cfg in "$cwd"/.eslintrc* "$cwd"/eslint.config.*; do
            [ -f "$cfg" ] && eslint_config_found=true && break
        done
    fi

    lint_rc=0
    if [ "$eslint_config_found" = "true" ] && command -v eslint >/dev/null 2>&1; then
        lint_out=$(eslint --format=stylish -- "$file" 2>&1); lint_rc=$?
        if [ $lint_rc -ne 0 ]; then
            findings="${findings}[eslint] $lint_out "
        fi
    fi

    log_entry "js/ts fmt=$fmt_rc lint=$lint_rc: $file"

# --- Go ---
elif [ "$ext" = "go" ]; then
    if ! command -v gofmt >/dev/null 2>&1; then
        log_entry "SKIP gofmt not found: $file"
        exit 0
    fi

    fmt_out=$(gofmt -l -- "$file" 2>&1); fmt_rc=$?
    if [ -n "$fmt_out" ]; then
        findings="${findings}[gofmt] $file is not formatted. "
    fi

    vet_rc=0
    if command -v go >/dev/null 2>&1; then
        vet_out=$(go vet -- "$file" 2>&1); vet_rc=$?
        if [ $vet_rc -ne 0 ]; then
            findings="${findings}[go vet] $vet_out "
        fi
    fi

    fmt_changed=0; [ -n "$fmt_out" ] && fmt_changed=1
    log_entry "go fmt_changed=$fmt_changed vet=$vet_rc: $file"

# --- Unknown extension ---
else
    log_entry "SKIP unknown extension .$ext: $file"
    exit 0
fi

# --- Emit findings to Claude if any ---
if [ -n "$findings" ]; then
    findings="${findings% }"
    emit_context "Format/lint issues after write — fix before committing: $findings"
else
    log_entry "clean: $file"
fi

exit 0
