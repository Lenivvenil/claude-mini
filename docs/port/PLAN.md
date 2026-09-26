# claude-mini v2 port: run plan, revision 2

> **Owner decisions, 2026-09-26 (override §0 and anything below that contradicts them):**
> - **S1** Migration ADR: ADR-0031, merged in #321, status accepted.
> - **S2** Phase issues: ADR #310, P0–P9 = #311–#320 (created by the orchestrating session on the owner's go).
> - **S3** Out-of-project footprint: accepted as the closed list of ADR-0031 §3, compared per entry, never restored wholesale.
> - **S4** No API money: "we work within subscriptions". No `--max-budget-usd` (it bills API usage, not subscription limits); the limiter is subscription quota, watched with `codeburn quota`. Acceptance mode A runs **locally only**, never in CI. Isolated runs (tests, driver) authenticate with a long-lived subscription token from `claude setup-token` **[verified 2026-09-26: the command exists on 2.1.283; an isolated `CLAUDE_CONFIG_DIR` is otherwise "Not logged in"]**, stored by the owner in the macOS Keychain item `claude-mini-test-oauth` and passed as `CLAUDE_CODE_OAUTH_TOKEN`; never logged. Without it, isolated tests exit 77 (SKIPPED), which never counts as a pass.
> - **S5** Jev key: open. Without it P8 is tested on the no-key path only.

- **Inputs:** plan v1, the Codex review ("A"), the Fable review ("F"), the port map (committed verbatim as [PORT-MAP.md](PORT-MAP.md), line numbers preserved), the Jev design (committed verbatim as [JEV-DESIGN.md](JEV-DESIGN.md), line numbers preserved), and the owner's additions. Plan v1 and the two reviews are not in the repository; every finding they raised is carried, with its resolution, in the last section, so this plan does not need them. The repo was read at `~/Projects/claude-mini` `main` 48867dc, 2026-09-26, and was not changed.
- **Evidence:**
  - `path:line` means checked on disk by me.
  - **[verified 2026-09-26]** means verified by the orchestrating session on this machine.
  - **[owner]** means a fact supplied by the owner.
  - **[unverified]** means still open.
- **Findings:** "A#n" / "F#n" are labels of the numbered findings of the Codex / Fable reviews. The last section maps every P0/P1 to a resolution.

## 0. Must decide before P0 starts (the run refuses to start without these)
- **S1. Migration ADR.** Three changes hit the explicit ADR triggers in docs/runbooks/adr-trigger.md:10 and :12 (public API, security model):
  - installer → per-project plugin,
  - the config contract,
  - the `setup/harness` CLI.

  principles.md:55 §5 also requires "пересмотр принципа отдельным ADR". Proposal: one ADR, merged separately before P0. It supersedes ADR-0018 (per-project command copying) and revises §5's wording. Existing ADR files stay byte-identical.
- **S2. Phase issues.** CI rejects any PR without `Closes #N` (ci.yml:171–175). The owner creates issues P0–P9 up front.
- **S3. Native-state footprint (was D1).** Local-scope install writes more than the project **[verified 2026-09-26]**:
  - an entry with `projectPath` in `~/.claude/plugins/installed_plugins.json`,
  - a marketplace entry,
  - a snapshot in `~/.claude/plugins/cache/`.

  CodeBurn adds `~/.cache/codeburn` and `~/.config/codeburn` **[owner]**. Decision needed: accept these as the only permitted out-of-project writes, compared **per entry** (never wholesale), or reject.
- **S4. Spending cap and auth for the run.**
  - Superseded by the owner decision S4 above: no USD cap, no `--max-budget-usd`.
  - Auth inside the isolated run config dir (§8) is either `ANTHROPIC_API_KEY` or an OAuth token via `--settings` apiKeyHelper **[unverified which works on 2.1.283]**.
- **S5. Jev key.** Is a TypeSafe key available for P8? Without it, P8 ships and is tested in the no-key path only.

## 1. Critique of the port map, PORT-MAP.md (v1 content, corrected)
- **Checked claims.** 14 claims were checked on disk and 13 are correct. The details are in v1 §1.1, and both reviewers re-confirmed them.
- **Corrections to v1:**
  - hooks.json has 19 lines, not 20;
  - open weekly ADR-audit PRs are **15, #270–#302**, and mutation issues are 16, #250–#301 (checked with `gh`);
  - `.claude/scratch/handoff-2026-04-29/` has **57** tracked files;
  - the ci.yml list is corrected in §3.
