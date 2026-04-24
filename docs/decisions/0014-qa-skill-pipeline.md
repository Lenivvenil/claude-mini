# 0014. Add `/qa` skill between `/implement` and `/review` to gate tests and docs

* Status: proposed
* Date: 2026-04-24
* Deciders: venil
* Tags: pipeline, governance, tooling, quality

## Context and Problem Statement

The canonical feature pipeline (`CLAUDE.md`) runs `/implement → /review → /codex-review → commit → PR`. In practice, code ships whose diff adds logic without a corresponding test and whose runbooks or `--help` text drift out of sync with observable behaviour. `/implement`'s Phase 3 mentions "run tests after every non-trivial change", but does not require tests to exist in the first place. `/review` scans the diff for a "Tests" category but treats missing tests as SUGGEST, not BLOCK, when the surrounding codebase lacks a harness. The Definition of Done in `docs/principles.md` is explicit ("unit-tests written; docs updated"), yet no stage in the pipeline owns the check before human review. The question is where to place that check — inside an existing stage, as a new stage, or as a pair of optional stages — and whether the check should block or merely surface.

**Why now:** In sprint 2026-04-24, three consecutive PRs (#52 shellcheck repair, #55 drift-hint fix, #62 subshell PATH fix) merged without a single new test and without runbook updates despite observable contract changes. All three passed `/review` and governance checks without generating a finding. The sprint produced a 4th fix (#58 json_deny sanitization) that did add a regression test, only because the advisor explicitly flagged the gap in a pre-done call — not because the pipeline required it. Four PRs exposing the same structural gap in one session is the triggering event for formalising a dedicated check.

## Decision Drivers

* **DoD enforcement coherence.** `docs/principles.md#definition-of-done` lists tests and docs as mandatory clauses, but no pipeline stage owns them. A DoD bullet with no owner in the automation path is a DoD bullet that gets skipped under deadline pressure.
* **Single-responsibility per stage.** `/implement` writes code; `/review` critiques code. Adding "also write tests and update docs" to either stage dilutes the responsibility of that stage and makes its prompt harder to keep concise and enforceable.
* **Advisory vs. hard block posture.** Some DoD clauses (commit format, issue-ref) are deterministic and deserve a hard block (ADR-0004, ADR-0011). "Is the docs update semantically correct?" is not deterministic — an LLM judgement at best. The pipeline must not pretend otherwise; the control must be honest about what it can and cannot mechanically enforce.
* **Escape hatch without silent bypass.** Projects without a test harness are a legitimate reality in this repo (bootstrap shell scripts, docs-only diffs). The control must admit exceptions without becoming noise — every exception must leave a trace the reviewer can see.
* **Observability of the gap.** Today there is no artifact on a PR that says "QA ran, here is what it found." Without such an artifact the operator cannot tell, post-merge, whether the absence of a test was a considered decision or an oversight.

## Considered Options

* **A: Expand `/implement` Phase 3** with explicit "write test + update docs" steps; no new skill.
* **B: New `/qa` skill** inserted between `/implement` and `/review`; `CLAUDE.md` pipeline updated; advisory output written to PR body as `## QA` section.
* **C: Gate inside `/review`** — `/review` emits a BLOCK finding if diff adds logic without tests and no `## QA` escape-hatch comment is present; no new skill.
* **D: Dual optional skills `/test` + `/docs`**, each invoked by the operator when relevant; not in canonical pipeline.

## Decision Outcome

Chosen option: **Option B — new `/qa` skill between `/implement` and `/review`**, because it is the only option that (i) gives the tests-and-docs check a single-owner stage with a concise prompt, (ii) produces an observable artifact on every PR (the `## QA` section) which supports the "knowledge in tools not memory" principle, and (iii) is honest about being advisory rather than a hard block — matching the LLM-judgement nature of the checks and preserving the ADR-0004/0011 convention that hard blocks are reserved for deterministic rules.

Driver prioritisation: Driver 1 (DoD ownership) eliminates A and D. A dilutes `/implement`'s single responsibility without giving the check a distinct artifact; D leaves ownership ambiguous — operator may or may not invoke the skills, recreating the original gap. Driver 2 (single-responsibility per stage) confirms elimination of A: adding "also write tests and docs" to `/implement` collapses two distinct responsibilities into one prompt. Driver 3 (advisory honesty) eliminates C: embedding a BLOCK-severity check inside `/review` requires mechanical detection of test adequacy across heterogeneous harnesses — false-positives are inevitable and the BLOCK label is devalued (same reasoning as ADR-0004's deterministic-block convention). Driver 4 (escape hatch with trace) is what B uniquely delivers: the `## QA` PR section is the auditable trace; Options A, C, and D have no equivalent observable artifact. Driver 5 (observability of gap) confirms B: a named `## QA` section on every PR is the observable artifact that makes the gap — and its resolution — machine-readable for weekly audit. No other option produces this artifact.

