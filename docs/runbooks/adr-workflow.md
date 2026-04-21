# Runbook: ADR workflow

Как принять архитектурно-значимое решение и зафиксировать его.

## Когда ADR нужен

Проверь по `docs/principles.md#что-значит-архитектурно-значимо`:

- Добавляется cross-cutting зависимость (logger, ORM, HTTP-клиент)
- Меняется граница BC или сигнатура межконтекстного контракта
- Выбор хранилища, очереди, cloud-платформы
- Публичный API
- Ограничение, которое будет трудно снять через 6 месяцев
- Смена модели безопасности или данных

Хотя бы одно — ADR. Ни одного — это plan, не decision.

## Workflow

### 1. Решение появилось — создать issue

```
/task-to-issue "ADR: retry strategy для HTTP-клиента"
```

Добавь label `adr-needed`.

### 2. Invoke solutions-architect

```
@agent-solutions-architect
```

Агент проведёт интервью через `adr-author` skill. Это серьёзный процесс — закладывай 30-60 минут.

**Ключевые требования к тебе** (агент не пропустит):
- ≥ 3 Decision Drivers
- ≥ 3 реальных Considered Options (не strawmen)
- Bad Consequences ≥ Good Consequences
- Ссылка на `docs/principles.md`
- Конкретный Confirmation mechanism (не "будем следить")
- Falsifiable Re-visit Trigger

Не пытайся срезать углы — агент откажется продолжать при нарушениях.

### 3. Review черновика

```
@agent-adr-reviewer docs/decisions/NNNN-<slug>.md
```

Reviewer проверит по severity (CRITICAL / WARNING / NIT). CRITICAL — блокирует approval. Исправляй и повторяй до zero CRITICAL/WARNING.

### 4. PR

```bash
git checkout -b adr/NNNN-<slug>
git add docs/decisions/NNNN-<slug>.md
git commit -m "adr: NNNN <slug> (#<issue>)"
gh pr create --title "adr: NNNN <slug>" \
             --body "Opens decision for review. Closes #<issue>" \
             --label type:adr
```

Governance hook не требует issue-ref для `adr:`-коммитов, но labels обязательны.

### 5. Merge

После review другими участниками (если есть) — merge. Пометь issue closed.

## Если ADR не удаётся

Иногда выходит, что принимать решение рано — нет данных, нет примеров реализации. Честный выход: **ADR со статусом "proposed"** и явной секцией "Open questions". Не заставляй себя решать без оснований.

Альтернатива: спайк-issue, результат которого — данные для следующего захода на ADR.

## Supersede

Если более ранний ADR устарел:

1. Новый ADR пишется как обычно
2. В секции `Status:` нового — `accepted` 
3. В старом — `superseded by [NNNN](NNNN-*.md)`
4. В новом — `Supersedes: [MMMM](MMMM-*.md)` в секции Links

Старый ADR НИКОГДА не удаляется. История решений — часть документации.
