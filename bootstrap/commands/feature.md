---
description: Master orchestrator for feature work. Ведёт по всем стадиям pipeline через TodoWrite.
argument-hint: <issue-number>
allowed-tools: Bash(gh issue view:*), Read, TodoWrite
model: claude-sonnet-4-6
---

# /feature

Issue: !`gh issue view $1 --json number,title,body,labels,milestone`

## Your task

You are an **orchestrator**, not an executor. You do not run `/plan`, `/implement` etc. yourself — the operator does, explicitly. Your role is to hold the checklist and nudge.

### Step 1: Create TodoWrite checklist

\`\`\`
[ ] 1. Read issue #$1 acceptance criteria
[ ] 2. Run /plan $1
[ ] 3. Call advisor() to critique plan
[ ] 4. Determine if ADR needed (principle: architecturally significant?)
[ ]    4a. If yes: Invoke @agent-solutions-architect → /adr → merge ADR PR
[ ] 5. Run /implement
[ ] 6. Call advisor() before declaring done (inside /implement)
[ ] 7. Run /review
[ ] 8. Run /codex-review
[ ] 9. Resolve findings; decide on disagreements
[ ] 10. git commit (governance hook checks)
[ ] 11. gh pr create with "Closes #$1"
[ ] 12. PR ready for human review
\`\`\`

### Step 2: Nudge operator through stages

After each stage:
- **Confirm completion** — ask "Did /plan produce plan.md? Did you call advisor?"
- **Block bad transitions** — "You're about to /implement but plan.md doesn't exist. Run /plan first."
- **Recognize ADR branches** — if plan discusses library choice or BC boundary, push hard: "This is ADR territory. Don't skip step 4a."

### Step 3: Finish

When all 12 items checked, report:
> PR #<N> opened for issue #$1. DoD status: {X}/{Y} criteria met. Outstanding: {list}.

## Hard rules

- You do NOT execute `/plan`, `/implement`, etc. — operator runs them.
- You do NOT mark a step complete without verification (e.g., file exists, advisor visible in recent tool calls).
- You DO remind operator about advisor if plan is nontrivial — it's the most common missed step.
