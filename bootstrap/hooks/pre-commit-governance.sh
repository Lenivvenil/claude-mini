#!/usr/bin/env bash
# pre-commit-governance.sh — Claude Code PreToolUse hook
#
# Запускается Claude Code при попытке вызвать `git commit`.
# Получает на stdin JSON: {"tool_input":{"command": "..."}, "cwd": "..."}
# Возвращает exit 0 для пропуска, exit 2 с JSON для блокировки.
#
# Правила (в порядке выполнения):
#   4. (first) Запрет direct commit на main (ADR-0009); carve-out: chore:/build: bootstrap/initial
#   1. Conventional Commits prefix в message
#   2. Ссылка на issue (#NNN или Closes #NNN) в message или branch name
#   3. Ссылка на ADR (docs/decisions/NNNN-*.md) для decision-type changes
#
# IMPORTANT: в settings.json путь к этому скрипту должен быть АБСОЛЮТНЫМ,
# не с тильдой — Claude Code передаёт command в exec без shell expansion.

set -uo pipefail

# --- Gate audit instrumentation (optional — fails silently if lib missing) ---
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_GATE_AUDIT_LIB="$_SELF_DIR/../scripts/gate-audit-lib.sh"
# Temporarily suspend -u while sourcing to guard against any unset-var reference in the lib.
# shellcheck source=/dev/null
if [ -f "$_GATE_AUDIT_LIB" ]; then
    set +u
    source "$_GATE_AUDIT_LIB"
    set -u
fi
unset _GATE_AUDIT_LIB

# --- Shared governance rules 1-3 (fail-closed below, after json_deny is defined) ---
_RULES_LIB="$_SELF_DIR/governance-rules-lib.sh"
if [ -f "$_RULES_LIB" ]; then
    # shellcheck source=/dev/null
    source "$_RULES_LIB"
fi

# --- Helpers ---

json_deny() {
    local reason="${1//\"/\\\"}"
    # Emit deny payload FIRST to guarantee the hook contract is met regardless of audit-write
    # duration or failure. Audit write happens after — it cannot block the deny response.
    cat <<JSON
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
JSON
    # Write blocked event only when we have cd'd to the target repo (_GATE_AUDIT_READY=1).
    # Early exits (jq missing, malformed stdin) fire before cd — skip there to avoid
    # writing to whatever repo the hook process was launched from.
    if [ "${_GATE_AUDIT_READY:-0}" = "1" ] && command -v gate_event_write >/dev/null 2>&1; then
        gate_event_write "pre-commit-governance" "blocked" >/dev/null || true
    fi
    exit 2
}

log() {
    echo "[pre-commit-governance] $*" >&2
}

# --- jq prerequisite check (fail-closed, not fail-open) ---

if ! command -v jq >/dev/null 2>&1; then
    # Use printf (bash builtin) — cat is not available without jq in minimal PATH
    printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"pre-commit-governance: jq not found. Install jq to enable commit governance (brew install jq)."}}\n'
    exit 2
fi

# --- Read input ---

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)

# Fail-closed on unparseable stdin — empty command on non-empty input means malformed JSON
if [ -n "$input" ] && [ -z "$command" ] && [ -z "$cwd" ]; then
    json_deny "pre-commit-governance: could not parse stdin as JSON (input non-empty but both fields empty). Check hook invocation."
fi

# --- Early exit: not a git commit ---

if ! echo "$command" | grep -qE '^\s*git\s+commit\b'; then
    exit 0
fi

log "checking: $command"

cd "$cwd" 2>/dev/null || {
    log "cannot cd to $cwd, allowing"
    exit 0
}
_GATE_AUDIT_READY=1  # gate_event_write now safe: we are in the correct repo

# --- Extract branch (needed by Rule 4, which runs before message-dependent rules) ---

# fail-open on detached HEAD (returns "HEAD", not "main") / fresh clone (error → "")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# --- Rule 4: No direct commits to main (ADR-0009) ---
# Placed before amend-skip and message rules so it fires first.
# This means `git commit --amend` on main is also blocked — intentional.
# ADR commits land on main via `gh pr merge` (API call, hook not triggered) — no carve-out needed.
# Carve-out: bootstrap/initial meta-commits scoped to chore:/build: prefix with word-boundary
# to prevent "feat: add initial thing (#N)" from bypassing.

