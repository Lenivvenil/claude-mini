# Project plan — claude-mini

План первых 8 недель работы, трёх milestones, двенадцати issues. Генерируется из `create-backlog.sh`; актуальный статус — всегда на [GitHub milestones](https://github.com/Lenivvenil/claude-mini/milestones).

## Милestones и ритм

| Milestone | Window | Цель |
|---|---|---|
| **M0: baseline verified** | Week 1–2 (до 2026-05-05) | Убедиться что то, что уже задекларировано, реально работает |
| **M1: pipeline proven on real project** | Week 3–4 (до 2026-05-19) | Пройти полный pipeline end-to-end на живой задаче |
| **M2: enforcement hardened** | Week 5–8 (до 2026-06-16) | Закрыть известные gap'ы защиты и docs |

Каждый milestone — 4 issues, 2 недели. Ритм: ежедневная работа + пятничный `/project-health`.

## M0: baseline verified (4 issues, ~13 estimate points)

**Гипотеза:** то, что описано в `docs/` и `bootstrap/`, реально установлено и работает. Без проверки — это fiction.

| # | Title | Priority | Estimate | Зависит от |
|---|---|---|---|---|
| 1 | Verify universal-setup.sh idempotency on mini | P0 | 3 | — |
| 2 | Smoke-test governance hook with deliberately bad commits | P0 | 3 | — |
| 3 | Install missing universal artefacts on mini | P1 | 2 | #1 |
| 4 | Empirically confirm advisor Opus billing | P1 | 3 | #3 |

**Параллелизм:** #1 и #2 можно делать одновременно (разные компоненты). #3 требует #1. #4 требует #3 и несколько дней работы для repr. данных.

**Критерий завершения M0:** все 4 issues закрыты, baseline verified ADR не требует пересмотра, можно стартовать реальную работу.

## M1: pipeline proven on real project (4 issues, ~16 estimate points)

**Гипотеза:** pipeline умеет проводить реальную фичу от issue до merged PR без имитации этапов.

| # | Title | Priority | Estimate | Зависит от |
|---|---|---|---|---|
| 5 | First real feature through full pipeline end-to-end | P1 | 8 | M0 complete |
| 6 | Enrich onboarding-repo runbook from first real practice | P2 | 3 | #5 |
| 7 | Establish weekly /project-health rhythm | P2 | 2 | — |
| 8 | Verify two-voice review catches real miss (30-day window) | P2 | 3 | — (observational) |

**Параллелизм:** #5 — критический путь, остальное сверху. #7 и #8 начинаются сразу как M0 завершился. #6 ждёт первого полного прогона pipeline'а.

**Ключевой риск M1:** pipeline не взлетает end-to-end на первой задаче. В этом случае #5 сам превращается в эпик-родителя для gap-ов (каждый gap → новый issue, M1 extended).

**Критерий завершения M1:** один PR merged через полный канонический путь; runbook обогащён реальной практикой; пятничный ритуал идёт 2 недели.

## M2: enforcement hardened (4 issues, ~20 estimate points)

**Гипотеза:** известные gap'ы в защите и документации закрыты; проект готов к долгосрочному использованию.

| # | Title | Priority | Estimate | Зависит от |
|---|---|---|---|---|
| 9 | Phase 2 governance: add git-level commit-msg hook | P1 | 5 | #2 verified; требует ADR |
| 10 | End-to-end validate CI workflow templates on real project | P2 | 5 | — |
| 11 | Populate docs/domain/ with project's own vocabulary | P3 | 5 | — (но лучше после #5) |
| 12 | Test incident-recovery runbook on drill scenarios | P3 | 5 | M0 complete |

**Параллелизм:** все 4 могут идти параллельно, #9 требует отдельного ADR (ADR 0009 \"git-level phase 2\").

**Критерий завершения M2:** terminal-direct коммиты защищены (phase 2); CI templates проверены на живых pet-репо; domain vocabulary живой; incident runbook не теоретический.

## Диаграмма зависимостей

```
M0 ──── M1 ──── M2
│       │       │
│       │       ├── #9 (требует #2)
│       │       ├── #10
│       │       ├── #11 (желательно после #5)
│       │       └── #12 (требует M0)
│       │
│       ├── #5 (требует M0) ──► #6
│       ├── #7
│       └── #8 (30-day обсервация, старт параллельно)
│
├── #1 ─── #3 ─── #4
└── #2 ─┤
```

## Границы скоупа

**В scope проекта claude-mini:**
- Всё в `docs/`, `bootstrap/`, `.github/`
- ADR'ы для этих компонентов
- Runbooks по их использованию
- CI для самого этого репо

**Out of scope (отдельные репо / задачи mini-станции):**
- iCloud Photos → Plex migration
- SSH hardening на mini
- Tailscale improvements
- LaunchAgents tuning (уже работают)
- Любой backend/frontend код реальных проектов — они потребляют claude-mini, но не часть его

## Ежедневный и еженедельный ритм

**Ежедневно:**
- `mini-preflight` при старте рабочей сессии
- `claude --model sonnet` с TodoWrite для текущей задачи
- Advisor × 2 на нетривиальных задачах (проверяется в /implement)

**Еженедельно (пятница):**
- `mini-health` — проверка инфраструктуры mini
- `/project-health` — метрики репо, запись в `docs/metrics/`
- `/backlog-review` через `@agent-backlog-groomer` (если > 20 open issues)
- Review milestone progress — переносить несделанное с мотивацией (не молча)

**Ежемесячно:**
- Sprint-планирование следующего milestone
- Пересмотр open ADRs — закрытие accepted без review как tech debt

## После M2

Дальше план не фиксирован — проект покажет, куда его тянет реальная работа. Candidates:

- Linux hardware runbook (если начнётся миграция)
- Second hardware target (MacBook Pro M4 для параллельной работы)
- Проксирование agents/commands между машинами (стал ли mini единственной точкой или стал распределённым?)
- Long-running automation через `claude` в agentic-режиме (headless long sessions)

Но это решать не сейчас. Сейчас — **прожить 8 недель с этой настройкой и собрать данные**, а не планировать 6 месяцев вперёд.
