# 0027. Domain Inversion: Meta vs Target Bounded Contexts

* Status: accepted (2026-06-10)
* Superseded-by: ~
* Date: 2026-05-05
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: domain, bounded-context, ddd, context-map, acl, meta-pipeline
* Related issue: #130

## Context and Problem Statement

Текущий `docs/domain/` описывает pipeline как один плоский bounded context
с именем `claude-mini-pipeline`. Это инверсия домена: pipeline — это
переиспользуемый процессный инструмент, а не домен. Реальные домены живут
внутри pet-проектов (`archi2likec4`, `digest`, и т.д.), у каждого из них —
свой агрегат, свои инварианты, свой ubiquitous language. Verraes (2025)
формулирует разделение прямо: domains и BCs не сопоставляются 1 к 1, и
смешение технического процесса с предметным доменом — типовой
анти-паттерн при попытке стратегического DDD «сверху вниз».

Решение архитектурно значимо по
`docs/principles.md#что-значит-архитектурно-значимо`: одновременно
срабатывают три триггера — (1) меняется граница bounded context
(`claude-mini-pipeline` → `meta-pipeline` плюс отдельные target BCs за
пределами этого репозитория), (2) появляется новый межконтекстный контракт
(ACL над Conformist), (3) фиксируется ограничение, которое будет трудно
снять через 6 месяцев — после распространения схемы артефактов в
target-репо через `--target` любая правка meta-schema превращается в
миграционное событие для всех потребителей.

## Decision Drivers

* **Domains ≠ BCs (Verraes 2025).** Текущая модель путает «что мы делаем»
  (домен pet-проекта) с «как мы это делаем» (pipeline). Эта путаница не
  устраняется ни перефразировкой, ни добавлением раздела — только сменой
  границы.
* **Независимость pet-проектов.** Каждый pet-проект живёт в своём репо и
  не обязан знать о существовании других. claude-mini не имеет права
  разрастаться в God-репозиторий, описывающий все pet-домены централизованно.
* **Принцип 4 — knowledge in tools.** Цели modeling — назвать сущности
  ubiquitous language. Если `meta-pipeline BC` и target BC реально
  разные things, они должны быть разными именованными BC, а не одним.
* **Принцип 8 — запас 2-3×, не 1000×.** Полное DDD strategic design всех
  pet-проектов внутри claude-mini — overengineering: это перенос работы
  с конкретного проекта на meta-репо ради структуры, которой никто не
  будет пользоваться.
* **Принцип 1 — нет размытости.** Двойной vocabulary (top-level + meta/)
  при одном BC — гарантированный drift. Либо BC один и vocabulary один,
  либо BC два и vocabularies два, по одному на каждый.
* **Совместимость с уже принятыми ADR.** ADR-0020 фиксирует три агрегата
  и cross-aggregate-query DoD; ADR-0024 фиксирует Session Continuity как
  отдельный BC. Любая смена границы должна сохранить эти решения,
  иначе она их супер-седит, а это не цель.

## Considered Options

* **Option A — Move-and-merge.** Перенести существующие
  `docs/domain/vocabulary.md` и `docs/domain/overview.md` в
  `docs/domain/meta/`; ввести `docs/runbooks/setup-target-domain.md` как
  onboarding-инструкцию для target-проектов; задокументировать
  существующую фрагментированную реализацию ACL; полное DDD-описание
  target-проектов вынести в их собственные репо.
* **Option B — Keep flat BC, supplement with `meta/` overlay.** Оставить
  `vocabulary.md` и `overview.md` на верхнем уровне (помечены как
  deprecated), новые термины добавлять только в `meta/`. Постепенно
  мигрировать.
* **Option C — Full DDD strategic design всех pet-проектов внутри
  claude-mini.** Создать `docs/domain/archi2likec4/`,
  `docs/domain/digest/` и т.д. в этом репо; meta-pipeline — один из
  поддоменов наравне с остальными.

## Decision Outcome

Chosen option: **Option A — Move-and-merge в `meta-pipeline` BC с ACL
поверх Conformist в сторону target BC.**

Граница проводится по факту независимости lifecycle и владения данными.
`meta-pipeline` владеет процессом (FeatureRun, GovernanceRun,
TwoVoiceReview, RunbookExecution), его vocabulary описывает шаги
pipeline и governance-правила. Target BC владеет предметной моделью
конкретного pet-проекта (например, `C4-Diagram`, `ContainerLayer` для
`archi2likec4`), его vocabulary описывает термины этой предметной
области. Эти два домена не пересекаются: meta никогда не читает
target-доменные данные напрямую, target никогда не вызывает meta-команд.
Контактная поверхность — артефакты, которые target производит для meta
(plan.md, qa-report, commit-message), и которые meta валидирует против
своей схемы.

