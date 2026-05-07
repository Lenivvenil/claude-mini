#!/usr/bin/env bash
# mini-bootstrap-demo.sh — guided tour of claude-mini pipeline without GitHub (#214)
#
# Modes:
#   (default)    Setup: git init, install pipeline commands, governance demo, guided steps
#   --finalize   Commit + summary (run after running /implement and /review in Claude Code)
#   --clean      Remove ~/claude-mini-demo to start fresh
#
# Run from claude-mini repo root:
#   bash bootstrap/scripts/mini-bootstrap-demo.sh
#   bash bootstrap/scripts/mini-bootstrap-demo.sh --finalize

set -uo pipefail

DEMO_DIR="$HOME/claude-mini-demo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_SRC="$REPO_ROOT/bootstrap/hooks/commit-msg-governance.sh"
SETUP_SH="$REPO_ROOT/bootstrap/universal-setup.sh"

GRN=$'\033[0;32m'
YEL=$'\033[0;33m'
RED=$'\033[0;31m'
CYN=$'\033[0;36m'
BLD=$'\033[1m'
NC=$'\033[0m'

ok()   { printf '  %s✓%s %s\n' "$GRN" "$NC" "$*"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$NC" "$*"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
step() { printf '\n%s%s━━━ %s ━━━%s\n' "$BLD" "$CYN" "$*" "$NC"; }

# ---- Parse arguments ----
MODE="setup"
while [ $# -gt 0 ]; do
    case "$1" in
        --finalize) MODE="finalize"; shift ;;
        --clean)    MODE="clean";    shift ;;
        -h|--help)
            printf 'Usage: %s [--finalize|--clean|--help]\n' "$0"
            printf '  (default)   Setup demo repo in ~/claude-mini-demo\n'
            printf '  --finalize  Commit + summary after Claude Code steps\n'
            printf '  --clean     Remove ~/claude-mini-demo to start over\n'
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\nRun: %s --help\n' "$1" "$0" >&2
            exit 1
            ;;
    esac
done

# ================================================================
# CLEAN
# ================================================================
if [ "$MODE" = "clean" ]; then
    if [ -d "$DEMO_DIR" ]; then
        printf 'Удалить %s? [y/N] ' "$DEMO_DIR"
        read -r _answer
        case "$_answer" in
            [yY]*) ;;
            *) printf 'Отменено.\n'; exit 0 ;;
        esac
        rm -rf "$DEMO_DIR"
        printf '%sRemoved: %s%s\n' "$GRN" "$DEMO_DIR" "$NC"
    else
        printf '%s not found — nothing to clean.\n' "$DEMO_DIR"
    fi
    exit 0
fi

