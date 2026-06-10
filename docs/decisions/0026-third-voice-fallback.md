# 0026. Raise Codex unavailability threshold to 35% and close #132 without implementation

* Status: accepted (2026-06-10)
* Date: 2026-05-05
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: quality, review, cost, principle-1, principle-7, principle-8, principle-9
* Resolves: #132
* Amends: ADR-0005 (does not supersede; ADR-0005's chosen option stands)

## Context and Problem Statement

ADR-0005 chose two-voice review (Claude `/review` + Codex via ChatGPT Plus
OAuth) with graceful degradation: when Codex is unavailable, open a
`type:deferred-review` issue and let merge proceed. ADR-0005 Re-visit
Trigger #4 named a falsifiable threshold: "if `type:deferred-review`
issues exceed 20% of PRs."

That trigger has fired. **18 deferred-review issues / 71 lifetime PRs
= 25.4%**, concentrated in April 2026 (14 issues) with 4 in May 2026
— the full life of the project. The distribution is not seasonal: the
flake rate was high from the project's first PRs and persisted into the
current month. Codex Plus-OAuth flake is no longer occasional — it is
systemic at this threshold.

Issue #132 frames the response as "third voice" (Kimi K2.6,
Qwen3-Coder-Next-80B-A3B, via OpenRouter or Ollama local). That framing
**evaluates against the wrong axis.** Cross-family diversity (Claude +
Codex) is already satisfied — Panickssery 2024 ("LLMs as judges") shows
two distinct families catch most of the additional bug classes that a
third family would catch. **The actual need is availability**: a
mechanism that responds when Codex does not. This ADR re-frames #132's
question accordingly: what is the cheapest, most principle-aligned way
to handle Codex unavailability >20% of the time?

The two branches issue #132 names are infeasible at the start:

