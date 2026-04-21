---
name: domain-discovery
description: DDD/Event Storming skill dlya issledovaniya novogo domena ili bounded context. Ispol'zuj pri zaprose "novyj domen", "event storming", "bounded context", "issledovaniye domena", "domain discovery", "UL nuzhna", "vocabulary".
---

# Domain discovery skill

## When to invoke

Invoked by `domain-researcher` agent, or when operator says:
- "новый bounded context"
- "event storming"
- "исследуем домен"
- "нужна Ubiquitous Language"

## Hard prerequisites

Before starting, verify:

1. `docs/domain/` directory exists (or will be created).
2. The BC name is known. Ask if not.
3. Confirm this is not existing BC evolution — for evolution, use `/plan` and update existing `overview.md`.

## Five-phase interview

### Phase 1: Actors (5 min)

Ask:
> Кто взаимодействует с этим BC? Внешние акторы, внутренние сервисы, автоматические процессы. Минимум 3.

Record as `- ActorName: role (human/service/scheduler/external-system)`.

### Phase 2: Events (past tense, 20 min)

Ask:
> Event Storming. Что уже произошло, что важно для этого BC? В прошедшем времени. Не "выставить счёт" (это команда), а "СчётВыставлен" (это событие).

Cycle through colors:
- **Orange (события)** — что произошло
- **Blue (команды)** — что вызывает событие (в повелительном наклонении)
- **Lilac (политики)** — "когда X, тогда Y"
- **Yellow (агрегаты)** — кто хранит инварианты
- **Green (read models)** — что потребляется для чтения
- **Red (горячие точки)** — неопределённости, разногласия, неизвестное

REFUSE to proceed if < 5 events. Keep pressing until operator surfaces more.

### Phase 3: Boundary (10 min)

Ask:
> Что входит в scope этого BC и что специально НЕ входит? Где проходит граница? И самое важное: **какой термин меняет смысл при переходе через эту границу?** Если ни один — возможно, это не отдельный BC.

Example: "Customer" inside Sales BC = покупатель; "Customer" inside Support BC = тикет-автор. Same word, different concept.

### Phase 4: Ubiquitous Language (15 min)

Ask:
> Минимум 5 терминов. Определения — на языке бизнеса, не технологий. "Order is a Go struct" — плохо. "Order is a customer's commitment to purchase that triggers fulfillment" — хорошо.

Build a table:
| Term | Business definition | Aliases to avoid |

REFUSE if < 5 real terms.

### Phase 5: Context map edges (10 min)

For each other BC the current one interacts with, ask:
> Какой паттерн связи? Shared Kernel / Customer-Supplier / Conformist / Anticorruption Layer / Open Host Service / Published Language / Separate Ways / Big Ball of Mud.

If operator doesn't know these patterns, briefly explain — but insist on picking one. "Just use" is not a pattern.

## Output

Write `docs/domain/<bc-name>/overview.md` with sections from the schema in agent `domain-researcher.md`.

## Hand-off

> Domain overview написан в `docs/domain/<bc>/overview.md`. Следующий шаг: `@agent-domain-reviewer docs/domain/<bc>/overview.md`. Если одобрит — commit и продолжайте на `/plan` уровне.

## Hard rules

- НЕ пропускайте phase, даже под давлением "у меня мало времени".
- НЕ принимайте "это очевидно" как ответ. Event Storming очевидное ловит в первой фазе; проблемы — в следующих.
- НЕ проектируйте implementation. Tables, APIs, code — всё в downstream.
- НЕ допускайте БГ (Big Ball of Mud) как постоянный паттерн — это временный статус, требующий рефакторинга.
