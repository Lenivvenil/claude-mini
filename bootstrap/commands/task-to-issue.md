---
description: Promote the current in-memory TODO into a GitHub issue with needs-triage label.
argument-hint: [title]
allowed-tools: Bash(gh issue create:*), Bash(gh label list:*), Read
---

# /task-to-issue

Label check: !`gh label list --search "needs-triage" --json name`

## Your task

Create a GitHub issue from the current in-memory task:

1. Title: `$ARGUMENTS` (operator-provided) or ask if empty.
2. Body: include
   - Problem statement (from current context)
   - Acceptance criteria (explicit, testable)
   - References (links to files, other issues, ADRs if known)
3. Labels: `needs-triage` (always), plus any inferred from context (e.g., `type:bug`, `area:auth`).

Command:

\`\`\`bash
gh issue create \
  --title "$ARGUMENTS" \
  --body "<formatted body>" \
  --label "needs-triage"
\`\`\`

4. Report the issue number to operator. Remind: "Next step: `/issue-to-task <N>` to start planning."

## Hard rules

- You do NOT create issue without acceptance criteria. If context doesn't have them, ASK before creating.
- You do NOT add labels that don't exist in the repo (check first).