* **Ollama local with Qwen3-Coder-Next-80B-A3B**: ADR-0005 Option D
  evaluated and rejected this on the same hardware ("Intel Mac mini
  3-8 tokens/sec — painful"). At 80B-class parameters, a 2018 Intel
  i7 with no GPU is the wrong machine, not a marginal one. Re-litigating
  the 80B class would require new hardware data we do not have.
* **OpenRouter**: paid API, marginal cost > $0 per call. Violates
  ADR-0005's "zero marginal cost" decision driver.

This ADR is architecturally significant per
`docs/principles.md#что-значит-архитектурно-значимо`:

* The decision either adds a new cross-cutting vendor dependency to
  the critical PR path (one of the proposed options does) **or**
  amends a falsifiable threshold in ADR-0005 (the chosen option does
  this).
* Whichever option wins ships to consuming pet-projects via
  `bootstrap/templates/` and `bootstrap/scripts/`; reversibility
  drops once N projects depend on the chosen mechanism.
* The decision touches the "review" boundary in the pipeline's domain
  model (`docs/domain/`) — `TwoVoiceReview` aggregate's
  graceful-degradation semantics. Whether the aggregate's invariants
  change is option-dependent and stated explicitly in Decision Outcome
  below (Option A: no invariant change; Option D: third skip-condition
  added).

**Triage status of the 18 deferred-review issues is the operator's
input, not the architect's.** This ADR cannot decide on the operator's
behalf whether the 18 issues are a tolerable price (most closed after
manual re-triage) or a backlog signal (most still open, accumulating).
The chosen option below assumes the former; if the operator's actual
state is the latter, the chosen option flips to Option D, and that is
named explicitly in the Decision Outcome.

## Decision Drivers

* **Principle 1 — no vague trade-offs, three permitted answer forms.**
  This ADR commits to (b) "правильный вариант с явным указанием
  условий применимости" for the chosen option, and (c) "не знаю,
  требуются эмпирические данные" for two of the rejected options
  whose facts could not be re-verified at draft time. Neither form is
  hedging; both are explicit about what is decided and what is open.
  Numerical values in this ADR (the new 35% threshold) are derived
  with stated rationale, not committed as bare numbers — see
  Decision Outcome.
* **Principle 7 — open format, vendor-neutral, source of truth in
  repo.** Adding a new vendor (Cloudflare, Groq, OpenRouter) to the
  critical PR path increases vendor-coupling. The chosen option avoids
  this; the rejected vendor options name it as a Bad consequence.
* **Principle 8 — 2-3× margin, not 1000×.** The 25% deferred-review
  rate is the discriminating measurement. If the cross-family signal
  is already captured on the 75% of PRs Codex covers, paying a new
  vendor dependency to recover the 25% is a 1000×-margin failure mode
  unless the 25% gap is provably costing the project something
  measurable. ADR-0005's confirmation criterion ("≥1 not-false-positive
  in 30 days") was met by Codex alone — there is no parallel evidence
  that a third voice on the missing 25% would catch a class of bug
  that two-voice on 75% misses. Principle 8 also drives the
  threshold-raise sizing: one margin step above the current measured
  rate, with a structurally-meaningful upper bound — see Decision
  Outcome.
* **Principle 9 — perehvat / human-runnable continuity.** Any chosen
  fallback must remain runnable without an LLM session. The chosen
  option (do nothing, raise threshold) is trivially compatible: the
  operator can manually open a `type:deferred-review` issue from a
  shell or web UI when Codex flakes. Vendor-fallback options must
  ship with `gh`-shell-runnable invocation, not an LLM-driven script.
* **ADR-0005's zero-marginal-cost driver still binds.** Any option
  with a per-call price (OpenRouter, paid HF tier beyond credits)
  is rejected on this criterion alone, without re-evaluating quality.
* **Hardware constraint: Intel Mac mini 2018, i7, 32 GB RAM, no GPU,
  CPU-only inference.** Local-model options are bounded by what
  llama.cpp can run at usable latency on this hardware. ADR-0005
  Option D rejected 32B-class for 3-8 tok/s; 7B-class at Q4 quantization
  is the only local size class plausibly under 30s per short diff.
  This constraint is empirical, not architectural; if hardware changes,
  the local option is re-litigated.
* **Unverified vendor free-tier facts at draft time.** Cloudflare
  Workers AI and Groq free-tier numbers (daily neurons, RPM/RPD per
  model, current model catalog) could not be re-verified at draft
  time — the operator's environment denied vendor-doc fetches. Per
  Principle 1 form (c), these options are evaluated against last-known
  public facts and named explicitly as "requires empirical
  verification before adoption."

## Considered Options

* **Option A — Do nothing; amend ADR-0005 Re-visit Trigger #4
  threshold from 20% to 35%; treat 25% deferred-review rate as the
  status-quo cost of Codex Plus-OAuth flake.** No new vendor, no new
  code, no new dependency. Recommended.
* **Option B — Cloudflare Workers AI free tier (Llama-3.3-70B-Instruct
  or Qwen2.5-Coder-32B-Instruct) as automatic fallback in
  `bootstrap/scripts/review-codex.sh`.** Requires operator empirical
  probe before adoption (free-tier limits unverified at draft).
* **Option C — Groq free tier (Llama-3.3-70B-versatile or
  qwen-coder-32b) as automatic fallback in
  `bootstrap/scripts/review-codex.sh`.** Same probe-before-adoption
  status as Option B.
* **Option D — Local Qwen2.5-Coder-7B-Instruct via Ollama (CPU-only,
  Q4 quantization), as automatic fallback when Codex flakes.**
  Revisits ADR-0005 Option D with a smaller model (7B instead of
  32B+); empirically verifiable today on the operator's hardware
  without external probe.
* **Option E — Hugging Face Inference API free tier as fallback.**
  Evaluated and rejected; included explicitly to surface the math.

Two options the task brief named are explicitly **out of scope**, not
"Considered":

* **Second Anthropic free account.** Verified infeasible at draft:
  Claude Code requires Pro/Max/Team/Enterprise/Console; the free
  claude.ai tier has no CLI access (source: code.claude.com/docs/en/setup,
  fetched 2026-05-05). Listing it in Considered Options would be a
  strawman per Principle 1 / role hard-rule "≥3 real options, not
  strawmen."
* **OpenRouter paid API.** Per-call price > $0 violates ADR-0005's
  zero-marginal-cost driver without re-evaluation. Issue #132's
  framing of OpenRouter is rejected at the ADR-0005-driver level.

## Decision Outcome

**Recommended option: Option A — do nothing; amend ADR-0005 Re-visit
Trigger #4's 20% threshold to 35%; treat 25.4% deferred-review rate
as the price of Codex Plus-OAuth flake on solo pet-project scale.**

**This is a recommendation, not a decision.** Per role boundary, the
operator chooses. The ADR Status remains `proposed` until the operator
flips it to `accepted` (with the chosen option named in the Status
line) or `rejected` (with a counter-recommendation in a comment trail).

**Threshold derivation (Principle 1: no bare numbers).** The new
threshold is **35%**, derived as follows:

* Lower bound: the current measured rate (25.4%). Setting the
  threshold below the current rate would re-fire the trigger on the
  next PR, which would defeat the purpose of the amendment.
* Margin: ~10 percentage points above the current rate, which is
  one Principle-8 margin step (≈ 1.4× the current rate). Two
  margin steps (≈ 2× ≈ 50%) reaches the structural ceiling
  described next.
* Upper bound: **50% is the structural ceiling.** Above 50%, half
  of merged PRs ship without two-voice and the mechanism is
  structurally broken — the trigger would fire only when the
  pipeline has already failed. The new threshold must sit
  meaningfully below this ceiling. 35% leaves ~15 percentage
  points of headroom before structural failure, which is the
  Principle-8 "one more margin step before the ceiling" sizing.
* No further raise without superseding ADR. This commitment is
  recorded in Re-visit Trigger; "20% became 35% became 50%" by
  iterative amendment is explicitly forbidden.

If the operator prefers a different specific value (30%, 40%) the
choice is theirs at `accepted`-flip; the rationale above is the
architect's recommendation, not a hard commit. What is committed is
the structure: lower bound = current rate, upper bound = 50%
structural ceiling, only one calibration round permitted.

**TwoVoiceReview aggregate impact (per `docs/domain/`).**

* Under Option A: **no aggregate-shape change.** The threshold is a
  parameter of the existing graceful-degradation semantics, not a
  new state or a new transition. No `docs/domain/aggregates/two-voice-review.md`
  update is required; the implementation PR (which carries no code)
  does not touch `docs/domain/`.
* Under Option D: **third skip-condition added.** The aggregate's
  state machine gains a "local-fallback exhausted" transition
  before "open deferred-review issue."
  `docs/domain/vocabulary.md` must be updated in a **separate PR
  before the implementation PR** — per AGENTS.md §ADR, domain model
  is stable before implementation begins. The implementation PR then
  triggers `domain-reviewer` invocation per CLAUDE.md conditional-agent-gates.
  Writing both in one PR is a protocol violation.

**The recommendation is conditional on operator triage state.** It
holds if and only if **most of the 18 lifetime `type:deferred-review`
issues have been closed after manual re-triage** (i.e., the deferred
state is processed, not accumulated). If the operator's actual state
is "≥10 of the 18 are still open and accumulating," the recommendation
flips to **Option D — local Qwen2.5-Coder-7B-Instruct via Ollama**,
because at that backlog level the 25% gap is provably costing the
project something measurable (un-reviewed code merging to `main`),
and Principle 8's 2-3× margin tips in favour of paying the local-model
latency cost to recover signal.

The triage-state check is mechanical and grep-executable:

```sh
gh issue list --label 'type:deferred-review' --state open  | wc -l
gh issue list --label 'type:deferred-review' --state closed | wc -l
```

If `open / total ≤ 0.4`, Option A. Else Option D.

**Note on threshold terminology.** Two distinct thresholds appear in
this ADR; they measure different things and must not be confused:

* **40%** (`open_deferred / total_deferred`) — the triage-state check
  above. Answers: "of all deferred-review issues ever opened, how many
  are still unresolved?" If ≥40% are open and accumulating, the graceful-
  degradation mechanism is producing a growing backlog of un-reviewed
  code, and Option D is warranted.
* **35%** (`deferred_prs / all_prs`) — the amended Re-visit Trigger #4
  threshold. Answers: "what fraction of lifetime PRs never got a second
  voice at all?" Currently 25.4%; this ADR raises the tolerable ceiling
  from 20% to 35%.
* **50%** (`deferred_prs / all_prs`) — the structural ceiling. If
  deferred-review rate reaches 50%, half of merged PRs ship without
  two-voice; the mechanism is structurally broken regardless of backlog
  state. The 35% threshold sits below this ceiling with headroom.

**Rationale for Option A as the default recommendation:**

1. **Cross-family diversity is already satisfied (Panickssery 2024).**
   The 75% of PRs that get two-voice already capture most of the bug
   classes a third family would catch. Adding a third vendor for the
   25% gap is the 1000×-margin failure mode under Principle 8 unless
   the 25% gap is provably costing the project measurable defects —
   ADR-0005's 30-day confirmation criterion was met by Codex alone,
   not by a hypothetical third voice.
2. **Vendor-neutrality (Principle 7) prefers no new vendor over any
   new vendor.** Cloudflare, Groq, HF — each is an additional
   third-party dependency in the critical PR path, each with its own
   uptime, ToS, rate-limit, and model-catalog churn. ADR-0005
   already added one such dependency (Codex Plus); adding a second
   to mitigate the first's flake doubles the surface, not halves it.
3. **The threshold itself was a guess.** ADR-0005 Re-visit Trigger #4
   committed "20%" as the firing line without evidence that 20% was
   the cost-tolerable boundary versus 30% or 40%. 25.4% is closer to
   "Codex Plus-OAuth is intermittent at ~25% baseline" than to "Codex
   is failing." Raising the trigger to 35% (per the derivation above)
   is a one-time calibration with a stated structural ceiling, not a
   capitulation.
4. **Operator hand-off cost is zero.** No new code in
   `bootstrap/scripts/`, no new template under `bootstrap/templates/`,
   no new ADR-0018 named exception, no new MCP server, no new vendor
   account, no new probe.

**Rationale for Option D as the alternative if triage state shows
backlog:**

* Local Qwen2.5-Coder-7B-Instruct at Q4_K_M quantization runs at
  ~10-15 tok/s on a 2018 Intel i7 with 32 GB RAM (**estimate** from
  last-known llama.cpp community benchmarks for 7B Q4 on comparable
  hardware; not measured on this machine). For a short diff (≤500
  lines, ~2K input tokens, ~500 output tokens), estimated 30-50s per
  review. Operator must run `ollama pull qwen2.5-coder:7b-instruct-q4_K_M
  && time ollama run qwen2.5-coder:7b-instruct-q4_K_M "hello"` to
  verify before adopting Option D.
* Principle 7 (vendor-neutral) is satisfied: Qwen2.5-Coder is
  open-weight (Apache-2.0); Ollama is open-source. No vendor in the
  critical path.
* Principle 9 (perehvat) is satisfied: the model runs on the operator's
  laptop; an internet outage does not block review.
* Empirically verifiable today, no probe required: `ollama pull
  qwen2.5-coder:7b-instruct-q4_K_M && time ollama run … < diff` on
  the operator's machine in <10 minutes.
* The cost is real (latency, disk space ~5 GB, RAM ~6-8 GB during
  inference, slower than Codex when Codex works) — see Bad
  Consequences below.

**Why Options B and C are not the recommendation today:**

Both depend on free-tier facts the operator's environment did not
permit re-verification of at ADR draft time (vendor-doc fetches
denied). Per Principle 1 form (c), neither can be `accepted` without
an operator-run empirical probe. The probe is named in Re-visit
Trigger; if the operator runs it and the data supports adoption,
this ADR is superseded by ADR-NNNN (next number) with an `accepted`
Status. Until then, recommending B or C would smuggle unverified
facts into a load-bearing decision.

**What changes in issue #132's AC under this recommendation
(Option A):**

* Drop the OpenRouter framing entirely (rejected at ADR-0005-driver
  level, not re-evaluated).
* Drop the Ollama Qwen3-Coder-80B framing entirely (rejected at
  ADR-0005-Option-D level, hardware constraint).
* Re-frame issue #132 from "add third voice" to "ADR-0005 Re-visit
  Trigger #4 fired; closed by ADR-0026 (this) — threshold raised to
  35%, no code change."
* Close issue #132 as **resolved-by-ADR-0026** with a comment linking
  this ADR. No `bootstrap/scripts/review-codex.sh` change. No
  `bootstrap/templates/` change. No new ADR-0018 named exception.

**What changes if the operator picks Option D instead:**

* Issue #132 re-scoped to "wire local Qwen2.5-Coder-7B via Ollama as
  Codex-fallback in `bootstrap/scripts/review-codex.sh`."
* New file: `bootstrap/scripts/review-local.sh` (mirrors
  `review-codex.sh`'s graceful-degradation contract, calls
  `ollama run qwen2.5-coder:7b-instruct-q4_K_M`).
* `review-codex.sh` modified: on Codex skip-conditions (startup
  hang, exit 4, exit 124), call `review-local.sh` instead of
  immediately opening `type:deferred-review` issue. If
  `review-local.sh` also fails (ollama not installed, model not
  pulled, timeout >180s), then open the deferred-review issue.
* New runbook: `docs/runbooks/local-fallback-setup.md` covers
  `ollama pull` + `claude doctor`-equivalent verification.
* `docs/domain/aggregates/two-voice-review.md` updates to add the
  third skip-condition transition.
* No new vendor dependency, no new ADR-0018 exception (no
  `bootstrap/templates/` template — the script lives in
  `bootstrap/scripts/` per ADR-0012's pattern).
* `bootstrap/VERSION` bumps minor.

**Reversibility.** Option A is fully reversible: a future ADR can
lower the threshold or add a vendor fallback without code changes.
Option D is reversible with friction: removing the local fallback
requires a superseding ADR and `--target` re-runs to remove the new
script from consuming pet-projects. Options B/C would have been
mostly-reversible with friction (vendor coupling under
`bootstrap/scripts/`), but they are not the recommendation.

### Positive Consequences

These apply to the recommended option (A); per-option Pros and Cons
are below.

* No new vendor dependency in the critical PR path. ADR-0005's
  vendor surface is unchanged.
* No new code, no new template, no new ADR-0018 named exception, no
  new MCP server, no new operator setup step.
* Principle 7 (vendor-neutral) is honoured by absence of new
  coupling.
* Principle 8 (2-3× margin) is honoured by not paying for a 25%-gap
  recovery whose value is not measurable; threshold-raise sizing is
  derived (one margin step above current, half a margin step below
  the structural ceiling).
* The threshold raise (20% → 35%) is a falsifiable commitment, not
  a wave of the hand: the new trigger fires at a higher empirical
  bar, the upper bound (50%) is structurally meaningful, and
  ADR-0005's mechanism stays intact.
* Operator hand-off cost is zero. ADR-0005 is left untouched (per
  MADR append-only convention; this ADR's Decision Outcome is the
  binding amendment record); the only artefact is this ADR itself.
* If the recommendation is wrong (i.e., backlog is in fact
  accumulating), the conditional flips automatically to Option D
  on the next operator triage check; the cost of being wrong is one
  re-read of this ADR, not a re-write.

### Negative Consequences

These apply to the recommended option (A). Bad ≥ Good is enforced;
the count below is seven Bad to seven Good.

* **The 25% deferred-review rate is locked in as tolerable, not
  fixed.** Every fourth PR ships without two-voice. If the cross-
  family signal value is in fact higher than Panickssery 2024
  generalises (pet-project / solo / Russian-speaking operator may
  not match the paper's distribution), this is silent quality
  loss, not a documented compromise.
* **Threshold-raise is calibration, but it can also be motivated
  reasoning.** "20% became 35%" is the kind of move that, repeated,
  erodes ADR-0005's confirmation contract. The Re-visit Trigger
  commits to "no further raise without superseding ADR" to prevent
  slow drift; this commitment is itself unenforced by mechanical
  tooling and relies on operator discipline.
* **Conditional on triage state assumes the operator triages.** If
  the operator does not in fact close `type:deferred-review` issues
  systematically — and the conditional check
  (`gh issue list --label … --state open | wc -l`) is not built
  into a recurring pipeline gate — the recommendation can hold
  formally while the actual cost (un-reviewed code on `main`) grows.
* **Cross-family diversity claim (Panickssery 2024) is one paper's
  generalisation, not a project-specific measurement.** Two-voice
  catching "most" bug classes is the paper's finding on its
  evaluation set; whether claude-mini's PR distribution matches that
  set is unverified. The recommendation rests on this claim without
  a falsifiability hook beyond the existing `/gate-audit`.
* **Codex Plus-OAuth flake at 25% is a vendor symptom, not a
  resolved cause.** Option A treats the symptom as background
  weather. If OpenAI's Plus quota tightens further (e.g., 5 reviews/
  week instead of 10-25), the deferred-review rate rises further,
  and the threshold-raise mechanism applied repeatedly degrades the
  pipeline incrementally.
* **No fallback means a worst-case PR that needs two-voice can't
  get it on demand.** When Codex is down and the operator believes
  this specific PR warrants the second voice (security-sensitive,
  prod-bound, complex refactor), the only escape is to wait for
  Codex Plus to recover or run a manual external review. Option D
  would have provided an offline path.
* **`plan.md` in the repository root is now stale.** It was written
  for a third-voice implementation that this ADR closes without code.
  `plan.md` is gitignored and cannot be part of this commit; the
  operator must clear it locally before the next `/plan` run to
  avoid misleading a future session.

### Neutral

* `bootstrap/scripts/review-codex.sh` is unchanged.
* `bootstrap/templates/` is unchanged.
* `docs/anti-patterns.md` does not gain entries on this ADR.
* `bootstrap/VERSION` does not bump (no implementation PR follows
  if Option A is accepted).
* `docs/domain/aggregates/two-voice-review.md` does not change
  under Option A; changes only if Option D is selected.
* ADR-0005 is left untouched (MADR append-only); this ADR's
  Decision Outcome is the binding amendment record.
* Issue #132 closes as resolved-by-ADR-0026 if Option A is chosen;
  re-scopes to local-Ollama wiring if Option D is chosen.

## Pros and Cons of the Options

### Option A — Do nothing; amend Re-visit Trigger #4 threshold to 35% (recommended)

* Good, because no new vendor surface — Principle 7 honoured by
  absence.
* Good, because no new code — operator hand-off cost is zero.
* Good, because the 25.4% measured rate is closer to "intermittent
  baseline" than "broken pipeline"; the 35% threshold is derived
  (current + one Principle-8 margin step, structural ceiling at 50%)
  rather than committed as a bare number.
* Good, because cross-family diversity is already satisfied per
  Panickssery 2024 — the marginal value of a third voice on the
  missing 25% is not established by ADR-0005's confirmation
  criterion.
* Good, because if the recommendation is wrong, the conditional
  Option-D flip costs one operator triage check, not a re-decision.
* Good, because Principle 9 (perehvat) is trivially satisfied — no
  new infrastructure to fail offline.
* Bad, because the 25% deferred-review rate is locked in as the
  tolerable status quo; quality loss on those PRs is now structural.
* Bad, because threshold-raise as a pattern erodes ADR-0005's
  confirmation contract if repeated; the "no further raise without
  superseding ADR" commitment is unenforced by mechanical tooling.
* Bad, because the "operator triages systematically" assumption is
  not enforced by a pipeline gate; backlog accumulation is invisible
  to CI.
* Bad, because Panickssery 2024's cross-family generalisation is
  one paper's finding on one evaluation set; project-specific
  validity is unverified.
* Bad, because Codex Plus-OAuth flake symptom is treated as weather;
  vendor-side degradation is unaddressed.
* Bad, because no fallback exists for the case where the operator
  knows a specific PR warrants two-voice and Codex is down.

### Option B — Cloudflare Workers AI free tier (probe required before adoption)

* Good, because Cloudflare Workers AI free tier is widely reported
  to include daily neuron allowance for Llama-3.3-70B-Instruct
  and Qwen2.5-Coder-32B-Instruct (last-known public facts; not
  re-verified at draft time).
* Good, because the model class (70B / 32B-Coder) is comparable to
  Codex's capability tier — quality of the third voice is plausibly
  on par.
* Good, because no local hardware burden; Cloudflare runs the
  inference on its edge.
* Good, because OpenAI-compatible API is exposed by Workers AI
  v1/chat/completions endpoint, simplifying integration with
  `review-codex.sh`-style script.
* Bad, because **free-tier limits could not be re-verified at draft
  time** (operator's environment denied vendor-doc fetches; per
  Principle 1 form (c), this option is "requires empirical data,"
  not "accepted"). Adoption requires operator-run probe.
* Bad, because new vendor dependency in critical PR path — Principle
  7 violation. Cloudflare uptime, ToS, model catalog, and free-tier
  generosity are all third-party-controlled.
* Bad, because daily neuron quota likely caps usage at a level that
  doesn't recover the full 25% gap — at solo scale, the quota is
  generous; at multi-pet-project scale (N consumers via `--target`),
  shared quota collisions become possible.
* Bad, because adds a second vendor's auth model to the operator's
  setup (Cloudflare API token, in addition to ChatGPT Plus OAuth).
* Bad, because new ADR-0018 named exception is needed (the new
  fallback script under `bootstrap/scripts/` is fine; but if vendor
  config lives in `bootstrap/templates/`, it is the seventh
  exception).

### Option C — Groq free tier (probe required before adoption)

* Good, because Groq's LPU inference is among the fastest publicly
  available; latency would be lower than Codex Plus on most
  short-diff reviews.
* Good, because Groq's free tier is widely reported to include
  Llama-3.3-70B-versatile and (more recently) Kimi K2 family
  (last-known public facts; not re-verified at draft time).
* Good, because OpenAI-compatible API simplifies
  `review-codex.sh`-style integration.
* Bad, because **free-tier limits and current model catalog could
  not be re-verified at draft time** (operator's environment denied
  vendor-doc fetches; Principle 1 form (c) applies).
* Bad, because new vendor dependency in critical PR path — Principle
  7 violation, same shape as Option B.
* Bad, because Groq's free tier has historically used per-minute and
  per-day rate limits that, on heavy review days, would themselves
  become the deferred-review trigger — replacing one flaky vendor
  with another.
* Bad, because Groq is a younger vendor (founded 2016, GA 2023) than
  Cloudflare; vendor-stability risk is higher in the multi-year
  reversibility window.
* Bad, because new operator auth (Groq API key) and a second vendor's
  ToS to track.

### Option D — Local Qwen2.5-Coder-7B-Instruct via Ollama

* Good, because Principle 7 (vendor-neutral) is fully satisfied:
  open-weight model (Apache-2.0), open-source runtime, no third party
  in critical path.
* Good, because Principle 9 (perehvat) is fully satisfied: works
  offline, runs on the operator's laptop, no internet dependency.
* Good, because empirically verifiable today on the operator's
  hardware in <10 minutes — no probe-pending status, no unverified
  free-tier facts.
* Good, because the model size (7B Q4_K_M, ~5 GB on disk, ~6-8 GB
  RAM) is well within the 2018 Mac mini's 32 GB capacity, with
  headroom.
* Good, because Qwen2.5-Coder-7B is purpose-built for code and
  trained on a corpus that includes diff-style reasoning — model-fit
  for the review task is plausible.
* Good, because cost (CPU cycles, electricity) is borne locally and
  has no per-call charge.
* Bad, because latency (~30-50s per short diff at 10-15 tok/s) is
  worse than Codex Plus (~5-15s when working). The operator pays
  this every time Codex is down, not just on the 25% gap.
* Bad, because 7B-class model quality is below 32B/70B class
  Codex/Cloudflare/Groq options; bug-class coverage is narrower.
  This may be acceptable as fallback (Codex covers 75% at full
  quality; 7B covers the remaining 25% at reduced quality) but is
  not equivalent.
* Bad, because Ollama install and `ollama pull` are operator setup
  steps that must be documented in a new runbook
  (`docs/runbooks/local-fallback-setup.md`); Principle 9's "open
  the repo and continue without setup" test weakens for new
  operators.
* Bad, because consuming pet-projects via `--target` inherit the
  Ollama dependency; pet-projects on machines without Ollama would
  silently fall through to deferred-review issue (graceful), but the
  expectation that "two-voice means Codex OR local" is now a per-machine
  property, not a repo property.
* Bad, because model staleness — Qwen2.5-Coder-7B is the version
  stable at draft time; later upgrades require operator re-pull and
  benchmark, not a vendor-side rollout.
* Bad, because revisits ADR-0005 Option D's rejected branch with a
  smaller model; the rejection rationale ("3-8 tok/s painful") was
  for 32B-class. Whether 7B at 10-15 tok/s clears the "painful"
  threshold is a judgment the operator must make in person.

### Option E — Hugging Face Inference API free tier (rejected)

Verified at draft (huggingface.co/docs/inference-providers/pricing,
fetched 2026-05-05): **free users receive $0.10/month in credits.**
At Llama-3.3-70B routing rates (~$0.0003-0.001 per 1K tokens), this
is approximately 3-10 short reviews per month before the operator
must purchase credits. At 71 lifetime PRs across the project's life,
the free tier covers <15% of the deferred-review gap. Rejected on
math, not on principle.

## Confirmation

Confirmation is conditional on the chosen option. If Option A
(recommended) is accepted:

1. **ADR-0005 Re-visit Trigger #4 amendment is recorded.** ADR-0005
   is **left untouched** per MADR 4.0 append-only convention; this
   ADR's Decision Outcome (specifically the threshold-derivation
   block and the 35% commitment) stands as the binding amendment
   record. The operator's `accepted` flip on this ADR's `Status:`
   line is the authoritative signal that the amendment is in force.
   `git diff` on `0005-two-voice-review-codex-plus.md` shows no
   change.
2. **Issue #132 is closed as resolved-by-ADR-0026.** A comment on
   #132 cites this ADR's path
   (`docs/decisions/0026-third-voice-fallback.md`) and the chosen
   option. `gh issue view 132` shows the comment and the closed
   state.
3. **No code changes.** `git diff main` after this ADR merges is
   limited to `docs/decisions/0026-third-voice-fallback.md`.
4. **Triage-check shell command is documented and scheduled.** The command
   ```sh
   gh issue list --label 'type:deferred-review' --state open  | wc -l
   gh issue list --label 'type:deferred-review' --state closed | wc -l
   ```
   is recorded in this ADR's Decision Outcome. The operator runs it
   at every `/gate-audit` execution (minimum: weekly). If the result
   at any run shows `open / total > 0.40`, the conditional in
   Decision Outcome flips to Option D.
5. **`bootstrap/VERSION` is unchanged** — no implementation PR
   follows.
6. **`docs/domain/aggregates/two-voice-review.md` is unchanged** —
   no aggregate-shape change under Option A.

If Option D is accepted instead:

1. New file: `bootstrap/scripts/review-local.sh` — mirrors
   `review-codex.sh`'s graceful-degradation contract, invokes
   `ollama run qwen2.5-coder:7b-instruct-q4_K_M`. Existence:
   `test -x bootstrap/scripts/review-local.sh` returns 0.
2. `bootstrap/scripts/review-codex.sh` modified: on Codex skip-conditions,
   calls `review-local.sh` before opening `type:deferred-review` issue.
3. New runbook: `docs/runbooks/local-fallback-setup.md`.
4. `docs/domain/aggregates/two-voice-review.md` updated: third
   skip-condition transition added before "open deferred-review
   issue." `domain-reviewer` invocation required.
5. Issue #132 re-scoped (not closed).
6. `bootstrap/VERSION` bumps minor.

If Option B or C is accepted, a separate ADR (NNNN, next number) is
required because the operator probe must produce empirical data
before the option can be `accepted` per Principle 1 form (c). This
ADR does not flip directly to B or C.

## Re-visit Trigger

Reconsider this decision (or the ADR-0005 amendment it carries) when
**any** of the following becomes true:

* **`type:deferred-review` rate exceeds 35% of lifetime PRs**
  (the new threshold this ADR commits). At that point Option A's
  "tolerable status quo" framing fails and Option D (or B/C with
  probe) is re-evaluated. **No further raise without superseding
  ADR.** A second amendment that pushes the threshold to 45% or
  beyond by inline edit is forbidden — the only path above 35% is
  a superseding ADR that re-litigates the structural-ceiling
  argument.
* **Open `type:deferred-review` issues exceed 50% of total
  deferred-review issues** (i.e., backlog accumulating, not being
  triaged). The conditional in Decision Outcome flips to Option D
  per the operator-triage check.
* **Operator runs the empirical probe for Option B (Cloudflare
  Workers AI free tier) and the data supports adoption** —
  specifically: free-tier daily neuron quota covers ≥75% of the
  current deferred-review gap, model latency is ≤30s per short
  diff, model quality on a 5-PR pilot is non-zero relative to no
  fallback. Then a superseding ADR (ADR-NNNN) is drafted with
  Status `accepted`, B as chosen.
* **Operator runs the empirical probe for Option C (Groq) with the
  same criteria.** Same outcome: superseding ADR with Groq as chosen.
* **Hardware change (Mac mini M-series with NPU, or external GPU
  on a different machine) lifts the 80B-class local-model
  rejection from ADR-0005 Option D.** That re-litigates the
  whole premise: an 80B-class local model would dominate Options
  B/C/D simultaneously.
* **Codex Plus-OAuth becomes stable** (e.g., OpenAI ships a fix
  that drops the deferred-review rate below 10%). At that point
  this ADR's threshold-raise is over-conservative; ADR-0005's
  20% threshold is restored or the trigger is re-calibrated.
* **Anthropic ships Claude Code-native multi-provider review**
  (e.g., a `/review --provider=openai` slash command). The whole
  two-voice mechanism is re-litigated; this ADR's amendment may
  become moot.
* **Two consecutive `/gate-audit` runs report two-voice review's
  ROI as < 0.2** (per the operational rule in
  `docs/principles.md` "Gate ROI обязателен"). The two-voice
  mechanism itself is removed or restructured; this ADR's
  amendment is superseded by the structural change.
* **Panickssery 2024's cross-family diversity claim is contradicted
  by a project-specific measurement** — e.g., a 30-day pilot in
  which a third voice catches a non-false-positive that Codex+Claude
  missed on a deferred-review-affected PR. The "diversity satisfied"
  premise of Option A fails.

## Out of Scope

* **Second Anthropic free account.** Verified infeasible at draft:
  Claude Code requires Pro/Max/Team/Enterprise/Console; the free
  claude.ai tier has no CLI access. Source:
  https://code.claude.com/docs/en/setup ("Authenticate" section,
  fetched 2026-05-05). Not a strawman option, not a Considered
  Option — out of scope.
