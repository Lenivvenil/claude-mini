# 0018. Per-project slash command installation with semver drift detection

* Status: accepted
* Date: 2026-04-28
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: pipeline, installation, tooling, governance

## Context and Problem Statement

Relates to: #94

`bootstrap/universal-setup.sh --install` currently writes every file under `bootstrap/commands/` into `~/.claude/commands/` — a single global namespace shared by every project on the machine. `feature.md` and several other commands embed project-specific values (GitHub Projects v2 board IDs, status field option IDs) that are correct only for the project where the last `--install` ran. With three or more repositories using the pipeline in parallel, every `/feature` invocation silently targets whichever board the most recent install configured. The contamination is invisible until a status transition fails or lands on the wrong board — which is exactly what occurred when `/feature 90` in claude-mini moved cards on a different repo's "digest" board. The decision is architecturally significant on two counts from `docs/principles.md#что-значит-архитектурно-значимо`: it establishes a new public CLI contract (`--target <repo>`), and it introduces an installed-state dependency in every consuming repo that will be hard to remove inside six months once N projects depend on it.

## Decision Drivers

* **Cross-project contamination must be impossible by construction, not by discipline.** A pipeline whose correctness depends on the operator remembering which repo they ran `--install` from last is broken; the test in `docs/principles.md §4` ("коллега восстанавливает контекст за час") fails immediately.
* **Scope-by-installation, not by configuration pattern** (`docs/principles.md §5`). The principle is already materialised for the commit-msg hook via `--hook-this-repo` — the same model must extend to commands once they too carry project-specific state. The boundary is the fact of installation in a specific directory, not a runtime path-match.
* **Version drift between the source repo and an installed project must be visible at invocation time, not at failure time.** `/feature` is the most frequently invoked command; its startup is the natural place for the check.
* **Boundary by directory, not per-file judgement.** A rule that classifies each file as "project-bound or global" by inspecting its content does not survive the next command added; the split must be structural.

## Considered Options

* **Option A — Per-project commands via `--target <repo>`; `--install` no longer writes `commands/`** (chosen)
* **Option B — Commands stay global; project-specific values live in a per-project `.claude/project.json` read at runtime**
* **Option C — Symlinks from each project's `.claude/commands/` into `~/.claude/commands/`**

## Decision Outcome

Chosen option: **Option A — `--target <repo>` per-project install with `bootstrap/VERSION` baked into the installed file**, because it is the only option that satisfies the structural-boundary driver (`docs/principles.md §5`: *"Граница — факт установки, а не конфигурационный паттерн"*) without introducing a runtime configuration layer that must itself be maintained, validated, and kept in sync. The split is by directory: every file under `bootstrap/commands/` is project-bound and installs only via `--target`; every file under `bootstrap/agents/`, `bootstrap/skills/`, and `bootstrap/hooks/` stays global because none of them embeds project-specific state. No per-file judgement, no precedence rule between global and project copies — `--install` simply stops touching `~/.claude/commands/`, so the conflict cannot exist.

The contract is:

```
universal-setup.sh --install
  copies agents/, skills/, hooks/ to ~/.claude/ as before
  does NOT copy commands/
  prints: "commands are per-project; use --target <repo>"

universal-setup.sh --target <repo>
  copies bootstrap/commands/*.md to <repo>/.claude/commands/
  substitutes the literal value of bootstrap/VERSION into each copied file
    wherever the placeholder PIPELINE_VERSION appears (notably in feature.md)
  writes <repo>/.claude/pipeline-version containing the same value
  does NOT touch ~/.claude/, settings.json, env vars, or system config
```

`bootstrap/VERSION` is a single-line semver string. Convention:

* **Major** — breaking command rename or removal (`/feature` → `/run-feature`, deletion of a command).
* **Minor** — new command, new skill, new optional flag.
* **Patch** — bugfix or wording change inside an existing command.

`feature.md` reads `<repo>/.claude/pipeline-version` at startup and compares against the baked `PIPELINE_VERSION`. Four states:

* **missing** → warn: "this project was not installed via `--target`; run `./bootstrap/universal-setup.sh --target .` from claude-mini".
* **stale** (file value < baked value) → warn: "pipeline drift: project at X.Y.Z, command at A.B.C; re-run `--target` to upgrade".
* **current** (file value == baked value) → silent.
* **future** (file value > baked value) — possible if `--target` wrote `pipeline-version` before completing the copy of `feature.md` (partial install race). Treated as **current** — no action required beyond noting that it can occur; the next `--target --force` run resolves it.

**Scope of the drift check.** This mechanism detects file-state inconsistency between an installed `feature.md` and its sibling `pipeline-version` — manual edits to either file, partial installs, or a `--target` run that was interrupted. It does **not** detect source-repository advancement: bumping `bootstrap/VERSION` in claude-mini does not change either file in a previously-installed project, so a project running an outdated baked version reports "current" until the operator re-runs `--target`. Closing that gap is the per-release `--target` discipline obligation, listed in Negative Consequences below.

