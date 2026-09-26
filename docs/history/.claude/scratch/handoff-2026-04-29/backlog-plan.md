# Backlog plan — handoff 2026-04-29

40 тикетов из synthesis раздел B + 1 post-handoff ticket (#41) добавленный по указанию оператора. Источник synthesis без изменений: `docs/synthesis/2026-04-29-pipeline-restructuring.md` (после step 2 коммита оператора).

**НЕ запускать `gh issue create` массово.** Оператор пройдёт через `/backlog-review` и решит, что создавать и в каком порядке. Команды ниже — заготовки.

Перед массовым созданием — выполнить `bash .claude/scratch/handoff-2026-04-29/labels.sh` для создания отсутствующих labels (`principle:*`, `type:bootstrap`, `prod-bound`).

---

## P0 (8 tickets)

## Ticket 01 — feat(verifier): wire Hypothesis property-based testing into /qa skill
- **priority:** P0
- **estimate:** M
- **principles:** #3
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/01.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(verifier): wire Hypothesis property-based testing into /qa skill" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/01.md
  ```

## Ticket 02 — feat(governance): PostToolUse hook for format+typecheck after Edit/Write
- **priority:** P0
- **estimate:** S
- **principles:** #3
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/02.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(governance): PostToolUse hook for format+typecheck after Edit/Write" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/02.md
  ```

## Ticket 03 — feat(governance): Stop hook ensures tests pass before session end
- **priority:** P0
- **estimate:** S
- **principles:** #9
- **labels (raw from synthesis):** principle:antifragile,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/03.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(governance): Stop hook ensures tests pass before session end" --label "principle:antifragile,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/03.md
  ```

## Ticket 04 — feat(verifier): static-analysis baseline (ruff/eslint/staticcheck/radon/jscpd)
- **priority:** P0
- **estimate:** M
- **principles:** #1, #3, #4
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/04.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(verifier): static-analysis baseline (ruff/eslint/staticcheck/radon/jscpd)" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/04.md
  ```

## Ticket 05 — chore(governance): /gate-audit weekly skill with ROI schema
- **priority:** P0
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** principle:gate-roi,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/05.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(governance): /gate-audit weekly skill with ROI schema" --label "principle:gate-roi,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/05.md
  ```

## Ticket 06 — feat(critic): adversarial-critic agent with explicit lazy-mandate
- **priority:** P0
- **estimate:** M
- **principles:** #2
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** #7
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/06.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(critic): adversarial-critic agent with explicit lazy-mandate" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/06.md
  ```

## Ticket 07 — feat(knowledge): docs/anti-patterns.md as accumulator artifact
- **priority:** P0
- **estimate:** S
- **principles:** #4
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/07.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(knowledge): docs/anti-patterns.md as accumulator artifact" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/07.md
  ```

## Ticket 08 — chore(adr): ADR retirement process with 90-day staleness audit
- **priority:** P0
- **estimate:** S
- **principles:** #4
- **labels (raw from synthesis):** type:adr,principle:gate-roi
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/08.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(adr): ADR retirement process with 90-day staleness audit" --label "type:adr,principle:gate-roi" --body-file .claude/scratch/handoff-2026-04-29/bodies/08.md
  ```

## P1 (13 tickets)

## Ticket 09 — feat(forge): forge.sh wrapper abstracting gh for GitHub/Gitea/Forgejo/GitLab
- **priority:** P1
- **estimate:** M
- **principles:** #7
- **labels (raw from synthesis):** principle:agnostic,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/09.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(forge): forge.sh wrapper abstracting gh for GitHub/Gitea/Forgejo/GitLab" --label "principle:agnostic,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/09.md
  ```

## Ticket 10 — feat(agnostic): AGENTS.md + CLAUDE.md duality migration
- **priority:** P1
- **estimate:** S
- **principles:** #7
- **labels (raw from synthesis):** principle:agnostic,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/10.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(agnostic): AGENTS.md + CLAUDE.md duality migration" --label "principle:agnostic,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/10.md
  ```

## Ticket 11 — feat(continuity): STATE.md + session-log + plan.md triple hand-off contract
- **priority:** P1
- **estimate:** M
- **principles:** #9
- **labels (raw from synthesis):** principle:continuity,type:bootstrap
- **depends-on:** #3
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/11.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(continuity): STATE.md + session-log + plan.md triple hand-off contract" --label "principle:continuity,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/11.md
  ```

## Ticket 12 — feat(audit): /audit-pass skill for human-authored ticket supervisory re-pass
- **priority:** P1
- **estimate:** S
- **principles:** #9
- **labels (raw from synthesis):** principle:continuity,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/12.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(audit): /audit-pass skill for human-authored ticket supervisory re-pass" --label "principle:continuity,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/12.md
  ```

## Ticket 13 — refactor(domain): split domain layer into meta-pipeline vs per-project
- **priority:** P1
- **estimate:** L
- **principles:** #8
- **labels (raw from synthesis):** principle:domain,type:adr
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/13.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "refactor(domain): split domain layer into meta-pipeline vs per-project" --label "principle:domain,type:adr" --body-file .claude/scratch/handoff-2026-04-29/bodies/13.md
  ```

## Ticket 14 — refactor(skills): convert slash commands to Claude Code Skills format
- **priority:** P1
- **estimate:** M
- **principles:** #6
- **labels (raw from synthesis):** principle:agnostic,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/14.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "refactor(skills): convert slash commands to Claude Code Skills format" --label "principle:agnostic,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/14.md
  ```

## Ticket 15 — feat(verifier): third voice on open-weight (Kimi K2.6 / DeepSeek V4 / Qwen3-Coder)
- **priority:** P1
- **estimate:** M
- **principles:** #2, #7
- **labels (raw from synthesis):** principle:agnostic,principle:lazy-detection
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/15.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(verifier): third voice on open-weight (Kimi K2.6 / DeepSeek V4 / Qwen3-Coder)" --label "principle:agnostic,principle:lazy-detection" --body-file .claude/scratch/handoff-2026-04-29/bodies/15.md
  ```

## Ticket 16 — feat(verifier): /intent-check skill (acceptance criteria vs diff alignment)
- **priority:** P1
- **estimate:** S
- **principles:** #1, #2
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/16.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(verifier): /intent-check skill (acceptance criteria vs diff alignment)" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/16.md
  ```

## Ticket 17 — chore(verifier): mutation testing weekly cron (mutmut/Stryker/cargo-mutants)
- **priority:** P1
- **estimate:** M
- **principles:** #3, #8
- **labels (raw from synthesis):** principle:lazy-detection,principle:antifragile
- **depends-on:** #7
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/17.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(verifier): mutation testing weekly cron (mutmut/Stryker/cargo-mutants)" --label "principle:lazy-detection,principle:antifragile" --body-file .claude/scratch/handoff-2026-04-29/bodies/17.md
  ```

## Ticket 18 — chore(governance): DoD compliance table — prune honor-only norms, automate
- **priority:** P1
- **estimate:** M
- **principles:** #1, #8
- **labels (raw from synthesis):** principle:gate-roi,type:bootstrap
- **depends-on:** #5
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/18.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(governance): DoD compliance table — prune honor-only norms, automate" --label "principle:gate-roi,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/18.md
  ```

## Ticket 19 — feat(verifier): semgrep rules for hedging-words and corporate-softening in plan.md
- **priority:** P1
- **estimate:** S
- **principles:** #1
- **labels (raw from synthesis):** principle:lazy-detection,type:bootstrap
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/19.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(verifier): semgrep rules for hedging-words and corporate-softening in plan.md" --label "principle:lazy-detection,type:bootstrap" --body-file .claude/scratch/handoff-2026-04-29/bodies/19.md
  ```

## Ticket 20 — chore(security): MCP transport hardening + pin versions + Stacklok ToolHive evaluation
- **priority:** P1
- **estimate:** M
- **principles:** #7
- **labels (raw from synthesis):** principle:agnostic,prod-bound
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/20.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(security): MCP transport hardening + pin versions + Stacklok ToolHive evaluation" --label "principle:agnostic,prod-bound" --body-file .claude/scratch/handoff-2026-04-29/bodies/20.md
  ```

## Ticket 41 — chore(docs): migrate DoD/ADR-trigger/advisor-policy from principles.md to runbooks
- **priority:** P1
- **estimate:** S
- **principles:** —
- **labels (raw from synthesis):** type:chore,type:runbook,area:docs,adr-followup
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/41.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(docs): migrate DoD/ADR-trigger/advisor-policy from principles.md to runbooks" --label "type:chore,type:runbook,area:docs,adr-followup" --body-file .claude/scratch/handoff-2026-04-29/bodies/41.md
  ```

## P2 (12 tickets)

## Ticket 21 — feat(adr): ADR Kit MCP integration
- **priority:** P2
- **estimate:** M
- **principles:** #4
- **labels (raw from synthesis):** type:adr,principle:gate-roi
- **depends-on:** #8
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/21.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(adr): ADR Kit MCP integration" --label "type:adr,principle:gate-roi" --body-file .claude/scratch/handoff-2026-04-29/bodies/21.md
  ```

## Ticket 22 — feat(verifier): Schemathesis for any HTTP surface in pet-projects
- **priority:** P2
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile,principle:lazy-detection
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/22.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(verifier): Schemathesis for any HTTP surface in pet-projects" --label "principle:antifragile,principle:lazy-detection" --body-file .claude/scratch/handoff-2026-04-29/bodies/22.md
  ```

## Ticket 23 — feat(release): GitHub native auto-merge for trivial PRs
- **priority:** P2
- **estimate:** S
- **principles:** #8
- **labels (raw from synthesis):** principle:gate-roi
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/23.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(release): GitHub native auto-merge for trivial PRs" --label "principle:gate-roi" --body-file .claude/scratch/handoff-2026-04-29/bodies/23.md
  ```

## Ticket 24 — feat(operability): OpenFeature flags via flagd file-based provider
- **priority:** P2
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/24.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(operability): OpenFeature flags via flagd file-based provider" --label "principle:antifragile" --body-file .claude/scratch/handoff-2026-04-29/bodies/24.md
  ```

## Ticket 25 — feat(backlog): /backlog-grooming agent with ICE/RICE scoring
- **priority:** P2
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** type:bootstrap,principle:gate-roi
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/25.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(backlog): /backlog-grooming agent with ICE/RICE scoring" --label "type:bootstrap,principle:gate-roi" --body-file .claude/scratch/handoff-2026-04-29/bodies/25.md
  ```

## Ticket 26 — refactor(ddd): aggressive DDD retirement audit at solo scale
- **priority:** P2
- **estimate:** S
- **principles:** #8
- **labels (raw from synthesis):** principle:domain,type:adr
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/26.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "refactor(ddd): aggressive DDD retirement audit at solo scale" --label "principle:domain,type:adr" --body-file .claude/scratch/handoff-2026-04-29/bodies/26.md
  ```

## Ticket 27 — feat(observability): structured JSON logs + OTel auto-instrumentation in pet-projects
- **priority:** P2
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/27.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(observability): structured JSON logs + OTel auto-instrumentation in pet-projects" --label "principle:antifragile" --body-file .claude/scratch/handoff-2026-04-29/bodies/27.md
  ```

## Ticket 28 — feat(security): supply-chain table-stakes (SLSA L2, cosign, gitleaks)
- **priority:** P2
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile,prod-bound
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/28.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(security): supply-chain table-stakes (SLSA L2, cosign, gitleaks)" --label "principle:antifragile,prod-bound" --body-file .claude/scratch/handoff-2026-04-29/bodies/28.md
  ```

## Ticket 29 — feat(continuity): runbook.md + restore drill weekly cron
- **priority:** P2
- **estimate:** S
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile,principle:continuity
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/29.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(continuity): runbook.md + restore drill weekly cron" --label "principle:antifragile,principle:continuity" --body-file .claude/scratch/handoff-2026-04-29/bodies/29.md
  ```

## Ticket 30 — feat(stpa): one-time STPA hazard pass on pipeline
- **priority:** P2
- **estimate:** M
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile,type:adr
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/30.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(stpa): one-time STPA hazard pass on pipeline" --label "principle:antifragile,type:adr" --body-file .claude/scratch/handoff-2026-04-29/bodies/30.md
  ```

## Ticket 31 — chore(governance): semgrep multimodal evaluation as deterministic-LLM hybrid
- **priority:** P2
- **estimate:** S
- **principles:** #3
- **labels (raw from synthesis):** principle:lazy-detection
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/31.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(governance): semgrep multimodal evaluation as deterministic-LLM hybrid" --label "principle:lazy-detection" --body-file .claude/scratch/handoff-2026-04-29/bodies/31.md
  ```

## Ticket 32 — feat(continuity): Beads (Yegge) trial as plan.md replacement
- **priority:** P2
- **estimate:** M
- **principles:** #9
- **labels (raw from synthesis):** principle:continuity
- **depends-on:** #11
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/32.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "feat(continuity): Beads (Yegge) trial as plan.md replacement" --label "principle:continuity" --body-file .claude/scratch/handoff-2026-04-29/bodies/32.md
  ```

## P3 (8 tickets)

## Ticket 33 — chore(sandbox): microVM sandbox evaluation (e2b/Daytona) — defer until needed
- **priority:** P3
- **estimate:** L
- **principles:** #8
- **labels (raw from synthesis):** principle:antifragile
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/33.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(sandbox): microVM sandbox evaluation (e2b/Daytona) — defer until needed" --label "principle:antifragile" --body-file .claude/scratch/handoff-2026-04-29/bodies/33.md
  ```

## Ticket 34 — chore(acp): ACP broker support (Zed/JetBrains) — defer
- **priority:** P3
- **estimate:** M
- **principles:** #7
- **labels (raw from synthesis):** principle:agnostic
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/34.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(acp): ACP broker support (Zed/JetBrains) — defer" --label "principle:agnostic" --body-file .claude/scratch/handoff-2026-04-29/bodies/34.md
  ```

## Ticket 35 — research(verifier): custom-trained discriminator for lazy-pattern detection
- **priority:** P3
- **estimate:** L
- **principles:** #4
- **labels (raw from synthesis):** principle:lazy-detection
- **depends-on:** #7
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/35.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "research(verifier): custom-trained discriminator for lazy-pattern detection" --label "principle:lazy-detection" --body-file .claude/scratch/handoff-2026-04-29/bodies/35.md
  ```

## Ticket 36 — research(optimizer): DSPy для core skill prompts — defer
- **priority:** P3
- **estimate:** L
- **principles:** —
- **labels (raw from synthesis):** principle:lazy-detection
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/36.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "research(optimizer): DSPy для core skill prompts — defer" --label "principle:lazy-detection" --body-file .claude/scratch/handoff-2026-04-29/bodies/36.md
  ```

## Ticket 37 — chore(adr): structured-madr / git-adr migration evaluation
- **priority:** P3
- **estimate:** M
- **principles:** #4
- **labels (raw from synthesis):** type:adr
- **depends-on:** #21
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/37.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(adr): structured-madr / git-adr migration evaluation" --label "type:adr" --body-file .claude/scratch/handoff-2026-04-29/bodies/37.md
  ```

## Ticket 38 — chore(runtime): quarterly Claude Code vendor-monitor — formalised
- **priority:** P3
- **estimate:** S
- **principles:** #7
- **labels (raw from synthesis):** principle:agnostic
- **depends-on:** —
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/38.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(runtime): quarterly Claude Code vendor-monitor — formalised" --label "principle:agnostic" --body-file .claude/scratch/handoff-2026-04-29/bodies/38.md
  ```

## Ticket 39 — chore(docs): 1h onboarding traps test (continuity)
- **priority:** P3
- **estimate:** S
- **principles:** #4, #9
- **labels (raw from synthesis):** principle:continuity
- **depends-on:** #7
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/39.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "chore(docs): 1h onboarding traps test (continuity)" --label "principle:continuity" --body-file .claude/scratch/handoff-2026-04-29/bodies/39.md
  ```

## Ticket 40 — research(verifier): multi-judge calibration with regression bias correction (arxiv 2510.11822)
- **priority:** P3
- **estimate:** L
- **principles:** #2
- **labels (raw from synthesis):** principle:lazy-detection
- **depends-on:** #5
- **duplicate-of:** —
- **body-file:** `.claude/scratch/handoff-2026-04-29/bodies/40.md`
- **gh-create-command:**
  ```bash
  gh issue create --title "research(verifier): multi-judge calibration with regression bias correction (arxiv 2510.11822)" --label "principle:lazy-detection" --body-file .claude/scratch/handoff-2026-04-29/bodies/40.md
  ```

