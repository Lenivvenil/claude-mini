# 0023. Add deterministic two-layer gate to `/review`: static-analysis layer 1 before LLM layer 2

* Status: accepted (2026-06-10)
* Date: 2026-04-30
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: pipeline, review, tooling, static-analysis, gate, principle-3
* Related issue: #121

## Context and Problem Statement

The `/review` skill (`bootstrap/commands/review.md`) today loads the diff and
hands it directly to the LLM critic. Style violations, cyclomatic-complexity
overruns, copy-paste blocks, and TODO-without-issue-ref — every class of
defect a deterministic linter detects in milliseconds at zero token cost — are
instead rediscovered by the LLM at cost, with lower precision and without a
reproducible threshold. `docs/principles.md` §3 ("сначала детерминированный
тулинг, потом, может быть, агент") states the inverse contract: deterministic
tooling first; LLM only on semantics the AST cannot reach. The current
`/review` violates that principle structurally — there is no layer 1.

Issue #121 closes that gap: a layer-1 deterministic gate (ruff, eslint +
typescript-eslint, radon, lizard, jscpd, semgrep) runs before the LLM critic;
configuration templates ship to `bootstrap/templates/` for installer delivery.
This ADR settles the architecturally-significant choices that must be locked
before `/implement`:

1. The **gate mechanism** — how layer 1 blocks layer 2.
2. The **tool set** — six new cross-cutting dev-tool dependencies.
3. The **threshold values** committed as a zero-warning baseline.
4. **Missing-tool behaviour** — fail vs warn.
5. The **two modes of `verify.sh`** — diff-scan (default, for `/review`)
   and full-scan (`--full`, for baseline establishment).

The decision meets `docs/principles.md#что-значит-архитектурно-значимо` on two
counts. First, six new cross-cutting tool dependencies enter the pipeline at
once — the ADR-trigger criterion "добавляется или удаляется зависимость,
которая становится cross-cutting" fires six times over. Second, the chosen
thresholds (CC ≤ 10, MI > 65, jscpd `min-tokens:50 min-lines:5`) become the
zero-warning baseline across every consuming pet-project, and raising any of
them later requires every pet-project that has been driven to that baseline
to be re-baselined; this satisfies "принимается ограничение, которое будет
трудно снять через 6 месяцев."

## Decision Drivers

* **Principle 3 — deterministic tooling first.** A linter-detectable defect
  must be caught by the linter, not by the LLM critic. Measurable: zero LLM
  tokens spent on diffs containing only ruff-/eslint-/radon-class defects.
* **Principle 9 — perehvat / human-runnable continuity.** Layer 1 must run
  without an LLM session. The script that the skill calls must be the same
  script a human runs from the shell during LLM outage. No LLM-only branch
  in the gate logic.
* **Principle 1 — no vague trade-offs.** The gate's enforcement model must
  be named honestly. If the stop is instruction-following rather than
  mechanical, that limitation is recorded, not glossed.
* **Principle 8 — 2-3× margin, not 1000×.** Threshold values are picked
  to match common industry practice for pet-project-grade code (radon
  CC ≤ 10 / MI > 65 from synthesis-doc reference, jscpd strict-mode
  defaults), not from hypothetical worst-case load. The margin is over
  typical pet-project code, not over a banking-grade adversarial input.
* **Cross-cutting consistency over per-project tuning.** One zero-warning
  baseline applies to every consuming pet-project. Per-project threshold
  drift would re-introduce the operator-discipline failure mode this ADR
  exists to remove.
* **Machine-readable finding output.** Each tool must emit a stable
  text-or-structured finding format (SARIF where available, otherwise a
  parseable text format) so future work (CI annotations, IDE integration)
  does not require rewriting the gate.
* **One-command install per tool.** Each tool must be installable via a
  single package-manager invocation (`pip install`, `npm i -g`,
  `brew install`); tools requiring source builds or binary downloads are
  rejected on operator-friction grounds.
