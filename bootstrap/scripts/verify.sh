#!/usr/bin/env bash
# verify.sh — layer-1 deterministic gate for /review (ADR-0023)
#
# Usage:
#   verify.sh           diff-scan: gates changed files only (default, used by /review)
#   verify.sh --full    full-scan: gates entire project (for zero-warning baseline setup)
#
# Output contract (ADR-0023 §5 — exit-code convention):
#   Always exits 0. Prints LAYER1_FAILED on stdout if any gate fails.
#   CI consumers: grep for LAYER1_FAILED to determine pass/fail.
#
# Missing tool = fail (ADR-0023 §3, Principle 3: did-not-run ≠ did-pass).
# Install commands:
#   ruff:     pip install ruff
#   eslint:   npm i -g eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser
#   radon:    pip install radon
#   lizard:   pip install lizard
#   jscpd:    npm i -g jscpd
#   semgrep:  pip install semgrep

set -uo pipefail

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

FAILED=0
OUT=""

emit() { OUT="${OUT}${*}
"; }
fail() { FAILED=1; emit "${*}"; }

# ── Tool availability ──────────────────────────────────────────────────────
MISSING=""
for t in ruff eslint radon lizard jscpd semgrep; do
    command -v "$t" >/dev/null 2>&1 || MISSING="${MISSING} $t"
done

if [ -n "$MISSING" ]; then
    emit "[MISSING-TOOLS]${MISSING}"
    emit "Install commands:"
    emit "  ruff:     pip install ruff"
    emit "  eslint:   npm i -g eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser"
    emit "  radon:    pip install radon"
    emit "  lizard:   pip install lizard"
    emit "  jscpd:    npm i -g jscpd"
    emit "  semgrep:  pip install semgrep"
    echo "LAYER1_FAILED"
    echo "$OUT"
    exit 0
fi

# ── File scope ─────────────────────────────────────────────────────────────
# Security: all file lists use ./ prefix — prevents filenames starting with -
# from being misinterpreted as CLI flags (argument injection).

DIFF_FILES=""
GIT_DIFF_OK=1
PY_FILES=""
JS_FILES=""
DIFF_FILES_SAFE=""  # ./-prefixed, space-separated, for lizard/semgrep

_detect_diff_files() {
    local out
    # --diff-filter=ACMR: Added/Copied/Modified/Renamed only — excludes Deleted.
    # Deleted files no longer exist; passing them to linters produces false failures.
    if out=$(git diff --cached --name-only --diff-filter=ACMR HEAD 2>/dev/null); then
        printf '%s' "$out"; return 0
    fi
    if out=$(git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null); then
        printf '%s' "$out"; return 0
    fi
    if out=$(git show HEAD --name-only --diff-filter=ACMR --format='' 2>/dev/null); then
        printf '%s' "$out"; return 0
    fi
    return 1
}

if [ "$FULL" = "1" ]; then
    # find already returns ./-prefixed paths
    PY_FILES=$(find . -name "*.py" -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null | tr '\n' ' ')
    JS_FILES=$(find . \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        -not -path "./.git/*" -not -path "./node_modules/*" 2>/dev/null | tr '\n' ' ')
else
    if ! DIFF_FILES=$(_detect_diff_files); then
        GIT_DIFF_OK=0
    fi
    if [ "$GIT_DIFF_OK" = "0" ]; then
        fail "[diff-detection] All git diff commands failed — cannot identify changed files."
        fail "Run with --full to scan everything, or check git repository state."
        fail ""
    fi
    # Add ./ prefix to prevent flag injection; filter to existing files only
    PY_FILES=$(echo "$DIFF_FILES" | grep -E '\.py$' | sed 's|^|./|' | tr '\n' ' ')
    JS_FILES=$(echo "$DIFF_FILES" | grep -E '\.(ts|tsx|js|jsx)$' | sed 's|^|./|' | tr '\n' ' ')
    DIFF_FILES_SAFE=$(echo "$DIFF_FILES" | sed 's|^|./|' | tr '\n' ' ')
fi

# Strip leading/trailing whitespace
PY_FILES=$(echo "$PY_FILES" | sed 's/^ *//; s/ *$//')
JS_FILES=$(echo "$JS_FILES" | sed 's/^ *//; s/ *$//')
DIFF_FILES_SAFE=$(echo "$DIFF_FILES_SAFE" | sed 's/^ *//; s/ *$//')

# ── Gate 1: ruff ───────────────────────────────────────────────────────────
if [ -n "$PY_FILES" ]; then
    # shellcheck disable=SC2086
    ruff_out=$(ruff check $PY_FILES 2>&1) && ruff_ok=1 || ruff_ok=0
    if [ "$ruff_ok" = "0" ]; then
        fail "[ruff] Style/lint violations:"
        fail "$ruff_out"
        fail ""
    fi
fi

# ── Gate 2: eslint ─────────────────────────────────────────────────────────
if [ -n "$JS_FILES" ]; then
    # shellcheck disable=SC2086
    eslint_out=$(eslint $JS_FILES 2>&1) && eslint_ok=1 || eslint_ok=0
    if [ "$eslint_ok" = "0" ]; then
        fail "[eslint] TS/JS violations:"
        fail "$eslint_out"
        fail ""
    fi
fi

# ── Gate 3: radon cc — CC > 10 (rank C+) ──────────────────────────────────
if [ -n "$PY_FILES" ]; then
    # -n C: show only rank C or worse (CC > 10); any output = violation
    # Guard exit code + error string — same pattern as radon mi (gate 4).
    # shellcheck disable=SC2086
    radon_cc_out=$(radon cc -n C $PY_FILES 2>&1) && radon_cc_ok=1 || radon_cc_ok=0
    if [ "$radon_cc_ok" = "0" ] || echo "$radon_cc_out" | grep -qi "error"; then
        fail "[radon-cc] radon exited with an error or reported ERROR:"
        fail "$radon_cc_out"
        fail ""
    elif [ -n "$radon_cc_out" ]; then
        fail "[radon-cc] Cyclomatic complexity > 10 (rank C+):"
        fail "$radon_cc_out"
        fail ""
    fi
fi

# ── Gate 4: radon mi — MI < 65 ─────────────────────────────────────────────
# Threshold 65 from synthesis doc (ADR-0023 §2); not radon's own rank boundary.
if [ -n "$PY_FILES" ]; then
    # shellcheck disable=SC2086
    radon_mi_raw=$(radon mi -s $PY_FILES 2>&1) && radon_mi_ok=1 || radon_mi_ok=0
    if [ "$radon_mi_ok" = "0" ] || echo "$radon_mi_raw" | grep -qi "error"; then
        fail "[radon-mi] radon exited with an error or reported ERROR:"
        fail "$radon_mi_raw"
        fail ""
    else
        # Output format: "path/to/file.py - RANK (score)" — extract score from parens
        radon_mi_bad=$(echo "$radon_mi_raw" | awk -F'[()]' 'NF>1 && $2+0 < 65 {print $0}')
        if [ -n "$radon_mi_bad" ]; then
            fail "[radon-mi] Maintainability Index < 65:"
            fail "$radon_mi_bad"
            fail ""
        fi
    fi
fi

# ── Gate 5: lizard — CCN > 10, length > 100, args > 5 ─────────────────────
if [ "$FULL" = "1" ]; then
    lizard_out=$(lizard -C 10 -L 100 -a 5 . 2>&1) && lizard_ok=1 || lizard_ok=0
elif [ "$GIT_DIFF_OK" = "0" ]; then
    lizard_ok=1  # diff-detection already failed; its LAYER1_FAILED is emitted above
    lizard_out=""
elif [ -n "$DIFF_FILES_SAFE" ]; then
    # shellcheck disable=SC2086
    lizard_out=$(lizard -C 10 -L 100 -a 5 $DIFF_FILES_SAFE 2>&1) && lizard_ok=1 || lizard_ok=0
else
    lizard_ok=1  # no changed files — nothing to scan
    lizard_out=""
fi
if [ "${lizard_ok}" = "0" ]; then
    fail "[lizard] Complexity/length/args threshold exceeded (-C 10 -L 100 -a 5):"
    fail "$lizard_out"
    fail ""
fi

# ── Gate 6: jscpd (always whole-repo — copy-paste spans files outside diff) ─
jscpd_out=$(jscpd . --min-tokens 50 --min-lines 5 --mode strict --reporters console 2>&1) \
    && jscpd_ok=1 || jscpd_ok=0
if [ "$jscpd_ok" = "0" ]; then
    fail "[jscpd] Duplication found (min-tokens:50, min-lines:5, strict):"
    fail "$jscpd_out"
    fail ""
fi

# ── Gate 7: semgrep — LLM anti-pattern rules ──────────────────────────────
SEMGREP_CONFIG=".semgrep/llm-antipatterns.yaml"
if [ ! -f "$SEMGREP_CONFIG" ]; then
    fail "[semgrep] $SEMGREP_CONFIG not found."
    fail "Run: ./bootstrap/universal-setup.sh --target . to install templates."
    fail ""
else
    if [ "$FULL" = "1" ]; then
        semgrep_target="."
    elif [ "$GIT_DIFF_OK" = "0" ]; then
        semgrep_target=""  # diff-detection failed; skip — LAYER1_FAILED already emitted above
    elif [ -n "$DIFF_FILES_SAFE" ]; then
        semgrep_target="$DIFF_FILES_SAFE"
    else
        semgrep_target="."
    fi
    if [ -n "$semgrep_target" ]; then
        # shellcheck disable=SC2086
        semgrep_out=$(semgrep --config "$SEMGREP_CONFIG" $semgrep_target 2>&1) && semgrep_ok=1 || semgrep_ok=0
        if [ "$semgrep_ok" = "0" ]; then
            fail "[semgrep] LLM anti-pattern findings:"
            fail "$semgrep_out"
            fail ""
        fi
    fi
fi

# ── Final output ───────────────────────────────────────────────────────────
if [ "$FAILED" = "1" ]; then
    echo "LAYER1_FAILED"
    echo ""
    printf "%s" "$OUT"
else
    echo "LAYER1_PASSED — all gates green"
fi

exit 0
