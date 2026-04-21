# 0002. Pipeline over fan-out for feature work

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: orchestration, agents, workflow
* Supersedes: Section F of `claude-multiagent-setup.md` (three-subagent fan-out pattern)

## Context and Problem Statement

Ранний multi-agent guide предлагал fan-out feature-работы на субагентов (`planner`, `coder`, `tester`) с шаринг контекста через compressed briefs. Опыт и Anthropic-исследования (advisor launch, April 9 2026) показали, что fan-out для содержательного кода даёт локально правильный, глобально неадекватный результат из-за lossy brief. Нужно решение, которое сохраняет context integrity при содержательных задачах.

## Decision Drivers

* Context non-fungibility: тысяча micro-decisions, которые накапливает main loop (файлы в соседних пакетах, стиль, дохлые ветки), не передаётся в абзац brief'а.
* SWE-bench Multilingual: advisor даёт +2.7 pp, fan-out на сложных задачах — регресс (Anthropic blog, April 9 2026).
* Single-author responsibility: три автора внутри одного feature-а размывают ответственность за код.
* Weekly Opus cap на Claude Max: fan-out требует много Opus-инференсов для каждого субагента.

## Considered Options

* **Option A: Сохранить fan-out.** Три субагента на feature, каждый в своём контексте. Координация через shared plan.
* **Option B: Pipeline с одним автором + advisor + read-only critics.** Linear sequence `/plan → /adr? → /implement → /review → /codex-review`. Subagents только read-only критики, вызываемые точечно.
* **Option C: Гибрид: pipeline для feature, fan-out для refactor/rename.** Формализованное правило когда можно fan-out.

## Decision Outcome

Chosen option: **Option C**, потому что (B) как дефолт + (A) как узкое исключение покрывают всю реальную нагрузку без потери context integrity там, где это важно. `docs/principles.md` запрещает fan-out для feature-работы; `CLAUDE.md` явно перечисляет разрешённые случаи (rename в 200 файлах, migration 50 импортов, шаблонизация тестов из схемы). Каждый fan-out — осознанное исключение, а не default.

### Positive Consequences

* Один автор на feature = один ответственный.
* Advisor делегирует «думать глубже» без потери контекста (server-side sub-inference).
* Opus-токены тратятся по ~2-3k на задачу вместо 200k — расход на weekly cap падает 10-50×.
* Критики специализируются и read-only — снижение риска «агент-коллега всё поломал».

### Negative Consequences

* Теряется кажущийся parallelism — задача идёт линейно.
* Invocation overhead на slash commands — стадии нельзя «проскочить».
* Требуется дисциплина: импульс «давай быстро subagent напишет боковой модуль» подавляется.
* Fan-out правила (что embarrassingly-parallel, что нет) требуют суждения — есть риск злоупотребления.

## Pros and Cons of the Options

### Option A: Pure fan-out

* Good, потому что воспринимаемый parallelism.
* Good, потому что меньше master-agent burn на тривиальных частях.
* Bad, потому что lossy brief → globally incoherent code.
* Bad, потому что три раза Opus context window вместо одного → дороже.
* Bad, потому что размытая ответственность в PR.

### Option B: Pure pipeline

* Good, полное context preservation.
* Good, детерминированная последовательность — легко аудировать.
* Bad, реально embarrassingly-parallel задачи (rename, migration) становятся медленными.
* Bad, недогружает возможность Claude Code работать с Task tool.

### Option C: Hybrid (chosen)

* Good, покрывает оба типа нагрузки корректным методом.
* Good, правило «когда fan-out» документировано и проверяемо.
* Bad, требует суждения на границе; потенциально слабое место.
* Bad, удваивает объём документации (два runbook'а вместо одного).

## Confirmation

Критерий: за 30 дней реальной работы в проекте количество fan-out случаев ≤ 10% от общего числа feature-задач, и каждый fan-out сопровождается комментарием в plan.md почему он допустим. Ревью через `/project-health` раз в неделю.

## Re-visit Trigger

* Anthropic выпускает официальный multi-agent primitive с guaranteed context preservation (например, shared session state между субагентами).
* Метрика показывает регулярное нарушение (>20% задач идут fan-out'ом) — значит правило непрактично.
* Введение команды >3 человек — тогда parallelism по людям заменяет parallelism по агентам.

## Links

* `0003-sonnet-main-opus-advisor.md` — как именно advisor встраивается в pipeline
* `0007-read-only-critic-agents.md` — почему агенты read-only
* `../runbooks/feature-pipeline.md` — практический ход pipeline
* Anthropic advisor launch blog, April 9 2026
