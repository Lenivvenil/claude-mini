#!/usr/bin/env python3
"""Phase 2 step 2: create 41 GitHub issues from bodies/*.md and persist mapping.

Reads ticket data from sibling _gen_bodies.py (TICKETS list).
Stops on first failure. Re-running is idempotent only if issue-map.json is intact:
already-created tickets are skipped (presence in map = skip).

Run from repo root: python3 .claude/scratch/handoff-2026-04-29/_phase2_create_issues.py
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BODIES = ROOT / "bodies"
MAP_PATH = ROOT / "issue-map.json"

# Import TICKETS by exec — _gen_bodies.py is sibling; cleaner than sys.path tricks.
gen_path = ROOT / "_gen_bodies.py"
spec_globals: dict = {"__file__": str(gen_path), "__name__": "_gen_bodies"}
exec(gen_path.read_text(encoding="utf-8"), spec_globals)
TICKETS: list[dict] = spec_globals["TICKETS"]
assert len(TICKETS) == 41, f"expected 41 tickets, got {len(TICKETS)}"


def load_map() -> dict[str, int]:
    if MAP_PATH.exists():
        return json.loads(MAP_PATH.read_text(encoding="utf-8"))
    return {}


def save_map(m: dict[str, int]) -> None:
    MAP_PATH.write_text(json.dumps(m, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def gh_issue_create(title: str, labels: list[str], body_file: Path) -> int:
    cmd = [
        "gh", "issue", "create",
        "--title", title,
        "--label", ",".join(labels),
        "--body-file", str(body_file),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh issue create failed (exit {result.returncode}): {result.stderr.strip()}")
    url = result.stdout.strip()
    m = re.search(r"/issues/(\d+)$", url)
    if not m:
        raise RuntimeError(f"could not parse issue URL: {url!r}")
    return int(m.group(1))


def main() -> int:
    issue_map = load_map()
    created_now = 0
    skipped = 0
    for t in TICKETS:
        key = f"{t['num']:02d}"
        if key in issue_map:
            skipped += 1
            print(f"skip (already mapped): ticket {key} → #{issue_map[key]}")
            continue
        body_file = BODIES / f"{key}.md"
        if not body_file.exists():
            print(f"FAIL: missing body file {body_file}", file=sys.stderr)
            return 2
        try:
            issue_num = gh_issue_create(t["title"], t["labels"], body_file)
        except RuntimeError as exc:
            print(f"FAIL on ticket {key}: {exc}", file=sys.stderr)
            save_map(issue_map)  # preserve partial progress
            return 3
        issue_map[key] = issue_num
        save_map(issue_map)  # persist after each create — recoverable on crash
        created_now += 1
        print(f"created: ticket {key} → #{issue_num}  ({t['title']})")
    print(f"\nDone. created={created_now} skipped={skipped} total_mapped={len(issue_map)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