The `## QA` PR-body section has a minimal fixed schema so that downstream audit and `/review` can consume it without re-deriving signals: (a) **test verdict** — one of `present` / `scaffolded` / `waived-no-harness`; (b) **docs verdict** — one of `none` or a bulleted list of affected-doc paths with the proposed change; (c) **carve-out** — when a carve-out applies, a single line `skipped — <reason>` (e.g. `skipped — adr: commit`, `skipped — docs-only diff`, `skipped — chore(bootstrap/initial)`), and no (a)/(b) fields.

Accepted trade-off: B lengthens the pipeline from 7 stages to 8 and creates a second place where "are tests present?" is examined (the other is `/review`'s Tests section). This duplication is the same class of problem as ADR-0011 created between `pre-commit-governance.sh` and `commit-msg-governance.sh`. It is a cost, not a disqualifier — mitigated by making `/qa`'s output machine-readable (`## QA` block on PR) so `/review` can read it rather than re-derive it.

References: `docs/principles.md#definition-of-done` (tests and docs clauses); `docs/principles.md` §1 *«Красные флаги вместо трейдоффов»* (no "both are fine" — advisory over block is the honest answer for LLM-judgement checks); §3 *«Автоматизировать только низкорискованное»* (why `/qa` is advisory, not a hard block).

### Positive Consequences

* DoD's tests-and-docs clauses acquire a named owner in the pipeline; the "nobody runs it" failure mode is closed.
* Every PR gains a `## QA` section — an observable artifact that can be audited weekly without opening each diff. Supports directive 4 (knowledge in tools, not memory).
* `/implement` and `/review` prompts stay single-purpose and concise; resistance to prompt drift is preserved.
* Escape hatch for no-harness cases is explicit and auditable: the `## QA` section states the reason, it is not silent.

### Negative Consequences

* **Pipeline length grows 7 → 8 stages.** Friction on every feature compounds; operators may start skipping `/qa` under deadline pressure, re-creating the original problem through a different door.
* **Rule duplication with `/review`.** Both stages now touch "are tests present?" Changes to the rule must be made in both prompts synchronously. Failure — silent divergence, same class as ADR-0011's hook duplication.
* **Advisory without teeth.** Because `/qa` does not hard-block, a motivated operator can ignore its findings and push through. Contrasts with ADR-0004/0011 which deliberately chose deterministic enforcement. If `/qa` findings are ignored in practice on ≥30% of PRs, the stage is theatre.
* **`## QA` section is human-signal, not machine-enforceable.** Governance hook cannot verify that the section is truthful or even non-empty; it can at best verify presence. Contrast with ADR-0011 which specifically rejected `PR body says X` as a control surface.
* **Test scaffolding without harness conventions produces wrong-idiom tests.** If `/qa` writes a test where no existing test pattern exists, the test may use the wrong framework/structure and need rework. Mitigation: `/qa` prompt must require the skill to detect "no harness exists" and defer rather than guess.
* **Docs-update judgement is subjective.** "Does this runbook need updating?" has false-positives (noise) and false-negatives (missed drift) from any LLM. Over time, noise may erode operator trust in the signal.
* **Carve-out logic in the skill prompt is non-trivial.** `adr:` commits, docs-only diffs, `chore(bootstrap/initial)` must be recognised and skipped with a one-line `## QA: skipped — reason` instead of full output. Prompt complexity grows; carve-out list must be kept in sync with the governance hooks' own carve-out list.

## Pros and Cons of the Options

### A: Expand `/implement` Phase 3

* Good, because no new stage — pipeline length unchanged.
* Good, because the author of the code is closest to knowing which tests and docs are relevant.
* Bad, because it dilutes `/implement`'s single responsibility (writing code); prompt grows, coherence erodes.
* Bad, because there is no observable artifact on the PR — "did the author actually do the test/docs step?" cannot be audited without reading the diff.
* Bad, because the check has no named owner distinct from the code-author; in practice the author marks their own work, which is the pattern DoD explicitly tries to avoid.

### B: New `/qa` skill

* Good, because tests-and-docs check gets a single-owner stage with a focused prompt.
* Good, because `## QA` section on the PR is an observable artifact — supports weekly audit and directive 4.
* Good, because advisory posture matches the LLM-judgement nature of the check (honest about capability).
* Good, because carve-outs live in one place (the `/qa` prompt), visible and editable.
* Bad, because pipeline length grows 7 → 8; friction compounds.
* Bad, because rule duplication with `/review`'s Tests section — must be kept in sync.
* Bad, because advisory-only means the stage can be ignored by a motivated operator.

### C: Gate inside `/review` with BLOCK severity

* Good, because no new stage and the BLOCK severity gives teeth.
* Good, because `/review` already scans the diff — incremental cost is small.
* Bad, because BLOCK severity requires deterministic rules (per ADR-0004 convention); test-presence across heterogeneous harnesses is not deterministic, so false-positives are inevitable and the BLOCK label is devalued.
* Bad, because escape-hatch mechanism ("add `## QA` comment to skip") is indistinguishable from a password — anyone who knows the incantation bypasses the gate with zero scrutiny.
* Bad, because no separate artifact — the check and the broader review collapse into one block of findings, harder to audit separately.

### D: Dual optional skills `/test` + `/docs`

* Good, because separation of concerns is clean — each skill has one job.
* Good, because operators invoke only what is relevant — no wasted stages.
* Bad, because "optional" means "not in DoD's critical path" — the skills will be forgotten exactly when they matter most (under deadline pressure).
* Bad, because two new surfaces to maintain instead of one; each has its own prompt and carve-out list.
* Bad, because no forcing function for consistency across the two skills (`/test` might carve out bootstrap, `/docs` might not, silently).

## Confirmation

1. **PR-body audit over 30 days post-rollout.** Script traverses all feature-branch PRs merged to main in the last 30 days; counts how many contain a `## QA` section. Two thresholds with distinct meanings: (a) **Healthy operation:** ≥90% of non-carveout PRs have the section — skill is running consistently; (b) **Minimum acceptable:** ≥70% — skill runs most of the time, borderline (improve tuning, no formal reconsideration yet); (c) **Failure:** <70% (i.e. ≥30% missing) — skill is being systematically skipped, Re-visit Trigger #1 fires. The 70–90% band = borderline, not a Re-visit event. (Carve-outs excluded per the skill's own logic: `adr:` commits, docs-only diffs, `chore(bootstrap/initial)`.)

2. **Post-merge gap audit over 60 days.** For each PR that merged without a test where `/qa` flagged the gap, record whether a follow-up bug or fix-forward commit appeared within 30 days. Threshold: ≤2 such incidents over the 60-day window. More than 2 → advisory posture is insufficient, reconsider toward hard block in `/review` (option C).

3. **Noise rate of `/qa` findings.** Weekly sample of 5 PRs; the operator categorises `/qa` findings as actionable vs. noise (false-positive docs suggestions, irrelevant test scaffolds). Threshold: ≥60% actionable across a 4-week rolling window. Below → prompt is mis-tuned or the stage is not worth its friction cost.

## Re-visit Trigger

Decision is reconsidered if **any** of the following falsifiable conditions occur:

1. **Operator skips `/qa` on ≥30% of feature PRs over a 30-day window** (measured by absence of `## QA` section in non-carveout PRs). Signals that advisory posture is rejected in practice — move to Option C (hard block in `/review`) or drop the stage entirely.

2. **≥3 bugs reach main within 30 days in code paths where `/qa` ran and did not flag a test gap.** Signals that the skill's detection is too weak to justify its position in the pipeline. Either the prompt must be tightened or the stage removed.

3. **`/qa` and `/review` rule-duplication causes a silent drift incident** (e.g. `/qa` passes a diff that `/review` later blocks for missing tests, or vice-versa). Signals that the duplication cost has materialised. Either collapse the check into one stage, or formalise shared-prompt infrastructure.

4. **Claude Code introduces native pipeline-stage governance** (e.g. `settings.json` declares required stages before commit). Then `/qa` becomes a configuration entry rather than a custom skill, and the ADR's rollout decisions need updating.

## Links

* `docs/principles.md#definition-of-done` — tests and docs clauses, now owned
* `docs/principles.md` §1 *«Красные флаги вместо трейдоффов»*, §3 *«Автоматизировать только низкорискованное»*
* `docs/decisions/0004-governance-via-prehook.md` — deterministic-block convention this ADR deliberately does not follow
* `docs/decisions/0011-git-level-governance-phase2.md` — rule-duplication class of problem inherited here; also the "PR body text is not a control surface" stance this ADR partially accepts (observable artifact, not enforceable artifact)
* `bootstrap/commands/implement.md` — current Phase 3, scope trimmed by this decision
* `bootstrap/commands/review.md` — Tests section, to be reconciled post-rollout
* Issue #66 — originating AC (escape hatch, carve-outs, advisory failure mode); this ADR must merge before the `/implement` ticket that adds the `/qa` skill file to `bootstrap/commands/` and updates `CLAUDE.md`'s pipeline section
