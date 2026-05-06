# Bounded Context: meta-pipeline BC

**Version:** 2026-05-06
**Status:** current as of ADR-0020 (God Aggregate extraction, issue #108) + gate-audit operational layer (issue #122) + ADR-0027 (Domain Inversion: meta vs target BC, issue #130); four aggregate roots: FeatureRun, GovernanceRun, TwoVoiceReview, RunbookExecution (draft)

## Table of Contents

- [Purpose](#purpose)
- [Actors](#actors)
- [Commands and Domain Events](#commands-and-domain-events)
- [Boundary](#boundary)
- [Aggregate Root](#aggregate-root)
- [Policies](#policies)
- [Context Map](#context-map)
- [Use Cases](#use-cases)
- [Domain Data Model](#domain-data-model)
- [Interface Contracts](#interface-contracts)
- [NFR](#nfr)
- [Internal Compliance](#internal-compliance)
- [Security](#security)
- [Red Hotspots](#red-hotspots)

---

## Purpose

This BC owns the workflow choreography for AI-assisted software development: pipeline stages, agent invocation, governance enforcement, ADR discipline, and the Definition of Done. It does NOT own the source code of projects where claude-mini is installed, Claude Code internals, or Anthropic model internals.

---

## Actors

| Actor | Role | Authority |
|---|---|---|
| **Operator** | Human running Claude Code; sole final decision-maker and author of production code | Full write, merge, approve |
| **Main Loop** (Sonnet) | Orchestrates all pipeline actions under operator direction | Write authority within repo |
| **Advisor** (Opus) | Consulted via `advisor()` before substantive work and before declaring done; two calls minimum on nontrivial tasks | Read-only; returns critique, not edits |
| **Read-only Critic** (subagent) | `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `reliability-reviewer`, `backlog-groomer`, `docs-reviewer`, `adversarial-critic` — evaluate artifacts, return markdown reports | Read-only; never writes to filesystem or mutates GitHub |
| **Author-gateway** (subagent) | `domain-researcher`, `solutions-architect` — invoke write-capable skills for docs artifacts only | Limited write via skill (docs only, not production code) |
| **Skill** | Slash-command (`/plan`, `/adr`, `/implement`, `/review`, `/feature`, etc.) executing under main-loop authority | Main-loop authority |
| **GitHub MCP** | MCP server invocable from inside the pipeline; ACL layer over GitHub platform | Pipeline-scoped GitHub API calls |
| **Codex CLI** | Second voice in two-voice review; accessed via ChatGPT Plus device-auth OAuth | Read-only output (review text) |

---

## Commands and Domain Events

Four aggregate roots own commands within this BC (ADR-0020 + ADR-0027). Commands are organized by owning aggregate. All 17 in-BC commands are accounted for within the four aggregate roots — none removed, none duplicated. `RunbookExecution` commands are TBD (Event Storming pending). (`PromoteTaskToIssue` is out-of-band and excluded from this count.)

### FeatureRun commands (pipeline orchestration)

| Command | Emits |
|---|---|
| `StartFeaturePipeline(issue)` | `FeaturePipelineStarted` |
| `DraftPlan` | `PlanDrafted` |
| `InvokeAdvisor` | `AdvisorInvoked`, `AdvisorReturned` |
| `DraftADR` | `ADRDrafted` |
| `RequestADRReview` | `ADRReviewRequested` |
| `StartImplementation` | `ImplementationStarted` |
| `ModifyDomainDocs` | `DomainDocsChanged` |
| `RequestSecurityReview` | `SecurityReviewRequested` |
| `RequestReliabilityReview` | `ReliabilityReviewRequested` |
| `CreatePR` | `PRCreated` |
| `DeclareDoDSatisfied` | `DoDSatisfied` |
| `MergeToMain` | `MergedToMain` |
| `MergeADR` | `ADRMerged` |

### GovernanceRun commands

| Command | Emits |
|---|---|
| `AttemptCommit` | `CommitAttempted` → `GovernanceBlocked` (retry; stays in same instance) \| `GovernanceApproved` (terminal) |

### TwoVoiceReview commands

| Command | Emits |
|---|---|
| `RequestReview` | `ReviewRequested` |
| `RequestCodexReview` | `CodexReviewRequested` \| `CodexReviewSkipped` |
| `RecordTwoVoiceResult(agreed\|disagreed)` | `TwoVoiceAgreed` (arg=agreed) \| `TwoVoiceDisagreed` (arg=disagreed); subsequent call after disagreed: `TwoVoiceReconciled` (disagreement resolved) \| `DeferredReviewIssueCreated` (Codex skipped after disagreement) |

### Out-of-band commands (not part of FeatureRun)

| Command | Emits | Notes |
|---|---|---|
| `PromoteTaskToIssue` | `TaskPromotedToIssue` | Pre-pipeline; no FeatureRun yet |

**Cross-reference:** `RunBacklogGroomer` / `BacklogGroomed` belong to a separate weekly aggregate (`BacklogGroomRun`), not to `FeatureRun`. They are not listed here to avoid boundary confusion. The ADR formalising this split is tracked in issue #107.

---

## Boundary

**In scope:**
- Feature pipeline choreography (stages, ordering, gates)
- Agent invocation rules (who, when, conditions)
- Governance hooks (commit-msg enforcement, `pre-commit-governance.sh` PreToolUse + `commit-msg-governance.sh` git hook)
- Format check hook (PostToolUse lint/format warnings, `posttooluse-format.sh`)
- ADR lifecycle (draft → review → merge)
- Domain model lifecycle (this BC maintains its own docs/domain/)
- Definition of Done enforcement
- Advisor policy (when to invoke, minimum count)
- Two-voice review protocol
- Fan-out rules (what is and isn't parallelizable)
- Issue-first discipline
- Per-ticket git worktree isolation for sweep operations (ADR-0017; `bootstrap/scripts/sweep-worktree*.sh`)
- Gate ROI audit operational layer: `GateEvent` append-log (`docs/gate-audit/events.jsonl`), `GateAuditWeek` read-model (`docs/gate-audit/aggregate.jsonl`), weekly aggregation (`gate-audit-aggregate.sh`), operator tagging CLI (`forge gate-tag`). These are **operational tooling read-models**, not DDD aggregate roots. The four aggregate roots of this BC are `FeatureRun`, `GovernanceRun`, `TwoVoiceReview`, `RunbookExecution` (ADR-0020 + ADR-0027).

**Out of scope:**
- **Domain models of target BCs** — aggregate names, invariants, and vocabulary of any pet-project (archi2likec4, digest, etc.) are unknown to this BC. meta-pipeline BC knows only that "a target artifact exists and conforms to meta-schema"; it never reads target-domain terms as domain concepts (ADR-0027, Domain Inversion).
- Source code of downstream projects where claude-mini is installed
- Claude Code engine internals (tool dispatch, context window management)
- GitHub platform internals (Actions runner mechanics, PR merge algorithms)
- Anthropic API (abstracted by Claude Code; pipeline never calls it directly)
- RTK proxy (infrastructure below the BC line)

**Terms that change meaning at the boundary:**

| Term | Inside this BC | Outside |
|---|---|---|
| `review` | `/review` + `/codex-review` two-voice gate | GitHub web UI PR review |
| `issue` | Backlog item with `#NNN` reference | "A problem" (generic English) |
| `agent` | Claude Code subagent: read-only critic or author-gateway (ADR 0007) | Any AI agent |
| `pipeline` | This BC's canonical feature pipeline | CI/CD pipeline |
| `skill` | Slash-command running under main-loop authority | Generic capability |

---

## Aggregate Root

Four aggregate roots within `meta-pipeline BC`, per ADR-0020 + ADR-0027 (`docs/decisions/0020-god-aggregate-sub-aggregate-extraction.md`, `docs/decisions/0027-domain-inversion-meta-vs-target-bc.md`).

### FeatureRun

**`FeatureRun`** — one complete invocation of `/feature <issue-number>`. The single orchestrator: holds full context (`issue_ref`, `dod_state`, `advisor_call_count`) from pipeline start to merge. Delegates to `GovernanceRun` and `TwoVoiceReview` sub-cycles and reads their terminal states for DoD evaluation.

On `FeaturePipelineStarted`, `FeatureRun` creates one `GovernanceRun` (state=pending, retry_count=0) and one `TwoVoiceReview` (state=pending) by reference. Sub-aggregates do not exist outside a `FeatureRun`; their lifecycle is bounded by the run that spawned them.

Invariants:
- Exactly one issue reference (`Closes #NNN`) per run
- `dod_state` monotonic: `in_progress → review_pending → done`; never reversed within a run
- `dod_state` may transition to `done` only when both: `TwoVoiceReview.state ∈ {agreed, reconciled, deferred}` AND `GovernanceRun.state = approved` — cross-aggregate query, not embedded state (ADR-0020 §Cross-aggregate-communication)
- `advisor()` called ≥ 2 times when task is nontrivial (per `docs/principles.md`)
- `FeatureRun` does not read target BC domain data directly — all target artifacts enter meta through ACL (ADR-0027)

**Note:** `BacklogGroomed` belongs to a separate out-of-band aggregate (`BacklogGroomRun`). It is not part of `FeatureRun`.

---

### GovernanceRun

**`GovernanceRun`** — one commit-governance episode for a `FeatureRun`. Created by `FeatureRun` on `FeaturePipelineStarted`; one instance per run, shared across all retry attempts. Remains in `pending` state until `AttemptCommit` is called; `GovernanceApproved` transitions it to `approved`. Enforcement artifacts: `pre-commit-governance.sh` (Claude Code PreToolUse hook) and `commit-msg-governance.sh` (installed at `.git/hooks/commit-msg` via `--hook-this-repo` for direct terminal commits — ADR-0011).

Invariants:
- State machine: `pending → approved` (terminal). `GovernanceBlocked` increments the internal retry counter without changing the instance; only `GovernanceApproved` terminates the run.
- Internal retry counter starts at 0; incremented by each `GovernanceBlocked`; no upper bound enforced — operator must resolve governance issues before proceeding.
- `GovernanceRun.state = approved` is required for `FeatureRun.dod_state` to reach `done`.

---

### TwoVoiceReview

**`TwoVoiceReview`** — one two-voice review episode for a `FeatureRun`. Owns the two-voice state machine and `ReviewArtifact` entities of type `claude_review` and `codex_review`.

Invariants:
- State machine: `{pending → agreed | pending → deferred | pending → disagreed | disagreed → reconciled | disagreed → deferred}` — `disagreed` entered via `RecordTwoVoiceResult(disagreed)`; `deferred` reachable from `pending` (Codex skip) and from `disagreed` (unresolved conflict)
- Terminal states (`agreed`, `reconciled`, `deferred`) are monotonically stable: no backward transition out of any terminal state.
- `TwoVoiceReview.state ∈ {agreed, reconciled, deferred}` is required for `FeatureRun.dod_state` to reach `done`.
- `ReviewArtifact` entities of type `claude_review` and `codex_review` are owned by this aggregate. `advisor_critique` type stays in `FeatureRun` — advisor is not part of two-voice review (per `vocabulary.md`, ADR-0020). `adversarial-critic` findings are context that enriches `claude_review`; they do NOT constitute a fourth `ReviewArtifact` type. The type set is stable at three: `claude_review`, `codex_review`, `advisor_critique`.
- `RequestSecurityReview` and `RequestReliabilityReview` commands must **not** be migrated into `TwoVoiceReview` — they are conditional prod-bound gates owned by `FeatureRun` (ADR-0020 Confirmation §5).

---

### RunbookExecution

**`RunbookExecution`** — один запуск задокументированной процедуры из `docs/runbooks/`. Независимый агрегатный корень; не вложен в `FeatureRun` — может существовать полностью вне feature-pipeline (drill, cron, manual recovery).

Инварианты:
- Один `RunbookExecution` — один runbook-документ, одна инвокация; повторный запуск = новый экземпляр
- State machine: `pending → in_progress → completed | aborted | failed`
  - `completed` — оператор объявил завершение или автоматический запуск завершился без ошибок
  - `aborted` — оператор остановил до конца
  - `failed` — автоматический запуск завершился с ошибкой
- `trigger` ∈ `{manual, scheduled, hook}` — определяет кто инициировал
- Каждый `RunbookExecution` оставляет минимум одну запись в `session-log`
- `RunbookExecution` не владеет и не порождает `FeatureRun`, `GovernanceRun`, `TwoVoiceReview`

---

## Policies

BC-wide flat table (not per-aggregate). Policy trigger ownership follows the owning aggregate — triggers from `GovernanceRun` and `TwoVoiceReview` are listed here for centralized reference (ADR-0020 Confirmation §8).

| Trigger event/condition | Owning aggregate | Policy |
|---|---|---|
| `DomainDocsChanged` | FeatureRun | Invoke `domain-reviewer` |
| `ADRDrafted` | FeatureRun | Invoke `adr-reviewer` |
| PR contains prod-bound change | FeatureRun | Invoke `security-reviewer` and `reliability-reviewer` inside `/review` phase |
| PR touches human-facing docs (`docs/runbooks/`, `docs/architecture/`, `docs/principles.md`, `README.md`) | FeatureRun | Invoke `docs-reviewer` inside `/review` phase |
| Layer 1 Gate passes on any `/review` invocation | FeatureRun | Invoke `adversarial-critic` (unconditional); findings are context for `claude_review` ReviewArtifact, not a new artifact type |
| `TwoVoiceDisagreed` and unresolved at PR time | TwoVoiceReview | Create deferred-review issue (`type:deferred-review`) |
| `CommitAttempted` without issue-ref | GovernanceRun | `GovernanceBlocked` |
| `CommitAttempted` on ADR-significant change without ADR-link | GovernanceRun | `GovernanceBlocked` |

---

## Context Map

| External BC | DDD Pattern | Notes |
|---|---|---|
| **target BC** (each pet-project) | AACL (Conformist downstream + ACL upstream) | target conforms to meta-pipeline BC schema (pipeline stages, governance rules, artifact format). meta validates incoming target artifacts through ACL. meta never reads target-domain terms as domain concepts. Full diagram: `docs/domain/context-map.md`. |
| **GitHub platform** (Issues, PRs, Projects, Actions) | Customer/Supplier + Open Host Service | Pipeline is customer. ACL via GitHub MCP server + `gh` CLI. Translates GitHub model into domain terms (issue-ref, PR body contract). |
| **ChatGPT Plus / Codex CLI** | Conformist | Pipeline takes device-auth OAuth output as-is; no translation layer. Corporate repo restriction is an operator access-gate, not a DDD pattern. |
| **Git hook system** | Customer/Supplier | `.git/hooks/` is the physical installation boundary per Principle 5. Pipeline supplies the hook; git is the consumer. |
| **Anthropic API** | Separate Ways | Claude Code abstracts it; this BC never integrates with Anthropic API directly. Both systems operate independently from the domain's perspective. |

---

## Use Cases

### UC-01: Happy Path — Feature Delivered to Main

**Actor:** Operator
**Preconditions:** GitHub issue exists with acceptance criteria; no feature branch for this issue; main is current with remote.
**Main scenario:**
1. Operator runs `/feature <N>` → issue moved to In Progress.
2. `/plan` reads issue and referenced files; produces `plan.md`.
3. `advisor()` called (pre-check): plan validated.
4. `/implement` executes plan; `advisor()` called again (pre-done).
5. `/qa` runs test coverage and docs currency checks; produces `qa-report.md`.
6. `/review` (Claude) scans diff against plan, principles, domain contracts.
7. `/codex-review` (Codex CLI) produces second-voice review.
8. Operator resolves findings; commits via governance hook.
9. `gh pr create` with `Closes #N`; issue moved to In Review.
10. Human self-review; PR merged to main.

**Alternatives:**
- (a) ADR needed: STOP after `/plan`; invoke `@agent-solutions-architect`, merge ADR, re-sync `plan.md §4`, then resume `/implement`.
- (b) `advisor()` returns STOP finding: update `plan.md` before continuing.
- (c) Two-voice disagrees: disagreement documented in PR thread; reconciled before merge.

**Postconditions:** PR merged; issue closed; `FeatureRun.dod_state = done`; all DoD boxes checked.

---

### UC-02: Codex Skip — Deferred Two-Voice Review

**Actor:** Operator (Codex CLI unavailable or quota-exhausted)
**Preconditions:** PR at `/codex-review` stage; Codex CLI is installed but unreachable (Plus OAuth stale or quota at limit).
**Main scenario:**
1. `/codex-review` invokes `bootstrap/scripts/review-codex.sh`.
2. Startup check: `timeout 10 codex --version` times out (exit 124) → SKIPPED marker.
3. `gh issue create --label type:deferred-review` opened automatically.
4. Script outputs `SKIPPED` to stdout; exits 0 (does not block pipeline).
5. Operator records skip in PR body; DoD grace clause satisfied.

**Alternatives:**
- (a) Quota exhausted (exit 4): same path as timeout.
- (b) `gh` CLI unavailable: issue creation silently skipped; SKIPPED marker still output.
- (c) Codex not installed: SKIPPED with install instruction; no issue created.

**Postconditions:** `TwoVoiceReview.state = deferred`; `type:deferred-review` issue exists; PR body documents the gap.

---

### UC-03: Governance Block — Commit Rejected

**Actor:** Operator (via Main Loop issuing `git commit` via Bash tool)
**Preconditions:** `/implement` complete; operator triggers commit via Claude Code.
**Main scenario:**
1. Claude Code PreToolUse hook fires; `pre-commit-governance.sh` receives JSON on stdin.
2. Rule 4: branch is not main → proceed.
3. Rule 1: commit message checked against Conventional Commits regex.
4. Rule 2: issue-ref `#NNN` checked in message or branch name.
5. Rule 3: staged files checked for decision markers; ADR-ref required if found.
6. Any rule fails → `json_deny` with reason; exit 2; commit blocked.

**Alternatives:**
- (a) Commit directly on main: Rule 4 fires first with "create a feature branch" message.
- (b) `--amend`: strict check skipped; exit 0.
- (c) `adr:` prefix: issue-ref and ADR-ref rules waived.
- (d) All rules pass: exit 0; commit proceeds (`GovernanceApproved`).
- (e) `jq` not installed / stdin not valid JSON: hook may fail-open (see `docs/runbooks/incident-recovery.md`).

**Postconditions:** `GovernanceBlocked` event; commit not created; operator fixes message and retries.

---

### UC-04: ADR-Significant Detection — Architecture Gate

**Actor:** Operator (running `/plan` via Main Loop)
**Preconditions:** Issue describes a change meeting at least one trigger in `docs/principles.md` (section "Что значит «архитектурно-значимо»").
**Main scenario:**
1. `/plan` reads issue and existing code.
2. Plan evaluation: at least one architectural trigger matches (new integration, BC boundary change, storage choice, etc.).
3. STOP emitted: `plan.md` includes "ADR required" notice.
4. `@agent-solutions-architect` invoked → ADR draft written to `docs/decisions/NNNN-*.md`.
5. `@agent-adr-reviewer` invoked → returns APPROVE or BLOCK findings.
6. Operator resolves findings; ADR PR merged.
7. `plan.md §4` re-synced with merged ADR; `/implement` proceeds.

**Alternatives:**
- (a) `adr-reviewer` returns BLOCK: revisions made before ADR PR merge.
- (b) Operator judges not architectural despite trigger: justification recorded in `plan.md`; no ADR authored.

**Postconditions:** `ADRMerged` event; `plan.md §4` references the ADR number; `/implement` may proceed.

---

### UC-05: Prod-Bound PR — Security and Reliability Gates

**Actor:** Operator (PR touches prod-bound paths)
**Preconditions:** PR diff touches `bootstrap/`, `.github/workflows/`, or `.git/hooks/`; or issue labeled `prod-bound`.
**Main scenario:**
1. `/review` reads diff and detects prod-bound paths.
2. `@agent-security-reviewer` invoked inside `/review` phase.
3. `@agent-reliability-reviewer` invoked inside `/review` phase.
4. Both return markdown reports (BLOCK / SUGGEST / NIT findings).
5. Operator resolves all BLOCK items before commit.

**Alternatives:**
- (a) `security-reviewer` returns BLOCK: fix required; merge blocked until resolved.
- (b) `reliability-reviewer` returns SUGGEST only: operator decides whether to address.
- (c) Both agents return no findings: review passes with no action required.

**Postconditions:** `SecurityReviewRequested` + `ReliabilityReviewRequested` events; all BLOCK items resolved; findings documented in PR description. Note: resolving BLOCK items before merge is enforced by honor — the governance hook does not mechanically block on reviewer findings (see Internal Compliance table).

---

## Domain Data Model

No storage schema. Attributes reflect domain invariants only.

### Entities

Per ADR-0020 + ADR-0027, entities are distributed across four aggregate roots.

| Entity | Owned by | Key Attributes | Valid States |
|---|---|---|---|
| **FeatureRun** | FeatureRun | `issue_ref` (string, `#NNN`, exactly one per run); `dod_state` (enum); `advisor_call_count` (int ≥ 0); `adr_required` (bool); `governance_run_ref` (ID); `two_voice_review_ref` (ID) | `in_progress → review_pending → done` (monotonic; DoD transition requires GovernanceRun.state = approved AND TwoVoiceReview.state ∈ {agreed, reconciled, deferred}) |
| **GovernanceRun** | GovernanceRun | `feature_run_ref` (ID); `retry_count` (int ≥ 0); `state` (enum: `pending \| approved`) | `pending → approved` (terminal; no backward transition; `GovernanceBlocked` increments `retry_count` without transitioning) |
| **TwoVoiceReview** | TwoVoiceReview | `feature_run_ref` (ID); `state` (enum) | `pending → agreed \| deferred \| disagreed → reconciled \| deferred` (terminal states monotonically stable — no backward transitions) |
| **DomainEvent** | BC-wide | `name` (string, PastTense); `emitted_by` (Command); `timestamp` | No state; append-only log |
| **ReviewArtifact** | Split — see note | `type` (enum: `claude_review \| codex_review` [owned by TwoVoiceReview] \| `advisor_critique` [owned by FeatureRun]); `content` (markdown); `verdict` (enum \| null) | `claude_review`, `codex_review`: `pending → approved \| blocked \| deferred`; `advisor_critique`: verdict always null (advisor returns critique only, never approves or blocks) |
| **Policy** | BC-wide | `trigger` (DomainEvent or condition); `action` (agent invocation or governance rule); `active` (bool) | `active \| waived` (waiver requires explicit justification) |

**ReviewArtifact seam:** `claude_review` and `codex_review` types are owned by `TwoVoiceReview`; `advisor_critique` type is owned by `FeatureRun`. This split is intentional — advisor is not part of two-voice review (ADR-0020, `vocabulary.md`). Three types, two owners, one entity name.

### FeatureRun invariant enforcement

| Invariant | Enforcement |
|---|---|
| Exactly one `issue_ref` per run | Governance hook Rule 2; `/feature` reads single issue number |
| `dod_state` monotonic: `in_progress → review_pending → done`; driven by `DoDSatisfied` (→ done); never reversed | Honor system — no artifact enforces the transition sequence |
| `dod_state = done` requires TwoVoiceReview.state ∈ {agreed, reconciled, deferred} AND GovernanceRun.state = approved | Honor system — cross-aggregate reads are operator judgment at DoD evaluation time |
| `advisor_call_count ≥ 2` on nontrivial tasks | Honor system — no artifact; see Internal Compliance table |
| `FeatureRun` does not read target BC domain data directly; all target artifacts enter through ACL | Honor system + ACL enforcement artifacts (`plan-lint.sh`, `pre-commit-governance.sh`, `@agent-domain-reviewer`) |

### TwoVoiceReview invariant enforcement

| Invariant | Enforcement |
|---|---|
| State machine: `pending → agreed \| deferred \| disagreed → reconciled \| deferred` | `review-codex.sh` drives `pending → deferred` path; reconciliation is operator judgment |
| Terminal states (`agreed`, `reconciled`, `deferred`) monotonically stable — no backward transitions | Honor system — no artifact; enforced by `domain-reviewer` checklist |

### GovernanceRun invariant enforcement

| Invariant | Enforcement |
|---|---|
| One GovernanceRun per FeatureRun; GovernanceBlocked increments retry counter, does not create new instance | Honor system — `pre-commit-governance.sh` enforces individual commit rules but does not track instance count |
| GovernanceApproved is terminal | Mechanical — commit proceeds and hook exits 0 |

---

## Interface Contracts

Sourced empirically from `bootstrap/scripts/review-codex.sh`, `bootstrap/hooks/pre-commit-governance.sh`, `bootstrap/commands/feature.md`, `bootstrap/universal-setup.sh`.

### External dependencies

| Interface | Operations used | Handled failures | Unhandled failures |
|---|---|---|---|
| **GitHub MCP** | MCP tools loaded and available (`issue_read/write`, PR read/review write, project item list/edit); current pipeline scripts route most ops through `gh` CLI directly — MCP acts as fallback and exploratory layer | Item not found in project → warn and continue (per `feature.md` startup block) | GitHub API rate limit; auth token expiry; MCP server unavailable — no retry in any case |
| **gh CLI** | `gh issue view`, `gh issue create --label`, `gh project item-list`, `gh project item-edit`, `gh project item-add`, `gh pr create`, `gh pr edit` | Project item not found → warn and continue; `gh` absent → SKIPPED with install instruction | Token expired → non-zero exit propagates to caller; rate limit → no retry; network failure → non-zero exit |
| **Codex CLI** | `codex --version` (startup check, 10s timeout); `codex --model gpt-5.2 exec <prompt>` (default 120s timeout) | Startup timeout (exit 124) → SKIPPED + `type:deferred-review` issue; quota (exit 4) → SKIPPED + issue; any other non-zero → SKIPPED + issue; `codex` not installed → SKIPPED; `timeout` binary absent → SKIPPED | Successful run with malformed output → not validated; device-auth token rotation needed → falls through to startup check failure |

### Internal integration points (owned by this BC)

| Mechanism | Operations | Handled failure modes | Unhandled failure modes |
|---|---|---|---|
| **pre-commit governance hook** (`pre-commit-governance.sh`) | Invoked as Claude Code PreToolUse on `git commit`; reads stdin JSON (`tool_input.command`, `cwd`); enforces Conventional Commits (Rule 1), issue-ref (Rule 2), ADR-ref for decision-type staged files (Rule 3), no-commit-to-main (Rule 4). | `--amend` → skip strict check; `adr:` prefix → waive issue-ref/ADR-ref; detached HEAD → fail-open; `cd $cwd` fails → fail-open | stdin not valid JSON → `jq` returns empty strings; malformed command string → message extraction may fail; hook file removed or corrupted → no enforcement (see Red Hotspot #8) |
| **commit-msg governance hook** (`commit-msg-governance.sh`) | Installed at `.git/hooks/commit-msg` per project via `--hook-this-repo` (ADR-0011); enforces the same rules as `pre-commit-governance.sh` on direct terminal `git commit` calls. | Same handled modes as pre-commit governance hook above | Same unhandled modes; additionally: if `.git/hooks/commit-msg` is missing or not executable, hook is silently absent for terminal commits |
| **format check hook** (`posttooluse-format.sh`) | Invoked as Claude Code PostToolUse on `Edit\|MultiEdit\|Write`; reads stdin JSON (`tool_input.file_path`); runs ruff/prettier/gofmt/eslint per file extension; emits `additionalContext` to Claude if violations found. Always exits 0 (non-blocking). Logs to `~/.claude/hooks/posttooluse.log`. | Tool not installed → exit 0, log `SKIP tool not found`; file not found → exit 0, log `SKIP file not found`; unknown extension → exit 0, log `SKIP unknown extension` | Log disk full → write may silently fail; `~/.claude/hooks/posttooluse.log` is a directory → `echo >>` fails silently |
| **universal-setup.sh** | `--install` (global skills/hooks/scripts + PostToolUse settings.json patch); `--target <repo>` (per-project commands + pipeline-version); `--hook-this-repo` (copies staged `commit-msg-governance.sh` to `.git/hooks/commit-msg`); `--check` (drift report, exits 0 always) | cp failure → `die` (exit 3); post-copy `cmp -s` mismatch → `die`; source file missing → `drift()` counter incremented; PostToolUse jq patch post-verify fail → `die` (exit 3) with original settings.json preserved | `--check` always exits 0 even with drift (use stdout, not exit code, for diagnostics) — see ADR-0019 |

---

## NFR

| Requirement | Measure | Enforcement artifact | Source |
|---|---|---|---|
| Every commit carries issue-ref (`#NNN`) and passes Conventional Commits | Commit rejected (exit 2) if any rule fails | `pre-commit-governance.sh` (PreToolUse hook) + `commit-msg-governance.sh` (`.git/hooks/commit-msg`) | ADR-0004, ADR-0011 |
| All shell scripts in `bootstrap/` pass ShellCheck with no warnings | CI job exits non-zero on any ShellCheck warning | `.github/workflows/` ShellCheck step | ADR-0012 |
| Installer exit 0 is an honest success signal — no silent partial failures | Test harness `test-install-verification.sh` — 13 assertions; all must pass | `bootstrap/scripts/test-install-verification.sh` | ADR-0019 |
| No direct commits to main | Pre-commit-governance.sh Rule 4 blocks `git commit` when branch is `main` (PreToolUse); `commit-msg-governance.sh` enforces same rule on terminal commits | `pre-commit-governance.sh` + `commit-msg-governance.sh` | ADR-0009 |

Constraints lacking a mechanical check (two-voice review completion, human self-review, `advisor ×2` on nontrivial) appear in the Internal Compliance table with honor-system designation.

---

## Internal Compliance

Every norm from `docs/principles.md` Definition of Done. **Enforcement type:** `automated` = script/CI always runs without human action; `agent-triggered` = agent invoked when condition met; `honor` = human commitment, no artifact enforces it.

**Enforcer column:** path to the hook/CI job/skill that enforces the norm, or `honor-only — see #NNN` for norms that remain on the honor system (tracked in a P2 ticket).

| Norm | Enforcement type | Enforcer | Remaining gap? |
|---|---|---|---|
| ADR merged before implementation, if architecturally significant | Automated (partial) | `bootstrap/hooks/pre-commit-governance.sh` Rule 3; `bootstrap/hooks/commit-msg-governance.sh` Rule 3 | Partial — whether an ADR was *needed* is human judgment; the hook only checks that if decision-type files are staged, an ADR ref exists |
| Domain docs updated if BC boundary or term changed | Automated (partial) | `bootstrap/hooks/pre-commit-governance.sh` Rule 3 (fires when `docs/domain/` staged, requires ADR ref); `domain-reviewer` agent invoked when `docs/domain/` changes | Partial — detecting *when* an update is needed remains human judgment; the hook only enforces traceability *when* domain files are staged. **Note:** table previously listed this as Honor — the hook coverage was already present but undocumented (#135). |
| Installer test harness passes (coverage gate N/A — pure shell/markdown repo; see note) | Automated | `.github/workflows/ci.yml` job `install-verification` — runs `bootstrap/scripts/test-install-verification.sh` (13 assertions) | No — CI blocks merge on failure. **Note:** norm text updated in #135: original "Unit tests; coverage ≥ 80%" does not apply to this repo type; installer integration test is the closest mechanical equivalent. |
| `/review` (Claude) approved | Honor | honor-only — see #202 | Yes — no merge gate; `/review` skill produces markdown report only |
| `/codex-review` approved OR `type:deferred-review` issue created | Automated (partial) | `bootstrap/scripts/review-codex.sh` — creates deferred issue on skip/quota | Partial — "approved" is human judgment; deferred-issue creation is automated |
| Disagreements between Claude and Codex resolved in PR thread | Honor | honor-only — see #203 | Yes — PR thread convention, no CI check |
| Human self-review performed | Honor | honor-only — see #204 | Yes — no artifact enforces it |
| Secret leak scan clean; dependency audit N/A for this repo (see note) | Automated | `.github/workflows/ci.yml` job `secret-scan` — scans for PEM private key headers and credential assignment patterns | No — CI blocks merge on every push/PR. Pattern grep covers the most common accidents (hardcoded private keys, credential assignment literals) for this repo type; dep-audit tools (`npm audit`, etc.) do not apply to a pure shell/markdown repo. **Note:** norm text updated in #135 from the principles.md examples which target language-specific dep audits. |
| Docs updated (README, runbook, CHANGELOG) | Agent-triggered (conditional) | `docs-reviewer` agent invoked when human-facing docs change | Partial — trigger detection is human judgment |
| Human-facing docs reviewed by `docs-reviewer` | Agent-triggered (conditional) | `docs-reviewer` agent invoked inside `/review` | Partial — trigger is human judgment; review itself is automated once triggered |
| Reliability reviewed by `reliability-reviewer` on prod-bound PRs | Agent-triggered (conditional) | `reliability-reviewer` agent invoked inside `/review` | Partial — prod-bound detection is human judgment; review itself is automated once triggered |
| CI green on all required jobs | Automated | `.github/workflows/ci.yml` (ShellCheck, setup-dry-run, install-verification, secret-scan, pr-body-check, markdown-links, gate-audit-test, adr-retirement-audit-test) | No |
| Conventional Commits; governance hook passed | Automated | `bootstrap/hooks/pre-commit-governance.sh` (PreToolUse hook) + `bootstrap/hooks/commit-msg-governance.sh` (`.git/hooks/commit-msg`) | No |
| PR body cross-references issue (`Closes #NNN`) | Automated | `.github/workflows/ci.yml` job `pr-body-check` — greps PR body for `Closes/Fixes/Resolves/Implements #NNN` (case-insensitive) on non-bot PRs | No — CI blocks merge on pull_request events. **Previously Honor; converted to automated in #135.** Note: this check requires a keyword prefix (`Closes`, `Fixes`, `Resolves`, `Implements`) — a deliberate tightening relative to the commit-msg governance hook (which accepts bare `#NNN` anywhere in the message). |
| PR body cross-references ADR if one was authored | Automated (partial) | `bootstrap/hooks/pre-commit-governance.sh` Rule 3 requires ADR-ref in commit message | Partial — commit is enforced; PR body itself is not re-checked by CI |
| `advisor()` called ≥ 2× on nontrivial tasks (beyond DoD checklist proper — included for completeness) | Honor | honor-only — see #205 (extends #101) | Yes — no mechanical trace of advisor invocations |

**Meta-result after #135:** 5 norms are fully automated (CI green, governance hook, install-verification, secret-scan, pr-body-check); 4 are partially automated (trigger detection or approval step remains human judgment); 3 are agent-triggered conditional; 4 are honor-only with P2 tracking tickets (#202 /review, #203 disagreements, #204 self-review, #205 advisor×2). Total: 16 norms. This table describes the actual enforcement state, not aspirational state — every gap is acknowledged and tracked.

---

## Security

Security model summary: governance is enforced at the physical installation boundary (per-repo, not global); no global git config is mutated; system-secret-store and GUI-dependent steps are explicitly excluded from automation. Known unmitigated gap: governance hook fails open when `jq` is missing or stdin is malformed (see Red Hotspot #8).

Authoritative sources — no duplication here:

- **ADR-0008** (`docs/decisions/0008-hardware-universal-split.md`) — hardware layer vs. universal layer split; rationale for why GUI-dependent steps and system-secret-store operations are excluded from automation.
- **ADR-0011** (`docs/decisions/0011-git-level-governance-phase2.md`) — per-repository commit-msg hook installation; isolation principle (scope limited to explicit installation); rationale for no global git config.
- **Governance hook docs** — source: `bootstrap/hooks/pre-commit-governance.sh`; recovery procedures: `docs/runbooks/incident-recovery.md`.

---

## Red Hotspots

Unresolved questions left explicit — not papered over:

1. **`domain-researcher` has no pipeline stage trigger.** ADR 0013 names this gap. Correct trigger is "docs/domain/ missing or stale", not "greenfield only". Resolution requires ADR 0014. Tracked in issue #60.
2. ~~God Aggregate: FeatureRun too large~~ — **resolved in issue #108** (`docs/decisions/0020-god-aggregate-sub-aggregate-extraction.md`). `GovernanceRun` and `TwoVoiceReview` extracted as separate aggregate roots. `FeatureRun` now owns 13 pipeline-orchestration commands; the two sub-aggregates own their respective flows. `domain-reviewer` scope updated to check all three roots.
3. **Fan-out boundary is human judgement.** "Embarrassingly parallel" (ADR 0002) is defined by examples, not a mechanical rule. No automation path identified.
4. **Codex skip ≠ Codex disapproval.** DoD requires a `deferred-review` issue on skip, but the gate between skip and fail is operator judgement. Not modelled formally.
5. **Nontrivial-task criterion for advisor-×-2** is enumerated in `docs/principles.md` but requires judgement at the margin.
6. **Skill vs agent distinction can drift.** ADR 0007 is normative but subtle; new contributors may conflate them.
7. **ADR 0013 cited in domain policies is `proposed`, not `accepted`.** Policy `DomainDocsChanged → domain-reviewer` is contingent on ADR 0013 being accepted. This doc should be updated once ADR 0013 status changes.
8. **Governance hook fails open on malformed input.** If `jq` is not installed or stdin is not valid JSON, `pre-commit-governance.sh` exits 0 (fail-open), bypassing all commit policy rules. Documented in `docs/runbooks/incident-recovery.md` but not mechanically mitigated. Tracked in issue #109.
9. ~~`BacklogGroomed` placement in Commands and Domain Events is unresolved~~ — resolved in issue #107: removed from Commands table; cross-reference note points to `BacklogGroomRun` separate aggregate. ADR to formalise the split still pending.
10. ~~Worktree isolation (ADR-0017) not modelled~~ — resolved in issue #110: added to Boundary "In scope".
