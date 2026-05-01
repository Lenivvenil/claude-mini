#!/usr/bin/env bash
# gate-audit-aggregate.sh — aggregate events.jsonl into weekly JSONL + markdown report
#
# Usage:
#   gate-audit-aggregate.sh [--events-file <path>] [--output-dir <path>] [--dry-run]
#
# --events-file  path to events.jsonl (default: <repo-root>/docs/gate-audit/events.jsonl)
# --output-dir   directory for output files (default: <repo-root>/docs/gate-audit)
# --dry-run      print outputs to stdout; do not write files
#
# Decision rule:
#   For each gate, examine the last 4 calendar weeks that have at least one
#   blocking event (real+fp+bypass > 0). If real/(real+fp+bypass) < 0.2 for
#   all 4 qualifying weeks → retention_rec=REMOVE.
#   Fewer than 4 qualifying weeks → INSUFFICIENT_DATA. Otherwise → KEEP.
#
# Requires: python3

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "gate-audit-aggregate: not inside a git repository" >&2
    exit 1
}

EVENTS_FILE="$REPO_ROOT/docs/gate-audit/events.jsonl"
OUTPUT_DIR="$REPO_ROOT/docs/gate-audit"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --events-file) EVENTS_FILE="${2:?'--events-file requires a value'}"; shift ;;
        --output-dir)  OUTPUT_DIR="${2:?'--output-dir requires a value'}";  shift ;;
        --dry-run)     DRY_RUN=1 ;;
        *)
            echo "gate-audit-aggregate: unknown argument '$1'" >&2
            exit 1
            ;;
    esac
    shift
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "gate-audit-aggregate: python3 is required but not found" >&2
    exit 1
fi

if [ ! -f "$EVENTS_FILE" ]; then
    echo "gate-audit-aggregate: events file not found: $EVENTS_FILE" >&2
    exit 1
fi

# Run the entire aggregation + report generation in a single python3 invocation.
# Arguments: events_file output_dir dry_run(0|1)
python3 - "$EVENTS_FILE" "$OUTPUT_DIR" "$DRY_RUN" << 'PYEOF'
import sys
import json
import os
import re
from collections import defaultdict
from datetime import date

REMOVE_THRESHOLD  = 0.2  # roi < this for all qualifying weeks → REMOVE
QUALIFYING_WINDOW = 4    # number of qualifying weeks required for REMOVE verdict

events_file = sys.argv[1]
output_dir  = sys.argv[2]
dry_run     = sys.argv[3] == "1"

current_day  = date.today()
iso_cal      = current_day.isocalendar()
current_week = f"{iso_cal[0]}-W{iso_cal[1]:02d}"

# ── Read events ────────────────────────────────────────────────────────────
# event fields: event_id, gate_name, week_iso, outcome, classification, cost_min
# outcome:      "blocked" | "allowed"
# classification: null | "real" | "false-positive" | "bypassed"

weekly = defaultdict(lambda: defaultdict(lambda: {
    "frequency": 0,
    "real_blocks": 0,
    "bypasses": 0,
    "false_positives": 0,
    "cost_min_total": 0.0,
    "cost_min_count": 0,
}))