* **OpenRouter or any paid third-voice API.** Per-call price > $0
  violates ADR-0005's zero-marginal-cost driver without
  re-evaluating the driver itself. Re-evaluation would require a
  separate ADR superseding ADR-0005.
* **Ollama local with Qwen3-Coder-Next-80B-A3B or any 32B+ class
  model.** Hardware constraint inherited from ADR-0005 Option D
  (3-8 tok/s on Intel Mac mini 2018, judged "painful"). Re-evaluation
  requires hardware change, named in Re-visit Trigger.
* **Editing ADR-0005 inline to record this amendment.** MADR 4.0
  treats ADRs as append-only; the amendment is recorded by this
  ADR's existence and Decision Outcome, not by a `git diff` on
  ADR-0005's file. Out of scope to preserve the audit trail.
* **Per-PR mechanism changes to `bootstrap/scripts/review-codex.sh`
  beyond what the chosen option requires.** Other Codex-flake
  improvements (e.g., retry-on-startup-hang, auth refresh
  automation, model-pin promotion to gpt-5.3) are out of scope of
  this ADR; they live in their own issues.
* **Cross-language extension of the third-voice mechanism.** Not
  language-specific; out of scope as a non-issue.
* **Mechanical PR-blocking on the deferred-review threshold.** The
  threshold (this ADR raises it to 35%) lives as a Re-visit Trigger
  in `docs/decisions/`, not as a CI gate. Mechanical enforcement
  would require a separate ADR establishing the gate semantics.
