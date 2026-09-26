#!/usr/bin/env bash
# find-tests.sh — locate test files for a given filename stem.
# Usage: find-tests.sh <stem>
# Output: matching test file paths, one per line; empty if none found.
# Exit 0 always.
stem="${1:?Usage: find-tests.sh <stem>}"
find . \( \
    -name "test_${stem}*" \
    -o -name "${stem}_test*" \
    -o -name "*.bats" \
\) 2>/dev/null