* **Reversibility within six months is one-way-difficult.** Once N
  pet-projects have been driven to the zero-warning baseline at the chosen
  thresholds, raising a threshold requires all consumers to re-baseline.
  The choice locks in operationally even though every artefact is
  plain-text-reversible.

## Considered Options

For the **gate-mechanism** axis (the architecturally-load-bearing choice;
plan §3):

* **Option A — Bash-in-skill.** Inline `Bash(ruff:*)`, `Bash(eslint:*)`,
  etc. tool grants in `review.md`; the LLM runs each linter as a tool call,
  reads the output, and decides whether to continue analysing the diff.
* **Option B — Dedicated `verify.sh` injected via `!` interpolation.** A
  shell script `bootstrap/scripts/verify.sh` runs all six gates, always
  exits 0, and prints `LAYER1_FAILED` as a text marker on any failure.
  `review.md` injects the result via `!verify.sh 2>&1`; the LLM follows
  the instruction "if you see `LAYER1_FAILED`, output only gate findings
  and stop." (chosen)
* **Option C — Separate `/verify` slash-command.** A standalone `/verify`
  skill the operator invokes manually before `/review`.

The other four points (tool set, thresholds, missing-tool=fail, two modes)
are dependent decisions: each is settled inside the chosen mechanism (Option
B) and recorded as a side decision in Decision Outcome below. They do not
get full Pros-and-Cons treatment because their alternatives are not
architecturally distinct from the chosen option — they are parameter
choices on the chosen mechanism.

## Decision Outcome

Chosen option: **Option B — `verify.sh` invoked via `!` interpolation, with
`LAYER1_FAILED` text marker as the stop instruction to the LLM.**

The constraint that discriminates the three options is Principle 9 combined
with Principle 1. Option A puts every linter call inside the LLM's context
window — defeating the token-saving rationale on every clean PR — and gives
the LLM authority to decide whether to continue, which is "Claude makes the
decision" (Principle 2 forbids this). It also fails Principle 9: a human
cannot run "the gate" without invoking a Claude Code session. Option C
satisfies Principle 9 but fails on the invocation model: slash-commands in
Claude Code cannot be chained from other slash-commands, so `/verify` would
have to be invoked manually before every `/review` — restoring the
operator-discipline failure mode the structural mechanism is meant to
eliminate.

Option B pre-computes the gate result outside the LLM's context (the `!`
interpolation runs at skill-load time, before the LLM sees the prompt),
emits a deterministic text marker, and is composable: the same script
serves `/review`, `/qa`, ad-hoc shell invocation, and any future CI
exerciser. The shell-script-as-pipeline-gate pattern is the same one
ADR-0012 (shellcheck-ci-scope) and ADR-0019 (installer post-run
verification) already established under `bootstrap/scripts/`.

**Honest limitation, recorded under Principle 1.** The stop in Option B is
**instruction-following, not mechanically enforced**. The LLM is told "if
output contains `LAYER1_FAILED`, stop and output only gate findings." A
future LLM context that ignores the instruction could still proceed to
analyse the diff. Mechanical enforcement would require an external wrapper
that inspects the script's exit code and refuses to invoke the skill on
non-zero — out of scope for this ADR. The gate pre-computes the layer-1
verdict outside LLM context and presents it deterministically; enforcement
of the stop depends on the LLM obeying. This is the strongest gate
achievable inside the current Claude Code skill model and is documented as
such rather than dressed up as hard.

The script always exits 0 in every invocation context; `LAYER1_FAILED` on
stdout is the universal failure marker. The decision to always exit 0 (and
not surface a non-zero shell exit even on direct invocation) follows from
plan §3 Approach B and plan §6 risk 4: Claude Code's behaviour on
`!`-interpolated non-zero exits is undocumented (existing skills like the
current `review.md` avoid non-zero exits via `|| fallbacks` for the same
reason); always exiting 0 makes the output predictable across Claude Code
versions, and the text marker is the single source of truth for pass/fail
that every consumer (Claude Code skill, human in shell, future CI wrapper)
reads identically. Mapping the marker to a non-zero shell exit for CI
contexts is explicitly deferred — see Out of Scope.

