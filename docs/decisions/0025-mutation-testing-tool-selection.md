# 0025. Adopt mutation testing on weekly cron with mutmut / Stryker / cargo-mutants

* Status: proposed
* Date: 2026-05-04
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: pipeline, verifier, testing, mutation-testing, ci, principle-3, principle-8
* Related issue: #134

## Context and Problem Statement

Tests written by an LLM exhibit a structural defect: they often re-encode the
training-data tutorial pattern rather than the behaviour the system under
test is supposed to exhibit. Line- and branch-coverage metrics do not catch
this — a "mirror test" can co-vary with its target perfectly while asserting
nothing meaningful. Mutation testing is the deterministic counter
(`docs/principles.md` §3): the tool perturbs the source (flips `+` to `-`,
inverts a comparator, deletes a `return`) and re-runs the suite; if no test
fails on the mutant, the tested behaviour is not actually under test, even
when coverage is 100%. arxiv 2503.08182 documents this LLM-test failure mode
empirically; mutation testing is the only deterministic instrument that
surfaces it.

This ADR closes the architecturally-significant choices that must be locked
before `/implement` on issue #134:

1. The **cadence** — when does mutation testing run (per-PR, nightly,
   weekly).
2. The **per-language tool** — Python, TS/JS, Rust.
3. The **score thresholds** committed as the gate baseline.
4. The **delivery mechanism** — workflow lives in claude-mini's
   `.github/workflows/` plus a `bootstrap/templates/mutation.yml` shipped
   via `--target`.

The decision meets `docs/principles.md#что-значит-архитектурно-значимо` on
two counts. First, three new infrastructural components enter the pipeline
at once (mutmut, Stryker, cargo-mutants) — the ADR-trigger criterion
"выбирается инфраструктурный компонент" fires three times. Second, the
chosen mutation-score targets (≥80% goal, ≥60% gate) become the
cross-cutting baseline across every consuming pet-project; raising either
later requires every consumer driven to the baseline to be re-baselined,
satisfying "принимается ограничение, которое будет трудно снять через
6 месяцев."

