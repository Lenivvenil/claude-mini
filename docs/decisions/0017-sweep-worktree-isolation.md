# 0017. Sweep per-ticket worktree isolation and abandoned-work contract

* Status: accepted
* Date: 2026-04-27
* Deciders: Lenivvenil
* Tags: pipeline, sweep, git, tooling

## Context and Problem Statement

Epic #44 (Autonomous Backlog Sweep) will process multiple GitHub issues sequentially and eventually in parallel. The current `/implement` branch guard operates on a single working tree: when ticket N finishes, ticket N+1 inherits the same branch, staged files, and uncommitted changes. This is safe for operator-driven single-ticket work but breaks entirely when a runner processes tickets autonomously — ticket N+1's PR silently carries ticket N's diff. Phase-0 (#80) fixes this by establishing the isolation mechanism and the contract for what happens to uncommitted work when a ticket exits via `needs-human`, before Epic #44's runner starts programming against it.

## Decision Drivers

* **Parallel-ticket capability** — the acceptance criteria for #80 explicitly require two concurrent worktrees; any mechanism based on a single shared HEAD is disqualified.
* **Data-loss safety on `needs-human` exit** — when an agent gives up and hands back control, the operator needs to see what the agent was doing. Silently discarding that work makes the `needs-human` signal less useful, not safer. Per `docs/principles.md §3`, destructive operations require explicit design, not incidental behaviour.
* **Inter-pipeline contract stability** — `scripts/sweep-worktree.sh` becomes a public surface that Epic #44's runner will call. The subcommand names, directory layout (`.sweep/<n>/`), and branch naming (`sweep/<n>-<slug>`) form a breaking-change boundary.
* **Cleanup auditability** — the operator must be able to see what worktrees are currently open without consulting logs. `git worktree list` provides this for free.
* **Operator experience stays in the pipeline** — recovery from stuck tickets should work through the same interface as the rest of the pipeline (Claude Code skills, GitHub issues), not through bare shell scripts. This ADR establishes the data contract; Epic #44 owns the UX surface.

## Considered Options

* **Option A — `git worktree` per ticket** (chosen)
* **Option B — `git stash` + branch reset in the main working tree**
* **Option C — in-place `git reset --hard origin/main && git clean -fdx`**

## Decision Outcome

Chosen option: **Option A — `git worktree` per ticket**, with data-loss policy **(d) lightweight ref via `git stash create`**, because it is the only option that satisfies the parallel-ticket driver without a shared-state footgun, and because it stores abandoned work in a non-intrusive, recoverable form that does not pollute the branch list.

`scripts/sweep-worktree.sh` exposes exactly two subcommands:

```
create <ticket-number> <slug>
  git fetch origin main
  git worktree add .sweep/<n> -b sweep/<n>-<slug> origin/main
  prints path to stdout

cleanup <ticket-number>
  WIP=$(git -C .sweep/<n> stash create 2>/dev/null)
  [ -n "$WIP" ] && git update-ref refs/sweep-abandoned/<n> "$WIP"
  git worktree remove --force .sweep/<n>
  git branch -D sweep/<n>-<slug>
  exits 0 if worktree already gone (idempotent)
  prints recovery command to stderr if WIP was saved
```

Slug is sanitised to lowercase alphanumeric + hyphen, truncated to 40 chars.

Per `docs/principles.md §3` ("автоматизировать только низкорискованное"): the cleanup is deliberately explicit — the runner calls `cleanup`, it does not happen automatically on process exit. This keeps the destructive operation visible and auditable.

**Reversibility:** reversible door. The script is a new file with no existing callers. Reverting requires updating Epic #44's runner to use a different isolation mechanism — a one-sprint migration once #44 ships, trivial before it does.

### Positive Consequences

* Two tickets can run simultaneously and never see each other's files — not through configuration, but because they physically live in different directories with separate indexes.
* `git worktree list` gives an instant, authoritative snapshot of what is open and on which branch. No logs, no state files.
* When an agent stops with `needs-human`, its in-progress work is preserved and reproducible: `git stash apply refs/sweep-abandoned/<n>` restores the exact working tree state.

### Negative Consequences

