#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq filters are single-quoted on purpose; values go in via --arg
# driver.sh — runs one port phase at a time in its own worktree (docs/port/PLAN.md §8–§10, #311).
#
#   driver.sh status              show every phase state
#   driver.sh start <pN>          fetch, check the predecessor, create the worktree, run the phase
#   driver.sh resume <pN>         replay the full launch with --resume <session id>
#
# State: .port-run/<pN>.json (tmp+mv). Lock: .port-run/lock (PID, checked for liveness).
# The agent never pushes or opens PRs; the driver does, after its own DoD run. The agent signals
# "blocked" by writing {"status":"blocked","question":...} to .port-run/<pN>.signal.json.
# Isolated Claude config: .port-run/claude-config, authenticated by the subscription token
# (tools/port-run/lib/isolated-claude.sh). Wall-clock cap: timeout_s in phases.json.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$REPO/.port-run"
PHASES="$REPO/tools/port-run/phases.json"
mkdir -p "$RUN"

die() { echo "driver: $*" >&2; exit 1; }
cfg() { jq -r "$1" "$PHASES"; }
phase_cfg() { jq -r --arg id "$1" ".phases[] | select(.id == \$id) | $2" "$PHASES"; }

state_file() { echo "$RUN/$1.json"; }
state_get() { [ -f "$(state_file "$1")" ] && jq -r "$2 // empty" "$(state_file "$1")"; }
state_set() {  # state_set <pN> <jq-filter> [--arg k v ...]
    local f; f=$(state_file "$1"); shift
    local filter="$1"; shift
    [ -f "$f" ] || echo '{}' > "$f"
    jq "$@" "$filter" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

lock() {
    if [ -f "$RUN/lock" ]; then
        local pid; pid=$(cat "$RUN/lock")
        if kill -0 "$pid" 2>/dev/null; then die "another driver is running (pid $pid)"; fi
        echo "driver: removing stale lock (pid $pid)" >&2
    fi
    echo $$ > "$RUN/lock"
    trap 'rm -f "$RUN/lock"' EXIT
}

prev_phase() { jq -r --arg id "$1" '[.phases[].id] as $ids | ($ids | index($id)) as $i | if $i > 0 then $ids[$i-1] else "" end' "$PHASES"; }

launch() {  # launch <pN> <worktree> <session-id> [--resume]
    local id="$1" wt="$2" sid="$3" mode="${4:-}"
    local prompt="$REPO/tools/port-run/prompts/$id.md"
    [ -f "$prompt" ] || die "no prompt file $prompt"
    # shellcheck source=/dev/null  # helper checked on its own
    . "$REPO/tools/port-run/lib/isolated-claude.sh"
    iso_require_token
    local allowed disallowed
    allowed=$(jq -r '.common.allowed_tools | join(",")' "$PHASES")
    disallowed=$(jq -r '.common.disallowed_tools | join(",")' "$PHASES")
    # shellcheck disable=SC2054  # commas inside --setting-sources and JSON are literal
    local args=(-p "$(cat "$REPO/tools/port-run/prompts/common.md" "$prompt")"
        --output-format json --permission-mode acceptEdits --permission-prompts none
        --setting-sources project,local --strict-mcp-config --mcp-config '{"mcpServers":{}}'
        --allowedTools "$allowed" --disallowedTools "$disallowed")
    if [ "$mode" = "--resume" ]; then args+=(--resume "$sid"); else args+=(--session-id "$sid"); fi
    state_set "$id" '.status = "running" | .updated = (now | todate)'
    (cd "$wt" && CLAUDE_CONFIG_DIR="$RUN/claude-config" timeout "$(cfg .timeout_s)" claude "${args[@]}") \
        > "$RUN/$id.out.json" 2> "$RUN/$id.err"
    local rc=$?
    state_set "$id" '.last_exit = $rc' --argjson rc "$rc"
    return "$rc"
}

run_dod() {  # run_dod <pN> <worktree>
    local id="$1" wt="$2" fail=0 cmd
    : > "$RUN/$id.dod.log"
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        echo "### $cmd" >> "$RUN/$id.dod.log"
        if (cd "$wt" && bash -c "$cmd") >> "$RUN/$id.dod.log" 2>&1; then
            echo "  dod ok    $cmd"
        else
            echo "  dod FAIL  $cmd (see .port-run/$id.dod.log)"; fail=1
        fi
    done < <(jq -r --arg id "$id" '(.common.dod + ((.phases[] | select(.id == $id) | .dod) // []))[]' "$PHASES")
    return "$fail"
}

check_signal() {  # returns 1 when the agent asked to stop
    local sig="$RUN/$1.signal.json"
    if [ -f "$sig" ] && [ "$(jq -r .status "$sig")" = "blocked" ]; then
        state_set "$1" '.status = "blocked" | .question = $q' --arg q "$(jq -r .question "$sig")"
        echo "driver: $1 blocked: $(jq -r .question "$sig")"; return 1
    fi
}

finish() {  # finish <pN> <worktree>: DoD, boundary, push, PR (never merge)
    local id="$1" wt="$2" branch; branch=$(state_get "$id" .branch)
    check_signal "$id" || return 1
    [ -z "$(git -C "$REPO" status --porcelain)" ] || { state_set "$id" '.status = "blocked" | .question = "main checkout is dirty after the session"'; die "boundary: main checkout changed"; }
    [ -z "$(git -C "$wt" status --porcelain)" ] || { state_set "$id" '.status = "blocked" | .question = "uncommitted work left in the worktree"'; die "$id: uncommitted work in $wt"; }
    run_dod "$id" "$wt" || { state_set "$id" '.status = "dod-failed"'; die "$id: DoD failed"; }
    git -C "$wt" push -q -u origin "$branch" || die "push failed"
    local pr; pr=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null)
    if [ -z "$pr" ]; then
        local body="$RUN/$id.pr.md"
        [ -f "$body" ] || die "$id: agent did not write the PR body to .port-run/$id.pr.md"
        pr=$(gh pr create --head "$branch" --base "$(state_get "$id" .base_ref)" \
            --title "$(head -1 "$RUN/$id.pr-title.txt" 2>/dev/null || echo "port: $id")" \
            --body-file "$body" | sed 's#.*/##')
    fi
    state_set "$id" '.status = "awaiting-merge" | .pr = ($pr | tonumber) | .reviewed_sha = $sha' \
        --arg pr "$pr" --arg sha "$(git -C "$wt" rev-parse HEAD)"
    echo "driver: $id → PR #$pr, awaiting the owner's merge"
}

