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

**Branch guard (ADR-0009):** Before reading any files, check the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

- If result is `main`: **STOP.** Create a feature branch first:
  ```bash
  git checkout -b feat/<short-slug>-<issue-number>
  ```
  Use the issue number from `plan.md` footer (`Closes #NNN`). Slug: 2–4 lowercase words from the issue title. Example: `feat/branch-strategy-adr-14`.
- If result is already a feature branch: proceed.

Note: `bootstrap/commands/implement.md` is installed to `~/.claude/commands/` via `./bootstrap/universal-setup.sh --install`. Changes here require re-install to take effect.

**Banned-terms check:** Read `docs/runbooks/banned-terms.md`. Scan `plan.md` for each scannable pattern (case-insensitive). Occurrences inside quoted spans (surrounded by `"`, `'`, or backtick characters) are exempt — they reference the term, not use it. If an unquoted match is found: **STOP.** Fix `plan.md` before continuing. (If `plan.md` is missing, the Hard Rules existence guard below applies — skip this check.)

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
> 1. `/qa` for test coverage + docs currency check.
> 2. `/review` for Claude review.
> 3. `/codex-review` for second-voice review.
> 4. Resolve findings, then commit.

## Hard rules

- You are the single author. Do NOT invoke `Task` tool for feature work.
- Advisor × 2 is mandatory for anything touching more than 1 module or with edge cases. You MAY skip for trivial (formatting, rename, one-line fix) — but explicitly state "advisor skipped because trivial".
- If plan.md doesn't exist, STOP and tell operator to run `/plan` first.
- You do NOT commit or push. That happens separately through governance-gated flow.
