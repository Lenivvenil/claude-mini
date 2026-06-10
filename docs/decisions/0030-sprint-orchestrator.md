# 0030. Use external bash process as sprint orchestrator over `/feature`

* Status: proposed (frozen 2026-06-10 — parked until digest-driven need; spike #227 closed as parked, see #255)
* Superseded-by: ~
* Date: 2026-05-10
* Deciders: Venil (operator)
* Tags: pipeline, orchestration, automation

## Context and Problem Statement

Текущий feature pipeline (`/feature <issue>`) запускается оператором по одному тикету за раз. Когда в Sprint-колонке висит N тикетов, оператор вынужден повторять одну и ту же последовательность вручную — это узкое место для autonomous backlog sweep (#44 Phase-0). Нужен механизм, который проходит по всему Sprint-статусу подряд без модификации существующего pipeline и без потери per-ticket изоляции; решение архитектурно значимо, потому что фиксирует контракт между внешним оркестратором и Claude Code как runtime'ом, выбирает источник истины для прогресса и определяет границу escalation'а.

## Decision Drivers

* Pipeline должен остаться неизменным — добавление autonomous sweep не должно требовать правки `/feature`, `/plan`, `/implement` или любого существующего skill'а; иначе нарушается Принцип 2 (Claude — критик, не executor: skill «один тикет» не превращается в multi-issue executor)
* GitHub — источник истины: статус Sprint, факт завершения тикета, escalation state должны быть проверяемы через `gh` API, а не через session-state или `.sprint-state` в одиночку (Принцип 7: vendor — расходник, артефакт читаем без оркестратора)
* Per-ticket isolation: контекст тикета N не должен протекать в тикет N+1 — каждая сессия Claude Code изолирована своим context window, что детерминирует контракт «один тикет — одна сессия»
* Детерминированная пост-верификация: успех sweep'а проверяется наблюдаемым фактом в репо/GitHub (PR существует, issue закрыт, label `needs-human` повешен), а не доверием к stdout Claude Code (Принцип 3: сначала детерминированный тулинг)
* Continuity-контракт: при сбое sweep'а посередине оператор должен иметь возможность открыть репо и продолжить руками с точки остановки без расспросов LLM (Принцип 9)

## Considered Options

* **Вариант A.** Headless-step-per-call — один `claude -p` вызов на стадию pipeline (plan, implement, qa, review) с реконструкцией контекста между вызовами
* **Вариант B.** `/sprint` slash-команда внутри одной живой сессии Claude Code, цикл по всем Sprint-тикетам в пределах одного context window
* **Вариант C.** Orchestrator внутри `/feature` — модифицировать `/feature` так, чтобы он сам обнаруживал и обрабатывал все Sprint-тикеты
* **Вариант D.** Внешний bash-процесс `bootstrap/scripts/sprint.sh`, одна Claude Code сессия на тикет через `claude -p "/feature <issue>"`, детерминированная пост-верификация фактов в репо/GitHub, закрытый список escalation-триггеров — выбран

## Decision Outcome

Chosen option: **Вариант D**, потому что он закрывает все пять drivers одним внешним процессом и ни одной модификацией существующего pipeline. Sprint orchestrator живёт как `bootstrap/scripts/sprint.sh` снаружи Claude Code — это применение Принципа 2: skill `/feature` остаётся single-issue orchestrator'ом, а multi-issue logic'а вынесена туда, где её можно реализовать на bash + `gh` без LLM. Источником истины остаётся GitHub (Принцип 7): прогресс sweep'а читается через `gh issue list --label sprint`, `gh pr list`, `gh issue view --json labels`; локальный `.sprint-state` — только кэш для restart-recovery, не canonical state. Per-ticket isolation достигается тем, что каждая итерация bash-цикла спавнит новый процесс `claude -p`, который начинает с чистого context window — это естественное свойство headless-вызова, не отдельная логика. Детерминированная пост-верификация (Принцип 3) реализуется bash-функциями: после каждого `claude -p` оркестратор сверяется не со stdout, а с фактами — `gh pr view <N>`, `gh issue view <N> --json state,labels`. Continuity (Принцип 9): оператор в любой момент может прочитать `.sprint-state` (plain JSON) или GitHub-метки и продолжить без LLM. Альтернативы отвергнуты по конкретным причинам ниже.

### Positive Consequences

* Pipeline не модифицируется ни в одной точке — `/feature`, `/plan`, `/implement` и все агенты остаются single-issue по контракту, что соответствует Принципу 2 и не создаёт регрессии в существующем потоке
* GitHub как источник истины сохранён — прогресс sweep'а читается через `gh` без `sprint.sh` и без локального state-файла; Принцип 7 удовлетворён
* Per-ticket изоляция получается даром: каждая сессия `claude -p` начинается с чистого context window — context bleed между тикетами невозможен по конструкции
* Оператор может проинспектировать любой тикет mid-sweep чтением GitHub — никакого опаквого session state, никаких «надо дождаться окончания, чтобы посмотреть прогресс»

### Negative Consequences

* Локальный `.sprint-state` файл нужен для restart-recovery — это не GitHub-артефакт, потенциальный источник дрейфа между локальным кэшем и канонической GitHub-картиной
* Зависимость от формата JSON-вывода Claude Code CLI — если Anthropic меняет shape stream'а, `sprint.sh` ломается; парсинг — известная точка хрупкости
* Каждый тикет спавнит полную Claude Code сессию — cold-start overhead на каждый тикет (token cost, latency на загрузку CLAUDE.md, повторное чтение контекста); 10 тикетов = 10 cold-start'ов
* GitHub-side audit trail отсутствует — какие именно тикеты обработаны в данном sweep'е известно только локальному `.sprint-state`; если машина умирает mid-sweep до commit'а promotion-маркеров, история sweep'а теряется
* Retirement cost минимален: удалить `bootstrap/scripts/sprint.sh`, удалить `.sprint-state`, вернуться к ручному запуску `/feature <issue>` — нет schema migration, нет GitHub state-cleanup, нет модификации pipeline

## Pros and Cons of the Options

### Вариант A — Headless-step-per-call

* Good, because стадии тривиально параллелизуемы между тикетами — можно гонять `plan` для тикета 1 одновременно с `implement` для тикета 2
* Good, because failure scope сужается до одной стадии, не до одного тикета — fail в `qa` не теряет работу `plan` и `implement`
* Bad, because state приходится реконструировать между вызовами — каждый `claude -p` стартует с пустым контекстом, а pipeline-стадии накапливают контекст внутри сессии (plan читается implement'ом, qa-report читается review'ем); реконструкция = дублирование логики `/feature` снаружи
* Bad, because context window continuity теряется — `/feature` рассчитан на single-session orchestration; разрезание на стадии = переписывание контракта skill'а
* Bad, because `/feature` не задокументирован как stage-resumable — нет API «выполни шаг 4 при условии что шаги 1-3 уже выполнены»; для headless-step-per-call этот API пришлось бы изобретать

### Вариант B — `/sprint` slash-команда в одной живой сессии

* Good, because нет нового артефакта снаружи Claude Code — single entry point, оператор не учит ещё один tool
* Good, because оператор визуально остаётся в loop'е — видит прогресс в той же сессии, в которой запустил
* Bad, because у одной живой сессии фиксированный context window — после нескольких тикетов окно заполняется и качество следующих решений деградирует, что напрямую нарушает driver «per-ticket isolation»
* Bad, because контекст тикета N протекает в тикет N+1 — это не баг, это свойство single-session работы; нет способа «забыть» тикет, не убив сессию
* Bad, because оператор не может вмешаться между тикетами без прерывания всей сессии — нет естественной точки checkpoint'а

### Вариант C — Orchestrator внутри `/feature`

* Good, because нет новой command surface — `/feature` уже знают и оператор, и документация
* Good, because нет нового артефакта (`sprint.sh`) для maintenance'а
* Bad, because нарушает Принцип 2 — skill превращается из критика-оркестратора в executor'а, который сам решает, какие тикеты брать
* Bad, because `/feature` сконтрактован как single-issue orchestrator — multi-issue режим меняет его контракт, что нарушает обратную совместимость для всех существующих сценариев вызова
* Bad, because internal-loop в LLM-сессии воспроизводит ту же проблему, что Вариант B — context bleed между итерациями неизбежен, потому что они в одном context window

### Вариант D — Внешний bash-процесс `bootstrap/scripts/sprint.sh` (выбран)

* Good, because pipeline неизменён — одно место добавления (`bootstrap/scripts/sprint.sh`), zero touchpoints в `/feature` и стадиях
* Good, because per-ticket isolation бесплатна — каждый `claude -p` это отдельный процесс с чистым контекстом
* Good, because пост-верификация детерминирована — bash + `gh` API + `git` без единого LLM-токена; Принцип 3 удовлетворён
* Good, because GitHub-readable — оператор открывает Projects board или `gh issue list` и видит реальное состояние без `sprint.sh`
* Bad, because `.sprint-state` нужен для restart-recovery и существует только локально — рассинхронизация с GitHub возможна
* Bad, because зависимость от формата `claude -p --output-format stream-json` — если Anthropic меняет схему, `sprint.sh` ломается тихо (нет валидации schema)
* Bad, because cold-start overhead на каждый тикет — N тикетов = N полных загрузок CLAUDE.md/AGENTS.md/MCP

## Confirmation

Перед мерджем имплементации `sprint.sh`: dry-run против fixture sprint'а из 3 тикетов с заранее известными terminal-состояниями (один merged, один escalated, один failed). После прогона `sprint.sh --dry-run` пост-верификация должна совпасть с ожиданиями: для merged — закрытый PR с `Closes #N` в main; для escalated — issue с label `needs-human` и комментарием с reason; для failed — запись в `.sprint-state` с `state: failed` и текстом ошибки. Несовпадение хотя бы на одном тикете блокирует merge `sprint.sh` в main. Fixture хранится в `bootstrap/tests/fixtures/sprint-orchestrator/`.

## Re-visit Trigger

Пересматривать решение когда выполнено хотя бы одно: (а) все Phase-0 conditions из эпика #44 закрыты И первый real sweep escalates более 30% тикетов в `needs-human` — это значит, что либо pipeline не справляется автономно, либо граница escalation выбрана не там, и контракт sprint orchestrator'а нужно перепроектировать; (б) формат JSON-вывода `claude -p` меняется (новые поля, удалённые поля, иной shape stream'а) — это инвалидирует парсинг в `sprint.sh` и требует либо переписывания парсера, либо смены подхода (например, на event-bus вместо stdout-парсинга). Порог 30% — двух-трёх кратный запас от ожидаемого baseline'а 5-10% (Принцип 8).

## Links

* Closes #221
* Blocks: design doc issue #230 (`docs/architecture/sprint-orchestrator.md`, forthcoming)
* Related: `docs/runbooks/feature-pipeline.md`
* Related: `docs/architecture/sprint-orchestrator.md` (forthcoming, see #230)
* Related: Epic #44 (Autonomous Backlog Sweep — Phase-0 conditions must be met before `sprint.sh` implementation)
* Related: #80 (per-ticket git worktree isolation — Phase-0 condition)
* Related: #81 (verify script side-effects — Phase-0 condition)
* Related: `docs/principles.md` (Principles 2, 3, 7, 8, 9)