`docs/synthesis/2026-04-29-pipeline-restructuring.md` (Раздел B, ticket
#17) carries the rationale and tool-selection inputs for this decision but
is not itself a decision record — it has no Considered Options table, no
Consequences section, no Confirmation, no Re-visit Trigger. Per Principle 4
(`docs/principles.md` §4), the source of truth for decisions is
`docs/decisions/`. This ADR consumes the synthesis as input and produces
the durable artefact.

## Decision Drivers

* **Principle 3 — deterministic tooling first.** Mutation testing IS the
  deterministic instrument for "does this test actually test behaviour."
  The principle is not invoked as window dressing; it is the *reason*
  mutation testing belongs in the verifier suite at all. No LLM tokens are
  spent per mutant — the gate runs without an agent loop.
* **Principle 8 — 2-3× margin, not 1000×.** Cadence sizing is governed by
  this principle: per-PR mutation testing on every commit is the 1000×
  failure mode (40+ minutes of CI per push for a marginal latency
  improvement on signal); weekly cron with `--in-diff` scoping is the 2-3×
  margin choice (signal preserved, cost bounded). Industry consensus —
  Henry Coles (Pitest author), Google "Practical Mutation Testing at
  Scale" (arxiv 2102.11378), nexocode case-report — converges on this
  cadence.
* **Principle 9 — perehvat / human-runnable continuity.** The workflow
  must be runnable without an LLM session. `workflow_dispatch` is wired
  alongside `schedule:` so the operator can re-trigger from the GitHub
  UI or `gh workflow run mutation.yml` during any LLM outage.
* **Principle 4 — knowledge in repo, not in model memory.** Surviving
  mutants that recur across weeks signal a pattern that the LLM critic
  did not catch; per synthesis-doc ticket #7, `docs/anti-patterns.md` is
  the accumulator. The workflow surfaces survivors in the weekly issue;
  the *operator* decides whether a pattern repeats and warrants an
  anti-patterns entry. No automatic mutation of `docs/anti-patterns.md`
  (Principle 2 — Claude does not decide).
* **Principle 1 — no vague trade-offs.** The score gate is a hard number,
  not "high enough." 60% minimum / 80% goal is committed in plain text;
  raising or lowering requires a superseding ADR.
* **Reversibility within six months is one-way-difficult.** Once N
  pet-projects have been driven to the ≥60% mutation-score baseline,
  raising the gate requires every consumer to re-baseline. The choice
  locks in operationally even though every artefact is plain text.
* **SARIF output for GitHub Code Scanning integration.** None of the
  three tools ships native SARIF; the gate's machine-readable contract
  is provided via custom converter scripts in `bootstrap/scripts/`. This
  is a real cost (named under Negative Consequences) but the absence of
  SARIF would forfeit Code Scanning's annotation surface entirely.

## Considered Options

The architecturally load-bearing axis is **cadence**. The three options
below are architecturally distinct: each implies a different cost
structure, a different signal latency, and a different relationship with
the rest of the pipeline.

* **Option A — Per-PR run** on every push to a feature branch.
* **Option B — Weekly cron on `main` with `--in-diff` scoping** (chosen).
* **Option C — Nightly cron on `main`.**

The other three points (per-language tool selection, score thresholds,
delivery mechanism) are dependent decisions: each is settled inside the
chosen cadence (Option B) and recorded as a side decision in Decision
Outcome below. They do not get full Pros-and-Cons treatment because
their alternatives are not architecturally distinct from the chosen
option — they are parameter choices on the chosen mechanism.

## Decision Outcome

Chosen option: **Option B — weekly cron on `main` (Sunday 00:00 UTC)
with `--in-diff` scoping for incremental Rust runs.**

The constraint that discriminates the three cadences is Principle 8.
Per-PR mutation testing is the 1000× failure mode: 20-40 minutes of CI
per push, applied to every diff regardless of whether the diff actually
warrants the analysis, for a signal that does not change materially when
delivered weekly. Henry Coles (Pitest author) and Google's
"Practical Mutation Testing at Scale" (arxiv 2102.11378) both publish
this conclusion explicitly: per-PR is an industry anti-pattern, not a
strict-mode aspiration. Nightly cron (Option C) is closer to right-sized
but pays 7× the CI cost of weekly with no proportional signal gain on
solo / pet-project cadence — the typical week sees zero or one merges
to `main`, so most nightly runs would be no-ops on unchanged code.
Weekly + `--in-diff` is the 2-3×-margin choice: signal preserved on
the week's actual merged code, cost bounded to one run per week per
language present.

**Side decisions closed by this ADR:**

1. **Per-language tool selection.** The chosen tools (mutmut, Stryker,
   cargo-mutants) are mandated by the task brief on issue #134 and by
   the synthesis document
   (`docs/synthesis/2026-04-29-pipeline-restructuring.md` §A.1, ticket
   #17). The synthesis evaluation (consumed as input here, not
   re-litigated) identified no maintained equivalent alternative for any
   of the three languages at the time of writing. Maturity claims about
   rejected alternatives below are inherited from the synthesis source,
   not independently re-verified at ADR draft time; if the synthesis
   evaluation is later found to have been wrong about an alternative's
   status, the Re-visit Trigger covers it.

   * **Python — mutmut v3+ over cosmic-ray and mutpy.**
     * mutmut v3: Good — single-binary `pip install mutmut`, supports
       `--paths-to-mutate` scoping, lowest install-friction surface.
       Bad — no native SARIF; requires mypy post-filter for type-invalid
       mutants (AST-valid but semantically invalid mutations pollute
       the survived count).
     * cosmic-ray: Good — more configurable, supports parallel workers.
       Bad — Celery worker model and multi-process orchestration are
       overkill for solo/pet-project scale; install surface significantly
       heavier. Per synthesis evaluation.
     * mutpy: Bad — evaluated and not recommended in synthesis source
       on maintenance grounds (judgement inherited, not re-verified at
       ADR draft time; Re-visit Trigger covers staleness).
   * **TS/JS — Stryker over vitest-mutation and jsmutate.**
     * Stryker: Good — stable thresholds API (`break/low/high`), HTML
       reporter, plugin model integrating with jest/vitest/mocha, active
       maintenance. Bad — no native SARIF; heredoc config required.
     * vitest-mutation: Good — native Vite integration if project uses
       Vite. Bad — experimental at synthesis-evaluation time; limited
       threshold API. Judgement inherited, not re-verified.
     * jsmutate: Bad — evaluated and not recommended in synthesis source;
       narrower ecosystem support. Judgement inherited, not re-verified.
   * **Rust — cargo-mutants v27+ over mutagen and "no Rust".**
     * cargo-mutants: Good — single-binary via `cargo install`,
       supports `--in-diff DIFF_FILE` (PATH argument, basis for
       weekly-incremental scoping), actively maintained. Bad — no native
       SARIF; JSON output requires converter.
     * mutagen: Bad — evaluated and not recommended in synthesis source
       on maintenance grounds. Judgement inherited, not re-verified.
     * No Rust mutation testing: Bad — claude-mini's own scripts are
       shell, but consuming pet-projects may include Rust (e.g., RTK is
       a Rust binary); unconditionally skipping Rust forces a follow-on
       ADR at the first Rust consumer. Rejected.

   Selection criteria common to all three (per synthesis source):
   actively maintained at evaluation time, single-command install,
   machine-readable output (JSON minimum, SARIF after custom
   conversion), supports incremental scoping (paths or `--in-diff`).

2. **Score thresholds: ≥80% target, ≥60% gate.**

   The gate is binary: a mutation score below 60% blocks (the workflow
   marks the weekly issue with a 🔴 status); 60-80% is yellow (🟡 —
   visible but not blocking); ≥80% is green (🟢). The 60% floor and
   80% target are taken from the synthesis document
   (`docs/synthesis/2026-04-29-pipeline-restructuring.md` §A.1) which
   cites them as cross-tool industry consensus. Per Principle 8, these
   are pet-project-grade margins, not banking-grade — banking code might
   want ≥90% gate, but at 60% the threshold is recognisable as the
   "industry-default" mutation-score floor below which the suite is
   provably under-asserting.

   Note on Stryker threshold alignment: Stryker's `break: 50` (the
   value that causes Stryker itself to exit non-zero) and the 60% gate
   enforced by `mutation-summary.sh` are **different enforcement layers**.
   `break: 50` is Stryker's own low-water mark that prevents Stryker
   from silently producing a vacuous run; the 60% gate is the
   cross-language policy enforced by the summary script's 🔴/🟡/🟢
   logic. Both thresholds are intentional: Stryker's `break: 50`
   catches catastrophic regressions within the Stryker run itself;
   `mutation-summary.sh`'s 60% catches cross-language policy violations
   in the weekly summary. There is no conflict.

