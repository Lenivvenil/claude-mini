# 0013. Wire agent invocations into /feature as gating steps

* Status: proposed
* Date: 2026-04-24
* Deciders: venil
* Tags: pipeline, orchestration, agents

## Context and Problem Statement

Pipeline in `CLAUDE.md:27-34` declares 6 agents in an agents table but does not wire any of them into pipeline stages. Invocation depends entirely on operator memory at the right moment. The gap was noticed 2026-04-24 during a session review that produced issue #53. Principle 4 ("Knowledge в инструментах, не в памяти") makes this structural, not incidental: if the pipeline does not encode agent invocations, they will not happen.

## Decision Drivers

* **Principle 4** — Knowledge in tools, not memory: pipeline must be self-documenting; a table in CLAUDE.md that no stage reads is decorative.
* **Principle 3** — Automate only low-risk: agent invocations are read-only critics; they are exactly the category approved for automation without approval gates.
* **Consistency** — `/feature` already orchestrates plan/implement/review; agents should be first-class citizens in the same orchestration, not a separate memory layer.
* **Auditability** — when agents change, there must be one place to update wiring, not six scattered skill files.

## Considered Options

* **Option A: Each slash-skill internally invokes its own agent** — decentralized; `/adr` calls `adr-reviewer`, `/plan` calls `solutions-architect`, each skill is self-contained.
* **Option B: `/feature` TodoWrite is the single location where agents are gating steps** — centralized orchestrator owns all agent choreography with access to full session context.
* **Option C: Explicit "manual by design" annotations in CLAUDE.md** — no automation; document each agent's intended trigger clearly so operator memory has a reference, but invocation stays manual.

## Decision Outcome

Chosen option: **Option B** (`/feature` as central orchestrator), because it is the only option that satisfies Principle 4 (knowledge in tools) without fragmenting orchestration logic. Principle 3 authorizes automation of read-only operations — agents qualify. `/feature` already owns the canonical pipeline; adding agent gates extends that ownership consistently. Conditional logic (`adr-needed`, `docs/domain/` change, prod-bound PR) is naturally available at the `/feature` level, not inside individual skills.

### Canonical stage → agent map

| Pipeline stage | Agent | Condition |
|---|---|---|
| pre-`/plan` | `domain-researcher` | greenfield BC only — no current pipeline stage; must be added |
| `/plan` | `solutions-architect` | significant tech choice (`adr-needed` label or decider judgement) |
| `/adr` | `adr-reviewer` | after draft is written |
| any `docs/domain/` edit | `domain-reviewer` | any stage — trigger is file path, not pipeline step |
| `/review` phase | `security-reviewer` | prod-bound change only |
| out-of-band (weekly) | `backlog-groomer` | intentionally outside the feature pipeline |

Notes:
- `security-reviewer` belongs inside the `/review` phase (alongside `/review` and `/codex-review`), not as a separate pre-PR step. The review phase = `/review` + `/codex-review` + conditional specialized critics.
- `domain-reviewer` is not tied to `/implement` — it fires whenever `docs/domain/` is modified, regardless of which stage caused it.
- `domain-researcher` has no current pipeline stage; the map above exposes this as a gap to address in the implementation PR.

### Positive Consequences

* Pipeline becomes self-documenting — Principle 4 satisfied.
* Operators using `/feature` receive agent reviews without remembering to invoke them.
* Single location for all pipeline choreography changes.

### Negative Consequences

* Skills invoked directly (outside `/feature`) do not get agent coverage — operator must remember for ad-hoc use.
* `/feature` skill grows more complex: conditional logic for 5 agents increases maintenance surface.
* Risk of false-positive invocations: `solutions-architect` may fire on trivial plan items if conditions are underspecified.
* Initial implementation effort: wiring requires a follow-up PR after this ADR merges; pipeline is still manual until that PR ships.
* Reversal is low-friction: undoing Option B means editing one block in the `/feature` skill's TodoWrite checklist. It does not require migrating logic across 6 skill files. If the Re-visit Trigger fires, rollback cost is a single PR.

## Pros and Cons of the Options

### Option A: Each skill invokes its own agent

* Good, because skill is self-contained — works when invoked outside `/feature`.
* Good, because skill ↔ agent relationship is explicit in the skill file itself.
* Bad, because wiring is scattered across 6+ skill files — no single place to audit the full pipeline.
* Bad, because skill has no session context — cannot distinguish "is this an adr-needed plan or a trivial one?" and will over-invoke.

### Option B: /feature owns all agent choreography

* Good, because one place holds the entire pipeline contract — readable in one scroll.
* Good, because conditional logic has full context: which labels are set, which files changed, whether ADR was opened.
* Bad, because agents do not fire for direct skill invocations (e.g. standalone `/adr` without `/feature`).
* Bad, because `/feature` TodoWrite grows; each new gating step adds cognitive load per run.
* Bad, because failure in `/feature` orchestration breaks all agent invocations simultaneously.

### Option C: Manual with CLAUDE.md annotations

* Good, because zero implementation risk — cannot wire incorrectly if you do not wire at all.
* Good, because per-agent conditions ("solutions-architect only on significant tech choice") are complex and hard to express reliably in code.
* Bad, because this is the current status quo that produced issue #53 — it does not solve the problem.
* Bad, because it explicitly violates Principle 4: the annotation is still knowledge in memory, not in the tool.

## Confirmation

After the first 5 `/feature` runs post-implementation: inspect task logs. Every run that included an ADR step or a `docs/domain/` change must show an agent invocation in its history. Every run bound for a production PR must show `security-reviewer` in its log. If any qualifying run shows no agent call, that is a bug, not a design choice — reopen this ADR.

## Re-visit Trigger

* If `/feature` TodoWrite grows beyond 12 steps total (agents included), reconsider Option A (decentralize per-skill) to reduce orchestrator complexity.
* If 3 or more sessions in a row bypass `/feature` and invoke skills directly — indicating operators find `/feature` too heavyweight — reconsider whether centralization is the right model.

## Links

* Closes #53 — agents: 5 of 6 declared agents have no deterministic trigger in the feature pipeline
* Related: [0007](0007-read-only-critic-agents.md) — establishes read-only constraint on agents; this ADR extends that decision by wiring invocations
* Related: [0002](0002-pipeline-over-fanout.md) — pipeline-over-fanout principle that `/feature` implements
* `docs/principles.md#3` — automate only low-risk
* `docs/principles.md#4` — knowledge in tools, not memory
