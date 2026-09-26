# SYNTHESIS-2026-04-29 — claude-mini после девяти принципов

## Раздел A — Глубокий свод

### 1. Что меняется в конструкции цикла после интервью

Девять принципов в их финальной редакции — это не косметика поверх существующего пайплайна. Принципы 7, 8, 9 (агностичность вендора, антихрупкость по домену, перехват-контракт) плюс явное признание двух больных мест — **lazy-by-default моделей** и **domain inversion** — переопределяют несущую нагрузку конструкции. Старый каркас держал три аггрегата (FeatureRun, GovernanceRun, TwoVoiceReview), 10 слэш-команд, 8 read-only критиков и pre-commit-governance hook. После интервью каркас не выдержит ещё двух месяцев без перестройки в шести местах.

**`/review` skill** перестаёт быть единым артефактом и расщепляется на детерминистический слой и LLM-критика с явным lazy-mandate. Детерминистический слой — это ruff/eslint/staticcheck для кода (что линтер ловит — линтер и должен ловить, принцип 3), radon/lizard для сложности (CC ≤ 10, MI > 65), jscpd в strict-mode (`min-tokens: 50`, `min-lines: 5`) для копипасты из соседних диф-ханков, semgrep-правила для TODO без ticket-ref и для пятиподряд-комментированных блоков. Это база, ниже которой LLM не пускается. LLM-слой получает adversarial-mandate — explicit instruction искать narrow special-cases, симптом-фиксы, дублирование, копипасту, обрезанные/пустые файлы (последнее — задокументированный режим лени Claude Code per Brooks McMillin). Без явного мандата LLM-критик скатывается в agreeableness — TPR 96%, TNR <25% (arxiv 2510.11822). Один LLM-критик статистически непригоден; нужна асимметричная схема: minority-veto для двухголосого review (Claude + Codex), не majority vote. Один критик блокирует — блок принимается. Согласие двух — слабый сигнал; разногласие — сильный сигнал к ручному взгляду.

**`/qa` skill** обогащается property-based тестированием на Hypothesis с шаблонами round-trip / metamorphic / invariant / idempotence. Шаблоны выбраны не от моды: arxiv 2510.09907 (Anthropic, NeurIPS DL4C 2025) показал 32% maintainer-reportable bugs из 100 Python пакетов на Opus 4.1 именно через эти шаблоны. Это и есть промышленный baseline: PBT — это не «дополнение к unit-тестам», это инструмент против over-fitting LLM на канонических примерах. `@example([])`, `@example([0])` — обязательные явные edge-cases, потому что Claude забывает их сам. Профили Hypothesis: `dev` (50 examples), `ci` (500), `nightly` (5000). Mutation testing (mutmut/Stryker/PIT/cargo-mutants) — НЕ per-PR, а weekly cron на main, целевой mutation score 80%, минимальный gate 60%. Per-PR mutation-testing — индустриальный антипаттерн, что подтверждают и Henry Coles (Pitest), и Google Practical Mutation Testing at Scale (arxiv 2102.11378), и nexocode case-report. Один прогон 20 минут локально — 40 минут в CI; weekly cron + `--in-diff` режим даёт сигнал без выжигания CO₂.

**Governance hook** расширяется с одного PreToolUse на четыре события. PreToolUse остаётся для блокировки опасных путей (.env, secrets), Conventional Commits, ADR-ref, issue-ref. Добавляется PostToolUse-matcher на `Edit|MultiEdit|Write` для запуска format+typecheck сразу после редактирования (prettier+tsc, ruff format+mypy) — ловим 80% мусора до того как он попадёт в commit. Stop-hook включает финальный gate «тесты должны проходить» — иначе session не закроется без явного `stop_hook_active`. SubagentStop — для очистки изоляции worktree. Это не бюрократия, это четыре гейта на четырёх событиях, каждый со своим audit-trail-полем. ROI каждого считается отдельно (см. раздел 7).

**Агенты — два изменения.** Первое: добавляется `adversarial-critic` агент с явным lazy-mandate в промпте (`tools: Read, Grep, Glob`, model haiku-или-sonnet в зависимости от глубины проверки, system prompt прямо называет lazy-режимы как enemy). Это не дублирование security-reviewer/reliability-reviewer — это агент, чья единственная задача найти, где модель схалявила. Второе: ретируются один-два критика, у которых /gate-audit покажет ROI < 0.2 четыре недели подряд. Скорее всего docs-reviewer или backlog-groomer — это honor-system артефакты, плохо работающие как агенты. Конкретный кандидат на ретирамент определяется первым же /gate-audit, но resource budget на 8 параллельных критиков для solo — это уже излишне; целевой коридор 5-6 активных критиков плюс adversarial-critic.

**DoD compliance table.** Из 14 норм 8 honor-system. Это бухгалтерия, не пайплайн. После интервью каждая honor-only норма должна получить либо механический enforcer (PreToolUse hook, PostToolUse hook, CI check, ADR-Kit policy block), либо явную пометку `honor-only — known gap` и тикет в P1/P2. Без этого compliance table будет лгать, и принцип 1 («размытость — нарушение») нарушен в самом ядре пайплайна.

**Domain layer.** Признать domain inversion. Текущий `docs/domain/` описывает пайплайн как domain — это методологически защитимо для self-bootstrapping проекта (Verraes, август 2025: домены и BC не маппятся 1-к-1; один домен может содержать несколько BC, BC может пересекать домены). Но pet-проекты (archi2likec4, news-digest) имеют свои домены, и единый `docs/domain/` затирает эту разницу. Решение: расщепить на два уровня. `docs/domain/meta/` — meta-tooling bounded context для самого пайплайна (FeatureRun, GovernanceRun, TwoVoiceReview). `docs/domain/<project>/` — per-project bounded context. Между ними — явный context map и Anti-Corruption Layer на стыке (Synpulse8 AACL pattern, 2025-2026 — пятилетней давности классический ACL Эванса с дополнением для probabilistic LLM outputs).

### 2. Lazy-detection как первоклассная инженерная задача

Lazy-detection — это самая болезненная категория проблем по собственному признанию пользователя. Оператор ловит intra-session, но не накапливает. Industry в 2026 году отвечает на это четырьмя слоями.

**Слой 1 — детерминистические гейты.** ruff (Python), eslint+typescript-eslint (TS/JS), staticcheck+golangci-lint (Go), clippy (Rust). Это вход — не до этого слоя LLM-критик не имеет права срабатывать вообще. radon с порогом CC ≤ 10 (rank A или B по radon-grading, fail на C+), MI > 65. lizard кросс-язык: `lizard -C 10 -L 100 -a 5`. jscpd с `mode: strict, min-tokens: 50, min-lines: 5` именно для случая «копипаста из соседнего диф-ханка». jscpd теперь поставляет Agent Skill для Claude/Cursor/Copilot — то есть LLM сам учится не дублировать, имея на руках свой же отчёт jscpd. Это первый шаг к «знание живёт в репо» (принцип 4) применительно к anti-patterns.

**Слой 2 — property-based testing.** Hypothesis для Python — де-факто стандарт; fast-check для TS/JS. Шаблоны — round-trip, metamorphic, invariant, idempotence — это анти-laziness конструкции, потому что они валят тесты, написанные «по примеру». arxiv 2510.09907 даёт точную формулу шестишагового prompt'а для агента, генерирующего PBT: analyze → understand → propose properties → write tests → execute → triage. Этот промпт встраивается в `/qa` skill один-в-один и сразу даёт документированный 32%-success-rate на реальных багах. Конкретный config — `conftest.py` с тремя профилями (dev/ci/nightly) и явными `@example([])`, `@example([0])` на критичных функциях.

**Слой 3 — mutation testing.** Не per-PR. Weekly cron на main. mutmut v3+ для Python (с mypy-фильтром невалидных мутантов), Stryker для JS/TS (порог `break: 50, low: 60, high: 80` — индустриальный consensus), cargo-mutants v27 (с `--in-diff` для инкрементального режима), PIT для Java (с `withHistory`). Цель — 80% mutation score; минимум 60%. Mutation testing ловит специфическую LLM-лень — тесты, которые повторяют training-data tutorial-pattern и не проверяют behaviour (arxiv 2503.08182). Включается через GitHub Actions workflow `mutation.yml` с `cron: '0 0 * * 0'`.

**Слой 4 — adversarial LLM-critic с lazy-mandate.** Не общий код-ревью; узкоспециализированный агент, в system-prompt которого явно перечислены классы лени: дубликат, симптом-фикс, узкий частный случай, копипаста из соседнего ханка, обрезанные/пустые файлы, hardcoded magic constants без обоснования, TODO без ticket-ref, commented-out code в коммите. Anthropic Code Review (запущен апрель 2026, multi-agent parallel-then-verify) — публичный референс: 84% PR > 1000 строк имеют баги, среднее 7.5 issues/PR, FP < 1%. На solo это переваривается локальным adversarial-critic'ом с моделью haiku или sonnet и read-only tools (`Read, Grep, Glob`).

