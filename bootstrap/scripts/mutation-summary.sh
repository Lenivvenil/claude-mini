#!/usr/bin/env bash
# mutation-summary.sh — produces a GitHub Issue body for the weekly mutation testing report.
#
# Written for an uninitiated reader: includes a preamble explaining what mutation
# testing is and what each metric means, before presenting the results.
#
# Usage:
#   mutation-summary.sh [OPTIONS] > body.md
#
# Options (all optional; omit a language block if that language wasn't run):
#   --week YYYY-WW              ISO week label (default: current week)
#   --python-score N            Python mutation score (0-100)
#   --python-killed N           Python killed mutant count
#   --python-survived N         Python survived mutant count
#   --python-timeout N          Python timeout mutant count
#   --python-survivors-file F   Path to file listing surviving Python mutants
#   --js-score N                TS/JS mutation score (0-100)
#   --js-killed N               TS/JS killed count
#   --js-survived N             TS/JS survived count
#   --js-timeout N              TS/JS timeout count
#   --js-survivors-file F       Path to file listing surviving TS/JS mutants
#   --rust-score N              Rust mutation score (0-100)
#   --rust-killed N             Rust killed count
#   --rust-survived N           Rust survived count
#   --rust-timeout N            Rust timeout count
#   --rust-survivors-file F     Path to file listing surviving Rust mutants
#   --no-languages-detected     All three languages were absent; emit skip notice
#
# Exit codes: 0 always (summary script does not gate — the workflow gates via issue label)

set -euo pipefail

