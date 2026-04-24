# 0012. Keep shellcheck full-repo scan and eliminate pre-existing debt atomically

* Status: proposed
* Date: 2026-04-24
* Deciders: venil
* Tags: ci, tooling, quality, governance

## Context and Problem Statement

The `shellcheck` job in `.github/workflows/ci.yml` (lines 9–16) uses `ludeeus/action-shellcheck@master` with `scandir: './bootstrap'`. It scans all 11 shell scripts under `./bootstrap` on every PR and currently fails on both `warning` and `note` severity. The repository carries ~15 pre-existing violations across 6 files (listed below), so every recent CI run has failed — 10+ consecutive — including PRs touching only documentation. CI is therefore producing noise, not signal: contributors cannot distinguish "I broke something" from "I merged into a repo whose CI is already red". The decision is which mechanism restores signal without creating a permanent blind spot in the scanned surface.

Pre-existing debt inventory (target of this decision):

| File | Violations | Severity |
|---|---|---|
| `bootstrap/universal-setup.sh` | SC2088 (×4), SC2295 (×2), SC2016 | warning / info |
| `bootstrap/scripts/test-governance-hook.sh` | SC2034, SC2059 | warning / info |
| `bootstrap/scripts/mini-health.sh` | SC2015 (×2) | info |
| `bootstrap/scripts/mini-preflight.sh` | SC2059 (×2) | info |
| `bootstrap/scripts/test-commit-msg-governance.sh` | SC2059 | info |
| `bootstrap/skills/adr-author/scripts/next_adr_number.sh` | SC2010 | warning |

The `adr-needed` label on issue #41 confirms architectural significance: the decision defines long-term CI signal surface and introduces (or refuses to introduce) a tolerated-violation mechanism, which is a cross-cutting governance constraint.

## Decision Drivers

* **CI signal fidelity.** A red CI must mean the PR broke something. Pre-existing debt firing on every unrelated PR destroys the one-bit answer a CI job is supposed to deliver. Measurable: rate of CI failures attributable to PR changes vs. pre-existing state — target 100% attributable.
* **No permanent blind spots in the scanned surface.** Every `.sh` under `./bootstrap` must be validated on every build. Mechanisms that shield a file from CI until it is "touched again" convert passing CI into a lie about the debt files. Measurable: `shellcheck bootstrap/**/*.sh` must return exit 0 when run locally against `main` at any time.
* **Minimal third-party supply-chain surface on CI hot path.** Each additional GitHub Action pinned on the PR path is a point of compromise. The fewer actions in the shellcheck job, the smaller the supply-chain footprint. Measurable: count of distinct third-party actions invoked per PR.
* **Correctness-grade shellcheck warnings are real bugs, not cosmetics.** SC2088 (`~` not expanded inside quotes), SC2010 (`ls | grep` instead of glob), SC2034 (unused variable) are semantic defects. Leaving them under a suppression marker means shipping known bugs. Measurable: number of `warning`-level findings in `main` — target 0.
* **Project posture — «no half-measures».** `docs/principles.md` §1 *«Красные флаги вместо трейдоффов»* rules out neutral-tradeoff framings ("both are fine, pick one") when a clear answer exists. Any option that leaves permanent carveouts (inline disables, scope narrowing, severity lowering) is structurally a half-measure and must be justified against this principle, not smuggled past it.

## Considered Options

* **A — Scope CI to changed files only.** Replace `ludeeus/action-shellcheck` with `tj-actions/changed-files` + `shellcheck` invoked on the diff's `.sh` files.
* **B — Inline allow-list of existing findings.** Add `# shellcheck disable=SCxxxx` at each violation site; keep full-repo scan.
* **C — Fix all pre-existing debt; keep full-repo scan.** Repair all ~15 violations in a single atomic PR; keep the current action configuration; CI returns to green with no new mechanism.
* **D — Hybrid: fix `warning`-level items, suppress `info`-level inline.** Repair the 6 `warning`-level defects (real bugs); mark the ~9 `info`-level items with per-site `# shellcheck disable=`.
* **E — Set `severity: warning` in the existing action.** One-line YAML change: stop failing on `note`/`info`; continue failing on `warning`. Must be combined with C or D because 5 `warning`-level violations remain.

## Decision Outcome

Chosen option: **C — fix all pre-existing debt and keep the full-repo scan**, because it is the only option that simultaneously satisfies drivers #2 (no blind spots), #3 (no new third-party action), #4 (no suppressed real bugs), and #5 (no half-measure). Driver #1 (signal fidelity) is satisfied by every option except the status quo; it does not discriminate. Drivers #2 and #5 are load-bearing: A creates a permanent blind spot (debt files checked only on diff); B and D mark real defects as tolerated; E alone is incomplete and only becomes viable if stapled to C, in which case C's effect is doing the work and the severity knob is decorative.

