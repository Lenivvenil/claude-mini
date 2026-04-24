# Ubiquitous Language — claude-mini-pipeline

**Version:** 2026-04-24
**Status:** draft — pending domain-reviewer approval

Terms are listed alphabetically. Each entry: one-sentence definition, then discriminating note where the term is easily confused.

---

## ADR (Architecturally Significant Decision Record)

A MADR 4.0 document in `docs/decisions/NNNN-*.md` recording a decision that meets at least one trigger in `docs/principles.md#что-значит-архитектурно-значимо`. Required before implementation; merged via canonical pipeline.

*Discriminating note:* a plan is not an ADR. If no trigger fires, use `/plan`, not `/adr`.

---

## Advisor

The Opus model instance invoked via `advisor()` to critique plans and review completed work. Always called at least twice on nontrivial tasks: before starting substantive work and before declaring done. Returns critique only — never edits files.

*Discriminating note:* the advisor is not part of the two-voice review. Two-voice = Claude `/review` + Codex `/codex-review`. Advisor = operator's senior consultant.

---

## Agent

A Claude Code subagent with a defined role and constrained toolset. Two subtypes per ADR 0007:
- **Read-only critic** — reads and evaluates, returns markdown report, never writes: `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `backlog-groomer`.
- **Author-gateway** — invokes a write-capable skill for docs artifacts only: `domain-researcher`, `solutions-architect`.

*Discriminating note:* "agent" in generic AI parlance means any AI agent. Inside this BC it means specifically a Claude Code subagent with the constraints above. See `docs/decisions/0007-read-only-critic-agents.md`.

---

## Author-gateway

An agent subtype that can invoke a write-capable skill to produce documentation artifacts (`docs/decisions/`, `docs/domain/`). Does not write production code. Does not edit existing files. Examples: `domain-researcher` (→ `domain-discovery` skill), `solutions-architect` (→ `adr-author` skill). See ADR 0007.

---

## Canonical Pipeline

The documented sequence in `CLAUDE.md:27-34`: `task-to-issue → plan → adr (if needed) → implement → review → codex-review → governance → PR`. The single authoritative path for feature work. Deviations require justification. Orchestrated by `/feature`.

---

## Definition of Done (DoD)

The checklist in `docs/principles.md#definition-of-done` that every change must satisfy before merge. Includes: ADR merged (if significant), domain docs updated (if BC changed), reviews passed, CI green, governance hook passed, PR body cross-references.

*Discriminating note:* DoD is the merge gate, not a style guide. Unchecked boxes block merge.

---

## Deferred Review

The state in which the second voice of two-voice review could not complete. Represented as a GitHub issue of type `type:deferred-review` (the artifact). Created when `/codex-review` is skipped (e.g., Plus OAuth quota exhausted, corporate repo gate). Satisfies the DoD graceful-degradation clause. Does not substitute for a passing review.

*Naming note:* "Deferred Review" is the concept/state. "deferred-review issue" is the GitHub artifact. `DeferredReviewIssueCreated` is the domain event. Three forms, one concept.

---

## Fan-out

Spawning multiple parallel agents or sub-tasks. Forbidden for feature work (ADR 0002). Permitted only for embarrassingly-parallel tasks: symbol renames across many files, import migrations, test templating from schema.

*Discriminating note:* embarrassingly-parallel is defined by examples, not a mechanical rule. Operator judgement required at the margin.

---

## Feature Pipeline

The canonical multi-stage workflow for delivering a change: issue → plan → (ADR) → implement → review → codex-review → governance → PR. Orchestrated by the `/feature` skill. Synonymous with Canonical Pipeline.

---

## Feature Run

One complete execution of `/feature <issue-number>`. The aggregate root of this BC. Invariants: single issue reference, monotonic DoD checklist, two-voice state machine, advisor called ≥ 2 times on nontrivial work.

---

## Governance Hook

The `pre-commit-governance.sh` shell hook installed at `.git/hooks/commit-msg`. Enforces Conventional Commits prefix and issue-ref (`#NNN`) on every commit. For ADR-significant changes, also enforces `Implements docs/decisions/NNNN-*.md`. Blocks commit if rules fail (`GovernanceBlocked` event).

---

## Governance-blocked Commit

A commit rejected by the governance hook. Not a failure state — it is the hook doing its job. Operator fixes the commit message and retries.

---

## Issue-first

The rule that any task longer than one session must have a GitHub issue before work starts. Enforced by the governance hook (commit-msg requires `#NNN`). Issues created via `/task-to-issue`.

---

## Main Loop

The Sonnet model instance that orchestrates all pipeline actions within a session. Has write authority over files and GitHub (within permissions). Distinct from the advisor (read-only) and agents (subagents with constrained toolsets).

---

## Operator

The human running Claude Code. Sole author of production code. Final decision-maker on all architectural choices. Claude is a "soul-crushing partner, not an expert" (Principle 2) — the operator is the expert.

---

## Pipeline Stage

A named step within the Feature Pipeline: `/plan`, `/adr`, `/implement`, `/review`, `/codex-review`, governance commit, `gh pr create`. Stages are ordered and gated; skipping a stage requires explicit justification.

---

## Read-only Critic

An agent subtype that reads artifacts and returns a markdown report. Never writes to the filesystem. Never mutates GitHub. Examples: `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `backlog-groomer`. See ADR 0007.

---

## Red Hotspot

An unresolved question or known invariant violation that the domain docs explicitly leave open. Flagged honestly rather than papered over. Current hotspots: see `overview.md#red-hotspots`.

---

## Skill

A slash-command (`/plan`, `/adr`, `/implement`, `/review`, `/feature`, etc.) that executes under main-loop authority. Has full write capability (subject to permissions). Distinct from agents, which are subagents with constrained toolsets.

*Discriminating note:* a skill is not an agent. Skills run inside the main loop. Agents are separate Claude Code subagents. This distinction is normative in ADR 0007 and subtle in practice.

---

## Two-voice Review

The gating mechanism combining `/review` (Claude main loop) and `/codex-review` (Codex CLI). Both must pass or their disagreement must be reconciled in the PR thread. If Codex is unavailable, a deferred-review issue is created.

*Discriminating note:* two-voice = Claude vs Codex. Advisor is not part of two-voice.

---

## Ubiquitous Language

The shared vocabulary of this bounded context. Terms here are used with their definitions above in all ADRs, issues, PR descriptions, runbooks, and conversations. Drift from these definitions is detected by `domain-reviewer`.
