# Bounded Context: Session Continuity

**Version:** 2026-05-03
**Status:** initial (ADR-0024, issue #128); one aggregate root: STATE.md

## Table of Contents

- [Purpose](#purpose)
- [Actors](#actors)
- [Commands and Domain Events](#commands-and-domain-events)
- [Boundary](#boundary)
- [Aggregate Root](#aggregate-root)
- [Context Map](#context-map)
- [Use Cases](#use-cases)
- [Domain Data Model](#domain-data-model)
- [Interface Contracts](#interface-contracts)
- [NFR](#nfr)
- [Internal Compliance](#internal-compliance)
- [Red Hotspots](#red-hotspots)

---

## Purpose

This BC owns the triple hand-off contract: maintaining `STATE.md` (snapshot), `session-log/YYYY/MM/YYYY-MM-DD.md` (append-only history), and `plan.md` linter (ADR-discipline gate) such that any new LLM session or operator can resume work within five minutes of reading the snapshot — the Human Resume Test.

This BC does NOT own pipeline orchestration, governance enforcement, or any `FeatureRun` lifecycle — those belong to `meta-pipeline BC`.

---

## Actors

| Actor | Role | Authority |
|---|---|---|
| **Operator** | Asserts operator-asserted STATE.md fields (`next_3_actions`, `blocked_on`, `open_questions`, `risk_flags`); issues `HandoffRequested` | Write authority over STATE.md fields |
| **stop-hook** | Automated process triggered on session end; updates mechanical STATE.md fields and appends session-log entry | Write via `stop-hook.sh` (bootstrap/hooks) |
| **Main Loop** | Runs plan.md linter during hand-off | Read + lint execution |

---

## Commands and Domain Events

### STATE.md commands

| Command | Emits |
|---|---|
| `SnapshotState(session_id, fields)` | `StateSnapshotted` |
| `HandoffRequested` | `PlanLintPassed` → `HandoffPrepared` \| `PlanLintFailed` → `HandoffBlocked` |

### session-log commands

| Command | Emits |
|---|---|
| `AppendSessionEntry(session_id, content)` | `SessionLogAppended` |

### Inbound events (consumed from meta-pipeline BC)

| Event | Source BC | Reaction |
|---|---|---|
| `FeaturePipelineStarted` | meta-pipeline BC | Update `STATE.md.active_feature_run_id` |
| `DoDSatisfied` | meta-pipeline BC | Update `STATE.md.next_3_actions`; append session-log note |
| `AdvisorReturned` | meta-pipeline BC | Append session-log entry referencing critique |

---

## Boundary

**In scope:**
- `STATE.md` — repo-root snapshot; ≤200 lines; 9 fields; replaced on each hand-off
- `session-log/YYYY/MM/YYYY-MM-DD.md` — append-only daily log; one file per UTC day
- `plan.md` linter invocation — runs at hand-off; blocks on failure
- `bootstrap/scripts/plan-lint.sh` — linter implementation (bash, grep-based)
- `bootstrap/templates/STATE.md.template` — starter for `--target` installs

**Out of scope:**
- `FeatureRun`, `GovernanceRun`, `TwoVoiceReview` lifecycle — owned by `meta-pipeline BC`
- ADR-discipline rule definition — owned by `meta-pipeline BC`; this BC only invokes the linter
- `docs/gate-audit/events.jsonl` — gate audit is a separate append-only log with different consumer (not unified by design; see ADR-0024 sub-decision 8)
- CI gate on plan.md linter — follow-up; not in this PR

---

## Aggregate Root

### STATE.md

Document-model aggregate root (ADR-0024, sub-decision 2). Nine fields:

| Field | Type | Who sets it |
|---|---|---|
| `session_id` | UTC ISO-8601 string | stop-hook (mechanical) |
| `date_iso` | UTC ISO-8601 date | stop-hook (mechanical) |
| `current_branch` | string | stop-hook (mechanical) |
| `last_commit_sha` | string | stop-hook (mechanical) |
| `active_feature_run_id` | issue ref `#NNN` or `null` | stop-hook (mechanical; reads FeatureRun by reference) |
| `next_3_actions` | list[string], cardinality=3 | operator-asserted |
| `blocked_on` | string or `null` | operator-asserted |
| `open_questions` | list[string] | operator-asserted |
| `risk_flags` | list[string] | operator-asserted |

**Invariants:**
- ≤200 lines (mechanically verifiable with `wc -l`)
- All 9 fields present; empty values (`null`, `[]`) valid; missing keys are not
- Replaced (not appended) on every hand-off; prior state preserved only via session-log
- `active_feature_run_id` is a reference only — no copy of `FeatureRun` state embedded

---

## Context Map

```
┌─────────────────────────────────┐     reference-only     ┌──────────────────────────────────┐
│     Session Continuity BC       │ ──────────────────────► │    meta-pipeline BC           │
│                                 │  (Customer/Supplier)    │                                   │
│  STATE.md (aggregate root)      │                         │  FeatureRun (aggregate root)      │
│  session-log (entity)           │  active_feature_run_id  │  GovernanceRun (aggregate root)   │
│  plan.md linter (invocation)    │  → reads FeatureRun     │  TwoVoiceReview (aggregate root)  │
│                                 │    by issue ref         │                                   │
└─────────────────────────────────┘                         └──────────────────────────────────┘
         ▲
         │ inbound events:
         │ FeaturePipelineStarted
         │ DoDSatisfied
         │ AdvisorReturned
         └─ Operator (HandoffRequested, SessionStarted)
```

Session Continuity is **Customer** of meta-pipeline BC (**Supplier**). Session Continuity reads `FeatureRun` state by ID at snapshot time and emits no commands back into meta-pipeline BC. This follows ADR-0020 cross-aggregate communication pattern.

---

## Use Cases

### UC-1: Session Hand-off (happy path)

**Actor:** Operator (or stop-hook automation)
**Preconditions:** Work-in-progress exists; at least one commit has been made this session.

**Main scenario:**
1. Operator (or stop-hook) triggers `HandoffRequested`.
2. stop-hook.sh appends entry to today's `session-log/YYYY/MM/YYYY-MM-DD.md` (log-first per ADR-0024 sub-decision 4).
3. stop-hook.sh refreshes mechanical STATE.md fields (`session_id`, `date_iso`, `current_branch`, `last_commit_sha`, `active_feature_run_id`).
4. stop-hook.sh logs WARNING to stop.log if operator-asserted fields still contain TODO-placeholders.
5. plan.md linter runs; passes.
6. `HandoffPrepared` emitted — session end is safe.

**Alternatives:**
- A: plan.md linter fails → `HandoffBlocked` emitted; operator adds ADR-ref or exemption; returns to step 5.
- B: session-log append fails → STATE.md not touched; next run retries the append.

**Postconditions:** `STATE.md` is valid; today's session-log entry exists; plan.md linter passes.

---

### UC-2: Resume (Human Resume Test)

**Actor:** Operator or fresh agent
**Preconditions:** `STATE.md` exists with all 9 fields; most recent `session-log` entry exists.

**Main scenario:**
1. Operator opens `STATE.md`.
2. Reads `current_branch`, `active_feature_run_id` — confirms context.
3. Reads `next_3_actions` — identifies first concrete step.
4. Reads `blocked_on` — if non-null, resolves blocker before proceeding.
5. Reads `open_questions` — notes unanswered questions.
6. Reads `risk_flags` — notes warnings.
7. Within 5 minutes of step 1: operator takes the first action in `next_3_actions`.

**Postconditions:** Resume succeeds (Human Resume Test passes) iff step 7 completes within the 5-minute budget.

---

## Domain Data Model

```
STATE.md (aggregate root)
  session_id: "2026-05-03T14:32:00Z"
  date_iso: "2026-05-03"
  current_branch: "feat/session-continuity-state-128"
  last_commit_sha: "048aa98"
  active_feature_run_id: "#128"
  next_3_actions:
    - "Run /qa on current branch"
    - "Run /review with security-reviewer"
    - "Commit and open PR"
  blocked_on: null
  open_questions: []
  risk_flags:
    - "stop-hook.sh atomicity: log-first order mitigates but does not eliminate risk"

session-log/2026/05/2026-05-03.md (entity, append-only)
  entry: [session_id, summary, decisions, advisor_calls, hand-off event]
  constraint: newest-at-bottom; never edited or deleted
```

---

## Interface Contracts

| Interface | Operations used | Handled failure | Unhandled failure |
|---|---|---|---|
| `git rev-parse HEAD` (stop-hook) | Read current commit SHA | Exit non-zero → skip STATE.md update, log warning | None — SHA is always available if git repo is valid |
| `git rev-parse --abbrev-ref HEAD` (stop-hook) | Read current branch | Exit non-zero → fallback to "unknown" | None expected |
| `date -u +%Y-%m-%dT%H:%M:%SZ` (stop-hook) | Generate session_id | OS date failure (not expected) | Not handled — assumed infallible |
| `wc -l STATE.md` (plan-lint or hook) | Check ≤200 lines invariant | File missing → lint fails | None |
| GitHub issue API (via `active_feature_run_id`) | Resolve FeatureRun ref | Issue closed/deleted → snapshot stays as-recorded; WARNING emitted | Stale ref not detected mechanically (ADR-0024 deferred) |

---

## NFR

| Constraint | Value | Enforcement artifact |
|---|---|---|
| Human Resume Test | ≤5 minutes from STATE.md open to first action | `docs/runbooks/resume-drill.md` (periodic drill; not per-session) |
| STATE.md size cap | ≤200 lines | `wc -l` in stop-hook.sh; WARNING if exceeded |
| plan.md linter | Zero false-negatives on §3/§4 design decisions | `bootstrap/scripts/plan-lint.sh` |
| session-log append-only | Entries never deleted or edited | Honor-system gap — no pre-commit check yet (follow-up) |

---

## Internal Compliance

| DoD norm | Enforcement | Artifact | Honor-system gap? |
|---|---|---|---|
| STATE.md ≤200 lines | Automated | stop-hook.sh `wc -l` check | No |
| All 9 fields present | Automated | stop-hook.sh field check | No |
| session-log entry per session | Automated | stop-hook.sh append | No |
| plan.md linter passing at hand-off | Automated | stop-hook.sh → plan-lint.sh | No |
| Operator-asserted fields filled | Honor | stop-hook.sh WARNING on TODO-placeholders | Yes — WARNING only, not blocking |
| session-log never edited/deleted | Honor | None (follow-up: pre-commit check) | Yes |

---

## Red Hotspots

1. **plan.md linter invocation boundary.** Linter enforces `meta-pipeline BC` rule (ADR-discipline) but is invoked from Session Continuity hand-off contract. Two defensible placements remain: (a) invocation owned here, rule defined in pipeline BC; (b) linter lives fully in pipeline BC. ADR-0024 chose option (a). Re-visit if the linter grows beyond grep-based checks. *(ADR-0024 sub-decision 1; trigger: linter needs LLM or complex logic)*

2. **Operator-asserted field enforcement.** `next_3_actions`, `blocked_on`, `open_questions`, `risk_flags` cannot be mechanically verified for *quality* — only for *presence*. A filled-but-meaningless field passes all checks. Human Resume Test catches this only post-hoc. *(ADR-0024 deferred; trigger: one confirmed resume failure attributable to misleading fields)*

3. **session-log append-only enforcement.** No pre-commit check prevents editing existing log entries. Honor-system only. *(ADR-0024 deferred; trigger: follow-up issue)*

4. **Stale `active_feature_run_id`.** If the referenced FeatureRun is closed/reopened/deleted, the snapshot silently refers to a stale context. WARNING-only per ADR-0024 sub-decision 9. *(trigger: confirmed resume confusion attributable to stale ref)*

5. **open_questions escalation path.** How a session-scoped `open_questions` entry becomes a `Red Hotspot` or GitHub issue is operator-judgement only. No formal escalation trigger defined. *(ADR-0024 deferred)*
