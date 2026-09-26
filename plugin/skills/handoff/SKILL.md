---
name: handoff
description: Record where the work stands so a new session or a person can resume in minutes. Use at the end of a feature, before stopping unfinished work, or on "handoff", "сохрани состояние", "передай работу". Appends a journal entry, then replaces the snapshot. Writes only inside the project.
---

# Handoff skill

Paths: `"${CLAUDE_PLUGIN_ROOT}/bin/config" get paths.handoff` (journal directory) and `get paths.state` (snapshot file), both relative to the project root. If config exits non-zero, stop and show its message.

## Steps

1. **Journal first.** Append an entry at the end of `<handoff>/YYYY/MM/YYYY-MM-DD.md` (UTC date). Markdown prose: what was done, what was decided and why, what is left. Include branch, short commit, and the issue if any. Never rewrite earlier entries.
2. **Then the snapshot.** Replace `<state>` whole, in the format of `${CLAUDE_PLUGIN_ROOT}/skills/handoff/templates/STATE.md`:
   - mechanical fields from git and the clock: `session_id` (UTC ISO-8601), `date_iso`, `current_branch`, `last_commit_sha`, `active_feature_run_id` (the issue as `#N`, or `null`);
   - fields from the session: `next_3_actions` (three ordered imperatives), `blocked_on`, `open_questions`, `risk_flags`.

   Keep all nine fields. An empty value is `null` or `[]`. The file stays under 200 lines.
3. **Warn, do not block.** If a session field would stay `TODO`, fill it from the conversation or say in chat which fields are unfilled.

## Output

The two paths written and the three next actions, in chat.

## Hard rules

- The journal comes before the snapshot: if the second write fails, the journal still holds the record.
- Write only the two paths above, inside the project. Do not commit unless the owner asks.
- The snapshot references the issue; it does not copy its content.