**Side decisions closed by this ADR:**

1. **Tool set: ruff, eslint + typescript-eslint, radon, lizard, jscpd,
   semgrep.** Selection criteria: zero-config startup, one-command install,
   machine-readable output, cross-language coverage where possible,
   established industry use.

   * **Python lint — ruff over pylint/flake8.** ruff's rule catalogue
     subsumes flake8 + many pylint checks; single Rust binary, sub-second
     on monorepos, `select = ["ALL"]` available. pylint is multi-second on
     small files and has Python-version compatibility tax; flake8 requires
     plugin discipline to reach ruff parity.
   * **JS/TS lint — eslint + typescript-eslint over oxlint/biome.**
     eslint+typescript-eslint is the only combination today with
     production-grade rule coverage for the type-aware rules
     (`no-floating-promises`, `no-misused-promises`); oxlint/biome are
     faster but type-unaware. The speed tax is acceptable on diff-scoped
     scans.
   * **Python complexity — radon over wily/xenon.** radon emits both CC
     (per-function) and MI (per-module) with a stable text-grading
     convention; wily is git-history-oriented and slower; xenon wraps
     radon adding a binary pass/fail but no incremental value over
     parsing radon's own output. radon's grading scale is the de-facto
     reference cited in the synthesis document
     (`docs/synthesis/2026-04-29-pipeline-restructuring.md` §A.1).
   * **Cross-language complexity — lizard over SCC.** lizard reports CCN,
     line count, and parameter count per function across 20+ languages
     with a single CLI flag set; SCC reports lines and tokens but not
     function-level cyclomatic complexity. lizard is the cross-language
     companion to radon (radon is Python-only).
   * **Copy-paste — jscpd over PMD CPD.** jscpd is JS-native, supports
     30+ languages out of the box including Python, ships SARIF reporter,
     and has a strict-mode preset matching the synthesis recommendation;
     PMD CPD is Java-toolchain-bound and requires a JVM at runtime,
     adding install friction.
   * **AST-rule engine — semgrep over hand-written AST walkers.**
     semgrep's rule format is a stable public artefact, multi-language,
     and the rules ship as YAML (Principle 7 — open format). Custom AST
     walkers per anti-pattern would multiply LOC and tie rule logic to
     a specific language's AST library.

2. **Thresholds: CC ≤ 10, MI > 65, lizard `-C 10 -L 100 -a 5`,
   jscpd `min-tokens:50 min-lines:5`, eslint `max-complexity:10`.**

   * **CC ≤ 10** is the synthesis-doc-recommended bound
     (`docs/synthesis/2026-04-29-pipeline-restructuring.md` §A.1) and
     matches the McCabe (1976) original maintainability threshold widely
     used as a default cyclomatic-complexity ceiling across linters. Per
     Principle 8, this is the 2-3×-margin choice for pet-project code,
     not the 1000× choice; banking-grade code might want CC ≤ 5, but at
     CC ≤ 10 the threshold is recognisable to most readers as the
     "industry-default" cyclomatic floor.
   * **MI > 65** is adopted from the synthesis document's
     recommendation, not from radon's own grading boundaries. Recorded
     as **inherited from the synthesis, not independently derived**;
     radon's own A/B/C grading uses different cut-points (radon
     documentation is the authoritative reference for those), and this
     ADR does not claim alignment with them. The 65 figure is the
     synthesis-doc choice and travels with the synthesis-doc rationale.
   * **lizard `-C 10 -L 100 -a 5`** — `-C 10` mirrors the radon CC
     bound at the cross-language layer. `-L 100` (function length cap)
     and `-a 5` (parameter count cap) are values commonly cited in
     code-smell literature (long-function and long-parameter-list
     smells, e.g., Fowler's *Refactoring*) and adopted here as the
     pet-project-grade cap. They are choices made by this ADR, not
     defaults inherited from lizard's own configuration.
   * **jscpd `min-tokens:50 min-lines:5`** is the strict-mode preset
     described in jscpd's documentation; 50 tokens / 5 lines is the
     smallest duplication block that consistently signals copy-paste
     over incidental similarity per the synthesis-doc rationale. Looser
     defaults (e.g., 100 tokens) miss the "copy-paste from a
     neighbouring diff hunk" case the synthesis names as the
     highest-leverage LLM anti-pattern to detect.
   * **eslint `max-complexity:10`** matches the CC ≤ 10 bound on the
     JS/TS surface. The choice here is to align with the radon/lizard
     bound, not to adopt eslint's own default for the rule (eslint's
     default has varied across versions; this ADR pins `10` explicitly
     in `bootstrap/templates/.eslintrc.json` rather than relying on
     upstream defaults).

   These thresholds are the **zero-warning baseline**: every consuming
   pet-project, after `--target` install, runs `verify.sh --full` once
   and fixes findings until the gate passes. Subsequent PRs run the
   diff-scan default. Raising any threshold later requires a
   superseding ADR plus per-pet-project re-baselining.

