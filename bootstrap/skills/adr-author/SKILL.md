---
name: adr-author
description: Navyk dlya sozdaniya ADR po MADR 4.0 cherez interv'yu. Ispol'zuj pri zaprose /adr, "novoye reshenie", "zafiksiruem reshenie", "architectural decision record", "ADR nuzhen". Zapuskaj tol'ko dlya arhitekturno-znachimykh reshenij (sm. principles.md).
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
2. Decision qualifies as architecturally-significant per `docs/runbooks/adr-trigger.md`. If not, REFUSE: "This is a plan, not a decision. Use `/plan`."

## The seven-step interview

Conduct sequentially. Do not skip. Do not let operator shortcut.

### Step 1: Context (why now?)

Ask:
> Что именно происходит, что требует решения сейчас? Не история, а триггер — что в вас толкает принять это решение в этот момент?

Two-to-four sentences. Write as-is into Context section.

### Step 2: Decision Drivers (≥3)

Ask:
> Какие силы определяют выбор? Перечислите минимум три. Если только одна — вы не на уровне решения, вы на уровне задачи.

If operator gives < 3, REFUSE to proceed. Ask again until ≥3.

### Step 3: Considered Options (≥3 realistic)

Ask:
> Какие варианты вы реально рассмотрели? Минимум три. Strawmen не считаются — не пишите "ничего не делать" просто чтобы было три.

For each option:
> Дайте одно предложение, что это — чтобы человек через полгода понял.

If an option looks obviously wrong or a strawman, PUSH BACK:
> "Это кажется соломенной фигурой. Что именно в ней плохо, и почему вы её включили? Если она действительно нереалистичная, замените настоящей альтернативой."

### Step 4: Pros and Cons per option

For each option, ask:
> Хорошее (≥2 пункта) и плохое (≥2 пункта). Если плохого не видите — вы себе льстите. Задумайтесь ещё раз.

### Step 5: Decision Outcome

Ask:
> Какой вариант выбираете и почему? Обоснование должно ссылаться на Decision Drivers.

Check: choice must link to at least one principle in `docs/principles.md`. If not, ASK:
> Какой принцип из `docs/principles.md` здесь задействован? Если ни один — это не архитектурное решение, это предпочтение.

### Step 6: Positive/Negative Consequences

Ask:
> Положительные последствия и отрицательные. ЖЁСТКОЕ правило: **отрицательных должно быть не меньше, чем положительных**. Если вы видите только плюсы, вы себя уговариваете, а не принимаете решение.

If Bad < Good, REFUSE and ask again.

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
- НЕ переходите к следующему шагу, если на текущем не выполнены quantitative-требования (3+ drivers, 3+ options, Bad≥Good).
- НЕ пишите за оператора. Если оператор даёт общие слова — переспрашивайте.
- НЕ сокращайте interview до template-filling. Смысл skill — в качестве мышления, а не в форме.
