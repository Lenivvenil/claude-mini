#!/usr/bin/env bash
# ledger-check.sh — the port ledger accounts for every tracked file, and nothing leaves without a
# landed capability or an archive (docs/port/PLAN.md, P0 and P9; #311).
#
# Checks tools/port-run/ledger.tsv:
#   - the header is exact;
#   - every tracked path outside docs/decisions/ has exactly one row;
#   - verdict and phase come from the allowed sets;
#   - KEEP-HISTORY rows name an archive_dest;
#   - a row whose path is no longer tracked has entry_point and evidence filled (the capability
#     landed somewhere and is proven), or is KEEP-HISTORY with a tracked archive_dest.
# Exit 0 ok · 1 findings.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER="$REPO/tools/port-run/ledger.tsv"
HEADER=$'path\tverdict\tcapability\tentry_point\tevidence\tphase\tarchive_dest'

python3 - "$REPO" "$LEDGER" "$HEADER" <<'PY'
import subprocess, sys
repo, ledger, header = sys.argv[1:4]
VERDICTS = {"KEEP", "PORT", "MODERNISE", "MERGE", "DROP", "KEEP-HISTORY"}
PHASES = {"-"} | {f"p{i}" for i in range(10)}
tracked = {f for f in subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True,
                                     check=True).stdout.split("\n") if f and not f.startswith("docs/decisions/")}
lines = open(ledger, encoding="utf-8").read().rstrip("\n").split("\n")
problems = []
if lines[0] != header:
    problems.append("header differs from the expected column list")
seen = {}
for n, line in enumerate(lines[1:], start=2):
    cols = line.split("\t")
    if len(cols) != 7:
        problems.append(f"line {n}: {len(cols)} columns, expected 7")
        continue
    path, verdict, capability, entry, evidence, phase, archive = cols
    if path in seen:
        problems.append(f"line {n}: duplicate row for {path} (first at line {seen[path]})")
    seen[path] = n
    if verdict not in VERDICTS:
        problems.append(f"line {n}: unknown verdict {verdict!r}")
    if phase not in PHASES:
        problems.append(f"line {n}: unknown phase {phase!r}")
    if verdict == "KEEP-HISTORY" and not archive:
        problems.append(f"line {n}: KEEP-HISTORY without archive_dest: {path}")
    if path not in tracked:
        if verdict == "KEEP-HISTORY":
            if not any(t.startswith(archive.rstrip("/") + "/") or t == archive for t in tracked):
                problems.append(f"line {n}: {path} left, but archive_dest {archive!r} holds nothing")
        elif not (entry and evidence):
            problems.append(f"line {n}: {path} left the tree without entry_point and evidence")
for path in sorted(tracked - set(seen)):
    problems.append(f"no ledger row for tracked path {path}")
for p in problems:
    print("  " + p)
print(f"ledger-check: {len(seen)} rows, {len(tracked)} tracked, {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
PY
