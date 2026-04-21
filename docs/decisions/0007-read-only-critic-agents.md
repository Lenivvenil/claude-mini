# 0007. All specialist agents are read-only critics, never authors

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: agents, orchestration, responsibility

## Context and Problem Statement

Субагенты в Claude Code могут иметь полный `tools: "*"` доступ и писать в репо. Это соблазн: "пусть `adr-author` сам пишет ADR целиком". Но комбинация autoMode + powerful subagents создаёт ситуацию, где ответственность размыта: кто автор ADR — человек, назвавший subagent, или subagent, записавший файл?

## Decision Drivers

* Вторая директива: "Claude — душный напарник, не эксперт. Единственный автор — человек."
* Lossy brief при Task-tool subagent invocation — критик на read-only этим не страдает, автор-subagent страдает.
* Ретроспективный аудит: если subagent написал что-то плохое, неясно кто обнаружил и когда.
* PR review process: человек ожидает увидеть свой diff, не diff третьего лица.

## Considered Options

* **Option A: Все агенты read-only — читают, критикуют, возвращают текстовую оценку.** Действия делает человек через `gh` / `edit`.
* **Option B: Часть агентов — authors, часть — critics.** `adr-author` пишет сам, `adr-reviewer` критикует.
* **Option C: Все агенты могут писать, но только в draft-ветки, merge всегда человеком.** Safety net через ветки.

## Decision Outcome

Chosen option: **Option A для agents, но skills — authors**. Это различие критично: **agents — субагенты в Claude Code sense** (invoked via `Task` или `@agent-name`); **skills — структурированные prompts/tools которые использует main loop**. Skill `adr-author` пишет ADR, но под main-loop authority; он не отдельный subagent с своим контекстом. Agent `adr-reviewer` — отдельный read-only subagent, который просматривает diff.

Опция B имеет конфуз: "author" как агент делает работу, которую Venil должен делать сам. Опция C добавляет ветки-draft, которые создают review overhead без решения проблемы (кто автор? всё равно subagent).

### Positive Consequences

* Ответственность за каждый файл в репо — у человека или у main-loop (который под контролем человека).
* Agents как mental load-balancers: берут на себя проверку полноты, не отвлекая main loop.
* Легко аудировать: PR-git blame показывает именно вашу авторскую линию, не линию subagent'а.
* Мягкое принуждение к engagement: вы должны прочитать findings и применить, а не принять "готово".

### Negative Consequences

* Теряется возможный speedup от parallel authoring subagents.
* Findings критиков могут игнорироваться при спешке — human дисциплина.
* Skill vs agent различие неочевидно новичку — требуется документация.

## Уточнение: две подкатегории агентов

После реализации стало ясно, что агенты делятся на два класса:

**Pure critics** (только чтение, возвращают markdown-отчёт):
- `adr-reviewer`
- `domain-reviewer`
- `backlog-groomer`
- `security-reviewer`

Эти имеют tools только из read-only набора (Read, Glob, Grep, read-only MCP calls, `git diff`-like Bash). Никогда не пишут в файловую систему и не мутируют GitHub.

**Author-gateways** (имеют ограниченный Write для вызова skills):
- `domain-researcher` — invoke'ит `domain-discovery` skill, который пишет в `docs/domain/<bc>/overview.md`
- `solutions-architect` — invoke'ит `adr-author` skill, который пишет в `docs/decisions/NNNN-*.md`

Эти агенты не "пишут код" в смысле implementation — они hub'ы для structured author-skills, продукт которых — docs-артефакты (не исходники). Скилл сам контролирует что именно пишется, через rigid-interview protocol (≥3 options, Bad≥Good и т.д.). Агент — просто контекстный wrapper.

Что это НЕ:
- Не авторы production code — ни один агент не может редактировать `.py`, `.go`, `.ts`, `.js` и т.п.
- Не мутаторы GitHub — ни у одного нет `mcp__github__create_*`, `mcp__github__update_*`, `mcp__github__close_*`.

## Confirmation

Автоматическая проверка в CI:

- Pure critics (4 файла) — не имеют `Edit`, `Write`, `mcp__github__create*`, `mcp__github__update*` в frontmatter.
- Author-gateways (2 файла) — имеют `Write`, но не имеют `Edit` или мутирующих MCP-tools (они пишут новые файлы через skills, не редактируют существующие).
- Ни один агент не имеет `Bash` без whitelist-паттерна.

## Re-visit Trigger

* Claude Code получает нативную поддержку ролей "assistant contributor" (subagent пишет, но помечает файл special author metadata).
* Количество subagent invocations в день > 20 — тогда ручная интеграция findings становится bottleneck'ом, нужна частичная автоматизация.

## Links

* `bootstrap/agents/` — все шесть агентов с read-only frontmatter
* `../principles.md#2`