cmd_status() {
    local id
    for id in $(jq -r '.phases[].id' "$PHASES"); do
        printf '%-3s %-14s pr=%-5s %s\n' "$id" "$(state_get "$id" .status || true)" \
            "$(state_get "$id" .pr || true)" "$(state_get "$id" .question || true)"
    done
}

cmd_start() {
    local id="$1"
    [ "$(phase_cfg "$id" .id)" = "$id" ] || die "unknown phase $id"
    [ "$(phase_cfg "$id" 'if has("driver") then .driver else true end')" = "true" ] || die "$id is not driven (done by hand)"
    lock
    git -C "$REPO" fetch -q origin || die "fetch failed"
    # Base: the merged predecessor on main, or (stacking) the predecessor's branch head.
    local prev base_ref base_sha; prev=$(prev_phase "$id")
    base_ref=$(cfg .base_branch)
    if [ -n "$prev" ]; then
        local ppr; ppr=$(state_get "$prev" .pr)
        local pstate; pstate=$( [ -n "$ppr" ] && gh pr view "$ppr" --json state -q .state 2>/dev/null )
        if [ "$pstate" != "MERGED" ]; then
            [ "${PORT_STACK:-0}" = "1" ] || die "$prev (PR ${ppr:-none}) is not merged; set PORT_STACK=1 to stack on its branch"
            base_ref=$(state_get "$prev" .branch)
            [ -n "$base_ref" ] || die "no branch recorded for $prev"
        fi
    fi
    base_sha=$(git -C "$REPO" rev-parse "origin/$base_ref") || die "cannot resolve origin/$base_ref"
    local branch wt="$RUN/wt/$id" sid
    branch="port/$id-$(phase_cfg "$id" .slug)"
    [ -e "$wt" ] && die "worktree $wt exists; use resume"
    git -C "$REPO" worktree add -q "$wt" -b "$branch" "$base_sha" || die "worktree add failed"
    sid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    state_set "$id" '. + {issue: $issue, branch: $b, base_ref: $br, base_sha: $bs, worktree: $wt, session_id: $sid, status: "starting"}' \
        --argjson issue "$(phase_cfg "$id" .issue)" --arg b "$branch" --arg br "$base_ref" --arg bs "$base_sha" --arg wt "$wt" --arg sid "$sid"
    launch "$id" "$wt" "$sid" || echo "driver: session exited non-zero; checking state"
    finish "$id" "$wt"
}

cmd_resume() {
    local id="$1" wt sid
    lock
    wt=$(state_get "$id" .worktree); sid=$(state_get "$id" .session_id)
    [ -n "$wt" ] && [ -n "$sid" ] || die "$id has no recorded worktree/session"
    rm -f "$RUN/$id.signal.json"
    launch "$id" "$wt" "$sid" --resume || echo "driver: session exited non-zero; checking state"
    finish "$id" "$wt"
}

case "${1:-}" in
    status) cmd_status ;;
    start) [ -n "${2:-}" ] || die "usage: driver.sh start <pN>"; cmd_start "$2" ;;
    resume) [ -n "${2:-}" ] || die "usage: driver.sh resume <pN>"; cmd_resume "$2" ;;
    *) echo "usage: driver.sh status | start <pN> | resume <pN>" >&2; exit 2 ;;
esac