with open(events_file) as f:
    for lineno, raw in enumerate(f, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            ev = json.loads(raw)
        except json.JSONDecodeError:
            print(f"[gate-audit-aggregate] WARN line {lineno}: not valid JSON — skipped",
                  file=sys.stderr)
            continue
        gate   = ev.get("gate_name", "")
        week   = ev.get("week_iso", "")
        outcome        = ev.get("outcome", "")
        classification = ev.get("classification")
        cost_min       = ev.get("cost_min")

        # Reject gate_name / week_iso values that could inject markdown — ^[a-z0-9-]+ only.
        # This also protects the markdown table output from pipe/backtick/HTML injection.
        if not re.match(r'^[a-z0-9][a-z0-9-]*$', gate or ""):
            print(f"[gate-audit-aggregate] WARN line {lineno}: invalid gate_name '{gate}' — skipped",
                  file=sys.stderr)
            continue
        if not re.match(r'^\d{4}-W\d{2}$', week or ""):
            print(f"[gate-audit-aggregate] WARN line {lineno}: invalid week_iso '{week}' — skipped",
                  file=sys.stderr)
            continue

        bucket = weekly[gate][week]
        bucket["frequency"] += 1

        if outcome == "blocked":
            if classification == "real":
                bucket["real_blocks"] += 1
            elif classification == "false-positive":
                bucket["false_positives"] += 1
            elif classification == "bypassed":
                bucket["bypasses"] += 1

        if cost_min is not None:
            try:
                bucket["cost_min_total"] += float(cost_min)
                bucket["cost_min_count"] += 1
            except (TypeError, ValueError):
                pass

# ── Compute per-gate retention_rec ────────────────────────────────────────

gate_results = {}  # gate_name -> list of week-dicts, sorted by week

for gate_name, weeks in sorted(weekly.items()):
    gate_weeks = []
    for week_iso in sorted(weeks.keys()):
        b   = weeks[week_iso]
        real = b["real_blocks"]
        fp   = b["false_positives"]
        byp  = b["bypasses"]
        freq = b["frequency"]
        denominator = real + fp + byp
        roi_ratio = real / denominator if denominator > 0 else None
        est_cost  = round(b["cost_min_total"] / b["cost_min_count"], 1) \
                    if b["cost_min_count"] > 0 else None
        gate_weeks.append({
            "week_iso":     week_iso,
            "frequency":    freq,
            "real_blocks":  real,
            "bypasses":     byp,
            "false_positives": fp,
            "roi_ratio":    roi_ratio,
            "est_cost_min": est_cost,
        })

    # Qualifying weeks: those with at least one blocking event
    qualifying = [w for w in gate_weeks
                  if (w["real_blocks"] + w["bypasses"] + w["false_positives"]) > 0]
    last4 = qualifying[-QUALIFYING_WINDOW:]
    if len(last4) < QUALIFYING_WINDOW:
        retention_rec = "INSUFFICIENT_DATA"
    elif all(w["roi_ratio"] is not None and w["roi_ratio"] < REMOVE_THRESHOLD for w in last4):
        retention_rec = "REMOVE"
    else:
        retention_rec = "KEEP"

    gate_results[gate_name] = (gate_weeks, retention_rec)

# ── Build aggregate JSONL ──────────────────────────────────────────────────

agg_lines = []
for gate_name, (gate_weeks, retention_rec) in gate_results.items():
    for w in gate_weeks:
        agg_lines.append(json.dumps({
            "gate_name":       gate_name,
            "week_iso":        w["week_iso"],
            "frequency":       w["frequency"],
            "real_blocks":     w["real_blocks"],
            "bypasses":        w["bypasses"],
            "false_positives": w["false_positives"],
            "est_cost_min":    w["est_cost_min"],
            "retention_rec":   retention_rec,
        }))

# ── Build markdown report ──────────────────────────────────────────────────

md_lines = [
    f"# Gate audit report — {current_week}",
    "",
    f"Generated: {current_day.isoformat()} ({current_week})",
    "",
    "Decision rule: `real / (real + fp + bypass) < 0.2` "
    "for 4 consecutive qualifying weeks → REMOVE",
    "",
]

for gate_name, (gate_weeks, retention_rec) in gate_results.items():
    if retention_rec == "REMOVE":
        badge = "REMOVE"
    elif retention_rec == "INSUFFICIENT_DATA":
        badge = "INSUFFICIENT_DATA"
    else:
        badge = "KEEP"

    md_lines += [
        f"## {gate_name}",
        "",
        f"**Retention:** {badge}",
        "",
        "| Week | Frequency | Real blocks | FP | Bypasses | Est cost (min) |",
        "|---|---|---|---|---|---|",
    ]
    for w in gate_weeks:
        cost = str(w["est_cost_min"]) if w["est_cost_min"] is not None else "—"
        md_lines.append(
            f"| {w['week_iso']} | {w['frequency']} | {w['real_blocks']} "
            f"| {w['false_positives']} | {w['bypasses']} | {cost} |"
        )
    md_lines.append("")

# ── Write or print ─────────────────────────────────────────────────────────

agg_text    = "\n".join(agg_lines)
report_text = "\n".join(md_lines)

if dry_run:
    print("=== AGGREGATE JSONL ===")
    print(agg_text)
    print("")
    print("=== MARKDOWN REPORT ===")
    print(report_text)
    sys.exit(0)

os.makedirs(output_dir, exist_ok=True)

agg_path = os.path.join(output_dir, "aggregate.jsonl")
with open(agg_path, "w") as fh:
    fh.write(agg_text + "\n")
print(f"gate-audit-aggregate: wrote {agg_path}", file=sys.stderr)

report_path = os.path.join(output_dir, f"{current_week}.md")
with open(report_path, "w") as fh:
    fh.write(report_text + "\n")
print(f"gate-audit-aggregate: wrote {report_path}", file=sys.stderr)
PYEOF
