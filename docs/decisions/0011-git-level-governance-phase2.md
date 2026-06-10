# 0011. Install git-level commit-msg hook per-project for phase 2 governance

* Status: accepted (2026-06-10)
* Date: 2026-04-24
* Deciders: venil
* Tags: governance, security, hooks, installer

## Context and Problem Statement

The PreToolUse hook enforces commit-message policy (Conventional Commits, issue references, ADR references, branch discipline), but only for commits made through Claude Code. Commits executed directly from the terminal — `git commit` outside a Claude session — bypass governance entirely. This creates two rule systems in the same repository: strict when Claude is active, none when the operator acts directly. After three pipeline runs (#26, #3, #15) the gap stopped being hypothetical: the same operator who formulated the rules can silently violate them by switching to another terminal. The decision is being made now to add a git-level `commit-msg` hook as a second enforcement point — and to define how that hook is installed strictly within pet projects, without any mechanism capable of affecting third-party repositories.

## Decision Drivers

* **Isolation at the level of installation.** Claude-mini governance applies only to repositories where the installer has physically placed the hook. No global git mechanisms (`core.hooksPath`), no path patterns (`includeIf` with directory glob), no allowlists. The boundary is defined by the fact of installation in a specific repository, not by path matching or naming conventions. Any path-based mechanism inevitably raises the question "what if the path matches accidentally" — that is not a boundary, it is an invitation to error.
* **Closing the gap between Claude and the terminal.** Currently the PreToolUse hook validates commits only when Claude Code is acting. Commits via `git commit` directly from the terminal bypass governance entirely. This gives two modes of operation in one repository: strict with Claude, none without it. Adding a commit-msg hook eliminates this gap: both entry points in governed repositories follow the same rules.
* **The operator remains root outside pet projects.** In any repository that is not a pet project, `git commit` works exactly as git assembled it — no rules, no checks, no surprises from claude-mini. This is the direct counterweight to driver #2: the gap is closed only inside governed repositories, not expanded outward. The operator's machine remains their machine.
* **Trivial rollback.** Per-project installation means that removing the hook is a single command: `rm .git/hooks/commit-msg`. The repository returns to its original state instantly, with no traces in global `~/.gitconfig`, no forgotten allowlist entries, no need to remember what else was configured elsewhere. If the approach proves incorrect tomorrow, abandoning it requires no archaeological operation.

## Considered Options

* **A: Global `core.hooksPath`** — one installer command (`git config --global core.hooksPath ~/.claude/git-hooks`) makes the hook fire in every git repository on the machine.
* **B: Per-project install** — the installer copies the hook script and sets `core.hooksPath` only in a specific repository when explicitly invoked there.
* **D: Allowlist-gated global** — global `core.hooksPath` set, but the hook script bails out (exit 0) when `$PWD` does not match an allowlist file.
* **F: `includeIf` directory glob** — a conditional include in `~/.gitconfig` keyed on a directory pattern activates `core.hooksPath` for matching paths only.

## Decision Outcome

Chosen option: **B (per-project install)**, because it is the only option where the governance boundary is defined by the physical fact of installation, not by a path pattern or configuration entry — which is precisely what the new principle *«Scope инструмента ограничен явной установкой»* (added to `docs/principles.md` as part of this ADR) requires.

Driver prioritisation: #1 and #3 are load-bearing — any option violating the isolation principle is excluded regardless of other considerations. A violates the principle by definition (global mechanism). D and F are both path/config-based and create a class of error "pattern accidentally matched where it should not" — this is structurally indistinguishable from a boundary failure. Driver #4 (trivial rollback) acts as a tie-breaker among the remaining options and confirms B. Driver #2 is a necessary condition for the ADR to exist at all; it does not discriminate between options.

Accepted trade-off: B requires an explicit install action in every new pet project and is subject to drift between hook copies (the same problem addressed by ADR-0010 for `~/.claude/` artifacts). Both downsides concern operations, not the boundary. The boundary is the load-bearing invariant; operability is a solvable problem.

References: `docs/principles.md` §3 *«Автоматизировать только низкорискованное»* (security-sensitive controls over commits justify a second enforcement point); `docs/principles.md` §5 *«Scope инструмента ограничен явной установкой»* (installation fact as the only legitimate boundary mechanism).

### Positive Consequences

* **The governance boundary becomes observable:** `ls .git/hooks/commit-msg` gives an unambiguous answer to "is this repository governed?" No hidden state in global configs, allowlist files, or path patterns.
* **Terminal commits in pet projects follow the same rules as Claude-mediated ones.** The gap described in Context is closed. Governance cannot be bypassed simply by switching terminals.
* **Future extension of the tool becomes disciplined.** The new principle *«Scope инструмента ограничен явной установкой»* cuts off an entire class of future temptations (global launchd plists, shell-rc entries, path-based conditions). Any such proposal now automatically requires reconsidering the principle, not just an ADR.
* **Rollback is trivial and local.** If the hook proves incorrect or limiting — removing it from one repository does not affect others. Experimentation is possible without fear of broad consequences.

### Negative Consequences

* **The installer is now required to activate governance in a new pet project.** Clone a repository, forget to run `--install` — governance silently does not work. Human forgetfulness becomes a failure point. Mitigation: `mini-health` / preflight must check hook installation as part of its report.
* **Drift between hook copies.** The logic of `commit-msg-governance.sh` lives as a copy in each installed repository. Change the rules in bootstrap — old installations retain old rules until the next `--install --force`. This is the same problem that ADR-0010 addresses for `~/.claude/` artifacts, but now multiplied across N pet projects instead of one directory.
* **Code duplication with the PreToolUse hook.** The same 4 rules now live in two places: `pre-commit-governance.sh` (PreToolUse) and `commit-msg-governance.sh` (git). Changing policy requires editing both files synchronously. Failure to do so — silent desynchronisation of rules between the two entry points.
* **Manual hook deletion is undetectable.** The operator can `rm .git/hooks/commit-msg` at any moment — the tool will not know. The next commit will pass without validation. Unlike ADR-0010 (installer abort-on-drift), there is no symmetric mechanism protecting against accidental or intentional removal.
* **The new principle adds a hard constraint on future architectural decisions.** Any future idea requiring global state (shell autocomplete for commands, system-wide launchd timers for housekeeping, cross-project indexing) will now run into this principle. The trade-off is conscious but real — the tool will not be able to become something that requires system-level integration.

## Pros and Cons of the Options

### A: Global `core.hooksPath`

* Good, because one installer command covers every current and future repository automatically.
* Good, because new pet projects pick up governance without additional action.
* Bad, because it violates driver #1 (isolation): the hook fires in **all** git repositories on the machine, including non-pet. Cannot be fixed without abandoning the approach.
* Bad, because it violates driver #4 (rollback): removing the hook from one project means removing it from the global config, losing protection everywhere. There is no way to opt out selectively.
* Bad, because it conflicts with third-party hooks: if a non-pet repository has its own `commit-msg` or `pre-commit`, the global `hooksPath` overrides it silently.

### B: Per-project install

* Good, because it precisely satisfies driver #1: the hook exists exactly where it was placed, without exceptions or path magic.
* Good, because trivial rollback (driver #4): `rm .git/hooks/commit-msg` — one command, zero residual state.
* Good, because it does not affect third-party hooks: if a repository already has its own `commit-msg`, the installer can detect this and ask the operator rather than silently overriding.
* Bad, because it requires an explicit installer action in every new repository. Forgotten → hook not installed → rules silently not enforced.
* Bad, because of drift between copies: if hook logic changes in bootstrap, old installed copies remain outdated until the next `--install`.

### D: Allowlist-gated global

* Good, because it preserves the convenience of global `hooksPath` — configured once, works automatically.
* Good, because it gives targeted control: if the repository is not in the allowlist, the hook exits immediately (exit 0), performing no checks.
* Bad, because it violates driver #1 conceptually: this is a **global mechanism with a carveout**, not a boundary. A forgotten allowlist entry = governance silently not working where it should. An error of omission, not commission — hard to notice.
* Bad, because of two sources of truth: "which repositories are governed" lives both in the allowlist file and in what the installer actually ran. They will diverge over time.
* Bad, because of additional hook code: every commit in every repository runs a script that reads the allowlist and compares paths. Slower on the hot path, especially in large repositories.

### F: `includeIf` directory glob

* Good, because it is elegant: `[includeIf "gitdir:~/code/pet/**"]` — git itself decides whether to apply the config. No custom code, no branching in the hook.
* Good, because rollback is cleaner than D: remove the `includeIf` block from `~/.gitconfig` — everything detaches cleanly.
* Bad, because it violates driver #1: the boundary is defined by the **filesystem path**. Any path match with the pattern — and governance activates where it should not. Move the repository, use a symlink, accidentally clone a non-pet project under `~/code/pet/` — governance is now there.
* Bad, because of hard coupling to filesystem layout. If pet projects are spread across paths (`~/code/`, `~/projects/`, external drive), the pattern must cover all of them. Glob maintenance sprawls.
* Bad, because it does not protect against a "forgotten" repository: a new pet project cloned outside the glob pattern will silently have no governance — the same problem as D but from the other direction.

## Confirmation

1. **Monthly audit of pet projects for hook presence.** A script traverses known pet projects (or the manifest from #31 when it exists), checks for `.git/hooks/commit-msg` with correct content (hash or marker string). Threshold: 100% of governed repositories have an up-to-date hook. Below that — drift report. Implemented as part of `mini-health` or the `/project-health` command (backlog #7).

2. **Zero-bypass commits to main in governed repositories over 30 days after installation.** `git log main --first-parent --since=30.days` in each governed repository — all commits must contain an issue reference and (for architectural changes) an ADR link. Violations signal that the hook is either absent or being bypassed via `--no-verify` regularly. Threshold: 0 violations. More → return to this decision.

3. **Zero incidents of "hook fired in a non-pet repository" over 90 days.** Qualitative criterion: if governance ever activates in a non-pet repository (technically impossible with B, but possible through installation error or accidental `.git/hooks/` copy) — the isolation principle is violated, and either the implementation or the decision is wrong. Threshold: 0 incidents. 1 or more → immediate re-visit.

## Re-visit Trigger

Decision is reconsidered if **any** of the following falsifiable conditions occur:

1. **≥3 commits to main without an issue reference in 30 days** in a governed repository. Signals that either the installer is being forgotten (→ B is unreliable in operation), or the hook is being systematically bypassed via `--no-verify` (→ protection does not work against a motivated operator, CI-side enforcement needed).

2. **The number of pet projects exceeds 10** and manual `--install` in each becomes a noticeable operational burden. This is the numeric threshold for transitioning from "a few projects" to "a portfolio", where the per-project model becomes operationally expensive. Then reconsider toward F (`includeIf`) with an explicit extension of the isolation principle, or toward D (allowlist) with a formalised inclusion process.

3. **Change of development environment:** transition to working across multiple machines simultaneously (e.g. laptop + desktop + mini with real synchronisation of pet projects between them). In this scenario "physical installation" ceases to be a local property — the hook must somehow synchronise, and B begins to require additional infrastructure. Then a comparative re-visit of B vs D is appropriate.

4. **The principle *«Scope инструмента ограничен явной установкой»* proves to be a blocker for a needed capability.** If a justified need arises for something systemically integrated (e.g. a global git template for new repositories with pre-baked governance), and the only way to implement it is through a mechanism the principle forbids — this signals that either the principle is too rigid, or the decision under it is too limiting. Both are reconsidered.

## Links

* Supersedes gap documented in: `docs/decisions/0004-governance-via-prehook.md` §Negative Consequences ("Does not cover direct `git commit` from the terminal — known gap until phase 2")
* Related: `docs/decisions/0010-installer-drift-behavior.md` (drift between installed copies — same class of problem, now extended to N repositories)
* Related: Issue #9 (implementation), Issue #25 (installer behaviour — cross-referenced, not resolved here), Issue #31 (manifest — when available, replaces `~/code/*/` glob in Confirmation #1)
* Hook code: `bootstrap/hooks/commit-msg-governance.sh` (to be created)
* `docs/principles.md` — §5 added as part of this ADR
