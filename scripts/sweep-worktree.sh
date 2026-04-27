#!/usr/bin/env bash
# sweep-worktree.sh — per-ticket git worktree isolation for Autonomous Backlog Sweep
# ADR-0017: docs/decisions/0017-sweep-worktree-isolation.md
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(git rev-parse --show-toplevel)"

_sanitize_slug() {
    local raw="$1"
    local slug
    slug=$(printf '%s' "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g; s/-\+/-/g' \
        | cut -c1-40 \
        | sed 's/^-*//; s/-*$//')
    if [[ -z "$slug" ]]; then
        echo "error: slug is empty after sanitization (input: '$raw')" >&2
        exit 1
    fi
    printf '%s' "$slug"
}

_validate_ticket_number() {
    local n="$1"
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo "error: ticket number must be numeric, got: '$n'" >&2
        exit 1
    fi
}

cmd_create() {
    local n="$1"
    local raw_slug="$2"
    _validate_ticket_number "$n"
    local slug
    slug=$(_sanitize_slug "$raw_slug")
    local branch="sweep/${n}-${slug}"
    local wt_path="${REPO_ROOT}/.sweep/${n}"

    git fetch origin main || {
        echo "error: git fetch origin main failed — aborting (stale main risks silent corruption)" >&2
        exit 1
    }

    git worktree add "${wt_path}" -b "${branch}" origin/main || {
        echo "error: could not create worktree at '${wt_path}' on branch '${branch}'" >&2
        echo "hint: if a prior run crashed, clean up with: ./scripts/sweep-worktree.sh cleanup ${n}" >&2
        exit 1
    }

    printf '%s\n' "${wt_path}"
}

cmd_cleanup() {
    local n="$1"
    _validate_ticket_number "$n"
    local wt_path="${REPO_ROOT}/.sweep/${n}"
    local branch=""

    if [[ -d "${wt_path}" ]]; then
        branch=$(git -C "${wt_path}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

        # stage untracked files so stash create captures full working state
        git -C "${wt_path}" add -A 2>/dev/null || true
        local wip
        wip=$(git -C "${wt_path}" stash create 2>/dev/null || true)
        if [[ -n "${wip}" ]]; then
            git update-ref "refs/sweep-abandoned/${n}" "${wip}"
            printf 'WIP preserved at refs/sweep-abandoned/%s\nRecover via: git stash apply refs/sweep-abandoned/%s\n' \
                "${n}" "${n}" >&2
        fi

        git worktree remove --force "${wt_path}" || true
    fi

    # branch may exist even if worktree is already gone (partial prior cleanup)
    if [[ -z "${branch}" ]]; then
        # prune stale worktree metadata so git branch --list reflects actual state
        git worktree prune 2>/dev/null || true
        # strip leading space, *, and + (+ marks worktrees that were prunable)
        branch=$(git branch --list "sweep/${n}-*" 2>/dev/null | head -1 | tr -d ' *+' || true)
    fi

    if [[ -n "${branch}" ]]; then
        git branch -D "${branch}" || true
    fi
}

_usage() {
    printf 'Usage:\n' >&2
    printf '  %s create <ticket-number> <slug>   create worktree at .sweep/<n>/, branch sweep/<n>-<slug>\n' "$0" >&2
    printf '  %s cleanup <ticket-number>          remove worktree and branch; preserve WIP to refs/sweep-abandoned/<n>\n' "$0" >&2
    exit 1
}

[[ $# -lt 1 ]] && _usage

case "$1" in
    create)
        [[ $# -ne 3 ]] && { echo "error: create requires <ticket-number> and <slug>" >&2; _usage; }
        cmd_create "$2" "$3"
        ;;
    cleanup)
        [[ $# -ne 2 ]] && { echo "error: cleanup requires <ticket-number>" >&2; _usage; }
        cmd_cleanup "$2"
        ;;
    *)
        echo "error: unknown subcommand '$1'" >&2
        _usage
        ;;
esac