* **Re-verification of Cloudflare Workers AI and Groq free-tier
  facts.** Operator's environment denied vendor-doc fetches at
  draft time. Re-verification is the operator's empirical probe,
  documented in Re-visit Trigger; not the architect's deliverable.
* **Issue lifecycle management for `type:deferred-review` beyond
  the existing graceful-degradation flow.** Auto-close of stale
  deferred-review issues, summary digests, and other tree-management
  tooling are deferred — the conditional Option-A/D check assumes
  manual triage and surfaces backlog mechanically.

## Links

* Amends (does not supersede): ADR-0005
  (`docs/decisions/0005-two-voice-review-codex-plus.md`) — Re-visit
  Trigger #4 threshold "20%" raised to "35%" per Decision Outcome
  Option A. ADR-0005's chosen option (Two-voice with graceful
  degradation) stands. ADR-0005's file is **not edited**; this
  ADR's Decision Outcome is the binding amendment record.
* Resolves: issue #132 — feat(review): third-voice fallback. The
  issue's framing is re-interpreted per this ADR's Context section;
  AC superseded by Decision Outcome (Option A closes without implementation).
* Related: ADR-0021 (nine-principle hardened revision) — invokes
  Principle 1 (no vague trade-offs, three permitted answer forms;
  no bare numbers — see threshold derivation), Principle 7
  (vendor-neutral), Principle 8 (2-3× margin; threshold sizing),
  Principle 9 (perehvat).
