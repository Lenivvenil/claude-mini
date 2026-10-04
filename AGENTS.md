# AGENTS.md — MACH

> Инструкции для любого агента. Claude Code читает этот файл сам, CLAUDE.md не нужен.

## Где живёт знание

| Что | Где |
|---|---|
| Задачи | GitHub Issues |
| Архитектурные решения | `docs/decisions/` (MADR 4.0) |
| Принципы | `docs/principles.md` |
| Ловушки LLM | `docs/anti-patterns.md` |
| План переноса v1 → v2 и опись файлов | `docs/port/PLAN.md`, `tools/port-run/ledger.tsv` |
| Как развернуть харнесс | `DEPLOY.md` |
| Файлы v1, ушедшие из работы | `docs/history/` (копии, по описи) |

Голова оператора, память LLM и история чата источниками истины не являются. Что не записано в репозитории, то потеряется.

## Структура

```
plugin/                  — харнесс: плагин Claude Code
├── agents/              — девять ролей по вызову
├── skills/              — feature, plan, adr-author, codex-review, handoff,
│                          domain-discovery, backlog-review, project-health
├── hooks/hooks.json     — хук формата коммитов
├── scripts/             — сам хук и его тесты
├── bin/                 — config (валидатор и чтение конфига), jev-check
└── config/              — schema.json и defaults.json
.claude-plugin/marketplace.json — каталог для `claude plugin marketplace add`
setup/harness            — assess / apply / verify / uninstall, два слоя
tests/                   — config, setup, jev, приёмка голым Claude, границы плагина
tools/port-run/          — опись переноса и её проверка
bootstrap/hardware/, bootstrap/scripts/mini-*  — машина владельца, Mac mini
```

## Проверки

```bash
claude plugin validate plugin --strict
bash scripts/lint-prompts.sh plugin/agents/*.md plugin/skills/*/SKILL.md
bash tools/port-run/ledger-check.sh
bash tests/lint/no-hardcode.sh
bash tests/config/run.sh
bash tests/setup/run.sh
bash tests/jev/run.sh
bash plugin/scripts/test-commit-msg-check.sh
bash tests/acceptance/deploy-bare.sh   # нужен ключ подписки, без него выходит 77
bash tests/plugin-scope/no-plugin-no-writes.sh   # тоже нужен ключ подписки
```

## Как идёт задача

`/mach:feature <N>` ведёт задачу от issue до PR. Ветка, `plan.md`, ADR при архитектурной значимости, реализация, проверки проекта, сверка с критериями приёмки, критики по тому, что затронуто, Codex, коммит и PR, передача работы. Вливает владелец.

## Жёсткие правила

1. Архитектурно значимое решение оформляется ADR отдельным PR до реализации. Договорённость в чате решением не считается.
2. PR ссылается на задачу: `Closes #NNN`. Проверка тела PR в CI это требует. Если был ADR, то ещё `Implements docs/decisions/NNNN-*.md`.
3. Коммиты и заголовки PR в формате Conventional Commits: `type(scope): message`. Хук плагина проверяет тему коммита. Заголовок PR при squash становится темой коммита в main.
4. ADR после принятия не правятся, кроме статуса.
5. `plugin/` и `.claude-plugin/marketplace.json` не переносить: проекты включают плагин из этого дерева на уровне local.
6. Правило, проверка или строка промпта попадают в харнесс, только если называют отказ, который предотвращают (`docs/port/PLAN.md` §2).

## MCP-серверы

`.mcp.json` в корне подключает три сервера. Транспортная политика описана в ADR-0028.

| Сервер | Транспорт | Версия | Зачем |
|---|---|---|---|
| Serena | stdio | `v1.2.0` | Навигация по символам кода |
| Context7 | stdio | `2.2.4` | Актуальная документация библиотек |
| GitHub | HTTP | — | Issues, PR, actions |
