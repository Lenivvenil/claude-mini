#!/usr/bin/env bash
# create-backlog.sh — создаёт initial backlog (12 issues) в Lenivvenil/claude-mini.
#
# Предусловия:
#   • deploy-to-github.sh успешно отработал (репо, labels, milestones созданы)
#   • gh аутентифицирован
#
# Идемпотентность: повторный запуск не дублирует issues — сверяет по title.
#
# Использование:
#   ./create-backlog.sh [--dry-run]

set -euo pipefail

OWNER="Lenivvenil"
REPO="claude-mini"
FULL="${OWNER}/${REPO}"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

say() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
die() { printf "\033[1;31mXX\033[0m %s\n" "$*" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || die "gh не аутентифицирован"
gh repo view "$FULL" >/dev/null 2>&1 || die "Репо ${FULL} не существует — сначала ./deploy-to-github.sh"

# Получаем map existing issues по title → number
mapfile -t EXISTING < <(gh issue list --repo "$FULL" --state all --limit 100 --json title --jq '.[].title' 2>/dev/null || true)

create_issue() {
    local title="$1" milestone="$2" body="$3"
    shift 3
    local labels=("$@")

    # Проверка дубликата
    for existing_title in "${EXISTING[@]}"; do
        if [ "$existing_title" = "$title" ]; then
            echo "  · #? ${title} (exists)"
            return 0
        fi
    done

    local label_args=""
    for l in "${labels[@]}"; do
        label_args+=" --label \"$l\""
    done

    if $DRY_RUN; then
        echo "  (dry) + ${title}"
        echo "        milestone=${milestone}, labels=${labels[*]}"
        return 0
    fi

    # gh issue create через stdin для body
    local num
    num=$(echo "$body" | eval gh issue create --repo "$FULL" \
        --title "\"$title\"" \
        --milestone "\"$milestone\"" \
        $label_args \
        --body-file - \
        --json number \
        --jq .number 2>/dev/null) || {
            echo "  ! failed: $title"
            return 1
        }
    echo "  + #${num} ${title}"
}

say "Создаю 12 initial issues"

# ============================================================================
# M0: Baseline verified
# ============================================================================

create_issue \
    "Verify universal-setup.sh idempotency on mini" \
    "M0: baseline verified" \
    "## Контекст

Идемпотентность \`bootstrap/universal-setup.sh\` — базовое обещание: повторный запуск не должен разрушать существующую установку.

Из ADR 0008 и memory: \`settings.json\` уже содержит RTK hook на Bash. Новый governance hook должен добавляться к тому же matcher через \`jq\`, не заменяя весь массив.

## Acceptance criteria

- [ ] На mini: запустить \`./bootstrap/universal-setup.sh --check\` — должен показать уже установленные артефакты как skip, новые как add
- [ ] Запустить \`./bootstrap/universal-setup.sh --install\`
- [ ] Запустить \`./bootstrap/universal-setup.sh --check\` повторно — должно показать \"no drift\" (exit 0, нет новых add)
- [ ] Проверить, что \`jq '.hooks.PreToolUse[] | select(.matcher == \"Bash\")' ~/.claude/settings.json\` возвращает БЫВШИЙ RTK hook И новый governance hook — оба сохранены
- [ ] Проверить, что \`~/.claude/agents/\` содержит все 6 агентов
- [ ] Проверить, что \`~/.claude/commands/\` содержит все 10 команд
- [ ] Проверить, что \`~/.claude/skills/\` содержит все 3 скилла
- [ ] Проверить, что symlinks \`~/bin/mini-*\` созданы и указывают в \`~/.claude/scripts/\`

## Риски

- RTK hook может быть перезаписан если \`jq\`-патч неверный — проверить руками перед apply
- \`~/.zshrc\` env vars могут задублироваться — скрипт должен grep перед add

## Definition of Done

Все чек-пункты выше; плюс \`mini-health\` возвращает зелёный статус." \
    "area:bootstrap" "P0-critical" "estimate/3" "type:spike"

create_issue \
    "Smoke-test governance hook with deliberately bad commits" \
    "M0: baseline verified" \
    "## Контекст

ADR 0004 заявляет, что PreToolUse governance hook блокирует плохие коммиты. Smoke-test на \`venil-smoketest-20260420\` PR #2 прошёл без проверки с **заведомо плохим input'ом** — это ложно-положительный \"pass\".

Из состояния проекта: \"hook path должен быть АБСОЛЮТНЫМ — тильду Claude Code не раскрывает\". Это gotcha, на которую уже наступили.

## Acceptance criteria

Каждый из следующих плохих commit'ов должен быть **заблокирован** (exit 2) с понятным error message:

- [ ] Commit без Conventional Commits префикса: \`git commit -m \"just did some stuff\"\`
- [ ] Commit без issue-ref: \`git commit -m \"feat: add new thing\"\` (без #NNN и без \`Closes #\` в branch или message)
- [ ] Commit с decision-type изменением без ADR-ref: правка \`docs/decisions/\` + \`git commit -m \"chore: update adr (#1)\"\` но без \`Implements docs/decisions/NNNN\` в body
- [ ] Breaking change без \`!\`: \`git commit -m \"feat: rename public API\"\` (без \`feat!:\`)

И **разрешены**:

- [ ] \`git commit -m \"feat: add X (#1)\"\` — valid CC + issue ref
- [ ] \`git commit -m \"feat!: rename public API (#1)\"\` — breaking с exclamation

## Deliverable

- [ ] Добавить diagnostic команду в \`mini-health\` для проверки hook'а с plain input (не через Claude)
- [ ] Записать в \`docs/runbooks/incident-recovery.md\` как проверять hook когда он \"молчит\"
- [ ] Закрыть gap из state.md: \"нет git-level commit-msg hook для terminal-direct bypass\" — для этого отдельное issue M2

## Definition of Done

Чек-лист выше; короткий отчёт в комментарий перед close." \
    "area:governance" "P0-critical" "estimate/3" "type:feature"

create_issue \
    "Install missing universal artefacts on mini via universal-setup.sh" \
    "M0: baseline verified" \
    "## Контекст

По состоянию после миграции 20 апреля на mini установлено **частично**:
- 3 агента из 6 (нет: domain-researcher, solutions-architect, security-reviewer)
- 5 команд из 10 (нет: /plan, /implement, /adr, /backlog-review, /feature)
- 2 скилла из 3 (нет: project-bootstrap)

Smoke-test \`venil-smoketest-20260420\` PR #2 прошёл **без** /plan, /implement, /adr — Claude имитировал стадии в голове. Это не полноценный pipeline.

## Acceptance criteria

После \`./bootstrap/universal-setup.sh --install\` на mini:

- [ ] \`ls ~/.claude/agents/ | wc -l\` = 6
- [ ] \`ls ~/.claude/commands/ | wc -l\` = 10
- [ ] \`ls ~/.claude/skills/ | wc -l\` = 3
- [ ] В \`~/.claude/skills/project-bootstrap/\` есть SKILL.md
- [ ] \`~/.claude/scripts/\` содержит 5 session-скриптов
- [ ] \`~/bin/\` содержит symlinks \`mini-preflight\`, \`mini-session\`, \`mini-bootstrap-project\`, \`mini-health\`
- [ ] \`which mini-preflight\` и \`mini-preflight --dry-run\` работают
- [ ] Запустить \`claude\` с новой командой \`/plan 1\` в sandbox-репо — команда распознаётся

## Блокеры

Зависит от issue \"Verify universal-setup.sh idempotency\" — must pass first.

## Definition of Done

Чек-пункты + короткий комментарий с выводом \`ls\` для подтверждения." \
    "area:agents" "area:commands" "area:skills" "P1-high" "estimate/2" "type:feature"

create_issue \
    "Empirically confirm advisor Opus billing against weekly cap" \
    "M0: baseline verified" \
    "## Контекст

ADR 0003 признаёт: не публично подтверждено, биллятся ли \`advisor()\` вызовы на weekly Opus cap или на общий pool. Вся экономика pipeline-over-fanout зависит от ответа.

## Acceptance criteria

- [ ] Снять baseline \`/usage\` в начале рабочего дня (Opus used %, Sonnet used %)
- [ ] Провести обычный день работы с интенсивным использованием advisor (целевое — 10+ вызовов на разных задачах)
- [ ] Снять \`/usage\` в конце дня
- [ ] Рассчитать: **реальное** потребление Opus vs **ожидаемое** по числу advisor-вызовов × средний token count
- [ ] Если совпадение — значит биллятся. Если реальное сильно меньше ожидаемого — значит нет.

## Deliverable

- [ ] Обновить ADR 0003 секцию Confirmation: фактические цифры
- [ ] Если биллятся: пересчитать рекомендуемый budget advisor-вызовов в неделю и обновить CLAUDE.md

## Риски

- Один день может быть нерепрезентативным — желательно повторить через неделю на другой нагрузке.
- \`/usage\` может не показывать split по source (direct vs advisor) — в этом случае нужно считать через API logs если доступны.

## Definition of Done

ADR 0003 обновлён; короткая записка в \`docs/metrics/advisor-billing-experiment.md\`." \
    "area:docs" "P1-high" "estimate/3" "type:spike"

# ============================================================================
# M1: Pipeline proven on real project
# ============================================================================

create_issue \
    "First real feature through full pipeline end-to-end" \
    "M1: pipeline proven on real project" \
    "## Контекст

Весь скоуп проекта — доказать, что pipeline работает. До сих пор он не прошёл на реальной задаче в этом репо (\`Lenivvenil/claude-mini\`), только на \`venil-smoketest-20260420\` PR #2 (и там без половины стадий).

## Выбор задачи

Рекомендация: взять issue с подходящей архитектурной значимостью, чтобы сработал путь \`/plan → /adr → /implement\`. Например: **Issue \"Populate docs/domain/ with project's own vocabulary\"** или **\"Add Linux hardware-runbook skeleton\"**.

## Acceptance criteria

Задача пройдёт полный pipeline:

- [ ] \`/task-to-issue\` (если из TODO) или существующий issue выбран
- [ ] \`/feature <issue-number>\` создал TodoWrite checklist
- [ ] \`/plan <issue>\` написал plan.md
- [ ] advisor() вызван 1 раз на критику плана
- [ ] \`/adr <slug>\` если архитектурно (MADR 4.0 интервью полное)
- [ ] ADR PR прошёл через \`@agent-adr-reviewer\` и merged
- [ ] \`/implement\` со вторым advisor() вызовом перед done
- [ ] \`/review\` выдал findings (или clean)
- [ ] \`/codex-review\` — успех или \`type:deferred-review\`
- [ ] \`git commit\` прошёл через governance hook (без manual override)
- [ ] PR body содержит \`Closes #N\` и \`Implements docs/decisions/NNNN\`
- [ ] PR merged

## Deliverable

- [ ] **Session log** в \`docs/runbooks/first-feature-session-log.md\` — что пошло плохо, где pipeline жал, какие gotchas найдены
- [ ] Open new issues для каждого gap'а, найденного в pipeline (если что-то не взлетело)

## Definition of Done

Pipeline полностью пройден + session log записан." \
    "P1-high" "estimate/8" "type:epic"

create_issue \
    "Enrich onboarding-repo runbook from first real practice" \
    "M1: pipeline proven on real project" \
    "## Контекст

\`docs/runbooks/onboarding-repo.md\` сейчас содержит теоретический скелет. После того как pipeline реально пройдёт на первой задаче (см. issue \"First real feature\"), runbook нужно обогатить **практикой**: какие шаги потребовали уточнения, что было неочевидно, какие команды работают в каком порядке.

## Acceptance criteria

- [ ] Прочесть существующий \`docs/runbooks/onboarding-repo.md\`
- [ ] Собрать заметки из session log предыдущей задачи
- [ ] Добавить секции:
  - [ ] Pre-flight checklist (что проверить на mini перед \`claude\` запуском)
  - [ ] Gotchas найденные на практике (минимум 3 из реального опыта)
  - [ ] \"Что делать если advisor недоступен\" (Opus cap исчерпан)
  - [ ] \"Что делать если Codex flake на неделе лимит\"
- [ ] Runbook должен пройти собственный pipeline (ADR не нужен, /plan → /implement → /review достаточно)

## Блокеры

Зависит от \"First real feature through full pipeline\" — нужен реальный session log.

## Definition of Done

Runbook актуален, покрывает реальные gotchas, merged в main." \
    "area:docs" "type:runbook" "P2-medium" "estimate/3"

create_issue \
    "Establish weekly /project-health rhythm" \
    "M1: pipeline proven on real project" \
    "## Контекст

\`/project-health\` command установлен и готов. Нужно превратить его в **ритуал** — каждую пятницу запускать, записывать отчёт в \`docs/metrics/health-YYYY-WW.md\`, смотреть на threshold breaches и опcoming ADR gap.

## Acceptance criteria

- [ ] Запустить \`/project-health\` в первую пятницу после deploy'а
- [ ] Отчёт записан в \`docs/metrics/health-YYYY-WW.md\`
- [ ] Настроить календарь / reminder на еженедельный запуск (напомнинание в Things/Reminder/whatever)
- [ ] Добавить в \`docs/runbooks/weekly-maintenance.md\` чек-лист пятничного ритма
- [ ] Прогнать 3 недели подряд — проверить, что метрики показывают тренд, не только snapshot

## Deliverable

- [ ] 3 weekly-отчёта в \`docs/metrics/\`
- [ ] Итоговая заметка: что ритуал даёт на практике — что ловит, что мимо

## Definition of Done

3 последовательных недели; заметка о ценности ритуала." \
    "area:docs" "P2-medium" "estimate/2" "type:feature"

create_issue \
    "Verify two-voice review catches real miss (30-day window)" \
    "M1: pipeline proven on real project" \
    "## Контекст

ADR 0005 содержит Confirmation-критерий: \"за 30 дней Codex нашёл ≥ 1 не-false-positive в PR, который \`/review\` пропустил\". Если нет — возврат к single-voice (Option A).

Это не spike, это observational experiment на нормальной работе. Задача — не забыть собрать данные.

## Acceptance criteria

- [ ] На каждом PR в claude-mini в первые 30 дней: отмечать в PR body секцию \`## Two-voice diff\` — что нашёл \`/review\` vs что нашёл \`/codex-review\`, сошлись ли
- [ ] Через 30 дней: посчитать \`codex_unique_findings\` — сколько раз Codex нашёл не-false-positive, пропущенный Claude
- [ ] Посчитать \`type:deferred-review\` issues — какой % PR'ов фактически прошёл без two-voice
- [ ] Записать заметку в \`docs/metrics/two-voice-evaluation-YYYY-MM.md\`

## Decision

Если \`codex_unique_findings == 0\` в ≥ 10 PR → close ADR 0005 как \"superseded, back to single-voice\" и open soil-ADR для перехода на Option A.

Если \`type:deferred-review\` > 20% → open ADR для Option D (локальный Qwen3-Coder).

## Definition of Done

30 дней данных; заметка; если triggered — открыть соответствующий ADR." \
    "area:governance" "P2-medium" "estimate/3" "type:spike"

# ============================================================================
# M2: Enforcement hardened
# ============================================================================

create_issue \
    "Phase 2 governance: add git-level commit-msg hook" \
    "M2: enforcement hardened" \
    "## Контекст

ADR 0004 признаёт gap: PreToolUse hook (phase 1) защищает только коммиты **через Claude**. Прямой \`git commit\` из терминала обходит governance. Phase 2 — git-level \`commit-msg\` hook через \`core.hooksPath\`.

Из state.md: этот gap явно не закрыт и известен.

## Acceptance criteria

- [ ] Написать \`bootstrap/hooks/commit-msg-governance.sh\` — bash скрипт, принимающий файл с commit message, возвращающий exit 1 на violation
- [ ] Те же три правила, что в PreToolUse-версии: CC prefix, issue-ref, ADR-ref для decision-type
- [ ] Обновить \`bootstrap/universal-setup.sh\`:
  - Копирует hook в \`~/.claude/hooks/commit-msg-governance.sh\`
  - Настраивает \`git config --global core.hooksPath ~/.claude/git-hooks\` ИЛИ per-project install
  - Решить какой вариант через отдельный ADR (глобально vs per-project)
- [ ] Написать ADR 0009 \"git-level governance phase 2\" с decision по scope (global vs per-project)
- [ ] Тест: \`git commit -m \"bad\"\` из plain shell (не Claude) блокируется

## Риски

- Global hooksPath может мешать другим репо (не-claude-mini проектам, где правила другие)
- Per-project install требует запуска какой-то команды в каждом репо — усложняет onboarding

## Definition of Done

ADR + hook + unit-тесты hook'а + обновлённый universal-setup + verified на живом commit'е." \
    "area:governance" "area:hooks" "adr-needed" "P1-high" "estimate/5" "type:feature"

create_issue \
    "End-to-end validate CI workflow templates on real project" \
    "M2: enforcement hardened" \
    "## Контекст

\`bootstrap/templates/ci-python.yml\`, \`ci-go.yml\`, \`ci-node.yml\` написаны статически, без проверки. Нужно прогнать каждый на соответствующем pet-проекте и пофиксить gaps.

## Acceptance criteria

- [ ] Взять (или создать) pet-проект на Python → прогнать \`ci-python.yml\` через \`mini-bootstrap-project\`
- [ ] Взять (или создать) pet-проект на Go → прогнать \`ci-go.yml\`
- [ ] Взять (или создать) pet-проект на Node → прогнать \`ci-node.yml\`
- [ ] Каждый CI должен: lint pass, typecheck pass, test pass, security-audit pass на минимальном валидном коде
- [ ] Фиксы в templates если что-то не взлетело
- [ ] Документировать использование в \`docs/runbooks/onboarding-repo.md\`

## Deliverable

- [ ] 3 живых pet-репо с зелёным CI (публичных или приватных, не важно)
- [ ] Обновлённые templates если были правки

## Definition of Done

3 зелёных CI run'а на реальных репо; все templates прошли через pipeline (если правились)." \
    "area:ci" "area:bootstrap" "P2-medium" "estimate/5" "type:feature"

create_issue \
    "Populate docs/domain/ with project's own vocabulary" \
    "M2: enforcement hardened" \
    "## Контекст

\`docs/domain/\` сейчас содержит только \`.keep\`. Проект имеет собственную UL: pipeline, advisor, governance hook, two-voice review, hardware/universal layer, read-only critic, skill-vs-agent distinction, decision archaeology, etc.

Без vocabulary-файла каждое новое обсуждение будет заново договариваться о терминах. \`domain-reviewer\` агент не может работать без \`docs/domain/vocabulary.md\`.

## Acceptance criteria

Пройти через \`domain-discovery\` skill на этом репо как на \"bounded context\":

- [ ] Invoke \`@agent-domain-researcher\` на \"claude-mini-pipeline\" как BC
- [ ] Заполнить \`docs/domain/overview.md\`:
  - Actors (operator, Claude, Codex, MCP servers, GitHub)
  - Events (pipeline started, advisor invoked, governance blocked, two-voice disagreed, etc.)
  - Boundary (что в scope — workflow; что out — сам код проектов где применяется)
  - Ubiquitous Language: минимум 10 терминов, кратко определённых
  - Context map edges к внешним \"BCs\" (GitHub, ChatGPT Plus, Anthropic API)
- [ ] \`@agent-domain-reviewer\` approve
- [ ] Merged через canonical pipeline

## Deliverable

- [ ] \`docs/domain/overview.md\` + \`docs/domain/vocabulary.md\`
- [ ] ADR-ссылки обновлены — где invoke \"Ubiquitous Language\" теперь линкуют на живой doc

## Definition of Done

Vocabulary content проходит через domain-reviewer; merged; будущие ADR ссылаются." \
    "area:docs" "type:feature" "P3-low" "estimate/5"

create_issue \
    "Test incident-recovery runbook on real incident or planned drill" \
    "M2: enforcement hardened" \
    "## Контекст

\`docs/runbooks/incident-recovery.md\` существует как guide. Никогда не прогонялся на практике. Incident-recovery документация, не проверенная на incident'е, — это fiction.

## Acceptance criteria

Либо **реальный incident**, либо **planned drill**:

- [ ] **Drill-scenario 1**: governance hook ложно-блокирует валидный commit (как диагностировать, как обойти безопасно, как исправить правило)
- [ ] **Drill-scenario 2**: \`/codex-review\` падает с unknown error (как понять что это Plus-OAuth, как reconfigure, когда открыть deferred-review issue)
- [ ] **Drill-scenario 3**: \`mini-preflight\` показывает broken state после реboot mini (как восстановиться)
- [ ] **Drill-scenario 4**: MCP GitHub связь упала (как отличить от auth issue, как reconnect)
- [ ] Для каждого сценария обновить runbook с реальными commands и error messages

## Deliverable

- [ ] Runbook содержит 4+ реально проверенных сценария (не \"теоретически сделай X\", а \"я сделал X, вот что получилось\")
- [ ] Отметки времени — как долго занимает восстановление из каждого состояния

## Definition of Done

4 drill'а пройдены; runbook обновлён; merged." \
    "area:docs" "type:runbook" "P3-low" "estimate/5"

say "Готово"
echo
echo "Issues: https://github.com/${FULL}/issues"
echo "Milestones: https://github.com/${FULL}/milestones"
echo
echo "Следующий шаг: открой project board (Projects v2) вручную через UI"
echo "(GitHub Projects v2 создаются через web UI или GraphQL API, не через gh CLI).
См. docs/runbooks/onboarding-repo.md § 'GitHub Projects v2 board setup'."
