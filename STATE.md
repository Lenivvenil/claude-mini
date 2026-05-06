# STATE.md — session continuity snapshot
<!-- Principle 9 hand-off artifact. Replaced (not appended) on each session end. -->
<!-- Five-minute cold-start: read this + latest session-log entry, start in 5 min. (ADR-0024) -->

session_id: 2026-05-06T06:21:53Z
date_iso: 2026-05-06
current_branch: feat/domain-inversion-meta-target-130
last_commit_sha: 25f9db5
active_feature_run_id: #130

next_3_actions:
  - Pick next issue from backlog (run /backlog-review or check GitHub Issues)
  - Issue #128 (session-continuity) was the prior active run — verify it merged or is still open
  - Run /project-health weekly report if not done this week

blocked_on: null

open_questions: []

risk_flags:
  - mutation.yml is a reference implementation that skips all language blocks on claude-mini itself (no src/); first real signal comes from target pet-projects after --target install
  - filter-mypy-invalid.py has no integration test (requires live mutmut + mypy); follow-up issue recommended
  - cargo-mutants outcomes.json format: confirmed "caught"/"missed" outcome values from docs; re-verify if cargo-mutants v27 ships a breaking format change
