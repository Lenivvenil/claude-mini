#!/usr/bin/env bash
# collect-metrics.sh — gather three gh-queryable project health metrics (1–3).
# Metric #4 (dependency age) is done inline by the skill — not collected here.
# Outputs a JSON object with three data fields and a _warnings array to stdout.
# _warnings is non-empty when a gh call failed (auth, rate-limit, network, etc.).
# Exits 0 always; per-field errors produce empty arrays with a _warnings entry.
set -uo pipefail

warnings=()

if ! review_cycle=$(gh pr list --state closed --limit 20 --json createdAt,mergedAt \
    --jq '[.[] | select(.mergedAt) | {h: ((.mergedAt|fromdate) - (.createdAt|fromdate)) / 3600}]' \
    2>/dev/null); then
    warnings+=("review_cycle: gh exited non-zero — check auth/network")
    review_cycle="[]"
fi

if ! issue_age=$(gh issue list --state open --json createdAt,number,title,labels \
    --jq 'map({days: ((now - (.createdAt|fromdate)) / 86400 | floor)})' \
    2>/dev/null); then
    warnings+=("issue_age: gh exited non-zero — check auth/network")
    issue_age="[]"
fi

if ! open_adrs=$(gh pr list --label type:adr --state open --json number,title,createdAt \
    2>/dev/null); then
    warnings+=("open_adrs: gh exited non-zero — check auth/network")
    open_adrs="[]"
fi

warnings_json=$(printf '%s\n' "${warnings[@]+"${warnings[@]}"}" | jq -Rn '[inputs]')

printf '{"review_cycle":%s,"issue_age":%s,"open_adrs":%s,"_warnings":%s}\n' \
    "$review_cycle" "$issue_age" "$open_adrs" "$warnings_json"
exit 0
