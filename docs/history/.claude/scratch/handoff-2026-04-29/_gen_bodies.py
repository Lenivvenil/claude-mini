#!/usr/bin/env python3
"""Generate 40 ticket body files + backlog-plan.md from synthesis data.

Run from repo root: python3 .claude/scratch/handoff-2026-04-29/_gen_bodies.py
"""
from __future__ import annotations

from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parent
BODIES = ROOT / "bodies"
BODIES.mkdir(parents=True, exist_ok=True)

SYNTHESIS_REF = "`docs/synthesis/2026-04-29-pipeline-restructuring.md`"

# Each ticket: number, title (full from synthesis incl. prefix), labels (raw from synthesis),
# estimate (S/M/L), priority (P0/P1/P2/P3), depends_on (list of ticket numbers from this batch),
# duplicate_of (issue number or None), problem, acceptance (list of raw AC bullets from synthesis),
# non_goals (raw text), references (raw text), principle_refs (list of principle numbers).
TICKETS = [
    # ============================ P0 (8) ============================
    dict(
        num=1, priority="P0", estimate="M",
        title="feat(verifier): wire Hypothesis property-based testing into /qa skill",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[3],
        depends_on=[],
        duplicate_of=None,
        problem="`/qa` сейчас полагается на example-based unit-tests, которые LLM пишет по training-data шаблонам. Это пропускает narrow-special-case bugs и over-fitting. Hypothesis с round-trip/metamorphic/invariant/idempotence шаблонами — индустриальный baseline (arxiv 2510.09907 Anthropic agentic PBT, 32% maintainer-reportable bugs/100 packages).",
        acceptance=[
            "`conftest.py` с тремя профилями (`dev` 50, `ci` 500, `nightly` 5000 examples) активирован в обоих pet-проектах.",
            "`/qa` skill включает шестишаговый prompt из arxiv 2510.09907 (analyze → understand → propose → write → execute → triage).",
            "На каждой критической функции: `@example([])`, `@example([0])` или эквивалентные explicit edge-cases.",
            "CI workflow запускает `ci` профиль; nightly cron — `nightly`.",
            "Документация в `docs/skills/qa.md` с одним worked example.",
        ],
        non_goals="НЕ замена unit-tests; НЕ покрытие 100% функций PBT (только critical-path); НЕ coverage-driven выбор properties.",
        references="Принцип 3, arxiv 2510.09907, Anthropic blog post red.anthropic.com/2026/property-based-testing/, honnibal/claude-skills hypothesis-tests.",
    ),
    dict(
        num=2, priority="P0", estimate="S",
        title="feat(governance): PostToolUse hook for format+typecheck after Edit/Write",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[3],
        depends_on=[],
        duplicate_of=None,
        problem="Текущий governance hook — только PreToolUse. После Edit/Write мусор (unformatted, type-error) попадает в commit и ловится только pre-commit-hook'ом. Это поздно. PostToolUse-matcher на `Edit|MultiEdit|Write` запускает prettier+tsc / ruff+mypy сразу — 80% мусора отсекается за секунды.",
        acceptance=[
            "`.claude/settings.json` PostToolUse-matcher на `Edit|MultiEdit|Write`.",
            "Запуск parallel: formatter + typechecker; non-blocking (warn, не deny).",
            "Per-language detect: Python → ruff format + mypy; JS/TS → prettier + tsc; Go → gofmt + go vet.",
            "Logged в `.claude/hooks/posttooluse.log` с timestamp, file, exit-code.",
            "Test-coverage: один pet-проект со специально внесённым typo и type-error фиксится в одну сессию без manual run.",
        ],
        non_goals="НЕ блокирует Edit при ошибке (обратная совместимость); НЕ заменяет pre-commit hook.",
        references="Принцип 3, claude-code hooks docs (https://code.claude.com/docs/en/hooks), pixelmojo.io production hooks pattern.",
    ),
    dict(
        num=3, priority="P0", estimate="S",
        title="feat(governance): Stop hook ensures tests pass before session end",
        labels=["principle:antifragile", "type:bootstrap"],
        principles=[9],
        depends_on=[],
        duplicate_of=None,
        problem="Сессия может закрыться с failing tests, и контекст теряется до следующей сессии — gap в continuity. Stop-hook блокирует session-end если tests не проходят (с явным `stop_hook_active` escape для аварийного выхода).",
        acceptance=[
            "`.claude/settings.json` Stop-hook с `npm test --silent || python -m pytest --quiet`.",
            "Возвращает `{\"decision\":\"block\",\"reason\":\"Tests failing\"}` если non-zero exit.",
            "Респектирует `stop_hook_active` flag для escape-hatch (не infinite loop).",
            "Логирует blocking events в `.claude/hooks/stop.log`.",
            "Документировано в STATE.md template как часть session-end ритуала.",
        ],
        non_goals="НЕ запускает full nightly suite; НЕ блокирует Ctrl+C kill; НЕ для long-running test suite (>5 min).",
        references="Принцип 9, claude-code hooks docs.",
    ),
    dict(
        num=4, priority="P0", estimate="M",
        title="feat(verifier): static-analysis baseline (ruff/eslint/staticcheck/radon/jscpd)",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[1, 3, 4],
        depends_on=[],
        duplicate_of=None,
        problem="`/review` пускает LLM-критика до того, как детерминистические gate отработали. Это нарушение принципа 3 («сначала детерминированный тулинг»). Linter/complexity/duplication gate отфильтровывает 60-80% issues, которые LLM сейчас тратит токены на повторное обнаружение.",
        acceptance=[
            "ruff (Python), eslint+typescript-eslint (TS/JS) сконфигурированы во всех pet-проектах с zero-warning baseline.",
            "radon gate: CC ≤ 10 (rank A или B), MI > 65, fail на C+. Запускается в `/review`.",
            "lizard cross-language gate: `lizard -C 10 -L 100 -a 5`.",
            "jscpd strict-mode: `min-tokens: 50, min-lines: 5, mode: strict`. SARIF reporter включён.",
            "semgrep custom rules: `llm-todo-without-ticket`, `llm-commented-block` (5+ consecutive comment lines).",
            "`/review` skill переписан: layer 1 deterministic gates → layer 2 LLM-критик; LLM не запускается если layer 1 fails.",
        ],
        non_goals="НЕ покрывает все semgrep-правила supply-chain (отдельный security-ticket); НЕ интеграция с SonarQube cloud.",
        references="Принципы 1, 3, 4. radon.readthedocs.io, jscpd.dev (Agent Skill для Claude), semgrep.dev/docs/writing-rules.",
    ),
    dict(
        num=5, priority="P0", estimate="M",
        title="chore(governance): /gate-audit weekly skill with ROI schema",
        labels=["principle:gate-roi", "type:bootstrap"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="Каждый gate — налог на время. Без ROI-данных gate'ы накапливаются как бюрократия. /gate-audit eженедельно собирает frequency, blocked-real, bypass, false-positive, cost. Decision rule: `real / (real + fp + bypass) < 0.2` четыре недели → REMOVE.",
        acceptance=[
            "`.claude/skills/gate-audit/SKILL.md` создан, weekly cron в CI.",
            "Schema audit-log JSONL: `{gate_name, week_iso, frequency, real_blocks, bypasses, false_positives, est_cost_min, retention_rec}`.",
            "Manual tagging tool: `forge gate-tag <event-id> --real|--false-positive` для оператора post-hoc.",
            "Output `docs/gate-audit/YYYY-WW.md` с recommendations.",
            "Один gate prune'ится по результатам первых 4 недель — proof-of-concept.",
        ],
        non_goals="НЕ автоматическое удаление gate (human approval); НЕ DORA full metrics (отдельный ticket).",
        references="Принцип 8 (operational rule, not principle), DORA 2024 report, getdx.com 2025 critique.",
    ),
    dict(
        num=6, priority="P0", estimate="M",
        title="feat(critic): adversarial-critic agent with explicit lazy-mandate",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[2],
        depends_on=[7],
        duplicate_of=None,
        problem="Текущие 8 критиков — security/reliability/domain — не имеют explicit lazy-detection mandate. Они findят то, что у них в названии. Lazy-режимы LLM (duplicate, symptom-fix, narrow case, copy-paste, truncated file, hardcoded constants) ускользают. Anthropic Code Review (multi-agent, апрель 2026) показал 84% PR > 1000 строк имеют такие баги.",
        acceptance=[
            "`.claude/agents/adversarial-critic.md` создан, `tools: Read, Grep, Glob`, model haiku (или sonnet для глубокой проверки).",
            "System prompt прямо перечисляет classes of laziness: duplicate code, symptom-fix-not-root, narrow special-case, copy-paste from adjacent diff hunks, truncated/empty files, hardcoded magic constants without justification, TODO without ticket-ref, commented-out code in commit.",
            "Загружает `docs/anti-patterns.md` в context (когда тикет #7 готов).",
            "Запускается в `/review` после deterministic gates.",
            "Output: structured list of findings с severity/location/anti-pattern-ref.",
        ],
        non_goals="НЕ дублирует security-reviewer; НЕ выполняет functional code review.",
        references="Принцип 2, Brooks McMillin Defense in Depth, Anthropic Code Review (code.claude.com/docs/en/code-review).",
    ),
    dict(
        num=7, priority="P0", estimate="S",
        title="feat(knowledge): docs/anti-patterns.md as accumulator artifact",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[4],
        depends_on=[],
        duplicate_of=None,
        problem="Оператор ловит lazy-режимы intra-session, но не накапливает. Каждая новая сессия начинается без контекста прошлых ловок. Принцип 4 нарушен. Прецедент: Arcanum-Sec/sec-context (Jason Haddix) поддерживает ANTI_PATTERNS_BREADTH/DEPTH специально для LLM-consumption.",
        acceptance=[
            "`docs/anti-patterns.md` создан с заголовками: «Pattern», «Frequency», «Severity», «Detector», «Example», «Fix».",
            "Initial seed: 5-10 anti-patterns из последних 8 дней работы (truncated files, hedging in plan.md, ADR drift, etc.).",
            "Ranking formula: `Frequency*2 + Severity*2 + Detectability` (per Arcanum-Sec model).",
            "adversarial-critic (тикет #6) грузит этот файл в context.",
            "Pre-commit hook: при каждом manual catch — добавление в anti-patterns.md в том же commit'е (governance rule, enforced via /audit-pass).",
        ],
        non_goals="НЕ замена ADR; НЕ exhaustive list — only patterns observed in repo.",
        references="Принцип 4. Arcanum-Sec/sec-context, honnibal/claude-skills, Brooks McMillin CLAUDE.md anti-patterns section.",
    ),
    dict(
        num=8, priority="P0", estimate="S",
        title="chore(adr): ADR retirement process with 90-day staleness audit",
        labels=["type:adr", "principle:gate-roi"],
        principles=[4],
        depends_on=[],
        duplicate_of=None,
        problem="20 ADR за 8 дней. Без retirement criteria каждый MADR-файл становится noise. Принцип 4 нарушается через противоположный механизм — слишком много знания.",
        acceptance=[
            "`/adr-retirement-audit` skill: weekly cron, по каждому ADR проверяет (a) 90 days no-incoming-refs, (b) underlying tech присутствует в `pyproject.toml`/`package.json`/`go.mod`, (c) `superseded-by` chain consistency.",
            "Output: список с recommendations `keep | mark-deprecated | mark-superseded`.",
            "Append-only: status field updated в YAML frontmatter, content не редактируется.",
            "ADR template обновлён: explicit `status` enum (proposed/accepted/deprecated/superseded), `superseded-by`, `last-referenced-sha`.",
            "Первый pass: 2-3 ADR из 20 retiring (proof).",
        ],
        non_goals="НЕ delete ADR file; НЕ автоматический tagging без human approval.",
        references="Принцип 4. Nygard 2011 «Documenting Architecture Decisions», MADR 4.0 spec, GDS Way ADR practice, kschlt/adr-kit (для будущей P2 интеграции).",
    ),
    # ============================ P1 (12) ============================
    dict(
        num=9, priority="P1", estimate="M",
        title="feat(forge): forge.sh wrapper abstracting gh for GitHub/Gitea/Forgejo/GitLab",
        labels=["principle:agnostic", "type:bootstrap"],
        principles=[7],
        depends_on=[],
        duplicate_of=None,
        problem="GitHub — medium vendor-lock risk (per matrix). Forge.sh wrapper preventively. Migration на Gitea/Forgejo/GitLab за час — это test для принципа 7. Прецедент: Leleat/git-forge (Rust); shell-wrapper greenfield.",
        acceptance=[
            "`bin/forge.sh` поддерживает `forge issue create`, `forge issue list`, `forge pr open`, `forge pr merge`, `forge release tag`.",
            "Под капотом: `FORGE_PROVIDER` env-переменная (`github` default, `gitea`, `gitlab`, `forgejo`).",
            "Driver-pattern: `forge-driver-github.sh`, `forge-driver-gitea.sh` (минимум первый, остальные stub).",
            "`/task-to-issue`, `/issue-to-task`, `/feature` мигрированы на forge.sh.",
            "Migration test: создаётся scratch Gitea instance в Docker, тикет создаётся через forge.sh с `FORGE_PROVIDER=gitea` без правок caller-кода.",
        ],
        non_goals="НЕ покрытие projects-v2, actions, gists; НЕ wrapper над `gh auth login`.",
        references="Принцип 7. Leleat/git-forge, AGENTS.md / Linux Foundation AAIF.",
    ),
    dict(
        num=10, priority="P1", estimate="S",
        title="feat(agnostic): AGENTS.md + CLAUDE.md duality migration",
        labels=["principle:agnostic", "type:bootstrap"],
        principles=[7],
        depends_on=[],
        duplicate_of=None,
        problem="AGENTS.md теперь под Linux Foundation AAIF (декабрь 2025), читается Codex CLI, Goose, opencode, Aider, Cursor, Devin, Jules. CLAUDE.md — Claude-specific dialect. Шипить оба.",
        acceptance=[
            "`AGENTS.md` создан, содержит generic instructions (репо структура, test/build/run, Conventional Commits).",
            "`CLAUDE.md` переписан как stub с `@AGENTS.md` import + Claude-специфичные skills/agents/hooks references.",
            "Обоих pet-проекта мигрированы.",
            "README.md документирует duality для maintainer.",
        ],
        non_goals="НЕ полный rewrite content; НЕ дублирование instructions.",
        references="Принцип 7. agents.md/, AAIF announcement, opencode docs (читает AGENTS.md + CLAUDE.md fallback).",
    ),
    dict(
        num=11, priority="P1", estimate="M",
        title="feat(continuity): STATE.md + session-log + plan.md triple hand-off contract",
        labels=["principle:continuity", "type:bootstrap"],
        principles=[9],
        depends_on=[3],
        duplicate_of=None,
        problem="Принцип 9 требует test «human resume в 5 min от LLM-stop». Сейчас plan.md drifts (gap 1), session-log не структурирован, STATE.md не существует. Тройной hand-off — STATE.md (snapshot, ≤200 lines), session-log (append-only daily), plan.md (regenerable).",
        acceptance=[
            "`STATE.md` template: `session_id, date_iso, current_branch, last_commit_sha, active_feature_run_id, next_3_actions, blocked_on, open_questions, risk_flags`.",
            "`session-log/YYYY/MM/YYYY-MM-DD.md` append-only.",
            "`plan.md` linter: каждое design-decision имеет ADR-ref (fixes gap 1).",
            "Resume drill: оператор симулирует «LLM unavailable, новый dev приходит на репо» — test passing если onboarding-task закрывается за 1-2 часа.",
            "Stop-hook (тикет #3) обновляет STATE.md.",
        ],
        non_goals="НЕ Beads integration (P2); НЕ замена git log.",
        references="Принцип 9. Anthropic CLAUDE.md/MEMORY.md docs, Cline memory bank, claudefa.st auto-dream.",
    ),
    dict(
        num=12, priority="P1", estimate="S",
        title="feat(audit): /audit-pass skill for human-authored ticket supervisory re-pass",
        labels=["principle:continuity", "type:bootstrap"],
        principles=[9],
        depends_on=[],
        duplicate_of=None,
        problem="Human-authored tickets (то что оператор пишет руками между LLM-сессиями) не проходят тот же quality gate, что LLM-генерируемые. Asymmetric continuity (принцип 9) фиксирует это через supervisory re-pass — НЕ блокирует, а лифтит.",
        acceptance=[
            "`.claude/skills/audit-pass/SKILL.md` принимает ticket markdown.",
            "Проверяет structural completeness: title (CC-compatible), priority, labels, problem statement, AC (≥3 testable), non-goals, references (principle ref obligatory), estimate (S/M/L).",
            "Output: diff suggestions, не auto-edit.",
            "Human accept-or-reject через `gh issue edit` или manual.",
            "Documented usage in `docs/skills/audit-pass.md`.",
        ],
        non_goals="НЕ auto-edit; НЕ блокирование create.",
        references="Принцип 9.",
    ),
    dict(
        num=13, priority="P1", estimate="L",
        title="refactor(domain): split domain layer into meta-pipeline vs per-project",
        labels=["principle:domain", "type:adr"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="Текущий `docs/domain/` описывает pipeline как domain. Domain inversion: pet-проекты имеют свои домены, метa-pipeline отдельный. Verraes (август 2025) подтверждает: домены и BC не маппятся 1-к-1.",
        acceptance=[
            "`docs/domain/meta/` — pipeline BC (FeatureRun, GovernanceRun, TwoVoiceReview, RunbookExecution).",
            "`docs/domain/<project>/` для каждого pet-проекта; archi2likec4 имеет свои аггрегаты (C4-Diagram, ContainerLayer).",
            "`docs/domain/context-map.md` — Mermaid с ACL-стрелками между meta и target.",
            "ACL implementation: один Python модуль, валидирующий artifacts из pet-проекта против meta-schema.",
            "ADR-XXXX «Domain Inversion: Meta vs Target Bounded Contexts» документирует решение.",
        ],
        non_goals="НЕ полный DDD strategic design для каждого pet-проекта (только если domain-rich — archi2likec4 yes, news-digest borderline).",
        references="Принцип 8. Verraes 2025 «Domains and BCs Don't Map 1 on 1», Eric Evans DDD Europe 2025, Synpulse8 AACL pattern.",
    ),
    dict(
        num=14, priority="P1", estimate="M",
        title="refactor(skills): convert slash commands to Claude Code Skills format",
        labels=["principle:agnostic", "type:bootstrap"],
        principles=[6],
        depends_on=[],
        duplicate_of=None,
        problem="Skills (релиз октябрь 2025, Open Standard декабрь 2025) — autoloaded by description matching, progressive disclosure, bundled scripts. Slash commands — manual-only injection. Migration: те команды что выигрывают от autoload (`/qa`, `/review`, `/backlog-review`, `/project-health`).",
        acceptance=[
            "`.claude/skills/qa/SKILL.md`, `.claude/skills/review/SKILL.md`, `.claude/skills/backlog-review/SKILL.md`, `.claude/skills/project-health/SKILL.md` созданы.",
            "Side-effecting (`/implement`, `/task-to-issue`, `/issue-to-task`) остаются как commands ИЛИ переведены с `disable-model-invocation: true`.",
            "Each SKILL.md ≤500 lines; heavy reference content в `references/` subdirectory.",
            "Deterministic steps вынесены в `scripts/*.{py,sh}`.",
            "Skill-creator skill используется для validation.",
        ],
        non_goals="НЕ migration `/feature` master orchestrator (он остаётся командой).",
        references="Принцип 6. code.claude.com/docs/en/skills, anthropics/skills repo.",
    ),
    dict(
        num=15, priority="P1", estimate="M",
        title="feat(verifier): third voice on open-weight (Kimi K2.6 / DeepSeek V4 / Qwen3-Coder)",
        labels=["principle:agnostic", "principle:lazy-detection"],
        principles=[2, 7],
        depends_on=[],
        duplicate_of=None,
        problem="Two-voice review (Claude /review + Codex /codex-review) проседает когда Codex недоступен (graceful-degradation в type:deferred-review). Третий голос на open-weight даёт пол. Cross-family мандатна (intra-family panels reinforce bias, не cancel — Panickssery 2024, EMNLP 2025).",
        acceptance=[
            "`.claude/skills/third-voice-review/SKILL.md` интегрируется через OpenRouter / Ollama local.",
            "Default model: Kimi K2.6 (Tier-A Akita benchmark, 89.3 coding) ИЛИ Qwen3-Coder-Next-80B-A3B локально.",
            "Запускается когда Codex unavailable ИЛИ оператор явно вызвал.",
            "Minority-veto strategy: любой из трёх блокирует — блок (per arxiv 2510.11822).",
            "Position bias mitigation: swap-and-rejudge на critical findings.",
        ],
        non_goals="НЕ заменяет Codex; НЕ training/fine-tuning open-weight.",
        references="Принципы 2, 7. arxiv 2510.11822 minority-veto, Akita benchmark, magazine.sebastianraschka.com open-weight 2026.",
    ),
    dict(
        num=16, priority="P1", estimate="S",
        title="feat(verifier): /intent-check skill (acceptance criteria vs diff alignment)",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[1, 2],
        depends_on=[],
        duplicate_of=None,
        problem="LLM имплементирует «around the AC» — диф решает похожую задачу, но не ту. /intent-check skill сравнивает AC из тикета и diff из feature branch и репортит mismatch.",
        acceptance=[
            "Skill принимает `<issue-id>` и текущий branch.",
            "Loads acceptance criteria from `gh issue view`.",
            "Compares against `git diff main...HEAD`.",
            "Output: list of AC items с status `covered | partial | missing | unrelated-changes`.",
            "Запускается в `/feature` finalization step и в `/review`.",
        ],
        non_goals="НЕ semantic test gen; НЕ замена manual review.",
        references="Принципы 1, 2.",
    ),
    dict(
        num=17, priority="P1", estimate="M",
        title="chore(verifier): mutation testing weekly cron (mutmut/Stryker/cargo-mutants)",
        labels=["principle:lazy-detection", "principle:antifragile"],
        principles=[3, 8],
        depends_on=[7],
        duplicate_of=None,
        problem="Per-PR mutation testing — антипаттерн (Pitest author, Google 2102.11378). Weekly cron на main с `--in-diff` для инкрементального режима. Mutation score target 80%, gate 60%.",
        acceptance=[
            "`.github/workflows/mutation.yml` с `cron: '0 0 * * 0'` (sunday 00:00 UTC).",
            "Python: mutmut v3+ с `--paths-to-mutate src/`, mypy-фильтр невалидных мутантов.",
            "TS/JS: Stryker с `break: 50, low: 60, high: 80`.",
            "Rust: cargo-mutants с `--in-diff`.",
            "Output: SARIF report uploaded; markdown summary в issue с label `type:mutation-report`.",
            "Surviving mutants добавляются в `docs/anti-patterns.md` (тикет #7) если pattern repeats.",
        ],
        non_goals="НЕ per-PR run; НЕ полный mutation на каждом push.",
        references="Принципы 3, 8. arxiv 2308.16557 (MuTAP), arxiv 2506.02954 (MutGen), Google arxiv 2102.11378, Pitest blog.",
    ),
    dict(
        num=18, priority="P1", estimate="M",
        title="chore(governance): DoD compliance table — prune honor-only norms, automate",
        labels=["principle:gate-roi", "type:bootstrap"],
        principles=[1, 8],
        depends_on=[5],
        duplicate_of=None,
        problem="8 of 14 DoD норм honor-system. Принцип 1 нарушен в ядре. Каждая норма — либо mechanical enforcer, либо явная пометка `honor-only — known gap` + ticket в P1/P2.",
        acceptance=[
            "`docs/domain/overview.md` compliance table обновлена: каждая норма имеет колонку `enforcer` (path to hook/CI/skill) или `honor-only — see #ticket`.",
            "4 of 8 honor-only converted в mechanical (hooks, CI checks, ADR-Kit policy blocks).",
            "Остальные 4 имеют tickets в P2 backlog.",
            "Weekly /gate-audit (тикет #5) включает DoD compliance в ROI calculation.",
        ],
        non_goals="НЕ 100% mechanisation (некоторые нормы fundamentally honor-only — e.g. «author truly understood why»).",
        references="Принципы 1, 8. Принцип-9 supervisory re-pass.",
    ),
    dict(
        num=19, priority="P1", estimate="S",
        title="feat(verifier): semgrep rules for hedging-words and corporate-softening in plan.md",
        labels=["principle:lazy-detection", "type:bootstrap"],
        principles=[1],
        depends_on=[],
        duplicate_of=None,
        problem="Gap 4 (banned terms in plan.md). Принцип 1 («размытость — нарушение») requires mechanical detection of hedging language: `maybe`, `possibly`, `depends`-without-branching-condition, «could», «might», «perhaps».",
        acceptance=[
            "`.semgrep/hedging.yml` rules с regex'ами на banned terms в `plan.md`, `STATE.md`, `docs/decisions/*.md`.",
            "Pre-commit hook вызывает semgrep на staged markdown files.",
            "`depends` allowed только если followed by «when X then Y, when Z then W» branching.",
            "False-positive review process: добавление в `.semgrepignore` с reason-comment.",
        ],
        non_goals="НЕ generic prose-linter; НЕ грамматика.",
        references="Принцип 1.",
    ),
    dict(
        num=20, priority="P1", estimate="M",
        title="chore(security): MCP transport hardening + pin versions + Stacklok ToolHive evaluation",
        labels=["principle:agnostic", "prod-bound"],
        principles=[7],
        depends_on=[],
        duplicate_of=None,
        problem="CVE-2026-27825 (MCPwnfluence, sooperset/mcp-atlassian, февраль 2026, CVSS 9.1) + 10 systemic CVE в Anthropic MCP SDK stdio transport (OX Security, апрель 2026) — MCP больше не low-risk slot. Bank context требует hardening.",
        acceptance=[
            "Все MCP servers в `.claude/mcp.json` pinned by version (semver, не latest).",
            "stdio transport для local (Serena, Context7); HTTP только с allowlist + bind 127.0.0.1.",
            "Stacklok ToolHive evaluated (off-the-shelf MCP isolation/network restriction).",
            "Quarterly review: CVE check всех installed MCP servers.",
            "ADR-XXXX «MCP Transport Security» документирует policy.",
        ],
        non_goals="НЕ полный MCP server audit (CVE check только); НЕ написание собственного MCP isolation.",
        references="Принцип 7. CVE-2026-27825, OX Security disclosure (thehackernews 2026/04), Stacklok ToolHive, modelcontextprotocol.io security_best_practices.",
    ),
    # ============================ P2 (12) ============================
    dict(
        num=21, priority="P2", estimate="M",
        title="feat(adr): ADR Kit MCP integration",
        labels=["type:adr", "principle:gate-roi"],
        principles=[4],
        depends_on=[8],
        duplicate_of=None,
        problem="kschlt/adr-kit предоставляет MCP server (`adr_preflight`, `adr_create`, `adr_approve`, `adr_analyze_project`), policy block в YAML frontmatter автогенерирует ESLint/Ruff правила, staged git hooks. Это operationalises «knowledge in repo».",
        acceptance=[
            "adr-kit установлен и настроен в `.claude/mcp.json`.",
            "Существующие 20 ADR мигрированы в формат с policy blocks где applicable.",
            "semantic search loads 3-5 relevant ADRs в agent context на каждом feature-run.",
            "Pre-commit <5s import-restriction hook включён.",
            "Pre-push <15s architecture-boundary hook.",
        ],
        non_goals="НЕ rewriting ADR content; НЕ замена MADR 4.0.",
        references="Принцип 4. github.com/kschlt/adr-kit.",
    ),
    dict(
        num=22, priority="P2", estimate="M",
        title="feat(verifier): Schemathesis for any HTTP surface in pet-projects",
        labels=["principle:antifragile", "principle:lazy-detection"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="news-digest bot имеет HTTP surface (если webhook). Schemathesis (v4.16.1, апрель 2026) — drop-in OpenAPI fuzzing на Hypothesis engine; phases examples → coverage → fuzzing → stateful.",
        acceptance=[
            "Schemathesis установлен в каждом проекте с HTTP surface.",
            "pytest integration: `schema.parametrize()` decorator.",
            "CI workflow: `schemathesis/action@v3` с `examples + coverage + fuzzing` phases.",
            "Stateful только если OpenAPI spec имеет links.",
            "Bounded `--max-examples=200` для CI runtime.",
        ],
        non_goals="НЕ для проектов без HTTP API.",
        references="Принцип 8. schemathesis.io.",
    ),
    dict(
        num=23, priority="P2", estimate="S",
        title="feat(release): GitHub native auto-merge for trivial PRs",
        labels=["principle:gate-roi"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="Trivial PRs (dependabot patches, format-only commits) проходят через manual merge — налог на внимание без ROI.",
        acceptance=[
            "GitHub repo settings: auto-merge enabled.",
            "`.github/workflows/auto-merge-trivial.yml`: matcher на `dependabot/`, `chore: format`, `chore: lint-fix` labels.",
            "Все CI gates должны pass.",
            "Логируется в /gate-audit (тикет #5) как «auto-merge: 12 PRs/week».",
        ],
        non_goals="НЕ auto-merge feature PRs; НЕ skip review.",
        references="Принцип 8 operational rule.",
    ),
    dict(
        num=24, priority="P2", estimate="M",
        title="feat(operability): OpenFeature flags via flagd file-based provider",
        labels=["principle:antifragile"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="Pet-проекты с пользователями (если/когда) нуждаются в kill-switch и feature flags. OpenFeature CNCF-incubating, file-based flagd — solo-friendly.",
        acceptance=[
            "flagd container или local binary с `flags.flagd.json`.",
            "Python/TS SDK интегрирован.",
            "1-2 feature flags активных в одном pet-проекте как proof.",
            "ADR-XXXX «Feature Flags via OpenFeature flagd».",
        ],
        non_goals="НЕ adoption если у проекта 0 пользователей; НЕ percentage rollouts.",
        references="Принцип 8 (depth-by-criticality). openfeature.dev, flagd CNCF.",
    ),
    dict(
        num=25, priority="P2", estimate="M",
        title="feat(backlog): /backlog-grooming agent with ICE/RICE scoring",
        labels=["type:bootstrap", "principle:gate-roi"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="Текущий backlog-groomer не ranks тикеты. ICE (Impact*Confidence*Ease) или RICE (Reach*Impact*Confidence/Effort) даёт numeric priority signal.",
        acceptance=[
            "`/backlog-review` skill добавляет ICE-score (1-10 на dimension) к каждому open issue.",
            "Output: ranked list `gh issue list --json` + computed score.",
            "Manual override через ticket label `priority:override`.",
            "Weekly /project-health включает ICE-distribution.",
        ],
        non_goals="НЕ авто-prioritisation merge; НЕ замена P0/P1/P2/P3.",
        references="Принцип 8 operational rule.",
    ),
    dict(
        num=26, priority="P2", estimate="S",
        title="refactor(ddd): aggressive DDD retirement audit at solo scale",
        labels=["principle:domain", "type:adr"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="DDD на solo масштабе pet-project pipeline meta — overhead concern (user explicitly flagged). Если 3 aggregates (FeatureRun, GovernanceRun, TwoVoiceReview) не несут domain-rich behaviour beyond CRUD — retire to scripts.",
        acceptance=[
            "Each aggregate audited: behaviour ≥ 3 non-trivial invariants? Lifecycle ≥ 3 states? Если нет — retire.",
            "Retired aggregates → simple modules.",
            "ADR-XXXX «DDD Retirement Audit» документирует решения per-aggregate.",
            "`docs/domain/meta/` обновлён.",
        ],
        non_goals="НЕ retire без evidence; НЕ touch per-project domain layers (тикет #13).",
        references="Принцип 8. Tony Marston critique, HN 2024 DDD discussion.",
    ),
    dict(
        num=27, priority="P2", estimate="M",
        title="feat(observability): structured JSON logs + OTel auto-instrumentation in pet-projects",
        labels=["principle:antifragile"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="7-ilities gate включает observability. Текущие pet-проекты — print-debugging. JSON logger + trace_id/span_id + OTel SDK auto-instrumentation в один backend (Honeycomb free tier или local OTel collector).",
        acceptance=[
            "structlog (Python) или pino (Node) с JSON format.",
            "OTel SDK initialised; trace_id propagation через requests.",
            "One backend connected (Honeycomb free / local OTel collector → SQLite).",
            "SLO `slo.md` с 1-2 SLI per project.",
        ],
        non_goals="НЕ full Datadog stack; НЕ multi-pillar.",
        references="Принцип 8. Charity Majors observability 2.0, honeycomb.io blog 2025.",
    ),
    dict(
        num=28, priority="P2", estimate="M",
        title="feat(security): supply-chain table-stakes (SLSA L2, cosign, gitleaks)",
        labels=["principle:antifragile", "prod-bound"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="2025 GhostAction npm/Actions compromises = baseline shifted. Dependabot, gitleaks, cosign keyless OIDC, SLSA L2 provenance — minimum.",
        acceptance=[
            "Dependabot enabled на обоих pet-проектах.",
            "gitleaks pre-commit hook + GitHub native secret scanning.",
            "Release workflow: `cosign sign --yes` + `actions/attest-build-provenance`.",
            "Pinned actions by SHA (не by tag).",
            "ADR-XXXX «Supply Chain Baseline».",
        ],
        non_goals="НЕ SLSA L3 hermetic builders; НЕ internal Fulcio/Rekor.",
        references="Принцип 8. AquilaX 2025 SLSA L2, OpenSSF guidance, sigstore/cosign docs.",
    ),
    dict(
        num=29, priority="P2", estimate="S",
        title="feat(continuity): runbook.md + restore drill weekly cron",
        labels=["principle:antifragile", "principle:continuity"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="Recoverability gate — 7-ility minimum. Currently no runbook, no restore drill. RPO=24h, RTO=1h declared.",
        acceptance=[
            "`runbook.md` per project with copy-pasteable restore commands.",
            "Weekly cron: restore last backup в scratch container, assert row counts / fixture data integrity.",
            "Failed restore → P0 incident issue auto-created.",
        ],
        non_goals="НЕ multi-region replication; НЕ PITR.",
        references="Принцип 8. Google SRE Book Ch.4.",
    ),
    dict(
        num=30, priority="P2", estimate="M",
        title="feat(stpa): one-time STPA hazard pass on pipeline",
        labels=["principle:antifragile", "type:adr"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="STPA Handbook (Leveson, MIT 2018) generic фреймворк. One-time pass даёт hazard list, маппящийся в hooks (PreToolUse denylist) и runbooks. Не повторять regularly; пересматривать при architecture change.",
        acceptance=[
            "`docs/stpa/hazard-analysis.md`: Losses → Hazards → Control Structure → UCAs → Loss Scenarios.",
            "5-10 UCAs identified (e.g., «agent provides `git push --force` on main»).",
            "Each UCA mapped to existing or new hook/control.",
            "ADR-XXXX «STPA Pipeline Hazard Analysis».",
        ],
        non_goals="НЕ ongoing STPA audits; НЕ formal safety-case.",
        references="Принцип 8. Leveson STPA Handbook 2018 (psas.scripts.mit.edu).",
    ),
    dict(
        num=31, priority="P2", estimate="S",
        title="chore(governance): semgrep multimodal evaluation as deterministic-LLM hybrid",
        labels=["principle:lazy-detection"],
        principles=[3],
        depends_on=[],
        duplicate_of=None,
        problem="Semgrep Multimodal (март 2026) — rule-based + LLM reasoning hybrid; Cursor/Claude Code plugin available. Может заменить часть adversarial-critic'а на детерминистическом slot.",
        acceptance=[
            "Evaluated на одном pet-проекте за 1 неделю.",
            "Comparison report: Semgrep Multimodal vs adversarial-critic findings (precision, recall, false-positive rate).",
            "Decision: adopt | reject | hybrid; ADR-XXXX документирует.",
        ],
        non_goals="НЕ replace adversarial-critic without evidence; НЕ paid tier.",
        references="Принцип 3. helpnetsecurity.com 2026/03/20 Semgrep Multimodal.",
    ),
    dict(
        num=32, priority="P2", estimate="M",
        title="feat(continuity): Beads (Yegge) trial as plan.md replacement",
        labels=["principle:continuity"],
        principles=[9],
        depends_on=[11],
        duplicate_of=None,
        problem="plan.md drifts. Beads (Steve Yegge, ~18K stars, v0.59 март 2026) — git-backed graph issue tracker для агентов; решает «50 First Dates» problem. Agent-agnostic; читается через CLAUDE.md / AGENTS.md instruction.",
        acceptance=[
            "Beads установлен, `.beads/` initialized в одном pet-проекте.",
            "1-2 weeks trial: plan.md заменён `bd ready --json` output.",
            "AGENTS.md instructs agent: «Use `bd` for task tracking».",
            "Comparison: drift incidents pre vs post.",
            "Decision adopt/reject + ADR-XXXX.",
        ],
        non_goals="НЕ replace STATE.md или session-log; НЕ migrate на Beads если drift не уменьшился.",
        references="Принцип 9. github.com/steveyegge/beads, Yegge launch essay Oct 2025.",
    ),
    # ============================ P3 (8) ============================
    dict(
        num=33, priority="P3", estimate="L",
        title="chore(sandbox): microVM sandbox evaluation (e2b/Daytona) — defer until needed",
        labels=["principle:antifragile"],
        principles=[8],
        depends_on=[],
        duplicate_of=None,
        problem="E2B ($150/mo Pro), Daytona (open-source, Docker default + Kata optional). Worth когда: third-party code, unattended overnight runs, parallel critic agents в worktrees. Currently — local + git checkpointing + PreToolUse denylist даёт 95% safety на 0% cost.",
        acceptance=[
            "trigger conditions documented.",
            "Re-evaluate quarterly.",
        ],
        non_goals="НЕ adopt без trigger.",
        references="Принцип 8 (overengineering failure mode).",
    ),
    dict(
        num=34, priority="P3", estimate="M",
        title="chore(acp): ACP broker support (Zed/JetBrains) — defer",
        labels=["principle:agnostic"],
        principles=[7],
        depends_on=[],
        duplicate_of=None,
        problem="ACP (Agent Client Protocol, Zed/JetBrains co-developed) реален и зрел; ACP Registry январь 2026. Useful когда нужна IDE-grade diff review.",
        acceptance=[
            "trigger documented («когда terminal UI Claude Code станет недостаточным»).",
        ],
        non_goals="",
        references="Принцип 7. agentclientprotocol.com.",
    ),
    dict(
        num=35, priority="P3", estimate="L",
        title="research(verifier): custom-trained discriminator for lazy-pattern detection",
        labels=["principle:lazy-detection"],
        principles=[4],
        depends_on=[7],
        duplicate_of=None,
        problem="Long-shot. Train small model (≤7B) на собственном corpus anti-patterns.md как discriminator для lazy-detection. Worth только если anti-patterns.md накопит ≥500 examples и adversarial-critic precision/recall plateau.",
        acceptance=[
            "trigger conditions documented.",
        ],
        non_goals="",
        references="Принцип 4.",
    ),
    dict(
        num=36, priority="P3", estimate="L",
        title="research(optimizer): DSPy для core skill prompts — defer",
        labels=["principle:lazy-detection"],
        principles=[],
        depends_on=[],
        duplicate_of=None,
        problem="DSPy worth когда (a) measurable metric, (b) eval set ≥50, (c) stable task ≥1000s calls. Сейчас pet-проекты one-shot. Defer до eval set готов.",
        acceptance=[
            "trigger documented.",
        ],
        non_goals="",
        references="Towards Data Science 2025 DSPy review.",
    ),
    dict(
        num=37, priority="P3", estimate="M",
        title="chore(adr): structured-madr / git-adr migration evaluation",
        labels=["type:adr"],
        principles=[4],
        depends_on=[21],
        duplicate_of=None,
        problem="zircote/structured-madr добавляет JSON Schema validation, GitHub Action, three-dimension risk assessment. Companion git-adr хранит в git notes (no merge conflicts). Эвалюируется после adr-kit (тикет #21) on production.",
        acceptance=[
            "comparison adr-kit vs structured-madr; decision documented.",
        ],
        non_goals="",
        references="github.com/zircote/structured-madr.",
    ),
    dict(
        num=38, priority="P3", estimate="S",
        title="chore(runtime): quarterly Claude Code vendor-monitor — formalised",
        labels=["principle:agnostic"],
        principles=[7],
        depends_on=[],
        duplicate_of=None,
        problem="Claude Code = high vendor-lock risk. Quarterly check: Akita / BenchLM benchmarks, breaking changes Claude Code, ACP Registry новые agents, opencode growth, open-weight progress (Kimi/Qwen/DeepSeek).",
        acceptance=[
            "quarterly cron issue auto-created с template.",
            "output `docs/vendor-watch/YYYY-Q.md`.",
        ],
        non_goals="",
        references="Принцип 7.",
    ),
    dict(
        num=39, priority="P3", estimate="S",
        title="chore(docs): 1h onboarding traps test (continuity)",
        labels=["principle:continuity"],
        principles=[4, 9],
        depends_on=[7],
        duplicate_of=None,
        problem="Тест принципа 4 («1h onboarding includes typical traps») — формализовать. Hypothetical new dev приходит на репо, проходит `docs/onboarding.md`, через 1h может (a) запустить `/feature` end-to-end on trivial task, (b) перечислить 3 anti-patterns из anti-patterns.md.",
        acceptance=[
            "`docs/onboarding.md` написан.",
            "quarterly drill — оператор просит ChatGPT-with-no-context пройти onboarding и репортит gaps.",
        ],
        non_goals="",
        references="Принципы 4, 9.",
    ),
    dict(
        num=40, priority="P3", estimate="L",
        title="research(verifier): multi-judge calibration with regression bias correction (arxiv 2510.11822)",
        labels=["principle:lazy-detection"],
        principles=[2],
        depends_on=[5],
        duplicate_of=None,
        problem="arxiv 2510.11822 предлагает regression-based bias correction с small (~30-100) human-annotated calibration set. Worth когда two-voice review накопит ≥100 human-tagged judgments из /gate-audit.",
        acceptance=[
            "trigger conditions documented.",
            "corpus build начат через manual tagging в /gate-audit (тикет #5).",
        ],
        non_goals="",
        references="Принцип 2. arxiv 2510.11822, Lin Shi et al. IJCNLP 2025 position bias.",
    ),
    # ============================ Post-handoff addition (operator directive 2026-04-29) ============================
    dict(
        num=41, priority="P1", estimate="S",
        title="chore(docs): migrate DoD/ADR-trigger/advisor-policy from principles.md to runbooks",
        labels=["type:chore", "type:runbook", "area:docs", "adr-followup"],
        principles=[],
        depends_on=[],
        duplicate_of=None,
        problem="DRAFT принципов (issue #117) удаляет три секции из текущего `docs/principles.md`: «Definition of Done» (14-item checklist), «Что значит архитектурно-значимо» (ADR-trigger), «Что значит нетривиальная задача» (advisor×2 trigger). Эти секции — operational rules, не principles, и должны переехать в runbooks. CLAUDE.md hard rule 6 и `.github/pull_request_template.md` ссылаются на anchored sections — без миграции anchors сломаются после мерджа #117. Этот тикет добавлен post-handoff по указанию оператора (2026-04-29); не входит в synthesis раздел B.",
        acceptance=[
            "`docs/runbooks/dod-checklist.md` создан, содержит 14-item DoD checklist verbatim из текущего `docs/principles.md`.",
            "`docs/runbooks/adr-trigger.md` создан, содержит критерии «архитектурно-значимо» verbatim.",
            "`docs/runbooks/advisor-policy.md` создан, содержит критерии «нетривиальная задача» (advisor × 2 trigger) verbatim.",
            "`CLAUDE.md` обновлён: ссылка `docs/principles.md#definition-of-done` → `docs/runbooks/dod-checklist.md`; hard rule 6 (advisor policy) → `docs/runbooks/advisor-policy.md`.",
            "`.github/pull_request_template.md` обновлён: DoD-блок заменён на ссылку (или regenerated copy) на `docs/runbooks/dod-checklist.md`.",
            "ADR на принципы (issue #117) ссылается на эти runbooks как destination для удалённых секций — добавляется в Decision Outcome.",
            "`solutions-architect` agent prompt (если содержит ADR-trigger criteria inline) обновлён ссылкой на `docs/runbooks/adr-trigger.md`.",
        ],
        non_goals="НЕ изменять содержание DoD/ADR-trigger/advisor-policy при переносе (verbatim copy). НЕ автоматизация enforcement (covered ticket 18). НЕ создание новых правил.",
        references="Operator directive 2026-04-29 после handoff. REPORT.md §4 (gap closed by this ticket). Issue #117 (ADR на принципы). Ticket 18 (DoD compliance prune — automation, не migration).",
    ),
]

assert len(TICKETS) == 41, f"expected 41 tickets, got {len(TICKETS)}"
nums = [t["num"] for t in TICKETS]
assert nums == list(range(1, 42)), nums


def fmt_ac_checklist(items: list[str]) -> str:
    return "\n".join(f"- [ ] {i}" for i in items)


def fmt_principles(nums: list[int]) -> str:
    if not nums:
        return "—"
    return ", ".join(f"#{n}" for n in nums)


def render_body(t: dict) -> str:
    title = t["title"]
    principle_refs = fmt_principles(t["principles"])
    ac = fmt_ac_checklist(t["acceptance"])
    deps = ", ".join(f"#{n}" for n in t["depends_on"]) if t["depends_on"] else "—"
    non_goals = t["non_goals"] or "—"
    refs = t["references"] or "—"
    refs_full = f"{refs}\n\nSynthesis: {SYNTHESIS_REF} (Раздел B, ticket #{t['num']}).\nPrinciples touched: {principle_refs}."

    return (
        f"# {title}\n\n"
        f"**Priority:** {t['priority']}\n"
        f"**Estimate:** {t['estimate']}\n"
        f"**Depends on (in this batch):** {deps}\n\n"
        f"## Problem statement\n\n"
        f"{t['problem']}\n\n"
        f"## Acceptance criteria\n\n"
        f"{ac}\n\n"
        f"## Non-goals\n\n"
        f"{non_goals}\n\n"
        f"## References\n\n"
        f"{refs_full}\n"
    )


def render_plan_entry(t: dict) -> str:
    title = t["title"]
    labels = ",".join(t["labels"])
    body_path = f".claude/scratch/handoff-2026-04-29/bodies/{t['num']:02d}.md"
    cmd = (
        f'gh issue create --title "{title}" '
        f'--label "{labels}" '
        f'--body-file {body_path}'
    )
    deps = ", ".join(f"#{n}" for n in t["depends_on"]) if t["depends_on"] else "—"
    dup = f"#{t['duplicate_of']}" if t["duplicate_of"] else "—"
    return (
        f"## Ticket {t['num']:02d} — {title}\n"
        f"- **priority:** {t['priority']}\n"
        f"- **estimate:** {t['estimate']}\n"
        f"- **principles:** {fmt_principles(t['principles'])}\n"
        f"- **labels (raw from synthesis):** {labels}\n"
        f"- **depends-on:** {deps}\n"
        f"- **duplicate-of:** {dup}\n"
        f"- **body-file:** `{body_path}`\n"
        f"- **gh-create-command:**\n"
        f"  ```bash\n"
        f"  {cmd}\n"
        f"  ```\n"
    )


def render_plan(tickets: list[dict]) -> str:
    header = (
        "# Backlog plan — handoff 2026-04-29\n\n"
        "40 тикетов из synthesis раздел B + 1 post-handoff ticket (#41) добавленный по указанию оператора. "
        "Источник synthesis без изменений: "
        "`docs/synthesis/2026-04-29-pipeline-restructuring.md` (после step 2 коммита оператора).\n\n"
        "**НЕ запускать `gh issue create` массово.** Оператор пройдёт через `/backlog-review` "
        "и решит, что создавать и в каком порядке. Команды ниже — заготовки.\n\n"
        "Перед массовым созданием — выполнить `bash .claude/scratch/handoff-2026-04-29/labels.sh` "
        "для создания отсутствующих labels (`principle:*`, `type:bootstrap`, `prod-bound`).\n\n"
        "---\n\n"
    )
    by_priority: dict[str, list[dict]] = {"P0": [], "P1": [], "P2": [], "P3": []}
    for t in tickets:
        by_priority[t["priority"]].append(t)
    sections = []
    for prio in ["P0", "P1", "P2", "P3"]:
        sections.append(f"## {prio} ({len(by_priority[prio])} tickets)\n\n")
        for t in by_priority[prio]:
            sections.append(render_plan_entry(t))
            sections.append("\n")
    return header + "".join(sections)


def main():
    for t in TICKETS:
        body = render_body(t)
        path = BODIES / f"{t['num']:02d}.md"
        path.write_text(body, encoding="utf-8")
    plan = render_plan(TICKETS)
    (ROOT / "backlog-plan.md").write_text(plan, encoding="utf-8")
    print(f"wrote {len(TICKETS)} body files to {BODIES}")
    print(f"wrote backlog-plan.md to {ROOT}")


if __name__ == "__main__":
    main()
