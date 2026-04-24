#!/usr/bin/env bash
# Returns the next ADR number in zero-padded 4-digit form.
# Reads docs/decisions/NNNN-*.md pattern and increments.
set -euo pipefail

ADR_DIR="${ADR_DIR:-docs/decisions}"

if [ ! -d "$ADR_DIR" ]; then
    echo "0001"
    exit 0
fi

latest=""
for _f in "$ADR_DIR"/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$_f" ] || continue
    _num=$(basename "$_f" | cut -c1-4)
    if [ -z "$latest" ] || [ "$((10#$_num))" -gt "$((10#$latest))" ]; then
        latest="$_num"
    fi
done

if [ -z "$latest" ]; then
    echo "0001"
else
    next=$((10#$latest + 1))
    printf "%04d\n" "$next"
fi
