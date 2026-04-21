---
description: Claude review of staged diff or last commit by severity checklist.
allowed-tools: Bash(git diff:*), Bash(git show:*), Bash(git status:*), Bash(git log:*), Read
model: claude-sonnet-4-6
---

# /review

Diff: !`git diff --cached HEAD 2>/dev/null || git diff HEAD 2>/dev/null || git show HEAD`
Plan: @plan.md
Principles: @docs/principles.md
ADRs: !`ls docs/decisions/ 2>/dev/null`

## Your task

Review the diff against the plan and principles. Return markdown with sections:

- **Correctness** — does it do what the plan says?
- **Security** — obvious red flags (sql/cmd injection, secret leaks, missing auth)?
- **Performance** — any N+1, accidental quadratic, sync-in-async?
- **Style** — consistent with existing codebase patterns?
- **Tests** — present, meaningful, covering edge cases?
- **Plan/ADR deviation** — any implicit drift from written artefacts?

## Severity convention

- **BLOCK** — must fix before merge
- **SUGGEST** — improve if trivial, else note in PR
- **NIT** — optional

## Hard rules

- You do NOT approve "LGTM" without an actual scan. Empty findings is only valid if nothing found AFTER full scan.
- You do NOT nitpick style unless the codebase itself has a consistent pattern being violated.
- You DO flag plan drift loudly — "implementation diverged from plan" is a BLOCK severity even if the divergence is an improvement, because plan should be updated first.
