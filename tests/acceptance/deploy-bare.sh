#!/usr/bin/env bash
# deploy-bare.sh — acceptance of ADR-0031: a bare Claude session asked "deploy my harness for this
# project" deploys it by itself and harms nothing around it (#314).
#
# Skeleton in P0 (#311): the deployment commands arrive in P2–P3, so this test reports
# NOT IMPLEMENTED and exits 1. P3 replaces this body; see docs/port/PLAN.md §5 for the checks.
# Exit: 0 pass · 1 fail or not implemented · 77 skipped (no subscription token).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null  # helper checked on its own; path resolved at run time
. "$REPO/tools/port-run/lib/isolated-claude.sh"
iso_require_token

echo "  NOT IMPLEMENTED: deploy-bare.sh is completed in P3 (#314)."
exit 1
