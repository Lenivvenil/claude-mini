# Project conventions — claude-mini

Этот файл — карта, а не территория. Перечитывай при старте сессии; не кешируй в memory.

## Source of truth

- **Backlog, milestones, sprints:** GitHub Issues + Projects v2 (этот репо).
- **Architecture decisions:** `docs/decisions/` (MADR 4.0). Новые — через `/adr`.
- **Domain model:** `docs/domain/`. Эволюционирует через `domain-researcher`.
- **System structure:** `docs/architecture/`.
- **Principles:** `docs/principles.md`.
- **Anti-patterns:** `docs/anti-patterns.md` (реестр ленивых решений LLM, Принцип 4).
- **Runbooks:** `docs/runbooks/`.

## Hard rules

1. **ADR-PR** обязателен для любого архитектурно-значимого решения. «Мы договорились в чате» — не решение.
2. **Issue-first** для любой задачи длиннее одной сессии. Промоут через `/task-to-issue`.
3. **Cross-ref в PR** обязателен: `Closes #NNN` и `Implements docs/decisions/NNNN-*.md` если был ADR.
4. **Conventional Commits.** `pre-commit-governance.sh` hook проверяет префикс и issue-ref.
5. **Definition of Done** — см. `docs/principles.md#definition-of-done`. Merge блокируется до выполнения.
6. **Advisor policy:** `advisor()` вызывается дважды на нетривиальную задачу — перед началом работы (проверка плана) и перед объявлением готовности (поиск багов/несоответствий ADR).

## Orchestration

**Главный цикл:** `claude --model sonnet` с `/advisor` (Opus 4.7 как консультант).

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

- **Serena** — семантическая навигация. Используй вместо grep на больших файлах.
- **GitHub** — issues/PR/projects/actions. Read-only header `X-MCP-Read-Only: true` для exploratory-сессий.
- **Context7** — актуальная документация библиотек. Проверяй здесь перед гипотезой «API такой».

## Что в этом репо уникально

Этот проект документирует и устанавливает сам себя. Каждое изменение (новый агент, новая команда, новый runbook) проходит через собственный pipeline: issue → plan → (ADR если надо) → implement → review → governance-commit → PR. Это не стайлинг — это дисциплина. Если pipeline не умеет произвести новый артефакт, pipeline сломан.

## Что не делать

- **Не редактировать `bootstrap/` напрямую в production `~/.claude/`.** Источник правды — этот репо. Глобальные артефакты (agents, skills, hooks): `./bootstrap/universal-setup.sh --install`. Slash-команды — per-project: `./bootstrap/universal-setup.sh --target <repo>`. Порядок миграции важен: сначала `--target <repo>`, затем `rm ~/.claude/commands/*.md` (не наоборот — иначе останешься без команд). (ADR-0018)
- **Не коммитить напрямую через терминал минуя `/review` и governance.** Для защиты от себя можно включить git-level commit-msg hook (см. `docs/runbooks/enforcement-extras.md` — TODO).
- **Не вызывать advisor на тривиальное.** Форматирование, переименование, мусорный refactor — без advisor. Он для содержательных решений.
