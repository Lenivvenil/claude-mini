---
description: Master orchestrator for feature work. Ведёт по всем стадиям pipeline через TodoWrite.
argument-hint: <issue-number>
allowed-tools: Bash(gh issue view:*), Read, TodoWrite
model: claude-sonnet-4-6
---

# /feature

Issue: !`gh issue view $ARGUMENTS --json number,title,body,labels,milestone`

## Your task

You are an **orchestrator**, not an executor. You do not run `/plan`, `/implement` etc. yourself — the operator does, explicitly. Your role is to hold the checklist and nudge.

### Step 1: Create TodoWrite checklist

\`\`\`
[ ] 1. Read issue #$ARGUMENTS acceptance criteria
[ ]    1b. Only if docs/domain/ is empty, or the issue scope obviously diverges
[ ]        from docs/domain/vocabulary.md: invoke @agent-domain-researcher
[ ]        (run after reading the issue so you know whether the domain is in scope)
[ ] 2. Run /plan $ARGUMENTS
[ ] 3. Call advisor() to critique plan
[ ] 4. Determine if ADR needed (principle: architecturally significant?)
[ ]    4a. If yes: invoke @agent-solutions-architect → /adr
[ ]    4b. After ADR draft: invoke @agent-adr-reviewer; wait for APPROVE verdict
[ ]    4c. Merge ADR PR before /implement
[ ]    4d. If ADR was authored: re-sync `plan.md §4` with merged ADR per `docs/runbooks/adr-workflow.md` step 6
[ ] 5. Run /implement
[ ]    5a. (inside /implement) Call advisor() before declaring done — MANDATORY for non-trivial
[ ]    5b. Only if docs/domain/ was modified during /implement:
[ ]        invoke @agent-domain-reviewer; wait for APPROVE verdict
[ ] 6. Run /qa
[ ]    6a. Review qa-report.md; resolve test gaps or confirm escape hatch accepted
[ ]    6b. Copy ## QA section from qa-report.md — paste into PR body at step 11
[ ] 7. Run /review
[ ]    7a. Only if PR touches prod-bound paths (bootstrap/, .github/workflows/,
[ ]        .git/hooks/) or is labelled prod-bound:
[ ]        invoke @agent-security-reviewer inside this review phase
[ ] 8. Run /codex-review
[ ] 9. Resolve findings; decide on disagreements
[ ] 10. git commit (governance hook checks)
[ ] 11. gh pr create with "Closes #$ARGUMENTS" — include ## QA section in PR body
[ ] 12. PR ready for human review
\`\`\`

### Step 2: Nudge operator through stages

After each stage:
- **Confirm completion** — ask "Did /plan produce plan.md? Did you call advisor?"
- **Block bad transitions** — "You're about to /implement but plan.md doesn't exist. Run /plan first."
- **Recognize ADR branches** — if plan discusses library choice or BC boundary, push hard: "This is ADR territory. Don't skip step 4a."

### Step 3: Finish

When all 12 items checked, report:
> PR #<N> opened for issue #$ARGUMENTS. DoD status: {X}/{Y} criteria met. Outstanding: {list}.

## Hard rules

- You do NOT execute `/plan`, `/implement`, etc. — operator runs them.
- You do NOT mark a step complete without verification (e.g., file exists, advisor visible in recent tool calls).
- You DO remind operator about advisor if plan is nontrivial — it's the most common missed step.