3. **Delivery mechanism: dual-location.** The workflow lives in
   claude-mini's own `.github/workflows/mutation.yml` *and* in
   `bootstrap/templates/mutation.yml`. The first satisfies the
   "eat your own dog food" Principle-4 test — claude-mini's reference
   implementation runs on its own CI. The second is the artefact
   delivered via `--target` to consuming pet-projects. Both files are
   the same conditional-skip workflow (Approach A in plan.md §3).
   This is the **third** non-`.claude/` file delivered via `--target`
   — see Boundary-rule extension below.

4. **Conditional skip per language.** The workflow detects `.py`, `.ts`/
   `.tsx`/`.js`/`.jsx` (with `package.json` present), and `.rs` files in
   the repo. Each language block runs only if its detection step finds
   files. claude-mini itself (no `src/`, mostly bash + markdown) will
   skip all three blocks on its reference run; this is intentional —
   the reference implementation exists to prove the conditional logic
   works on a live CI run, not to produce mutation results for
   claude-mini code.

5. **`--in-diff` scoping is Rust-only.** mutmut v3 does not have a
   stable `--in-diff` equivalent (mutmut's incremental support is via
   `mutmut results --paths` filtering, not native diff scoping); Stryker's
   `--mutate` flag accepts globs but not git-diff input directly. Only
   cargo-mutants exposes a documented `--in-diff DIFF_FILE` argument.
   Python and TS/JS runs scope by `--paths-to-mutate src/` (mutmut) or
   `mutate: ["src/**/*.ts"]` (Stryker config); both run the full
   project's `src/` weekly, accepting the higher cost as the price of
   not having native diff scoping in those tools.

6. **SARIF conversion via custom Python scripts.** None of mutmut,
   Stryker, cargo-mutants emit SARIF natively. Three converters live
   under `bootstrap/scripts/`: `mutmut-to-sarif.py`,
   `stryker-to-sarif.py` (if Stryker JSON proves insufficient), and
   `cargo-mutants-to-sarif.py`. SARIF schema 2.1.0 is the target.
   First converters produce minimal-viable SARIF (file/line annotations
   for survivors) without rich rule metadata; richer annotations are
   deferred to a follow-on issue.

7. **Surviving mutants → `docs/anti-patterns.md` is operator-driven,
   not automatic.** The weekly issue lists survivors with file/line
   context; the operator decides whether a recurring pattern warrants
   an anti-patterns entry. Principle 2 (Claude does not decide) bars
   automatic mutation of `docs/anti-patterns.md`.

8. **Stryker config location: heredoc emission.** The Stryker
   thresholds (`break: 50, low: 60, high: 80`) and `mutate` glob are
   emitted by the workflow via a heredoc into a per-run `stryker.conf.json`
   in the runner's working directory; no `bootstrap/templates/stryker.conf.json`
   is added. This keeps the named-exception count at **six** and avoids
   widening the template surface. Plan.md §2 does not list
   `stryker.conf.json` as a new template file, which is consistent with
   this choice. A future ADR may move thresholds to a versioned template
   file if consumer projects need to override them independently; that
   would push the count to seven and require a Re-visit Trigger update.

