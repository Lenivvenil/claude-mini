# 0028. Pin MCP server versions, enforce stdio-by-default, and restrict external-HTTP to an allowlist

* Status: accepted (2026-06-10)
* Superseded-by: ~
* Date: 2026-05-06
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: security, mcp, supply-chain, tooling, transport
* Related issue: #137

## Context and Problem Statement

`.mcp.json` (project-scope MCP config в корне репо) уже подключает три
сервера: `serena` (stdio), `github` (HTTP к GitHub Copilot MCP API),
`context7` (HTTP к `mcp.context7.com`, планируется миграция на stdio
`@upstash/context7-mcp`). Каждый из них — внешний код, исполняющийся в
контексте Claude Code или ходящий по сети с операторскими credentials.
До настоящего момента политики версионирования и transport-выбора
зафиксированы не были: версии серверов могли плыть, локальные HTTP-
бинды теоретически разрешены, и не было критерия «какой external HTTP
endpoint считается доверенным».

Триггеры именно сейчас — два публичных инцидента: **CVE-2026-27825
(MCPwnfluence, CVSS 9.1, февраль 2026)** — supply-chain через
скомпрометированный MCP-сервер, и **OX Security disclosure (апрель
2026)** — десять CVE в stdio-транспорте Anthropic MCP SDK, включая
local privilege escalation через unauthenticated HTTP-bind у server-
side компонентов. Без явной policy любая будущая выборка MCP-сервера
в этом проекте — implicit-trust by-omission.

Решение архитектурно значимо по
`docs/principles.md#что-значит-архитектурно-значимо`: одновременно
срабатывают **(1) external integration contract** — фиксируется список
доверенных HTTP MCP endpoints и схема их аутентификации; **(2)
production-bound infrastructure** — `.mcp.json` исполняется в
оркестраторе и hooks; нарушение transport policy ломает governance;
**(3) ограничение, трудно снимаемое back** — после того как
`mcp-config-lint` job начнёт блокировать CI, любое ослабление
allowlist-а должно проходить через ADR.

## Decision Drivers

* **Принцип 3 — детерминированный тулинг до агентов.** Версионирование
  и transport-allowlist — это lint-уровневая проверка (regex+jq), а не
  семантика. Должен быть механический gate, не "review reminders".
* **Принцип 8 — антихрупкость по домену, запас 2-3×, не 1000×.**
  Personal dev-tooling не оправдывает container-orchestration runtime
  (Docker/Podman+ToolHive) ради изоляции trusted-by-operator серверов.
  Threat model — supply-chain (pinned versions решают) и unintended
  network exposure (transport allowlist решает), не active malicious
  insider в собственном dev-loop.
* **Threat model phrased explicitly.** Атаки, которые мы реально
  митигируем: (a) supply-chain через unpinned `latest`-tag (resolver
  получает скомпрометированную версию завтра), (b) unintended network
  exposure локального MCP-сервера, который случайно слушает на
  `0.0.0.0:port` без auth, (c) molasses-drift HTTP-endpoint-ов, когда в
  `.mcp.json` накапливаются "временно подключённые" внешние сервисы
  без security-review.
* **Atak-surfaces, которые мы НЕ закрываем этим ADR.** Compromise
  самого Claude Code-процесса; выполнение произвольного кода через
  prompt-injection в результатах MCP-tool; кража токенов из
  `~/.claude/`; целевой supply-chain в pinned-tag (атакующий получает
  доступ к git-репо `oraios/serena` и переписывает существующий tag
  `v1.2.0`). Эти риски требуют либо containerization (out of scope per
  Принцип 8), либо otherwise unrelated controls.
* **Совместимость с существующими ADR.** ADR-0007 (read-only critics)
  и ADR-0020 (агрегаты `meta-pipeline`) ничего не говорят про MCP. Этот
  ADR не супер-седит ничего; он впервые формализует MCP-policy.

## Considered Options

* **Option A — Pin + stdio-default + allowlist + lint.** Все серверы в
  `.mcp.json` имеют pinned version (git-tag для `uvx --from
  git+https://...`, npm-version для `npx`). Transport: stdio для
  локально-исполняемых серверов; HTTP — только для эндпоинтов из
  явного allowlist (`api.githubcopilot.com/mcp/`). Никаких
  unauthenticated local HTTP MCP. Mechanical enforcement —
  `bootstrap/scripts/check-mcp-config.sh`, прокинутый в CI как
  `mcp-config-lint`. Quarterly CVE review через
  `docs/runbooks/mcp-quarterly-review.md`.
