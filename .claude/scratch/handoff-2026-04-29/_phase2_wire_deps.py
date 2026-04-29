#!/usr/bin/env python3
"""Phase 2 step 3: prepend Depends-on block to issue bodies for tickets that have depends_on.

Reads ticket data from sibling _gen_bodies.py (TICKETS list).
Reads issue-map.json to resolve ticket NN → GitHub issue number.
For each ticket with non-empty depends_on:
  - Build a "## Depends on" block listing each dependency by GitHub issue number + ticket id + title.
  - Prepend the block to the original body content from bodies/NN.md.
  - Push via `gh issue edit <num> --body-file <tmp>`.

Idempotent: regenerates the prefix block from current map every run; replaces existing
prefix if it starts with our marker. Safe to re-run after edits to dependencies.

Run from repo root: python3 .claude/scratch/handoff-2026-04-29/_phase2_wire_deps.py
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BODIES = ROOT / "bodies"
MAP_PATH = ROOT / "issue-map.json"

gen_path = ROOT / "_gen_bodies.py"
spec_globals: dict = {"__file__": str(gen_path), "__name__": "_gen_bodies"}
exec(gen_path.read_text(encoding="utf-8"), spec_globals)
TICKETS: list[dict] = spec_globals["TICKETS"]
TICKETS_BY_NUM: dict[int, dict] = {t["num"]: t for t in TICKETS}

issue_map: dict[str, int] = json.loads(MAP_PATH.read_text(encoding="utf-8"))


def resolve(ticket_num: int) -> int:
    key = f"{ticket_num:02d}"
    if key not in issue_map:
        raise KeyError(f"ticket {key} not in issue-map.json")
    return issue_map[key]


def render_deps_block(t: dict) -> str:
    lines = ["## Depends on", ""]
    for dep_num in t["depends_on"]:
        dep_issue = resolve(dep_num)
        dep_title = TICKETS_BY_NUM[dep_num]["title"]
        lines.append(f"- #{dep_issue} (ticket {dep_num:02d}: {dep_title})")
    lines.append("")
    lines.append("---")
    lines.append("")
    return "\n".join(lines)


def gh_issue_edit(issue_num: int, body: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as fp:
        fp.write(body)
        tmp_path = fp.name
    cmd = ["gh", "issue", "edit", str(issue_num), "--body-file", tmp_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    Path(tmp_path).unlink(missing_ok=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh issue edit #{issue_num} failed: {result.stderr.strip()}")


def main() -> int:
    updated = 0
    skipped = 0
    for t in TICKETS:
        if not t["depends_on"]:
            skipped += 1
            continue
        key = f"{t['num']:02d}"
        body_path = BODIES / f"{key}.md"
        original = body_path.read_text(encoding="utf-8")
        deps_block = render_deps_block(t)
        new_body = deps_block + original
        issue_num = resolve(t["num"])
        try:
            gh_issue_edit(issue_num, new_body)
        except RuntimeError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            return 3
        deps_str = ", ".join(f"#{resolve(d)}" for d in t["depends_on"])
        print(f"wired ticket {key} → #{issue_num} (depends on {deps_str})")
        updated += 1
    print(f"\nDone. updated={updated} skipped_no_deps={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