**Boundary-rule extension (ADR-0022 Re-visit Trigger #5 fires).**
ADR-0022 established the named-exception rule for non-`.claude/`
`bootstrap/templates/` files (`conftest.py`). ADR-0023 extended that list
by four (`ruff.toml`, `.eslintrc.json`, `.jscpd.json`,
`.semgrep/llm-antipatterns.yaml`). This ADR adds the **sixth**:
`bootstrap/templates/mutation.yml`, destined for `<repo>/.github/workflows/`
on `--target` install. The boundary rule remains structural by
named-file enumeration; the destination is `<repo>/.github/workflows/`
rather than the repo root, which is itself a new sub-destination. The
named-exception list is now: `conftest.py` (repo root), four config
files (repo root or `.semgrep/`), and `mutation.yml`
(`.github/workflows/`). At six named exceptions across three
destinations, the per-file enumeration is approaching the friction
boundary at which a manifest model becomes the cleaner abstraction —
this is named in the Re-visit Trigger as falsifiable signal. Side
decision 8's optional `stryker.conf.json` would push the count to seven
if adopted.

**Reversibility.** Mostly reversible with friction. Reverting requires
either (a) a superseding ADR removing mutation testing entirely and
withdrawing the workflow from consuming pet-projects, or (b) keeping
the workflow but switching cadence (e.g., to monthly) via a superseding
ADR plus `--target` re-runs. Neither is destructive; both incur
operator effort proportional to consuming-pet-project count.

### Positive Consequences

* `docs/principles.md` §3 is honoured: a class of test-quality defect
  that LLMs structurally produce (mirror tests with high coverage but
  zero assertion power) is caught by deterministic tooling rather than
  re-discovered by an LLM critic.
* The same `mutation.yml` is callable from the CI cron, from the
  GitHub UI (`workflow_dispatch`), and from the operator's shell
  (`gh workflow run`) — Principle 9 is satisfied without an
  LLM-only branch.
* Score thresholds are committed in plain text in `stryker.conf.json`
  (or workflow heredoc per side decision 8), in `mutation.yml` step
  arguments, and (for Python) in `mutation-summary.sh` gate logic;
  raising or lowering is a visible PR diff, not a config drift.
* Surviving mutants surface in a weekly GitHub issue with file/line
  context and a uninitiated-reader preamble (per plan.md §4); a new
  contributor or the operator-six-months-later can read the issue and
  understand both the metrics and the action.
* Anti-patterns accumulation has a structural source (weekly issue) for
  the operator to review, instead of relying on intra-session memory.
* The reference implementation runs on claude-mini's own CI, proving
  the conditional-skip logic works on a live workflow before
  pet-projects consume the template.

### Negative Consequences

* **Custom SARIF converters for all three tools.** None of mutmut,
  Stryker, cargo-mutants emit SARIF natively. Three converters
  (`mutmut-to-sarif.py`, `stryker-to-sarif.py`,
  `cargo-mutants-to-sarif.py`) become long-lived maintenance debt under
  `bootstrap/scripts/`. Upstream output-format changes break the
  converters silently unless a schema-validation test runs in CI.
  Mitigation: SARIF 2.1.0 schema validation in CI; first converters
  ship minimal annotation richness (file/line only) with richer
  metadata deferred to a follow-on.
* **Issue accumulation: 52 issues/year per consuming pet-project.**
  The weekly issue with `type:mutation-report` label is appropriate
  for pet-project scale today (manual close after triage) but at N
  pet-projects it produces 52×N issues/year. No automatic close-old
  logic in this ADR; deferred to a follow-on if the noise becomes
  measurable. Risk #7 in plan.md acknowledged here as
  architectural-adjacent.
* **Three new cross-cutting infrastructure dependencies** —
  mutmut (Python), Stryker (Node), cargo-mutants (Rust). Each has its
  own upstream cadence; output-format stability across versions is not
  guaranteed. Drift across consuming pet-projects is possible until
  pinning is added in a follow-on.
* **mypy-filter for Python invalid mutants is slow.** Each survived
  mutmut mutant requires a separate `mypy` invocation to check
  type-invalidity; on a project with hundreds of survivors this is
  minutes of additional CI time. `xargs -P4` parallelism mitigates
  but does not eliminate; `timeout-minutes: 30` on the Python step
  caps the worst case.
* **Weekly cron Actions-minutes cost is operator-borne and unbounded
  by this ADR.** Each consuming pet-project pays one mutation run per
  week across all detected languages. With N projects and growing
  source-tree size, the bill grows as O(N × LOC). The Re-visit
  Trigger names a falsifiable threshold; this ADR does not commit
  to a global Actions-minutes budget.
* **Sixth named exception under ADR-0018 boundary rule.** The
  per-file enumeration list (`conftest.py`, four config files,
  `mutation.yml`) is approaching the point at which a manifest
  abstraction becomes cleaner than a hand-edited list. This ADR
  pushes the count to six (or seven if side decision 8 adopts the
  template path) and names the friction in the Re-visit Trigger;
  future template additions will need either continued enumeration
  or a manifest follow-on.
* **First template destined for `<repo>/.github/workflows/`** rather
  than the repo root or `.claude/`. ADR-0018's destination model
  widens to a third sub-destination. Future operators reasoning
  "if it's project-bound, it's in `.claude/` or repo root" will be
  wrong about `mutation.yml`. The discipline must be: documented
  here and in CLAUDE.md.
* **`--in-diff` only on Rust.** Python and TS/JS runs scope by
  `--paths-to-mutate src/` and full Stryker config respectively;
  weekly run cost on those languages does not scale down on weeks
  with small diffs. This is a tool-capability gap, not a design
  choice; the Re-visit Trigger names the upgrade path.
* **Reference run on claude-mini produces an empty-table issue.**
  claude-mini has no `src/` and will skip all three language blocks;
  the weekly issue body will read "Languages with production code
  not detected — run skipped." This is intentional (proves the
  conditional logic on live CI) but is one more issue/week of
  operator-noise on the parent repo. A `paths:` filter on the
  workflow could suppress, but `paths:` does not apply to
  `schedule:` triggers — accepted as cost.