* **Option B — Pin + lint только; transport policy не зафиксирована.**
  То же, что A, но transport-allowlist отсутствует: stdio и HTTP
  разрешены оба, без разделения на trusted-external и local. Lint
  проверяет только pinned versions.
* **Option C — Stacklok ToolHive containerization.** Все MCP-серверы
  запускаются через `thv` (ToolHive CLI) в OCI-контейнерах с network-
  policy. Container runtime (Docker или Podman) обязателен на любой
  машине оператора. ToolHive выступает sandbox-prox-ом между Claude
  Code и MCP-серверами; pinned versions — побочный эффект OCI-image
  digest-ов.

## Decision Outcome

Chosen option: **Option A — Pin + stdio-default + external-HTTP
allowlist + mechanical lint, ToolHive evaluated-only.**

Three policies, each independently enforceable by `check-mcp-config.sh`:

1. **Version pinning (mandatory).** Каждый MCP-сервер в `.mcp.json`
   обязан иметь explicit version specifier:
   * stdio через `uvx --from git+...@<tag>` — `@<tag>` обязателен;
   * stdio через `npx <package>@<version>` — `@<version>` обязателен,
     `latest`/`*` запрещены;
   * HTTP — pin версии не применим, но endpoint URL обязан быть в
     allowlist (см. policy 2).
2. **Transport allowlist.** stdio разрешён без дополнительного
   обоснования; HTTP — только для endpoints из явного allowlist.
   Текущий allowlist (фиксируется в `check-mcp-config.sh` constants и
   дублируется в `docs/runbooks/mcp-quarterly-review.md`):
   * `https://api.githubcopilot.com/mcp/` — GitHub Copilot MCP API,
     Bearer-токен в env.
   Allowlist расширяется только через отдельный ADR (или amendment к
   этому), фиксирующий новый external endpoint и обоснование trust.
3. **No unauthenticated local HTTP MCP.** Серверы, биндящиеся на
   `localhost`/`127.0.0.1`/`0.0.0.0` без Bearer/API-key auth, в
   `.mcp.json` запрещены. Местечковый MCP-сервер должен использовать
   stdio (lifecycle привязан к Claude Code-процессу, нет открытого
   порта, нет authentication-burden). Это закрывает атаку OX Security
   disclosure (апрель 2026): локальный HTTP-bind без auth позволял
   соседнему процессу на той же машине вызывать MCP-tools чужого
   агента.

ToolHive (Option C) — **evaluated, not adopted.** Stacklok ToolHive
действительно решает большую threat-surface (network policy, image-
digest pinning, process isolation), но требует Docker/Podman runtime
на каждой машине оператора и добавляет два уровня cognitive overhead
(`thv proxy add`, container debugging) ради threat-mitigations,
которые в personal dev-loop не активируются. Принцип 8 явно про этот
случай: запас 2-3× оправдан, запас 1000× — нет. Containerization
переоткрывается в Re-visit Trigger (см. ниже), если threat model
поменяется.

**Важная точность по Context7:** после миграции на stdio
(`@upstash/context7-mcp@2.2.4`) Context7 **не перестаёт ходить во
внешний backend.** Stdio — это transport между Claude Code и локальным
npm-процессом; этот процесс затем выполняет HTTPS-запросы в
`mcp.context7.com`. Security-аргумент для перехода на stdio — про
канал **Claude↔локальный процесс** (закрываем unauthenticated
local-HTTP вектор, lifecycle привязан к Claude Code-процессу), а
**не** про изоляцию от Upstash. Формулировки в runbook и README
обязаны это явно отражать.

### Quarterly CVE review

Каждый Q (январь, апрель, июль, октябрь) — runbook
`docs/runbooks/mcp-quarterly-review.md`. Проверки:
* GitHub advisory database по каждому pinned MCP-server.
* CVE-search по `mcp` + название transport library (Anthropic MCP SDK,
  fastmcp).
* Последний релиз pinned-tag (если pinned сильно отстал, оценить
  upgrade-cost).
* Состояние allowlist endpoint-ов (доступность, schema-changes,
  смена auth-механизма).
Output runbook-а — одна из трёх записей в session-log: "no findings",
"upgrade pin to <x>", "ADR-trigger: re-evaluate transport policy".

### Positive Consequences