Driver prioritisation: #2 and #5 exclude A, B, D, and E-alone. #3 breaks ties within the remaining candidates by rejecting A's new `tj-actions/changed-files` dependency. #4 confirms C over any option that retains `warning`-level findings under suppression. The cost of C — ~2–3 hours of upfront repair, atomic landing — is operational, not structural; the options it rejects pay in structure (blind spots, suppressed bugs, added dependencies) for equivalent operational savings.

Principle link: `docs/principles.md` §1 *«Красные флаги вместо трейдоффов»* — this ADR is the place where "it depends" is refused and a direct answer is recorded.

**Sequencing.** This ADR merges first as `proposed`. The repair PR cites `Implements docs/decisions/0012-shellcheck-ci-scope.md`, lands all fixes in one commit (or squashed PR) so CI transitions red → green atomically, and flips this ADR's status to `accepted` on merge. The repair PR does not modify `.github/workflows/ci.yml` — the action config is already correct; only the source files change. This matches project hard rule #1 (ADR-PR) and #3 (cross-ref in PR).

### Positive Consequences

* **CI signal is restored without a tolerance mechanism.** A green build after the repair PR means the full `./bootstrap` tree is clean, not that the checker was scoped around the dirty parts.
* **No new third-party action enters the PR hot path.** Supply-chain surface of the shellcheck job stays at one action (`ludeeus/action-shellcheck`).
* **Real bugs (SC2088, SC2010, SC2034) get fixed rather than catalogued.** The warning-level items are correctness defects; fixing them is value delivered, not tax paid.
* **The bar for future shell scripts is raised implicitly.** Once `main` is clean, any new violation is introduced by a specific PR and is attributable. No one inherits the "it was already red" excuse.
* **No carveout code artifact survives the repair.** No inline `# shellcheck disable=` markers, no `.shellcheckrc`, no allowlist file — nothing future auditors must distinguish "deliberate" from "forgotten".

### Negative Consequences

* **Atomic landing requirement creates a merge-queue bottleneck.** The repair PR must land as one unit; until it does, CI continues to fail on every other PR. Unrelated work is blocked or must be merged with failing CI acknowledged — both are ugly.
* **~2–3 hours of upfront work on files not otherwise being touched.** This is debt repayment in a sprint that did not budget for it, and it cannot be sliced across PRs without producing an intermediate red state.
* **Any regression in the fix itself blocks everyone.** If one of the 15 fixes introduces a behavioural change (e.g., changing `ls | grep` to a glob alters ordering in a script that depends on it), both the fix and the revert land on the hot path. There is no graceful degradation — CI is binary.
* **The bar for future contributors rises.** New shell scripts must pass shellcheck clean from the first commit. Contributors unfamiliar with SC2059/SC2295/SC2088 must learn them before their first CI-green PR. This is correct long-term but is real friction.
* **Next shellcheck version bump may reintroduce red.** When `ludeeus/action-shellcheck@master` updates to a shellcheck version adding new rule classes, existing clean code may produce new findings, and the "clean main" invariant breaks without warning. The action is pinned to `@master`, which amplifies this risk — a secondary decision (pin to a SHA or semver tag) is implied but out of scope here; flagged as a re-visit trigger.

## Pros and Cons of the Options

### A — Scope CI to changed files only

* Good, because zero-friction path to green CI: no debt files are repaired, no suppressions are added, clean PRs stay clean.
* Good, because new violations in *changed* files are still caught (whole file is shellchecked when it appears in the diff), so the check remains useful on the hot path.
* Bad, because the debt files are permanently shielded from CI until someone touches them. Files like `mini-health.sh` rarely change; their violations will ride along indefinitely. This is a structural blind spot, not a transitional state.
* Bad, because it adds a second third-party action (`tj-actions/changed-files`) to the PR hot path — expanding supply-chain surface for a problem caused by unfinished cleanup, not by tool scope.
* Bad, because it encodes a norm — "CI only checks what you wrote" — that propagates to future jobs (linters, type-checkers, test coverage) and becomes the default architectural answer to every "CI is slow/red" problem. A local fix with a global cultural effect.
* Bad, because it violates driver #5 («no half-measures»): it is the textbook half-measure — work around the symptom, leave the cause.

### B — Inline allow-list of existing findings

* Good, because it preserves the full-repo scan: every file is still read by shellcheck on every PR.
* Good, because each suppression is local and visible in the source; no global `.shellcheckrc` hides rules from future code.
* Bad, because it marks real correctness bugs (SC2088, SC2010, SC2034) as tolerated. Shipping known bugs under a comment is not governance.
* Bad, because per-site disables hide future real bugs of the same class. A `# shellcheck disable=SC2088` on one line silences that rule for that line forever, including after refactors that make the original excuse obsolete.
* Bad, because the suppression markers are permanent code artifacts that future auditors must read, understand, and decide whether to keep — turning a one-time cleanup into a recurring cognitive tax.

### C — Fix all pre-existing debt; keep full-repo scan