* **Maturity claims about rejected alternatives are inherited from
  the synthesis source, not re-verified at ADR draft time.** Per
  side decision 1, judgments that mutpy / vitest-mutation / jsmutate /
  mutagen are unmaintained or experimental travel from the synthesis
  evaluation; if any of those alternatives has shipped a maintained
  release since the synthesis was written, the rejection rationale
  is stale. Re-visit Trigger covers it.

### Neutral

* `bootstrap/scripts/` gains four new files (`mutmut-to-sarif.py`,
  `cargo-mutants-to-sarif.py`, `mutation-summary.sh`,
  `test-mutation-summary.sh`) plus `filter-mypy-invalid.py`.
  ADR-0012's shell-script-as-pipeline-gate pattern under
  `bootstrap/scripts/` is reused; no new public verb on
  `universal-setup.sh`.
* `bootstrap/VERSION` bumps a minor version on the implementation PR
  (new template under `--target`'s contract; ADR-0018 minor-bump
  rule).
* `docs/anti-patterns.md` does not gain entries on this PR; entries
  appear iff and when the operator triages a recurring survivor
  pattern from a future weekly issue.

## Pros and Cons of the Options

### Option A — Per-PR run on every push

* Good, because feedback latency is minimal — surviving mutants
  surface within minutes of the push that introduced them.
* Good, because every change is gated; nothing slips to `main`
  without mutation analysis.
* Bad, because per-PR mutation testing is an industry-cited
  anti-pattern (Henry Coles / Pitest, Google arxiv 2102.11378,
  nexocode case-report) — 20-40 minutes of CI per push for a signal
  that does not materially change vs. weekly delivery.
* Bad, because Principle 8 (2-3× margin) is violated structurally:
  the cost is 7-30× the weekly equivalent for a marginal latency
  gain on signal that is not latency-critical.
* Bad, because CI minutes consumed scale linearly with PR volume;
  a busy week of small PRs (formatting, doc fixes) pays the full
  mutation cost on each, with no signal value because the diffs
  don't include source code.
* Bad, because operator becomes trained to bypass (`--no-verify`,
  `[skip ci]`) when latency frustration peaks; the gate's signal is
  lost not because it is wrong but because it is annoying.

### Option B — Weekly cron on `main` with `--in-diff` scoping (chosen)

* Good, because cost is bounded to one run per week per language
  present in the repo — the architecturally honest cadence per
  industry consensus.
* Good, because the signal is preserved: `--in-diff` (Rust) and
  full-`src/` scans (Python, TS/JS) cover the week's merged changes,
  which is the unit of analysis that matters for "did the tests
  catch what merged."
* Good, because `workflow_dispatch` makes the workflow callable on
  demand without an LLM session — Principle 9 is satisfied without
  reshaping the cron model.
* Good, because the weekly issue cadence matches the operator's
  triage rhythm; weekly review of one issue is ~5 minutes, and
  recurring-pattern detection (the input to `docs/anti-patterns.md`)
  needs multi-week observation anyway.
* Bad, because feedback latency on a freshly-introduced mirror test
  is up to 7 days; a regression that shipped on Monday is not
  surfaced until Sunday.
* Bad, because `--in-diff` only works on Rust today; Python and
  TS/JS scope by `--paths-to-mutate` / Stryker config and pay full
  `src/` cost regardless of week's diff size.
