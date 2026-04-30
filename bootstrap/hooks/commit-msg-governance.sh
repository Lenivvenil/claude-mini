#!/usr/bin/env bash
# commit-msg-governance.sh — git commit-msg hook (phase 2 governance, ADR-0011)
#
# Called by git with a file path as $1 containing the proposed commit message.
# Enforces Rules 1-3 from the governance policy, covering direct terminal commits
# that bypass Claude Code's PreToolUse hook (phase 1).
#
# Rules enforced:
#   1. Conventional Commits prefix in message
#   2. Issue reference (#NNN or Closes #NNN) in message or branch name
#   3. ADR reference for decision-type staged changes
#
# Rule 4 (no direct commits to main) is deliberately NOT enforced here.
# Rationale: the hook exists only where the installer placed it; the operator
# is root on their own machine; terminal commits to main remain ungoverned
# by design. See ADR-0011 §Decision Outcome.
#
# Sync note: rules are duplicated from pre-commit-governance.sh (PreToolUse).
# If the policy changes in one, update both.
# Cross-reference: bootstrap/hooks/pre-commit-governance.sh

set -uo pipefail

deny() {
    echo "[commit-msg-governance] BLOCKED: $1" >&2
    exit 1
}

log() {
    echo "[commit-msg-governance] $*" >&2
}

# --- Read commit message from file ($1 is the path) ---

msg_file="${1:-}"
if [ -z "$msg_file" ] || [ ! -f "$msg_file" ]; then
    log "called without a valid message file; passing through"
    exit 0
fi

msg_raw=$(cat "$msg_file")

# Strip comment lines (lines starting with #) — git includes them in the file
msg_body=$(echo "$msg_raw" | grep -v '^#')

# Subject = first non-blank non-comment line
msg_subject=$(echo "$msg_body" | sed '/^[[:space:]]*$/d' | head -1)

if [ -z "$msg_subject" ]; then
    deny "Empty commit message"
fi

# --- Exempt merge commits ---
# Merge commits (git merge --no-ff) have no CC prefix by design.
# In this solo workflow merges go through GitHub PR API and don't invoke this hook.
if echo "$msg_subject" | grep -qE '^Merge (branch|pull request|remote-tracking branch|tag)'; then
    log "merge commit detected, passing through"
    exit 0
fi

# --- Exempt fixup and squash commits (git rebase -i) ---
if echo "$msg_subject" | grep -qE '^(fixup|squash)!'; then
    log "fixup/squash commit detected, passing through"
    exit 0
fi

# --- Rule 1: Conventional Commits prefix (subject line only) ---

cc_regex='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr)(\([a-z0-9_.-]+\))?!?:[[:space:]].+'

if ! echo "$msg_subject" | grep -qE "$cc_regex"; then
    deny "Rule 1: message does not follow Conventional Commits. Expected: type(scope?)!?: subject. Allowed types: feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr. Got: '$msg_subject'"
fi

# --- Rule 2: Issue reference (full message body + branch name) ---
# Refs may appear in subject OR body (e.g. "Closes #9" in a multi-line message).

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

has_issue_ref=false
if echo "$msg_body" | grep -qE '#[0-9]+'; then
    has_issue_ref=true
fi
if echo "$branch" | grep -qE '[0-9]+'; then
    has_issue_ref=true
fi

# ADR-commits and bootstrap/initial commits are exempt from issue-ref requirement
if ! echo "$msg_subject" | grep -qE '^adr(\(|:)' && ! echo "$msg_body" | grep -qE '\b(bootstrap|initial)\b'; then
    if [ "$has_issue_ref" = "false" ]; then
        deny "Rule 2: message or branch name must reference an issue (#NNN). Got subject: '$msg_subject', branch: '$branch'"
    fi
fi

# --- Rule 3: ADR reference for decision-type staged changes (full message body) ---
# Refs may appear in subject OR body (e.g. "Implements ADR-0011" in body).

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

# ADR-commits are self-referencing — exempt from the ADR-ref requirement
if echo "$msg_subject" | grep -qE '^adr(\(|:)'; then
    is_decision_change=false
fi

if [ "$is_decision_change" = "true" ]; then
    has_adr_ref=false
    if echo "$msg_body" | grep -qiE 'adr[ -]?[0-9]+|docs/decisions/[0-9]+'; then
        has_adr_ref=true
    fi
    if echo "$staged" | grep -qE '^docs/decisions/[0-9]+-.*\.md$'; then
        has_adr_ref=true
    fi
    if [ "$has_adr_ref" = "false" ]; then
        deny "Rule 3: decision-type change detected (staged: $(echo "$staged" | tr '\n' ' ' | head -c 200)). Commit must reference an ADR (e.g., 'Implements ADR-0012' or 'docs/decisions/0012-*.md') OR stage the ADR file itself."
    fi
fi

# --- Anti-patterns reminder (non-blocking, exit 0) ---
# Fires when: (a) staged files include non-docs code (*.sh, *.py, *.bats,
# bootstrap/) AND (b) docs/anti-patterns.md is not staged in this commit AND
# (c) docs/anti-patterns.md has not been touched in any commit on this branch
# since it diverged from origin/main.
# Scoped to merge-base..HEAD so existing commits on main do not suppress the
# reminder on a new branch. Falls back to HEAD (all history) when origin/main
# does not exist (e.g. sandboxed repos in tests).
all_staged=$(git diff --cached --name-only 2>/dev/null || true)
staged_code=$(echo "$all_staged" | \
    grep -v '^docs/' | grep -v '\.md$' | grep -E '\.(sh|py|bats)$|^bootstrap/' || true)
if echo "$all_staged" | grep -qE '^docs/anti-patterns\.md$'; then
    ap_staged=yes
else
    ap_staged=
fi
if [ -n "$staged_code" ] && [ -z "$ap_staged" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    _base=$(git merge-base HEAD origin/main 2>/dev/null || true)
    if [ -n "$_base" ]; then
        anti_pattern_commits=$(git log --oneline --max-count=1 "${_base}..HEAD" -- docs/anti-patterns.md 2>/dev/null | wc -l | tr -d '[:space:]')
    else
        anti_pattern_commits=$(git log --oneline --max-count=1 HEAD -- docs/anti-patterns.md 2>/dev/null | wc -l | tr -d '[:space:]')
    fi
    unset _base
    if [ "${anti_pattern_commits:-0}" -eq 0 ]; then
        log "REMINDER: code staged but docs/anti-patterns.md not touched on this branch — consider adding a new entry if you caught a lazy pattern this session"
    fi
fi

log "OK: $msg_subject"
exit 0
