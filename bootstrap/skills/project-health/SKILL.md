---
name: project-health
description: Weekly project health report with four metrics: review cycle time, open-issue age, open ADRs, and dependency age. Writes docs/metrics/health-YYYY-WW.md. Use when asked to "run project health", "generate health report", or "weekly health check". Requires gh CLI and an active GitHub repository.
---

# Project health skill

## When to invoke

- "run project health", "generate health report", "weekly health check"
- "еженедельный health отчёт", "метрики проекта"
- Weekly (out-of-band from feature pipeline)

## Prerequisites

- Authenticated `gh` CLI
- Active GitHub repository with issues and PRs
- `docs/metrics/` directory (created if absent)

## Steps

Current week: `date +%Y-W%V`

Collect raw data for metrics 1–3 using the bundled script:
```bash
bash ~/.claude/skills/project-health/scripts/collect-metrics.sh
```
If the script is unavailable, run the three `gh` queries inline (see script source). Metric #4 (dependency age) is always done inline — it requires local file reads and an optional Dependabot API call that the script does not perform.

### 1. Review cycle time (PR open → merge)

From the `review_cycle` field in the script output: compute median, P90, and trend vs prior week if `docs/metrics/health-*.md` files exist.

### 2. Open-issue age distribution

From the `issue_age` field: compute median, P90, count > 60 days.

### 3. Open ADRs awaiting decision

From the `open_adrs` field: count, oldest open.

### 4. Dependency age (if applicable)

Check `package.json`, `pyproject.toml`, `go.mod` — last update. Pair with Dependabot alerts from `gh api repos/:owner/:repo/dependabot/alerts` if available.

## Output

Written to `docs/metrics/health-YYYY-WW.md`:

```markdown
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
```

## Hard rules

- Do NOT write synthetic numbers for "looks good" reports. If data is insufficient, write `N/A` and say why.
- DO write N/A honestly for young repos — no CI yet is not a failure, it's a known gap.
