# STATE.md — session continuity snapshot
<!-- Principle 9 hand-off artifact. Replaced (not appended) on each session end. -->
<!-- Five-minute cold-start: a fresh operator/agent reads this + latest session-log entry  -->
<!-- and reaches the first concrete action within 5 minutes. (Human Resume Test, ADR-0024) -->
<!-- Mechanical fields are updated by stop-hook.sh. Operator-asserted fields: fill before  -->
<!-- ending the session. TODO-placeholders cause a WARNING in stop.log, not a hard block.  -->

session_id: TODO              # stop-hook sets: UTC ISO-8601 e.g. 2026-05-03T14:32:00Z
date_iso: TODO                # stop-hook sets: UTC date e.g. 2026-05-03
current_branch: TODO          # stop-hook sets: git rev-parse --abbrev-ref HEAD
last_commit_sha: TODO         # stop-hook sets: git rev-parse --short HEAD
active_feature_run_id: null   # stop-hook sets: open GitHub issue ref e.g. #128, or null

next_3_actions:               # OPERATOR: exactly 3 ordered imperatives
  - TODO
  - TODO
  - TODO

blocked_on: null              # OPERATOR: single concrete blocker, or null

open_questions: []            # OPERATOR: questions next session needs answered

risk_flags: []                # OPERATOR: soft warnings (not blockers)