- **Stale claim.** PORT-MAP.md's "mutation cron not verified" is stale. mutation.yml was deleted today in aa83609, and the issues it created are still open.
- **Wrong or missing verdicts (unchanged from v1):**
  - the hardware DROP was overridden by the owner;
  - `plugin/evals/results/` is gitignored (.gitignore:27), so `git mv` does not apply to it;
  - VERSION 1.5.0 differs from plugin.json 2.0.0;
  - agent `model:` pins in plugin/agents/*:5;
  - `CC_REGEX` is hardcoded at commit-msg-check.sh:62 and :73.
- **Unmapped components.** No phase in PORT-MAP.md owns: `.claude/scratch/handoff-2026-04-29/` (57 files), `.github/ISSUE_TEMPLATE/*`, `pull_request_template.md`, `markdown-link-check.json`, root `.semgrep/hedging.yml`, `.semgrepignore`, eval graders and prompt. They are assigned in the P0 ledger (§3), which answers F-req1.
- **Phase order.** Config, the safety net and deployment come before porting. CI is edited in the same PR as every move. Removal is gated by capability, not by filename (A#10).

## 2. Design principles (binding, proportional)
- **Selection rule (owner, 2026-09-26): reliable, antifragile, compact, universal, configurable, current; no long tight muzzles on modern models without a very strong reason.** A rule, check, pipeline step or prompt instruction moves into the plugin only when it names the failure it prevents: a case seen in use, an eval, or a review finding. Without that it stays in git history, ledger verdict `KEEP-HISTORY`. Deterministic checks at a boundary (the commit hook, setup's write boundary) meet the bar. Instructions on how an agent should think do not by default.
- **Scope is the install boundary.** Source: principles.md:51–55 §5. Enforced by the execution boundary (§8) and the hash tests, not by prose.
- **§8, 2–3× margin, not 1000×** (principles.md:79–87).
  - Full depth goes to the commit hook, setup/apply/uninstall and the acceptance test.
  - Pure-move PRs get only the move checks (§9).
  - Where a reviewer called something over-engineered, v2 simplifies. There is no driver state machine (§10). There is no seven-dimension table on move PRs. Mandatory allowlist shrinkage is dropped (A#12, F#13).
- **§9, takeover is a contract** (principles.md:91–101). These are enough to continue by hand without an LLM:
  - the run state,
  - the setup intent log,
  - the consequences report,
  - `docs/port/followups.md`.

  Handoff is an explicit skill, and there is no Stop hook.
- **Strict inside, harmless outside** [owner]:
  - never overwrite or delete what setup did not create;
  - back up before modifying;
  - log every change;
  - fail closed on uncertainty;
  - degrade gracefully without Codex, Jev, CodeBurn or network.
- **Every failure found in use becomes a test or eval case,** in the PR that fixes it.

- **No CLAUDE.md.** Claude Code 2.1.283 loads AGENTS.md by itself (probe 2026-09-26: AGENTS.md-only project, file tools disallowed, zero tool calls, the file's codeword returned). The repository has no CLAUDE.md, and the project layer never creates one.

## 3. Phases (one branch `port/p<N>-<slug>`, one PR, one issue each)
Every PR runs `claude plugin validate plugin --strict`, and passes today. From P2 on, it also runs `tests/setup/run.sh`. From P3 on, it also runs `tests/acceptance/deploy-bare.sh` (mode A).

**P0 — Safety net + run infrastructure** (no behaviour change)
- A phase driver (§10) was built here and removed on 2026-09-26 unused. `.port-run/` stays in .gitignore for test temp dirs.
- `tools/port-run/ledger.tsv` has these columns: `path`, `verdict`, `capability` (the behaviour preserved), `entry_point` (packaged skill/agent/script), `evidence` (the test or command that proves it), `phase`, `archive_dest`. `KEEP-HISTORY` needs `archive_dest` and cannot stand in for a capability marked required (A#10).
- `tests/plugin-scope/no-plugin-no-writes.sh` runs with `HOME=$T/home CLAUDE_CONFIG_DIR=$T/home/.claude` and hashes only `$T` (F#9).
- `tests/lint/no-hardcode.sh` covers a narrow set: model names in frontmatter or scripts, `Lenivvenil`, `PVT_`, `/Users/`, and literal `main` used as a default in scripts. Prose is not scanned, and exceptions are listed with a reason (F#13, A#12).
- Skeletons for `DEPLOY.md` (linked from README) and `tests/acceptance/deploy-bare.sh`. `docs/port/followups.md` is created empty.
- DoD:
  - the tests above exit 0;
  - `tools/port-run/ledger-check.sh` confirms that every `git ls-files` path outside `docs/decisions/` appears exactly once, counted **after** P0's own files are added (F#14);
  - validate --strict passes.

**P1 — Config contract** (after S1)
- `plugin/config/schema.json` and `defaults.json`. The project override is `<project>/.claude/claude-mini.json`.
- JSON, because jq and the Python stdlib both read it.
- **Validator:** `plugin/bin/config validate` is a deliberately limited typed validator in the stdlib (A#11). It supports:
  - object, string, int, bool and enum types;
  - required keys;
  - rejection of unknown keys.

  It is not a full JSON Schema engine, and the schema file documents only the subset it uses. Merge rules: objects deep-merge and arrays replace. On a `schema_version` mismatch it refuses with a migration message.
- **Readers:**
  - hooks run `"$CLAUDE_PLUGIN_ROOT/bin/config" get commit.types`;
  - skills declare `allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/config *)` and call it from the body, which is documented substitution (F#10). The `!` preamble is used only once a P1 test proves it works.
- First consumers:
  - `CC_REGEX` → `commit.types`,
  - codex-review base `main` → `git.base_branch`,
  - agent `model:` → `inherit`.
- DoD:
  - validating defaults gives exit 0;
  - validation fails on an unknown key, a wrong type and a version mismatch;
  - test-commit-msg-check.sh passes with types read from config;
  - validate --strict passes.

**P2 — Setup part 1: machine layer** (`setup/`, top-level, outside the plugin)
- Built from universal-setup.sh:323–334, mini-health.sh, mini-preflight.sh, the GETTING-STARTED tiers, and mac-mini-2018.md §2–10. New files are copied with `git show`, and the originals stay until P9.
- These must not be ported:
  - universal-setup.sh:318 and :758–777;
  - universal-setup.sh:813;
  - mini-preflight.sh:24;
  - mac-mini-2018.md:85 and :89.
- Machine items include `node >= 22.13`, needed by CodeBurn **[owner]**.
- DoD:
  - T1–T6, T8, T10 (§4);
  - CI matrix on ubuntu and macos runs `assess --json` and `apply --dry-run`, with no system installs;
  - fix types are declared per OS (`brew` or `apt`), not hardcoded (F-req6).

**P3 — Setup part 2: harness layer, DEPLOY.md, acceptance green** (the gate for P4 and after)
- **Enablement** **[verified 2026-09-26]**. Two commands:
  1. `claude plugin marketplace add --scope local <path>`
  2. `claude plugin install claude-mini@claude-mini --scope local`

  Together they write exactly `extraKnownMarketplaces` and `enabledPlugins` into `<project>/.claude/settings.local.json`. In another project the plugin shows `Status: disabled`.
- **Rollback** is `claude plugin uninstall claude-mini@claude-mini --scope local`, not a byte restore. The report lists its four write targets (F-req8).
- A local-path marketplace is snapshotted into `~/.claude/plugins/cache/`, not cloned. The marketplace entry points at the directory (F#8).
- The global Git excludes file already has `**/.claude/settings.local.json` on this machine (`~/.config/git/ignore`, 1 line, dated Feb 2026). On a fresh machine Claude may add it (A#4, [per docs, via Astra]). So `apply` first adds the pattern to the project's `.git/info/exclude`, and the file joins the watch list.
- DoD:
  - T1–T10;
  - acceptance mode A green;
  - owner runs mode B once on the real machine before P4 (D-9 kept).

**P4 — Agents.** Six `git mv bootstrap/agents/*.md plugin/agents/` in a pure-move commit, then the edits, then the `critics` config section. ci.yml:36 changes in the same PR. DoD: lint-prompts, validate --strict, `git log --follow` shows history, acceptance green.
- **As built in P4.** The six roles were rewritten after the move, per PORT-MAP rows 13–18; the commit message lists the cuts per role. Subagents cannot ask the user questions, so `domain-researcher` and `solutions-architect` work from the caller's material and return open questions. The `critics` config section is deferred to P6: nothing reads it before the review skill, and config without a reader has no evidence under the selection rule (§2).

**P5 — Planning skills.** Covers issue, plan, adr-author, domain-discovery and backlog-review, including ticket-audit.sh and plan-lint.sh. The ci.yml lines for moved scripts change in the same PR.
- **As built in P5.** `backlog-review` and `domain-discovery` moved into the plugin and were rewritten thin. The discovery interview runs in the main session and `domain-researcher` drafts, because subagents cannot ask the user. The `plan` and `adr` commands are MERGE: `plan` and `adr-author` already carry their capability. The `issue` skill is not built: `task-to-issue`, `issue-to-task`, `audit-pass`, `ticket-audit.sh`, `plan-lint.sh` and the fixtures are KEEP-HISTORY under the selection rule (§2). This is a deviation from the line above, recorded in followups for the owner. No ci.yml line changes: none of these scripts moved.

**P6 — Execution skills and hooks.** Covers feature, implement, qa, review, codex-review and handoff, plus verify.sh, the SARIF and mutation scripts, and stop-hook → handoff skill. ci.yml edits in the same PR:
- :32 (`find bootstrap`),
- :57–63,
- :84,
- :106–108,
- :188,
- :95 (a plugin path, not a bootstrap one, which v1 mislabelled; it moves with the test).

- **As built in P6.** One `feature` skill runs the cycle from issue to PR: branch, plan, implement, verify with the project's own commands, map acceptance criteria to evidence, critics chosen by what the change touches plus Codex, commit and PR, handoff. `implement`, `intent-check`, `qa` and `review` merged into it, so ADR-0031 п. 7 holds with one stage skill. The `handoff` skill replaces the Stop hook: journal first, then the snapshot, a warning on unfilled fields (ADR-0024 sub-decisions 4 and 9). Paths come from new config keys `paths.state` and `paths.handoff`. `plan` and `codex-review` lost `disable-model-invocation`, because a skill with it cannot be called by `feature`. `adr-author` lost its numeric quotas. The formatter hook, verify.sh, mutation and SARIF tools, hedging lint, notify, forge and sprint are KEEP-HISTORY. No ci.yml line changes: none of those files moved.

**P7 — Project skills and templates.** Covers project-bootstrap, project-health (with the CodeBurn report, §7) and adr-retirement-audit. ci.yml edits in the same PR:
- :39 and :43, template readers that v1 missed (A#10);
- :73 (`folder-path: 'docs, bootstrap'`), which v1 missed (F);
- :199–205 and :213.

DoD for P5–P7:
- the moved tests pass under `tests/<area>/`;
- each ledger row gets `entry_point` and `evidence` filled;
- validate --strict passes;
- acceptance is green.

- **As built in P7.** `project-health` moved into the plugin and reports in chat: review time, issue age, ADRs awaiting decision, and AI spend from CodeBurn when `codeburn.enabled`. The ADR template moved into `adr-author`, which uses the project's own template first. `codeburn.version` defaults to 0.9.25, checked on the npm registry (MIT, Node ≥22.13.0). Project bootstrap, the stack templates, gate-audit, adr-retirement-audit and check-mcp-config are KEEP-HISTORY. No ci.yml line changes: none of those files moved.

**P8 — Jev: one advisory plan check** (was P9; now a deliverable, per A#8 and F-req2)
- Scope is [JEV-DESIGN.md](JEV-DESIGN.md#L46) item 6 (lines 46–50, "Plan quality lint") and rollout step 1 at line 125, cut 1 only: advisory plan lint. There are three Noul questions:
  - unsupported design assertion,
  - claimed ADR support absent from the cited excerpt,
  - AC without a verification method.
- `plugin/bin/jev-check` is called by the `plan` skill after the deterministic plan-lint.sh. Output is JSON `{status: ok|unavailable|timeout|invalid_response|oversized_state|disabled, findings[]}`, and the findings are advisory lines in the plan.
- Config holds `jev.{enabled:false, model:"jev-1.13.0", questions[], thresholds, timeout_ms:3000}`. The key comes from env only and is never logged.
- Deterministic gates are unchanged. Jev never blocks, waives or approves anything.
- DoD:
  - these tests pass: disabled → `disabled`; no key → `unavailable`; a stub server that sleeps longer than the timeout → `timeout` within 3.5 s; malformed JSON → `invalid_response`; oversized state → `oversized_state`;
  - in all five cases plan-lint.sh and the plan skill complete normally;
  - with a key (S5), one live smoke on a fixture plan, cost logged;
  - thresholds are marked uncalibrated in config.
- ADR-trigger shadowing and critic grading stay in followups.

**P9 — Removal and docs** (capability-gated)
- `git rm` only for rows with `evidence` passing, or with `KEEP-HISTORY` and `archive_dest`.
- README, AGENTS and CLAUDE are rewritten. principles.md §5 is rewritten per the S1 ADR (F#5).
- **Must not move** `plugin/` or `.claude-plugin/marketplace.json`: `~/Projects/likec4` uses this marketplace at local scope from the working tree **[verified 2026-09-26; installed_plugins.json entry: projectPath likec4, sha 48867dc]**.
- The grep for `universal-setup` runs only over active deployment surfaces (README, DEPLOY, AGENTS, CLAUDE, setup/, plugin/). ADR-0018:34 legitimately keeps it (A#10).
- DoD:
  - `git diff --stat main -- docs/decisions` is empty;
  - ledger-check passes;
  - acceptance modes A and B are green on the final main.

## 4. Setup: checklist, assess, apply, uninstall
- **Interface:**
  - `setup/harness assess [--project DIR] [--layer machine|project|all] [--json]` is **strictly read-only**. The report goes to stdout only (A#6).
  - `setup/harness apply [--project DIR] [--allow-system id,…] [--dry-run]`
  - `setup/harness verify [--project DIR]`
  - `setup/harness uninstall [--project DIR] [--item id]`

  There is no separate `rollback` verb. `uninstall --item` is the rollback of one item.

  As built in P2 (#313):
  - `verify` is `assess` with a failing exit when a required (not `optional`) applicable item is not ready.
  - Exit codes: 0 ok, reduced mode included · 1 invalid config or state · 2 usage · 3 `apply`: a program is missing and its id is not in `--allow-system` (nothing installed for it) · 4 a fix failed · 5 `verify`: a required item is not ready. `assess` and `apply --dry-run` exit 0 whatever the statuses.
  - `--allow-system` naming an unknown item, or one setup cannot install on this OS, is a usage error. Naming an item that is already ready is fine, so the same command can be repeated.
  - `wrong-version` is never upgraded by setup: an upgrade has no clean rollback. The report gives the upgrade command.
  - `uninstall` without `--item` changes nothing and lists what `apply` installed. `uninstall --item` removes only a package whose install `apply` logged as done.
- **Checklist item** (in schema `checklist.items[]`): `{id, layer, handler, applies_if, optional, purpose}` plus the handler's own typed fields: `binary`, `min_version`, `packages.{brew,apt}`, `manual` for `binary-version`; `tool` for `auth-status`. There is no `kind` field: an item with `packages` is a system install and needs consent. P2 implements `binary-version` and `auth-status`, the rest come with the project layer. `handler` is one of a fixed set of typed handlers implemented in code, with containment checks:
  - `binary-version`
  - `auth-status` (gh, claude, codex)
  - `project-file`
  - `project-json-merge`
  - `mise-pin`
  - `plugin-local`
  - `git-exclude`

  There are **no free shell strings** in config (A#11).
- **Status values:** `ready | missing | wrong-version | not-applicable | needs-manual`. Auth reports `ready` when the status command confirms it, and `needs-manual` only when action is needed (A#11).
- **Scope:**
  - writes stay under `DIR`;
  - tool versions are pinned in `DIR/mise.toml` and run via `mise exec --`;
  - `kind: system-binary` fixes run only when named in `--allow-system`, and are refused otherwise;
  - never touched: `~/.claude/settings.json`, shell profiles, `~/bin`, other projects.

  S3 lists the only permitted native writes.
- **Owned artifacts:** `DIR/.claude/claude-mini/{intent.jsonl, backup/, reports/, src/}` is excluded from the "unchanged" hashes by rule. Uninstall removes it last, so T9 compares the tree without it, then checks that it is gone (A#6).
- **Crash-safe apply per item** (A#5; the lesson of the half-applied file is 2 of 4 edits applied, then a NameError):
  1. Append intent `{item, path, sha_before, backup, state: started}` and fsync.
  2. Write the candidate to a temp file in the same directory.
  3. Validate the **candidate**: syntax plus a behavioural smoke check. For the hook, a bad message is denied and a good one allowed. For config, `config validate <candidate>`.
  4. Back up the original, then atomic `mv`.
  5. Append `state: done, sha_after`.

  On restart, any `started` item without `done` is recovered from its backup if the current file still has `sha_before` or the candidate hash. Otherwise the item is reported under Broken, for a human.
- **Uninstall** restores a file only if its current hash equals the recorded `sha_after`. If the user edited it since, the item is left alone and reported under Not done.
- **Multi-target operations** are recovered by their own inverse command and verified by re-reading the state they touched:
  - `plugin-local` is recovered with `claude plugin uninstall … --scope local`;
  - package installs are recovered with `brew uninstall` or `apt remove`, and only if setup installed the package itself.
- **No-op rule:** a second apply with an empty delta writes nothing, not even a report file. It prints only.
- **As built in P3 (#314).** The project layer has two items, both applied without `--allow-system` because they write inside the project: `git-exclude` (Claude Code's local settings file and setup's run directory join `.git/info/exclude`) and `plugin-local` (Claude Code's own `marketplace add` and `install` with `--scope local`). `uninstall` without `--item` disables the plugin, returns `.claude/settings.local.json` and the exclude file to their bytes unless edited since, and removes the run directory last; packages setup installed stay until `uninstall --item`. Handlers `project-file`, `project-json-merge` and `mise-pin` are not built: no item needs them under the selection rule. The optional git hook of ADR-0031 п. 9 is not built yet (default off); see followups.
- **Where T8 runs.** The machine layer changes no files, only packages. The crash-safe file primitive (`setup/lib/txn.py`) is built and fault-tested in P2, and the project-layer items of P3 use it.
- **Consequences report** (apply and uninstall save it to `reports/<ts>.md`; assess prints it). Every item is re-checked at report time. It has three sections:
  - **Broken:** what, the evidence (command and output), and one fix command plus one rollback command.
  - **Not done:** what failed and why, and what state remains.
  - **Works:** what, and the verifying command.
- **Tests** (`tests/setup/`: temp HOME, temp projects, PATH shims for brew, apt, mise and claude):
  - T1: assess on a ready fixture gives an empty delta and writes nothing.
  - T2: apply twice; the second run writes nothing.
  - T3: system-binary without consent is refused, exit 3.
  - T4: the watch list is unchanged: sibling tree; `~/.claude/settings.json`; shell profiles; `.gitconfig`; `~/.config/git/ignore`; `.claude/` of the other listed projects. The comparison covers paths created or deleted, bytes, symlinks and modes (A#7).
  - T5: `uninstall` restores the project tree (owned directory excluded, then checked absent).
  - T6: assess `--json` validates.
  - T7: hook deny with a staged-commit fixture. A bad message is denied **by the hook**, asserted from the hook's stderr marker. A good message commits. Git identity is set in the fixture (A#7).
  - T8: fault injection before the swap, after the swap and before `done`, and between items. Each target is byte-identical or recovered, and the report is correct.
  - T9: apply → uninstall → hashes equal the originals.
  - T10: without codex, CodeBurn or network → reduced mode, exit 0, listed under Not done.
  - T11: a user edit after apply followed by uninstall leaves the edit in place.

## 5. Acceptance test `tests/acceptance/deploy-bare.sh` (final DoD; the gate from P3 on)
1. **Candidate pinning (A#7, F#6).** The harness source is the **phase worktree path at a recorded SHA**. The prompt names that local path. The GitHub route is checked only at P9, against merged main.
2. **Setup.** Create `$T/proj` with a staged fixture commit, `$T/sibling` with its own `.claude/settings.local.json` and a linked worktree, and a symlink into `$T/proj`. Hash the watch list from T4. For `installed_plugins.json` and `known_marketplaces.json`, record **per-entry** hashes.
3. **Run.** Prompt: `deploy my harness for this project` plus `Harness: <path>`. The command is `claude -p … --output-format json --permission-mode acceptEdits --permission-prompts none` with:
   - `--allowedTools "Bash(git *),Bash(claude plugin *),Bash(bash *),Read,Edit,Write"`;
   - `--disallowedTools "Bash(git push *),Bash(gh *)"`.

   `Bash(bash *)` is needed because the cloned path is not a stable prefix (F#7). The boundary is the hash check, not the allowlist (F#1).
4. **Pass** when all of the following hold:
   - (a) a fresh session in `$T/proj` lists `claude-mini` in init `plugins`, with no `plugin_errors`;
   - (b) T7 passes in `$T/proj` (no stream-shape parsing, F#12);
   - (c) validate passes;
   - (d) a session in `$T/sibling` shows the plugin as not enabled, and `git -C $T/sibling commit` with a bad message is not blocked by claude-mini;
   - (e) the watch list is unchanged, and the only new native entries are the S3-permitted ones for `$T/proj`;
   - (f) the report has an empty Broken section;
   - (g) after uninstall, the per-entry hashes of the native registries are back to their before-state.
5. **Modes.**
   - **A** (CI and default): `HOME=$T/home CLAUDE_CONFIG_DIR=$T/home/.claude`, auth per S4.
   - **B** (real machine, owner go only): snapshot and diff. It excludes the pre-existing `claude-mini@claude-mini` entry for projectPath `…/likec4` and likec4's own files, so they do not fail (e) and (g) spuriously (F#8).
6. **Parsing.** `--output-format json` returns an **array** on 2.1.283 (a nested-session test on 2026-09-26 returned a list of 4, with `session_id` and `total_cost_usd` in the last element). jq uses `if type=="array" then .[-1] else . end` (F#4).

## 6. Config keys (defaults in plugin, override in project)
- **Keys:**
  - `schema_version`
  - `git.base_branch`
  - `commit.{types,scope_regex,require_issue_ref}`
  - `critics[{agent,paths,labels}]`
  - `review.{block_on,record}`
  - `codex.{enabled,modes,timeout_ms}`
  - `jev.*` (P8)
  - `codeburn.*` (§7)
  - `templates.set`
  - `tracker.{kind,repo,board_id}` (all null by default)
  - `paths.{state,handoff,run_dir}`
  - `output.language`
  - `checklist.items[]`
  - `tools.{name: version_req}`
- **Stays in code:**
  - the typed validator and handlers;
  - hook events and matchers;
  - frontmatter keys;
  - parser logic;
  - exit codes;
  - security guards.

## 7. CodeBurn [owner facts: MIT, Node ≥22.13, reads ~/.claude and Codex sessions, writes ~/.cache/codeburn and ~/.config/codeburn]
- **Machine layer.** A `node` check (≥22.13). CodeBurn itself is never installed globally and runs as `npx -y codeburn@<pinned>`.
- **Config.** `codeburn.{enabled:false, version:"<pin>", runner:"npx", mcp:false}`. There is **no key that enables `optimize --apply`**. The command is refused in code, because it edits `~/.claude`, moves `~/.claude/skills`, and edits `.mcp.json` and CLAUDE.md [owner].
- **Project-health.** A read-only report, `codeburn report --project <project root> -p 30days --format json` [verified 2026-09-26 against the 0.9.25 README: `--project` takes an absolute path and selects that project; `report` has no `--by-pr`, `--by-work-unit` or `--by-agent`]. When CodeBurn is unavailable → reduced mode (T10).
- **MCP.** Opt-in only, and only as `claude mcp add --scope local codeburn -- npx -y codeburn@<pin> mcp` in the target project. Never at user scope.
- **Run driver.** Uses `codeburn --by-pr --format json` for per-phase and per-PR cost, instead of summing `total_cost_usd`. This fixes the double counting of cumulative resume totals (A budget, F#4). Fallback when CodeBurn is absent: keep the latest `total_cost_usd` per distinct session_id and sum across sessions.
- **Global dirs.** `~/.cache/codeburn` and `~/.config/codeburn` are part of decision S3.

## 8. Guardrails
Phases run by hand in a session; every PR is merged by the owner.
- **Forbidden:** global config and shell profiles; pushes to or merges into main; closing or editing issues and PRs; changes to `docs/decisions/*` other than status; `git rm` outside the ledger; editing tests to make them pass; moving `plugin/` or `marketplace.json` (likec4 uses them).
- **Commits.** Conventional Commits `type(scope): subject #N`. A pure `git mv` commit comes before any edit of the moved files.
- **Stop and ask the owner** on: a system program to install, a new ADR trigger beyond S1, a P0/P1 finding still open after 2 rounds.

## 9. Review policy (reconciled with docs/runbooks/dod-checklist.md, A#9)
- **Pure-move PR commits.** Checks: `git diff -M --stat` shows only renames, plus CI green. No critics and no §8 table.
- **Before implementation, per phase (second voice).** One `solutions-architect` call on the phase prompt and file list. This is the preimplementation opinion the pipeline requires.
- **Per PR, inside one review session with subagents** (this settles F#11):
  - `adversarial-critic` always (dod:11);
  - `reliability-reviewer` when `bootstrap/`, `setup/`, `.github/workflows/` or the hooks are touched (dod:18);
  - `docs-reviewer` when README, runbooks, principles or DEPLOY are touched (dod:17);
  - `security-reviewer` on P2, P3 and P8;
  - Codex **once**: `codex review --base <base>` plus `--uncommitted` if the tree is dirty (SKILL.md:18–26).
  - A short §8 table (N/A allowed) goes in the PR body, except for pure-move PRs.
- **Blocking and deferral.** Only P0/P1 block. P2/P3 findings are appended to the tracked `docs/port/followups.md` as issue-ready text, which is durable (A#9). This replaces dod:12's auto-created `type:deferred-review` issue, and the S1 ADR records the change.
- **Rounds.** At most 2 fix rounds, each recording the reviewed SHA. Every semantic fix of a P0/P1 is re-checked by the critic that raised it, and Codex runs once more if any P0/P1 fix changed non-test code. The 50-line rule is dropped. After 2 rounds the state is `blocked` with the unresolved finding, and approval is not implied.
- **Parser edge cases** are P2 unless a bad message passes or a good one is blocked.

## 10. Driver
Removed on 2026-09-26 without a single run: it needs the subscription token for isolated sessions, and every phase so far was run by hand. It stays in git history (P0, #322).

## 11. Budget (uncalibrated; P0 is the calibration run)
- **Per phase:** 3 sessions (implementation, review with subagents inside, fix if needed), plus 1 architect call and 1 Codex call. P3 adds 3–5 acceptance runs.
- **Total:** ≈30–35 sessions and ≈12 acceptance runs.
- **Known data points (F):**
  - eval run: $0.254;
  - trivial `-p` call: $0.005;
  - Jev lint: ≈ $0.0003 per call ([JEV-DESIGN.md](JEV-DESIGN.md#L50)).
- **Wall time:** ≈18–28 h of agent time, plus rework and merge latency. Re-estimate after P0 and P1 from CodeBurn per-PR data.
- **Hard stop:** none by flag: `--max-turns` is not in `--help` on 2.1.283 and `--max-budget-usd` is out per S4. The limit is subscription quota.

## 12. Remaining owner decisions (not blocking P0)
- D-2. Stacked branches instead of a merge after every PR. Default: off.
- D-4. mac-mini-2018.md:20: revise or keep as history.
- D-5b. Closed by S4: acceptance runs locally only.
- D-6. Attribution lines. Default: current practice, yes.
- D-7. What to do with the weekly-report noise (#250–#301, #270–#302), `.claude/scratch/handoff-2026-04-29/`, STATE.md and session-log/.
- D-9. Mode B on the real machine: required after P3 and after P9? Default: yes.
- D-10. Commit the target project's `reports/`, or gitignore them. Default: gitignore, and the owned directory in general.
- D-11. When likec4 is re-pointed, so that `plugin/` may ever move.

## 13. Review finding → resolution
| Finding | Sev | Resolution |
|---|---|---|
| A#1 ADR, prerequisites before P0 / F#5 ADR | P0/P1 | Fixed: §0 S1–S5; principles §5 rewrite in P9 |
| A#2 enforced execution boundary | P0 | Fixed: §8 isolated CLAUDE_CONFIG_DIR, strict MCP, post-session boundary check |
| A#3 restartable driver | P0 | Fixed: §10 lock, base_sha, UUID before launch, full replay, PR discovery |
| A#4 local ≠ harmless, global excludes, registries | P1 | Fixed: S3 per-entry comparison; P3 `.git/info/exclude`; `~/.config/git/ignore` in T4 |
| A#5 crash window, candidate validation | P1 | Fixed: §4 intent log, recovery, restore-only-if-unchanged, T8, T11 |
| A#6 inconsistent DoD (read-only assess, reports) | P1 | Fixed: §4 assess prints only; owned dir excluded; no-op writes nothing |
| A#7 acceptance semantics | P1 | Fixed: §5 SHA-pinned path, staged fixture, good commit, sibling session, symlink/mode checks |
| A#8 / F-req2 Jev deliverable | P1 | Fixed: P8 with DoD and failure-mode tests |
| A#9 review reconciliation | P1 | Fixed: §9 per dod:11/17/18, architect pre-voice, `--uncommitted`, followups tracked. Partly rejected: dod:12 auto-issue replaced by followups file (guardrail against auto-issues), recorded in S1 ADR |
| A#10 capability ledger, ci.yml:39, ADR-0018 grep | P1 | Fixed: P0 ledger columns; P7 ci:39/:43/:73; P9 grep scoped |
| A#11 validator, command language, auth | P1 | Fixed: P1 limited validator; §4 typed handlers; auth `ready` when verified |
| F#1 allowlist unwritten | P0 | Fixed: §8 per-phase lists; hashes are the boundary |
| F#2 CI needs `Closes #N` | P0 | Fixed: S2 |
| F#3 exit 10 impossible | P0 | Fixed: §8 state-file channel |
| F#4 JSON array, cumulative cost | P0 | Fixed: §5.6 jq; §7 CodeBurn per-PR plus per-session fallback |
| F#6 acceptance tests main | P1 | Fixed: §5.1 |
| F#7 `Bash(setup/harness *)` never matches | P1 | Fixed: §5.3 `Bash(bash *)` + hash boundary |
| F#8 live marketplace, cache path, likec4 | P1 | Fixed: P3 wording, P9 no-move, §5.5 mode-B exclusions |
| F#9 no-plugin test measures real HOME | P1 | Fixed: P0 isolated HOME |
| F#10 `${CLAUDE_PLUGIN_ROOT}` in `!` | P1 | Fixed: P1 allowed-tools form; `!` only after test |
| F#11 sessions vs calls contradiction | P1 | Fixed: §9/§11 one review session with subagents |
| F#12 hook-deny stream shape | P1 | Fixed: (b) relies on T7 |
| F factual: PRs #270–#302, 57 files, ci labels, cache snapshot | — | Fixed: §1, P6/P7, P3 |
| A#12, F#13 ceremony, over-engineering | P2 | Simplified: no shrink quota, prose not scanned, no §8 table on moves, no state machine |