* The runner cannot simply start working on a ticket. It must call `sweep-worktree.sh create`, receive the path, and change directory into it. This is a contract that must be maintained and tested independently.
* Every abandoned ticket leaves data in `refs/sweep-abandoned/`. Git will never delete these automatically — they block garbage collection. The retention policy for `refs/sweep-abandoned/` is **not defined in this ADR** and is deferred as a follow-up (see Out of Scope).
* Abandoned work is invisible by default — refs do not appear in `git branch`, `git log`, or any standard UI. The operator only discovers them if Epic #44's runner posts the recovery command to the GitHub issue. If the runner omits this step, the data exists but is unfindable. This responsibility falls entirely on Epic #44's design.
* `git stash create` on a clean worktree (no changes) returns an empty string. The cleanup script must check for this explicitly — an empty `git update-ref` call exits with an error and leaves the worktree un-removed.

## Pros and Cons of the Options

### Option A — `git worktree` per ticket

* Good, because physical directory separation makes cross-contamination impossible without any runtime coordination.
* Good, because parallel execution requires no locking — two worktrees use different paths and different branches.
* Good, because `git worktree list` provides free auditability.
* Bad, because it adds a mandatory script dependency that every caller must respect.
* Bad, because cleanup requires an explicit policy for uncommitted work — there is no safe default.

### Option B — `git stash` + branch reset

* Good, because no new directories or scripts are needed.
* Good, because any git user understands it without reading documentation.
* Bad, because stash is a single global stack — parallel tickets are impossible without a custom stash-management layer.
* Bad, because a failed stash-pop from ticket N leaves a dirty working tree for ticket N+1, and the runner has no reliable way to detect this.

### Option C — in-place `git reset --hard origin/main && git clean -fdx`

* Good, because the mental model is maximally simple — two commands, no abstractions, no dependencies.
* Good, because no script is needed; the runner issues the commands directly.
* Bad, because `git clean -fdx` discards all untracked files without warning or recovery. Any file the operator placed in the tree and forgot to gitignore is permanently gone.
* Bad, because one HEAD means serial-only execution forever. Every reset also flushes editor state, LSP caches, and open buffers — collateral damage that compounds over long sweep runs.

## Confirmation

After `/implement` — manual test with two concurrent worktrees:
1. `create 101 foo` and `create 102 bar` — both show clean `git status`, `git worktree list` shows two entries on separate branches.
2. Stage an uncommitted file in `.sweep/101/`, run `cleanup 101` — `refs/sweep-abandoned/101` is created, recovery command printed to stderr, directory removed.
3. `cleanup 999` (non-existent) — exits 0.
4. `create 101 foo` on a clean worktree, `cleanup 101` — no ref created, clean exit.

Before Epic #44 Phase-1 merge: integration test that the runner calls `create`/`cleanup` correctly and that the recovery command appears in the GitHub issue comment.

## Re-visit Trigger

* Epic #44 runner adopts a different mechanism for preserving abandoned work (e.g. direct commit to a recovery branch), making `refs/sweep-abandoned/` redundant — consolidate the two mechanisms.
* More than 50 `refs/sweep-abandoned/` refs accumulate without cleanup and GC pressure becomes measurable — define a retention policy.

## Out of Scope

**Operator-facing recovery and visibility tooling** — how `needs-human` outcomes are surfaced to the operator (GitHub issue comment, project board status, `/resume` skill) is owned by Epic #44, not this ADR. This ADR guarantees the data is recoverable; the UX surface is Epic #44's contract with the operator.

**Retention policy for `refs/sweep-abandoned/`** — `git for-each-ref refs/sweep-abandoned/` enumeration and automated cleanup are deferred to a follow-up issue.

**Sweep domain modelling** — `Sweep`, `SweepTicket`, and `needs-human` as domain concepts, and their relationship to `FeatureRun` invariants (advisor ×2, operator as sole decision-maker), are deliberately not modelled here. A `domain-researcher` interview is required before Epic #44 Phase-1 begins. Until that interview lands, no Phase-1 work on the sweep runner may start.

## Links

* Implements: issue #80 (sweep: per-ticket git worktree isolation, Phase-0 for #44)
* Related: Epic #44 (Autonomous Backlog Sweep)
* Related: ADR-0009 (feature-branch-pr-flow) — branch-per-ticket discipline this script extends