# ================================================================
# FINALIZE
# ================================================================
if [ "$MODE" = "finalize" ]; then
    step "Финал демо"

    if [ ! -d "$DEMO_DIR/.git" ]; then
        err "$DEMO_DIR не найдена или не является git-репо."
        err "Сначала запустите setup: bash $0"
        exit 1
    fi

    if ! cd "$DEMO_DIR"; then
        err "Не удалось cd в $DEMO_DIR"
        exit 1
    fi

    printf '\n%sGit status:%s\n' "$BLD" "$NC"
    git status --short

    if ! git add .; then
        err "git add завершился с ошибкой"
        exit 1
    fi

    staged=$(git diff --cached --name-only 2>/dev/null || true)
    if [ -z "$staged" ]; then
        warn "Нет staged изменений."
        warn "Запустили ли вы /implement в Claude Code?"
        printf '\n  Подсказка: cd %s && claude, затем /implement\n' "$DEMO_DIR"
        exit 1
    fi

    ok "Staged файлы: $(printf '%s' "$staged" | tr '\n' ' ')"

    printf '\n%sКоммит через governance hook...%s\n' "$CYN" "$NC"
    git commit \
        -m "feat(demo): implement demo task" \
        -m "Closes #1"
    ok "Commit создан."

    step "Артефакты в $DEMO_DIR"
    printf '\n'
    git log --oneline -5
    printf '\n'
    for artifact in plan.md CONTRIBUTING.md README.md issue-1.md; do
        if [ -f "$artifact" ]; then
            printf '  %s%-20s%s — ' "$BLD" "$artifact" "$NC"
            case "$artifact" in
                plan.md)
                    printf 'карта задачи (6 разделов: проблема, файлы, подходы, решение, тест, риски)\n'
                    ;;
                CONTRIBUTING.md)
                    printf 'результат /implement — что создал Claude Code по плану\n'
                    ;;
                README.md)
                    printf 'seed-файл проекта\n'
                    ;;
                issue-1.md)
                    printf 'dummy issue — задание, которое читал /implement\n'
                    ;;
            esac
        fi
    done
    printf '\n  .claude/commands/ — установленные pipeline-команды:\n'
    for _f in .claude/commands/*.md; do
        if [ -f "$_f" ]; then
            printf '    %s\n' "$(basename "$_f")"
        fi
    done

    step "Демо завершено"
    printf '\n%sВот что произошло:%s\n\n' "$BLD" "$NC"
    printf '  1. bash mini-bootstrap-demo.sh\n'
    printf '       git init + pipeline-команды + governance hook установлены\n'
    printf '       plan.md и issue-1.md созданы (SAMPLE-шаблоны)\n\n'
    printf '  2. Claude Code / /implement\n'
    printf '       Claude прочитал plan.md и создал CONTRIBUTING.md\n\n'
    printf '  3. Claude Code / /review\n'
    printf '       Claude проверил изменение\n\n'
    printf '  4. bash mini-bootstrap-demo.sh --finalize\n'
    printf '       Git commit через установленный governance hook\n\n'
    printf '%sСледующий шаг:%s docs/onboarding/first-week.md — план на неделю.\n' "$GRN" "$NC"
    exit 0
fi

# ================================================================
# SETUP (default)
# ================================================================

printf '\n%s%s=== mini-bootstrap-demo ===%s\n' "$BLD" "$CYN" "$NC"
printf 'Создаём демо-окружение в: %s\n' "$DEMO_DIR"
printf 'GitHub не нужен. Ваш текущий проект не затрагивается.\n'

# ---- 1. Preflight ----
step "1. Preflight"

_miss=0
for _cmd in bash git; do
    if command -v "$_cmd" >/dev/null 2>&1; then
        ok "$_cmd доступен"
    else
        err "Нужен '$_cmd' — не найден в PATH"
        _miss=$((_miss + 1))
    fi
done

if [ ! -f "$HOOK_SRC" ]; then
    err "Не найден: $HOOK_SRC"
    err "Запускайте скрипт из корня claude-mini репо."
    exit 1
fi

if [ ! -f "$SETUP_SH" ]; then
    err "Не найден: $SETUP_SH"
    err "Запускайте скрипт из корня claude-mini репо."
    exit 1
fi

if [ "$_miss" -gt 0 ]; then
    err "Установите недостающие инструменты и повторите."
    exit 1
fi

ok "claude-mini repo: $REPO_ROOT"

# ---- 2. Create demo dir ----
step "2. Создаём demo-директорию"

if [ -d "$DEMO_DIR" ]; then
    warn "$DEMO_DIR уже существует."
    warn "Запустите --clean чтобы начать заново: bash $0 --clean"
    exit 1
fi

mkdir -p "$DEMO_DIR"
ok "Создана: $DEMO_DIR"

# ---- 3. git init ----
step "3. Git init"

if ! cd "$DEMO_DIR"; then
    err "Не удалось cd в $DEMO_DIR"
    exit 1
fi

if git init -b main 2>/dev/null; then
    ok "git init -b main"
else
    if ! git init 2>/dev/null; then
        err "git init завершился с ошибкой"
        exit 1
    fi
    if ! git symbolic-ref HEAD refs/heads/main; then
        err "Не удалось установить ветку main"
        exit 1
    fi
    ok "git init (ветка main через symbolic-ref)"
fi

# Set local git identity for demo commits; avoids "Please tell me who you are" on fresh macOS.
if ! git config user.email >/dev/null 2>&1; then
    git config --local user.email "demo@claude-mini.local"
    git config --local user.name "Claude Mini Demo"
    ok "git config: demo@claude-mini.local (локально, только для этого репо)"
fi

printf '# Demo project\n\nСоздан демо-скриптом claude-mini.\n' > README.md
ok "README.md создан"

# ---- 4. Install pipeline commands ----
step "4. Установка pipeline-команд"

if bash "$SETUP_SH" --target "$DEMO_DIR"; then
    ok "Pipeline-команды установлены в $DEMO_DIR/.claude/commands/"
else
    err "universal-setup.sh --target завершился с ошибкой."
    exit 1
fi

# ---- 5. Install governance hook ----
step "5. Установка governance hook"

mkdir -p "$DEMO_DIR/.git/hooks"
if ! cp "$HOOK_SRC" "$DEMO_DIR/.git/hooks/commit-msg"; then
    err "Не удалось скопировать governance hook"
    exit 1
fi
if ! chmod +x "$DEMO_DIR/.git/hooks/commit-msg"; then
    err "Не удалось сделать hook исполняемым"
    exit 1
fi
ok "Governance hook: .git/hooks/commit-msg"

# ---- 6. Seed files ----
step "6. Создаём стартовые файлы"

_today=$(date +%Y-%m-%d)

cat > issue-1.md <<'ISSUE_EOF'
# Issue #1: Add CONTRIBUTING.md

## Задача

Добавить `CONTRIBUTING.md` с базовыми инструкциями для контрибьюторов.

## Acceptance Criteria

- [ ] CONTRIBUTING.md создан
- [ ] Есть секции: Setup, Making Changes, Opening a PR
ISSUE_EOF
ok "issue-1.md создан (dummy issue)"

cat > plan.md <<PLAN_EOF
<!-- SAMPLE — pre-seeded by mini-bootstrap-demo.sh, not produced by /plan -->
# plan.md — demo issue #1: Add CONTRIBUTING.md

**Issue:** #1 | **Date:** $_today | **Status:** draft

---

## 1. Problem restatement

Новый репо не имеет CONTRIBUTING.md. Контрибьюторы не знают как делать PR.

---

## 2. Affected bounded contexts and files

| Файл | Действие |
|---|---|
| CONTRIBUTING.md | Новый — базовые инструкции для контрибьюторов |

---

## 3. Considered approaches

### A. Минимальный CONTRIBUTING.md (chosen)

Setup + Making Changes + Opening a PR — три секции, достаточно.

### B. Полный contributing guide

Избыточно для демо-проекта.

**Выбор: A.**

---

## 4. Chosen approach and why

Создать CONTRIBUTING.md с тремя секциями. Нет новых зависимостей. ADR не нужен.

---

## 5. Test strategy

Проверить что файл создан и содержит три заголовка.

---

## 6. Risks and unknowns

Нет рисков — документ нового репо.
PLAN_EOF
ok "plan.md создан (SAMPLE — см. заголовок файла)"

# ---- 7. Governance hook demo (before staging — only Rules 1 & 2 in play) ----
step "7. Демонстрация governance hook"

printf '\n  Governance hook проверяет каждый commit message по трём правилам:\n'
printf '    Rule 1: Conventional Commits prefix (feat|fix|docs|chore|...)\n'
printf '    Rule 2: ссылка на issue (#NNN) в сообщении или имени ветки\n'
printf '    Rule 3: ссылка на ADR если staged файлы в docs/decisions/\n'
printf '  (Rule 3 не срабатывает — нет staged файлов в docs/decisions/)\n'
printf '\n'

_bad=$(mktemp "${TMPDIR:-/tmp}/demo-bad.XXXXXX")
_good=$(mktemp "${TMPDIR:-/tmp}/demo-good.XXXXXX")
_hook_out=$(mktemp "${TMPDIR:-/tmp}/demo-hook-out.XXXXXX")
printf 'bad commit: just adding files' > "$_bad"
printf 'chore(demo): setup demo project\n\nCloses #1\n' > "$_good"

printf '  Тест 1: плохое сообщение — должен заблокировать\n'
if bash "$DEMO_DIR/.git/hooks/commit-msg" "$_bad" >"$_hook_out" 2>&1; then
    warn "Hook не заблокировал (неожиданно). Вывод hook:"
    sed 's/^/    /' "$_hook_out" >&2
else
    ok "Заблокировал: \"bad commit: just adding files\""
fi

printf '  Тест 2: правильное сообщение — должен пропустить\n'
if bash "$DEMO_DIR/.git/hooks/commit-msg" "$_good" >"$_hook_out" 2>&1; then
    ok "Пропустил: \"chore(demo): setup demo project\""
else
    warn "Заблокировал правильное сообщение (неожиданно). Вывод hook:"
    sed 's/^/    /' "$_hook_out" >&2
fi

rm -f "$_bad" "$_good" "$_hook_out"

# ---- 8. Stage & initial commit ----
step "8. Первый commit"

if ! git add .; then
    err "git add завершился с ошибкой"
    exit 1
fi

# .github/workflows/mutation.yml was placed by --target (ADR-0018); reference it.
if ! git commit \
        -m "chore(demo): setup demo project" \
        -m "Implements ADR-0018" \
        -m "Closes #1"; then
    err "git commit не прошёл — смотрите вывод hook выше"
    exit 1
fi
ok "Commit создан через governance hook."

# ---- 9. Guided next steps ----
step "9. Что делать дальше"

printf '\n%s%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$BLD" "$CYN" "$NC"
printf '\n  Теперь открой Claude Code в демо-репо и пройди pipeline-шаги:\n\n'
printf '  %s1.%s Открой новый терминал:\n' "$BLD" "$NC"
printf '       cd %s\n' "$DEMO_DIR"
printf '       git checkout -b feat/add-contributing-1\n'
printf '       claude\n\n'
printf '  %s2.%s Внутри Claude Code — реализуй задачу по плану:\n' "$BLD" "$NC"
printf '       /implement\n'
printf '     (Claude прочитает plan.md и создаст CONTRIBUTING.md)\n\n'
printf '  %s3.%s Просмотри результат:\n' "$BLD" "$NC"
printf '       /review\n'
printf '     (Claude проверит изменение и вынесет вердикт)\n\n'
printf '  %s4.%s Выйди из Claude Code (Ctrl+C или /exit)\n\n' "$BLD" "$NC"
printf '  %s5.%s Вернись сюда и запусти финал:\n' "$BLD" "$NC"
printf '       bash %s --finalize\n' "$REPO_ROOT/bootstrap/scripts/mini-bootstrap-demo.sh"
printf '\n%s%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$BLD" "$CYN" "$NC"
printf 'Артефакты для изучения: %s\n' "$DEMO_DIR"
