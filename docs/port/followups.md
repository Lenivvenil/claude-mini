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
- What: `tests/plugin-scope/no-plugin-no-writes.sh` still creates its temp projects under `.port-run/tmp` inside this repository, so a session there also reads the repository's AGENTS.md. The acceptance test (P3) already uses a temp directory outside and checks that no instructions file sits above it.
- Proposed fix: move the plugin-scope test to the same outside temp directory.

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

## Optional git hook (ADR-0031 п. 9) not built
- Source: P3
- Severity: P2
- What: ADR-0031 п. 9 makes a hook in `.git/hooks` an optional project item, off by default, for commits made by people. P3 does not build it: the plugin hook already checks every commit made from Claude, and no request for checking human commits exists yet.
- Proposed fix: add a `git-hook` project item when a project asks for it; it installs a `commit-msg` hook that calls the plugin's check, through the same txn primitive.

## A plugin entry that was false before setup is not restored
- Source: P3, Codex review
- Severity: P2
- What: if `.claude/settings.local.json` already had `enabledPlugins["claude-mini@claude-mini"] = false`, apply enables it and Claude Code's uninstall removes the entry, so the file no longer equals the original and setup leaves it (reported as disabled, bytes differ).
- Proposed fix: restore the owned keys to their original values, not only the whole file when nothing else changed.

## `critics` config section deferred from P4 to P6
- Source: P4, PR for #315
- Severity: P2
- What: PLAN P4 put the `critics[{agent,paths,labels}]` section in P4. No component reads it until the review skill arrives in P6, so in P4 it would be config without a reader.
- Proposed fix: add the section in P6 together with the review skill that reads it, or drop it if the agent descriptions prove enough for delegation.

## No `issue` skill in P5
- Source: P5, PR for #316
- Severity: P2
- What: PLAN P5 and PORT-MAP rows 27, 29, 31, 76 and 106 put issue capture and the ticket audit into a new `issue` skill. Under the selection rule no failure was named that they prevent, so they are KEEP-HISTORY and the skill is not built. `audit-pass` implements ADR-0023.
- Proposed fix: the owner accepts or reverses. If accepted, P9 marks ADR-0023 superseded when the files go.

## adr-author keeps numeric quotas
- Source: P5
- Severity: P2
- What: `plugin/skills/adr-author/SKILL.md` still refuses to proceed with fewer than three drivers or options, or fewer bad than good consequences. P4 removed the same quotas from `solutions-architect` and `adr-reviewer` asks for real options, not a count.
- Proposed fix: in P6 or a separate PR, replace the quotas with the reviewer's rule: real options and real costs.
