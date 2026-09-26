#!/usr/bin/env bash
# hedging-lint.sh — scan pipeline artifacts for hedging language (Principle 1)
#
# Usage: hedging-lint.sh [file1 file2 ...]
#   Files are filtered to target paths only: plan.md, STATE.md, docs/decisions/*.md
#   CWD must be the repository root (config at .semgrep/hedging.yml is resolved relative to CWD).
#
# Exit codes:
#   0 — no findings or no target files staged
#   1 — semgrep findings (hedging language detected)
#   2 — setup error: semgrep not installed or config missing (fail-closed)

set -uo pipefail

CONFIG=".semgrep/hedging.yml"
TARGET_RE='^(plan\.md|STATE\.md|docs/decisions/[^/]+\.md)$'

RED=$'\033[0;31m'; NC=$'\033[0m'

# --- Filter args to target paths only ---

files=()
for f in "$@"; do
    clean="${f#./}"  # strip leading ./ for pattern matching
    if echo "$clean" | grep -qE "$TARGET_RE" && [ -f "$clean" ]; then
        files+=("./$clean")
    fi
done

[ "${#files[@]}" -eq 0 ] && exit 0

# --- Fail-closed checks ---

if ! command -v semgrep >/dev/null 2>&1; then
    printf '%s[hedging-lint] semgrep not installed. Install: brew install semgrep  OR  pip install semgrep%s\n' "$RED" "$NC" >&2
    exit 2
fi

if [ ! -f "$CONFIG" ]; then
    printf '%s[hedging-lint] Config not found: %s%s\n' "$RED" "$CONFIG" "$NC" >&2
    printf 'Run: ./bootstrap/universal-setup.sh --target . to install, or add .semgrep/hedging.yml manually.\n' >&2
    exit 2
fi

# --- Run semgrep ---
# --error: exit 1 when findings present
# stderr suppressed from semgrep verbosity; only findings go to stdout

semgrep scan --config "$CONFIG" --error "${files[@]}"