Этот выбор активирует Принцип 4 (knowledge in repo): два разных
концепта получают два разных имени и две разные документации, а не
склеиваются в один за счёт одинаковой инфраструктуры. Принцип 8
поддерживает отказ от Option C: claude-mini не должен брать на себя
работу по DDD-моделированию pet-проектов, которой никто не закажет —
это запас 1000× от реальной потребности. Принцип 1 поддерживает отказ
от Option B: deprecated-overlay создаёт два источника истины
параллельно, что неминуемо приводит к расхождению.

### Тип отношения между BC: AACL (Anti-Corruption Layer over Conformist)

Target BC **conforms** to meta's схеме артефактов: pipeline-стадии,
governance-правила, формат commit-message, структура plan.md и
qa-report — всё это диктуется meta, и target не имеет голоса в их
определении. В обратную сторону meta защищает себя через **ACL**:
прежде чем принять артефакт от target, meta валидирует его против
своей schema; невалидный артефакт отклоняется, и target домен не
протекает в meta.

Альтернативы для типа отношения, рассмотренные и отклонённые:

* **Customer/Supplier** — отклонено. Meta-schema не принимает запросы
  от отдельных target-проектов; target не может потребовать от meta
  изменения формата артефактов. Отношение асимметрично, но не в духе
  Customer/Supplier (где Supplier учитывает потребности Customer).
* **Partnership** — отклонено. Нет синхронной co-evolution: meta
  меняется по своим основаниям (внутренние ADR), target — по своим
  (продуктовые потребности). Никто никого не ждёт.
* **Shared Kernel** — отклонено. Нет общего кода или vocabulary,
  принадлежащего обеим сторонам. У meta свой словарь
  (`FeatureRun`, `GovernanceRun`), у target свой (`C4-Diagram`,
  `ContainerLayer`). Пересечения нет.
* **Open Host Service** — отклонено. Направление обратное: target
  потребляет язык meta (форматы артефактов), а не meta публикует
  стандартизированный API для произвольных потребителей. OHS
  предполагает, что upstream формализует язык для downstream; здесь
  downstream (target) подчиняется языку upstream (meta) без
  переговоров — это и есть Conformist.

### Ключевые подрешения, явно зафиксированные

Для трассируемости — `adr-reviewer` должен мочь найти каждый пункт:

1. **AC#2 reinterpretation — `docs/domain/<project>/` живёт в репо
   pet-проекта, не в claude-mini.** Исходная формулировка AC #2
   ("Establish `docs/domain/<project>/` for each pet-project") была
   написана так, как будто эти директории должны жить внутри
   claude-mini. Оператор уточнил: каждый проект живёт независимо;
   проекты не знают друг о друге. Корректная интерпретация:
   `docs/domain/<project>/` — путь **внутри собственного репо
   pet-проекта**. claude-mini поставляет только
   `docs/runbooks/setup-target-domain.md` как
   шаблон/инструкцию по onboarding. Этот pull прямо отклоняет
   Option C.

2. **AC#4 reinterpretation — существующая фрагментированная
   реализация ACL и есть ACL.** Исходная формулировка AC #4
   ("Implement ACL as a Python module") была расплывчатым
   аспирационным заявлением. Корректная интерпретация: ACL уже
   реализован тремя фрагментами:
   * `bootstrap/scripts/plan-lint.sh` — валидация `plan.md` на
     ADR-discipline;
   * `bootstrap/hooks/pre-commit-governance.sh` (и
     `commit-msg-governance.sh`) — валидация Conventional Commits +
     issue-ref + ADR-ref в commit message;
   * `@agent-domain-reviewer` — семантическая проверка vocabulary и
     invariant drift в `docs/domain/`.
   Каждый фрагмент закрывает свой класс артефактов. Консолидация в
   единый Python-модуль — отдельный follow-up issue, **не часть этого
   PR**. Документация существующих фрагментов как ACL — обязательная
   часть `/implement` по этому ADR.

