# Architecture overview

Архитектура разработческого сетапа в одном документе: слои, потоки данных, ключевые решения. Для детального разделения hardware vs universal — см. `layers.md`. Для обоснования конкретных выборов — см. `../decisions/`.

## Слои системы

```
┌─────────────────────────────────────────────────────────────────────────┐
│ EXTERNAL                                                                │
│                                                                          │
│  GitHub (issues, projects v2, PR, sub-issues, actions)                  │
│  Codex CLI ↔ ChatGPT Plus (two-voice review)                            │
│  Context7 (live library docs)                                           │
│  Anthropic API (advisor sub-inference)                                  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ Tailscale mesh
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ WORKFLOW                    (universal layer)                           │
│                                                                          │
│  Main loop: claude --model sonnet-4.6                                   │
│                     │                                                    │
│                     │  /advisor                                         │
│                     └────────────────▶ Opus 4.7 sub-inference           │
│                                                                          │
│  Commands (10):   /plan  /implement  /adr  /review  /codex-review       │
│                   /task-to-issue  /issue-to-task  /backlog-review       │
│                   /project-health  /feature (master orchestrator)       │
│                                                                          │
│  Agents (9):                                                            │
│     adr-reviewer        domain-reviewer        domain-researcher        │
│     solutions-architect backlog-groomer        security-reviewer        │
│     docs-reviewer       reliability-reviewer   adversarial-critic       │
│                                                                          │
│  Skills (3, author tools):                                              │
│     adr-author   domain-discovery   project-bootstrap                   │
│                                                                          │
│  Hooks:  pre-commit-governance.sh (PreToolUse Bash → blocks bad commits)│
│          rtk (PreToolUse Bash → compresses output)                      │
│          posttooluse-format.sh (PostToolUse Edit|MultiEdit|Write → lint)│
│                                                                          │
│  Deny-rules: .env*, secrets/**, ~/.ssh/**, age-key paths                │
│  Mode: auto + disableBypassPermissionsMode=true                         │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ MCP                         (universal layer)                           │
│                                                                          │
│  Serena (uvx)     ── semantic code navigation via LSP                   │
│  GitHub (HTTP)    ── issues/PR/projects/actions; PAT from Keychain      │
│  Context7 (HTTP)  ── fresh library docs, no auth                        │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ SECRETS                 (hardware-bridge: Keychain is OS-specific)      │
│                                                                          │
│  Per-project env injection via mise:                                    │
│     Keychain (security CLI)  ─── long-lived API keys                    │
│     age + sops ────────────── per-project encrypted .env.json in git    │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ RUNTIMES                    (universal layer)                           │
│                                                                          │
│  mise → Python 3.13 (+ uv), Go 1.24, Node 22                            │
│  CLI: ripgrep, jq, starship                                             │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PLATFORM                    (hardware layer)                            │
│                                                                          │
│  Mac mini 2018 Intel i7 32GB · macOS Sequoia 15.7.5                     │
│  Homebrew (/usr/local) · CLT 16.4                                       │
│  LaunchAgents (tmux, Plex, Transmission, caffeinate)                    │
│  Tailscale daemon · SSH key auth · Ghostty                              │
└─────────────────────────────────────────────────────────────────────────┘
```

## Ключевые потоки

### Feature pipeline (canonical)

```
Issue (GH)
   │
   ▼
/task-to-issue ─── (если задача была в TODO)
   │
   ▼                         ┌── advisor × 1 ── Opus 4.7 критикует план
/plan <issue>  ──────────────┤
   │    пишет plan.md        └── (если архитектурно значимо)
   │                             │
   │                             ▼
   │                          /adr <slug> ─── adr-author skill
   │                             │           (MADR 4.0 интервью)
   │                             ▼
   │                          @agent-adr-reviewer ─── sonnet review
   │                             │
   │                             ▼
   │                          ADR PR merged
   │
   ▼
/implement ─── advisor × 2 ── Opus 4.7 перед началом и перед done
   │    читает plan.md
   │    пишет код
   │
   ▼
/review ─── Claude critique staged diff
   │
   ▼
/codex-review ─── Codex CLI critique, результаты агрегируются
   │              (graceful degradation: если Codex упал → issue type:deferred-review)
   ▼
git commit ─── pre-commit-governance.sh проверяет:
   │              • Conventional Commits prefix
   │              • #NNN или Closes #N в message/branch
   │              • ADR-ref если decision-type изменение
   ▼
gh pr create ─── body включает Closes #N и Implements ADR
   │
   ▼
human approval + merge
```

### Master orchestrator `/feature`

Единая точка входа для feature-работы. Создаёт TodoWrite с чек-листом стадий и ведёт по нему:

```
/feature <issue-number>
   │
   ├─ [ ] Read issue body and acceptance criteria
   ├─ [ ] Run /plan and fill plan.md
   ├─ [ ] Determine if ADR needed (architectural implications?)
   │    └─ [ ] If yes: /adr and wait for merge
   ├─ [ ] Advisor call #1 on plan
   ├─ [ ] /implement (advisor #2 before declaring done)
   ├─ [ ] /review
   ├─ [ ] /codex-review
   ├─ [ ] git commit with governance
   └─ [ ] gh pr create with cross-refs
```

Оркестратор не выполняет команды за вас — он держит чек-лист, напоминает о следующем шаге, и использует hooks для предотвращения пропусков (commit без `/review` блокируется).

## Ключевые решения (детальные обоснования в ADR)

| # | Решение | ADR |
|---|---|---|
| 1 | Baseline state at takeover | `0001-baseline-state-at-takeover.md` |
| 2 | Pipeline over fan-out | `0002-pipeline-over-fanout.md` |
| 3 | Sonnet main + Opus advisor | `0003-sonnet-main-opus-advisor.md` |
| 4 | Governance via PreToolUse hook | `0004-governance-via-prehook.md` |
| 5 | Two-voice review с Codex Plus | `0005-two-voice-review-codex-plus.md` |
| 6 | MCP over memory | `0006-mcp-over-memory.md` |
| 7 | Read-only critic agents | `0007-read-only-critic-agents.md` |
| 8 | Hardware vs universal split | `0008-hardware-universal-split.md` |

## Почему именно так

Три центральных эффекта, без которых это был бы обычный сетап:

**Контекст не фрагментируется.** Единственный автор кода — главный цикл на Sonnet. Все остальные участники (advisor, agents) работают на read-only либо через server-side sub-inference на той же сессии. Это убирает проблему «lossy brief» при fan-out: невозможно потерять то, что никогда не передавалось.

**Knowledge живёт за пределами сессии.** ADR в `docs/decisions/`, issues в GitHub, plans в `plan.md`. Новая сессия = чистая память + доступ к тем же артефактам. Тест: через месяц вы или новый коллега открываете репо и за час без чат-истории восстанавливаете контекст.

**Governance материален, не декларативен.** Правила «коммит должен иметь issue-ref» работают не потому что вы помните, а потому что PreToolUse hook блокирует `git commit` без неё. Автоматизация пропускает лёгкое и блокирует тяжёлое — третья директива в коде, не в душе.
