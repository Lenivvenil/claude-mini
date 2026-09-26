---
name: backlog-review
description: Groom the project's open issues. Use when asked to review, groom or clean up the backlog ("что с бэклогом"). Runs the backlog-groomer agent, shows its report, and applies only the batch of commands the owner approves.
---

# Backlog review skill

## Steps

1. Run the `claude-mini:backlog-groomer` agent on the current repository. Pass any thresholds or label rules the owner gave.
2. Show the owner the summary and the proposed commands, grouped by check.
3. Save the full report only if the owner asks, where the owner says.
4. The owner approves commands by naming them or a whole group. Run exactly the approved commands and report each result. Leave the rest.

## Output

The groomer's report summary in chat, and for applied commands a list of what ran and what it returned.

## Hard rules

- Do NOT run a command that changes the tracker unless the owner approved that command or its group in this conversation.
- Do NOT rewrite the groomer's findings. Disagreement goes into the conversation or the issue, not into the report.