* Bad, because Sunday 00:00 UTC may collide with other weekly cron
  jobs across the GitHub Actions account; staggering across multiple
  workflows is operator's responsibility.

### Option C — Nightly cron on `main`

* Good, because feedback latency is bounded to ~24 hours, much
  better than weekly for catching regressions.
* Good, because nightly is closer to the cadence at which a
  high-velocity team would want mutation testing.
* Bad, because at solo / pet-project scale most nights see zero
  merges; ~80% of nightly runs are no-ops on unchanged code,
  paying full CI cost for zero signal change.
* Bad, because 7× the CI cost of weekly with no proportional
  signal gain at this cadence — Principle 8 violated structurally.
* Bad, because seven issues/week per pet-project (vs. one) multiplies
  the operator-noise problem by 7× with no compensating signal.
* Bad, because aggregating "did this week's merges hold up" requires
  the operator to manually combine seven nightly issues; the
  weekly-cadence option produces this aggregation natively.

## Confirmation

After implementation lands on `main`, the following grep- and
shell-executable checks must all pass before the implementation PR
merges:

1. **Workflow exists in claude-mini reference location.**
   `test -f .github/workflows/mutation.yml` returns 0;
   `actionlint .github/workflows/mutation.yml` (or equivalent
   YAML/Actions linter) returns 0.
2. **Workflow exists as `--target` template.**
   `test -f bootstrap/templates/mutation.yml` returns 0; the file is
   byte-identical to (or a documented diff of) the reference
   workflow.
3. **Cron schedule wired correctly.**
   Run the following shell commands; both must return 0:
   ```sh
   grep -q "cron: '0 0 * * 0'" .github/workflows/mutation.yml
   grep -q 'workflow_dispatch'  .github/workflows/mutation.yml
   ```
   The first grep matches Sunday 00:00 UTC schedule; the second
   confirms the manual `workflow_dispatch` trigger is present.
4. **All three language blocks present.** Each tool name appears as
   an invocation step in `mutation.yml`:
   `for t in mutmut stryker cargo-mutants; do
   grep -q "$t" .github/workflows/mutation.yml || exit 1; done`
   returns 0.
5. **Conditional skip on each language.** Each language block has
   a `detect-{python,js,rust}` step with `skip` output and a
   following `if: steps.detect-X.outputs.skip != 'true'` guard.
   `grep -q 'skip=true' .github/workflows/mutation.yml` and
   `grep -q "if: steps\.detect-" .github/workflows/mutation.yml`
   both return 0.
6. **`--in-diff` wired for Rust only.**
   `grep -q -- '--in-diff' .github/workflows/mutation.yml` returns 0
   on the cargo-mutants step; the same flag does not appear on the
   mutmut or Stryker steps.
7. **`fetch-depth: 0` on checkout** (required by `--in-diff` on Rust).
   `grep -q 'fetch-depth: 0' .github/workflows/mutation.yml`
   returns 0.
8. **SARIF converters exist and are syntactically valid.**
   `test -x bootstrap/scripts/mutmut-to-sarif.py` and
   `test -x bootstrap/scripts/cargo-mutants-to-sarif.py` return 0;
   `python3 -m py_compile` on each returns 0.
9. **mypy-filter helper exists.**
   `test -x bootstrap/scripts/filter-mypy-invalid.py` returns 0;
   the script invokes `mypy` and uses `xargs -P4` for parallelism.
10. **Markdown summary script exists with uninitiated-reader
    preamble.** `test -x bootstrap/scripts/mutation-summary.sh`
    returns 0; `grep -q 'mutation testing' bootstrap/scripts/mutation-summary.sh`
    finds the explanatory section; `grep -q 'mutation score'`
    finds the threshold-explanation section.
11. **Score-gate logic enforces 60% / 80% thresholds.**
    `grep -E '(60|80)' bootstrap/scripts/mutation-summary.sh` finds
    both numbers; the script emits 🔴 for <60%, 🟡 for 60-80%, 🟢
    for ≥80% (verifiable via fixture in
    `bootstrap/scripts/test-mutation-summary.sh`).
12. **Stryker thresholds wired via heredoc (side decision 8).**
    `bootstrap/templates/stryker.conf.json` does NOT exist (heredoc
    path chosen; named-exception count stays at six). The workflow
    emits thresholds inline; verify:
    ```sh
    grep -q '"break": 50'  .github/workflows/mutation.yml
    grep -q '"low": 60'    .github/workflows/mutation.yml
    grep -q '"high": 80'   .github/workflows/mutation.yml
    ```
    All three must return 0.
