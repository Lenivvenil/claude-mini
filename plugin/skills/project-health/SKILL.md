---
name: project-health
description: Read-only health report for this project - pull request review time, open-issue age, ADRs awaiting decision, and AI spend from CodeBurn when enabled. Use for "project health", "метрики проекта", "сколько мы тратим".
---

# Project health skill

## Steps

1. **Review time.** `gh pr list --state merged --limit 50 --json createdAt,mergedAt`. Median and 90th percentile from open to merge.
2. **Issue age.** `gh issue list --state open --limit 500 --json number,createdAt,updatedAt`. Median age, 90th percentile, and the count with no activity for 60 days.
3. **ADRs awaiting decision.** Open pull requests that add files under `docs/decisions/` (`gh pr list --state open --json number,title,createdAt,files`), plus ADR files on the current branch whose status is proposed or draft. Count and the oldest.
4. **AI spend.** Only if `"${CLAUDE_PLUGIN_ROOT}/bin/config" get codeburn.enabled` prints `true`. Then run

   ```bash
   npx -y codeburn@<codeburn.version> report --project "$(git rev-parse --show-toplevel)" -p 30days --format json
   ```

   with the version from `"${CLAUDE_PLUGIN_ROOT}/bin/config" get codeburn.version`. Report cost, sessions, top models and cost per session for this project. If Node or CodeBurn is unavailable, write "AI spend: not available" with the reason.

## Output

A short report in chat, one section per metric, `N/A` with the reason where data is missing. Save it to a file only if the owner asks, where the owner says.

## Hard rules

- Read only. Of CodeBurn, run only `report`. Never `optimize --apply`, `guard`, `act` or `mcp` from this skill: they change `~/.claude` or settings.
- No invented numbers. Missing data is `N/A` with the reason.
