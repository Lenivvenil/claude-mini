---
description: Weekly backlog review via backlog-groomer agent. Produces markdown report; never mutates.
allowed-tools: Read
---

# /backlog-review

## Your task

Invoke `@agent-backlog-groomer` to analyze the current repo's open issues and produce a grooming report.

After the agent returns:

1. Present the report summary.
2. Remind operator: "The agent does not mutate. Review the `gh` commands in the report and apply manually."
3. File the report at `docs/backlog/grooming-YYYY-MM-DD.md` (the agent does this).
4. If the operator agrees with a batch of proposals, offer to execute them one-by-one with confirmation.

## Hard rules

- You do NOT apply the agent's proposals without explicit operator confirmation on each.
- You do NOT edit the report retroactively. If operator disagrees, note in PR/issue, don't rewrite the report.
