# HANDOFF: Synthesis 2026-04-29 — раскладка по проекту

**Кому:** Claude Code, работающему в репозитории `claude-mini`.
**От кого:** Оператор (Venil), после интервью с research-Claude от 2026-04-29.
**Что приложено:** `SYNTHESIS-2026-04-29.md` (deep synthesis + backlog), `PRINCIPLES-DRAFT.md` (финальная редакция девяти принципов).

---

## Контракт этой задачи

Ты НЕ имплементируешь backlog. Ты НЕ пишешь код. Ты НЕ создаёшь skills/agents/hooks.

Ты делаешь ОДНО: аккуратно раскладываешь вводные по правильным местам в репозитории, чтобы дальнейшая работа шла через стандартный pipeline (`/feature`, `/plan`, `/adr`, `/task-to-issue`).

Любая попытка выйти за этот scope — нарушение Принципа 5 (scope = границы установки) и Принципа 2 (Claude — критик, не автор решений).

---

## Что должно произойти (порядок)

### Шаг 1 — Принципы

Открой `PRINCIPLES-DRAFT.md`. Это финальная редакция девяти принципов после интервью.

Сравни с текущим `docs/principles.md`:
- Принципы 1-4 — **обновлены жёстче** (см. изменения в DRAFT, особенно расширение принципа 4 с anti-patterns).
- Принципы 5-6 — без изменений.
- Принципы 7, 8, 9 — **новые**.

Действие: создай PR-ready патч `docs/principles.md`. НЕ коммить, НЕ пушить. Положи диф в `.claude/scratch/handoff-2026-04-29/principles.diff`. Оператор сам решит, мерджить ли.

Открой issue типа `type:adr` с заголовком `docs(principles): adopt nine-principle hardened revision (2026-04-29 interview)`, в body — ссылка на этот HANDOFF и diff. Это ADR-кандидат — оператор пройдёт через `/adr` отдельно.

### Шаг 2 — Synthesis в репо

Положи `SYNTHESIS-2026-04-29.md` в `docs/synthesis/2026-04-29-pipeline-restructuring.md` без изменений. Это living document, на который будут ссылаться будущие ADR и тикеты. Закоммить отдельным коммитом `docs(synthesis): add 2026-04-29 pipeline restructuring synthesis` после того как оператор подтвердит.

### Шаг 3 — Backlog

Synthesis содержит 40 тикетов (P0–P3). Тикеты НЕ создавай скопом. Сделай следующее:

3.1. Прочитай раздел B Synthesis целиком, не выборочно.

3.2. Для каждого тикета проверь:
- Существует ли уже похожий открытый issue в проекте (`gh issue list --state open`). Если да — отметь в отчёте как `duplicate-of #N`, тикет НЕ создавай.
- Зависит ли тикет от другого тикета из этой же партии (явно или неявно). Например, #6 (adversarial-critic) грузит `docs/anti-patterns.md` из #7 — значит #7 блокирует #6.

3.3. Подготовь файл `.claude/scratch/handoff-2026-04-29/backlog-plan.md` со следующей структурой для каждого тикета:

```
## Ticket NN — <title from synthesis>
- gh-create-command: gh issue create --title "..." --label "..." --body-file ...
- depends-on: [список номеров других тикетов из этой партии]
- duplicate-of: #N (если есть)
- body-file: .claude/scratch/handoff-2026-04-29/bodies/NN.md
```

3.4. Для каждого тикета создай файл body в `.claude/scratch/handoff-2026-04-29/bodies/NN.md` со структурой:
- Problem statement (из synthesis)
- Acceptance criteria (из synthesis, **разверни в чеклист** `- [ ] ...`)
- Non-goals (из synthesis)
- References (из synthesis + ссылка на `docs/synthesis/2026-04-29-pipeline-restructuring.md` и на принцип)
- Estimate (S/M/L)
- Depends-on (если есть)

3.5. НЕ запускай `gh issue create`. Положи всё в scratch. Оператор пройдёт через `/backlog-review` и решит, что создавать и в каком порядке.

### Шаг 4 — Отчёт

В `.claude/scratch/handoff-2026-04-29/REPORT.md` напиши:
- Какие issues уже существуют (duplicates).
- Какие тикеты имеют межзависимости (граф).
- Какие принципы каких тикетов касаются (matrix).
- Чего в backlog не хватает по твоему чтению (но НЕ добавляй сам — flagни).
- Конфликты с существующими ADR (например, #13 split domain layer может конфликтовать с ADR-XXXX, который описывает текущую структуру domain). Список конфликтов — оператор решит.

---

## Что нельзя делать

- НЕ создавать issues через `gh issue create`. Только подготовка файлов.
- НЕ модифицировать существующий код, hooks, skills, agents.
- НЕ запускать тесты, mutation, property-based — это работа по самим тикетам.
- НЕ делать ADR через `/adr`. ADR-кандидаты — issues типа `type:adr`, оператор пройдёт через них сам.
- НЕ переписывать synthesis. Положить как есть.
- НЕ объединять близкие тикеты. Synthesis намеренно разделил их — у каждого своя acceptance criteria.
- НЕ начинать с P0. Все тикеты — это backlog, оператор сам решит порядок старта.

---

## Что должно остаться после твоей работы

Структура:
```
.claude/scratch/handoff-2026-04-29/
├── principles.diff
├── backlog-plan.md
├── bodies/
│   ├── 01.md
│   ├── 02.md
│   ├── ...
│   └── 40.md
└── REPORT.md

docs/synthesis/
└── 2026-04-29-pipeline-restructuring.md  (закоммичен)

GitHub Issues:
└── один issue type:adr — adopt nine-principle revision
```

Никаких других изменений.

---

## Контроль качества handoff

Перед тем как отчитаться оператору о завершении, прогони сам себя по чеклисту:

- [ ] Прочитал HANDOFF-BRIEF.md полностью, включая «что нельзя делать».
- [ ] Прочитал PRINCIPLES-DRAFT.md и сверил с docs/principles.md.
- [ ] Прочитал раздел A Synthesis (свод), не только раздел B (тикеты).
- [ ] Каждый из 40 тикетов имеет body-файл, gh-команду, depends-on граф.
- [ ] Дубликаты с открытыми issues перечислены.
- [ ] Конфликты с существующими ADR флажены в REPORT.md.
- [ ] Никаких `gh issue create` запусков; никаких code changes; никаких hook installations.
- [ ] Принципы НЕ закоммичены — только diff в scratch.

Если хоть один пункт не выполнен — не отчитывайся «готово». Доделай или явно скажи оператору, на каком пункте споткнулся и почему.

---

## Если что-то непонятно

Не угадывай. Не додумывай. Не делай «как, наверное, имелось в виду».

Создай в `.claude/scratch/handoff-2026-04-29/QUESTIONS.md` список вопросов и остановись. Оператор ответит и ты продолжишь.

Это Принцип 1 (размытость — нарушение) и Принцип 2 (Claude — критик, не автор) применённые к самому handoff.