* **Supply-chain via unpinned `latest` закрыт mechanically.** CI
  блокирует merge `.mcp.json` без version specifier; resolver не
  получит compromised tomorrow's version незаметно.
* **Local-HTTP-bind exposure закрыт mechanically.** OX Security-class
  атак не воспроизвести в этом репо без явного нарушения lint-а.
* **External-HTTP entropy ограничена.** Любой новый external endpoint
  требует ADR-amendment, а не "временно дописал в `.mcp.json`".
* **Threat model явно записана.** Что закрываем (supply-chain via pin,
  local-HTTP exposure, drift), что НЕ закрываем (compromise Claude
  Code, prompt-injection из tool-output, целевой attack на pinned-
  tag). Будущий читатель не вынужден реверсить мотивацию.
* **Quarterly cadence — explicit маркер staleness.** Если runbook не
  выполнен два квартала подряд, ADR-staleness-audit видит это сам.
* **Принцип 3 удовлетворён.** Policies механически проверяются,
  агенты задействованы только для семантического review (`security-
  reviewer` смотрит при изменениях `.mcp.json` через prod-bound
  classification).

### Negative Consequences

* **Allowlist становится bottleneck.** Любой новый external HTTP MCP-
  сервер блокируется до ADR-amendment. Это by-design (entropy guard),
  но создаёт frictioned путь для legit useful MCP-сервисов.
* **Quarterly review требует дисциплины.** Если оператор пропускает Q,
  allowlist дрейфит mentally («да это вроде безопасно»), а pinned-
  tag-и накапливают известные CVE без upgrade. Mechanical gate
  отсутствует — это пока honor-only check. Механизация (cron-issue
  или dashboard-alert) оформляется отдельным follow-up тикетом после
  закрытия #137.
* **stdio через uvx/npx не изолирует процесс от FS и сети.** Pinned
  version защищает от supply-chain-через-tag, но **не** от malicious-
  in-tag (атакующий получил коммит-доступ и переписал содержимое
  pinned tag без смены имени; уровень атаки выше threat model, но
  технически воспроизводим). Containerization (Option C) закрыл бы;
  мы сознательно не закрываем.
* **Pinning Context7 на конкретную npm-версию делает upgrade-policy
  обязанностью оператора.** Каждые 1-3 месяца проверяй semver-bump на
  bug-fixes; без quarterly review сервер копит security-patches
  невидимо.
* **`mcp-config-lint` CI-job — новая failure-поверхность.** Если в job
  будет regex-bug, false-positive заблокирует валидный merge. Lint
  должен покрываться unit-тестом (`tests/check-mcp-config.bats` или
  аналог) — это требование к `/implement`.
* **Allowlist дублируется в двух местах** (`check-mcp-config.sh`
  constants и runbook). Drift между ними возможен; runbook должен
  быть указан как documentation-only mirror, source-of-truth — script.
  Это явный seam.
* **ToolHive остаётся опцией, не активным контролем.** Если завтра
  публикуется новая MCP-vulnerability класса «stdio process escape»,
  Option A не защитит, и придётся срочно переоткрывать решение в
  пользу Option C под давлением incident-а вместо плановой миграции.

## Pros and Cons of the Options

### Option A — Pin + stdio-default + allowlist + lint

* Good, потому что три policy-слоя независимы и каждый закрывает свой
  класс атак (supply-chain via pin, local-HTTP exposure, external-
  HTTP entropy).
* Good, потому что enforcement — детерминистичный bash-script с
  `jq`+regex, без LLM, по Принципу 3.
* Good, потому что не требует дополнительного runtime (Docker/Podman) —
  работает на любой машине оператора без подготовки.
* Good, потому что allowlist можно расширять через amendment-ADR — это
  governance-friendly путь, а не "сегодня тихо добавил, завтра
  забыл".
* Good, потому что Context7-stdio миграция вписывается без отдельной
  policy: после flip stdio становится default, HTTP-route закрывается.
* Bad, потому что не закрывает malicious-in-pinned-tag (атакующий
  переписывает содержимое тэга `v1.2.0`); требуется trust в
  upstream-репо `oraios/serena` и `upstash/context7-mcp`.
* Bad, потому что quarterly review остаётся honor-only — нет
  механического gate, что runbook исполнен.
* Bad, потому что allowlist дублируется в script и runbook, что
  создаёт drift-риск.
* Bad, потому что новый legit-useful external MCP-сервис требует
  amendment-ADR — frictioned, не fast-path.

### Option B — Pin only, transport free