* Related: ADR-0012 (`bootstrap/scripts/` shell-script-as-pipeline-gate
  pattern) — relevant only if Option D is chosen; the new
  `review-local.sh` follows ADR-0012's pattern.
* Related: ADR-0018 (per-project command installation, named-exception
  list) — not invoked under recommended Option A; would gain a seventh
  named exception if Option B's vendor config landed under
  `bootstrap/templates/`.
* External: Panickssery, Saminsa et al. 2024 — "LLMs as Judges:
  Cross-Family Diversity in Code Review" (cited in ADR-0005;
  re-cited here as the basis for Option A's "diversity satisfied"
  premise).
* External: Hugging Face Inference Providers pricing —
  https://huggingface.co/docs/inference-providers/pricing (verified
  $0.10/month free credit at draft; basis for Option E rejection).
* External: Claude Code authentication —
  https://code.claude.com/docs/en/setup (verified Claude Code
  requires Pro/Max/Team/Enterprise/Console; basis for second-account
  out-of-scope).
* External: Cloudflare Workers AI documentation — pricing and
  limits page; **fetch denied at draft time**, operator probe
  required before Option B adoption (named in Re-visit Trigger).
* External: Groq documentation — pricing and rate-limits page;
  **fetch denied at draft time**, operator probe required before
  Option C adoption (named in Re-visit Trigger).
* External: Qwen2.5-Coder model card —
  https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct (Apache-2.0
  license, basis for Option D's vendor-neutrality claim).
* External: Ollama project — https://ollama.com (open-source
  runtime, basis for Option D's local-execution path).
* External: GitHub issues openai/codex#14181, openai/codex#14735
  (cited in ADR-0005; baseline for Codex Plus-OAuth flake symptom
  this ADR responds to).
