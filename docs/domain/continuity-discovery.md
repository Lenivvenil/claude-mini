# Session Continuity — Domain Discovery

**Status:** discovery draft (pre-implementation, issue #128)
**Date:** 2026-05-03
**Author:** `domain-researcher`
**Scope:** propose a Ubiquitous Language extension and a Bounded Context Canvas sketch for a new "Session Continuity" bounded context. **Not** a vocabulary.md edit — that is for the operator to merge after review.
**Relationship to `claude-mini-pipeline`:** sibling BC, not a sub-aggregate. Session Continuity *observes* `FeatureRun` (read-only reference via `active_feature_run_id`); it does not own pipeline orchestration. See "Boundary tensions" red hotspot below for the two unresolved seams.

---

## Why a new BC

`claude-mini-pipeline` owns *one feature delivery* end-to-end (`FeatureRun` lifecycle: issue → plan → ADR → implement → review → PR → merge). It does not own *what happens between LLM sessions* — the moment the session ends and a new operator (or the same operator on a new day) tries to pick up where things stopped.

Issue #128 introduces three artifacts whose collective purpose is "the next session can resume in ≤5 minutes":
- `STATE.md` — snapshot (≤200 lines)
- `session-log/YYYY/MM/YYYY-MM-DD.md` — append-only daily log
- `plan.md` linter — verifies design-decision → ADR-ref discipline

The first two clearly belong to a continuity-of-work concern that spans multiple `FeatureRun`s and multiple sessions. The third is borderline (see hotspot #1).

A separate BC keeps `FeatureRun` invariants clean: `FeatureRun` already has 13 commands and a non-trivial state machine. Folding "session snapshot" attributes into it would re-create the God Aggregate problem ADR-0020 just solved.

---

## Ubiquitous Language extension (proposed additions)

These entries are written in the style of `docs/domain/vocabulary.md` (alphabetical, one-sentence definition, discriminating note where confusion is likely). They are **proposed additions only** — `vocabulary.md` is not edited by this discovery doc.

Existing terms (`FeatureRun`, `GovernanceRun`, `TwoVoiceReview`, `Operator`, `Main Loop`, `ADR`, etc.) are referenced but not redefined.

**Intentional exclusions from the UL extension.** Three of the nine `STATE.md` fields are deliberately **not** added as Ubiquitous Language terms because they carry no discriminating semantic weight beyond their plain meaning: `date_iso` (ISO-8601 calendar date), `current_branch` (git branch name), `last_commit_sha` (git commit SHA). They are described in `STATE.md`'s field list and need no separate dictionary entry. The remaining six fields plus `STATE.md`, `session-log`, `Session`, and the conceptual umbrella terms (`Hand-off`, `Continuity`, `Resume`, `Human Resume Test`, `Triple Hand-off Contract`, `plan.md Linter`) are defined below.

---

### active_feature_run_id

One of the nine `STATE.md` fields holding a reference (issue ref, e.g., `#128`) to the `FeatureRun` currently in progress, or `null` if no run is active. Read-only pointer across the BC boundary into `claude-mini-pipeline`; resolves to a `FeatureRun` aggregate that Session Continuity does not own.

*Discriminating note:* this is a reference, not an embedded copy of `FeatureRun` state. Session Continuity reads `FeatureRun.dod_state` by ID at snapshot time; it does not mirror or cache it (ADR-0020 cross-aggregate communication pattern).

---

### blocked_on

A `STATE.md` field naming the single concrete obstacle preventing forward progress, or `null` if not blocked. Phrased as a noun-phrase referencing a person, ticket, decision, or external system — not a free-form excuse ("waiting on operator decision re: ADR-0021", not "lots of stuff to think about").

*Discriminating note:* `blocked_on` is operator-asserted at snapshot time; no agent infers it. Distinct from `risk_flags` — `blocked_on` is a hard stop right now; `risk_flags` are warnings about possible future stops.

---

### Continuity (property)

The property that work-in-progress survives the boundary between LLM sessions: any next session can read `STATE.md` + the most recent `session-log` entry and resume meaningful work without interrogating the operator. Continuity is the goal; the Session Continuity BC owns the artifacts that maintain it.

*Discriminating note:* continuity is not the same as persistence. Persistence is "data still exists on disk." Continuity is "a new session can act on that data without ramp-up."

---

### Hand-off (triple)

The contract by which a session transfers state to its successor: `STATE.md` (snapshot, replaces) + `session-log/YYYY/MM/YYYY-MM-DD.md` (history, appends) + `plan.md` linter pass (decision discipline, gates). Called "triple" because all three artifacts must be in their valid post-hand-off state simultaneously for the hand-off to be considered complete.

*Discriminating note:* a hand-off is not a commit. A commit changes the repo; a hand-off prepares for session change. They often coincide but are not the same — a session can hand off without committing (e.g., end-of-day with WIP), and a commit happens without hand-off (mid-session).

---

### Human Resume Test

The acceptance criterion for Session Continuity: an operator (or a fresh agent) given only `STATE.md` and the latest `session-log` entry can identify the next concrete action and begin work within five minutes. The five-minute budget is a sustained design constraint, not a stopwatch metric per session.

*Discriminating note:* the Human Resume Test is the BC's primary NFR, not a unit test. It is verified by periodic operator drill (rare) or by post-mortem after a real resume (common). It is not mechanically measured.

---

### next_3_actions

A `STATE.md` field listing exactly three ordered, concrete next actions, written as imperatives (e.g., "Run /implement on plan.md §3"). Cardinality is fixed at three: fewer signals premature stop, more signals lack of focus.

*Discriminating note:* `next_3_actions` describes the immediate plan, not the full backlog. The full backlog lives in GitHub issues; `next_3_actions` is the slice the next session executes first.

---

### open_questions

A `STATE.md` field listing zero or more unresolved questions the current session encountered that the next session needs answers for before progressing. Each entry is one line, phrased as a question with enough context that a reader who was not present can understand what is being asked.

*Discriminating note:* `open_questions` is **not** the same as `Red Hotspot`. `Red Hotspot` (defined in `vocabulary.md`) is a BC-level invariant tension surfaced in `overview.md#red-hotspots` and may persist for sprints. `open_questions` is per-session and short-lived — resolved within hours/days or escalated to a Red Hotspot or GitHub issue. Lifecycle, scope, and audience differ.

---

### plan.md Linter

A check that scans the current `plan.md` and verifies every entry under §4 ("Selected approach") and §3 ("Approaches considered") that asserts a design decision carries an `ADR-ref` (`docs/decisions/NNNN-*.md` or explicit "no ADR — justification: ..."). Run as part of the hand-off contract; failure blocks the hand-off from being declared complete.

*Discriminating note:* the plan.md linter enforces ADR-discipline on plan content, which is `claude-mini-pipeline` concern, but is invoked from the hand-off contract, which is Session Continuity concern. This BC owns the *invocation* (when to run); `claude-mini-pipeline` owns the *rule definition* (what counts as a design decision). See hotspot #1.

---

### Resume

The act of a new session reading the hand-off artifacts and beginning meaningful work on the previous session's outstanding context. Distinct from "starting fresh" (no prior STATE.md) and from "continuing within a session" (no session boundary crossed).

*Discriminating note:* a resume succeeds when the first action a new session takes matches one of the prior session's `next_3_actions` (or explicitly supersedes one with justification). A resume that re-plans from scratch is a continuity failure, not a successful resume.

---

### risk_flags

A `STATE.md` field listing zero or more known risks the next session should be aware of: pending external dependencies, suspected bugs not yet investigated, drift between docs and code, etc. Each flag is one line; `risk_flags: []` is a valid (and common) state.

*Discriminating note:* `risk_flags` are warnings, not blockers — work can proceed despite them. `blocked_on` is a single hard stop; `risk_flags` is a list of soft warnings.

---

### Session

A continuous interval of LLM (Claude Code) operation under a single operator presence, bounded on each side by a session-end event (operator closes the client, advisor times out, machine sleeps, day rolls over). Identified by `session_id` in `STATE.md`. The unit of work that hand-offs occur between.

*Discriminating note:* a session is not a `FeatureRun`. A single session may span zero, one, or several `FeatureRun`s; a single `FeatureRun` typically spans several sessions. They are orthogonal lifecycles.

---

### session-log

The append-only daily log file at `session-log/YYYY/MM/YYYY-MM-DD.md` recording per-session entries: session boundaries, significant decisions, advisor calls, hand-off events. One file per UTC day; entries are appended chronologically and never edited or deleted.

*Discriminating note:* session-log is not the same family as `docs/gate-audit/events.jsonl`. Both are append-only logs, but session-log is human-readable narrative for resume; `events.jsonl` is structured machine data for ROI analysis. They serve different consumers and are not unified by design (see hotspot #4).

---

### session_id

A `STATE.md` field uniquely identifying the session that wrote the current snapshot. Format: UTC ISO-8601 timestamp (e.g., `2026-05-03T14:32:00Z`), set by `stop-hook.sh` via `date -u`. See ADR-0024 sub-decision 4.

*Discriminating note:* `session_id` identifies the *writer* of the snapshot, not the *FeatureRun*. The `active_feature_run_id` field is a separate reference into a different BC.

---

### STATE.md

The repo-root snapshot file (≤200 lines) with nine fields recording the current resumable state of work: `session_id`, `date_iso`, `current_branch`, `last_commit_sha`, `active_feature_run_id`, `next_3_actions`, `blocked_on`, `open_questions`, `risk_flags`. Replaced (not appended) on each hand-off; the prior state moves to `session-log` history.

*Discriminating note:* `STATE.md` is not a backlog and not a runbook. It is a thin snapshot whose only job is to satisfy the Human Resume Test. Anything that does not contribute to a five-minute resume should not be in STATE.md.

---

### Triple Hand-off Contract

The combined precondition that all three hand-off artifacts (STATE.md updated and ≤200 lines; session-log entry appended for today; plan.md linter passing) are simultaneously valid. The contract is binary: all three pass, or hand-off is incomplete. Partial hand-offs are not a recognised state.

*Discriminating note:* "triple" is normative, not descriptive. It enforces that snapshot-without-history (STATE.md changes but no log entry) and history-without-snapshot (log entry but stale STATE.md) are both equally broken. The plan.md linter being the third leg is the design choice currently most contested (see hotspot #1).

---

## Where these terms fit relative to existing aggregates

| New term | Relationship to existing BC |
|---|---|
| `STATE.md` | New aggregate root candidate in Session Continuity BC; references `FeatureRun` by `active_feature_run_id` |
| `session-log` | New entity in Session Continuity BC; append-only; not owned by any `FeatureRun` |
| `Session` | New aggregate root candidate in Session Continuity BC; lifecycle orthogonal to `FeatureRun` |
| `Hand-off` | New process/event concept in Session Continuity BC; triggers cross to `claude-mini-pipeline` only via plan.md linter |
| `Continuity`, `Resume`, `Human Resume Test` | Properties / acceptance criteria of Session Continuity BC |
| `next_3_actions`, `blocked_on`, `risk_flags`, `open_questions`, `session_id`, `active_feature_run_id` | Attributes of the `STATE.md` aggregate |
| `plan.md Linter` | **Cross-BC seam** — owned by Session Continuity (invocation), enforces a `claude-mini-pipeline` rule (ADR-discipline). See hotspot #1 |

`FeatureRun` is **not modified** by this BC. Session Continuity holds a reference (`active_feature_run_id`) and may read `FeatureRun.dod_state`, `FeatureRun.issue_ref` for snapshot content, but emits no commands into `claude-mini-pipeline`.

Plain attributes `date_iso`, `current_branch`, `last_commit_sha` are STATE.md fields but are intentionally not promoted to UL terms (see "Intentional exclusions" note at top of UL section).

---

## Invariants and rules

### STATE.md invariants

- **Size cap:** ≤200 lines (mechanical — verifiable by `wc -l`).
- **Field completeness:** all nine fields present; missing fields invalidate the snapshot. Empty values (`null`, `[]`) are valid; missing keys are not.
- **Replacement, not append:** every hand-off rewrites STATE.md in full; prior content is preserved only via the corresponding session-log entry.
- **`active_feature_run_id` is a reference:** if non-null, it must resolve to an existing GitHub issue. Session Continuity does not duplicate `FeatureRun` state.
- **`next_3_actions` cardinality:** exactly 3 entries when work is active; `[]` only valid when `blocked_on != null` or work is fully done.

### session-log invariants

- **Append-only:** entries are added; existing entries are never edited or deleted. Mechanically enforceable by a pre-commit check (not yet designed).
- **One file per UTC day:** `session-log/YYYY/MM/YYYY-MM-DD.md`. Day boundary is UTC, not local — operators in different timezones use the same calendar.
- **Chronological within file:** newest entry at the bottom (or top — convention not yet decided; see hotspot #5).

### Triple Hand-off Contract invariant

- **All-or-nothing:** hand-off is complete iff (STATE.md valid) AND (session-log entry for today exists) AND (plan.md linter passes). No partial-hand-off state is recognised.

### Human Resume Test invariant (NFR)

- **Five-minute budget:** the design must support a fresh operator/agent reaching first concrete action within five minutes of opening STATE.md. Verified by periodic drill or post-resume retrospective; not mechanically measured per session.

---

## Bounded Context Canvas — Session Continuity (sketch)

### Purpose

Maintain a triple hand-off contract (STATE.md + session-log + plan.md linter) such that any new LLM session or operator can resume work within five minutes of reading the snapshot — the Human Resume Test.

### Strategic classification

- **Core / Supporting / Generic:** Supporting. Continuity is critical to operator trust but does not differentiate the pipeline; it serves the core (`claude-mini-pipeline`).
- **Domain role:** observability + resumability layer over feature work.

### Responsibilities

- Maintain `STATE.md` as a current ≤200-line snapshot of resumable state.
- Append a `session-log/YYYY/MM/YYYY-MM-DD.md` entry on every session boundary and significant in-session event (advisor call, hand-off, decision recorded).
- Run the `plan.md` linter at hand-off time and block the hand-off if it fails.
- Provide a verifiable Human Resume Test as the BC's primary acceptance criterion.

### Not responsibilities (out of scope)

- Owning or mutating `FeatureRun`, `GovernanceRun`, or `TwoVoiceReview` state — they remain in `claude-mini-pipeline`.
- Defining what counts as a "design decision" in plan.md — that rule belongs to `claude-mini-pipeline` (the linter only enforces it).
- Storing pipeline events or governance decisions — `events.jsonl` (gate-audit) and ADRs are separate audit trails.

### Inbound events (consumed)

| Event | Source BC | Reaction |
|---|---|---|
| `FeaturePipelineStarted` | claude-mini-pipeline | Update `STATE.md.active_feature_run_id` |
| `DoDSatisfied` | claude-mini-pipeline | Update `STATE.md.next_3_actions` (likely "open PR" or move to next ticket); append session-log note |
| `AdvisorReturned` | claude-mini-pipeline | Append session-log entry referencing critique |
| `SessionStarted` (operator action) | self | Read prior STATE.md; append session-log start marker |
| `HandoffRequested` (operator command) | self | Run plan.md linter; refresh STATE.md; append session-log; emit `HandoffPrepared` or `HandoffBlocked` |

### Outbound events (emitted)

| Event | Trigger | Consumer |
|---|---|---|
| `StateSnapshotted` | STATE.md replaced | Session Continuity (internal); operator-visible |
| `SessionLogAppended` | new entry written to today's log | Session Continuity (internal) |
| `HandoffPrepared` | triple contract satisfied | Operator (signal to end session safely) |
| `HandoffBlocked` | one or more contract legs fail | Operator (must resolve before session-end) |
| `PlanLintFailed` | linter detects design-decision without ADR-ref | Operator (must add ADR-ref or justification before hand-off) |

### Collaborators

- **`claude-mini-pipeline` (upstream):** Session Continuity reads `FeatureRun` state by reference; relationship pattern = **Customer/Supplier** (we are customer, pipeline is supplier of run state). Reference-only reads via `active_feature_run_id` follow the ADR-0020 cross-aggregate communication pattern. (House style note: existing `overview.md` reserves explicit ACL labelling for external systems like GitHub; for an internal upstream, plain Customer/Supplier with reference-only reads is closer to current convention. Operator may tighten this.)
- **Operator:** the only actor that triggers `HandoffRequested` and `SessionStarted`. Also the sole human consumer of `STATE.md` content.
- **Git / filesystem:** the durability layer. STATE.md and session-log live in the repo; their persistence is git's responsibility.
- **`adversarial-critic` and `domain-reviewer` (potential future):** may consume hand-off artifacts to verify continuity quality. Not currently designed.

### Ubiquity of language

All terms in the "Ubiquitous Language extension" section above must be used consistently across `STATE.md`, `session-log` entries, runbooks, ADRs, and PR descriptions. Drift detected by `domain-reviewer`.

### Distance from core

One hop from `claude-mini-pipeline` (its primary collaborator). Two hops from GitHub (via pipeline). No direct integration with Anthropic API, Codex CLI, or external services.

---

## Red Hotspots (open questions)

These are explicit unresolved questions, flagged honestly per `vocabulary.md#Red Hotspot` discipline.

1. **plan.md linter ownership seam.** The linter enforces `claude-mini-pipeline`'s ADR-discipline rule but is invoked from Session Continuity's hand-off contract. Two defensible placements: (a) linter lives in pipeline BC, hand-off contract simply *consumes* its result; (b) linter lives in Session Continuity, pipeline owns only the rule definition. Issue #128 bundles all three artifacts under "triple hand-off"; domain-wise, leg three may belong elsewhere. Needs operator decision before implementation.

2. ~~**Is `Session` an aggregate root, or is `STATE.md` a projection of `Session`?**~~ **Resolved by ADR-0024 (sub-decision 2):** `STATE.md` is the aggregate root; `Session` is an attribute (`session_id`). Document-model chosen over event-sourcing per Principle 8. Approach B1 chosen; B2 (event-sourced `Session`) rejected.

3. ~~**`session_id` generation rule undefined.**~~ **Resolved by ADR-0024 (sub-decision 4):** UTC ISO-8601 timestamp (e.g., `2026-05-03T14:32:00Z`). Rationale: human-readable, sortable, no external dependency. ULID, git-style hash, and operator-typed string rejected.

4. **Relationship between `session-log` and `events.jsonl` (gate-audit).** Both are append-only logs in the repo; both record events with timestamps. Are they the same family with different schemas, or genuinely separate? Current draft says "separate" (different consumers, different formats), but a unified event log is a defensible alternative. Not yet ADR-discussed.

5. ~~**Chronological order in session-log entries.**~~ **Resolved by ADR-0024 (sub-decision 5):** newest-at-bottom. True append; a pre-commit check can verify by `diff --unified=0` that only trailing additions exist. Newest-at-top rejected (rewrites file head, breaking mechanical append-only enforcement).

6. **Session boundary detection.** A session ends when… the client closes? An hour of inactivity? A new operator types `/resume`? The definition affects when `HandoffRequested` should fire automatically vs require operator command. Currently assumed operator-explicit; auto-detection deferred.

7. **What if `STATE.md` is never updated?** A session that crashes mid-work leaves stale STATE.md. The next session reads outdated `next_3_actions` and may take wrong action. Mitigation could be a freshness field (`last_updated`) compared to `last_commit_sha` — not yet designed.

8. **Cross-BC reference resolution failure.** If `active_feature_run_id` points to an issue that has been closed/reopened/deleted, what should the new session see? Currently undefined. Likely: snapshot stays as-recorded; resume logic surfaces a "stale reference" warning.

9. **Concurrent sessions.** What happens if two operators (or one operator with two clients) write `STATE.md` simultaneously? Not currently in scope (operator is singular per `vocabulary.md#Operator`), but worth flagging if multi-operator becomes real.

10. **`open_questions` vs `Red Hotspot` escalation path.** Both record unresolved questions but at different scope and lifetime. The lifecycle by which a session-scope `open_questions` entry escalates to a BC-scope `Red Hotspot` (or to a GitHub issue) is not formally defined. Likely operator-judgement at retrospective time, but the discipline could drift.

---

## Hand-off to next stage

This discovery doc is intended for:
1. **Operator review** — confirm or revise the BC boundary call (sibling vs sub-aggregate of `claude-mini-pipeline`), resolve red hotspots #1 and #2, decide `session_id` rule.
2. **`domain-reviewer`** — verify no vocabulary drift against existing `vocabulary.md`, check that proposed terms do not collide with existing terms (especially `open_questions` vs `Red Hotspot`), validate cross-aggregate reference pattern matches ADR-0020.
3. **`/plan 128`** — once boundary is confirmed and term set is approved, plan can proceed knowing the language and aggregate placement.

`vocabulary.md` and `overview.md` are **not** modified by this discovery. Merging the proposed terms into `vocabulary.md` and adding a sibling BC overview at `docs/domain/session-continuity/overview.md` is a separate operator-approved step.