`<repo>/.claude/commands/` and `<repo>/.claude/pipeline-version` are gitignored — they are build artefacts, the same way `dist/` is. `bootstrap/commands/` is the source of truth.

The `platform.done` hardware-layer gate is **relaxed for `--target` mode**: `--target` only copies files into a repo working tree and touches no system configuration, so the gate has no signal to provide. `--install` continues to require it, unchanged.

**Reversibility:** mostly reversible, with friction. The `--target` CLI surface becomes external the moment the second repo runs it; reverting requires either a deprecation cycle or accepting that every consuming repo must re-install via the replacement mechanism. For `~/.claude/commands/` the change is a one-way door at first install — the global copies become stale shadows from that moment on.

### Positive Consequences

* `/feature` invoked in repo X cannot move cards on repo Y's board, because the command in repo X carries repo X's IDs by construction. The class of bugs that produced #94 is eliminated, not mitigated.
* Pipeline upgrades become explicit: `git pull && ./bootstrap/universal-setup.sh --target .` per project. There is no "did I forget to re-install?" — the drift check answers it on the next `/feature` against the file-state contract.
* Boundary rule is one sentence ("everything in `bootstrap/commands/` is project-bound; everything else is global"), survives every future command added without re-litigation.
* `bootstrap/VERSION` becomes a single-source pipeline version visible in `git log` and `git blame`; every command-touching PR carries a bump in the diff.

### Negative Consequences

* **Manual migration of existing `~/.claude/commands/` is required and not automated.** Operators with prior installs must first inspect `~/.claude/commands/` (`ls`, then diff against `bootstrap/commands/` for any file they suspect they edited), and only then run `rm ~/.claude/commands/*.md`. This ADR deliberately does not script the deletion: any user who copied or edited a command in place would lose that customisation silently, and the cost of a wrong automated `rm` outweighs the convenience.
* **Per-project upgrade cost scales linearly.** Three repos using the pipeline mean three `--target` runs per pipeline release. There is no batch-upgrade tool in this ADR's scope; if the count grows past a threshold, that becomes a separate decision.
* **No CI enforcement of `bootstrap/VERSION` bumps.** Operators must remember to bump the version on every PR that changes `bootstrap/commands/`. A PR that adds a command without bumping `VERSION` will pass review and ship a stealth update — no installed project will see a drift warning until the next unrelated bump. CLAUDE.md will document the discipline; CI does not enforce it.
* **The drift check does not detect source advancement.** A project that was installed at `1.0.0`, when the source is now `1.2.0`, reports "current" because the baked value and the sibling file agree. The mechanism is a guardrail against partial or corrupted installs, not against forgetting to upgrade. The "forgot to upgrade" failure mode is mitigated by the `--target` cadence discipline, not by the runtime check.
* **`feature.md` mutation at install time** means the file in `<repo>/.claude/commands/feature.md` is not byte-identical to the source. Any future debugging must keep this in mind: the installed copy is the truth at runtime, the source is the truth at edit time.
* **Existing global shadow copies, if not removed, will silently diverge.** `--install` no longer refreshes them, but Claude Code will still load them when no project copy exists. An operator who skips the migration step has the worst of both worlds: stale global commands plus the new contract.

## Pros and Cons of the Options

### Option A — Per-project commands via `--target <repo>`; `--install` drops `commands/`

* Good, because the global namespace contains nothing that varies per project, so the contamination class disappears at the structural level.
* Good, because the boundary rule is by directory and survives without per-file inspection.
* Good, because version drift is detected at the natural point of use (`/feature` startup) without any background process.
* Good, because the model already exists in this codebase — `--hook-this-repo` is the same pattern for the commit-msg hook, and `docs/principles.md §5` is on the books.
* Bad, because every consuming repo must run `--target` once at adoption and again on every pipeline release.
* Bad, because the migration of pre-existing `~/.claude/commands/` is operator responsibility — automating it risks deleting hand-edited customisations.
* Bad, because the installed `feature.md` is no longer a byte-copy of the source — debuggers must remember the literal substitution.

### Option B — Global commands plus per-project `.claude/project.json` config

* Good, because the install model does not change — `--install` continues to write commands to `~/.claude/commands/` and operators do not learn a new flag.
* Good, because adding a new project requires only writing a small JSON file, not running a script.
* Bad, because the global mutable state remains: a corrupted or absent `project.json` falls back to whatever values the command was last installed with, recreating the original bug in a new shape.
* Bad, because it treats project autonomy as a data-lookup problem rather than a structural-isolation problem; the runtime now has to validate the config schema, handle missing keys, and decide a fallback policy — none of which exist in Option A.
* Bad, because it violates `docs/principles.md §5`: scope is determined by a configuration pattern (`if project.json exists, read it`) rather than by the fact of installation in a specific directory.
* Bad, because a project added without a `project.json` would not fail loudly — it would inherit the global defaults and corrupt another project's board exactly as today.

