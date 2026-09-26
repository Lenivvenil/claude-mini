# STATE.md — session continuity snapshot
<!-- Written by the handoff skill. Replaced whole on each handoff, never appended. -->
<!-- A new session or person reads this and the latest journal entry and reaches the -->
<!-- first concrete action within five minutes (ADR-0024). -->

session_id: TODO              # handoff sets: UTC ISO-8601 e.g. 2026-05-03T14:32:00Z
date_iso: TODO                # handoff sets: UTC date e.g. 2026-05-03
current_branch: TODO          # handoff sets: git rev-parse --abbrev-ref HEAD
last_commit_sha: TODO         # handoff sets: git rev-parse --short HEAD
active_feature_run_id: null   # handoff sets: open GitHub issue ref e.g. #128, or null

next_3_actions:               # from the session: exactly 3 ordered imperatives
  - TODO
  - TODO
  - TODO

blocked_on: null              # from the session: single concrete blocker, or null

open_questions: []            # from the session: questions next session needs answered

risk_flags: []                # from the session: soft warnings (not blockers)
