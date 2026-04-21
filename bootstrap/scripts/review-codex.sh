#!/usr/bin/env bash
# review-codex.sh — второе мнение через Codex CLI с graceful degradation
#
# Fallback chain для diff:
#   1. git diff --cached (staged)
#   2. git diff HEAD (unstaged)
#   3. git show HEAD (last commit)
#   4. Against base branch (main/master) — для review уже коммитнутой ветки
#
# На exit 4 (quota) или 124 (timeout) создаёт `type:deferred-review` issue
# и выходит с маркером SKIPPED — не блокирует pipeline.

set -uo pipefail

CODEX_TIMEOUT="${CODEX_TIMEOUT:-120}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.2}"

# --- Prerequisite checks ---

if ! command -v codex >/dev/null 2>&1; then
    echo "# /codex-review"
    echo ""
    echo "SKIPPED: codex CLI не установлен. Install: npm i -g @openai/codex"
    exit 0
fi

# --- Get diff with fallback chain ---

diff=""
source=""

if diff=$(git diff --cached 2>/dev/null) && [ -n "$diff" ]; then
    source="staged diff"
elif diff=$(git diff HEAD 2>/dev/null) && [ -n "$diff" ]; then
    source="working tree diff"
elif diff=$(git show HEAD 2>/dev/null) && [ -n "$diff" ]; then
    source="last commit"
else
    # Последний fallback: diff против base branch (main/master)
    base_branch=""
    for candidate in main master; do
        if git show-ref --verify --quiet "refs/heads/$candidate"; then
            base_branch="$candidate"
            break
        fi
    done
    if [ -n "$base_branch" ]; then
        current=$(git rev-parse --abbrev-ref HEAD)
        if [ "$current" != "$base_branch" ]; then
            diff=$(git diff "$base_branch"..."$current" 2>/dev/null || echo "")
            source="branch vs $base_branch"
        fi
    fi
fi

if [ -z "$diff" ]; then
    echo "# /codex-review"
    echo ""
    echo "Ничего не найдено для review — staged, working tree, last commit, и branch diff все пусты."
    exit 0
fi

# --- Prepare prompt ---

prompt=$(cat <<PROMPT
Review the following diff and report findings by severity (BLOCK / SUGGEST / NIT).

Check for:
- Correctness (logic errors, off-by-one, null handling)
- Security (SQL injection, secrets, auth bypass, unsafe deserialization)
- Performance (N+1, accidental quadratic, blocking I/O in async)
- Consistency with codebase style
- Test coverage (are critical paths tested?)

Return markdown only. No preamble. Maximum 300 words.

Source: $source

Diff:
\`\`\`
$diff
\`\`\`
PROMPT
)

# --- Invoke Codex with timeout ---

tmp_out=$(mktemp)
tmp_err=$(mktemp)
trap 'rm -f "$tmp_out" "$tmp_err"' EXIT

timeout "$CODEX_TIMEOUT" codex --model "$CODEX_MODEL" exec "$prompt" \
    > "$tmp_out" 2> "$tmp_err"
exit_code=$?

# --- Handle result ---

case $exit_code in
    0)
        echo "# /codex-review"
        echo ""
        echo "**Source:** $source"
        echo "**Model:** $CODEX_MODEL"
        echo ""
        cat "$tmp_out"
        exit 0
        ;;
    4|124)
        # Quota exhausted (4) or timeout (124) — graceful degradation
        echo "# /codex-review" >&2
        echo "" >&2
        echo "SKIPPED: Codex недоступен (exit=$exit_code: $([ $exit_code -eq 4 ] && echo quota || echo timeout))" >&2
        echo "" >&2

        # Open deferred-review issue if gh available
        if command -v gh >/dev/null 2>&1; then
            issue_title="Deferred codex review: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
            issue_body=$(cat <<BODY
Codex review скипнут из-за $([ $exit_code -eq 4 ] && echo "Plus quota" || echo "timeout").

**Source:** $source
**Branch:** $(git rev-parse --abbrev-ref HEAD 2>/dev/null)
**Commit:** $(git rev-parse HEAD 2>/dev/null)

Повторить review вручную когда Plus квота восстановится:
\`\`\`bash
git checkout $(git rev-parse HEAD)
bash ~/.claude/scripts/review-codex.sh
\`\`\`
BODY
            )
            if gh issue create \
                --title "$issue_title" \
                --body "$issue_body" \
                --label "type:deferred-review" >/dev/null 2>&1; then
                echo "Opened deferred-review issue." >&2
            fi
        fi

        # Stdout для Claude Code — маркер SKIPPED
        echo "SKIPPED"
        exit 0  # не блокируем pipeline
        ;;
    *)
        echo "# /codex-review" >&2
        echo "" >&2
        echo "ERROR: Codex exit=$exit_code" >&2
        cat "$tmp_err" >&2
        echo "SKIPPED"
        exit 0
        ;;
esac