**Накопление — `docs/anti-patterns.md`.** Самое важное и самое отсутствующее. Прецедент существует: Arcanum-Sec/sec-context (Jason Haddix, 2026) поддерживает ANTI_PATTERNS_BREADTH.md (25+ паттернов) и ANTI_PATTERNS_DEPTH.md (top-7 critical), синтезированных из 150+ источников и ранжированных Frequency×2 + Severity×2 + Detectability. Файл explicitly предназначен для system-prompt injection или reference-load в LLM-критика. honnibal/claude-skills (Matthew Honnibal, spaCy) делает то же на уровне per-skill checklists. Brooks McMillin's CLAUDE.md template имеет секцию "Anti-patterns" как стандартный раздел. Это и есть operationalisation принципа 4 («знание живёт в репо»): каждый раз, когда оператор ловит лень в сессии — добавление в anti-patterns.md в течение того же commit'а. Нет добавления — gap не закрылся, потому что в следующей сессии контекст потерян.

**Bias в two-voice review.** arxiv 2510.11822 показал, что LLM-judge имеет TPR 96% и TNR <25% — то есть он одобряет почти всё, в том числе плохое. Majority voting — слабая защита. Авторы предлагают minority-veto и regression-based bias correction с маленьким (~30-100) human-annotated calibration set. Practical implication: текущая схема `/review + /codex-review → graceful degradation` должна перейти на minority-veto (любой из двух блокирует — блок), а не на consensus-or-defer. Лучше FP в block, чем FN-пропуск. Position bias — также реальный (Lin Shi et al., IJCNLP 2025): порядок предъявления влияет на judgment; нужен swap-and-rejudge на критических тикетах. Третий голос на open-weight (DeepSeek V4 / Qwen3-Coder-Next / Kimi K2.6) даёт пол при degradation Codex; cross-family мандатна, потому что intra-family panels усиливают bias, не гасят.

### 3. Domain inversion — методология

Текущая архитектура моделирует пайплайн как домен. Это самозагрузочный (self-bootstrapping) проект, поэтому defensible: пока пайплайн — единственный артефакт, домен пайплайна = domain layer. Но как только pet-проекты (archi2likec4, news-digest) проходят через пайплайн с собственными доменами (C4-architecture, news-aggregation), возникает inversion: meta-domain (tooling) vs target-domain (продукт).

