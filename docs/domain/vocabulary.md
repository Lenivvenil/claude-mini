# Ubiquitous Language — claude-mini-pipeline

> **DEPRECATED as of ADR-0027 (2026-05-06).** This file has been migrated to `docs/domain/meta/vocabulary.md`. The canonical vocabulary for `meta-pipeline BC` lives there. This file is kept for historical ADR cross-reference integrity. Do not edit; do not use as source of truth.

**Version:** 2026-05-04
**Status:** superseded by `docs/domain/meta/vocabulary.md` (ADR-0027, issue #130)

Terms are listed alphabetically. Each entry: one-sentence definition, then discriminating note where the term is easily confused.

---

## AC alignment

The property of a feature branch diff where every acceptance criterion in the linked issue is addressed by at least one code, test, or doc change. Verified by the `/intent-check` skill, which classifies each AC item as `covered | partial | missing | unrelated-changes`. The check is advisory — `missing` findings surface for operator decision, not automatic pipeline block.

*Discriminating note:* AC alignment is not the same as test coverage. A branch can have 100% test coverage while still missing an AC item (the tests cover the wrong behavior). `/intent-check` checks semantic intent; `verify.sh` and test runners check code correctness.

---

## ADR (Architecturally Significant Decision Record)

A MADR 4.0 document in `docs/decisions/NNNN-*.md` recording a decision that meets at least one trigger in `docs/runbooks/adr-trigger.md`. Required before implementation; merged via canonical pipeline.

*Discriminating note:* a plan is not an ADR. If no trigger fires, use `/plan`, not `/adr`.

---

## active_feature_run_id

The `STATE.md` field holding a reference (issue number, e.g., `#128`) to the `FeatureRun` currently in progress, or `null` if no run is active. Read-only pointer across the BC boundary into `claude-mini-pipeline`; resolves to a `FeatureRun` aggregate that Session Continuity does not own.

*Discriminating note:* this is a reference, not an embedded copy of `FeatureRun` state. Session Continuity reads `FeatureRun.dod_state` by ID at snapshot time; it does not mirror or cache it (ADR-0020 cross-aggregate communication pattern, ADR-0024 sub-decision 2).

---

## Advisor

The Opus model instance invoked via `advisor()` to critique plans and review completed work. Always called at least twice on nontrivial tasks: before starting substantive work and before declaring done. Returns critique only — never edits files.

*Discriminating note:* the advisor is not part of the two-voice review. Two-voice = Claude `/review` + Codex `/codex-review`. Advisor = operator's senior consultant.

---

## Agent

A Claude Code subagent with a defined role and constrained toolset. Two subtypes per ADR 0007:
- **Read-only critic** — reads and evaluates, returns markdown report, never writes: `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `reliability-reviewer`, `backlog-groomer`, `docs-reviewer`, `adversarial-critic`.
- **Author-gateway** — invokes a write-capable skill for docs artifacts only: `domain-researcher`, `solutions-architect`.

*Discriminating note:* "agent" in generic AI parlance means any AI agent. Inside this BC it means specifically a Claude Code subagent with the constraints above. See `docs/decisions/0007-read-only-critic-agents.md`.

---

## Author-gateway

An agent subtype that can invoke a write-capable skill to produce documentation artifacts (`docs/decisions/`, `docs/domain/`). Does not write production code. Does not edit existing files. Examples: `domain-researcher` (→ `domain-discovery` skill), `solutions-architect` (→ `adr-author` skill). See ADR 0007.

---

## Canonical Pipeline

The documented sequence in `CLAUDE.md:27-34`: `task-to-issue → plan → adr (if needed) → implement → review → codex-review → governance → PR`. The single authoritative path for feature work. Deviations require justification. Orchestrated by `/feature`.

---

## Continuity (property)

The property that work-in-progress survives the boundary between LLM sessions: any next session can read `STATE.md` + the most recent `session-log` entry and resume meaningful work without interrogating the operator. Continuity is the goal; the Session Continuity BC owns the artifacts that maintain it.

*Discriminating note:* continuity is not the same as persistence. Persistence is "data still exists on disk." Continuity is "a new session can act on that data without ramp-up."

---

## dod_state

The `FeatureRun` attribute tracking pipeline progress. Valid transitions: `in_progress → review_pending → done` (monotonic; never reversed within a run). Driven by pipeline stage completion events.

*Discriminating note:* `dod_state` is not the same as the DoD checklist. The checklist is a set of boolean flags; `dod_state` is the aggregate state derived from them.

---

## Definition of Done (DoD)

The checklist in `docs/runbooks/dod-checklist.md` that every change must satisfy before merge. Includes: ADR merged (if significant), domain docs updated (if BC changed), reviews passed, CI green, governance hook passed, PR body cross-references.

*Discriminating note:* DoD is the merge gate, not a style guide. Unchecked boxes block merge.

---

## Deferred Review

The state in which the second voice of two-voice review could not complete. Represented as a GitHub issue of type `type:deferred-review` (the artifact). Created when `/codex-review` is skipped (e.g., Plus OAuth quota exhausted, corporate repo gate). Satisfies the DoD graceful-degradation clause. Does not substitute for a passing review.

*Naming note:* "Deferred Review" is the concept/state. "deferred-review issue" is the GitHub artifact. `DeferredReviewIssueCreated` is the domain event. Three forms, one concept.

---

## blocked_on

A `STATE.md` field naming the single concrete obstacle preventing forward progress, or `null` if not blocked. Phrased as a noun-phrase referencing a person, ticket, decision, or external system ("waiting on operator decision re: ADR-0021", not "lots of stuff to think about").

*Discriminating note:* `blocked_on` is operator-asserted at snapshot time; no agent infers it. Distinct from `risk_flags` — `blocked_on` is a hard stop right now; `risk_flags` are warnings about possible future stops.

---

## Bypass (gate)

An instance of a gate being deliberately skipped, circumventing its enforcement. Occurs when an operator runs `git commit` directly (bypassing the Claude Code hook) or uses a workaround known to skip a specific gate. Contributes to the `bypasses` field in `GateAuditWeek`. Not automatically detected; must be manually recorded in `events.jsonl`.

*Discriminating note:* a bypass is an intentional skip, not a gate failure or a false positive. A gate that always fires and is always a false positive has `fp > 0`; one that is actively circumvented has `bypasses > 0`.

---

## False Positive (gate)

A gate blocking an action that was, upon operator judgment, a legitimate operation. The gate fired correctly (it detected the pattern it was designed to detect), but the detection was unwarranted in context. Recorded by `bash ~/.claude/scripts/forge.sh gate-tag <event_id> --false-positive` (see `bootstrap/skills/gate-audit/SKILL.md` for full invocation). Contributes to `false_positives` in `GateAuditWeek`. High false-positive rate is the primary signal for `REMOVE`.

*Discriminating note:* a false positive is not a gate bug. A bug fires in error (unexpected path); a false positive fires on a real pattern that happens not to matter here.

---

## Fan-out


Spawning multiple parallel agents or sub-tasks. Forbidden for feature work (ADR 0002). Permitted only for embarrassingly-parallel tasks: symbol renames across many files, import migrations, test templating from schema.

*Discriminating note:* embarrassingly-parallel is defined by examples, not a mechanical rule. Operator judgement required at the margin.

---

## Feature Pipeline

The canonical multi-stage workflow for delivering a change: issue → plan → (ADR) → implement → review → codex-review → governance → PR. Orchestrated by the `/feature` skill. Synonymous with Canonical Pipeline.

---

## Feature Run

One complete execution of `/feature <issue-number>`. The orchestrating aggregate root of `claude-mini-pipeline` BC. Holds full context (`issue_ref`, `dod_state`, `advisor_call_count`) from pipeline start to merge. Delegates to `GovernanceRun` and `TwoVoiceReview` sub-cycles and reads their terminal states at DoD evaluation.

Invariants: single issue reference; monotonic `dod_state` (`in_progress → review_pending → done`); `dod_state = done` requires `GovernanceRun.state = approved` AND `TwoVoiceReview.state ∈ {agreed, reconciled, deferred}`; advisor called ≥ 2 times on nontrivial work.

*Discriminating note:* `FeatureRun` no longer owns `two_voice_state` — that attribute migrated to `TwoVoiceReview` (ADR-0020). `FeatureRun` reads `TwoVoiceReview.state` by ID reference; it does not embed a copy.

---

## Format Check Hook

The `posttooluse-format.sh` Claude Code hook registered under `PostToolUse[Edit|MultiEdit|Write]` in `~/.claude/settings.json`. Runs after every file write to check formatting and linting: Python → `ruff format --check` + `ruff check`; JS/TS → `prettier --check` + `eslint` (if config present); Go → `gofmt -l` + `go vet`. Non-blocking (always exits 0). Surfaces findings to Claude via `hookSpecificOutput.additionalContext` so Claude can self-correct in-session. Logs to `~/.claude/hooks/posttooluse.log`.

*Discriminating note:* the Format Check Hook is not the Governance Hook. The Format Check Hook runs on every file write (PostToolUse) and warns only. The Governance Hook runs on commit attempts (PreToolUse) and blocks on rule violations.

---

## GateAuditWeek

A read-model summary record (not a DDD aggregate root) for gate ROI: one (gate_name, week_iso) pair from `docs/gate-audit/aggregate.jsonl`. Fields: `frequency` (total fires), `real_blocks`, `false_positives`, `bypasses`, `est_cost_min`, `retention_rec`. The `retention_rec` field is computed over the last 4 qualifying `GateAuditWeek` records for a gate, not within a single week. Produced by `gate-audit-aggregate.sh`; not owned by any aggregate root within this BC.

*Discriminating note:* `GateAuditWeek` is a read-model summary record, not a DDD aggregate root. The three aggregate roots of this BC remain `FeatureRun`, `GovernanceRun`, `TwoVoiceReview` (ADR-0020). `GateEvent` is the raw per-fire record.

---

## GateEvent

A single gate fire recorded in `docs/gate-audit/events.jsonl`. Fields: `event_id`, `gate_name`, `timestamp`, `week_iso`, `outcome` ("blocked" | "allowed"), `classification` (null | "real" | "false-positive"), `cost_min`. Written by the hook immediately after the gate decision is made. Tagged post-hoc by the operator via `forge gate-tag`.

*Discriminating note:* `GateEvent` captures one fire, regardless of outcome. `GateAuditWeek` aggregates many `GateEvent` records. Not every `GateEvent` reaches `GateAuditWeek` — unclassified blocked events contribute to `frequency` only.

---

## Governance Hook

The `pre-commit-governance.sh` shell hook registered under `PreToolUse[Bash]` in `~/.claude/settings.json`. Enforces Conventional Commits prefix and issue-ref (`#NNN`) on every commit attempt made by Claude. For ADR-significant changes, also enforces `Implements docs/decisions/NNNN-*.md`. Blocks commit if rules fail (`GovernanceBlocked` event). A companion script `commit-msg-governance.sh` is installed at `.git/hooks/commit-msg` per project (via `--hook-this-repo`) to enforce the same rules on direct terminal commits.

*Discriminating note:* the Governance Hook is not the Format Check Hook. The Governance Hook blocks on rule violations (PreToolUse, exit 2 = deny). The Format Check Hook warns after file writes (PostToolUse, always exit 0).

---

## GovernanceRun

An aggregate root within `claude-mini-pipeline` BC. One commit-governance episode per `FeatureRun`. Created by `FeatureRun` on `FeaturePipelineStarted`; remains in `pending` state until `AttemptCommit` is first called. Owns: command `AttemptCommit`; events `CommitAttempted`, `GovernanceBlocked`, `GovernanceApproved`; internal `retry_count`.

State machine: `pending → approved` (terminal). `GovernanceBlocked` increments retry counter without changing the instance; `GovernanceApproved` terminates it. `GovernanceRun.state = approved` is required for `FeatureRun.dod_state = done`. Enforcement artifact: `pre-commit-governance.sh`.

*Discriminating note:* `GovernanceRun` is not the same as the governance hook. The hook is the enforcement mechanism; `GovernanceRun` is the domain aggregate that models the lifecycle of one commit-governance episode.

---

## Governance-blocked Commit

A commit rejected by the governance hook. Not a failure state — it is the hook doing its job. Operator fixes the commit message and retries.

---

## Hand-off (triple)

The contract by which a session transfers state to its successor: `STATE.md` (snapshot, replaces) + `session-log/YYYY/MM/YYYY-MM-DD.md` (history, appends) + `plan.md` linter pass (decision discipline, gates). Called "triple" because all three artifacts must be in their valid post-hand-off state simultaneously for the hand-off to be considered complete.

*Discriminating note:* a hand-off is not a commit. A commit changes the repo; a hand-off prepares for session change. They often coincide but are not the same — a session can hand off without committing (e.g., end-of-day with WIP), and a commit can happen without a hand-off (mid-session progress commit).

---

## Human Resume Test

The acceptance criterion for Session Continuity: an operator (or a fresh agent) given only `STATE.md` and the latest `session-log` entry can identify the next concrete action and begin work within five minutes. The five-minute budget is a sustained design constraint, not a stopwatch metric per session.

*Discriminating note:* the Human Resume Test is the BC's primary NFR, not a unit test. It is verified by periodic operator drill (see `docs/runbooks/resume-drill.md`) or by post-mortem after a real resume. It is not mechanically measured per session.

---

## IntentCheck (skill)

The `/intent-check` skill that compares acceptance criteria from a GitHub issue against `git diff main...HEAD` for a feature branch. Outputs a per-AC-item table with statuses `covered | partial | missing | unrelated-changes` and an evidence file:line pointer for each claim. Runs at two points in the pipeline: after `/implement` (step 5c in `/feature`) and inside `/review` Layer 2 as the `**AC alignment**` subsection.

*Discriminating note:* IntentCheck is a skill, not an agent — it is invoked by the operator (or by `/feature` checklist nudge), not autonomously by the pipeline. It does not block merge; its output is advisory and operator-resolved.

---

## Issue-first

The rule that any task longer than one session must have a GitHub issue before work starts. Enforced by the governance hook (commit-msg requires `#NNN`). Issues created via `/task-to-issue`.

---

## Layer 1 Gate

The deterministic verification phase within `/review` that runs `~/.claude/scripts/verify.sh` before any LLM analysis. Outputs `LAYER1_PASSED` or `LAYER1_FAILED`. When it passes, Layer 2 (LLM review) and Layer 3 (adversarial-critic) both proceed. When it fails, `/review` stops and the operator must resolve the deterministic findings before re-invoking.

*Discriminating note:* "Layer 1 Gate" is often abbreviated "Layer 1" in implementation artifacts (`bootstrap/commands/review.md`). In domain language, use "Layer 1 Gate" to distinguish it from the LLM-review phases (Layer 2, Layer 3). The gate is a single `verify.sh` invocation — not a separate aggregate; it is a precondition step owned by `FeatureRun`.

---

## Main Loop

The Sonnet model instance that orchestrates all pipeline actions within a session. Has write authority over files and GitHub (within permissions). Distinct from the advisor (read-only) and agents (subagents with constrained toolsets).

---

## open_questions

A `STATE.md` field listing zero or more unresolved questions the current session encountered that the next session needs answers for before progressing. Each entry is one line, phrased as a question with enough context that a reader who was not present can understand what is being asked.

*Discriminating note:* `open_questions` is not the same as `Red Hotspot`. `Red Hotspot` is a BC-level invariant tension surfaced in `overview.md#red-hotspots` and may persist for sprints. `open_questions` is per-session and short-lived — resolved within hours/days or escalated to a Red Hotspot or GitHub issue. Lifecycle, scope, and audience differ.

---

## Operator

The human running Claude Code. Sole author of production code. Final decision-maker on all architectural choices. Claude is a "soul-crushing partner, not an expert" (Principle 2) — the operator is the expert.

---

## Pipeline Stage

A named step within the Feature Pipeline: `/plan`, `/adr`, `/implement`, `/review`, `/codex-review`, governance commit, `gh pr create`. Stages are ordered and gated; skipping a stage requires explicit justification.

---

## plan.md Linter

A grep-based bash script (`bootstrap/scripts/plan-lint.sh`) that scans the current `plan.md` and verifies every entry in §3 ("Approaches considered") and §4 ("Selected approach") that asserts a design decision carries an `ADR-ref` (`docs/decisions/NNNN-*.md`) or an explicit exemption (`"no ADR — justification: ..."`). Run as part of the hand-off contract; failure blocks the hand-off from being declared complete. No LLM dependency — bash and grep only (Principle 3).

*Discriminating note:* the plan.md linter enforces ADR-discipline on plan content, which is a `claude-mini-pipeline` concern, but is invoked from the hand-off contract, which is a Session Continuity concern. This BC owns the *invocation* (when to run); `claude-mini-pipeline` owns the *rule definition* (what counts as a design decision).

---

## Read-only Critic

An agent subtype that reads artifacts and returns a markdown report. Never writes to the filesystem. Never mutates GitHub. Examples: `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `reliability-reviewer`, `backlog-groomer`, `docs-reviewer`. See ADR 0007.

---

## Red Hotspot

An unresolved question or known invariant violation that the domain docs explicitly leave open. Flagged honestly rather than papered over. Current hotspots: see `overview.md#red-hotspots`.

---

## Real Block (gate)

A gate blocking an action that, upon operator judgment, was a genuine violation that the gate was correct to catch. Recorded by `bash ~/.claude/scripts/forge.sh gate-tag <event_id> --real` (see `bootstrap/skills/gate-audit/SKILL.md` for full invocation). Contributes to `real_blocks` in `GateAuditWeek`. A gate with consistently high `real_blocks / (real_blocks + false_positives + bypasses)` ratio has proven ROI and should be kept.

*Discriminating note:* "real block" is the operator's post-hoc judgment, not the gate's output. The gate does not distinguish real from false-positive at fire time.

---

## Resume

The act of a new session reading the hand-off artifacts and beginning meaningful work on the previous session's outstanding context. Distinct from "starting fresh" (no prior STATE.md) and from "continuing within a session" (no session boundary crossed).

*Discriminating note:* a resume succeeds when the first action a new session takes matches one of the prior session's `next_3_actions` (or explicitly supersedes one with justification). A resume that re-plans from scratch is a continuity failure, not a successful resume.

---

## risk_flags

A `STATE.md` field listing zero or more known risks the next session should be aware of: pending external dependencies, suspected bugs not yet investigated, drift between docs and code, etc. Each flag is one line; `risk_flags: []` is a valid (and common) state.

*Discriminating note:* `risk_flags` are warnings, not blockers — work can proceed despite them. `blocked_on` is a single hard stop; `risk_flags` is a list of soft warnings.

---

## RetentionRecommendation

The decision-rule output for a gate over a rolling 4-week window: `KEEP`, `REMOVE`, or `INSUFFICIENT_DATA`. Computed by `gate-audit-aggregate.sh` from `GateAuditWeek` records. `REMOVE` means `real / (real + fp + bypass) < 0.2` for all 4 qualifying weeks. Requires human approval before any gate is actually removed — this is a recommendation, not an automatic action.

*Discriminating note:* `REMOVE` is not a verdict; it is a prompt for human review. The gate stays active until a human opens and merges a PR to remove it.

---

## Session

A continuous interval of LLM (Claude Code) operation under a single operator presence, bounded on each side by a session-end event (operator closes the client, advisor times out, machine sleeps, day rolls over). Identified by `session_id` in `STATE.md`. The unit of work that hand-offs occur between.

*Discriminating note:* a session is not a `FeatureRun`. A single session may span zero, one, or several `FeatureRun`s; a single `FeatureRun` typically spans several sessions. They are orthogonal lifecycles.

---

## session-log

The append-only daily log file at `session-log/YYYY/MM/YYYY-MM-DD.md` recording per-session entries: session boundaries, significant decisions, advisor calls, hand-off events. One file per UTC day; entries are appended chronologically (newest-at-bottom) and never edited or deleted.

*Discriminating note:* session-log is not the same family as `docs/gate-audit/events.jsonl`. Both are append-only logs, but session-log is human-readable narrative for resume; `events.jsonl` is structured machine data for ROI analysis. They serve different consumers and are not unified by design (ADR-0024, sub-decision 8).

---

## session_id

A `STATE.md` field uniquely identifying the session that wrote the current snapshot. Format: UTC ISO-8601 timestamp (e.g., `2026-05-03T14:32:00Z`) — human-readable, sortable, no external dependencies (ADR-0024, sub-decision 3).

*Discriminating note:* `session_id` identifies the *writer* of the snapshot, not the `FeatureRun`. The `active_feature_run_id` field is a separate reference into a different BC.

---

## Skill

A slash-command (`/plan`, `/adr`, `/implement`, `/review`, `/feature`, etc.) that executes under main-loop authority. Has full write capability (subject to permissions). Distinct from agents, which are subagents with constrained toolsets.

*Discriminating note:* a skill is not an agent. Skills run inside the main loop. Agents are separate Claude Code subagents. This distinction is normative in ADR 0007 and subtle in practice.

---

## STATE.md

The repo-root snapshot file (≤200 lines) with nine fields recording the current resumable state of work: `session_id`, `date_iso`, `current_branch`, `last_commit_sha`, `active_feature_run_id`, `next_3_actions`, `blocked_on`, `open_questions`, `risk_flags`. The aggregate root of the Session Continuity BC. Replaced (not appended) on each hand-off; the prior state moves to `session-log` history.

Invariants (ADR-0024): ≤200 lines; all nine fields present (empty values `null`/`[]` are valid; missing keys are not); replaced not appended on each hand-off; `active_feature_run_id` is a reference only — Session Continuity does not duplicate `FeatureRun` state.

*Discriminating note:* `STATE.md` is not a backlog and not a runbook. It is a thin snapshot whose only job is to satisfy the Human Resume Test. Anything that does not contribute to a five-minute resume should not be in STATE.md.

---

## Honor-System Gap

A norm in the Internal Compliance table that has no mechanical enforcement artifact — it depends on operator discipline alone. Labeled explicitly in the `Honor-system gap?` column as "Yes." The existence of a gap does not mean the norm is optional; it means there is no automated gate preventing violation.

*Discriminating note:* a partial-automation gap (e.g., "agent-triggered but trigger detection is human judgment") is different from a full honor-system gap. Both are documented, but full gaps carry higher regression risk.

---

## Interface Contract

A row in the Interface Contracts section of a BC overview specifying: interface name, operations used, handled failure modes, and explicitly unhandled failure modes. Sourced empirically from code — not inferred. Unhandled failures are as important as handled ones: they define the boundary of what the pipeline can recover from.

---

## Internal Compliance

The section of a BC overview mapping each Definition of Done norm to its enforcement type (`automated | agent-triggered | honor`), the concrete artifact enforcing it, and whether a honor-system gap exists. Distinct from NFR: NFR states what the system must do; Internal Compliance states how each DoD norm is actually enforced (or not).

---

## next_3_actions

A `STATE.md` field listing exactly three ordered, concrete next actions, written as imperatives (e.g., "Run /implement on plan.md §3"). Cardinality is fixed at three: fewer signals premature stop, more signals lack of focus. The field is `[]` only when `blocked_on != null` or all work is complete.

*Discriminating note:* `next_3_actions` describes the immediate plan, not the full backlog. The full backlog lives in GitHub issues; `next_3_actions` is the slice the next session executes first.

---

## NFR (Non-Functional Requirement)

In this BC: a measurable constraint on pipeline behavior that is already mechanically verified by an existing check or ADR. Speculative constraints and intent-only statements are excluded. Constraints without mechanical checks appear in the Internal Compliance table as honor-system rows instead.

*Discriminating note:* not every quality attribute is an NFR in this BC's sense. A constraint must have a cited enforcement artifact to qualify.

---

## Policy (entity)

A domain entity capturing the rule "when trigger X, then action Y." Distinct from the Policies *table* (which is the collection of all active policies). A Policy entity has `trigger`, `action`, and `active` attributes. A waived policy requires explicit justification.

*Discriminating note:* "policy" (lowercase) in generic English means any rule. `Policy` in this BC means a specific persistable domain entity with a trigger-action pair and an active state.

---

## ReviewArtifact

A domain entity representing the output of a review step. Three types, two owners (ADR-0020):
- `claude_review` — owned by `TwoVoiceReview`; verdict: `pending → approved | blocked | deferred`
- `codex_review` — owned by `TwoVoiceReview`; verdict: `pending → approved | blocked | deferred`
- `advisor_critique` — owned by `FeatureRun`; verdict always null (advisor returns critique only, never approves or blocks)

The split is intentional: advisor is not part of two-voice review. `claude_review` and `codex_review` form the two-voice pair; `advisor_critique` is pre-work validation outside that pair.

*Discriminating note:* a ReviewArtifact is not the same as the act of reviewing. It is the *persisted output* of a review step. The type-discriminator determines which aggregate owns the instance.

---

## Triple Hand-off Contract

The combined precondition that all three hand-off artifacts (STATE.md updated and ≤200 lines; session-log entry appended for today; plan.md linter passing) are simultaneously valid. The contract is binary: all three pass, or hand-off is incomplete. Partial hand-offs are not a recognised state.

*Discriminating note:* "triple" is normative, not descriptive. It enforces that snapshot-without-history (STATE.md changes but no log entry) and history-without-snapshot (log entry but stale STATE.md) are both equally broken. The plan.md linter as the third leg is a Session Continuity design choice (ADR-0024).

---

## Two-voice Review

The gating mechanism combining `/review` (Claude main loop) and `/codex-review` (Codex CLI). Both must pass or their disagreement must be reconciled in the PR thread. If Codex is unavailable, a deferred-review issue is created.

*Discriminating note:* two-voice = Claude vs Codex. Advisor is not part of two-voice.

---

## TwoVoiceReview

An aggregate root within `claude-mini-pipeline` BC. One two-voice review episode per `FeatureRun`. Owns: commands `RequestReview`, `RequestCodexReview`, `RecordTwoVoiceResult`; all two-voice events; `ReviewArtifact` entities of type `claude_review` and `codex_review`; the `two_voice_state` machine.

State machine: `{pending → agreed | pending → deferred | pending → disagreed | disagreed → reconciled | disagreed → deferred}`. Terminal states (`agreed`, `reconciled`, `deferred`) are monotonically stable — no backward transitions. `TwoVoiceReview.state ∈ {agreed, reconciled, deferred}` is required for `FeatureRun.dod_state = done`.

*Discriminating note:* `TwoVoiceReview` (the aggregate root) is not the same as "two-voice review" (the gating concept). The aggregate owns the lifecycle; the concept names the protocol.

---

## two_voice_state

The `TwoVoiceReview` aggregate attribute tracking the two-voice review state machine. Valid transitions: `pending → agreed | pending → deferred | pending → disagreed | disagreed → reconciled | disagreed → deferred`. The `deferred` state is reachable from both `pending` (Codex skip without disagreement) and `disagreed` (skip after unresolved conflict). Terminal states are monotonically stable.

*Discriminating note:* `two_voice_state` is the vocabulary term name for this concept. The aggregate attribute name on `TwoVoiceReview` is `state` — use `TwoVoiceReview.state` in cross-aggregate references, not `TwoVoiceReview.two_voice_state`. The term migrated from `FeatureRun` to `TwoVoiceReview` in ADR-0020; references to `FeatureRun.two_voice_state` in pre-ADR-0020 docs are stale.

---

## Use Case

A scenario in the Use Cases section describing how an actor achieves a goal with this BC. Required structure: Actor, Preconditions, Main scenario (numbered steps), Alternatives (lettered), Postconditions. Use Cases are the primary navigation entry point for new contributors: they show *why* the pipeline behaves as it does, not just *what* it does.

*Discriminating note:* a Use Case is not a user story ("As a … I want … so that …"). It is a structured scenario with explicit alternatives and postconditions.

---

## Ubiquitous Language

The shared vocabulary of this bounded context. Terms here are used with their definitions above in all ADRs, issues, PR descriptions, runbooks, and conversations. Drift from these definitions is detected by `domain-reviewer`.
