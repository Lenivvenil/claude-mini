#!/usr/bin/env bash
# Create missing labels referenced by synthesis backlog tickets.
# Idempotent: skips labels that already exist; aborts on any other failure.
# Source: operator directive 2026-04-29 (Phase 1 + Phase 2).

set -uo pipefail

create_label() {
  local name="$1" color="$2" desc="$3"
  local out rc
  out=$(gh label create "$name" --color "$color" --description "$desc" 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "ok: $name"
  elif echo "$out" | grep -qiE "already exists|HTTP 422"; then
    echo "skip (exists): $name"
  else
    echo "FAIL: $name (exit $rc): $out" >&2
    exit 1
  fi
}

create_label "principle:agnostic"        "0e8a16" "Vendor-agnostic / open format (principle 7)"
create_label "principle:antifragile"     "0e8a16" "Antifragile by domain depth (principle 8)"
create_label "principle:continuity"      "0e8a16" "Hand-off contract (principle 9)"
create_label "principle:lazy-detection"  "d93f0b" "Lazy-pattern detection (principles 1-4)"
create_label "principle:gate-roi"        "fbca04" "Gate ROI / operational rule"
create_label "principle:domain"          "5319e7" "Domain modeling (principle 8 + DDD)"
create_label "type:bootstrap"            "1d76db" "Bootstrap / pipeline scaffolding"
create_label "prod-bound"                "b60205" "Touches prod-bound paths (hooks, workflows, bootstrap)"

echo "Done. Existing-but-needed: type:adr, type:deferred-review, type:runbook, type:chore, area:docs."