Verraes (август 2025, «No, Your Domains and Bounded Contexts Don't Map 1 on 1») явно дезавуирует допущение «один домен = один BC». Несколько BC на домен — нормально и часто желательно. Один BC поверх нескольких доменов — тоже. Это и есть лицензия на конструкцию: meta-tooling BC рядом с product BC, на стыке — context map с явным переводчиком.

Eric Evans, DDD Europe 2025 keynote («My AI Learning Journey»), развивает тезис из Explore DDD 2024: **обученная языковая модель — это bounded context**. Системы должны строиться из множества fine-tuned узких LLM, не из одной general-purpose. Применительно к claude-mini это значит: каждый из 8 read-only критиков — это собственный BC в смысле языка и фокуса (security-reviewer говорит на CVE/CWE/STRIDE, domain-reviewer говорит на ubiquitous language pet-проекта). Anti-Corruption Layer между ними — это AACL Synpulse8 (2025-2026), формальный паттерн нормализации probabilistic LLM-выходов в structured correction signals для детерминистических потребителей.

Конкретный план разделения:
- `docs/domain/meta/` — пайплайн (FeatureRun, GovernanceRun, TwoVoiceReview, RunbookExecution).
- `docs/domain/<project>/` — per-project: archi2likec4 имеет домены C4-Diagram, ContainerLayer, RelationshipGraph; news-digest имеет Source, Article, Digest, DeliveryWindow.
- `docs/domain/context-map.md` — Mermaid-диаграмма с явными ACL-стрелками между meta и target.
- ACL имплементация — один python модуль в meta-tooling, валидирующий входящие artifacts из pet-проекта против meta-pipeline schema.

Tony Marston и HN-критика DDD на CRUD-приложениях — здоровый напоминатель: DDD не платит, если pet-проект — простая CRUD. archi2likec4 — domain-rich (граф, связи, layout); news-digest — borderline. Применять DDD к news-digest на solo масштабе — overhead. Принцип 8 («2-3×, не 1000×») здесь срабатывает: meta-domain полная, per-project — только если домен реально rich.

### 4. Vendor-lock как несущая балка

Принцип 7 переписывает архитектуру в трёх местах одновременно.

**`forge.sh` wrapper.** Реальность: широко принятого `forge.sh` shell-wrapper в индустрии нет. Ближайший прецедент — Leleat/git-forge (Rust CLI, абстрагирует issues/PR поверх GitHub/GitLab/Gitea/Forgejo). Это greenfield. Дизайн `forge.sh` для claude-mini: тонкая обёртка над `gh`, которая принимает абстрактные команды (`forge issue create`, `forge pr open`, `forge release tag`) и под капотом вызывает `gh`/`glab`/`tea` в зависимости от `FORGE_PROVIDER` env-переменной. Test for vendor-agnosticism: миграция на Gitea за час — это и есть «test = git+text-editor+bash recovers everything». Не пытаться покрыть всю поверхность `gh` — только то, что фактически используется в `/task-to-issue`, `/issue-to-task`, `/feature`. Releases, projects, actions — out-of-scope первой версии.

**AGENTS.md / CLAUDE.md duality.** AGENTS.md теперь под Linux Foundation Agentic AI Foundation (декабрь 2025). Read-by: Codex CLI, Goose, opencode, Aider, Cursor, Devin, Jules. CLAUDE.md — Claude-Code-специфичный диалект. Шипить оба. AGENTS.md содержит generic instructions (структура репо, команды test/build/run, коммит-конвенции). CLAUDE.md делает import: `@AGENTS.md` плюс Claude-специфичные skills/agents/hooks. Один источник истины для общих правил, два формата для двух потребителей. Migration: `mv CLAUDE.md AGENTS.md`, переписать CLAUDE.md как 5-строчный stub с импортом.

**MCP transport security.** CVE-2026-27825 (MCPwnfluence, sooperset/mcp-atlassian, CVSS 9.1, февраль 2026) — это реальный unauthenticated RCE через `confluence_download_attachment` без directory confinement, плюс SSRF через unvalidated header. Цепочка фиксится в v0.17.0. Plus systemic finding (OX Security, апрель 2026): 10 CVE в Anthropic MCP SDK stdio transport через Python/TS/Java/Rust SDK — 7000+ публично доступных серверов, 150M+ загрузок. Anthropic отказался менять протокол, назвав поведение «expected default». Plus конкретные: CVE-2025-49596 (MCP Inspector RCE), CVE-2025-6514 (mcp-remote command injection, CVSS 9.6), CVE-2025-53109/53110 (Filesystem MCP path bypass), CVE-2025-68143/68144/68145 (mcp-server-git path validation). Plus Cursor CVE-2025-54136 — «rug-pull» класс: клиент approve один раз, сервер тихо обновляет tool description — stored prompt injection. Plus Flowise CVE-2025-59528 (CVSS 10.0, exploited ITW апрель 2026).

Вывод для банковского контекста: MCP — больше НЕ low-risk slot в vendor-lock матрице. Перевод в medium-risk. Конкретная гигиена: stdio для local (Serena, Context7 локально установленный), pinned versions, никогда не bind на 0.0.0.0, allowlist доменов в HTTP-режиме, restrict outbound на MCP-процессах (Stacklok ToolHive — off-the-shelf для этого). Любой community MCP — untrusted code.

**Runtime alternatives.** Goose CLI (теперь aaif-goose под Linux Foundation, ~28K stars, Apache 2.0, Rust, 15-25+ providers, ACP-server и ACP-client одновременно). Codex CLI (OpenAI, GPT-5.4 default, 3M+ weekly devs, isolated cloud sandbox network-disabled, hierarchical AGENTS.md). Aider (~39K stars, model-agnostic, git-native CONVENTIONS.md). opencode (sst, ~147K stars, 75+ providers, AGENTS.md native, offline через Ollama — самый растущий open альтернативный CLI). Open-weight для local: Kimi K2.6 (Tier-A в Akita benchmark, 89.3 coding score), Qwen3-Coder-Next-80B-A3B (февраль 2026), DeepSeek V4 Pro (апрель 2026). Vendor-monitor quarterly check: бенчмарки Akita/BenchLM, breaking changes Claude Code, новые ACP-агенты в registry. Migration ticket НЕ блокирующая; настоящая балка — это AGENTS.md duality и forge.sh, потому что они снимают migration-cost на момент когда balance перестанет работать.

### 5. Антихрупкость по домену — 7 -ilities при 2-3× margin

Каждая -ility получает minimum-viable-artifact и явный overengineering failure mode. Принцип 8 фиксирует: глубина scaling'а зависит от criticality домена. Pet-проект news-digest при отсутствии пользователей — minimum. archi2likec4 если будет внешним пользовательским tool — depth выше.

**Reliability.** SLO-lite: один `slo.md` с 1-2 SLI (availability + p95 latency на user-critical path), один error budget. Charity Majors / Honeycomb 2025: SLO из wide structured events дешевле и переслайсуемее, чем metric-derived. Overengineering: burn-rate alerts, multi-window/multi-burn pages, per-endpoint SLOs для проекта с 1 пользователем (с самим собой).

**Observability.** JSON-logger с trace_id/span_id. OpenTelemetry SDK auto-instrumentation в один backend. Observability-as-code: SLO-определения и alerts как YAML в репо. Overengineering: full Datadog three-pillars stack, отдельный metrics DB + log store + tracer (cardinality-cost trap по Charity).

**Recoverability.** runbook.md с copy-pasteable restore-командами. Weekly cron, восстанавливающий backup в scratch container и асерчающий row counts. RPO=24h, RTO=1h для pet-проектов — заявлено явно. Overengineering: multi-region replication, cross-cloud DR drills, PITR с 5-min RPO для данных, регенерируемых из публичных API.

**Security.** Dependabot включён, gitleaks pre-commit, GitHub native secret scanning, cosign keyless OIDC signing релизных артефактов, SLSA Level 2 provenance через actions/attest-build-provenance, pinned actions по SHA. После 2025 GhostAction supply-chain — это table-stakes. Overengineering: SLSA L3 hermetic builders, internal Fulcio/Rekor instance, Kyverno admission controllers для контейнера, который никто не пуллит.

**Maintainability.** Kent Beck «Tidy First?» (O'Reilly 2023): строгое разделение structural vs behavioural changes, никогда в одном коммите. Conventional Commits + prefix `[S]` или `[B]` в body. Coverage как proxy с известными ограничениями: ≥60% acceptable, ≥90% suspicious of test-tautology, mutation score доминирует над coverage. Overengineering: coverage gate 95%, branch+condition coverage, mutation per-PR.

**Operability.** `deploy.sh` (tag → build → sign → push), `rollback.sh` (re-deploy previous tag), feature flags как env vars или checked-in `flags.yaml` читаемый при boot. DORA 2024 confirms: high performers favour small batches + reversible deploys. Overengineering: per-user targeted rollouts, percentage rollouts, multi-variant experiments на solo масштабе.

**Auditability.** ADR refs в каждом коммите, `audit.log` JSONL для privileged actions (timestamp, actor=me, action, sha). ADR ↔ commit SHA ↔ issue chain. Overengineering: signed audit log с hash-chain Merkle proofs, immutable WORM storage, SOC 2 evidence collectors на 3 ADR.

**STPA-как-метод.** Nancy Leveson STPA Handbook (MIT PSASS, 2018) — generic фреймворк (Losses → Hazards → Control Structure → Unsafe Control Actions → Loss Scenarios). «STPA-light» как named publication не существует — это informal shorthand. Применение к solo pipeline: Losses = «leak secret to public repo», «irreversibly delete user data», «agent commits to main without review», «cost runaway from infinite agent loop». Hazards = «agent has push permission while constitution-check bypassed». UCAs = «agent provides `git push --force` on main», «agent does not provide test invocation before deploy». Один-разовый STPA pass на pipeline даёт hazard list, который маппится в hooks (PreToolUse denylist) и runbooks. Не повторять regularly; пересматривать при architecture change.

### 6. Continuity — STATE.md + session-log + plan.md

Принцип 9 — перехват — контракт. Audience: self-in-6-months или новый team-member 1-2h onboarding. Test: human может resume в 5 минут от любого LLM-stop без LLM.

**Steve Yegge's Beads** (~18K stars, v0.59.0 март 2026) — git-backed graph issue tracker для агентов, написан в Go, storage Dolt + append-only JSONL под `.beads/`. Hash-based ID (`bd-a3f2`), четыре типа dependency links (blocks, parent-child, related, discovered-from), `bd ready --json` для surfaced unblocked work. «Land the plane» ritual в конце сессии — copy-paste prompt для следующей сессии. Решает «50 First Dates problem»: агент просыпается без памяти. Agent-agnostic — работает с Claude Code, Codex, Cursor.

**Anthropic CLAUDE.md / MEMORY.md** — два механизма: human-authored persistent (CLAUDE.md) + auto-memory (MEMORY.md ≤200 lines / ~25 KB), Claude Code ≥v2.1.59 (февраль 2026). Index-pattern: одна строка на topic в MEMORY.md, детали в `references/<topic>.md`. «Auto Dream» four-phase consolidation prompt — date-canonicalisation, pruning contradicted facts (claudefa.st референс).

**Конкретный формат тройного hand-off:**

`STATE.md` — current session snapshot, ≤200 lines, обновляется в конце каждой сессии. Поля: `session_id`, `date_iso`, `current_branch`, `last_commit_sha`, `active_feature_run_id`, `next_3_actions`, `blocked_on`, `open_questions`, `risk_flags`. Append-only за пределами текущей сессии — старые STATE-snapshots уходят в `state-history/YYYY-MM-DD.md`.

`session-log/YYYY/MM/YYYY-MM-DD.md` — по дням, what was done + why + decisions + dead-ends. Append-only.

`plan.md` — текущий feature plan, регенерится /plan-командой при каждом feature-run; устаревший plan архивируется в `plans/feature-<id>.md`. ADR-references обязательны на каждом design-decision; gap 1 (plan drifts from ADR) фиксится встроенным linter'ом, проверяющим что каждый «решение» в plan.md имеет ADR-ref.

Beads — рассматривается как substitute для plan.md (его дизайн ровно для этого), но НЕ для STATE.md и session-log. Beads решает «what next», не «how got here». Внедрение Beads — P2-кандидат, не P0; сначала markdown-triple, потом если работает — миграция в Beads на plan-слой.

**Supervisory re-pass для human-authored tickets.** Принцип 9, asymmetric continuity. Human пишет ticket draft → /audit-pass skill пропускает через тот же supervisory re-pass, что и LLM-генерируемые тикеты: проверка acceptance criteria, non-goals, references, estimate. Lift human-authored до project-стандарта без формализации каждой ручной правки. Skill: read ticket markdown, check structural completeness (all 5 fields filled, AC are testable, non-goals not empty, refs include principle), produce diff suggestions. Human accept-or-reject. NOT auto-edit.

### 7. Gate ROI как механизм против бюрократии

Каждый гейт — это налог на время и внимание. Без доказательства ROI — налог взимается ни за что. /gate-audit weekly skill собирает по каждому gate:

| field | type | source |
|---|---|---|
| gate_name | string | hook config / CI workflow |
| frequency_triggered | int (per week) | hook log / GH Actions metrics |
| blocked_real_issues | int | manual tag «real-block» в audit log |
| bypass_count | int | `--no-verify`, manual override |
| false_positive_count | int | manual tag «false-block» |
| est_cost_min_per_week | float | wall-clock timing |
| retention_recommendation | KEEP/TUNE/REMOVE | derived |

Decision rule: `blocked_real_issues / (false_positive_count + bypass_count + blocked_real_issues) < 0.2` четыре недели подряд → REMOVE. Это не industry-cited threshold, это операционная эвристика; запускается `/gate-audit` и tuning'уется по 8 неделям наблюдения.

DORA 2024 (Accelerate State of DevOps Report, Google, октябрь 2024) — четыре ключа (deploy freq, change lead time, change fail rate, failed deployment recovery time) плюс пятый (reliability). Применимость к solo: lead time → keep (commit-to-prod < 1h achievable и worth tracking); deploy freq → keep weekly; change fail rate и recovery time имеют огромную дисперсию при N<30 deploys/quarter — отслеживать но не gate'ить. DORA 2024 явно меняет MTTR на «failed deployment recovery time» и переносит recovery в throughput cluster (RedMonk analysis ноябрь 2024). DORA 2025 report — UNCERTAIN по дате выхода. getdx.com 2025 critique: DORA shows system data, не объясняет why; AI-tooling улучшает individual metrics, но team-level stability иногда деградирует. Solo dev видит только upside, что и есть risk-flag сам по себе.

### 8. ADR retirement — против MADR proliferation

20 ADR за 8 дней — это не decision log, это шум. Принцип 4 («знание живёт в репо») нарушается через противоположный механизм: знания так много, что оно перестаёт быть retrievable. Без retirement criteria каждый MADR-файл становится noise.

**MADR 4.0** (релиз 2024-09-17, github.com/adr/madr) — текущий стандарт. Validation→Confirmation, Deciders→Decision Maker(s), placeholders как one-liners.

**kschlt/adr-kit** — verified, прямо релевантен solo AI-pipeline. MCP server для агентов (`adr_preflight`, `adr_create`, `adr_approve`, `adr_analyze_project`), CLI, **policy block в YAML frontmatter** автогенерирует ESLint/Ruff правила и CI workflow из ADR, staged git hooks (pre-commit <5s, pre-push <15s, CI comprehensive), semantic search над ADR'ами для load 3-5 relevant в agent context. Local-only, no external API. Это именно тот instrument, который operationalises «knowledge in repo» — ADR не просто декларация, а enforcer.

**zircote/structured-madr** — добавляет JSON Schema validation, GitHub Action validator, three-dimension risk assessment, audit-trail. Companion `zircote/git-adr` хранит в git notes (нет merge conflicts).

**Retirement criteria** (composite Nygard 2011 + GDS Way + practice):
- 90 days no-incoming-refs (commit, ADR, issue) → mark `deprecated`.
- `superseded-by` chain present → mark `superseded` + bidirectional link.
- Underlying tech removed from `package.json`/`go.mod`/etc. → `deprecated`.
- Policy block (adr-kit/structured-madr) больше не матчит код → enforcement rule auto-removed.
- Append-only: status meняется, content не редактируется.

Конкретный artefact: `/adr-retirement-audit` skill weekly cron, один скрипт, рекомендует список ADR для status change, человек approve.

### 9. Принципы в operationalised форме

| # | Принцип | Mechanical artifact | Status |
|---|---|---|---|
| 1 | Размытость — нарушение | semgrep rule «hedging-words» banned-list в plan.md (`maybe`, `possibly`, `depends`-without-branch); PR check | NEW — to build |
| 2 | Claude — критик, не автор | `tools: Read, Grep, Glob` whitelist на всех критиках; adversarial-critic agent с lazy-mandate | EXISTS, extend |
| 3 | Сначала детерминированный тулинг | `/review` two-layer: linters/radon/jscpd → LLM; approval = irreversibility-in-a-minute test embedded in PreToolUse | NEW — extend |
| 4 | Знание живёт в репо | `docs/anti-patterns.md` accumulator; adr-kit policy blocks; 1h onboarding trap-test | NEW — to build |
| 5 | Scope — границы установки | per-project worktree (ADR-0017) + universal-setup.sh idempotent | EXISTS |
| 6 | Команды — per-project | `.claude/commands/` semver drift (ADR-0018) + skill-migration plan | EXISTS, extend |
| 7 | Открытый формат — источник истины | forge.sh wrapper + AGENTS.md/CLAUDE.md duality + git+text-editor recovery test | NEW — to build |
| 8 | Антихрупкость по домену | 7-ilities gate в DoD; STPA hazard list; depth-by-criticality | NEW — to build |
| 9 | Перехват — контракт | STATE.md + session-log + plan.md triple; /audit-pass for human-tickets; 5-min resume test | NEW — to build |

8 of 14 DoD honor-system норм маппятся на принципы 1, 4, 8, 9 — большинство не имеют mechanical enforcer. Тикеты P0/P1 ниже закрывают эти gap по очереди.

### 10. Что НЕ делать в 2026

**GitHub Spec Kit** (github/spec-kit, сентябрь 2025). 4-фазная ceremony (constitution → spec → plan → tasks) для multi-agent + team. Gojko Adzic характеризует как «revenge of Waterfall or BDD taken to a new level». На solo с tight feedback loops — ADR + tests быстрее. Skip.

**Amazon Kiro** (kiro.dev, public preview июль 2025). Spec-driven, EARS notation, agent hooks, $20/mo. Одна цитата InfoQ обзора: «I feel like I'm a PM, not an engineer.» VS Code fork — vendor-lock на отдельную IDE. Wait для settling.

**Multi-role agent crews** (CrewAI, AutoGen, LangGraph multi-agent). Сам CrewAI блог: «If a step doesn't need intelligence, it's just code in your Flow. Don't overcomplicate it with agents.» На pet-scale один capable agent + clear spec + tests beats 5-agent crew. Inter-agent communication = token overhead.

**Devin** (Cognition Labs, $20/mo Core + $2.25/ACU). Independent eval: «3 of 20 tasks successfully». Holger Mueller (Constellation, апрель 2025): «lost a lot of momentum». Cursor/Claude Code at $20/mo с человеком-в-петле dominates. Skip.

**Stacked diffs** (Graphite, Sapling). Решает review-bandwidth team problem. Solo нет review queue. Rebase-tax + N×CI cost = pure overhead. Skip; trunk-based + small commits.

**DSPy** (stanfordnlp/dspy). Worth it только если: measurable metric + held-out eval ≥50 examples + stable task ≥1000s of calls. Pet-проекты — one-shot. Skip пока eval-set не построен.

**Mutation testing per-PR.** Pitest author Henry Coles, Google «Practical Mutation Testing at Scale» (arxiv 2102.11378), nexocode case-report — все sequentially против per-PR. Weekly cron + `--in-diff`. Это уже встроено в P0 список.

**Microvm sandbox** (E2B, Daytona). $150/mo Pro. Worth когда: third-party code, unattended overnight runs, parallel critic agents в worktrees. Сейчас — local + git checkpointing + PreToolUse denylist даёт 95% safety на 0% cost. P3.

**ACP broker для solo.** ACP реален и зрел (Zed/JetBrains co-developed, Apache 2.0). Используется когда нужна IDE-grade diff review. Solo на терминале — текущая Claude Code TUI достаточна. P3.

---

## Раздел B — Backlog тикетов

40 тикетов. Группированы по приоритету. Каждый совместим с `gh issue create --title ... --label ... --body ...`.

### P0 — на этой неделе (8 тикетов)

---

**#1 — feat(verifier): wire Hypothesis property-based testing into /qa skill**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: M

Problem statement: `/qa` сейчас полагается на example-based unit-tests, которые LLM пишет по training-data шаблонам. Это пропускает narrow-special-case bugs и over-fitting. Hypothesis с round-trip/metamorphic/invariant/idempotence шаблонами — индустриальный baseline (arxiv 2510.09907 Anthropic agentic PBT, 32% maintainer-reportable bugs/100 packages).

Acceptance criteria:
- `conftest.py` с тремя профилями (`dev` 50, `ci` 500, `nightly` 5000 examples) активирован в обоих pet-проектах.
- `/qa` skill включает шестишаговый prompt из arxiv 2510.09907 (analyze → understand → propose → write → execute → triage).
- На каждой критической функции: `@example([])`, `@example([0])` или эквивалентные explicit edge-cases.
- CI workflow запускает `ci` профиль; nightly cron — `nightly`.
- Документация в `docs/skills/qa.md` с одним worked example.

Non-goals: НЕ замена unit-tests; НЕ покрытие 100% функций PBT (только critical-path); НЕ coverage-driven выбор properties.

References: Принцип 3, arxiv 2510.09907, Anthropic blog post red.anthropic.com/2026/property-based-testing/, honnibal/claude-skills hypothesis-tests.

---

**#2 — feat(governance): PostToolUse hook for format+typecheck after Edit/Write**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: S

Problem statement: текущий governance hook — только PreToolUse. После Edit/Write мусор (unformatted, type-error) попадает в commit и ловится только pre-commit-hook'ом. Это поздно. PostToolUse-matcher на `Edit|MultiEdit|Write` запускает prettier+tsc / ruff+mypy сразу — 80% мусора отсекается за секунды.

Acceptance criteria:
- `.claude/settings.json` PostToolUse-matcher на `Edit|MultiEdit|Write`.
- Запуск parallel: formatter + typechecker; non-blocking (warn, не deny).
- Per-language detect: Python → ruff format + mypy; JS/TS → prettier + tsc; Go → gofmt + go vet.
- Logged в `.claude/hooks/posttooluse.log` с timestamp, file, exit-code.
- Test-coverage: один pet-проект со специально внесённым typo и type-error фиксится в одну сессию без manual run.

Non-goals: НЕ блокирует Edit при ошибке (обратная совместимость); НЕ заменяет pre-commit hook.

References: Принцип 3, claude-code hooks docs (https://code.claude.com/docs/en/hooks), pixelmojo.io production hooks pattern.

---

**#3 — feat(governance): Stop hook ensures tests pass before session end**
Labels: `principle:antifragile`, `type:bootstrap`
Estimate: S

Problem statement: сессия может закрыться с failing tests, и контекст теряется до следующей сессии — gap в continuity. Stop-hook блокирует session-end если tests не проходят (с явным `stop_hook_active` escape для аварийного выхода).

Acceptance criteria:
- `.claude/settings.json` Stop-hook с `npm test --silent || python -m pytest --quiet`.
- Возвращает `{"decision":"block","reason":"Tests failing"}` если non-zero exit.
- Респектирует `stop_hook_active` flag для escape-hatch (не infinite loop).
- Логирует blocking events в `.claude/hooks/stop.log`.
- Документировано в STATE.md template как часть session-end ритуала.

Non-goals: НЕ запускает full nightly suite; НЕ блокирует Ctrl+C kill; НЕ для long-running test suite (>5 min).

References: Принцип 9, claude-code hooks docs.

---

**#4 — feat(verifier): static-analysis baseline (ruff/eslint/staticcheck/radon/jscpd)**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: M

Problem statement: `/review` пускает LLM-критика до того, как детерминистические gate отработали. Это нарушение принципа 3 («сначала детерминированный тулинг»). Linter/complexity/duplication gate отфильтровывает 60-80% issues, которые LLM сейчас тратит токены на повторное обнаружение.

Acceptance criteria:
- ruff (Python), eslint+typescript-eslint (TS/JS) сконфигурированы во всех pet-проектах с zero-warning baseline.
- radon gate: CC ≤ 10 (rank A или B), MI > 65, fail на C+. Запускается в `/review`.
- lizard cross-language gate: `lizard -C 10 -L 100 -a 5`.
- jscpd strict-mode: `min-tokens: 50, min-lines: 5, mode: strict`. SARIF reporter включён.
- semgrep custom rules: `llm-todo-without-ticket`, `llm-commented-block` (5+ consecutive comment lines).
- `/review` skill переписан: layer 1 deterministic gates → layer 2 LLM-критик; LLM не запускается если layer 1 fails.

Non-goals: НЕ покрывает все semgrep-правила supply-chain (отдельный security-ticket); НЕ интеграция с SonarQube cloud.

References: Принципы 1, 3, 4. radon.readthedocs.io, jscpd.dev (Agent Skill для Claude), semgrep.dev/docs/writing-rules.

---

**#5 — chore(governance): /gate-audit weekly skill with ROI schema**
Labels: `principle:gate-roi`, `type:bootstrap`
Estimate: M

Problem statement: каждый gate — налог на время. Без ROI-данных gate'ы накапливаются как бюрократия. /gate-audit eженедельно собирает frequency, blocked-real, bypass, false-positive, cost. Decision rule: `real / (real + fp + bypass) < 0.2` четыре недели → REMOVE.

Acceptance criteria:
- `.claude/skills/gate-audit/SKILL.md` создан, weekly cron в CI.
- Schema audit-log JSONL: `{gate_name, week_iso, frequency, real_blocks, bypasses, false_positives, est_cost_min, retention_rec}`.
- Manual tagging tool: `forge gate-tag <event-id> --real|--false-positive` для оператора post-hoc.
- Output `docs/gate-audit/YYYY-WW.md` с recommendations.
- Один gate prune'ится по результатам первых 4 недель — proof-of-concept.

Non-goals: НЕ автоматическое удаление gate (human approval); НЕ DORA full metrics (отдельный ticket).

References: Принцип 8 (operational rule, not principle), DORA 2024 report, getdx.com 2025 critique.

---

**#6 — feat(critic): adversarial-critic agent with explicit lazy-mandate**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: M

Problem statement: текущие 8 критиков — security/reliability/domain — не имеют explicit lazy-detection mandate. Они findят то, что у них в названии. Lazy-режимы LLM (duplicate, symptom-fix, narrow case, copy-paste, truncated file, hardcoded constants) ускользают. Anthropic Code Review (multi-agent, апрель 2026) показал 84% PR > 1000 строк имеют такие баги.

Acceptance criteria:
- `.claude/agents/adversarial-critic.md` создан, `tools: Read, Grep, Glob`, model haiku (или sonnet для глубокой проверки).
- System prompt прямо перечисляет classes of laziness: duplicate code, symptom-fix-not-root, narrow special-case, copy-paste from adjacent diff hunks, truncated/empty files, hardcoded magic constants without justification, TODO without ticket-ref, commented-out code in commit.
- Загружает `docs/anti-patterns.md` в context (когда тикет #7 готов).
- Запускается в `/review` после deterministic gates.
- Output: structured list of findings с severity/location/anti-pattern-ref.

Non-goals: НЕ дублирует security-reviewer; НЕ выполняет functional code review.

References: Принцип 2, Brooks McMillin Defense in Depth, Anthropic Code Review (code.claude.com/docs/en/code-review).

---

**#7 — feat(knowledge): docs/anti-patterns.md as accumulator artifact**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: S

Problem statement: оператор ловит lazy-режимы intra-session, но не накапливает. Каждая новая сессия начинается без контекста прошлых ловок. Принцип 4 нарушен. Прецедент: Arcanum-Sec/sec-context (Jason Haddix) поддерживает ANTI_PATTERNS_BREADTH/DEPTH специально для LLM-consumption.

Acceptance criteria:
- `docs/anti-patterns.md` создан с заголовками: «Pattern», «Frequency», «Severity», «Detector», «Example», «Fix».
- Initial seed: 5-10 anti-patterns из последних 8 дней работы (truncated files, hedging in plan.md, ADR drift, etc.).
- Ranking formula: `Frequency*2 + Severity*2 + Detectability` (per Arcanum-Sec model).
- adversarial-critic (тикет #6) грузит этот файл в context.
- Pre-commit hook: при каждом manual catch — добавление в anti-patterns.md в том же commit'е (governance rule, enforced via /audit-pass).

Non-goals: НЕ замена ADR; НЕ exhaustive list — only patterns observed in repo.

References: Принцип 4. Arcanum-Sec/sec-context, honnibal/claude-skills, Brooks McMillin CLAUDE.md anti-patterns section.

---

**#8 — chore(adr): ADR retirement process with 90-day staleness audit**
Labels: `type:adr`, `principle:gate-roi`
Estimate: S

Problem statement: 20 ADR за 8 дней. Без retirement criteria каждый MADR-файл становится noise. Принцип 4 нарушается через противоположный механизм — слишком много знания.

Acceptance criteria:
- `/adr-retirement-audit` skill: weekly cron, по каждому ADR проверяет (a) 90 days no-incoming-refs, (b) underlying tech присутствует в `pyproject.toml`/`package.json`/`go.mod`, (c) `superseded-by` chain consistency.
- Output: список с recommendations `keep | mark-deprecated | mark-superseded`.
- Append-only: status field updated в YAML frontmatter, content не редактируется.
- ADR template обновлён: explicit `status` enum (proposed/accepted/deprecated/superseded), `superseded-by`, `last-referenced-sha`.
- Первый pass: 2-3 ADR из 20 retiring (proof).

Non-goals: НЕ delete ADR file; НЕ автоматический tagging без human approval.

References: Принцип 4. Nygard 2011 «Documenting Architecture Decisions», MADR 4.0 spec, GDS Way ADR practice, kschlt/adr-kit (для будущей P2 интеграции).

---

### P1 — следующие 2-6 недель (12 тикетов)

---

**#9 — feat(forge): forge.sh wrapper abstracting gh for GitHub/Gitea/Forgejo/GitLab**
Labels: `principle:agnostic`, `type:bootstrap`
Estimate: M

Problem statement: GitHub — medium vendor-lock risk (per matrix). Forge.sh wrapper preventively. Migration на Gitea/Forgejo/GitLab за час — это test для принципа 7. Прецедент: Leleat/git-forge (Rust); shell-wrapper greenfield.

Acceptance criteria:
- `bin/forge.sh` поддерживает `forge issue create`, `forge issue list`, `forge pr open`, `forge pr merge`, `forge release tag`.
- Под капотом: `FORGE_PROVIDER` env-переменная (`github` default, `gitea`, `gitlab`, `forgejo`).
- Driver-pattern: `forge-driver-github.sh`, `forge-driver-gitea.sh` (минимум первый, остальные stub).
- `/task-to-issue`, `/issue-to-task`, `/feature` мигрированы на forge.sh.
- Migration test: создаётся scratch Gitea instance в Docker, тикет создаётся через forge.sh с `FORGE_PROVIDER=gitea` без правок caller-кода.

Non-goals: НЕ покрытие projects-v2, actions, gists; НЕ wrapper над `gh auth login`.

References: Принцип 7. Leleat/git-forge, AGENTS.md / Linux Foundation AAIF.

---

**#10 — feat(agnostic): AGENTS.md + CLAUDE.md duality migration**
Labels: `principle:agnostic`, `type:bootstrap`
Estimate: S

Problem statement: AGENTS.md теперь под Linux Foundation AAIF (декабрь 2025), читается Codex CLI, Goose, opencode, Aider, Cursor, Devin, Jules. CLAUDE.md — Claude-specific dialect. Шипить оба.

Acceptance criteria:
- `AGENTS.md` создан, содержит generic instructions (репо структура, test/build/run, Conventional Commits).
- `CLAUDE.md` переписан как stub с `@AGENTS.md` import + Claude-специфичные skills/agents/hooks references.
- Обоих pet-проекта мигрированы.
- README.md документирует duality для maintainer.

Non-goals: НЕ полный rewrite content; НЕ дублирование instructions.

References: Принцип 7. agents.md/, AAIF announcement, opencode docs (читает AGENTS.md + CLAUDE.md fallback).

---

**#11 — feat(continuity): STATE.md + session-log + plan.md triple hand-off contract**
Labels: `principle:continuity`, `type:bootstrap`
Estimate: M

Problem statement: принцип 9 требует test «human resume в 5 min от LLM-stop». Сейчас plan.md drifts (gap 1), session-log не структурирован, STATE.md не существует. Тройной hand-off — STATE.md (snapshot, ≤200 lines), session-log (append-only daily), plan.md (regenerable).

Acceptance criteria:
- `STATE.md` template: `session_id, date_iso, current_branch, last_commit_sha, active_feature_run_id, next_3_actions, blocked_on, open_questions, risk_flags`.
- `session-log/YYYY/MM/YYYY-MM-DD.md` append-only.
- `plan.md` linter: каждое design-decision имеет ADR-ref (fixes gap 1).
- Resume drill: оператор симулирует «LLM unavailable, новый dev приходит на репо» — test passing если onboarding-task закрывается за 1-2 часа.
- Stop-hook (тикет #3) обновляет STATE.md.

Non-goals: НЕ Beads integration (P2); НЕ замена git log.

References: Принцип 9. Anthropic CLAUDE.md/MEMORY.md docs, Cline memory bank, claudefa.st auto-dream.

---

**#12 — feat(audit): /audit-pass skill for human-authored ticket supervisory re-pass**
Labels: `principle:continuity`, `type:bootstrap`
Estimate: S

Problem statement: human-authored tickets (то что оператор пишет руками между LLM-сессиями) не проходят тот же quality gate, что LLM-генерируемые. Asymmetric continuity (принцип 9) фиксирует это через supervisory re-pass — НЕ блокирует, а лифтит.

Acceptance criteria:
- `.claude/skills/audit-pass/SKILL.md` принимает ticket markdown.
- Проверяет structural completeness: title (CC-compatible), priority, labels, problem statement, AC (≥3 testable), non-goals, references (principle ref obligatory), estimate (S/M/L).
- Output: diff suggestions, не auto-edit.
- Human accept-or-reject через `gh issue edit` или manual.
- Documented usage in `docs/skills/audit-pass.md`.

Non-goals: НЕ auto-edit; НЕ блокирование create.

References: Принцип 9.

---

**#13 — refactor(domain): split domain layer into meta-pipeline vs per-project**
Labels: `principle:domain`, `type:adr`
Estimate: L

Problem statement: текущий `docs/domain/` описывает pipeline как domain. Domain inversion: pet-проекты имеют свои домены, метa-pipeline отдельный. Verraes (август 2025) подтверждает: домены и BC не маппятся 1-к-1.

Acceptance criteria:
- `docs/domain/meta/` — pipeline BC (FeatureRun, GovernanceRun, TwoVoiceReview, RunbookExecution).
- `docs/domain/<project>/` для каждого pet-проекта; archi2likec4 имеет свои аггрегаты (C4-Diagram, ContainerLayer).
- `docs/domain/context-map.md` — Mermaid с ACL-стрелками между meta и target.
- ACL implementation: один Python модуль, валидирующий artifacts из pet-проекта против meta-schema.
- ADR-XXXX «Domain Inversion: Meta vs Target Bounded Contexts» документирует решение.

Non-goals: НЕ полный DDD strategic design для каждого pet-проекта (только если domain-rich — archi2likec4 yes, news-digest borderline).

References: Принцип 8. Verraes 2025 «Domains and BCs Don't Map 1 on 1», Eric Evans DDD Europe 2025, Synpulse8 AACL pattern.

---

**#14 — refactor(skills): convert slash commands to Claude Code Skills format**
Labels: `principle:agnostic`, `type:bootstrap`
Estimate: M

Problem statement: Skills (релиз октябрь 2025, Open Standard декабрь 2025) — autoloaded by description matching, progressive disclosure, bundled scripts. Slash commands — manual-only injection. Migration: те команды что выигрывают от autoload (`/qa`, `/review`, `/backlog-review`, `/project-health`).

Acceptance criteria:
- `.claude/skills/qa/SKILL.md`, `.claude/skills/review/SKILL.md`, `.claude/skills/backlog-review/SKILL.md`, `.claude/skills/project-health/SKILL.md` созданы.
- Side-effecting (`/implement`, `/task-to-issue`, `/issue-to-task`) остаются как commands ИЛИ переведены с `disable-model-invocation: true`.
- Each SKILL.md ≤500 lines; heavy reference content в `references/` subdirectory.
- Deterministic steps вынесены в `scripts/*.{py,sh}`.
- Skill-creator skill используется для validation.

Non-goals: НЕ migration `/feature` master orchestrator (он остаётся командой).

References: Принцип 6. code.claude.com/docs/en/skills, anthropics/skills repo.

---

**#15 — feat(verifier): third voice on open-weight (Kimi K2.6 / DeepSeek V4 / Qwen3-Coder)**
Labels: `principle:agnostic`, `principle:lazy-detection`
Estimate: M

Problem statement: two-voice review (Claude /review + Codex /codex-review) проседает когда Codex недоступен (graceful-degradation в type:deferred-review). Третий голос на open-weight даёт пол. Cross-family мандатна (intra-family panels reinforce bias, не cancel — Panickssery 2024, EMNLP 2025).

Acceptance criteria:
- `.claude/skills/third-voice-review/SKILL.md` интегрируется через OpenRouter / Ollama local.
- Default model: Kimi K2.6 (Tier-A Akita benchmark, 89.3 coding) ИЛИ Qwen3-Coder-Next-80B-A3B локально.
- Запускается когда Codex unavailable ИЛИ оператор явно вызвал.
- Minority-veto strategy: любой из трёх блокирует — блок (per arxiv 2510.11822).
- Position bias mitigation: swap-and-rejudge на critical findings.

Non-goals: НЕ заменяет Codex; НЕ training/fine-tuning open-weight.

References: Принципы 2, 7. arxiv 2510.11822 minority-veto, Akita benchmark, magazine.sebastianraschka.com open-weight 2026.

---

**#16 — feat(verifier): /intent-check skill (acceptance criteria vs diff alignment)**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: S

Problem statement: LLM имплементирует «around the AC» — диф решает похожую задачу, но не ту. /intent-check skill сравнивает AC из тикета и diff из feature branch и репортит mismatch.

Acceptance criteria:
- Skill принимает `<issue-id>` и текущий branch.
- Loads acceptance criteria from `gh issue view`.
- Compares against `git diff main...HEAD`.
- Output: list of AC items с status `covered | partial | missing | unrelated-changes`.
- Запускается в `/feature` finalization step и в `/review`.

Non-goals: НЕ semantic test gen; НЕ замена manual review.

References: Принципы 1, 2.

---

**#17 — chore(verifier): mutation testing weekly cron (mutmut/Stryker/cargo-mutants)**
Labels: `principle:lazy-detection`, `principle:antifragile`
Estimate: M

Problem statement: per-PR mutation testing — антипаттерн (Pitest author, Google 2102.11378). Weekly cron на main с `--in-diff` для инкрементального режима. Mutation score target 80%, gate 60%.

Acceptance criteria:
- `.github/workflows/mutation.yml` с `cron: '0 0 * * 0'` (sunday 00:00 UTC).
- Python: mutmut v3+ с `--paths-to-mutate src/`, mypy-фильтр невалидных мутантов.
- TS/JS: Stryker с `break: 50, low: 60, high: 80`.
- Rust: cargo-mutants с `--in-diff`.
- Output: SARIF report uploaded; markdown summary в issue с label `type:mutation-report`.
- Surviving mutants добавляются в `docs/anti-patterns.md` (тикет #7) если pattern repeats.

Non-goals: НЕ per-PR run; НЕ полный mutation на каждом push.

References: Принципы 3, 8. arxiv 2308.16557 (MuTAP), arxiv 2506.02954 (MutGen), Google arxiv 2102.11378, Pitest blog.

---

**#18 — chore(governance): DoD compliance table — prune honor-only norms, automate**
Labels: `principle:gate-roi`, `type:bootstrap`
Estimate: M

Problem statement: 8 of 14 DoD норм honor-system. Принцип 1 нарушен в ядре. Каждая норма — либо mechanical enforcer, либо явная пометка `honor-only — known gap` + ticket в P1/P2.

Acceptance criteria:
- `docs/domain/overview.md` compliance table обновлена: каждая норма имеет колонку `enforcer` (path to hook/CI/skill) или `honor-only — see #ticket`.
- 4 of 8 honor-only converted в mechanical (hooks, CI checks, ADR-Kit policy blocks).
- Остальные 4 имеют tickets в P2 backlog.
- Weekly /gate-audit (тикет #5) включает DoD compliance в ROI calculation.

Non-goals: НЕ 100% mechanisation (некоторые нормы fundamentally honor-only — e.g. «author truly understood why»).

References: Принципы 1, 8. Принцип-9 supervisory re-pass.

---

**#19 — feat(verifier): semgrep rules for hedging-words and corporate-softening in plan.md**
Labels: `principle:lazy-detection`, `type:bootstrap`
Estimate: S

Problem statement: gap 4 (banned terms in plan.md). Принцип 1 («размытость — нарушение») requires mechanical detection of hedging language: `maybe`, `possibly`, `depends`-without-branching-condition, «could», «might», «perhaps».

Acceptance criteria:
- `.semgrep/hedging.yml` rules с regex'ами на banned terms в `plan.md`, `STATE.md`, `docs/decisions/*.md`.
- Pre-commit hook вызывает semgrep на staged markdown files.
- `depends` allowed только если followed by «when X then Y, when Z then W» branching.
- False-positive review process: добавление в `.semgrepignore` с reason-comment.

Non-goals: НЕ generic prose-linter; НЕ грамматика.

References: Принцип 1.

---

**#20 — chore(security): MCP transport hardening + pin versions + Stacklok ToolHive evaluation**
Labels: `principle:agnostic`, `prod-bound`
Estimate: M

Problem statement: CVE-2026-27825 (MCPwnfluence, sooperset/mcp-atlassian, февраль 2026, CVSS 9.1) + 10 systemic CVE в Anthropic MCP SDK stdio transport (OX Security, апрель 2026) — MCP больше не low-risk slot. Bank context требует hardening.

Acceptance criteria:
- Все MCP servers в `.claude/mcp.json` pinned by version (semver, не latest).
- stdio transport для local (Serena, Context7); HTTP только с allowlist + bind 127.0.0.1.
- Stacklok ToolHive evaluated (off-the-shelf MCP isolation/network restriction).
- Quarterly review: CVE check всех installed MCP servers.
- ADR-XXXX «MCP Transport Security» документирует policy.

Non-goals: НЕ полный MCP server audit (CVE check только); НЕ написание собственного MCP isolation.

References: Принцип 7. CVE-2026-27825, OX Security disclosure (thehackernews 2026/04), Stacklok ToolHive, modelcontextprotocol.io security_best_practices.

---

### P2 — 1-3 месяца (12 тикетов)

---

**#21 — feat(adr): ADR Kit MCP integration**
Labels: `type:adr`, `principle:gate-roi`
Estimate: M

Problem statement: kschlt/adr-kit предоставляет MCP server (`adr_preflight`, `adr_create`, `adr_approve`, `adr_analyze_project`), policy block в YAML frontmatter автогенерирует ESLint/Ruff правила, staged git hooks. Это operationalises «knowledge in repo».

Acceptance criteria:
- adr-kit установлен и настроен в `.claude/mcp.json`.
- Существующие 20 ADR мигрированы в формат с policy blocks где applicable.
- semantic search loads 3-5 relevant ADRs в agent context на каждом feature-run.
- Pre-commit <5s import-restriction hook включён.
- Pre-push <15s architecture-boundary hook.

Non-goals: НЕ rewriting ADR content; НЕ замена MADR 4.0.

References: Принцип 4. github.com/kschlt/adr-kit.

---

**#22 — feat(verifier): Schemathesis for any HTTP surface in pet-projects**
Labels: `principle:antifragile`, `principle:lazy-detection`
Estimate: M

Problem statement: news-digest bot имеет HTTP surface (если webhook). Schemathesis (v4.16.1, апрель 2026) — drop-in OpenAPI fuzzing на Hypothesis engine; phases examples → coverage → fuzzing → stateful.

Acceptance criteria:
- Schemathesis установлен в каждом проекте с HTTP surface.
- pytest integration: `schema.parametrize()` decorator.
- CI workflow: `schemathesis/action@v3` с `examples + coverage + fuzzing` phases.
- Stateful только если OpenAPI spec имеет links.
- Bounded `--max-examples=200` для CI runtime.

Non-goals: НЕ для проектов без HTTP API.

References: Принцип 8. schemathesis.io.

---

**#23 — feat(release): GitHub native auto-merge for trivial PRs**
Labels: `principle:gate-roi`
Estimate: S

Problem statement: trivial PRs (dependabot patches, format-only commits) проходят через manual merge — налог на внимание без ROI.

Acceptance criteria:
- GitHub repo settings: auto-merge enabled.
- `.github/workflows/auto-merge-trivial.yml`: matcher на `dependabot/`, `chore: format`, `chore: lint-fix` labels.
- Все CI gates должны pass.
- Логируется в /gate-audit (тикет #5) как «auto-merge: 12 PRs/week».

Non-goals: НЕ auto-merge feature PRs; НЕ skip review.

References: Принцип 8 operational rule.

---

**#24 — feat(operability): OpenFeature flags via flagd file-based provider**
Labels: `principle:antifragile`
Estimate: M

Problem statement: pet-проекты с пользователями (если/когда) нуждаются в kill-switch и feature flags. OpenFeature CNCF-incubating, file-based flagd — solo-friendly.

Acceptance criteria:
- flagd container или local binary с `flags.flagd.json`.
- Python/TS SDK интегрирован.
- 1-2 feature flags активных в одном pet-проекте как proof.
- ADR-XXXX «Feature Flags via OpenFeature flagd».

Non-goals: НЕ adoption если у проекта 0 пользователей; НЕ percentage rollouts.

References: Принцип 8 (depth-by-criticality). openfeature.dev, flagd CNCF.

---

**#25 — feat(backlog): /backlog-grooming agent with ICE/RICE scoring**
Labels: `type:bootstrap`, `principle:gate-roi`
Estimate: M

Problem statement: текущий backlog-groomer не ranks тикеты. ICE (Impact*Confidence*Ease) или RICE (Reach*Impact*Confidence/Effort) даёт numeric priority signal.

Acceptance criteria:
- `/backlog-review` skill добавляет ICE-score (1-10 на dimension) к каждому open issue.
- Output: ranked list `gh issue list --json` + computed score.
- Manual override через ticket label `priority:override`.
- Weekly /project-health включает ICE-distribution.

Non-goals: НЕ авто-prioritisation merge; НЕ замена P0/P1/P2/P3.

References: Принцип 8 operational rule.

---

**#26 — refactor(ddd): aggressive DDD retirement audit at solo scale**
Labels: `principle:domain`, `type:adr`
Estimate: S

Problem statement: DDD на solo масштабе pet-project pipeline meta — overhead concern (user explicitly flagged). Если 3 aggregates (FeatureRun, GovernanceRun, TwoVoiceReview) не несут domain-rich behaviour beyond CRUD — retire to scripts.

Acceptance criteria:
- Each aggregate audited: behaviour ≥ 3 non-trivial invariants? Lifecycle ≥ 3 states? Если нет — retire.
- Retired aggregates → simple modules.
- ADR-XXXX «DDD Retirement Audit» документирует решения per-aggregate.
- `docs/domain/meta/` обновлён.

Non-goals: НЕ retire без evidence; НЕ touch per-project domain layers (тикет #13).

References: Принцип 8. Tony Marston critique, HN 2024 DDD discussion.

---

**#27 — feat(observability): structured JSON logs + OTel auto-instrumentation in pet-projects**
Labels: `principle:antifragile`
Estimate: M

Problem statement: 7-ilities gate включает observability. Текущие pet-проекты — print-debugging. JSON logger + trace_id/span_id + OTel SDK auto-instrumentation в один backend (Honeycomb free tier или local OTel collector).

Acceptance criteria:
- structlog (Python) или pino (Node) с JSON format.
- OTel SDK initialised; trace_id propagation через requests.
- One backend connected (Honeycomb free / local OTel collector → SQLite).
- SLO `slo.md` с 1-2 SLI per project.

Non-goals: НЕ full Datadog stack; НЕ multi-pillar.

References: Принцип 8. Charity Majors observability 2.0, honeycomb.io blog 2025.

---

**#28 — feat(security): supply-chain table-stakes (SLSA L2, cosign, gitleaks)**
Labels: `principle:antifragile`, `prod-bound`
Estimate: M

Problem statement: 2025 GhostAction npm/Actions compromises = baseline shifted. Dependabot, gitleaks, cosign keyless OIDC, SLSA L2 provenance — minimum.

Acceptance criteria:
- Dependabot enabled на обоих pet-проектах.
- gitleaks pre-commit hook + GitHub native secret scanning.
- Release workflow: `cosign sign --yes` + `actions/attest-build-provenance`.
- Pinned actions by SHA (не by tag).
- ADR-XXXX «Supply Chain Baseline».

Non-goals: НЕ SLSA L3 hermetic builders; НЕ internal Fulcio/Rekor.

References: Принцип 8. AquilaX 2025 SLSA L2, OpenSSF guidance, sigstore/cosign docs.

---

**#29 — feat(continuity): runbook.md + restore drill weekly cron**
Labels: `principle:antifragile`, `principle:continuity`
Estimate: S

Problem statement: recoverability gate — 7-ility minimum. Currently no runbook, no restore drill. RPO=24h, RTO=1h declared.

Acceptance criteria:
- `runbook.md` per project with copy-pasteable restore commands.
- Weekly cron: restore last backup в scratch container, assert row counts / fixture data integrity.
- Failed restore → P0 incident issue auto-created.

Non-goals: НЕ multi-region replication; НЕ PITR.

References: Принцип 8. Google SRE Book Ch.4.

---

**#30 — feat(stpa): one-time STPA hazard pass on pipeline**
Labels: `principle:antifragile`, `type:adr`
Estimate: M

Problem statement: STPA Handbook (Leveson, MIT 2018) generic фреймворк. One-time pass даёт hazard list, маппящийся в hooks (PreToolUse denylist) и runbooks. Не повторять regularly; пересматривать при architecture change.

Acceptance criteria:
- `docs/stpa/hazard-analysis.md`: Losses → Hazards → Control Structure → UCAs → Loss Scenarios.
- 5-10 UCAs identified (e.g., «agent provides `git push --force` on main»).
- Each UCA mapped to existing or new hook/control.
- ADR-XXXX «STPA Pipeline Hazard Analysis».

Non-goals: НЕ ongoing STPA audits; НЕ formal safety-case.

References: Принцип 8. Leveson STPA Handbook 2018 (psas.scripts.mit.edu).

---

**#31 — chore(governance): semgrep multimodal evaluation as deterministic-LLM hybrid**
Labels: `principle:lazy-detection`
Estimate: S

Problem statement: Semgrep Multimodal (март 2026) — rule-based + LLM reasoning hybrid; Cursor/Claude Code plugin available. Может заменить часть adversarial-critic'а на детерминистическом slot.

Acceptance criteria:
- Evaluated на одном pet-проекте за 1 неделю.
- Comparison report: Semgrep Multimodal vs adversarial-critic findings (precision, recall, false-positive rate).
- Decision: adopt | reject | hybrid; ADR-XXXX документирует.

Non-goals: НЕ replace adversarial-critic without evidence; НЕ paid tier.

References: Принцип 3. helpnetsecurity.com 2026/03/20 Semgrep Multimodal.

---

**#32 — feat(continuity): Beads (Yegge) trial as plan.md replacement**
Labels: `principle:continuity`
Estimate: M

Problem statement: plan.md drifts. Beads (Steve Yegge, ~18K stars, v0.59 март 2026) — git-backed graph issue tracker для агентов; решает «50 First Dates» problem. Agent-agnostic; читается через CLAUDE.md / AGENTS.md instruction.

Acceptance criteria:
- Beads установлен, `.beads/` initialized в одном pet-проекте.
- 1-2 weeks trial: plan.md заменён `bd ready --json` output.
- AGENTS.md instructs agent: «Use `bd` for task tracking».
- Comparison: drift incidents pre vs post.
- Decision adopt/reject + ADR-XXXX.

Non-goals: НЕ replace STATE.md или session-log; НЕ migrate на Beads если drift не уменьшился.

References: Принцип 9. github.com/steveyegge/beads, Yegge launch essay Oct 2025.

---

### P3 — someday/optional (8 тикетов)

---

**#33 — chore(sandbox): microVM sandbox evaluation (e2b/Daytona) — defer until needed**
Labels: `principle:antifragile`
Estimate: L

Problem statement: E2B ($150/mo Pro), Daytona (open-source, Docker default + Kata optional). Worth когда: third-party code, unattended overnight runs, parallel critic agents в worktrees. Currently — local + git checkpointing + PreToolUse denylist даёт 95% safety на 0% cost.

Acceptance criteria: trigger conditions documented. Re-evaluate quarterly.

Non-goals: НЕ adopt без trigger.

References: Принцип 8 (overengineering failure mode).

---

**#34 — chore(acp): ACP broker support (Zed/JetBrains) — defer**
Labels: `principle:agnostic`
Estimate: M

Problem statement: ACP (Agent Client Protocol, Zed/JetBrains co-developed) реален и зрел; ACP Registry январь 2026. Useful когда нужна IDE-grade diff review.

Acceptance criteria: trigger documented («когда terminal UI Claude Code станет недостаточным»).

References: Принцип 7. agentclientprotocol.com.

---

**#35 — research(verifier): custom-trained discriminator for lazy-pattern detection**
Labels: `principle:lazy-detection`
Estimate: L

Problem statement: long-shot. Train small model (≤7B) на собственном corpus anti-patterns.md как discriminator для lazy-detection. Worth только если anti-patterns.md накопит ≥500 examples и adversarial-critic precision/recall plateau.

Acceptance criteria: trigger conditions documented.

References: Принцип 4.

---

**#36 — research(optimizer): DSPy для core skill prompts — defer**
Labels: `principle:lazy-detection`
Estimate: L

Problem statement: DSPy worth когда (a) measurable metric, (b) eval set ≥50, (c) stable task ≥1000s calls. Сейчас pet-проекты one-shot. Defer до eval set готов.

Acceptance criteria: trigger documented.

References: Towards Data Science 2025 DSPy review.

---

**#37 — chore(adr): structured-madr / git-adr migration evaluation**
Labels: `type:adr`
Estimate: M

Problem statement: zircote/structured-madr добавляет JSON Schema validation, GitHub Action, three-dimension risk assessment. Companion git-adr хранит в git notes (no merge conflicts). Эвалюируется после adr-kit (тикет #21) on production.

Acceptance criteria: comparison adr-kit vs structured-madr; decision documented.

References: github.com/zircote/structured-madr.

---

**#38 — chore(runtime): quarterly Claude Code vendor-monitor — formalised**
Labels: `principle:agnostic`
Estimate: S

Problem statement: Claude Code = high vendor-lock risk. Quarterly check: Akita / BenchLM benchmarks, breaking changes Claude Code, ACP Registry новые agents, opencode growth, open-weight progress (Kimi/Qwen/DeepSeek).

Acceptance criteria: quarterly cron issue auto-created с template; output `docs/vendor-watch/YYYY-Q.md`.

References: Принцип 7.

---

**#39 — chore(docs): 1h onboarding traps test (continuity)**
Labels: `principle:continuity`
Estimate: S

Problem statement: тест принципа 4 («1h onboarding includes typical traps») — формализовать. Hypothetical new dev приходит на репо, проходит `docs/onboarding.md`, через 1h может (a) запустить `/feature` end-to-end на trivial task, (b) перечислить 3 anti-patterns из anti-patterns.md.

Acceptance criteria: `docs/onboarding.md` написан; quarterly drill — оператор просит ChatGPT-with-no-context пройти onboarding и репортит gaps.

References: Принципы 4, 9.

---

**#40 — research(verifier): multi-judge calibration with regression bias correction (arxiv 2510.11822)**
Labels: `principle:lazy-detection`
Estimate: L

Problem statement: arxiv 2510.11822 предлагает regression-based bias correction с small (~30-100) human-annotated calibration set. Worth когда two-voice review накопит ≥100 human-tagged judgments из /gate-audit.

Acceptance criteria: trigger conditions documented; corpus build начат через manual tagging в /gate-audit (тикет #5).

References: Принцип 2. arxiv 2510.11822, Lin Shi et al. IJCNLP 2025 position bias.

---

## Закрывающий комментарий

**Что уезжает в production за неделю:** 8 P0 тикетов закрывают principal gaps по lazy-detection, gate-ROI, continuity-baseline. Каждый из них имеет grounded reference и понятный test для приёмки. Принципы 1, 2, 3, 4, 9 получают первый mechanical enforcer; принципы 7, 8 — заходят в P1.

**Где состояние индустрии неопределённо** (явно):
- DORA 2025 report — не подтверждён к выходу на 29 апреля 2026.
- «STPA-light» как named publication — не существует; STPA Handbook 2018 generic фреймворк.
- Vaughn Vernon flagship 2025-2026 piece on AI agents = BC — не найден; substitute Verraes 2025.
- ContextCrush CVE assignment — не верифицирован в NVD на момент проверки.
- forge.sh wrapper в значимом ecosystem — не существует; Leleat/git-forge ближайший прецедент в Rust, не в shell.

**Что НЕ должно попасть в backlog в 2026 при solo-масштабе:** Spec Kit ceremony, Kiro IDE fork, multi-agent crews (CrewAI/AutoGen), Devin cloud, stacked diffs, DSPy без eval set, mutation testing per-PR, microvm sandbox без trigger. Каждое — P3 минимум, большинство — never-unless-trigger.

Принципы переведены из философии в чек-листы. Чек-листы переведены в hooks, skills, agents, semgrep rules, ADR policy blocks, /gate-audit metrics. Каждый P0 тикет имеет binary acceptance criterion — либо работает, либо нет. Никаких «должно бы». Снайперская винтовка, не пулемёт.