3. **Missing-tool behaviour: fail.** If any of the six tools is not
   installed, `verify.sh` prints `LAYER1_FAILED` and identifies the
   missing tool. Rationale: under Principle 3, deterministic tooling
   either ran-and-passed or did-not-run; "did not run" is not
   semantically equivalent to "passed." Soft-warn would let the gate
   silently degrade — a tool dropped from the operator's environment
   would not surface for weeks, and the LLM critic would be processing
   diffs unguarded by the layer it was promised. Fail-loud surfaces the
   drift in O(seconds). The runbook documents the install command for
   each tool so the failure is self-fixing.

4. **Two modes of `verify.sh`.** Diff-scan (default, no flag) is invoked
   by `/review` and scopes per-language tools to changed files from
   `git diff --name-only HEAD`. Full-scan (`--full` flag) runs all
   tools against the whole project; this is the mode the operator runs
   once per pet-project after `--target` install to establish the
   zero-warning baseline. **jscpd is whole-repo in both modes** because
   copy-paste detection that scopes to the diff misses the most common
   LLM-laziness pattern: copy-paste from a file outside the diff into
   a file inside the diff. Both modes live in the same script,
   distinguished by a single flag, because separate scripts would
   diverge over time on shared logic (changed-file extraction, tool
   invocation wrappers, output formatting).

5. **Exit-code convention: always exit 0; `LAYER1_FAILED` on stdout is
   the universal failure marker.** This applies in every invocation
   context — Claude Code `!` interpolation, direct shell invocation,
   future CI wrappers. Plan §3 Approach B and plan §6 risk 4 lock this
   convention because Claude Code's behaviour on `!`-interpolated
   non-zero exits is undocumented; always exiting 0 makes the
   pass/fail signal a single text-marker contract that every consumer
   reads identically. CI wrappers needing a non-zero shell exit are
   responsible for grepping the marker themselves and translating; the
   script does not branch on invocation context.

**Reversibility.** Mostly reversible with friction. Reverting requires
either (a) a superseding ADR removing the gate and migrating consuming
pet-projects back to LLM-only review, or (b) leaving the gate in place
but loosening thresholds — also via superseding ADR plus re-baselining.
Neither is destructive; both incur operator effort proportional to
consuming-pet-project count.

### Positive Consequences

* `docs/principles.md` §3 is honoured structurally: the linter-detectable
  class of defect is caught by the linter before the LLM is asked.
* The same `verify.sh` is callable from `/review`, `/qa`, ad-hoc shell,
  future CI, and the human Principle-9 path — one script, four call
  sites, one source of truth on threshold values.
* Token cost on clean PRs drops to near-zero for the layer-1 portion of
  review: the gate output is a few hundred bytes, vs. LLM-rediscovery of
  the same defects at thousands of tokens per finding.
* Threshold values are documented in plain-text config files
  (`ruff.toml`, `.eslintrc.json`, `.jscpd.json`, `.semgrep/`) shipped via
  `--target`; consuming pet-projects inherit one canonical baseline.
