# Port follow-ups

P2 findings and other deferred items from the port run (docs/port/PLAN.md §9). One entry per item, ready to become an issue text. The owner decides which become issues.

<!-- Format:
## <short title>
- Source: <phase, reviewer, PR>
- Severity: P2
- What: <one paragraph>
- Proposed fix: <one paragraph>
-->

## Worktrees and test projects live inside the main checkout
- Source: P0, reliability review of PR #322
- Severity: P2
- What: the driver puts phase worktrees in `.port-run/wt/pN` and tests put temp projects in `.port-run/tmp`, both under the main checkout. Claude Code loads CLAUDE.md files from parent directories, so an agent in a worktree also reads the main checkout's CLAUDE.md, which may be on another branch. The same holds for the temp projects in tests.
- Proposed fix: make the worktree and temp roots configurable in `phases.json`, default outside the checkout, and check at start that no CLAUDE.md or AGENTS.md exists above the chosen root.

## The OAuth token is visible to the agent
- Source: P0, reliability review of PR #322
- Severity: P2
- What: `CLAUDE_CODE_OAUTH_TOKEN` is exported into the agent's environment, so any allowed `python3` or `bash tests/*` call can read it.
- Proposed fix: none known on 2.1.283 that keeps isolated auth; revisit if Claude Code offers a credential helper for isolated config dirs.

## Main-checkout drift check blocks on the owner's own edits
- Source: P0, reliability review of PR #322
- Severity: P2
- What: `finish` blocks when `git status --porcelain` of the main checkout is not empty, including edits the owner made during the run. It also does not see writes into ignored paths.
- Proposed fix: snapshot the main checkout status at start and compare, instead of requiring it empty.

## No-plugin test is not wired and its hook check is indirect
- Source: P0, reliability review of PR #322
- Severity: P2
- What: `tests/plugin-scope/no-plugin-no-writes.sh` runs neither in CI nor in the phase DoD (it needs the subscription token). "Hook did not fire in B" is inferred from a successful commit; there is no control that the hook blocks the same commit in A, so a model that refuses the command looks the same as a hook.
- Proposed fix: add the A-side control (the hook denies `bad subject` in A) and add the test to the local acceptance list in DEPLOY.md once P3 lands.

## P0 DoD tests that need Claude were not executed
- Source: P0, reliability review of PR #322
- Severity: P2
- What: PLAN §3 P0 DoD says the tests exit 0. The tests that start Claude exit 77 (SKIPPED) until the owner stores the subscription token, so they were not executed for P0.
- Proposed fix: run them once the token is in the Keychain and record the result in the P1 PR.

## Ledger evidence is recorded, not executed
- Source: P0, reliability review of PR #322
- Severity: P2
- What: `ledger-check.sh` requires `capability`, `entry_point` and `evidence` to be non-empty when a path leaves the tree; it does not run the evidence command.
- Proposed fix: in P9, run each distinct evidence command of removed rows as part of the P9 DoD.

## No review session or WIP branch in the driver
- Source: P0, adversarial and reliability reviews of PR #322
- Severity: P2
- What: PLAN §10 v1 described a separate review session and a `wip/pN` commit on resume. The driver runs critics inside the phase session and never deletes a worktree instead; PR-level review happens on the draft PR.
- Proposed fix: none unless the in-session critics prove insufficient on P1–P2.

## Docs: skeleton DEPLOY.md and pasted reports
- Source: P0, docs review of PR #322
- Severity: P2
- What: DEPLOY.md lists `setup/harness` commands that do not exist until P2–P3 (it is marked skeleton). PORT-MAP.md and JEV-DESIGN.md are agent reports committed verbatim, without a heading that says what they are and who reads them; PLAN cites their line numbers, so only their links were rewritten.
- Proposed fix: fill DEPLOY.md in P3; in P9 give both files a short preface and convert PLAN's line citations to anchors.
