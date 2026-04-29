# claude-mini

> Воспроизводимый enterprise workflow для Claude Code на headless-станции. Сетап сам себя документирует и сам себя устанавливает.

[![governance](https://img.shields.io/badge/governance-hook--enforced-green)](docs/architecture/overview.md#governance)
[![pipeline](https://img.shields.io/badge/pipeline-sonnet%20+%20advisor-blue)](docs/decisions/0003-sonnet-main-opus-advisor.md)

## Что это

Персональная AI-assisted разработческая станция, построенная на четырёх принципах:

1. **Красные флаги вместо трейдоффов** — либо правильный ответ, либо честное «не знаю».
2. **Claude — душный напарник, не эксперт** — агенты критикуют, не решают.
3. **Автоматизировать только низкорискованное** — остальное — через approval.
4. **Knowledge в инструментах, не в памяти** — ADR, issues, docs — source of truth.

Проект решает две задачи одновременно:

- **Material reference** — готовый набор агентов, skills, commands, hooks, scripts и runbooks, устанавливаемый одной командой.
- **Живая документация** — каждое решение зафиксировано как ADR, каждая процедура как runbook, каждый процесс прошёл через собственный pipeline.

## Быстрый старт

**Prerequisite (hardware layer — один раз на машине):**
См. `bootstrap/hardware/` для вашей платформы. Сейчас задокументирована `mac-mini-2018.md`.

**Universal layer (на любой машине с установленным Claude Code):**

```bash
git clone https://github.com/<owner>/claude-mini.git
cd claude-mini
./bootstrap/universal-setup.sh --check     # dry-run
./bootstrap/universal-setup.sh --install   # идемпотентно
```

Скрипт:
- копирует агентов, skills, commands, hooks, scripts в `~/.claude/`
- патчит `~/.claude/settings.json` (добавляет PreToolUse wiring через абсолютные пути)
- проверяет `gh auth`, `codex login`, `ANTHROPIC_*` env vars
- создаёт symlinks `~/bin/mini-*` на session-скрипты
- не трогает уже существующие файлы без `--force`

## Структура

```
docs/
├── architecture/       — как устроено целиком (слои, потоки)
├── decisions/          — ADR (MADR 4.0), решения с обоснованием
├── domain/             — термины и границы контекстов
├── principles.md       — контракт, на котором всё держится
├── runbooks/           — пошаговые сценарии
└── metrics/            — артефакты /project-health

bootstrap/
├── hardware/           — platform-specific (Mac mini, будущий Linux)
├── agents/             — read-only критики для ~/.claude/agents/
├── skills/             — авторские тулы для ~/.claude/skills/
├── commands/           — slash-commands для ~/.claude/commands/
├── hooks/              — PreToolUse hooks для ~/.claude/hooks/
├── scripts/            — утилиты для ~/.claude/scripts/ и ~/bin/
├── templates/          — шаблоны (CLAUDE.md, PR template, CI workflows)
└── universal-setup.sh  — идемпотентный installer
```

## Что внутри

**Агенты (8):** `adr-reviewer`, `domain-reviewer`, `domain-researcher`, `solutions-architect`, `backlog-groomer`, `security-reviewer`, `docs-reviewer`, `reliability-reviewer`.

**Skills (3):** `adr-author` (MADR 4.0), `domain-discovery` (Event Storming), `project-bootstrap` (новый репо со всей обвязкой).

**Slash commands (10):** `/plan`, `/implement`, `/adr`, `/review`, `/codex-review`, `/task-to-issue`, `/issue-to-task`, `/backlog-review`, `/project-health`, `/feature` (master orchestrator).

**Hooks (1):** `pre-commit-governance.sh` — блокирует коммиты без CC-префикса / issue-ref / ADR-ref.

**Scripts (5):** `mini-preflight`, `mini-session`, `mini-bootstrap-project`, `mini-health`, `review-codex.sh`.

## Контракт воспроизводимости

- Любой шаг можно пройти повторно без разрушения состояния (`--install` после `--install` ничего не сломает).
- Hardware-специфичное живёт в `bootstrap/hardware/<platform>.md` и **не вызывается** из `universal-setup.sh`.
- Переход с Mac на Linux = пройти соответствующий hardware-runbook, затем запустить тот же `universal-setup.sh`.

## Как работает пайплайн

Каждая фича проходит через три управляемых цикла. Все три создаются в момент старта `/feature <issue>` и не существуют без него:

```
/feature <issue>
│
├─ FeatureRun (оркестратор) ─────────────────────────────────────────┐
│   issue → plan → (ADR?) → implement → qa                           │
│                                        │                            │
│   ┌── GovernanceRun ─────────────┐     │                            │
│   │  AttemptCommit               │     │                            │
│   │  ├─ BLOCKED → retry          │     │                            │
│   │  └─ APPROVED ✓ (terminal)    │     │                            │
│   └──────────────────────────────┘     │                            │
│                                        │                            │
│   ┌── TwoVoiceReview ────────────┐     │                            │
│   │  /review (Claude)            │     │                            │
│   │  /codex-review (Codex)       │     │                            │
│   │  ├─ agreed ✓                 │     │                            │
│   │  ├─ reconciled ✓             │     │                            │
│   │  └─ deferred ✓ (+issue)      │     │                            │
│   └──────────────────────────────┘     │                            │
│                                        │                            │
│   DoD = done iff:                      │                            │
│     GovernanceRun.state = approved  ───┘                            │
│     TwoVoiceReview.state ∈ {agreed|reconciled|deferred}             │
└─────────────────────────────────────────────────────────────────────┘
        │
        └─▶ gh pr create  (pre-PR artifact gate — issue #115)
```

**Что обязательно на каждом этапе** — см. `docs/runbooks/feature-pipeline.md#10-pre-pr-artifact-verification`. Пропуск этапа без явного основания блокирует pipeline.

**Механический gate коммитов:** `pre-commit-governance.sh` блокирует коммит без Conventional Commits prefix + issue-ref.

**Механический gate PR:** планируется в issue #115.

## Как с этим работать

- Ежедневный флоу: `docs/runbooks/daily-session.md`
- Новая фича: `docs/runbooks/feature-pipeline.md`
- Новое архитектурное решение: `docs/runbooks/adr-workflow.md`
- Onboarding существующего репо: `docs/runbooks/onboarding-repo.md`
- Пятничная maintenance: `docs/runbooks/weekly-maintenance.md`
- Что-то сломалось: `docs/runbooks/incident-recovery.md`

## Статус

Первичный bootstrap проекта выполнен через собственный pipeline — каждая директория и каждый ADR созданы как самостоятельная задача (см. issues и закрытые PR с labels `type:adr`, `type:bootstrap`). Это не стайлинг, а доказательство работоспособности: если проект нельзя построить через pipeline, pipeline сломан.

## Лицензия

MIT. См. `LICENSE`.
