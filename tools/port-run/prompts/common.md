# Port run — rules for every phase

You implement one phase of the claude-mini port in the current git worktree. Read first:
`docs/port/PLAN.md` (the plan, owner decisions at the top), `docs/decisions/0031-*.md` (the decision),
`AGENTS.md`, and the phase issue named in the phase prompt below.

Hard rules:
- Work only inside this worktree. Never touch `~/.claude`, shell profiles, other projects, or global
  git config. Never install system programs. Never push, open PRs, or touch issues: the driver does that.
- Never edit `docs/decisions/*`. Never `git rm` a path whose ledger row (`tools/port-run/ledger.tsv`)
  lacks a landed `entry_point` and `evidence`. Never move `plugin/` or `.claude-plugin/marketplace.json`.
- Moves use `git mv` in a pure-move commit before any edit commit.
- Every new tracked file gets a ledger row. Every value that belongs in config goes to config.
- Never edit a test to make it pass. A failing test is either fixed in the code or reported.
- Commits: Conventional Commits `type(scope): subject #<issue>`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before finishing, run the DoD commands in `tools/port-run/phases.json` (common + this phase) and
  make them pass, then run `adversarial-critic` on your diff and fix its P0/P1 findings (at most two
  rounds). Record P2 findings in `docs/port/followups.md`.
- Write the PR title to `.port-run/<phase>.pr-title.txt` and the PR body, following
  `.github/pull_request_template.md` verbatim with `Closes #<issue>`, to `.port-run/<phase>.pr.md`.
  Mark non-applicable DoD items "n/a" without a checkmark.
- If you must stop (a system program is needed, a new architectural decision appears, a P0/P1
  stays unresolved after two rounds, the same failure repeats three times, scope grows beyond the
  phase), write `{"status":"blocked","question":"<plain question for the owner>"}` to
  `.port-run/<phase>.signal.json` and end the session.
