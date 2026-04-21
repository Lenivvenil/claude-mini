# 0003. Sonnet 4.6 main loop with Opus 4.7 advisor

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: orchestration, cost, performance

## Context and Problem Statement

Claude Max план имеет weekly Opus cap. При main-loop на Opus 4.7 типичная session в 200k контекста съедает cap за несколько задач, оставляя дни без Opus. Нужен режим, в котором глубокое мышление Opus применяется только там, где оно нужно, а остальное работает на Sonnet.

## Decision Drivers

* Weekly Opus cap — дефицитный ресурс; цена промаха высока (день без Opus при важной архитектурной работе).
* Sonnet 4.6 snappier на десятках tool calls per task — для mechanical работы быстрее per-call.
* Opus 4.7 «effort-calibrated» — на low effort может под-думать; при явном advisor-вызове включается на полную.
* Advisor pattern (April 9 2026) — server-side sub-inference на той же сессии, без lossy brief.

## Considered Options

* **Option A: Main loop на Opus 4.7.** Максимальное качество, минимум инструментария.
* **Option B: Main loop на Sonnet 4.6, Opus 4.7 вызывается через `/advisor` на hard steps.**
* **Option C: Main loop на Haiku 4.5 + Opus advisor.** BrowseComp SWE-bench на Haiku+advisor: 19.7 → 41.2. Максимальная экономия.
* **Option D: Context-aware: начинать с Sonnet, переключаться на Opus при срабатывании эвристики сложности.**

## Decision Outcome

Chosen option: **Option B**. Main Sonnet + advisor Opus — это 10-50× снижение Opus-расхода per-session при сохранении качества на hard steps. Haiku+advisor (C) даёт бóльшую экономию, но Haiku слабее на multi-file navigation, что критично при работе через MCP (Serena, GitHub). Опция D (dynamic switching) не поддерживается нативно Claude Code; попытка её имитировать через subshells ломает session state.

### Positive Consequences

* Opus weekly cap хватает на ~10× больше задач.
* Sonnet быстрее на tool-heavy-работе (десятки read'ов, греп'ов).
* Advisor вызывается детерминированно дважды на нетривиальную задачу (перед работой и перед declared done) — защита от under-thinking.

### Negative Consequences

* Есть риск что advisor Opus-токены биллятся на тот же weekly cap (не публично подтверждено Anthropic). Нужна эмпирическая верификация за первые 48 часов работы.
* На простейших задачах advisor — overhead; нужно правило «не звать на тривиальное».
* Sonnet 4.6 может принять решение, которое Opus 4.7 не принял бы — граница между «тривиальной» и «нужен advisor» задачей размытая.

## Confirmation

После 48 часов типичной нагрузки:

* `/usage` показывает, что Opus weekly bucket потрачен <50% (раньше — >80%).
* Количество advisor-вызовов в session log — в диапазоне 1-4 per feature, как предписано `CLAUDE.md`.
* Если advisor Opus-токены биллятся на weekly cap — рассчитать новый бюджет и задокументировать в ADR-update.

## Re-visit Trigger

* Anthropic публикует официальное guidance по advisor billing (подтверждает или опровергает счёт на weekly cap).
* Выход Opus 5 или Sonnet 5 меняет soft/hard capability границу.
* Выход модели, которая объединяет Sonnet-скорость и Opus-глубину.
* Введение Claude-Enterprise плана с per-model квотами вместо объединённого cap'а.

## Links

* `0002-pipeline-over-fanout.md` — advisor как замена fan-out'у
* Anthropic advisor launch blog (April 9 2026)
* SWE-bench Multilingual delta report (+2.7 pp)
