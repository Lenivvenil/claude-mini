---
description: Weekly project health report. Four metrics written to docs/metrics/health-YYYY-WW.md.
allowed-tools: Bash(gh:*), Bash(git log:*), Bash(date:*), Read, Write
model: claude-sonnet-4-6
---

# /project-health

Current week: !`date +%Y-W%V`

## Your task

Compute four metrics and write `docs/metrics/health-YYYY-WW.md`:

### 1. Review cycle time (PR open → merge)

\`\`\`bash
gh pr list --state closed --limit 20 --json createdAt,mergedAt --jq '.[] | select(.mergedAt) | {h: ((.mergedAt|fromdate) - (.createdAt|fromdate)) / 3600}'
\`\`\`

Report: median, P90, trend vs prior week if available.

### 2. Open-issue age distribution

\`\`\`bash
gh issue list --state open --json createdAt,number,title,labels --jq 'map({days: ((now - (.createdAt|fromdate)) / 86400 | floor)})'
\`\`\`

Report: median, P90, count > 60 days.

### 3. Open ADRs awaiting decision

\`\`\`bash
gh pr list --label type:adr --state open --json number,title,createdAt
\`\`\`

Report: count, oldest open.

### 4. Dependency age (if applicable)

Check `package.json`, `pyproject.toml`, `go.mod` — last update. Pair with Dependabot alerts from `gh api repos/:owner/:repo/dependabot/alerts` if available.

## Output

Write to `docs/metrics/health-YYYY-WW.md`:

\`\`\`markdown
# Project health — YYYY, week WW

## Summary
- Review cycle median: {X}h
- Open issues P90 age: {X} days
- Open ADRs: {N} (oldest: #{M}, {X} days)
- Dependency age flag: {Y/N}

## Threshold breaches
- [ ] {metric} exceeded {threshold}

## Details
{per-metric breakdown}

## Actions
- {concrete next step per breach}
\`\`\`

## Hard rules

- You do NOT write synthetic numbers for "looks good" reports. If data is insufficient, write `N/A` and say why.
- You DO write N/A honestly for young repos — no CI yet is not a failure, it's a known gap.
