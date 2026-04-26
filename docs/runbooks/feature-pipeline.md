# Runbook: feature pipeline

Канонический путь для содержательной фичи.

## Когда

- Новая функциональность
- Bug fix, требующий мышления
- Рефакторинг в одном модуле
- Добавление зависимости

## Не подходит для

- Тривиальная правка (typo, форматирование) — просто `edit` + commit
- Embarrassingly-parallel работа (rename в 200 файлах) — fan-out допустим

## Шаги

### 0. Domain check (после чтения issue, до /plan)

После того как прочитал issue — убедись что `docs/domain/` актуален:
```bash
ls docs/domain/  # должен содержать overview.md + vocabulary.md
```

Если пуст или данные явно устарели — сначала:
```
@agent-domain-researcher
```

Подробнее: `docs/decisions/0014-feature-checklist-after-agent-wiring.md`.

### 1. Issue first

Если задачи ещё нет в GitHub:
```
/task-to-issue "Добавить retry logic для HTTP-клиента"
```

Убедись что issue содержит:
- Problem statement
- Acceptance criteria (testable!)
- References (на файлы, другие issues)

### 2. Planning

```
/plan <issue-number>
```

Создаётся `plan.md` в корне репо. Содержит 6 секций (см. команду). Прочитай плана — если что-то не так, скажи Claude "rewrite section N".

### 3. Advisor critique (MANDATORY для нетривиальной)

```
advisor("Review this plan against codebase. Missing edge cases? ADR violations?")
```

Или Claude позовёт сам, если `/implement` с advisor policy. Но правильнее **до** `/implement` — тогда findings ложатся на план, а не на код.

### 4. Нужен ли ADR?

Проверь по `docs/principles.md#что-значит-архитектурно-значимо`:

- Выбор библиотеки → YES, ADR
- Изменение BC границы → YES
- Публичный API → YES
- Просто реализация внутри модуля → NO, pass

Если YES:
```
@agent-solutions-architect
```
или
```
/adr <slug>
```

Дождись merge ADR PR до `/implement`.

If an ADR was authored: after the ADR PR merges, re-read `plan.md §4` — does the Chosen approach match the ADR's Decision Outcome? Update `plan.md` if not, before running `/implement`. The ADR interview can change the mechanism relative to what `plan.md` described before the interview. (Evidence: `docs/runbooks/first-feature-session-log.md` Gap 1.)

### 5. Implementation

Before running `/implement`, create the feature branch if you haven't already:

```bash
git checkout -b feat/<short-slug>-<issue-number>
# Example: git checkout -b feat/retry-logic-42
```

The governance hook (ADR-0009) blocks direct commits to `main`; creating the branch here avoids a stash/rebase recovery later.

```
/implement
```

Claude:
- Читает plan.md и упомянутые файлы
- Вызывает advisor × 1 перед началом
- Пишет код, гоняет тесты
- Вызывает advisor × 2 перед declared done

Если plan дрейфует в процессе — Claude должен STOP и обновить plan.md. Если ты видишь дрейф без обновления — красный флаг, скажи.

### 5b. Domain review (если docs/domain/ изменялся)

Только если `/implement` трогал файлы в `docs/domain/`:
```
@agent-domain-reviewer
```

Дождись APPROVE перед `/review`.

### 6. Review

```
/review
```

Claude сам критикует свой diff по severity.

Если PR затрагивает prod-bound пути (`bootstrap/`, `.github/workflows/`, `.git/hooks/`) или имеет label `prod-bound` — **в рамках той же фазы /review, до перехода к /codex-review**:
```
@agent-security-reviewer
```

`security-reviewer` — дополнение к `/review`, не замена и не отдельный шаг после него.

### 7. Codex review (two-voice)

```
/codex-review
```

Codex через Plus даёт второе мнение. Если Codex пропал (quota/timeout) — открывается `type:deferred-review` issue, pipeline не блокируется.

### 8. Разрешение разногласий

Если Codex и Claude расходятся — обсудить. Типичные ответы:
- Agreement → confident merge
- Codex caught miss → Claude признаёт, fix
- Codex не прав → Claude объясняет почему, ты решаешь

### 9. Commit with governance

```bash
git add <files>
git commit -m "feat: добавить retry logic (#42)"
```

PreToolUse hook проверит: CC prefix, issue-ref, ADR-ref. При ошибке — исправь сообщение.

### 10. PR

```bash
gh pr create --title "..." --body "Closes #42"
```

PR body должен включать:
- `Closes #<issue>`
- `Implements docs/decisions/NNNN-*.md` если был ADR
- DoD checklist из `.github/pull_request_template.md`

### 11. Forge lock-in surface

The following GitHub-specific commands and files are used in this pipeline. This inventory exists so a future forge migration has known, enumerated scope rather than surprise discovery. **Update this section when adding new `gh` commands.**

| Artifact | Location | Notes |
|---|---|---|
| `gh pr create` | Step 10 above; `bootstrap/commands/feature.md` step 11 | Creates PR from feature branch |
| `gh pr merge` | Operator post-review; `docs/decisions/0009-feature-branch-pr-flow.md` | Merges PR to main |
| `gh pr view` | `/review` skill, `/codex-review` skill | Reads PR metadata and diff |
| `gh issue view` | `bootstrap/commands/feature.md` line 11 | Loads issue JSON for `/feature` |
| `.github/pull_request_template.md` | `.github/pull_request_template.md` | PR body DoD checklist |
| `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | CI gate for required checks |

## Master orchestrator

Вместо последовательного вызова — одной командой:

```
/feature <issue-number>
```

Создаст TodoWrite со всеми стадиями и будет напоминать. Сами команды всё равно запускаешь ты.
