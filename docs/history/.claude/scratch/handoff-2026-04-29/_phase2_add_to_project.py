#!/usr/bin/env python3
"""Phase 2 step 4: add 41 issues to Projects v2 board #5 (claude-mini, owner Lenivvenil).

Reads issue numbers from issue-map.json and runs:
  gh project item-add 5 --owner Lenivvenil --url https://github.com/Lenivvenil/claude-mini/issues/<num>

No Status/Priority assignment — board has lifecycle Status (Icebox/Backlog/Next up/...) but no
P0..P3 priority field. P-level is already encoded in labels (P0-critical/P1-high/...). Mapping
P-level → lifecycle Status would be interpretation; flagged in REPORT.md instead.

Idempotent at item level: gh project item-add returns success even if item already on board
(the platform deduplicates by URL). Re-running is safe.

Run from repo root: python3 .claude/scratch/handoff-2026-04-29/_phase2_add_to_project.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MAP_PATH = ROOT / "issue-map.json"
PROJECT_NUMBER = "5"
PROJECT_OWNER = "Lenivvenil"
REPO = "Lenivvenil/claude-mini"

issue_map: dict[str, int] = json.loads(MAP_PATH.read_text(encoding="utf-8"))


def gh_project_item_add(issue_url: str) -> str:
    cmd = [
        "gh", "project", "item-add", PROJECT_NUMBER,
        "--owner", PROJECT_OWNER,
        "--url", issue_url,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh project item-add failed for {issue_url}: {result.stderr.strip()}")
    return result.stdout.strip()


def main() -> int:
    added = 0
    failed = 0
    for key in sorted(issue_map.keys()):
        issue_num = issue_map[key]
        url = f"https://github.com/{REPO}/issues/{issue_num}"
        try:
            out = gh_project_item_add(url)
            print(f"added: ticket {key} → #{issue_num}")
            added += 1
        except RuntimeError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            failed += 1
    print(f"\nDone. added={added} failed={failed}")
    return 0 if failed == 0 else 3


if __name__ == "__main__":
    sys.exit(main())
