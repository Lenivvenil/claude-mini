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

# --- Helpers ---

json_deny() {
    local reason="$1"
    cat <<JSON
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
JSON
    exit 2
}

log() {
    echo "[pre-commit-governance] $*" >&2
}

# --- Read input ---

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# --- Early exit: not a git commit ---

if ! echo "$command" | grep -qE '^\s*git\s+commit\b'; then
    exit 0
fi

log "checking: $command"

cd "$cwd" 2>/dev/null || {
    log "cannot cd to $cwd, allowing"
    exit 0
}

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

# --- Rule 1: Conventional Commits prefix ---

cc_regex='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr)(\([a-z0-9_.-]+\))?!?:\s+.+'

if ! echo "$msg" | grep -qE "$cc_regex"; then
    json_deny "Commit message does not follow Conventional Commits. Expected: type(scope?)!?: subject. Allowed types: feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr. Got: '$msg'"
fi

# --- Rule 2: Issue reference ---

has_issue_ref=false
if echo "$msg" | grep -qE '#[0-9]+'; then
    has_issue_ref=true
fi
if echo "$branch" | grep -qE '[0-9]+'; then
    has_issue_ref=true
fi

# ADR-commits и bootstrap не требуют issue-ref (сам ADR — первичный артефакт)
if ! echo "$msg" | grep -qE '^adr(\(|:)' && ! echo "$msg" | grep -qE 'bootstrap|initial'; then
    if [ "$has_issue_ref" = "false" ]; then
        json_deny "Commit message or branch name must reference an issue (#NNN). Got message: '$msg', branch: '$branch'"
    fi
fi

# --- Rule 3: ADR reference for decision-type changes ---

# Decision-type changes: изменения в docs/decisions/, или в файлах, помеченных как
# architecture/data-model/dependencies. Проверяем staged files.

staged=$(git diff --cached --name-only 2>/dev/null || echo "")

decision_markers=(
    "docs/decisions/"
    "go.mod"
    "pyproject.toml"
    "Cargo.toml"
    "package.json"
    ".github/workflows/"
    "docs/domain/"
)

is_decision_change=false
for marker in "${decision_markers[@]}"; do
    if echo "$staged" | grep -qF "$marker"; then
        is_decision_change=true
        break
    fi
done

# ADR-commits сами себе reference — пропускаем
if echo "$msg" | grep -qE '^adr(\(|:)'; then
    is_decision_change=false
fi

if [ "$is_decision_change" = "true" ]; then
    has_adr_ref=false
    # Ссылка на ADR в message
    if echo "$msg" | grep -qiE 'adr[ -]?[0-9]+|docs/decisions/[0-9]+'; then
        has_adr_ref=true
    fi
    # ИЛИ ADR staged в этом же коммите
    if echo "$staged" | grep -qE '^docs/decisions/[0-9]+-.*\.md$'; then
        has_adr_ref=true
    fi

    if [ "$has_adr_ref" = "false" ]; then
        json_deny "Decision-type change detected (staged: $(echo "$staged" | tr '\n' ' ' | head -c 200)). Commit must reference an ADR (e.g., 'Implements ADR-0012' or 'docs/decisions/0012-*.md') OR stage the ADR itself."
    fi
fi

log "OK: $msg"
exit 0