* Zero-warning baseline at the chosen thresholds becomes a documented,
  enforceable claim — not an aspiration.

### Negative Consequences

* **The stop is instruction-following, not mechanically enforced.** A
  future LLM context that ignores the `LAYER1_FAILED` instruction could
  still produce diff analysis. The gate pre-computes the verdict
  deterministically; enforcement of the LLM's stop depends on the LLM
  obeying. Mechanical enforcement is out of scope.
* **Six new cross-cutting dev-tool dependencies.** Operators must
  install ruff, eslint + typescript-eslint, radon, lizard, jscpd, and
  semgrep on every machine running `/review`. Each tool is a separate
  upstream version cadence; output-format stability across versions
  (especially SARIF) is not guaranteed by the upstream projects. Drift
  across machines is possible until pinning is added in a follow-on.
* **Threshold lock-in.** CC ≤ 10, MI > 65, jscpd `min-tokens:50` are
  now committed as the cross-cutting baseline. Raising them later
  requires every consuming pet-project that has been driven to the
  baseline to be re-baselined. The asymmetry — easy to lower, hard to
  raise — is a real cost.
* **jscpd whole-repo scan time scales with repository size.** Strict
  mode at `min-tokens:50` is fast on pet-projects today (sub-second on
  current claude-mini); on a multi-thousand-file repo it could exceed
  the implicit "skill loads in seconds" budget. The Re-visit Trigger
  names a falsifiable threshold.
* **semgrep false-positive rate on `llm-commented-block`.** Five
  consecutive comment lines is the proposed pattern; this fires on
  legitimate multi-line commentary (header licence blocks, long
  docstrings written as `#` comments, ASCII-art block diagrams). The
  rule must be tuned against real fixtures before shipping; a noisy
  rule degrades the gate's signal-to-noise and trains the operator to
  ignore it.
* **Always-exit-0 hides failure from naive shell consumers.**
  `verify.sh && next-step` will never short-circuit; an operator
  running the gate in a chained shell command must `grep LAYER1_FAILED`
  explicitly. This is a deliberate consequence of the universal-marker
  decision (side decision 5) — but it does shift detection
  responsibility onto the consumer.
* **First time the pipeline gates a non-`bootstrap/`-touched PR with a
  whole-repo scan.** jscpd whole-repo runs on every `/review`
  invocation regardless of diff scope. A doc-only PR will trigger the
  full jscpd pass. This is intentional (copy-paste spans files outside
  the diff) but is an asymmetry future operators must remember when
  diagnosing "why is `/review` slow on this trivial PR."
* **Operator-discipline tax on missing-tool=fail.** Every machine that
  runs `/review` must have all six tools installed; new contributors,
  fresh laptops, and CI runners all need the install step. The runbook
  makes this self-fixing but the friction is real on the first run.

### Neutral

* `bootstrap/templates/` gains four new files (`ruff.toml`,
  `.eslintrc.json`, `.jscpd.json`, `.semgrep/llm-antipatterns.yaml`)
  delivered via `--target`; ADR-0022 already established the boundary
  rule for non-`.claude/` template delivery, and these files are the
  second category to use it. Re-visit Trigger #5 of ADR-0022 fires:
  "A second non-`.claude/` `bootstrap/templates/` file becomes
  project-bound." This ADR resolves that trigger by named extension —
  the four config files join `conftest.py` on the project-bound list.
* `bootstrap/VERSION` bumps a minor version on the implementation PR
  (new templates under `--target`'s contract; ADR-0018 minor-bump
  rule).
* `docs/anti-patterns.md` gains two entries (TODO-without-ticket,
  commented-block) cross-referenced to the semgrep rules.

## Pros and Cons of the Options

### Option A — Bash-in-skill, inline linter calls

* Good, because no external script is needed; everything lives in
  `bootstrap/commands/review.md`.
* Good, because no install path for `bootstrap/scripts/` is added.
* Bad, because every linter run consumes LLM tool-call turns and
  bloats the context window — defeating the token-cost rationale
  the gate exists to deliver.