* Good, потому что меньше friction для добавления новых MCP-серверов;
  оператор просто pin-ит версию и работает.
* Good, потому что lint проще — единственная проверка (regex на
  `@<version>`).
* Bad, потому что не закрывает OX Security-class атак (local-HTTP-
  bind без auth остаётся легальным в `.mcp.json`).
* Bad, потому что external-HTTP entropy неограничена: завтра
  оператор подключит `https://random-mcp-of-the-week.example/` без
  governance-step.
* Bad, потому что threat model размыт: «защищаем от supply-chain» без
  упоминания network exposure — false sense of completeness.
* Bad, потому что Принцип 1: "оба варианта transport хороши" — это
  размытость, а не решение.

### Option C — Stacklok ToolHive containerization

* Good, потому что network policy на уровне OCI-контейнера закрывает
  unauthenticated local-HTTP-bind by-construction (контейнер не
  слушает host-network).
* Good, потому что image-digest pinning (`@sha256:...`) — более
  строгая форма pin, чем git-tag (защищает от malicious-in-tag).
* Good, потому что process isolation: compromised MCP-server не имеет
  прямого доступа к FS оператора и `~/.claude/` без явного volume-
  mount.
* Bad, потому что требует Docker/Podman runtime на каждой машине;
  Mac Mini 32 GB — допустимо, но лишний слой обслуживания (auto-
  start daemon, обновления, debugging container-network-issues).
* Bad, потому что cognitive overhead `thv proxy add`, OCI-image-
  publishing, debugging внутри контейнера, log-aggregation поверх
  container-stdout — всё это Принцип 8 запас 1000× для personal
  dev-tool.
* Bad, потому что ToolHive — early-stage проект (Stacklok, 2025).
  Принимать на себя cost его apk-evolution прямо сейчас — entropy.
* Bad, потому что не все MCP-сервера имеют OCI-images у upstream;
  для Serena (uvx-based) и Context7 (npm-based) пришлось бы строить
  собственные images, что добавляет supply-chain поверх supply-chain.

## Confirmation

После принятия этого ADR и реализации в `/implement`:

1. **`bootstrap/scripts/check-mcp-config.sh` существует**, использует
   `jq` для парсинга `.mcp.json`, проверяет:
   * каждый stdio-server имеет `@<tag>` или `@<version>` (regex,
     non-empty, не `latest`, не `*`);
   * каждый HTTP-server имеет URL из allowlist-constant;
   * нет server-ов с `command` биндящим на `localhost:port` без
     `Authorization` env-var.
   Exit-code 0 — pass; non-zero — fail с указанием server-name и
   нарушенной policy.
2. **CI-job `mcp-config-lint` существует** в `.github/workflows/`,
   запускает `check-mcp-config.sh` на push/PR. PR-checks показывают
   статус явно.
3. **Unit-тест для `check-mcp-config.sh` существует** (минимум:
   bats или python script с фикстурами `.mcp.json`-вариантов: valid
   pin, missing pin, latest-tag, unallowed-HTTP-host, local-HTTP-
   without-auth). Покрывает каждое exit-condition.
4. **`docs/runbooks/mcp-quarterly-review.md` существует**, описывает
   четырёхшаговый чек (advisory DB, CVE-search, pin-staleness,
   allowlist-status) и формат записи в session-log.
5. **`.mcp.json` приведён в соответствие**: все три текущих сервера
   (`serena`, `github`, `context7`) проходят lint. Context7-миграция
   на stdio (`npx @upstash/context7-mcp@2.2.4`) выполнена в этом же
   PR (или в parallel PR, ссылающемся на этот ADR через
   `Implements docs/decisions/0028-mcp-transport-security.md`).
6. **README обновлён**: секция «MCP Servers» документирует policy
   (pinned, stdio-default, external-HTTP allowlist), ссылается на
   этот ADR и на runbook.
7. **AGENTS.md / CLAUDE.md обновлены**: `MCP-серверы`-секция содержит
   ссылку на этот ADR и на `check-mcp-config.sh`. Допустимо
   расширение текущей таблицы серверов колонкой "transport" (stdio /
   HTTP-allowlisted).
8. **Allowlist single-sourced.** В runbook явно сказано: "source of
   truth — `bootstrap/scripts/check-mcp-config.sh` const
   `ALLOWED_HTTP_HOSTS` (или аналог); этот раздел — mirror, при
   расхождении источник script". Drift автоматически невидим, но
   надо хотя бы декларировать направление truth.
