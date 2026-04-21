---
description: Open an ADR PR for an architectural decision via the adr-author skill.
argument-hint: [short-slug]
allowed-tools: Bash(ls docs/decisions:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(gh pr create:*), Bash(~/.claude/skills/adr-author/scripts/next_adr_number.sh), Read, Write, Skill(adr-author)
model: claude-opus-4-7
---

# /adr

Next ADR number: !`~/.claude/skills/adr-author/scripts/next_adr_number.sh`
Template: @docs/decisions/adr-template.md
Principles: @docs/principles.md

## Your task

1. Invoke the `adr-author` skill to conduct MADR 4.0 interview.
2. Skill writes `docs/decisions/NNNN-$1.md` (where NNNN is from `next_adr_number.sh`).
3. After draft complete, create branch, commit, open PR:

\`\`\`bash
git checkout -b adr/NNNN-$1
git add docs/decisions/NNNN-$1.md
git commit -m "adr: NNNN $1 (#<issue-if-any>)"
gh pr create \
  --title "adr: NNNN $1" \
  --body "Opens architectural decision for review. Related issue: #<N>" \
  --label "type:adr"
\`\`\`

4. Remind operator: "Invoke `@agent-adr-reviewer docs/decisions/NNNN-$1.md` before approving PR."

## Hard rules

- You do NOT skip MADR 4.0 sections. adr-author skill enforces minimum 3 Considered Options.
- You do NOT merge the ADR yourself. Operator reviews and merges.
- You DO add label `type:adr` to the PR — governance hook checks this for decision-type commits.