* Good, because it removes the cause, not the symptom — full-repo scan stays reliable and meaningful.
* Good, because it fixes real bugs (warning-level findings are semantic defects, not style opinions).
* Good, because no new mechanism, no new dependency, no new markers enter the codebase.
* Good, because it aligns with the project's «no half-measures» posture (principle §1) without further argument.
* Bad, because the fix must land atomically to avoid intermediate red state — creates a one-shot merge-queue bottleneck.
* Bad, because ~2–3h of upfront repair falls on whichever sprint picks up #41, regardless of original sprint plan.
* Bad, because a regression in the repair itself blocks all CI until fixed, with no fallback.

### D — Hybrid: fix warnings, suppress info-level inline

* Good, because it prioritises real bugs (the 6 warnings) over cosmetic findings.
* Good, because scope of inline suppressions is smaller than B (~9 markers vs. ~15).
* Bad, because it still leaves permanent `# shellcheck disable=` markers for ~9 findings — the same permanence cost as B, just quantitatively smaller.
* Bad, because some info-level findings are not purely cosmetic: SC2295 (missing quotes inside `${var#pattern}`) can alter pattern-matching behaviour. Blanket-suppressing "info" is not equivalent to "safe to ignore".
* Bad, because "partial fix + partial suppression" creates an ambiguous precedent: future contributors must guess whether a new finding deserves repair or a disable marker. C produces a simpler rule ("fix it"); D produces a judgement call on every finding.

### E — Set `severity: warning` in existing action

* Good, because it is a one-line YAML change requiring no source edits.
* Good, because it immediately drops the blocking count from ~15 to ~6 by ignoring `info`/`note` findings.
* Bad, because 5 warning-level findings still fail CI — E alone does not achieve green, it only reduces noise. It is incomplete by construction.
* Bad, because it permanently lowers the bar: `info`-level findings never fail CI in the future either, so new `info` findings accumulate invisibly.
* Bad, because combining E with C means C did the work and E is decorative; combining E with D compounds D's ambiguity (now the "tolerated" set is defined by severity knob, not by site-level decision).
* Bad, because the severity floor is a silent policy buried in workflow YAML, not a visible code-level statement of intent.

## Confirmation

1. **Local invariant: `shellcheck bootstrap/**/*.sh` exits 0 on `main` for 30 consecutive days post-merge.** Run as a local check or a scheduled CI cron. If any single run returns non-zero on unchanged code (not a diff-introduced finding), either the repair was incomplete or the action's shellcheck version drifted — reopen this decision.

2. **CI attribution check: zero shellcheck failures on PRs that do not modify `.sh` files over 30 days post-merge.** A PR touching only `docs/` or `.github/` that fails shellcheck is a signal that pre-existing debt has re-accumulated. Threshold: 0 such failures. ≥1 → reopen.

3. **No `# shellcheck disable=` markers appear in `bootstrap/**/*.sh` in `main`.** Grep-check, automatable. This is the structural invariant distinguishing C from B/D after the fact. If a future PR introduces such a marker without amending this ADR, it is a silent regression toward D and must be challenged in review.

## Re-visit Trigger

Decision is reconsidered if **any** of the following falsifiable conditions occur:

1. **`ludeeus/action-shellcheck@master` bumps to a shellcheck version that produces ≥5 new findings on previously clean `bootstrap/**/*.sh`.** This breaks the "clean main" invariant without a code change and forces a choice between re-fixing, pinning the action to an older SHA, or adopting A/B/D. Reopen and decide.

2. **The count of shell scripts under `bootstrap/` exceeds 30** and the atomic-fix model becomes operationally infeasible for future debt-repayment PRs. At that scale, A (scope-to-changed-files) becomes the pragmatic answer and the "no blind spots" principle must be explicitly renegotiated in a successor ADR.

3. **CI runtime of the shellcheck job exceeds 60 seconds on the PR hot path.** Currently the full scan is near-instant on 11 files. If it becomes slow enough to matter, A's argument (check only the diff) gains weight that it does not have today.

4. **A shellcheck finding in `main` is ignored via `--no-verify` or a forced-merge ≥3 times in 30 days.** Signals that the "fix atomically" model has collapsed in practice and a tolerance mechanism is being improvised in merge discipline instead of in the ADR. Reopen to formalise or abandon tolerance.

## Links

* Issue: [#41](https://github.com/Lenivvenil/claude-mini/issues/41) — CI design: scope shellcheck to changed files only, not full repo
* CI file: `.github/workflows/ci.yml` lines 9–16 (shellcheck job, unchanged by this decision)
* Principle: `docs/principles.md` §1 *«Красные флаги вместо трейдоффов»* — load-bearing for rejection of A/B/D/E as half-measures
* Related ADR: `docs/decisions/0011-git-level-governance-phase2.md` — same pattern of preferring installation/fix-at-source over path-based or configuration-based carveouts
* Shellcheck rule references: SC2088, SC2295, SC2016, SC2034, SC2059, SC2015, SC2010 — https://www.shellcheck.net/wiki/
