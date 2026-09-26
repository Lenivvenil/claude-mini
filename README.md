# claude-mini

> Харнесс для Claude Code: роли по вызову, скиллы цикла задачи, хук формата коммитов.
> Включается только в том проекте, где его развернули. Разворачивается и убирается одной командой.

## Развёртывание

Инструкция для человека и для агента — [DEPLOY.md](DEPLOY.md), решение — [ADR-0031](docs/decisions/0031-project-scoped-plugin-two-layer-deploy.md). Можно попросить Claude в проекте: «deploy my harness for this project», указав путь к клону.

```bash
git clone https://github.com/Lenivvenil/claude-mini.git ~/claude-mini   # один раз
cd <твой-проект>
~/claude-mini/setup/harness assess --project .     # что есть, чего нет; ничего не пишет
~/claude-mini/setup/harness apply --project .      # только недостающее
~/claude-mini/setup/harness verify --project .     # всё ли готово
~/claude-mini/setup/harness uninstall --project .  # вернуть как было
```

Два слоя. Слой машины проверяет программы и входы (git, python3, jq, claude, gh, по желанию codex и node). Системную программу он ставит только с явного согласия `--allow-system <id>`. Слой проекта включает плагин в `--scope local` этого проекта и добавляет локальные файлы в `.git/info/exclude`. В других проектах и сессиях плагина нет.

## Что внутри

| Компонент | Что делает |
|---|---|
| `/claude-mini:feature <issue>` | ведёт задачу от issue до PR, в конце передаёт работу; вливает владелец |
| `/claude-mini:plan <issue>` | пишет `plan.md`: варианты, выбор, тесты, риски; по желанию советник Jev |
| `/claude-mini:adr-author` | ADR по MADR 4.0 через интервью |
| `/claude-mini:codex-review [base]` | второе мнение Codex по ветке и незакоммиченному |
| `/claude-mini:handoff` | журнал, затем снимок `STATE.md`, чтобы продолжить за пять минут |
| `/claude-mini:domain-discovery` | интервью по Event Storming, черновик пишет `domain-researcher` |
| `/claude-mini:backlog-review` | разбор бэклога, выполняются только одобренные команды |
| `/claude-mini:project-health` | время ревью, возраст задач, ADR в ожидании, расходы из CodeBurn |
| роли | `adversarial-critic`, `security-reviewer`, `reliability-reviewer`, `docs-reviewer`, `domain-reviewer`, `adr-reviewer`, `backlog-groomer`, `domain-researcher`, `solutions-architect` |
| хук `PreToolUse` | на `git commit` из Claude проверяет формат Conventional Commits |

Роли вызываются по описанию, когда задача к ним подходит. Промпт роли грузится только при вызове. Модели не закреплены: роли наследуют модель сессии, Codex берёт свою из `~/.codex/config.toml`.

## Настройка

Значения по умолчанию — `plugin/config/defaults.json`, допустимые ключи — `plugin/config/schema.json`. Проект переопределяет только нужное в `.claude/claude-mini.json`, например `{"schema_version": 1, "commit": {"types": ["feat", "fix", "docs"]}}`. Неизвестный ключ считается ошибкой.

```bash
plugin/bin/config validate .claude/claude-mini.json
plugin/bin/config effective
```

Внешние сервисы необязательны. Без Codex, Jev, CodeBurn или сети харнесс работает в урезанном режиме и прямо говорит, чего нет. Jev и CodeBurn по умолчанию выключены.

## Принципы

Контракт проекта — [docs/principles.md](docs/principles.md):

1. **Размытость — нарушение.** Правильный вариант с обоснованием или честное «не знаю» и эксперимент.
2. **Claude — критик, решает оператор.** Trade-off закрывает только человек.
3. **Сначала детерминированный тулинг, потом агент.**
4. **Знание живёт в репозитории или нигде.**
5. **Scope — граница проекта.** Харнесс действует только там, где плагин включён на уровне проекта.
6. **Команды живут в проекте.** Это скиллы плагина с пространством имён, глобального namespace нет.
7. **Открытый формат — источник истины, vendor — расходник.**
8. **Антихрупкость по домену, запас 2–3×.**
9. **Перехват — контракт.** При отказе LLM оператор продолжает с точки остановки.

Правило отбора: правило, проверка или строка промпта попадают в харнесс, только если называют отказ, который предотвращают ([docs/port/PLAN.md §2](docs/port/PLAN.md)).

## Разработка

Структура, проверки и правила для агентов — в [AGENTS.md](AGENTS.md). Claude Code читает его сам, CLAUDE.md не нужен. Перенос v1 в плагин описан в [docs/port/PLAN.md](docs/port/PLAN.md). Ушедшие из работы файлы v1 лежат в `docs/history/`, их опись — `tools/port-run/ledger.tsv`.

## MCP-серверы

`.mcp.json` подключает `serena` (stdio, `v1.2.0`), `context7` (stdio, `2.2.4`) и `github` (HTTP). Транспортная политика — [ADR-0028](docs/decisions/0028-mcp-transport-security.md): stdio по умолчанию, HTTP только для явно разрешённых адресов, stdio-серверы закреплены по версии.

## Лицензия

MIT. См. `LICENSE`.