13. **Issue-creation idempotency.** The workflow calls
    `gh label create "type:mutation-report" --force` before
    `gh issue create`; the label-creation step is non-blocking
    (`continue-on-error: true` or equivalent).
14. **`--target` delivers the workflow.** A clean run of
    `./bootstrap/universal-setup.sh --target /tmp/test-mutation` on
    an empty directory produces
    `/tmp/test-mutation/.github/workflows/mutation.yml`
    byte-identical to `bootstrap/templates/mutation.yml`. Re-running
    reports `identical, skip` and exits 0 with `DRIFT=0`.
15. **`--target --check` surfaces drift on the new file.** After
    step 14, edit the target file to differ; rerun with `--check`
    reports the drift line in stdout naming the workflow file.
16. **Unit tests for `mutation-summary.sh` pass.**
    `bash bootstrap/scripts/test-mutation-summary.sh` exits 0;
    fixtures cover all four cases from plan.md §5 (Python score 85%,
    70%, 45%, no data).
17. **CI gate runs the unit tests.**
    `grep -q 'test-mutation-summary' .github/workflows/ci.yml`
    returns 0 (the test is wired into the existing `setup-dry-run`
    or equivalent job).
18. **Reference workflow runs successfully on claude-mini's CI.**
    A `workflow_dispatch` invocation on the implementation PR's
    branch completes in green; the resulting issue body contains
    "Languages with production code not detected" (or equivalent)
    confirming the conditional-skip path executed.