### Option C — Symlinks from `<repo>/.claude/commands/` into `~/.claude/commands/`

* Good, because a single edit to the global file propagates to every linked project for free.
* Good, because there is no version-drift concept to design — every project is by definition current.
* Bad, because it removes the isolation entirely: every project sees the same file content, so per-project IDs cannot live in the file at all. The original problem is unsolved.
* Bad, because version baking has nowhere to live — a symlinked `feature.md` cannot carry a different `PIPELINE_VERSION` per project.
* Bad, because symlinks across `~/` boundaries are fragile under repository moves, dotfile syncers, and editors that follow vs preserve links — operationally hostile.

## Confirmation

Validation is the smoke from `plan.md §5`, executed manually before the implementation PR merges:

1. **Install produces a self-consistent pair.** `./bootstrap/universal-setup.sh --target /tmp/test-proj` on an empty directory produces `/tmp/test-proj/.claude/commands/feature.md` with `PIPELINE_VERSION="<value of bootstrap/VERSION>"` baked in, and `/tmp/test-proj/.claude/pipeline-version` containing the same string verbatim.
2. **Drift states fire correctly.** Starting from a clean install of step 1: (a) manually edit `/tmp/test-proj/.claude/commands/feature.md` to raise the baked `PIPELINE_VERSION` (simulating a partial or corrupted install), invoke `/feature`, observe the **stale** warning naming both versions; (b) delete `/tmp/test-proj/.claude/pipeline-version`, invoke `/feature`, observe the **missing** warning; (c) restore both files via a fresh `--target` run, invoke `/feature`, observe no drift output.
3. **`--install` no longer touches global commands.** `./bootstrap/universal-setup.sh --install` after the change leaves `~/.claude/commands/` byte-identical: `diff` of the directory before and after the run is empty.
4. **`--target` is idempotent.** Running `--target` twice in succession on the same repo reports "identical, skip" for every file and does not bump the timestamp on `pipeline-version`.

These four checks are the merge gate for #94's implementation PR. If any fails, the implementation does not match this ADR.

## Re-visit Trigger

Reconsider this decision when **any** of the following becomes true:

* A CI check enforces `bootstrap/VERSION` bumps on PRs that touch `bootstrap/commands/` — the "no CI enforcement" negative consequence is then obsolete and the ADR's discipline clause should be rewritten or removed.
* The number of projects consuming the pipeline exceeds five and the per-release `--target` cost becomes measurable (operator reports skipping upgrades or running them out of order) — a batch-upgrade tool or a different distribution model becomes warranted.
* Claude Code introduces an officially-supported per-project command resolution that supersedes filesystem-copy installation (e.g. a manifest-based command registry) — the whole `--target` mechanism may become redundant.
* A second class of artefact under `bootstrap/` (currently only `commands/`) acquires per-project state — the directory-level boundary rule has to be re-examined to decide whether the new directory is also project-bound.

## Out of Scope

* **Automated migration of pre-existing `~/.claude/commands/`.** A scripted `rm` cannot distinguish operator customisations from stale shadows; the ADR documents the manual step and stops there. A future ADR may revisit this if a safe diff-based migration becomes feasible.
* **CI enforcement of `bootstrap/VERSION` bumps.** A linter that fails PRs touching `bootstrap/commands/` without a `VERSION` change is a logical follow-up but is not part of this decision; the issue tracker carries it as a separate ticket.
* **Source-advancement drift detection.** A `/feature` startup that compares the installed version against the live `bootstrap/VERSION` in the claude-mini repo (via env var, registry, or network call) is deliberately not part of this decision; the per-release `--target` cadence is the only mechanism in scope.
* **Batch upgrade across all consuming repositories.** A `--target-all` mode that reads a registry of installed projects is deferred until the project count justifies the registry's existence.
* **Conflict-resolution semantics between global and per-project commands.** This ADR removes the global copy entirely; the question of which copy wins when both exist is therefore undefined by design and will only become relevant if a future decision restores a global copy.

## Links

* Implements: issue #94 (per-project pipeline commands with semver drift detection)
* Related: `docs/principles.md §5` — *Scope инструмента ограничен явной установкой*; this ADR extends that principle from the commit-msg hook (`--hook-this-repo`) to slash commands (`--target`).
* Related: ADR-0009 (feature-branch-pr-flow) — establishes per-repo `/feature` invocation as the unit of work this isolation protects.