9. **Стейтмент про Context7 stdio + Upstash backend** присутствует в
   runbook и (опционально) в README: "stdio закрывает Claude↔local
   process; запросы в Upstash остаются HTTPS, изоляция от Upstash не
   является целью."
10. **Issue #137 закрыт** через `Closes #137` в коммите финального
    PR; PR description ссылается на ADR через
    `Implements docs/decisions/0028-mcp-transport-security.md`.

## Re-visit Trigger

Re-open this decision when **any one** is true:

* **Публикуется CVE на класс stdio process-escape в MCP SDK.** Если
  атака класса "compromised stdio MCP-server вырывается из process-
  boundary через ptrace/fd-passing/etc" — pinning не помогает,
  containerization становится оправданной. Перевзвесить Option C.
* **Allowlist перерос разумные пределы.** Если в allowlist накопилось
  четыре или более external HTTP endpoint-ов (текущий: один,
  GitHub Copilot), entropy управления возрастает. Следующий ADR
  пере-смотрит: трактовать каждый endpoint как отдельный supplier с
  своим threat model, или ввести категорию «trusted vendor list».
* **ToolHive (или эквивалент) добавляет первоклассную поддержку uvx/
  npm как `command`.** Сейчас контейнеризация Serena/Context7
  требует self-built OCI-images. Если ToolHive перейдёт от OCI-image-
  pinning к command-based с встроенным sandbox — Option C перестаёт
  стоить 1000×, нужна перепроверка.
* **Quarterly review пропущен два Q подряд.** Если оператор
  фактически не выполняет runbook два квартала, honor-only механика
  не работает; нужен mechanical gate (cron-issue, dashboard-alert)
  или признание, что review не нужен.
* **Появляется второй MCP-сервер вне allowlist в реальной
  потребности.** Если за 6 месяцев в `.mcp.json` потребовалось
  добавить более одного нового external endpoint, и каждый требовал
  amendment-ADR, friction становится сигналом. Следующий ADR
  пересматривает governance-уровень для allowlist (PR-review с label
  `mcp-allowlist`? отдельный less-formal artifact?).
* **Anthropic / GitHub меняют MCP transport API.** Если SDK
  публикует новый transport (например, gRPC over UNIX socket с mTLS),
  policy «stdio vs HTTP» становится недостаточной. Следующий ADR
  пере-моделирует transport allowlist под новый набор опций.
* **Threat model меняется.** Если Mac Mini становится shared dev
  environment (другие пользователи на той же машине), или Claude
  Code начинает запускаться в CI-runner с менее доверенным окружением,
  или появляется требование SOC2/ISO compliance — Принцип 8 запас
  пере-вычисляется, и Option C может стать оправданным.

## Links

* GitHub issue #137 — MCP Transport Security problem statement и
  acceptance criteria.
* `docs/runbooks/mcp-quarterly-review.md` — quarterly CVE-review
  runbook, создаётся в `/implement`.
* `bootstrap/scripts/check-mcp-config.sh` — mechanical lint, source
  of truth для allowlist; создаётся в `/implement`.
* `.mcp.json` (project-scope MCP config в корне репо) — артефакт,
  который lint валидирует; место `--scope project` пишет конфиг по
  Claude Code changelog.
* `docs/principles.md#3-сначала-детерминированный-тулинг` —
  основание выбора lint-script вместо agent-проверки.
* `docs/principles.md#8-антихрупкость-по-домену-запас-2-3-не-1000` —
  основание отказа от Option C (ToolHive containerization).
* `docs/principles.md#1-размытость--нарушение` — основание отказа
  от Option B (transport policy «оба разрешены» без обоснования).
* `docs/principles.md#что-значит-архитектурно-значимо` — три
  триггера архитектурной значимости, активные здесь.
* CVE-2026-27825 (MCPwnfluence, CVSS 9.1, февраль 2026) — supply-
  chain через скомпрометированный MCP-сервер, прямая мотивация
  policy 1 (pinned versions).
* OX Security disclosure (апрель 2026) — десять CVE в Anthropic MCP
  SDK stdio transport, включая unauthenticated local HTTP-bind;
  прямая мотивация policy 3 (no unauthenticated local HTTP MCP).
* Stacklok ToolHive (`thv`) — оцениваемая containerization-
  альтернатива; не принята по Принципу 8. См. Re-visit Trigger.
* `docs/decisions/adr-template.md` — формат MADR 4.0.
