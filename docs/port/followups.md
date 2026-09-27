# Port follow-ups

P2 findings and other deferred items from the port run (docs/port/PLAN.md §9). One entry per item, ready to become an issue text. The owner decides which become issues.

<!-- Format:
## <short title>
- Source: <phase, reviewer, PR>
- Severity: P2
- What: <one paragraph>
- Proposed fix: <one paragraph>
-->

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

## `critics` config section deferred from P4 to P6
- Source: P4, PR for #315
- Severity: P2
- What: PLAN P4 put the `critics[{agent,paths,labels}]` section in P4. No component reads it until the review skill arrives in P6, so in P4 it would be config without a reader.
- Proposed fix: add the section in P6 together with the review skill that reads it, or drop it if the agent descriptions prove enough for delegation.

## v1 `--target` no longer installs `/feature`
- Source: P6, PR for #317
- Severity: P2
- What: `bootstrap/commands/feature.md` became the plugin skill `feature`, so `universal-setup.sh --target` stops copying a `/feature` command into projects. The plugin skill replaces it where the plugin is enabled. Board status transitions with fixed project IDs were dropped with it; `tracker.*` config is not built.
- Proposed fix: none while the plugin is the delivery path; P9 removes the v1 installer.

## Run driver cost by PR
- Source: P7
- Severity: P3
- What: PLAN §7 planned per-PR cost from `codeburn --by-pr`. CodeBurn 0.9.25 `report` has no such flag, and the run driver was removed on 2026-09-26.
- Proposed fix: none needed now. If per-PR cost is wanted, filter `report --format json` by date range of the PR.

## uninstall leaves an empty `.claude` directory
- Source: first v2 deployment on the Mac mini, 2026-09-27
- Severity: P3
- What: in a project that had no `.claude` directory, `apply` makes Claude Code create `.claude/` for the local settings file. `uninstall` removes the file and the run directory but leaves the empty `.claude/`. The acceptance test compares files, not directories, so it passes.
- Proposed fix: record in the intent log whether `.claude/` existed before setup; uninstall removes it only if setup created it and it is empty. Add the directory check to the acceptance snapshot.

## mini-preflight still checks the v1 advisor variable
- Source: first v2 deployment on the Mac mini, 2026-09-27
- Severity: P3
- What: `bootstrap/scripts/mini-preflight.sh:62-65` warns when `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` is not set. v1 put it in `~/.zshrc`, v2 does not use it, and it was removed from the Mac mini, so the check now gives a false warning. The script also lost its `~/bin/mini-preflight` link and runs from the clone.
- Proposed fix: drop the check, or ask the owner whether the variable is still wanted outside the harness.
