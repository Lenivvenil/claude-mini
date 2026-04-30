# 0022. Deliver Hypothesis property-based testing into Python pet-projects via `--target` installer template

* Status: accepted
* Date: 2026-04-29
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: pipeline, testing, installation, qa, hypothesis
* Related issue: #118

## Context and Problem Statement

The `/qa` skill (ADR-0016) instructs the LLM to write example-based unit tests
during the pre-review stage of `FeatureRun`'s lifecycle. Example-based tests
catch the cases the model thinks of; they miss the input-space corners the model
never imagines. Issue #118 proposes Hypothesis property-based testing (PBT) as
the deterministic-tooling complement: a `conftest.py` registering three
Hypothesis profiles (`dev`, `ci`, `nightly`) plus a 6-step PBT prompt
(analyze → understand → propose → write → execute → triage, paraphrased from
arxiv 2510.09907 as cited in #118) folded into the `/qa` skill, with CI and
nightly cron jobs running the `ci` and `nightly` profiles.

The architecturally-significant question this ADR closes is **delivery**: how
does `bootstrap/templates/conftest.py` reach the **N** Python pet-projects
managed by this pipeline (currently two pilots, designed for growth)? The choice
fires ADR-0018's Re-visit Trigger #4 verbatim: *"A second class of artefact
under `bootstrap/` acquires per-project state — the directory-level boundary
rule has to be re-examined to decide whether the new directory is also
project-bound."* This ADR re-examines that boundary and extends it.

The decision meets `docs/principles.md#что-значит-архитектурно-значимо` on two
counts: it adds Hypothesis as a cross-cutting test-framework dependency for
every Python pet-project, and it widens `universal-setup.sh --target`'s public
contract from `.claude/`-only to also writing into the target repo root —
constraints that will be hard to remove inside six months once the second
pet-project consumes the template.

## Decision Drivers

* **Acceptance criterion #1 of issue #118 reads "activated".** Activation by
  mechanism scales with N pet-projects; activation by manual copy degrades as
  O(N) operator-discipline failures and converts the acceptance criterion into
  "documented how to manually activate," which is not Done.
* **Idempotency and drift-honesty over the new file category** — extension of
  ADR-0019: any new artefact `--target` writes must be detectable by `cmp -s`,
  must increment `DRIFT` on mismatch, and must surface in `--check`. A silent
  partial install on a Python project root is the same class of dishonesty
  ADR-0019 closed for `.claude/` artefacts.
* **Boundary clarity over dual-rule complexity.** ADR-0018's rule today is
  "everything in `bootstrap/commands/` is project-bound; everything else is
  global." The clean extension is "`bootstrap/commands/` and one named
  template under `bootstrap/templates/` are project-bound; the rest of
  `bootstrap/templates/` stays global (already copied to
  `~/.claude/templates/claude-mini/`)." Per-file enumeration of the new
  category, not a per-content rule, preserves ADR-0018's structural-boundary
  driver.
* **Principle 3 alignment** (`docs/principles.md` §3 "сначала детерминированный
  тулинг"). PBT is the canonical deterministic-tooling complement to
  example-based LLM-authored tests: Hypothesis explores input space the model
  did not enumerate, with no LLM tokens spent on each generated case.
* **Principle 8's 2-3× margin discipline** (`docs/principles.md` §8). The
  three profiles are not 1000×-overengineering; they map to three distinct
  expected loads — `dev` for sub-second feedback during edit cycles, `ci` for
  PR-gate confidence at every push, `nightly` for shrink-heavy rare-bug
  hunting on cron. The 10×-per-tier example-count ratio is the discovered
  curve across those three purposes, not a single use case scaled three
  times.
* **Reversibility within six months is one-way-difficult.** Once the second
  pet-project consumes a delivery mechanism, switching mechanisms requires
  every consuming repo to re-onboard. The choice locks in operationally
  even though the file is plain text.

## Considered Options

* **Option A — `bootstrap/templates/conftest.py` template, delivered via
  `universal-setup.sh --target <repo>` into the repo root** (chosen)
* **Option B — `bootstrap/templates/conftest.py` template, scaffolded by the
  `project-bootstrap` skill only; existing pet-projects copy manually**
* **Option C — Skip the template; only update the `/qa` skill prompt and
  `bootstrap/templates/ci-python.yml`**

## Decision Outcome

Chosen option: **Option A — extend `--target` to copy
`bootstrap/templates/conftest.py` into the target repo root, alongside its
existing `.claude/commands/` copy loop.**

The constraint that discriminates the three options is the verb in #118's
acceptance criterion: *"activated in pet-projects"*. Option C concedes the
criterion outright (plan §3 documents this honestly: partial delivery, not
Done). Option B reduces "activated" to "documented manual step," which
restores the operator-discipline failure mode `docs/principles.md` §1 forbids
("scope inferred from operator memory"). Option A is the only mechanism that
makes activation structural rather than disciplinary. With N pet-projects, the
discipline cost of B grows as O(N) opportunities to forget; the mechanism cost
of A grows as O(N) mechanical `--target` runs — already accepted by ADR-0018
and unchanged here.

The boundary-rule cost of Option A is real and named: this is the first
artefact `--target` writes **outside `<repo>/.claude/`**. The repo root
becomes a destination. ADR-0018's Re-visit Trigger #4 is fired and resolved
here by **named extension**: `bootstrap/templates/conftest.py` joins
`bootstrap/commands/*.md` as project-bound; every other file under
`bootstrap/templates/` (e.g., `ci-python.yml`, future templates) stays global
and reaches `~/.claude/templates/claude-mini/` via `--install`. The boundary
remains structural — by named-file enumeration, not by content inspection —
preserving ADR-0018's "no per-file judgement at runtime" guarantee. This rule
is by-name, not by-destination, on purpose: a future `bootstrap/templates/`
file destined for the repo root must not auto-inherit project-bound status;
it requires its own ADR amendment, identical to how a new
`bootstrap/commands/*.md` requires an ADR-0018-aware review.

ADR-0019's `--check`-after-install discipline extends without modification:
`copy_file()`-style semantics (`cmp -s`, drift-increment, `--force` to
overwrite) apply to the new destination identically.

**Side decisions closed by this ADR:**

1. **Worked-example doc location: `docs/runbooks/qa-pbt.md`.** Confirmed.
   This triggers the `docs-reviewer` gate per CLAUDE.md routing rules — that
   is the intended behaviour for a new operator-facing workflow, not a cost
   to mitigate.
2. **6-step PBT prompt provenance: paraphrased from issue #118's framing of
   the arxiv 2510.09907 abstract (analyze → understand → propose → write →
   execute → triage).** The full paper text was not retrieved at ADR-draft
   time. The "32% detection rate" claim from #118 is not encoded in the ADR
   or the runbook; if the paper is later read and the prompt drifts from its
   intent, the worked example must be re-aligned (Re-visit Trigger).
3. **Profile defaults `dev`=50, `ci`=500, `nightly`=5000 are accepted as-is
   from issue #118.** Rationale per Principle 8: each tier addresses a
   distinct expected load — `dev` ≈ sub-second edit-cycle feedback,
   `ci` ≈ PR-gate confidence in <30s wall-clock per property,
   `nightly` ≈ rare-shrink budget on cron, where minutes per property are
   acceptable. The 10×-per-tier example ratio is the discovered curve over
   three purposes, not a single load scaled 1000×; the 2-3× margin
   discipline applies *within* a tier, not across tiers serving different
   purposes.
4. **`bootstrap/templates/ci-python.yml` is modified in this PR**, not a
   follow-on. Splitting the CI exerciser from the template under test would
   ship a `conftest.py` with no automated proof it loads, violating the
   cohesion that ADR-0019 enforces between an installer change and its
   `--check`-able verification.

**Hypothesis profile-selection mechanism (constraint, not code).** Upstream
Hypothesis exposes `settings.register_profile(name, **kwargs)` and
`settings.load_profile(name)`; profile selection is **not** keyed off a
`HYPOTHESIS_PROFILE` env var natively. The `ci` profile is auto-loaded only
when the upstream-recognised `CI` env var is set. The `conftest.py` template
must therefore call `load_profile()` explicitly during pytest configuration,
reading whichever env var the implementation chooses (e.g., a project-local
`HYPOTHESIS_PROFILE`) and falling through to upstream auto-CI detection. This
is recorded so `/implement` does not invent the non-existent native env var;
exact code lives in the implementation PR, not this ADR.

**Reversibility:** mostly reversible, with friction. Reverting Option A
requires one of: (a) a new ADR superseding this and migrating all consumers
back to manual copy, or (b) leaving the template in place and dropping the
`--target` copy loop while accepting drift goes silent on existing installs.
Neither is destructive; both require operator effort proportional to the
pet-project count at revert time.

### Positive Consequences

* The acceptance criterion of #118 ("activated in pet-projects") is met by
  mechanism, scaling cleanly to N: each new pet-project gets one `--target`
  run and the template lands.
* The delivery mechanism is the same one ADR-0018 already established and
  ADR-0019 already taught to be drift-honest. No new public verb on
  `universal-setup.sh`; the surface widens by one named filename, not by a
  flag or subcommand.
* Hypothesis becomes the canonical PBT framework across the pipeline's Python
  surface — one cross-cutting choice locked in `docs/decisions/`, not a
  per-project re-litigation each time a project adds tests.
* The CI exerciser (`ci-python.yml`) and the artefact it exercises ship in
  one PR, so a regression in either surfaces inside the same review window
  rather than in an orphaned follow-on.

### Negative Consequences

* **First project-bound artefact whose destination is outside `<repo>/.claude/`.**
  Until now `--target` has written only to `<repo>/.claude/`; this ADR widens
  that to include the repo root for one named file. Future operators
  reasoning "if it's project-bound, look in `.claude/`" will be wrong about
  `conftest.py`. The discipline must be: `bootstrap/templates/conftest.py` is
  the named exception, documented here and in CLAUDE.md.
* **Hypothesis becomes a cross-cutting dev-dependency that every Python
  pet-project must declare.** `ci-python.yml` runs `uv sync --all-extras
  --dev`; if `hypothesis` is not in the target project's `pyproject.toml`
  dev-dependencies, the imported `conftest.py` raises at collection time.
  Operator must add `hypothesis` to each pet-project's `[dev-dependencies]`
  before or during `--target`; nothing in this ADR automates that addition.
* **Per-release `--target` discipline scales linearly with N pet-projects**
  — same cost ADR-0018 already accepted for commands. With this ADR,
  forgetting a `--target` run no longer just leaves an old command; it leaves
  an old `conftest.py` that may pin Hypothesis behaviour to outdated profile
  defaults. The drift check from ADR-0018's `pipeline-version` covers commands
  but does **not** cover `conftest.py` content drift in the same alarm path.
* **Nightly Actions-minutes cost is operator-borne and unbounded by this
  ADR.** `nightly` at 5000 examples runs on every consuming pet-project's
  GitHub Actions cron. With N projects and growing property counts, the
  Actions-minutes bill grows as O(N × properties × 5000). The 2-3× margin
  discipline applies *within* a tier; this ADR does not commit to a global
  budget across tiers and projects.
* **arxiv 2510.09907 prompt is paraphrased, not transcribed.** The paper
  text was not retrieved at ADR draft time. If a later reading shows the
  6-step structure is not what the paper specifies, both the `/qa` skill
  prompt and the worked example in `docs/runbooks/qa-pbt.md` must be
  rewritten — the misleading-runbook risk is real until the paper is
  cross-checked.
* **`/qa` carve-out behaviour interaction.** Today `/qa` carves out on
  prompt-artifact-only diffs. PRs touching both `bootstrap/commands/qa.md`
  and Python files (which will become more common once PBT is in regular
  use) fall through to Phase 1 — pre-existing behaviour, but the frequency
  rises after this ADR lands.

### Neutral

* `docs/runbooks/qa-pbt.md` adds one runbook to the corpus; `docs-reviewer`
  cost on the implementing PR is one extra review pass.
* `bootstrap/VERSION` bumps to a minor version on this PR (new template
  category under `--target`'s contract; ADR-0018 minor-bump rule).

## Pros and Cons of the Options

### Option A — `bootstrap/templates/conftest.py` delivered via `--target`

* Good, because activation is structural — operator runs `--target` once per
  pet-project and the template lands; no manual copy step survives in
  documentation as latent operator-discipline failure.
* Good, because it reuses ADR-0018's established mechanism and ADR-0019's
  drift-honesty contract; no new public flag, no new exit-code semantics.
* Good, because it scales to N pet-projects without redesign — the same
  one-line invocation per repo that already ships commands.
* Good, because the boundary extension (one named template file) is
  enumerable, surviving `domain-reviewer`-style audits without
  per-file-content judgement at runtime.
* Bad, because it widens `--target`'s destination contract from
  `<repo>/.claude/` to also `<repo>/` for one named file — the first
  outside-`.claude/` write, and a precedent that future templates must be
  weighed against.
* Bad, because per-release upgrade discipline now applies to `conftest.py`
  too: forgetting a `--target` after a profile-default change leaves the
  pet-project running stale settings, with no `pipeline-version`-style alarm
  on the file's content.
* Bad, because it does not solve the "Hypothesis missing from
  `pyproject.toml`" failure: the imported template raises at collection
  time, and that diagnosis is left to the runbook.

### Option B — `project-bootstrap` skill scaffolds, no `--target` copy

* Good, because `universal-setup.sh` does not change — one less script to
  re-verify against ADR-0019 contracts on this PR.
* Good, because `bootstrap/templates/conftest.py` still lives in the repo
  and is version-controlled; the only difference from A is the delivery
  path.
* Bad, because existing pet-projects get no automatic delivery — issue
  #118's "activated" reduces to "documented manual step," which violates
  `docs/principles.md` §1 (no operator-discipline-as-mechanism) and §5
  (scope is the fact of installation, not a runtime pattern).
* Bad, because with N pet-projects (design target, not 2), the manual-copy
  failure rate compounds: every pet-project added is one more place where
  the template might be forgotten or inconsistently edited.
* Bad, because the manual-copy artefact silently diverges from
  `bootstrap/templates/conftest.py` in the source repo — no drift detection
  exists for content the operator typed by hand.

### Option C — `/qa` prompt + `ci-python.yml` only, no template

* Good, because the highest-leverage change (the prompt that shifts LLM
  test-writing behaviour) lands without any installer-contract change.
* Good, because blast radius is minimal — `bootstrap/commands/qa.md` and
  `bootstrap/templates/ci-python.yml`, no new file category.
* Bad, because the `ci`-profile/`nightly`-profile pair has nowhere to be
  registered without a `conftest.py`; CI runs would have no profile to
  load and would fall back to Hypothesis defaults, breaking the profile
  contract from #118.
* Bad, because issue #118's first acceptance criterion ("conftest.py с тремя
  профилями") is explicitly not satisfied — this is documented partial
  delivery, not Done.
* Bad, because deferring the template to a later PR re-opens the
  delivery-mechanism question with the LLM behaviour already shifted —
  the change order maximises confusion in the meantime.

## Confirmation

After implementation lands on `main`, the following grep- and shell-executable
checks must all pass before the implementation PR merges:

1. **Template artefact exists in source.**
   `test -f bootstrap/templates/conftest.py` returns 0; the file syntax-compiles
   via `python3 -m py_compile bootstrap/templates/conftest.py`.
2. **Three profiles registered by name.** All three of these grep:
   `grep -q 'register_profile.*"dev"' bootstrap/templates/conftest.py`,
   `grep -q 'register_profile.*"ci"' bootstrap/templates/conftest.py`,
   `grep -q 'register_profile.*"nightly"' bootstrap/templates/conftest.py`.
3. **Profile-selection wired without inventing a non-existent upstream env
   var.** `grep -q 'load_profile' bootstrap/templates/conftest.py` returns 0
   — the template uses the supported API rather than a nonexistent upstream
   `HYPOTHESIS_PROFILE` env var.
4. **`--target` delivers the template idempotently.** A clean run of
   `./bootstrap/universal-setup.sh --target /tmp/test-pbt-proj` (against an
   empty directory) produces `/tmp/test-pbt-proj/conftest.py` byte-identical
   to `bootstrap/templates/conftest.py`. Re-running the same command reports
   `identical, skip` for `conftest.py` and exits 0 with `DRIFT=0`.
5. **`--target --check` surfaces drift on the new file category.** After
   step 4, edit `/tmp/test-pbt-proj/conftest.py` to differ from the source.
   `./bootstrap/universal-setup.sh --target /tmp/test-pbt-proj --check`
   reports the drift line in stdout naming `conftest.py` and finishes with a
   non-zero `DRIFT` counter in the warning summary. (Note: `--target --check`
   today exits 0 even on drift; the implementation PR may either preserve
   that contract — drift visible only via stdout — or extend it to exit
   non-zero. Either is consistent with this ADR; the implementation PR
   states which and updates ADR-0019 if it changes the exit-code contract.)
6. **`/qa` skill carries the 6-step PBT block.**
   `grep -q 'analyze.*understand.*propose.*write.*execute.*triage'
   bootstrap/commands/qa.md` returns 0 (or equivalent multi-line check); a
   prose section labelled "Phase 2.5 — Property-based testing" or similar is
   present.
7. **CI template exercises the `ci` profile.**
   `grep -q 'CI:' bootstrap/templates/ci-python.yml` (env var set by the
   workflow so Hypothesis auto-selects `ci`), and a separate cron job exists:
   `grep -q 'schedule:' bootstrap/templates/ci-python.yml` with the
   nightly schedule running the `nightly` profile.
8. **Runbook landed.** `test -f docs/runbooks/qa-pbt.md` returns 0; it
   contains at least one worked example referencing `register_profile` and
   one of the four PBT templates (round-trip, metamorphic, invariant,
   idempotence).
9. **Agent gates fired on the implementation PR.** `docs-reviewer` runs
   (triggered by the new runbook); `reliability-reviewer` runs because
   `bootstrap/` is touched (per CLAUDE.md routing). This ADR is in
   `accepted` status at the time the implementation PR opens.
10. **`bootstrap/VERSION` bumped.** `git diff main -- bootstrap/VERSION`
    on the implementation PR is non-empty; the bump is at least a minor
    version per ADR-0018 conventions.

If any check fails, the implementation does not match this ADR.

## Re-visit Trigger

Reconsider this decision when **any** of the following becomes true:

* **Pet-project count exceeds five** — ADR-0018's same threshold. At that
  count the per-release `--target` cost across both commands and the
  conftest.py template becomes measurable, and a batch-upgrade tool
  (`--target-all`-style) becomes warranted in a follow-on ADR.
* **Nightly Actions-minutes across consuming pet-projects exceed an
  operator-defined budget** (candidate threshold: > 60 minutes/month
  aggregate, or first month a billing alert fires). Then the `nightly`
  profile's 5000-example default is re-evaluated, or a sampling/quota
  mechanism enters scope.
* **Upstream Hypothesis introduces a native `HYPOTHESIS_PROFILE` env var**,
  or otherwise changes the profile-selection API (e.g., deprecates
  `load_profile`). The `conftest.py` template must adapt, and the
  selection-mechanism note in this ADR's Decision Outcome becomes obsolete.
* **arxiv 2510.09907 is read in full and the 6-step structure is found to
  diverge materially from the paper's intent.** The `/qa` skill prompt and
  `docs/runbooks/qa-pbt.md` worked example must be rewritten; this ADR's
  paraphrase note becomes a fix-required entry.
* **A second non-`.claude/` `bootstrap/templates/` file becomes project-bound**
  (e.g., a `Makefile` template, a `pyproject.toml` snippet template). The
  named-exception boundary rule from this ADR no longer scales — `--target`'s
  contract needs a third reformulation, possibly toward a manifest model
  (ADR-0008 re-visit trigger territory).

## Out of Scope

* **Adding `hypothesis` to consuming pet-projects' `pyproject.toml`.** The
  template assumes the dependency is declared by the operator; automating
  that edit would require either modifying foreign repo source files or
  introducing a manifest of declared dependencies, both of which exceed
  ADR-0018's structural-isolation guarantees.
* **Drift detection on `conftest.py` content** analogous to
  `pipeline-version` for commands. Out-of-scope for this ADR; deferred to
  the same future tooling that would address command-content drift
  (currently covered by `cmp -s` at install time but not at invocation
  time).
* **Migration of the existing two pilot pet-projects.** This ADR establishes
  the mechanism; the operator runs `--target` against each pilot once the
  implementation PR merges. No batch script is in scope.
* **CI-minutes budget enforcement.** The Re-visit Trigger names a candidate
  threshold; an actual budget-enforcement gate is not part of this ADR.
* **Cross-language extension.** This ADR scopes Hypothesis as the PBT
  framework for Python pet-projects only. Rust pet-projects, if any arrive,
  would need a separate decision (`proptest`, `quickcheck`, etc.).

## Links

* Implements: issue #118 — feat(verifier): wire Hypothesis property-based
  testing into `/qa` skill.
* Related: ADR-0018 (per-project command installation) — fires its
  Re-visit Trigger #4 and resolves it by named extension; reuses the
  `--target` mechanism.
* Related: ADR-0019 (installer post-run verification) — extends `--check`
  and drift-honesty to the new file category without modification.
* Related: ADR-0021 (nine-principle revision) — invokes Principle 3
  (deterministic tooling first) as the reason PBT belongs alongside
  example-based tests, and Principle 8 (2-3× margin within a tier) as the
  rationale for accepting the 50/500/5000 profile defaults.
* Related: ADR-0016 (`/qa` skill placement) — this ADR adds a phase to the
  skill defined there; the placement contract is unchanged.
* External: arxiv 2510.09907 — agentic property-based testing (Anthropic).
  Cited via issue #118; full paper text not retrieved at ADR draft time.
* External: Hypothesis settings / profiles documentation —
  `settings.register_profile`, `settings.load_profile`, upstream `CI` env
  auto-detection.