19. **Anti-patterns hand-off documented.** `mutation-summary.sh`
    output explicitly instructs the operator: "If a pattern recurs
    across weeks, add to `docs/anti-patterns.md`"; `grep -q
    'anti-patterns.md' bootstrap/scripts/mutation-summary.sh`
    returns 0.
20. **ADR is in `accepted` status when the implementation PR opens**;
    `bootstrap/VERSION` bump is non-empty in the implementation
    PR's diff against `main`.

If any check fails, the implementation does not match this ADR.

## Re-visit Trigger

Reconsider this decision when **any** of the following becomes true:

* **Any of the three tools ships native SARIF output.** mutmut,
  Stryker, or cargo-mutants ships a SARIF reporter in a stable
  release. The corresponding custom converter under
  `bootstrap/scripts/` is then deprecated in favour of the native
  reporter; the converter is removed in the same superseding ADR.
* **Weekly mutation Actions-minutes across consuming pet-projects
  exceed an operator-defined budget** (candidate threshold: > 90
  minutes/month aggregate, or first month a billing alert fires).
  Then the cadence (weekly), the scope (`--paths-to-mutate src/`
  for Python and TS/JS), or the per-tool filter logic is
  re-evaluated.
* **A consuming pet-project introduces a fourth language**
  (Go, Java, Kotlin, etc.). The tool-set choice is re-litigated:
  PIT (Java), gremlins-go (Go), or other appropriate per-language
  tool joins the workflow as a fourth conditional-skip block, or
  the operator declines mutation testing for that language with
  documented rationale.
* **Mutation score plateau below the 60% gate for four consecutive
  weeks on any consuming pet-project.** This is a process question,
  not a tool question — it signals either that the threshold is
  unrealistic for the project's domain (raise the gate's tolerance
  via a superseding ADR per side decision 2) or that test-writing
  practices need a different intervention.
* **The named-exception list under ADR-0018's boundary rule reaches
  eight entries** (currently six after this ADR; was five after
  ADR-0023, four after ADR-0022; would become seven if side
  decision 8 adopts the `stryker.conf.json` template path). The
  per-file enumeration becomes measurably more friction than a
  manifest-based abstraction; a follow-on ADR introduces the
  manifest model.
* **mutmut, Stryker, or cargo-mutants becomes unmaintained**
  (>18 months without a release, or upstream archival). The
  per-language tool selection is re-litigated against the then-current
  alternatives.
* **A rejected alternative ships a maintained release that
  invalidates the synthesis-inherited maturity claim** (e.g.,
  vitest-mutation reaches production-grade status, or mutpy
  resumes maintenance). The per-language tool choice is
  re-litigated for the affected language.
* **`bootstrap/scripts/` SARIF converter maintenance burden exceeds
  one fix per quarter** (upstream output-format changes break the
  converter, requiring schema-fix work). The converters become a
  net cost; native SARIF or skipping Code Scanning integration is
  reconsidered.
* **Two consecutive `/gate-audit` runs report the mutation-testing
  gate as ROI < 0.2** (per the operational rule in
  `docs/principles.md` "Gate ROI обязателен"). The gate is removed
  or restructured per the audit's recommendation.

## Out of Scope

* **Per-PR mutation testing.** Explicitly rejected per Decision
  Outcome and industry-cited rationale. Re-evaluation requires
  evidence that the cadence trade-off has shifted (e.g., upstream
  tools become 100× faster), not operator preference.
* **Automatic mutation of `docs/anti-patterns.md`.** Surviving-mutant
  triage is operator-driven (Principle 2). The workflow surfaces
  data; the operator decides what becomes an anti-pattern.
* **Tool version pinning across operator machines and consuming
  pet-projects.** Each tool's upstream cadence is independent;
  pinning would require a manifest mechanism per consuming
  pet-project. Deferred to a follow-on once drift is observed.
* **Issue lifecycle management beyond creation.** Auto-close of old
  weekly mutation issues, summary-of-summaries quarterly digest,
  and other issue-tree management tooling are deferred. Manual
  close after triage is the current contract.
* **Migration of existing pet-projects to the mutation-testing
  workflow.** This ADR establishes the mechanism; the operator runs
  `--target` against each pet-project once the implementation PR
  merges. No batch-migration tool is in scope.
* **Cross-language extension beyond Python / TS-JS / Rust.**
  Go, Java, Kotlin, Swift, etc. surfaces are out of scope. Adding
  a fourth language is named as a Re-visit Trigger.
* **Richer SARIF annotations.** First converters produce minimal
  file/line annotations for survivors. Rich rule metadata (mutation
  operator names, equivalence-class hints, suggested-fix snippets)
  is deferred to a follow-on issue.
* **Mechanical enforcement of the 60% gate via PR-blocking status
  check.** The gate marker (🔴) lives in the weekly issue body; it
  does not block PRs to `main` independently. Mechanical PR
  enforcement is a future consideration once the gate's stability is
  observed across multiple weeks.
* **Re-verification of synthesis-inherited maturity claims at ADR
  draft time.** Per side decision 1, judgments about rejected
  alternatives travel from the synthesis source. If a later
  evaluation contradicts the inherited judgment, the Re-visit
  Trigger covers it; the chosen tools (mutmut, Stryker,
  cargo-mutants) are mandated by the task brief and not subject to
  re-litigation in this ADR.

## Links

* Implements: issue #134 — chore(verifier): mutation testing
  weekly cron.
* Related: ADR-0018 (per-project command installation) — its
  Re-visit Trigger #4 fires for the new template file; resolved by
  named extension to the project-bound list, identical to how
  ADR-0022 and ADR-0023 resolved it.
* Related: ADR-0019 (installer post-run verification) — extends
  `--check`-after-install discipline and `cmp -s`/drift semantics to
  the new template file without modification.
* Related: ADR-0021 (nine-principle hardened revision) — invokes
  Principle 3 (deterministic tooling first) as the normative basis
  for mutation testing's place in the verifier suite, Principle 8
  (2-3× margin) as the cadence discriminator (per-PR is 1000×; weekly
  is 2-3×), Principle 9 (continuity / human-runnable) for the
  `workflow_dispatch` design, Principle 4 (knowledge in repo) for
  the operator-driven `docs/anti-patterns.md` accumulation hook, and
  Principle 1 (no vague trade-offs) for the hard 60%/80% numbers.
* Related: ADR-0022 (Hypothesis PBT via installer template) — the
  named-extension boundary rule for non-`.claude/`
  `bootstrap/templates/` files, established there for `conftest.py`,
  is reused here for `mutation.yml` (sixth named exception,
  third sub-destination).
* Related: ADR-0023 (two-layer review gate) — the deterministic-tooling
  layer 1 established there is the conceptual sibling to mutation
  testing in the verifier suite; layer 1 catches "code that would
  obviously be wrong," mutation testing catches "tests that wouldn't
  notice if the code were wrong."
* External: `docs/synthesis/2026-04-29-pipeline-restructuring.md`
  Раздел B ticket #17 — synthesis document motivating tool selection
  and the weekly-cron cadence; consumed as input, not a decision
  record itself.
* External: arxiv 2102.11378 — Google "Practical Mutation Testing
  at Scale" (per-PR is anti-pattern; weekly cron is industry
  consensus).
* External: arxiv 2503.08182 — empirical documentation of LLM
  mirror-test failure mode that mutation testing surfaces.
* External: Henry Coles (Pitest author) blog — per-PR mutation
  testing as anti-pattern; cited via synthesis document.
* External: nexocode case-report — weekly mutation cadence in
  practice; cited via synthesis document.
* External: mutmut v3 documentation —
  `--paths-to-mutate`, `mutmut results --json`.
* External: Stryker documentation —
  `thresholds: { break, low, high }`.
* External: cargo-mutants v27 documentation —
  `--in-diff DIFF_FILE` (PATH argument, not boolean flag).
* External: SARIF 2.1.0 schema —
  https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
  (target output format for GitHub Code Scanning integration).