* Bad, because "LLM decides whether to continue" makes the LLM the
  enforcer of the gate it is being gated by; Principle 2 forbids
  Claude making this class of decision.
* Bad, because Principle 9 fails: a human cannot run "the gate"
  without launching a Claude Code session — there is no
  shell-runnable artefact.
* Bad, because adding six `Bash(<tool>:*)` permissions widens the
  skill's tool surface unnecessarily; future skills would have to
  duplicate the permission set or call into a wrapper anyway.

### Option B — `verify.sh` injected via `!` interpolation (chosen)

* Good, because the layer-1 result is pre-computed outside LLM
  context; the LLM never sees raw linter output unless it has to
  reason about it.
* Good, because the same script runs from a shell during LLM outage
  (Principle 9) and is composable across `/review`, `/qa`, and any
  future CI exerciser without re-implementation.
* Good, because the gate's threshold values live in plain-text
  config files (`ruff.toml`, `.eslintrc.json`, `.jscpd.json`,
  `.semgrep/`), readable and editable without launching Claude Code
  (Principle 7 — open format).
* Good, because tool permissions on the skill do not need to be
  widened; `Bash(verify.sh:*)` is the only addition.
* Bad, because the stop is instruction-following, not mechanically
  enforced; a future LLM ignoring the `LAYER1_FAILED` instruction
  could continue to analyse the diff.
* Bad, because the script must be present at the path the skill
  references; a botched `--target` install leaves the gate
  unreachable, and the LLM gets no layer-1 input.
* Bad, because `!`-interpolation behaviour on non-zero exits is
  undocumented in Claude Code; the always-exit-0-with-text-marker
  workaround is a soft contract, not a hard one.

### Option C — Separate `/verify` slash-command

* Good, because maximum composability: any pipeline stage could
  invoke `/verify` explicitly.
* Good, because the gate has its own audit trail as a first-class
  pipeline step.
* Bad, because Claude Code does not support slash-commands invoking
  other slash-commands; the operator would have to invoke `/verify`
  manually before every `/review`.
* Bad, because manual two-command invocation is exactly the
  operator-discipline-as-mechanism failure mode Principle 1 forbids.
* Bad, because adding a new public slash-command bumps the public
  API surface ahead of the demonstrated need; over-engineering for
  current scope.

## Confirmation

After implementation lands on `main`, the following grep- and
shell-executable checks must all pass before the implementation PR
merges:

1. **Gate script exists and is executable.**
   `test -x bootstrap/scripts/verify.sh` returns 0;
   `bash -n bootstrap/scripts/verify.sh` (syntax check) returns 0.
2. **Marker token present.**
   `grep -q 'LAYER1_FAILED' bootstrap/scripts/verify.sh` returns 0.
3. **All six tools wired.** Each tool name appears as a command
   invocation in `verify.sh`:
   `for t in ruff eslint radon lizard jscpd semgrep; do
   grep -q "$t" bootstrap/scripts/verify.sh || exit 1; done`
   returns 0.
4. **Two modes wired.**
   `grep -q -- '--full' bootstrap/scripts/verify.sh` returns 0;
   the script's help/usage text mentions both modes.
5. **Always-exit-0 contract.** The script never contains an `exit 1`
   (or other non-zero exit) on the failure paths. A pragmatic check:
   `grep -E '^[[:space:]]*exit [1-9]' bootstrap/scripts/verify.sh`
   returns no matches in production code paths (test-only stubs may
   exist but must be clearly marked).
6. **Threshold values present in config files.**
   `grep -q '"complexity"' bootstrap/templates/.eslintrc.json`
   returns 0 and the configured value is `10` (the eslint rule is named
   `complexity`, not `max-complexity` — corrected from draft);
   `grep -q '"minTokens"' bootstrap/templates/.jscpd.json` and
   `grep -q '"minLines"' bootstrap/templates/.jscpd.json` return 0
   with values `50` and `5` respectively;
   the radon CC ≤ 10 / MI > 65 thresholds are documented in
   `bootstrap/scripts/verify.sh` as named arguments to the radon
   invocations.
