---
description: Implement the current plan. Full context, single author, two advisor calls.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, mcp__serena
model: claude-sonnet-4-6
---

# /implement

Plan: @plan.md
Principles: @docs/principles.md
Current issue: !`gh issue view $(cat plan.md | grep -oE 'Closes #[0-9]+' | head -1 | grep -oE '[0-9]+') 2>/dev/null || echo "no issue linked in plan"`

## Your task

Implement the plan. You are the single author. No subagent delegation.

### Phase 1 — Orient

1. Read `plan.md` completely. Read every file referenced in it.
2. Read 3–5 related files for context (neighbouring modules, existing patterns).
3. Check relevant ADRs (`docs/decisions/`) for constraints.

### Phase 2 — Advisor pre-check (MANDATORY for non-trivial tasks)

Call advisor() with:

> "Review this plan against the codebase I've now read. Is the approach sound? Missing edge cases? ADR violations? ≤150 words, enumerated."

Integrate advisor feedback before writing code.

### Phase 3 — Implement

1. Write code. Run tests after every non-trivial change.
2. If tests fail, fix before continuing.
3. If you discover the plan was wrong, STOP and update `plan.md` before continuing. Plan drift without update is a red flag.

### Phase 4 — Advisor pre-done (MANDATORY)

Call advisor() with:

> "Here's the diff I'm about to commit. Look for bugs, missing edge cases, or violations of the ADR/plan. ≤150 words, enumerated."

Address findings before declaring done.

### Phase 5 — Hand-off

Report to operator:

> Implementation complete. Diff summary: {stats}. Advisor was called {N} times. Next steps:
>
> 1. `/review` for Claude review.
> 2. `/codex-review` for second-voice review.
> 3. Resolve findings, then commit.

## Hard rules

- You are the single author. Do NOT invoke `Task` tool for feature work.
- Advisor × 2 is mandatory for anything touching more than 1 module or with edge cases. You MAY skip for trivial (formatting, rename, one-line fix) — but explicitly state "advisor skipped because trivial".
- If plan.md doesn't exist, STOP and tell operator to run `/plan` first.
- You do NOT commit or push. That happens separately through governance-gated flow.
