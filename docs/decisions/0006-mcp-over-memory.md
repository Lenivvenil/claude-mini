# 0006. Prefer MCP-retrieved context over Claude memory summaries

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: architecture, context, mcp

## Context and Problem Statement

У Claude есть memory-система с cross-session summaries. Есть также MCP-серверы, читающие актуальные артефакты (GitHub Issues, репо-файлы через Serena). Два источника контекста конкурируют — как понять какой источник истины.

## Decision Drivers

* Memory может отставать (периодическая генерация), MCP всегда live.
* Memory компрессирует; компрессия лосси.
* Четвёртая директива: "knowledge в инструментах, не в памяти".
* Новая сессия (особенно другого оператора) memory не имеет — только инструменты.

## Considered Options

* **Option A: Memory как primary, MCP как fallback.** Быстрый старт сессии, но stale-risk.
* **Option B: MCP как primary, memory — кэш "что говорит сам пользователь о себе".**
* **Option C: Disable memory для этого проекта.** Чистота инварианта.

## Decision Outcome

Chosen option: **Option B**. Memory остаётся включённой — она полезна для запоминания предпочтений оператора (не-репо фактов: как зовут, где работает, как любит форматировать). Memory не используется как источник истины про проект: ADR, issues, plans всегда читаются через tools. Option C (отключить memory) отказывает в полезной cross-project информации.

Материально: `CLAUDE.md` проекта начинается с фразы «Этот файл — карта, а не территория. Перечитывай при старте сессии; не кешируй в memory.» Это инструкция Claude не делать из чтения CLAUDE.md summary в memory — он перечитывается каждый раз.

### Positive Consequences

* Новая сессия (свежий контекст) получает актуальную картину из MCP.
* Другой оператор открывает репо без дисадвантажа (memory-то Venil'а, не его).
* Stale-risk минимизирован.

### Negative Consequences

* Накладные расходы: каждая сессия тратит первые tool calls на чтение state (issues, ADR, plans).
* Memory всё ещё может заводить Claude на стереотипы ("ты обычно делаешь X") — требуется явное подавление в CLAUDE.md.

## Confirmation

Тест: новый оператор (или вы сами через HTTPs на чужой машине) открывает репо и за час без чата восстанавливает "что сделано, что в работе, какие решения приняты". Если пришлось спросить Venil'а — инвариант сломан, memory-тяжесть просочилась.

## Re-visit Trigger

* Claude Code получает project-scoped memory, которая живёт в репо как артефакт (не в облаке Anthropic).
* Выяснится, что MCP-latency делает старт сессии неприемлемо медленным.

## Links

* `../architecture/overview.md` — где MCP stand in архитектуре
* `CLAUDE.md#source-of-truth`
