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

### 5. Implementation

```
/implement
```

Claude:
- Читает plan.md и упомянутые файлы
- Вызывает advisor × 1 перед началом
- Пишет код, гоняет тесты
- Вызывает advisor × 2 перед declared done

Если plan дрейфует в процессе — Claude должен STOP и обновить plan.md. Если ты видишь дрейф без обновления — красный флаг, скажи.

### 6. Review

```
/review
```

Claude сам критикует свой diff по severity.

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

## Master orchestrator

Вместо последовательного вызова — одной командой:

```
/feature <issue-number>
```

Создаст TodoWrite со всеми стадиями и будет напоминать. Сами команды всё равно запускаешь ты.
