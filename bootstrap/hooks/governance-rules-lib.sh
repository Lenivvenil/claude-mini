#!/usr/bin/env bash
# shellcheck disable=SC2034
# (SC2034: GOV_REASON is this library's out-parameter — assigned here, read by sourcing hooks.)
#
# governance-rules-lib.sh — shared implementation of governance Rules 1-3.
#
# Single source of truth for the rules previously duplicated verbatim between:
#   bootstrap/hooks/pre-commit-governance.sh  (Claude Code PreToolUse, phase 1)
#   bootstrap/hooks/commit-msg-governance.sh  (git commit-msg hook, phase 2, ADR-0011)
#
# Deployment (matches the callers' lookup of "$(dirname $0)/governance-rules-lib.sh"):
#   - in-repo:           bootstrap/hooks/  (next to both hooks)
#   - universal layer:   ~/.claude/hooks/  (hooks copy loop picks up every *.sh)
#   - commit-msg staged: ~/.claude/git-hooks/  (staged by universal-setup.sh --install)
#   - per-repo install:  .git/hooks/  (copied by universal-setup.sh --hook-this-repo)
#
# Library contract:
#   - Sourcing has no side effects: defines functions and constants only, never exits.
#   - Each gov_rule* returns 0 (pass) or 1 (violation) and sets GOV_REASON on violation.
#   - Callers own the deny mechanism (exit 1 to git vs JSON + exit 2 to Claude Code).
#   - No `set -e/-u` assumptions beyond using only declared locals and parameters.

GOV_CC_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr)(\([a-z0-9_.-]+\))?!?:[[:space:]].+'

# Paths whose staged presence marks a commit as decision-type (Rule 3 trigger).
GOV_DECISION_MARKERS=(
    "docs/decisions/"
    "go.mod"
    "pyproject.toml"
    "Cargo.toml"
    "package.json"
    ".github/workflows/"
    "docs/domain/"
)

# Denial messages embed the staged-file list; bound it so the message stays
# readable in terminals and safe to interpolate into JSON deny payloads.
# The full list is always available via `git diff --cached --name-only`.
GOV_STAGED_DISPLAY_LIMIT=200

GOV_REASON=""

# gov_is_adr_commit <subject> → 0 if the subject is an adr-type commit (adr: / adr(scope):)
gov_is_adr_commit() {
    echo "${1:-}" | grep -qE '^adr(\(|:)'
}

# Rule 1: Conventional Commits prefix on the subject line.
# gov_rule1_conventional_commits <subject>
gov_rule1_conventional_commits() {
    local subject="${1:-}"
    GOV_REASON=""
    if echo "$subject" | grep -qE "$GOV_CC_REGEX"; then
        return 0
    fi
    GOV_REASON="Rule 1: message does not follow Conventional Commits. Expected: type(scope?)!?: subject. Allowed types: feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|adr. Got: '$subject'"
    return 1
}

# Rule 2: issue reference (#NNN) in message body or digits in branch name.
# Exempt: adr-type commits (the ADR is the primary artifact) and
# bootstrap/initial meta-commits (word-boundary match, so "reinitialize" does not bypass).
# gov_rule2_issue_ref <subject> <body> <branch>
gov_rule2_issue_ref() {
    local subject="${1:-}" body="${2:-}" branch="${3:-}"
    GOV_REASON=""
    if gov_is_adr_commit "$subject"; then
        return 0
    fi
    if echo "$body" | grep -qE '\b(bootstrap|initial)\b'; then
        return 0
    fi
    if echo "$body" | grep -qE '#[0-9]+'; then
        return 0
    fi
    if echo "$branch" | grep -qE '[0-9]+'; then
        return 0
    fi
    GOV_REASON="Rule 2: message or branch name must reference an issue (#NNN). Got subject: '$subject', branch: '$branch'"
    return 1
}

# Rule 3: decision-type staged changes must reference an ADR in the message
# body or stage an ADR file in the same commit.
# Exempt: adr-type commits (self-referencing).
# gov_rule3_adr_ref <subject> <body> <staged-file-list>
gov_rule3_adr_ref() {
    local subject="${1:-}" body="${2:-}" staged="${3:-}"
    local marker is_decision_change=false
    GOV_REASON=""
    if gov_is_adr_commit "$subject"; then
        return 0
    fi
    for marker in "${GOV_DECISION_MARKERS[@]}"; do
        if echo "$staged" | grep -qF "$marker"; then
            is_decision_change=true
            break
        fi
    done
    if [ "$is_decision_change" = "false" ]; then
        return 0
    fi
    if echo "$body" | grep -qiE 'adr[ -]?[0-9]+|docs/decisions/[0-9]+'; then
        return 0
    fi
    if echo "$staged" | grep -qE '^docs/decisions/[0-9]+-.*\.md$'; then
        return 0
    fi
    GOV_REASON="Rule 3: decision-type change detected (staged: $(echo "$staged" | tr '\n' ' ' | head -c "$GOV_STAGED_DISPLAY_LIMIT")). Commit must reference an ADR (e.g., 'Implements ADR-0012' or 'docs/decisions/0012-*.md') OR stage the ADR file itself."
    return 1
}
