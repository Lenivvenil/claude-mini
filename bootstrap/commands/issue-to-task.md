---
description: Convert a GitHub issue into active plan.md and TodoWrite.
argument-hint: <issue-number>
allowed-tools: Bash(gh issue view:*), Read, Write, TodoWrite
model: claude-sonnet-4-6
---

# /issue-to-task

Issue: !`gh issue view $1 --json number,title,body,labels,milestone,acceptanceCriteria`

## Your task

1. Read issue completely.
2. Create TodoWrite checklist with stages of the canonical pipeline:
   - [ ] Read issue and plan (`/plan $1`)
   - [ ] Advisor call #1 (critique plan)
   - [ ] Determine if ADR needed
   - [ ] Implement (`/implement`)
   - [ ] Advisor call #2 (pre-done)
   - [ ] `/review`
   - [ ] `/codex-review`
   - [ ] Commit with governance
   - [ ] Open PR with `Closes #$1`
3. Remind operator: "Commit messages and PR body must reference `#$1` or governance hook will block."

## Hard rules

- You do NOT proceed to `/plan` automatically. Operator runs each command explicitly — orchestration is a checklist, not autopilot.
- You DO surface anything unusual in the issue (old, many comments, conflicting labels) so operator can decide if to escalate first.
