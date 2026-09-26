# Порядок реализации — Phase 2 backlog (handoff 2026-04-29)

Mapping ticket → GitHub issue из `issue-map.json`. Зависимости из `REPORT.md` §2 (extracted from synthesis text).

---

## Старт: можно брать любой из этих сейчас (P0, без зависимостей)

- #118 — ticket 01: feat(verifier): wire Hypothesis property-based testing into /qa skill
- #119 — ticket 02: feat(governance): PostToolUse hook for format+typecheck after Edit/Write
- #120 — ticket 03: feat(governance): Stop hook ensures tests pass before session end
- #121 — ticket 04: feat(verifier): static-analysis baseline (ruff/eslint/staticcheck/radon/jscpd)
- #122 — ticket 05: chore(governance): /gate-audit weekly skill with ROI schema
- #124 — ticket 07: feat(knowledge): docs/anti-patterns.md as accumulator artifact
- #125 — ticket 08: chore(adr): ADR retirement process with 90-day staleness audit

## Wave 2: после ticket 07 (#124)

- #123 — ticket 06: feat(critic): adversarial-critic agent with explicit lazy-mandate

---

## P1 — следующие 2-6 недель

### P1 unblocked (можно брать сразу или после соответствующих P0)
- #126 — ticket 09: feat(forge): forge.sh wrapper abstracting gh for GitHub/Gitea/Forgejo/GitLab
- #127 — ticket 10: feat(agnostic): AGENTS.md + CLAUDE.md duality migration
- #129 — ticket 12: feat(audit): /audit-pass skill for human-authored ticket supervisory re-pass
- #130 — ticket 13: refactor(domain): split domain layer into meta-pipeline vs per-project
- #131 — ticket 14: refactor(skills): convert slash commands to Claude Code Skills format
- #132 — ticket 15: feat(verifier): third voice on open-weight (Kimi K2.6 / DeepSeek V4 / Qwen3-Coder)
- #133 — ticket 16: feat(verifier): /intent-check skill (acceptance criteria vs diff alignment)
- #136 — ticket 19: feat(verifier): semgrep rules for hedging-words and corporate-softening in plan.md
- #137 — ticket 20: chore(security): MCP transport hardening + pin versions + Stacklok ToolHive evaluation
- #158 — ticket 41: chore(docs): migrate DoD/ADR-trigger/advisor-policy from principles.md to runbooks (post-handoff)

### P1 blocked
- #128 — ticket 11: feat(continuity): STATE.md + session-log + plan.md triple hand-off contract — depends on #120 (ticket 03 Stop-hook)
- #134 — ticket 17: chore(verifier): mutation testing weekly cron — depends on #124 (ticket 07 anti-patterns.md)
- #135 — ticket 18: chore(governance): DoD compliance table — prune honor-only norms — depends on #122 (ticket 05 /gate-audit)

---

## P2 — 1-3 месяца

### P2 unblocked
- #139 — ticket 22: feat(verifier): Schemathesis for any HTTP surface in pet-projects
- #140 — ticket 23: feat(release): GitHub native auto-merge for trivial PRs
- #141 — ticket 24: feat(operability): OpenFeature flags via flagd file-based provider
- #142 — ticket 25: feat(backlog): /backlog-grooming agent with ICE/RICE scoring
- #143 — ticket 26: refactor(ddd): aggressive DDD retirement audit at solo scale  ⚠ live conflict, см. §Conflict ниже
- #144 — ticket 27: feat(observability): structured JSON logs + OTel auto-instrumentation in pet-projects
- #145 — ticket 28: feat(security): supply-chain table-stakes (SLSA L2, cosign, gitleaks)
- #146 — ticket 29: feat(continuity): runbook.md + restore drill weekly cron
- #147 — ticket 30: feat(stpa): one-time STPA hazard pass on pipeline
- #148 — ticket 31: chore(governance): semgrep multimodal evaluation as deterministic-LLM hybrid

### P2 blocked
- #138 — ticket 21: feat(adr): ADR Kit MCP integration — depends on #125 (ticket 08 ADR retirement)
- #149 — ticket 32: feat(continuity): Beads (Yegge) trial as plan.md replacement — depends on #128 (ticket 11 STATE.md/session-log triple)

---

## P3 — defer / trigger conditions documented in bodies

### P3 unblocked
- #150 — ticket 33: chore(sandbox): microVM sandbox evaluation (e2b/Daytona)
- #151 — ticket 34: chore(acp): ACP broker support (Zed/JetBrains)
- #153 — ticket 36: research(optimizer): DSPy для core skill prompts
- #155 — ticket 38: chore(runtime): quarterly Claude Code vendor-monitor — formalised

### P3 blocked
- #152 — ticket 35: research(verifier): custom-trained discriminator for lazy-pattern detection — depends on #124 (ticket 07 anti-patterns.md)
- #154 — ticket 37: chore(adr): structured-madr / git-adr migration evaluation — depends on #138 (ticket 21 ADR Kit)
- #156 — ticket 39: chore(docs): 1h onboarding traps test (continuity) — depends on #124 (ticket 07 anti-patterns.md)
- #157 — ticket 40: research(verifier): multi-judge calibration with regression bias correction — depends on #122 (ticket 05 /gate-audit)

---

## Conflict (NOT block): живой

- **#143 ticket 26** (DDD retirement audit) vs **ADR-0020** (god-aggregate-sub-aggregate-extraction, accepted 2026-04-28). Operator directive 2026-04-29: «Конфликт прямой и осознанный. Ticket 26 при исполнении начинается с явного `superseded-by` или `partially-supersedes` apply к ADR-0020 через ADR-Kit retirement-протокол (тикет 8 туда же). Не закрывай конфликт сейчас, оставь как живой.» См. REPORT.md §5.

---

## Параллельные роли P0

Семь P0 unblocked + одно Wave-2 — все могут стартовать в любом порядке (или параллельно). Граф минимален: только #123 ждёт #124. Это сделано намеренно — стресс-тест на 7 параллельных независимых тикетов покажет здоровье pipeline'а.

Последовательность по operator strawman 2026-04-29 («Начни с P0 #1, #2, #3, #7»):
1. #118 (ticket 01) — Hypothesis в /qa
2. #119 (ticket 02) — PostToolUse hook
3. #120 (ticket 03) — Stop hook (разблокирует #128 ticket 11)
4. #124 (ticket 07) — anti-patterns.md (разблокирует #123 ticket 06, #134 ticket 17, #152 ticket 35, #156 ticket 39)