3. **Совместимость с ADR-0020 сохранена.** Domain Inversion меняет
   имя и scope BC (`claude-mini-pipeline` → `meta-pipeline`), но НЕ
   меняет:
   * cross-aggregate query для DoD: `FeatureRun.dod_state → done`
     требует `GovernanceRun.state = approved` AND
     `TwoVoiceReview.state ∈ {agreed, reconciled, deferred}`;
   * четыре инварианта `FeatureRun` (см. ADR-0020 §"Cross-aggregate
     communication" и §"Scope of extraction");
   * `SecurityReview` / `ReliabilityReview` остаются в `FeatureRun`,
     не мигрируют в `TwoVoiceReview`;
   * `advisor_critique` остаётся в `FeatureRun`, не мигрирует в
     `TwoVoiceReview`.
   ADR-0020 НЕ супер-седится — все его подрешения преимущественно
   structurally сохраняются. Цитаты на `claude-mini-pipeline` в
   ADR-0020 становятся технически устаревшими по имени, но
   семантически корректными (тот же агрегатный набор, новое имя BC).

4. **Совместимость с ADR-0024 сохранена.** Session Continuity
   остаётся отдельным sibling BC, как объявлено ADR-0024. Все девять
   подрешений ADR-0024 (BC placement, aggregate root,
   cross-BC reference pattern, session_id format, session-log порядок,
   linter scope, log format, отдельность session-log и events.jsonl,
   stale detection) сохраняются. Точное отношение между
   `meta-pipeline` BC и `Session Continuity` BC (sibling? nested
   внутри meta?) — **TBD в follow-up issue**, и этот ADR его НЕ
   решает. ADR-0024 НЕ супер-седится. Текущая формулировка ADR-0024
   "Session Continuity is a bounded context peer to
   `claude-mini-pipeline`" читается как peer к новому
   `meta-pipeline` тем же образом.

5. **RunbookExecution — четвёртый агрегат `meta-pipeline`, статус
   draft.** RunbookExecution объявлен как четвёртый aggregate root в
   `meta-pipeline` BC наравне с FeatureRun, GovernanceRun,
   TwoVoiceReview. Однако его state-machine, инварианты, command/event
   набор — **provisional**. Перед финализацией требуется мини
   Event Storming session с оператором. До тех пор раздел
   RunbookExecution в `docs/domain/meta/overview.md` помечается
   `status: draft`, и `domain-reviewer` НЕ блокирует на нарушении
   его инвариантов (потому что инварианты ещё не зафиксированы).

### Scope of artifacts (что коммитится в `/implement`)

После принятия этого ADR и реализации:

* `docs/domain/meta/overview.md` существует и содержит описание
  `meta-pipeline` BC: четыре aggregate roots (FeatureRun,
  GovernanceRun, TwoVoiceReview, RunbookExecution), commands/events,
  policies, NFR. RunbookExecution-секция помечена `status: draft`.
* `docs/domain/meta/vocabulary.md` существует и содержит ubiquitous
  language `meta-pipeline` (перенос текущего `vocabulary.md` плюс
  RunbookExecution-термины со статусом draft).
* `docs/domain/context-map.md` существует с Mermaid-диаграммой,
  показывающей: `meta-pipeline BC` ←AACL→ `target BC`,
  `meta-pipeline BC` ↔sibling↔ `Session Continuity BC` (отношение
  TBD в follow-up).
* `docs/runbooks/setup-target-domain.md` существует как onboarding-
  инструкция для pet-проекта: как создать `docs/domain/` в своём
  репо, как зарегистрировать target-схему, какие артефакты meta
  ожидает.
* Существующие верхнеуровневые `docs/domain/vocabulary.md` и
  `docs/domain/overview.md` либо удалены, либо превращены в
  редиректы на `docs/domain/meta/*.md` (выбор — за `/implement`).
* `bootstrap/agents/domain-reviewer.md` обновлён: знает о
  `meta-pipeline` BC, четырёх агрегатах (RunbookExecution в
  draft-режиме), о существовании target BC за границей репо
  (но не валидирует target-домен).
* Документ `docs/architecture/` (если затрагивается) обновлён:
  любое упоминание `claude-mini-pipeline` BC заменено на
  `meta-pipeline` BC.

### Positive Consequences

* `meta-pipeline` и target BC получают first-class identity в
  ubiquitous language: каждый — referenceable noun. Будущие ADR,
  runbook'и и PR-описания ссылаются однозначно.
* Pet-проекты остаются независимыми. claude-mini не превращается в
  God-репо, описывающий все домены. Установка claude-mini в новый
  pet-проект не требует от него поделиться доменом.
* Граница между «процесс» и «домен» становится явной. Инверсия
  устранена: pipeline — это не домен, это процесс над доменом.
* Тип отношения AACL над Conformist даёт прямую модель для будущих
  target-проектов: «вы конформитесь к нашей schema артефактов; мы
  валидируем входящие». Без переговоров, без synchronous co-evolution.
* Совместимость с ADR-0020 и ADR-0024 сохранена — никаких супер-
  седов, никаких структурных откатов.

### Negative Consequences

* **Latent enforcement.** ADR фиксирует границу и типы отношений; вся
  protection материализуется только после `/implement` (миграция
  файлов, обновление `domain-reviewer`, runbook). Между merge этого
  ADR и merge `/implement`-PR BC переименован, но не материализован.
* **ACL остаётся фрагментированным.** AC#4 пере-интерпретирован:
  единого Python-модуля нет, есть три bash/markdown-фрагмента
  (`plan-lint.sh`, `pre-commit-governance.sh`, `@agent-domain-reviewer`).
  Каждый покрывает свой класс артефактов; никто не валидирует все
  входящие артефакты единообразно. Консолидация — отдельный
  follow-up, не закрыта этим ADR.
* **RunbookExecution провизорный.** Один из четырёх агрегатов
  `meta-pipeline` ships в draft-статусе. `domain-reviewer` не может
  enforce-ить его инварианты до Event Storming session. Это
  documented seam, не fixed problem.
* **Naming churn существующих ADR.** ADR-0020, ADR-0024, ADR-0007 (и
  другие) цитируют BC под именем `claude-mini-pipeline`. После
  Domain Inversion имя BC — `meta-pipeline`. Цитаты остаются
  технически устаревшими по имени; читатель должен mentally
  подставлять новое имя. Чтобы не вышло supersede-цикла, эти ADR не
  переписываются.
* **Target репо обязаны конформиться без права голоса.** Conformist-
  направление асимметрично: если target-проекту нужен другой формат
  plan.md или другой governance-flow, у него нет канонического канала
  потребовать изменения. Запрос на изменение meta-schema превращается
  в issue на claude-mini, который мерж-ится по своим правилам.
* **Schema-migration cost масштабируется по количеству target-репо.**
  Любое breaking-изменение meta-schema (формат plan.md, правила
  pre-commit-governance, инварианты домен-reviewer) — миграционное
  событие, которое надо раскатываться по всем установленным target-
  репо через `--target`. Цена пропорциональна количеству target-
  проектов.
* **Большая cognitive entry cost для новичка.** Раньше один BC, одно
  vocabulary, один overview. После: два BC (`meta-pipeline` и
  `Session Continuity`) с ссылкой на третий за границей репо
  (target), context-map, AACL-relationship type. Onboarding-кривая
  растёт.
* **Отношение `meta-pipeline ↔ Session Continuity` остаётся TBD.**
  ADR-0024 объявил Session Continuity как peer к
  `claude-mini-pipeline`. Этот ADR переименовал и переграничил
  бывший `claude-mini-pipeline`, но не описал, как именно теперь
  выглядит peer-отношение к Session Continuity (sibling под одним
  meta-зонтом? nested внутри meta? полностью независимый peer?).
  Решение — отдельный follow-up issue.

## Pros and Cons of the Options

### Option A — Move-and-merge

* Good, потому что граница проводится по факту независимости
  lifecycle: процесс vs домен — действительно разные things.
* Good, потому что pet-проекты остаются независимыми; claude-mini не
  принимает на себя работу по их DDD-моделированию.
* Good, потому что AACL над Conformist — реалистичная модель
  отношений: meta диктует формат, target подчиняется, meta валидирует.
* Good, потому что ADR-0020 и ADR-0024 сохраняются без супер-седа —
  только переименование BC, не структурный откат.
* Good, потому что миграция механическая: переместить два файла в
  `meta/`, написать context-map, написать onboarding runbook.
* Bad, потому что enforcement остаётся latent до merge `/implement`.
* Bad, потому что AC#4 пере-интерпретируется в "ACL = три
  существующих фрагмента"; единый Python-модуль остаётся
  follow-up'ом, и наивный читатель ожидает большего.
* Bad, потому что RunbookExecution shipped в draft-режиме —
  consistency `domain-reviewer` ослабевает на одном из четырёх
  агрегатов.
* Bad, потому что отношение к `Session Continuity` BC переоткрыто —
  ADR-0024 описывал peer к `claude-mini-pipeline`, а теперь peer к
  чему именно? Это TBD.

### Option B — Keep flat BC, supplement with `meta/` overlay

* Good, потому что не требует немедленного move; миграция
  постепенная, риск ошибки меньше.
* Good, потому что существующие цитаты на `vocabulary.md` и
  `overview.md` остаются валидными короткое время.
* Bad, потому что появляются два vocabulary под одним BC — гарантированный
  drift между deprecated top-level и new `meta/`. Нарушение Принципа 1
  (нет размытости).
* Bad, потому что фактическая граница BC не меняется — это
  косметическая правка раскладки файлов под видом архитектурного
  решения. Domain inversion НЕ устраняется.
* Bad, потому что новые термины придётся помещать «или там, или
  тут» — каждый раз с обоснованием выбора, потому что граница не
  чистая.
* Bad, потому что миграция «потом» в практике никогда не
  завершается — deprecated-файлы живут вечно, vocabulary дрейфит.

### Option C — Full DDD strategic design всех pet-проектов внутри claude-mini

* Good, потому что один центральный обзор всех доменов; наглядно для
  одного оператора с одним мозгом.
* Bad, потому что pet-проекты теряют независимость: чтобы изменить
  свою domain-модель, target должен делать PR в claude-mini.
  Нарушение базового решения «проекты не знают друг о друге».
* Bad, потому что claude-mini становится God-репо, отвечающим за
  все домены оператора. Объём растёт пропорционально количеству
  pet-проектов; ни один из них не получит достаточной глубины.
* Bad, потому что Принцип 8 — это запас 1000×: кто будет
  поддерживать DDD-модель `digest` или `archi2likec4` синхронно с
  кодом этих проектов? Никто. Модель устаревает в момент создания.
* Bad, потому что это явно отклонено оператором; AC говорит
  "**Non-Goals:** Full DDD strategic design for every pet-project".

## Confirmation

После принятия этого ADR и реализации в `/implement`:

1. **`docs/domain/meta/overview.md` существует** и описывает
   `meta-pipeline` BC: четыре aggregate roots, commands/events,
   policies. RunbookExecution-секция помечена `status: draft`,
   инвариантов нет.
2. **`docs/domain/meta/vocabulary.md` существует** и содержит
   ubiquitous language `meta-pipeline` (включая текущие термины
   `FeatureRun`, `GovernanceRun`, `TwoVoiceReview`, `dod_state`,
   `Advisor` и др. + новые draft-термины для RunbookExecution).
3. **`docs/domain/context-map.md` существует** с Mermaid-диаграммой,
   показывающей AACL-отношение `meta-pipeline BC ←AACL→ target BC`
   и (TBD) отношение к `Session Continuity BC`.
4. **`docs/runbooks/setup-target-domain.md` существует** и описывает,
   как pet-проект разворачивает свой `docs/domain/` (внутри
   собственного репо), как регистрирует target-схему, какие
   артефакты meta ожидает.
5. **`bootstrap/agents/domain-reviewer.md` обновлён** и знает о
   `meta-pipeline` (4 агрегата, RunbookExecution draft) и о
   существовании target BC за границей репо. Не валидирует
   target-домен.
6. **Существующие верхнеуровневые `docs/domain/vocabulary.md` и
   `docs/domain/overview.md` мигрированы** (либо удалены, либо
   redirect-stub'ы на `meta/`). Исключение: `docs/domain/session-
   continuity/` (отдельный BC по ADR-0024) остаётся на своём месте.
7. **Документация существующего ACL.** В `docs/domain/meta/overview.md`
   §"ACL" перечислены три фрагмента: `bootstrap/scripts/plan-lint.sh`
   (plan ADR-discipline), `bootstrap/hooks/pre-commit-governance.sh` +
   `commit-msg-governance.sh` (commit message + issue/ADR refs),
   `bootstrap/agents/domain-reviewer.md` (vocabulary/invariant drift).
   Указан scope каждого и явно сказано, что консолидация — follow-up.
8. **Follow-up issues созданы:**
   * Event Storming для RunbookExecution — финализация state-machine
     и инвариантов.
   * Уточнение отношения `meta-pipeline ↔ Session Continuity`
     (sibling/nested) — будущий ADR.
   * Консолидация ACL в единый Python-модуль (или решение о
     сохранении фрагментированной формы) — будущий ADR.
9. **Ни один из четырёх инвариантов FeatureRun (ADR-0020) не
   нарушен.** Cross-aggregate query DoD читается без изменений.
   `SecurityReview`, `ReliabilityReview`, `advisor_critique`
   остаются в FeatureRun.

## Re-visit Trigger

Re-open this decision when **any one** is true:

* **Event Storming для RunbookExecution показал, что это не один
  агрегат.** Если ES вскрывает, что RunbookExecution лучше сплитить
  на два или объединить с другим существующим агрегатом — следующий
  ADR пере-смотрит aggregate-набор `meta-pipeline`.
* **Отношение `meta-pipeline ↔ Session Continuity BC` описывается
  как nested, а не sibling.** Если follow-up принимает решение, что
  Session Continuity находится «внутри» meta (например, Continuity
  становится частью RunbookExecution), это ADR пере-смотрит
  context-map.
* **Target pet-проект требует от meta читать его доменные данные
  напрямую.** Если возникает реальный use-case, где meta должен
  заглянуть в target-домен (например, для специализированной
  валидации или агрегации метрик), направление AACL Conformist
  ломается. Следующий ADR ре-моделирует тип отношения.
* **Фрагментация ACL становится maintenance liability.** Если
  drift между `plan-lint.sh`, `pre-commit-governance.sh` и
  `domain-reviewer` накапливается до уровня, где invariants
  пересекаются с конфликтами или дублируются — приходит время
  следующего ADR на консолидацию.
* **Schema-миграция meta ломает downstream targets at scale.** Если
  изменение meta-schema (формат plan.md, правила governance)
  требует ручной миграции в более чем двух target-репо одновременно
  — следующий ADR должен описать миграционный протокол (versioning,
  compatibility window, deprecation policy).
* **Появляется второй pet-проект, повторяющий target-структуру.**
  При наличии второго реального target (помимо `archi2likec4`),
  пере-проверить, что Conformist-направление действительно работает
  в обе стороны и target'ы не пытаются переговариваться через meta
  как через Customer/Supplier.

## Links

* GitHub issue #130 — Domain Layer Refactoring problem statement и
  acceptance criteria.
* `docs/decisions/0020-god-aggregate-sub-aggregate-extraction.md` —
  предыдущая фиксация трёх aggregate roots внутри
  `claude-mini-pipeline`. Этим ADR имя BC меняется на
  `meta-pipeline`; структурный набор агрегатов и инварианты
  сохраняются (см. §"Совместимость с ADR-0020").
* `docs/decisions/0024-session-continuity-bc-and-state-schema.md` —
  Session Continuity BC. Сохраняется как отдельный BC; точное
  отношение к `meta-pipeline` BC — TBD в follow-up.
* `docs/decisions/0007-read-only-critic-agents.md` — определение
  read-only-критиков; `domain-reviewer` обновляется как следствие
  этого ADR.
* `docs/principles.md#4-знание-живёт-в-репо-в-репо-или-нигде` —
  Principle 4: разные things получают разные имена в ubiquitous
  language.
* `docs/principles.md#8-антихрупкость-по-домену-запас-2-3-не-1000` —
  Principle 8: основание отказа от Option C.
* `docs/principles.md#1-размытость--нарушение` — Principle 1:
  основание отказа от Option B (двойной vocabulary при одном BC).
* `docs/principles.md#что-значит-архитектурно-значимо` — три
  триггера архитектурной значимости, срабатывающие здесь.
* `docs/domain/overview.md` — current `claude-mini-pipeline` BC
  overview; будет перенесён в `docs/domain/meta/overview.md` при
  `/implement`.
* `docs/domain/vocabulary.md` — current ubiquitous language; будет
  перенесён в `docs/domain/meta/vocabulary.md` при `/implement`.
* Verraes M. (2025) — формулировка «domains and BCs don't map 1
  to 1»; источник постановки задачи.
* DDD Europe 2025 / Synpulse8 AACL pattern — внешний reference на
  AACL (Anti-Corruption Layer over Conformist) как тип отношения
  между BC.
* `bootstrap/scripts/plan-lint.sh`, `bootstrap/hooks/pre-commit-
  governance.sh`, `bootstrap/hooks/commit-msg-governance.sh`,
  `bootstrap/agents/domain-reviewer.md` — три фрагмента
  существующего ACL (см. AC#4 reinterpretation).
