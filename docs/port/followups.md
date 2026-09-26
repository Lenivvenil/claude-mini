# Port follow-ups

P2 findings and other deferred items from the port run (docs/port/PLAN.md §9). One entry per item, ready to become an issue text. The owner decides which become issues.

<!-- Format:
## <short title>
- Source: <phase, reviewer, PR>
- Severity: P2
- What: <one paragraph>
- Proposed fix: <one paragraph>
-->

## Test projects live inside the repository
- Source: P0, reliability review of PR #322
- Severity: P2
- What: tests that start Claude create temp projects under `.port-run/tmp` inside this repository. Claude Code loads CLAUDE.md files from parent directories, so such a session also reads this repository's CLAUDE.md.
- Proposed fix: in P3, put the acceptance test's temp projects outside the repository (a temp directory) and check that no CLAUDE.md or AGENTS.md sits above them.

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

## Docs: skeleton DEPLOY.md and pasted reports
- Source: P0, docs review of PR #322
- Severity: P2
- What: DEPLOY.md lists `setup/harness` commands that do not exist until P2–P3 (it is marked skeleton). PORT-MAP.md and JEV-DESIGN.md are agent reports committed verbatim, without a heading that says what they are and who reads them; PLAN cites their line numbers, so only their links were rewritten.
- Proposed fix: fill DEPLOY.md in P3; in P9 give both files a short preface and convert PLAN's line citations to anchors.

## setup/harness: apt as root is not tested
- Source: P2, Codex review
- Severity: P2
- What: on Linux as root, apt runs without sudo; as another user, apt is offered only when sudo exists. Tests run as a normal user on macOS and ubuntu, so the root path is covered by reading only.
- Proposed fix: a container job running `tests/setup/run.sh` as root, if the port gets a Linux container stage.

## setup/harness: probe timeout is a guess
- Source: P2, reliability review
- Severity: P2
- What: `--version` and login-status probes share a 15-second timeout, not calibrated on slow networks or cold starts.
- Proposed fix: record probe durations in the P3 acceptance runs and set the value from them; move it to config if it needs to differ per host.

## setup/harness: --project inside another repository
- Source: P2, adversarial review
- Severity: P2
- What: `--project` is resolved to the git top level, so pointing it at a subdirectory targets the whole enclosing repository.
- Proposed fix: say so in DEPLOY.md (P3) and print the resolved project in every report header.
