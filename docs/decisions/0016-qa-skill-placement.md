# 0016. Place `/qa` between `/implement` and `/review` as the advisory repair stage

* Status: accepted
* Date: 2026-04-26
* Deciders: Lenivvenil
* Tags: pipeline, tooling, qa

## Context and Problem Statement

Three consecutive PRs in the current sprint (#52, #55, #58) merged without new tests or runbook updates. The cause is structural, not operator inattention: `/implement` produces code, and `/review` is a read-only critic (per ADR-0007) that can only flag missing tests at SUGGEST severity — it cannot author them. Nothing in the canonical pipeline (`CLAUDE.md` "Feature pipeline") sits in the gap between code-written and code-reviewed and is permitted to write fixes. Issue #66 introduces `/qa` to close that gap; this ADR fixes its placement and behavioural contract before the skill is implemented.

The choice is architecturally significant: `/qa` is a new public slash command (new public API), it inserts a required pipeline stage that will be hard to remove inside six months, and it mutates the canonical feature pipeline declared in `CLAUDE.md`.

## Decision Drivers

* Test/docs gaps are structural, not discipline failures — enforcement must be wired into the pipeline, not into operator memory (`docs/principles.md` Directive 4: "Knowledge в инструментах, не в памяти").
* `/review` is intentionally read-only (ADR-0007); granting it write capability would void the separation-of-concerns guarantee that the critic does not modify the artefact it critiques.
* The repair window is *after* code is written and *before* an independent critic sees it — repair must not be folded into review.
* Failure mode must match the existing graceful-degradation pattern (ADR-0005): surface findings, do not block the pipeline. This aligns with `docs/principles.md` Directive 3, which scopes hard gates to high-risk changes and keeps low-risk advisory loops unblocked.
* The QA report has to land in the PR body so the test-coverage and docs-currency lines of Definition of Done (`docs/principles.md#definition-of-done`) are auditable by humans on review — a handoff mechanism is required, not optional. (This ADR is what introduces the `## QA` PR-body section as a DoD-supporting artefact; DoD itself is not amended here.)
* Step-count budget for `/feature` is governed by ADR-0014 (re-visit threshold = 20 steps); the placement decision must respect that envelope.

## Considered Options

* **Option A — Single `/qa` skill, both checklists (tests + docs), advisory failure mode, between `/implement` and `/review`.**
* **Option B — Two separate skills `/qa-tests` and `/qa-docs`, each its own pipeline step.**
* **Option C — Fold the test/docs check into `/review`, allowing `/review` to write fixes.**

## Decision Outcome

Chosen option: **Option A** — single `/qa` skill, two sub-checklists (tests, docs), advisory failure mode, slotted between `/implement` and `/review`.

Rationale anchored in drivers and principles:

* Option C is rejected categorically: it violates ADR-0007's read-only-critic invariant. A critic that can patch the diff it is critiquing cannot certify it.
* Option B doubles the pipeline interruptions for the same conceptual gate, working against ADR-0014's step-count discipline and the "minimal friction" intent of the centralized `/feature` orchestrator (ADR-0013).
* Option A localises the repair window in one stage, preserves `/review`'s purity, and adopts the advisory failure mode already proven in ADR-0005's Codex degradation path. This is the principled placement, not a compromise.

The ADR also fixes five behavioural contracts that must be explicit before implementation begins:

1. **Carve-outs are file-path based, not commit-message based**, because `/qa` runs *before* `git commit` and no commit message yet exists. Specifically:
   * **Docs-only** carve-out: every changed file matches `*.md`. When fired, Phase 2 (tests) is skipped.
   * **ADR-only** carve-out: every changed file matches `docs/decisions/NNNN-*.md`. When fired, *both* Phase 2 (tests) and Phase 3 (docs currency for non-ADR docs) are skipped.
   * **Precedence**: ADR-only is the more specific case and takes precedence — a pure-ADR PR satisfies both globs but is treated as ADR-only and never as Docs-only. Implementations must evaluate ADR-only first and short-circuit.
   * When any carve-out fires, the skip is recorded verbatim in `qa-report.md` with the matched glob and the file list.

2. **Escape-hatch wording is fixed and copy-pasted**, not paraphrased: `"No test harness for [shell scripts]. Escape hatch applied. Add ## QA section to PR body noting this before merge."` Fixed wording is the only way the escape hatch is auditable across runs.

3. **Test-harness reality**: this repository contains only shell scripts and has no `bats` (or equivalent) harness today. The escape hatch is **steady-state acceptable** for existing artefacts — the value of `/qa` in this repo's current state is concentrated in Phase 3 (docs currency), and forcing harness adoption now would block every feature on a side-quest. `/qa` *does* propose introducing `bats` only when a **new** `.sh` file is created with no corresponding test; for edits to existing scripts, the escape hatch stands. This narrow proposal is the only test-authoring `/qa` is permitted to do today.

4. **QA report handoff**: `/qa` writes `qa-report.md` to the repo root (analogous to the existing ephemeral `plan.md`). The `/feature` orchestrator (ADR-0013) gains a step "copy `## QA` section into PR body" that fires at `gh pr create` time, not earlier. The file is `.gitignore`-eligible; the operator must not commit it.

5. **Step-count check vs ADR-0014**: adding `/qa` brings `/feature` to ~13–14 steps. ADR-0014's re-visit threshold is 20 steps. No amendment to ADR-0014 is required by this change.

### Positive Consequences

* Test gaps and stale runbooks are caught before `/review` sees the diff, restoring the missing repair window structurally.
* `/review` remains a clean read-only critic; ADR-0007's invariant is preserved.
* The escape hatch is explicit and recorded in the PR body — silent gaps become impossible by construction.

### Negative Consequences

* One additional pipeline interruption per feature, paid on every run regardless of whether tests or docs were the gap.
* In a shell-script-only repo with no harness, Phase 2 (tests) routinely produces escape-hatch notices, creating a real risk of rubber-stamping the escape-hatch line as boilerplate.
* `qa-report.md` is a new ephemeral artefact at the repo root (joining `plan.md`); operators must remember not to commit it, and the `.gitignore` entry is now load-bearing.
* When `/qa` writes a test scaffold or runbook patch, `/review` subsequently reviews `/qa`'s output as if it were the operator's — provenance of the change is no longer self-evident from the diff. Reviewers must trust the QA report to attribute correctly.
* Fixing the escape-hatch wording is a maintenance liability: any change to the wording is a breaking change to consumers (grep tooling, future audit scripts).

## Pros and Cons of the Options

### Option A — single `/qa`, advisory, between `/implement` and `/review`

* Good, because it keeps `/review` read-only and ADR-0007 intact.
* Good, because one pipeline stage matches one conceptual gate (repair window), satisfying ADR-0014's step-count discipline.
* Good, because the advisory failure mode mirrors ADR-0005, so operators already know the surface-don't-block contract.
* Bad, because the operator now bears the cognitive load of two sub-checklists in one step (tests + docs); confusion about which sub-check fired is possible.
* Bad, because escape-hatch boilerplate becomes the default path in a shell-only repo, weakening the gate's signal-to-noise.

### Option B — two skills `/qa-tests` and `/qa-docs`

* Good, because each sub-checklist is independently composable and independently deferrable.
* Good, because failure attribution is unambiguous — `/qa-docs` failed means docs, full stop.
* Bad, because two new pipeline interruptions where one suffices; pushes `/feature` toward ADR-0014's 20-step ceiling for no semantic gain.
* Bad, because two ephemeral reports (or one shared report with two writers) doubles the handoff complexity to PR body.
* Bad, because the conceptual gate "repair window before review" is one thing; splitting it implies two gates exist when only one does.

### Option C — fold check into `/review`, give `/review` write powers

* Good, because zero new pipeline steps; the operator-visible surface area does not grow.
* Bad, because it breaks ADR-0007's read-only-critic invariant, the load-bearing structural guarantee of every reviewer agent in this repo.
* Bad, because a critic reviewing a diff it itself patched cannot certify the diff — the assurance `/review` is supposed to provide collapses.
* Bad, because future critics (security-reviewer, domain-reviewer) would face pressure to follow the same precedent, eroding the read-only category across the board.

## Confirmation

After merge, run `/feature 66` end-to-end on this very issue and verify all three:

1. The `/qa` step appears in `TodoWrite` between `/implement` and `/review`.
2. `qa-report.md` is produced at the repo root during the run.
3. The resulting PR body contains a `## QA` section copied from that report.

If any of the three is absent, the implementation has not satisfied the ADR and must not be marked accepted.

## Re-visit Trigger

Reopen this decision if **either** condition becomes true:

* Three or more consecutive feature runs produce escape-hatch notices with no test scaffolding written **and** no `bats` harness exists in the repo — the gate is rubber-stamping and `bats` adoption must be re-evaluated as a prerequisite, not an option.
* The `/feature` checklist reaches 18 steps or more (approaching ADR-0014's 20-step ceiling), at which point the cost of `/qa` as a discrete stage must be weighed against folding sub-checks back into adjacent stages.

## Links

* Related: ADR-0005 (advisory / graceful-degradation pattern — failure-mode model for `/qa`).
* Related: ADR-0007 (read-only critic principle — the invariant Option C would have broken).
* Related: ADR-0013 (centralized agent orchestration — `/feature` is the carrier for the new step).
* Related: ADR-0014 (step-count governance — budget envelope this ADR fits inside).
* Related: ADR-0015 (domain invariants in review — adjacent reviewer contract, unaffected).
* Closes: issue #66.
* Principles invoked: `docs/principles.md` Directive 3 ("Автоматизировать только низкорискованное" — advisory mode for low-risk gate), Directive 4 ("Knowledge в инструментах, не в памяти" — pipeline carries the gate, not memory), `docs/principles.md#definition-of-done` (QA section in PR body is DoD-supporting).
