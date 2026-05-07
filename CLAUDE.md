@AGENTS.md

<!-- Claude Code разворачивает @AGENTS.md автоматически.                    -->
<!-- Другие инструменты и GitHub читают AGENTS.md напрямую.                 -->

> **Vendor-neutral инструкции:** [AGENTS.md](AGENTS.md) — структура репо, workflow, правила, hook, MCP.

# Claude Code — дополнительная конфигурация

Этот файл добавляет Claude Code-специфику поверх `AGENTS.md`.
Перечитывай при старте сессии; не кешируй в memory.

## Orchestration

**Главный цикл:** `claude --model sonnet` с `advisor()` (Opus 4.7 как консультант).

**Feature pipeline (канонический путь):**

```
/task-to-issue (опц.) → /plan <issue> → /adr (если нужно) → /implement
  → /qa → /review → /codex-review → git commit (governance) → gh pr create
```

**Conditional agent gates** (вызываются в рамках соответствующей стадии):

| Стадия | Агент | Условие |
|---|---|---|
| step 1b (после чтения issue, до /plan) | `domain-researcher` | `docs/domain/` пуст или scope выходит за его границы |
| после `/adr` | `adr-reviewer` | всегда после черновика |
| после `/implement` | `domain-reviewer` | если `docs/domain/` изменялся |
| внутри `/review` | `security-reviewer`, `reliability-reviewer` | prod-bound: `bootstrap/`, `.github/workflows/`, `.git/hooks/`, или label `prod-bound` |
| внутри `/review` | `docs-reviewer` | PR затрагивает `docs/runbooks/`, `docs/architecture/`, `docs/principles.md`, `README.md` — и НЕ только `docs/decisions/` или `docs/domain/` |
| внутри `/review` (всегда, после Layer 1) | `adversarial-critic` | каждый PR; передать diff как context; BLOCK-findings блокируют merge |
| еженедельно | `backlog-groomer` | **out-of-band**, не входит в pipeline |
| еженедельно | `/adr-retirement-audit` | **out-of-band**, CI cron Monday 06:00 UTC — staleness check по всем ADR |

**Оркестратор одной кнопкой:** `/feature <issue-number>` — ведёт по всем стадиям через TodoWrite.

**Fan-out запрещён для feature-работы.** Разрешён только для embarrassingly-parallel: переименование символа в 200 файлах, миграция 50 импортов, шаблонизация тестов из схемы.

## Agents

Read-only критики. Вызов: `@agent-<name>`.

| Агент | Когда звать |
|---|---|
| `adr-reviewer` | После черновика ADR — проверит полноту секций MADR 4.0 и конфликты с инвариантами агрегатов BC (`FeatureRun`, `GovernanceRun`, `TwoVoiceReview`) |
| `domain-reviewer` | После правки `docs/domain/` — ловит vocabulary drift, нарушения BC, нарушения инвариантов всех трёх агрегатов (`FeatureRun`, `GovernanceRun`, `TwoVoiceReview`) в текущем диффе |
| `domain-researcher` | Когда `docs/domain/` пуст или устарел — перед `/plan` (триггер: missing-or-stale, не только greenfield) |
| `solutions-architect` | Значимый технический выбор — library, integration contract, данные |
| `backlog-groomer` | **Out-of-band by design.** Раз в неделю — предлагает triage, сам не мутирует. Не входит в feature pipeline. |
| `security-reviewer` | Перед prod-значимым PR — затрагивает `bootstrap/`, `.github/workflows/`, `.git/hooks/`, или label `prod-bound` |
| `reliability-reviewer` | Перед prod-значимым PR (те же условия, что `security-reviewer`) — проверяет idempotency, recoverability, fault tolerance, observability, auditability, resilience |
| `docs-reviewer` | Внутри `/review`, если PR меняет human-facing docs (`docs/runbooks/`, `docs/architecture/`, `docs/principles.md`, `README.md`) — проверяет читаемость для новичка, исполняемость примеров, отсутствие orphaned sections |
| `adversarial-critic` | Внутри `/review` всегда (после Layer 1) — ловит ленивые паттерны LLM: дублирование, symptom-fix, narrow-case, copy-paste, truncated-file, magic constants, TODO-без-тикета, commented-out code; загружает `docs/anti-patterns.md` в context |

## MCP tooling

Назначение серверов — в `AGENTS.md §MCP-серверы`. Claude Code-специфика:

- **GitHub** — для exploratory-сессий добавляй `X-MCP-Read-Only: true` header.
- **Context7** — проверяй здесь перед любой гипотезой об API библиотеки; training data устаревает.

## Advisor policy

Полный критерий «нетривиальная задача» — `docs/runbooks/advisor-policy.md`.

`advisor()` вызывается **дважды** на нетривиальной задаче:
1. **Перед реализацией** — проверить план, найти дыры до написания кода.
2. **Перед объявлением готовности** — проверить diff на баги и несоответствия ADR.

Нетривиальная задача: затрагивает >1 модуля, неочевидные edge cases, конкурирует с похожим кодом, содержит асинхронность. Тривиальное (форматирование, rename, однострочный fix) — без advisor.

## Что не делать

- **Не редактировать `bootstrap/` напрямую в production `~/.claude/`.** Источник правды — этот репо. Глобальные артефакты: `./bootstrap/universal-setup.sh --install`. Slash-команды — per-project: `./bootstrap/universal-setup.sh --target <repo>`. Порядок важен: сначала `--target <repo>`, затем `rm ~/.claude/commands/*.md`. (ADR-0018)
- **Не коммитить напрямую через терминал минуя `/review` и governance.**
- **Не вызывать advisor на тривиальное.** Форматирование, переименование, мусорный refactor — без advisor.
