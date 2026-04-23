---
description: Plan a change against the current issue. Writes plan.md; does not touch code.
argument-hint: [issue-number]
allowed-tools: Bash(gh issue view:*), Bash(gh label list:*), Read, Glob, Grep, Write
model: claude-sonnet-4-6
---

# /plan

Issue context: !`gh issue view $ARGUMENTS --json number,title,body,labels,milestone,assignees`
Domain docs (если есть): @docs/domain/
Principles: @docs/principles.md
Related ADRs: !`ls docs/decisions/ 2>/dev/null | tail -5`

## Your task

Produce `plan.md` in the repo root with exactly these sections:

1. **Problem restatement** — one paragraph in your own words, not a copy of the issue.
2. **Affected bounded contexts and files** — list with paths. If domain docs exist, name the BCs explicitly.
3. **Considered approaches** — at least 2, with trade-offs. Если только один очевидный путь и он действительно единственный — скажи это явно и обоснуй.
4. **Chosen approach and why** — reference relevant ADRs if any exist.
5. **Test strategy** — unit / integration / e2e split, what assertions matter.
6. **Risks and unknowns** — honest list; "none" is a smell.

## Gating

After writing plan.md, check the "Architectural significance" criteria in `docs/principles.md`. If any is triggered:

> **STOP.** This change has architectural implications. Before `/implement`:
>
> 1. Invoke `@agent-solutions-architect` to produce an ADR draft.
> 2. Wait for ADR PR to merge.
> 3. Then proceed to `/implement`.

If not architectural:

> Plan written to `plan.md`. Next steps:
>
> 1. Call advisor() to critique the plan.
> 2. Run `/implement` when plan is sound.

## Hard rules

- You do NOT write code. Only `plan.md`.
- You do NOT skip "Considered approaches" with just one option unless you justify why.
- You DO read files referenced in the issue body — plan must be grounded in actual code.