WEEK=""
PY_SCORE=""; PY_KILLED=""; PY_SURVIVED=""; PY_TIMEOUT="0"; PY_SURVIVORS=""; PY_STATUS="success"
JS_SCORE=""; JS_KILLED=""; JS_SURVIVED=""; JS_TIMEOUT="0"; JS_SURVIVORS=""; JS_STATUS="success"
RS_SCORE=""; RS_KILLED=""; RS_SURVIVED=""; RS_TIMEOUT="0"; RS_SURVIVORS=""; RS_STATUS="success"
NO_LANGUAGES=0
RUN_URL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --week)                  WEEK="$2";              shift 2 ;;
        --run-url)               RUN_URL="$2";           shift 2 ;;
        --python-score)          PY_SCORE="$2";          shift 2 ;;
        --python-killed)         PY_KILLED="$2";         shift 2 ;;
        --python-survived)       PY_SURVIVED="$2";       shift 2 ;;
        --python-timeout)        PY_TIMEOUT="$2";        shift 2 ;;
        --python-survivors-file) PY_SURVIVORS="$2";      shift 2 ;;
        --python-status)         PY_STATUS="$2";         shift 2 ;;
        --js-score)              JS_SCORE="$2";          shift 2 ;;
        --js-killed)             JS_KILLED="$2";         shift 2 ;;
        --js-survived)           JS_SURVIVED="$2";       shift 2 ;;
        --js-timeout)            JS_TIMEOUT="$2";        shift 2 ;;
        --js-survivors-file)     JS_SURVIVORS="$2";      shift 2 ;;
        --js-status)             JS_STATUS="$2";         shift 2 ;;
        --rust-score)            RS_SCORE="$2";          shift 2 ;;
        --rust-killed)           RS_KILLED="$2";         shift 2 ;;
        --rust-survived)         RS_SURVIVED="$2";       shift 2 ;;
        --rust-timeout)          RS_TIMEOUT="$2";        shift 2 ;;
        --rust-survivors-file)   RS_SURVIVORS="$2";      shift 2 ;;
        --rust-status)           RS_STATUS="$2";         shift 2 ;;
        --no-languages-detected) NO_LANGUAGES=1;         shift   ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$WEEK" ]; then
    WEEK=$(python3 -c "
from datetime import date
d = date.today()
iso = d.isocalendar()
print(f'{iso[0]}-W{iso[1]:02d}')
" 2>/dev/null || date +"%Y-W%V")
fi

# --- Helpers ---

_status_icon() {
    local score="$1"
    if [ "$score" -ge 80 ]; then
        printf "🟢"
    elif [ "$score" -ge 60 ]; then
        printf "🟡"
    else
        printf "🔴"
    fi
}

_status_label() {
    local score="$1"
    if [ "$score" -ge 80 ]; then
        printf "≥80%% — цель достигнута"
    elif [ "$score" -ge 60 ]; then
        printf "60–80%% — требует внимания"
    else
        printf "<60%% — ниже минимального gate"
    fi
}

_language_row() {
    local lang="$1" score="$2" killed="$3" survived="$4" timeout="$5" step_status="${6:-success}"
    local icon status
    if [ "$step_status" != "success" ]; then
        # Tool crashed — do not render 0% (would be indistinguishable from "all mutants survived")
        printf "| %s | ⚠ tool error | — | — | — | см. логи Actions |\n" "$lang"
        return
    fi
    icon=$(_status_icon "$score")
    status=$(_status_label "$score")
    printf "| %s | %s%% | %s | %s | %s | %s %s |\n" \
        "$lang" "$score" "$killed" "$survived" "$timeout" "$icon" "$status"
}

_survivors_section() {
    local lang="$1" file="$2"
    if [ -n "$file" ] && [ -f "$file" ] && [ -s "$file" ]; then
        printf "\n### Выжившие мутанты — %s\n\n" "$lang"
        printf '```\n'
        cat "$file"
        printf '```\n'
        printf "\n"
    fi
}

# --- Output ---

cat <<'PREAMBLE'
## Что такое mutation testing и зачем это нужно

Mutation testing — способ проверить, насколько тесты реально «видят» баги.
Инструмент вносит мелкие изменения в код (мутации): меняет `+` на `-`, убирает
условие, инвертирует сравнение. Затем запускает тесты. Если тесты не заметили
изменение — они не проверяют нужное поведение, даже если coverage 100%.

Запускается **еженедельно**, не на каждом PR — это намеренно: полный прогон
занимает 20–40 минут. Проверяется только код, изменившийся за прошедшую неделю.

## Что означают метрики

| Метрика | Значение |
|---|---|
| **Mutation score** | % мутантов, которых тесты «убили» (обнаружили). Цель: ≥80%. Минимум gate: 60%. |
| **Killed** | Мутация сломала хотя бы один тест. Хорошо — тесты покрывают это поведение. |
| **Survived** | Мутация прошла незамеченной. Тесты не проверяют этот участок по смыслу. |
| **Timeout** | Тест завис на мутанте. Нейтрально; исключается из score. |
| 🟢 | Score ≥80% — цель достигнута. |
| 🟡 | Score 60–80% — видимо, но не блокирует. |
| 🔴 | Score <60% — ниже gate, требует действий. |

PREAMBLE

printf "## Результаты прогона %s\n\n" "$WEEK"

if [ "$NO_LANGUAGES" -eq 1 ]; then
    cat <<'SKIP'
**Языков с production кодом не обнаружено — прогон пропущен.**

Workflow запустился и корректно обнаружил отсутствие Python (`src/*.py`),
TS/JS (`package.json` + `.ts`/`.js`), и Rust (`.rs`) файлов в репозитории.
Это ожидаемое поведение для bootstrap-репо без собственного production кода.

Если ты видишь этот отчёт для проекта с реальным кодом, убедись что:
- Python код лежит в `src/` (mutmut сканирует `--paths-to-mutate src/`)
- TS/JS проект имеет `package.json` в корне
- Rust код есть в репозитории (`.rs` файлы)

SKIP
    printf "\n---\n\n"
    printf "_Workflow установлен и работает корректно. Прогон мутаций начнётся автоматически, когда в репо появится production код._\n"
    exit 0
fi

HAS_RESULTS=0

if [ -n "$PY_SCORE" ]; then
    HAS_RESULTS=1
fi
if [ -n "$JS_SCORE" ]; then
    HAS_RESULTS=1
fi
if [ -n "$RS_SCORE" ]; then
    HAS_RESULTS=1
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    printf "_Данные для отчёта отсутствуют — все языковые блоки пропущены._\n\n"
    exit 0
fi

printf "| Язык | Score | Killed | Survived | Timeout | Статус |\n"
printf "|------|-------|--------|----------|---------|--------|\n"

if [ -n "$PY_SCORE" ] || [ "$PY_STATUS" != "success" ]; then
    _language_row "Python (mutmut)" "${PY_SCORE:-0}" "${PY_KILLED:-?}" "${PY_SURVIVED:-?}" "${PY_TIMEOUT:-0}" "$PY_STATUS"
fi
if [ -n "$JS_SCORE" ] || [ "$JS_STATUS" != "success" ]; then
    _language_row "TS/JS (Stryker)" "${JS_SCORE:-0}" "${JS_KILLED:-?}" "${JS_SURVIVED:-?}" "${JS_TIMEOUT:-0}" "$JS_STATUS"
fi
if [ -n "$RS_SCORE" ] || [ "$RS_STATUS" != "success" ]; then
    _language_row "Rust (cargo-mutants)" "${RS_SCORE:-0}" "${RS_KILLED:-?}" "${RS_SURVIVED:-?}" "${RS_TIMEOUT:-0}" "$RS_STATUS"
fi

printf "\n"

_survivors_section "Python" "$PY_SURVIVORS"
_survivors_section "TS/JS" "$JS_SURVIVORS"
_survivors_section "Rust" "$RS_SURVIVORS"

cat <<'FOOTER'
## Surviving mutants — что с этим делать

Для каждого выжившего мутанта выше: посмотри на строку файла и подумай, есть ли
у этого поведения тест. Если нет — добавь тест, который явно проверяет именно
это поведение (не coverage — смысл).

Если **один и тот же паттерн выживает несколько недель подряд** — это сигнал:
тесты структурно не покрывают этот класс изменений. Добавь запись в
`docs/anti-patterns.md` (решение оператора, не автоматически — Принцип 2).

---
FOOTER

if [ -n "$RUN_URL" ]; then
    printf "_Workflow run: %s_\n\n" "$RUN_URL"
fi
printf "_Implements: [docs/decisions/0025-mutation-testing-tool-selection.md](docs/decisions/0025-mutation-testing-tool-selection.md)_\n"
