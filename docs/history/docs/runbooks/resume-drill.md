# Runbook: Resume Drill (Human Resume Test)

**ADR:** docs/decisions/0024-session-continuity-bc-and-state-schema.md
**Principle:** 9 (hand-off contract)
**When to run:** Monthly or after any suspected continuity failure.

---

## Purpose

Verify that `STATE.md` + the latest `session-log` entry satisfy the Human Resume Test:
a fresh operator (or agent) can identify the next concrete action and begin work within
**five minutes** of opening `STATE.md`.

Two levels of drill:
- **Level 1 (5-min gate):** Can the next session *start*? — 5-minute budget.
- **Level 2 (1-2hr gate):** Can the next session *finish* an onboarding task without oral introduction? — 1-2 hour budget.

Run Level 1 each time. Run Level 2 when Level 1 has been green for at least 2 consecutive
sessions, or whenever the human-resume contract is questioned.

---

## Prerequisites

- `STATE.md` exists at repo root with all 9 fields present.
- `session-log/YYYY/MM/YYYY-MM-DD.md` exists with at least one entry from the most recent session.
- A second person (or a cold-start simulation: new terminal, no prior context) is available.

---

## Level 1 — 5-minute gate (start-ability)

**Goal:** Reach first concrete action within 5 minutes of opening `STATE.md`.

**Steps:**

0. Run `mini-preflight` from the repo root (#257). Its «Что накопилось за отсутствие»
   section is the return-ritual companion to STATE.md: days since last session, the
   latest run of every CI workflow (red first, including scheduled ones that fail
   silently for weeks), unread auto-issues (mutation weekly, deferred-review), open
   PRs, and proposed ADRs with age. STATE.md answers "where did I stop"; this section
   answers "what did the system accumulate while I was away". Offline it degrades to
   a warn and skips — the drill itself never depends on the network.

1. Open a new terminal / clean session. Do NOT look at chat history, PR descriptions,
   or any context beyond `STATE.md`, today's `session-log` entry, and the preflight output.

2. Start a 5-minute timer.

3. Read `STATE.md` top to bottom.

4. If `blocked_on` is non-null: identify what concrete step unblocks it and note it.

5. From `next_3_actions`, pick action #1. Confirm you understand:
   - Which file or command to touch first.
   - What "done" looks like for that action.

6. Stop timer.

**Pass criterion:** Timer stopped with ≥1 minute remaining AND you can state the first
action and done-condition without ambiguity.

**Fail criterion:** Timer exceeded, OR first action is ambiguous / requires reading
additional docs not referenced in STATE.md or session-log.

---

## Level 2 — 1-2 hour gate (completion-ability)

**Goal:** Close a real onboarding task without any oral introduction from the prior operator.

**Steps:**

1. Select a self-contained task from `next_3_actions` that can be completed in 1-2 hours.

2. Assign it to a person who was **not** the prior session's operator.

3. That person reads only:
   - `STATE.md`
   - The most recent `session-log/YYYY/MM/YYYY-MM-DD.md` entry
   - The GitHub issue referenced in `active_feature_run_id` (if any)

4. Start a 2-hour timer.

5. Assignee works the task to completion (PR open, or clearly defined stopping point).

6. At end: record outcome — task closed? blockers encountered? questions that STATE.md
   did not answer?

**Pass criterion:** Task reaches a clear stopping point within 2 hours without requiring
oral clarification from the prior operator.

**Fail criterion:** Assignee could not proceed without asking prior operator, OR task
required > 2 hours without a clear stopping point.

---

## Failure handling

If Level 1 fails:
- Fill `open_questions` in STATE.md with what was missing.
- Update `next_3_actions` to be more specific (imperative + target + done-condition).
- Re-run Level 1 before the next session ends.
- If this is a recurring failure, open a GitHub issue with label `principle:continuity`.

If Level 2 fails:
- Post-mortem: what did the assignee ask about? Add those answers to either STATE.md or
  `session-log`, whichever is more appropriate.
- If the failure is structural (STATE.md schema insufficient), open a GitHub issue against
  ADR-0024 with a re-visit trigger.

---

## Recording results

After each drill, append a row to this table:

| Date | Level | Operator | Assignee | Result | Notes |
|---|---|---|---|---|---|
| YYYY-MM-DD | L1 / L2 | — | — | PASS / FAIL | Brief note on what was missing or exceptional |

---

## Related artifacts

- `STATE.md` — aggregate root (Session Continuity BC)
- `session-log/YYYY/MM/YYYY-MM-DD.md` — append-only history
- `bootstrap/scripts/mini-preflight.sh` — return ritual: «что накопилось за отсутствие» (#257)
- `bootstrap/scripts/plan-lint.sh` — linter for plan.md ADR-discipline (third leg of hand-off)
- `bootstrap/hooks/stop-hook.sh` — automates mechanical STATE.md field updates
- `docs/decisions/0024-session-continuity-bc-and-state-schema.md` — ADR governing all of the above
