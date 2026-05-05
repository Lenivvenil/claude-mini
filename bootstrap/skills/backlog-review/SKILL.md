---
name: backlog-review
description: Weekly backlog grooming report. Invokes backlog-groomer agent to analyze open GitHub issues and produce a triage report with gh commands. Use when asked to "review backlog", "groom backlog", or "run weekly backlog review". Requires an active GitHub repository with open issues.
---

# Backlog review skill

## When to invoke

- "review backlog"
- "groom backlog"
- "run weekly backlog review"
- "что с бэклогом", "прогони backlog groomer"

## Prerequisites

- GitHub repository with open issues (authenticated `gh` CLI in the environment)
- `@agent-backlog-groomer` available (installed via `./bootstrap/universal-setup.sh --install`)

## Steps

Invoke `@agent-backlog-groomer` to analyze the current repo's open issues and produce a grooming report.

After the agent returns:

1. Present the report summary.
2. Remind operator: "The agent does not mutate. Review the `gh` commands in the report and apply manually."
3. File the report at `docs/backlog/grooming-YYYY-MM-DD.md` (the agent does this).
4. If the operator agrees with a batch of proposals, offer to execute them one-by-one with confirmation.

## Output

Report filed at `docs/backlog/grooming-YYYY-MM-DD.md`. Summary printed to conversation with list of proposed `gh` commands for operator review.

## Hard rules

- Do NOT apply the agent's proposals without explicit operator confirmation on each.
- Do NOT edit the report retroactively. If operator disagrees, note in PR/issue, don't rewrite the report.