7. **`/review` skill calls the gate.**
   `grep -q '!.*verify.sh' bootstrap/commands/review.md` returns 0;
   the skill instruction text contains the `LAYER1_FAILED` stop rule
   verbatim.
8. **Missing-tool behaviour: fail.** A controlled test where one of
   the six tools is masked from `PATH` produces stdout containing
   `LAYER1_FAILED` and a line naming the missing tool. The
   `bootstrap/tests/verify/` fixture suite includes this case.
9. **Two-mode behaviour validated by fixture.**
   `bash bootstrap/tests/verify/run.sh` runs the three documented
   fixture cases (clean Python, CC violation, TODO-without-ticket)
   and exits 0 on all-green. The full-scan fixture is also exercised.
10. **`bootstrap/templates/` gained the four new files.**
    `test -f bootstrap/templates/ruff.toml`,
    `test -f bootstrap/templates/.eslintrc.json`,
    `test -f bootstrap/templates/.jscpd.json`,
    `test -f bootstrap/templates/.semgrep/llm-antipatterns.yaml`
    all return 0.
11. **`--target` delivers the four new files idempotently.** A clean
    run of `./bootstrap/universal-setup.sh --target /tmp/test-l1` on
    an empty directory produces all four files byte-identical to the
    sources. Re-running reports `identical, skip` for each and exits
    0 with `DRIFT=0`. Drift on any of the four surfaces in
    `--target --check`.
12. **Anti-patterns registry updated.** `docs/anti-patterns.md` has
    new entries for `llm-todo-without-ticket` and
    `llm-commented-block`, each cross-referencing the corresponding
    semgrep rule file path.
13. **ADR is in `accepted` status when the implementation PR opens**;
    `bootstrap/VERSION` bump is non-empty in the implementation PR's
    diff against `main`.

If any check fails, the implementation does not match this ADR.

## Re-visit Trigger

Reconsider this decision when **any** of the following becomes true:

* **A consuming pet-project documents a function whose justified
  cyclomatic complexity exceeds 10** and the operator wants to permit
  it without a per-file disable comment. The CC ≤ 10 floor must then be
  re-evaluated against domain evidence, not adjusted by intuition.
