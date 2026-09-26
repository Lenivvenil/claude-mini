#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq filters are single-quoted on purpose; values go in via --arg
# driver.sh — runs one port phase at a time in its own worktree (docs/port/PLAN.md §8–§10, #311).
#
#   driver.sh status              show every phase state
#   driver.sh start <pN>          fetch, check the predecessor, create the worktree, run the phase
#   driver.sh resume <pN>         replay the full launch with --resume <session id>
#
# State: .port-run/<pN>.json (tmp+mv). Lock: .port-run/lock (PID, checked for liveness).
# The prompt is prompts/common.md + the phase issue text (fetched by the driver; the agent has no
# gh) + optional prompts/<pN>.md. The agent writes its handoff files inside its worktree:
#   <wt>/.port-run/<pN>.signal.json   {"status":"done"} or {"status":"blocked","question":"…"}
#   <wt>/.port-run/<pN>.pr-title.txt, <wt>/.port-run/<pN>.pr.md
# Only a "done" signal, an unchanged watch list, clean trees and a green DoD lead to push + PR.
# The driver never merges and does not review: reviews run on the PR (docs/port/PLAN.md §9).
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
branch_of() { echo "port/$1-$(phase_cfg "$1" .slug)"; }

state_file() { echo "$RUN/$1.json"; }
state_get() { [ -f "$(state_file "$1")" ] && jq -r "$2 // empty" "$(state_file "$1")"; }
state_set() {  # state_set <pN> <jq-filter> [--arg k v ...]; fails loudly
    local f; f=$(state_file "$1"); shift
    local filter="$1"; shift
    [ -f "$f" ] || echo '{}' > "$f"
    { jq "$@" "$filter" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; } || die "cannot write state $f"
}
block() {  # block <pN> <question>
    state_set "$1" '.status = "blocked" | .question = $q' --arg q "$2"
    die "$1 blocked: $2"
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

# Files outside the project that no phase may change (PLAN §8, watch list).
watch_hash() {
    local f
    for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
             "$HOME/.gitconfig" "$HOME/.config/git/ignore" "$HOME/.claude/settings.json" \
             "$HOME/.claude/plugins/installed_plugins.json" "$HOME/.claude/plugins/known_marketplaces.json"; do
        if [ -e "$f" ]; then printf '%s %s\n' "$(shasum -a 256 < "$f" | cut -c1-64)" "$f"; else printf 'absent %s\n' "$f"; fi
    done
}
require_tools() {  # everything the run needs, checked before anything is created
    local t
    for t in git gh jq claude timeout uuidgen shasum; do
        command -v "$t" >/dev/null 2>&1 || die "missing program: $t"
    done
    # shellcheck source=/dev/null  # helper checked on its own
    . "$REPO/tools/port-run/lib/isolated-claude.sh"
    iso_require_token
}
# Branches and tags on origin, main excluded (the owner merges there while phases run).
remote_refs() { git -C "$REPO" ls-remote -q origin 'refs/heads/*' 'refs/tags/*' | grep -v $'\trefs/heads/main$' | sort; }
# A ref that is new or moved since the snapshot (deletions are the owner's cleanup).
remote_new() { comm -13 "$RUN/$1.remote" <(remote_refs); }

watch_same() { [ "$(watch_hash)" = "$(cat "$RUN/$1.watch")" ]; }

compose_prompt() {  # compose_prompt <pN> <out-file>
    local id="$1" out="$2" issue
    issue=$(phase_cfg "$id" .issue)
    {
        cat "$REPO/tools/port-run/prompts/common.md" || return 1
        printf '\n# This phase: %s (issue #%s)\n\n' "$id" "$issue"
        gh issue view "$issue" --json title,body -q '"## " + .title + "\n\n" + .body' || return 1
        if [ -f "$REPO/tools/port-run/prompts/$id.md" ]; then echo; cat "$REPO/tools/port-run/prompts/$id.md"; fi
        printf '\nHandoff files for this phase: .port-run/%s.signal.json, .port-run/%s.pr-title.txt, .port-run/%s.pr.md (inside this worktree).\n' "$id" "$id" "$id"
    } > "$out"
}

launch() {  # launch <pN> <worktree> <session-id> [--resume]
    local id="$1" wt="$2" sid="$3" mode="${4:-}"
    local allowed disallowed
    allowed=$(jq -r '.common.allowed_tools | join(",")' "$PHASES")
    disallowed=$(jq -r '.common.disallowed_tools | join(",")' "$PHASES")
    # shellcheck disable=SC2054  # commas inside --setting-sources and JSON are literal
    local args=(-p "$(cat "$RUN/$id.prompt.md")"
        --output-format json --permission-mode acceptEdits --permission-prompts none
        --setting-sources project,local --strict-mcp-config --mcp-config '{"mcpServers":{}}'
        --allowedTools "$allowed" --disallowedTools "$disallowed")
    if [ "$mode" = "--resume" ]; then args+=(--resume "$sid"); else args+=(--session-id "$sid"); fi
    mkdir -p "$wt/.port-run" "$RUN/agent-home"
    rm -f "$wt/.port-run/$id.signal.json"
    # The agent gets a throw-away HOME: no shell profile, git or gh credentials of the owner.
    # GIT_CONFIG_NOSYSTEM drops the system gitconfig too (on macOS it sets the keychain
    # credential helper). Only the git identity is copied, so commits carry the owner's name.
    local gitcfg="$RUN/agent-home/.gitconfig"
    : > "$gitcfg"
    git config -f "$gitcfg" user.name "$(git -C "$REPO" config user.name)"
    git config -f "$gitcfg" user.email "$(git -C "$REPO" config user.email)"
    state_set "$id" '.status = "running" | .updated = (now | todate)'
    (cd "$wt" && HOME="$RUN/agent-home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$gitcfg" CLAUDE_CONFIG_DIR="$RUN/claude-config" \
        timeout "$(cfg .timeout_s)" claude "${args[@]}") > "$RUN/$id.out.json" 2> "$RUN/$id.err"
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

finish() {  # finish <pN> <worktree> <session-rc>: signal, boundary, DoD, push, PR (never merge)
    local id="$1" wt="$2" rc="$3" branch sig; branch=$(state_get "$id" .branch)
    sig="$wt/.port-run/$id.signal.json"
    [ -f "$sig" ] || { state_set "$id" '.status = "interrupted"'; die "$id: no signal from the agent (session exit $rc); use resume"; }
    case "$(jq -r .status "$sig" 2>/dev/null)" in
        done) ;;
        blocked) block "$id" "$(jq -r '.question // "no question given"' "$sig")" ;;
        *) state_set "$id" '.status = "interrupted"'; die "$id: unreadable signal file; use resume" ;;
    esac
    watch_same "$id" || block "$id" "files outside the project changed during the session (watch list)"
    [ -z "$(git -C "$REPO" status --porcelain)" ] || block "$id" "the main checkout changed during the session"
    [ -z "$(git -C "$wt" status --porcelain)" ] || block "$id" "uncommitted work left in the worktree"
    run_dod "$id" "$wt" || { state_set "$id" '.status = "dod-failed"'; die "$id: DoD failed"; }
    watch_same "$id" || block "$id" "files outside the project changed during the DoD run (watch list)"
    local moved; moved=$(remote_new "$id") || die "ls-remote failed"
    [ -z "$moved" ] || block "$id" "refs on origin created or moved during the session: $(printf '%s' "$moved" | cut -f2 | paste -sd' ' -)"
    local body="$wt/.port-run/$id.pr.md" title="$wt/.port-run/$id.pr-title.txt"
    local pr; pr=$(gh pr list --head "$branch" --state open --json number -q '.[0].number') || die "gh pr list failed"
    [ -n "$pr" ] || { [ -s "$body" ] && [ -s "$title" ]; } || block "$id" "the agent did not write the PR title and body"
    git -C "$wt" push -q -u origin "$branch" || die "push failed"
    if [ -z "$pr" ]; then
        local url
        url=$(gh pr create --draft --head "$branch" --base "$(state_get "$id" .base_ref)" \
            --title "$(head -1 "$title")" --body-file "$body") || die "gh pr create failed"
        pr=${url##*/}
    fi
    [[ "$pr" =~ ^[0-9]+$ ]] || die "could not determine the PR number (got '$pr')"
    state_set "$id" '.status = "awaiting-merge" | .pr = ($pr | tonumber) | .pushed_sha = $sha' \
        --arg pr "$pr" --arg sha "$(git -C "$wt" rev-parse HEAD)"
    echo "driver: $id → draft PR #$pr; reviews run on the PR, the owner merges"
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
    # Base: main when the predecessor's PR is merged; its branch when stacking (PORT_STACK=1).
    # The predecessor is found by its branch name, so phases done by hand count too.
    local prev base_ref base_sha; prev=$(prev_phase "$id")
    base_ref=$(cfg .base_branch)
    if [ -n "$prev" ]; then
        local pbranch pstate; pbranch=$(branch_of "$prev")
        pstate=$(gh pr list --head "$pbranch" --state all --json state -q '.[0].state') || die "gh pr list failed"
        if [ "$pstate" != "MERGED" ]; then
            [ "${PORT_STACK:-0}" = "1" ] || die "$prev ($pbranch, PR state '${pstate:-none}') is not merged; set PORT_STACK=1 to stack on it"
            git -C "$REPO" rev-parse -q --verify "origin/$pbranch" >/dev/null || die "origin/$pbranch does not exist"
            base_ref=$pbranch
        fi
    fi
    base_sha=$(git -C "$REPO" rev-parse "origin/$base_ref") || die "cannot resolve origin/$base_ref"
    local branch wt="$RUN/wt/$id" sid
    branch=$(branch_of "$id")
    [ -e "$wt" ] && die "worktree $wt exists; use resume"
    require_tools
    compose_prompt "$id" "$RUN/$id.prompt.md" || die "cannot compose the prompt for $id (issue text)"
    watch_hash > "$RUN/$id.watch"
    remote_refs > "$RUN/$id.remote" || die "ls-remote failed"
    git -C "$REPO" worktree add -q "$wt" -b "$branch" "$base_sha" || die "worktree add failed"
    sid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    state_set "$id" '. + {issue: $issue, branch: $b, base_ref: $br, base_sha: $bs, worktree: $wt, session_id: $sid, status: "starting"}' \
        --argjson issue "$(phase_cfg "$id" .issue)" --arg b "$branch" --arg br "$base_ref" --arg bs "$base_sha" --arg wt "$wt" --arg sid "$sid"
    local rc=0; launch "$id" "$wt" "$sid" || rc=$?
    finish "$id" "$wt" "$rc"
}

cmd_resume() {
    local id="$1" wt sid
    lock
    require_tools
    wt=$(state_get "$id" .worktree); sid=$(state_get "$id" .session_id)
    { [ -n "$wt" ] && [ -n "$sid" ] && [ -f "$RUN/$id.prompt.md" ] && [ -f "$RUN/$id.watch" ]; } \
        || die "$id has no recorded worktree, session, prompt or watch snapshot"
    remote_refs > "$RUN/$id.remote" || die "ls-remote failed"
    local rc=0; launch "$id" "$wt" "$sid" --resume || rc=$?
    finish "$id" "$wt" "$rc"
}

case "${1:-}" in
    status) cmd_status ;;
    start) [ -n "${2:-}" ] || die "usage: driver.sh start <pN>"; cmd_start "$2" ;;
    resume) [ -n "${2:-}" ] || die "usage: driver.sh resume <pN>"; cmd_resume "$2" ;;
    *) echo "usage: driver.sh status | start <pN> | resume <pN>" >&2; exit 2 ;;
esac
