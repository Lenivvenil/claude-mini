#!/usr/bin/env bash
# Returns the next ADR number in zero-padded 4-digit form.
# Reads docs/decisions/NNNN-*.md pattern and increments.
set -euo pipefail

ADR_DIR="${ADR_DIR:-docs/decisions}"

if [ ! -d "$ADR_DIR" ]; then
    echo "0001"
    exit 0
fi

latest=$(ls -1 "$ADR_DIR" 2>/dev/null \
    | grep -oE '^[0-9]{4}' \
    | sort -n \
    | tail -1 || true)

if [ -z "$latest" ]; then
    echo "0001"
else
    next=$((10#$latest + 1))
    printf "%04d\n" "$next"
fi
