#!/usr/bin/env python3
"""Phase 3: set Status field on 20 of 41 board items.

Reads issue-map.json (ticket NN → issue #M).
Calls `gh project item-list` to build issue → item-id map → writes item-map.json.
Sets Status=Next up on 7 P0-unblocked issues.
Sets Status=Backlog on 13 issues (#123 ticket-06 wave-2 + 12 synthesis P1 tickets 09-20).
Leaves remaining 21 issues in default Icebox (no mutation; per operator brief).

Project: claude-mini (#5, owner Lenivvenil).
Project node ID: PVT_kwHOAD4W5M4BVPoL.
Status field ID: PVTSSF_lAHOAD4W5M4BVPoLzhQsxg4.
Option IDs: Next up=435f820d, Backlog=5ddc69df, Icebox=f75ad846.

Run from repo root: python3 .claude/scratch/handoff-2026-04-29/_phase3_set_status.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ISSUE_MAP_PATH = ROOT / "issue-map.json"
ITEM_MAP_PATH = ROOT / "item-map.json"

PROJECT_NUMBER = "5"
PROJECT_OWNER = "Lenivvenil"
PROJECT_NODE_ID = "PVT_kwHOAD4W5M4BVPoL"
STATUS_FIELD_ID = "PVTSSF_lAHOAD4W5M4BVPoLzhQsxg4"
OPT_NEXT_UP = "435f820d"
OPT_BACKLOG = "5ddc69df"

# tickets → issues for placement, computed from issue-map at runtime.
NEXT_UP_TICKETS = ["01", "02", "03", "04", "05", "07", "08"]  # P0 unblocked roots
BACKLOG_TICKETS = ["06"] + [f"{n:02d}" for n in range(9, 21)]  # ticket 06 wave 2 + synthesis P1 (09..20)
# Remaining 21 = tickets 21..41 (12 P2 + 8 P3 + 1 post-handoff) → default Icebox, no mutation.

issue_map: dict[str, int] = json.loads(ISSUE_MAP_PATH.read_text(encoding="utf-8"))


def list_project_items() -> list[dict]:
    cmd = ["gh", "project", "item-list", PROJECT_NUMBER, "--owner", PROJECT_OWNER,
           "--format", "json", "--limit", "200"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    return data.get("items", [])


def build_item_map(items: list[dict], target_issue_nums: set[int]) -> dict[str, str]:
    """Map issue-number (string) → item-id (string) for items whose content.number is in target."""
    out: dict[str, str] = {}
    for item in items:
        content = item.get("content") or {}
        num = content.get("number")
        if num in target_issue_nums:
            out[str(num)] = item["id"]
    return out


def set_status(item_id: str, option_id: str) -> None:
    cmd = [
        "gh", "project", "item-edit",
        "--id", item_id,
        "--field-id", STATUS_FIELD_ID,
        "--single-select-option-id", option_id,
        "--project-id", PROJECT_NODE_ID,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh project item-edit failed (item {item_id}): {result.stderr.strip()}")


def main() -> int:
    target_nums = set(issue_map.values())
    items = list_project_items()
    item_by_issue = build_item_map(items, target_nums)

    if len(item_by_issue) != 41:
        print(f"FAIL: expected 41 phase-2 items on board, found {len(item_by_issue)}", file=sys.stderr)
        return 2

    ITEM_MAP_PATH.write_text(json.dumps(item_by_issue, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"item-map.json written: {len(item_by_issue)} entries")

    # Next up
    next_up_failures = 0
    for ticket in NEXT_UP_TICKETS:
        issue_num = issue_map[ticket]
        item_id = item_by_issue[str(issue_num)]
        try:
            set_status(item_id, OPT_NEXT_UP)
            print(f"Next up: ticket {ticket} → #{issue_num}")
        except RuntimeError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            next_up_failures += 1

    # Backlog
    backlog_failures = 0
    for ticket in BACKLOG_TICKETS:
        issue_num = issue_map[ticket]
        item_id = item_by_issue[str(issue_num)]
        try:
            set_status(item_id, OPT_BACKLOG)
            print(f"Backlog: ticket {ticket} → #{issue_num}")
        except RuntimeError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            backlog_failures += 1

    total_failures = next_up_failures + backlog_failures
    print(f"\nDone. next_up={len(NEXT_UP_TICKETS) - next_up_failures}/{len(NEXT_UP_TICKETS)} "
          f"backlog={len(BACKLOG_TICKETS) - backlog_failures}/{len(BACKLOG_TICKETS)} "
          f"icebox=21 (default, untouched) failures={total_failures}")
    return 0 if total_failures == 0 else 3


if __name__ == "__main__":
    sys.exit(main())
