---
type: llm
weight: 3
---

PASS if the review states that install.sh still uses `git rev-parse --git-dir` while check.sh now reads from `--git-common-dir`, so when install.sh runs from a linked worktree the hook lands in the worktree's private git dir (.git/worktrees/<name>/hooks) — where git never executes hooks and where check.sh does not look — and the repo silently stays ungoverned.
FAIL if the review does not connect the installer path to the new reader path for linked worktrees, or only praises the change.