* **jscpd whole-repo scan exceeds 60 seconds** on any consuming
  pet-project. The "skill loads in seconds" implicit budget is
  violated; either the threshold is loosened, jscpd is moved to a
  separate scheduled scan (out of `verify.sh`'s diff-scan path), or a
  faster duplicate-detector replaces it.
* **Claude Code documents `!`-interpolation behaviour on non-zero
  exits** and the documented behaviour differs from this ADR's
  always-exit-0 assumption. The exit-code convention may then move to
  the documented mechanism.
* **The operator drops one of the six tools from the standard
  install** (e.g., abandons jscpd in favour of a faster tool, or
  consolidates radon/lizard). The tool-set choice is then re-litigated;
  this ADR's selection is not infinitely stable.
* **Mechanical enforcement of the stop becomes available** — a Claude
  Code feature, an external wrapper, or a hook — that lets a non-zero
  layer-1 result block the LLM from receiving the prompt. The
  instruction-following limitation in this ADR is then an upgrade
  target, not an accepted constraint.
* **A consuming pet-project's domain demands a banking-grade margin
  (CC ≤ 5, MI > 80, jscpd `min-tokens:30`).** The 2-3×-margin
  thresholds in this ADR are pet-project-grade per Principle 8; a
  banking-grade pet-project (if one ever joins the consumer set) needs
  a stricter baseline.
* **Two consecutive `/gate-audit` runs report the layer-1 gate as
  ROI < 0.2** (per the operational rule in `docs/principles.md`
  "Gate ROI обязателен"). The gate is removed or restructured per the
  audit's recommendation.

## Out of Scope

* **Mechanical enforcement of the stop** — the wrapper or hook that
  inspects `verify.sh`'s exit code and refuses to invoke the LLM on
  non-zero. Out of scope; named as a Re-visit Trigger upgrade target.
* **Shell-conventional exit-code semantics for direct invocation.**
  `verify.sh` always exits 0 in every context. CI consumers needing a
  non-zero shell exit grep for `LAYER1_FAILED` themselves and
  translate; mapping the marker to a non-zero shell exit inside the
  script is deferred until either the `!`-interpolation contract is
  documented (Re-visit Trigger) or a CI use-case forces the question.
* **Tool version pinning across operator machines.** Each tool's
  upstream cadence is independent; pinning would require a
  package-manifest mechanism (`requirements-dev.txt`,
  `package.json devDependencies`, etc.) per consuming pet-project.
  Deferred to a follow-on once drift is observed.
* **CI integration.** This ADR scopes `verify.sh` to local `/review`
  invocation. Wiring the same script into GitHub Actions is a
  follow-on issue; the script is designed to be CI-callable but the
  workflow change is not in scope here.
* **Per-pet-project threshold customisation.** The zero-warning
  baseline is cross-cutting by construction. A per-project override
  mechanism (e.g., per-repo `verify.toml`) would re-introduce the
  drift this ADR exists to prevent and is rejected on those grounds;
  if domain evidence later mandates customisation, the Re-visit
  Trigger covers it.
* **Migration of existing pet-projects to the zero-warning baseline.**
  This ADR establishes the mechanism and the baseline; the operator
  runs `verify.sh --full` against each pet-project once the
  implementation merges and fixes findings. No batch-migration tool is
  in scope.
* **Cross-language extension beyond ruff/eslint coverage.** Go, Rust,
  Java, etc. surfaces are out of scope. lizard provides cross-language
  CCN coverage, and semgrep is multi-language, so partial coverage
  exists; per-language native linters (clippy, staticcheck,
  golangci-lint) are deferred until a consuming pet-project requires
  them.

## Links

* Implements: issue #121 — feat(verifier): static-analysis baseline.
* Related: ADR-0007 (`/review` read-only critic) — this ADR augments
  `/review` by adding a layer-1 deterministic gate; the LLM-layer
  read-only contract is preserved (the gate writes nothing; it
  produces stdout consumed by the skill).
* Related: ADR-0012 (shellcheck-ci-scope) — establishes the
  shell-script-as-pipeline-gate pattern under `bootstrap/scripts/`
  reused here.
* Related: ADR-0018 (per-project command installation) — its
  Re-visit Trigger #4 fires for the four new template files; resolved
  by named extension to the project-bound list, identical to how
  ADR-0022 resolved it for `conftest.py`.
* Related: ADR-0019 (installer post-run verification) — extends
  `--check`-after-install discipline and `cmp -s`/drift semantics to
  the four new template files without modification.
* Related: ADR-0021 (nine-principle hardened revision) — invokes
  Principle 3 (deterministic tooling first) as the normative basis,
  Principle 9 (continuity / human-runnable) for the script-not-skill
  choice, Principle 1 (no vague trade-offs) for the honest disclosure
  of instruction-following stop, and Principle 8 (2-3× margin) for
  threshold sizing.
* Related: ADR-0022 (Hypothesis PBT via installer template) — the
  named-extension boundary rule for non-`.claude/` `bootstrap/templates/`
  files, established there for `conftest.py`, is reused here for the
  four config files.
* External: `docs/synthesis/2026-04-29-pipeline-restructuring.md` §A.1
  — synthesis document motivating the threshold values (CC ≤ 10,
  MI > 65, jscpd strict-mode preset).
* External: radon documentation — CC and MI grading scales (consulted
  for radon-grade reference; the MI > 65 cutoff in this ADR is the
  synthesis-doc value, not a radon grading boundary).
* External: jscpd documentation — strict-mode preset
  (`min-tokens:50 min-lines:5`).
* External: lizard documentation — `-C/-L/-a` flag semantics.
