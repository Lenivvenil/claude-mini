---
name: adr-author
description: Write an ADR in MADR 4.0 through a short interview. Use for /adr, "new decision", "architectural decision record", only for architecturally significant decisions by the project's own rules.
---

# ADR author skill

## When to invoke

Invoked by `/adr` command or when operator says:
- "нужен ADR"
- "зафиксируем решение"
- "создай новое архитектурное решение"
- «architectural decision record»

## Hard prerequisites

Before starting, verify:

1. Issue linked (`gh issue view` returns the issue).
2. Decision is architecturally significant by the project's own criteria (`AGENTS.md` or an ADR trigger doc; otherwise the list in the `plan` skill). If not, say "This is a plan, not a decision" and suggest `claude-mini:plan`.

## The seven-step interview

Conduct sequentially. Do not skip. Do not let operator shortcut.

### Step 1: Context (why now?)

Ask:
> Что именно происходит, что требует решения сейчас? Не история, а триггер — что в вас толкает принять это решение в этот момент?

Two-to-four sentences. Write as-is into Context section.

### Step 2: Decision Drivers

Ask:
> Какие силы определяют выбор?

If there is only one driver, say so: this may be a task, not a decision.

### Step 3: Considered Options

Ask:
> Какие варианты вы реально рассмотрели? Соломенные чучела не считаются. Если текущее положение дел — реальный вариант, включите его.

For each option:
> Дайте одно предложение, что это — чтобы человек через полгода понял.

If an option looks obviously wrong or a strawman, PUSH BACK:
> "Это кажется соломенной фигурой. Что именно в ней плохо, и почему вы её включили? Если она действительно нереалистичная, замените настоящей альтернативой."

### Step 4: Pros and Cons per option

For each option, ask:
> Что хорошего и что плохого? Если у варианта нет цены, её ещё не нашли.

### Step 5: Decision Outcome

Ask:
> Какой вариант выбираете и почему? Обоснование должно ссылаться на Decision Drivers.

If the project has written principles or rules (`AGENTS.md`, `docs/principles.md`), cite the ones the choice relies on.

### Step 6: Positive/Negative Consequences

Ask:
> Положительные последствия и отрицательные. Если отрицательных нет, вы себя уговариваете, а не принимаете решение.

### Step 7: Confirmation + Re-visit Trigger

Ask:
> **Confirmation:** Как мы узнаем, что решение было правильным? Конкретный механизм — не "будем следить", а "раз в неделю проверять X, порог Y".
>
> **Re-visit Trigger:** При каком фальсифицируемом условии решение пересматривается? Если вы не можете придумать — решение не является решением, это догма.

## Output

Write `docs/decisions/NNNN-<slug>.md` filling in `docs/decisions/adr-template.md`. NNNN from `scripts/next_adr_number.sh`.

## Hand-off

After writing:

> ADR черновик написан в `docs/decisions/NNNN-<slug>.md`. Следующий шаг: `@agent-adr-reviewer docs/decisions/NNNN-<slug>.md`. Если reviewer одобрит — `git checkout -b adr/NNNN-<slug> && git commit && gh pr create --label type:adr`.

## Hard rules

- НЕ пропускайте шаги, даже если operator торопится.
- НЕ пишите за оператора. Если оператор даёт общие слова — переспрашивайте.
- НЕ сокращайте interview до template-filling. Смысл skill — в качестве мышления, а не в форме.
