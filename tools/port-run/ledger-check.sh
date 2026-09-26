#!/usr/bin/env bash
# ledger-check.sh — the port ledger accounts for every tracked file, and nothing leaves without a
# landed capability or an archive (docs/port/PLAN.md, P0 and P9; #311).
#
# Checks tools/port-run/ledger.tsv:
#   - the header is exact;
#   - every tracked path outside docs/decisions/ has exactly one row;
#   - verdict and phase come from the allowed sets;
#   - KEEP-HISTORY rows name their own archive file, docs/history/<path>;
#   - a row whose path is no longer tracked has capability, entry_point and evidence filled (what
#     survives, where it lives now, which test or command shows it), or is KEEP-HISTORY and its
#     archive file is tracked. Evidence is recorded here and run by the phase DoD, not by this check.
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
    if verdict == "KEEP-HISTORY" and archive != "docs/history/" + path:
        problems.append(f"line {n}: KEEP-HISTORY archive_dest must be docs/history/{path}, got {archive!r}")
    if path not in tracked:
        if verdict == "KEEP-HISTORY":
            if archive not in tracked:
                problems.append(f"line {n}: {path} left, but its archive file {archive!r} is not tracked")
        elif not (capability and entry and evidence):
            problems.append(f"line {n}: {path} left the tree without capability, entry_point and evidence")
for path in sorted(tracked - set(seen)):
    problems.append(f"no ledger row for tracked path {path}")
for p in problems:
    print("  " + p)
print(f"ledger-check: {len(seen)} rows, {len(tracked)} tracked, {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
PY