if [ "$branch" = "main" ]; then
    msg_for_rule4=$(echo "$command" | grep -oE '\-m\s+"[^"]*"' | head -1 | sed -E 's/^-m[ ]+"(.*)"$/\1/')
    if [ -z "$msg_for_rule4" ]; then
        msg_for_rule4=$(echo "$command" | grep -oE "\-m\s+'[^']*'" | head -1 | sed -E "s/^-m[ ]+'(.*)'$/\1/")
    fi
    if ! echo "$msg_for_rule4" | grep -qE '^(chore|build)(\([a-z0-9_.-]+\))?!?:\s+.*\b(bootstrap|initial)\b'; then
        json_deny "Direct commits to 'main' are not allowed (ADR-0009). Create a feature branch first: git checkout -b feat/<slug>-<issue-number>. Carve-out: chore:/build: bootstrap/initial commits only."
    fi
fi

# --- Extract commit message ---

# Case 1: git commit -m "..."
# Case 2: git commit -am "..."
# Case 3: git commit --amend (no new message — skip strict check)
# Case 4: git commit (will open editor — Claude shouldn't do this, but allow)

if echo "$command" | grep -qE '\-\-amend'; then
    log "amend detected, skipping strict check"
    exit 0
fi

msg=$(echo "$command" | grep -oE '\-m\s+"[^"]*"' | head -1 | sed -E 's/^-m[ ]+"(.*)"$/\1/')

if [ -z "$msg" ]; then
    msg=$(echo "$command" | grep -oE "\-m\s+'[^']*'" | head -1 | sed -E "s/^-m[ ]+'(.*)'$/\1/")
fi

if [ -z "$msg" ]; then
    json_deny "Commit without -m flag not allowed from Claude (would open editor). Use: git commit -m \"<type>: <subject> (#NNN)\""
fi

# --- Rules 1-3 (shared logic: governance-rules-lib.sh) ---
# Fail-closed: a missing rules library means no governance — deny, do not pass through.

if ! command -v gov_rule1_conventional_commits >/dev/null 2>&1; then
    json_deny "pre-commit-governance: governance-rules-lib.sh missing at $_RULES_LIB. Re-run: ./bootstrap/universal-setup.sh --install"
fi

staged=$(git diff --cached --name-only 2>/dev/null || echo "")

# `git commit -m` carries a single message string: it is both subject and body here.
if ! gov_rule1_conventional_commits "$msg"; then
    json_deny "$GOV_REASON"
fi

if ! gov_rule2_issue_ref "$msg" "$msg" "$branch"; then
    json_deny "$GOV_REASON"
fi

if ! gov_rule3_adr_ref "$msg" "$msg" "$staged"; then
    json_deny "$GOV_REASON"
fi

# --- Rule H: Hedging language in plan.md / STATE.md / docs/decisions/*.md ---
# Scans staged markdown artifacts for banned hedging terms (Principle 1).
# Fail-closed: missing wrapper, missing semgrep, or missing config → deny.

_HEDGING_LINT="$_SELF_DIR/../scripts/hedging-lint.sh"

# Use core.quotePath=false + -z so Cyrillic/space filenames are not C-quoted or word-split.
hedging_staged=()
while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    case "$f" in
        plan.md|STATE.md|docs/decisions/*.md)
            hedging_staged+=("./$f")
            ;;
    esac
done < <(git -c core.quotePath=false diff --cached --name-only -z 2>/dev/null)

if [ "${#hedging_staged[@]}" -gt 0 ]; then
    if [ ! -f "$_HEDGING_LINT" ]; then
        json_deny "pre-commit-governance Rule H: hedging-lint.sh missing at $_HEDGING_LINT. Re-run: ./bootstrap/universal-setup.sh --install"
    fi
    hedging_out=$(bash "$_HEDGING_LINT" "${hedging_staged[@]}" 2>&1)
    hedging_exit=$?
    if [ "$hedging_exit" -ne 0 ]; then
        # Strip control chars from semgrep output before JSON interpolation
        # (json_deny only escapes double-quotes; semgrep findings contain ANSI escapes, backticks)
        hedging_summary=$(echo "$hedging_out" \
            | grep -E '(hedging-|depends-without|Blocking|┆)' \
            | head -5 \
            | sed 's/[[:cntrl:]]//g; s/\\//g' \
            | tr '\n' ' ')
        if [ "$hedging_exit" -eq 2 ]; then
            json_deny "pre-commit-governance Rule H setup error (semgrep or config missing). Details: $hedging_summary. Re-run: ./bootstrap/universal-setup.sh --install"
        else
            json_deny "Hedging language in staged files (Principle 1). Fix or add nosemgrep. See: docs/runbooks/hedging-lint.md. Details: $hedging_summary"
        fi
    fi
fi

log "OK: $msg"
if [ "${_GATE_AUDIT_READY:-0}" = "1" ] && command -v gate_event_write >/dev/null 2>&1; then
    gate_event_write "pre-commit-governance" "allowed" >/dev/null || true
fi
exit 0
