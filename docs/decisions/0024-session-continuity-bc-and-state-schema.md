# 0024. Establish Session Continuity as a sibling bounded context with `STATE.md` as document-model aggregate root

* Status: accepted (2026-06-10)
* Superseded-by: ~
* Date: 2026-05-03
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: domain, bounded-context, session-continuity, state-schema, continuity
* Related issue: #128

## Context and Problem Statement

Principle 9 (`docs/principles.md#9-перехват--контракт`) requires that an
operator (or fresh agent) can open the repo after an LLM session ends and
resume meaningful work within five minutes — the "Human Resume Test". Today
this is impossible: there is no `STATE.md`, no structured session-log, and
no linter that enforces ADR-discipline on `plan.md`. Issue #128 introduces
all three artifacts simultaneously, and the artifacts collectively span a
concern — what survives between sessions — that does not belong inside any
existing aggregate of bounded context `claude-mini-pipeline`.

The decision is architecturally significant per
`docs/principles.md#что-значит-архитектурно-значимо`: four triggers fire at
once — (1) a new bounded-context boundary, (2) a cross-BC contract
(`active_feature_run_id` reference into `claude-mini-pipeline`), (3) a data
model (`STATE.md` 9-field schema) that becomes hard to change once
distributed via `--target` to consumer repos, and (4) a new cross-cutting
tool dependency (`plan-lint.sh`) installed into every target repo. The
`domain-researcher` discovery doc at `docs/domain/continuity-discovery.md`
has surfaced the proposed Ubiquitous Language extension and the Bounded
Context Canvas; this ADR records the boundary call and the schema choices
that the discovery doc deliberately left open.

## Decision Drivers

* **Principle 9 contract.** Hand-off must be readable without LLM, in five
  minutes, from artifacts on disk. The BC's primary NFR (`Human Resume
  Test`) is the binding constraint; every schema choice is judged against
  it.
* **ADR-0020 cross-aggregate pattern must hold.** `FeatureRun` was already
  split (ADR-0020) precisely to avoid embedding orthogonal lifecycles in
  one aggregate. A new lifecycle (`Session`) with its own boundaries must
  not regress that decision.
* **Principle 8 — 2-3× margin, not 1000×.** The current scale is one
  operator, low-frequency hand-offs, single-repo. Event-sourcing,
  structured-log machinery, and atomic write protocols are
  over-engineering at this scale; document model with replacement
  semantics is sufficient.
* **Principle 3 — deterministic tooling first.** Mechanical invariants
  (`STATE.md` size cap, append-only, one-file-per-day) must be checkable
  by `wc`, `grep`, and `test`, not by an agent.
* **Documentation-only cost.** This ADR records boundary and schema; the
  implementation cost is bash plumbing in the existing `stop-hook.sh` and
  one new `plan-lint.sh` script. No production code, no migration.
* **Distribution to target repos via `--target`.** `STATE.md.template` and
  `plan-lint.sh` will be installed into consumer repos. Schema changes
  after distribution are migration events; the schema must therefore be
  cheap-to-change-now and load-bearing-after-merge.

## Considered Options

* **Approach A — Embed session state in `FeatureRun`.** Add `session_id`,
  `next_3_actions`, `blocked_on`, etc. as attributes of the existing
  `FeatureRun` aggregate root inside `claude-mini-pipeline`. `stop-hook`
  reads the active `FeatureRun`, writes `STATE.md` as a projection. One
  aggregate, minimum new documentation.
* **Approach B1 — Sibling BC `Session Continuity`; `STATE.md` as
  document-model aggregate root.** New BC. `STATE.md` is the aggregate
  root with nine fields. `session-log` is an append-only entity.
  `active_feature_run_id` is a reference-only cross-BC pointer into
  `claude-mini-pipeline`. Document model: replace on hand-off, no event
  store.
* **Approach B2 — Sibling BC `Session Continuity`; `Session` as event-sourced
  aggregate root, `STATE.md` as projection.** Same BC boundary as B1, but
  `Session` is the aggregate root, `session-log` entries are its event
  stream, and `STATE.md` is a derived current-state projection. Cleaner
  DDD semantics; event-store overhead.
* **Approach C — Linter as part of `/plan` skill, not hand-off.** `plan.md`
  ADR-discipline check runs at plan generation time only, owned by the
  `/plan` slash command in `claude-mini-pipeline`. No invocation from
  Session Continuity. Two-leg hand-off contract (STATE.md + session-log)
  instead of triple.

## Decision Outcome

Chosen option: **Approach B1 — Session Continuity as a sibling bounded
context, with `STATE.md` as a document-model aggregate root and
`active_feature_run_id` as a reference-only cross-BC pointer into
`claude-mini-pipeline`.**

A and B1 differ on whether session lifecycle deserves its own bounded
context. They have non-overlapping lifecycles: a single session may span
zero, one, or several `FeatureRun`s; a single `FeatureRun` typically spans
several sessions. ADR-0020 extracted `GovernanceRun` and `TwoVoiceReview`
out of `FeatureRun` for exactly this reason — orthogonal lifecycles do not
belong in one aggregate. Folding session state into `FeatureRun` would
re-create the God Aggregate problem ADR-0020 just resolved, regardless of
how few attributes are added today. The `domain-researcher` discovery doc
arrived at the same conclusion independently
(`docs/domain/continuity-discovery.md` §"Why a new BC").

B1 and B2 differ on the modelling weight of `Session`. B2 is theoretically
cleaner: `Session` as aggregate root with `STATE.md` as a projection over
its event stream maps onto event-sourcing without seams. B1 wins on
Principle 8: at the current scale (one operator, low-frequency hand-offs)
event-sourcing's overhead — projection logic, event schema versioning,
replay infrastructure — does not pay for itself. The document model is one
file with nine fields, replaceable atomically by a single shell-write. If
session-log later grows into structured machine-parseable events, B2
becomes the migration target; the present ADR does not foreclose that.

C is rejected because plan content drifts after generation: an operator
adds design decisions to `plan.md` mid-session without re-running the
generator. ADR-discipline must be enforced at hand-off boundary, not only
at plan-generation boundary. The discovery doc flagged this seam (Red
Hotspot #1); locating the linter invocation in Session Continuity (with
the rule definition still owned by `claude-mini-pipeline`) keeps both
sides honest.

This invokes Principle 8 (document model is the 2-3× margin choice;
event-sourcing would be the 1000× choice) and Principle 9 (the entire BC
exists to satisfy the hand-off contract Principle 9 mandates). It applies
the cross-aggregate communication pattern established by ADR-0020 to a
cross-BC reference: Session Continuity reads `FeatureRun.dod_state` and
`FeatureRun.issue_ref` by ID; it never commands `claude-mini-pipeline`.

### Sub-decisions recorded explicitly

For traceability — `adr-reviewer` should be able to locate each:

1. **BC placement: sibling, not sub-aggregate.** Session Continuity is a
   bounded context peer to `claude-mini-pipeline`, not a sub-aggregate
   inside it. Rationale: orthogonal lifecycles per ADR-0020. Rejected
   alternative: Approach A (embed in `FeatureRun`).

2. **Aggregate root: `STATE.md` (document model).** `STATE.md` is the
   aggregate root; `Session` is an attribute (`session_id`) of it.
   Rationale: Principle 8. Rejected alternative: Approach B2
   (event-sourced `Session` with `STATE.md` as projection).

3. **Cross-BC reference pattern: `active_feature_run_id` is a pointer,
   not an embedded copy.** Session Continuity reads `FeatureRun.dod_state`
   and `FeatureRun.issue_ref` by ID at snapshot time; it does not mirror
   or cache those attributes. The relationship type is **Customer/Supplier**
   (Session Continuity is customer; `claude-mini-pipeline` is supplier of
   run state). Pattern source: ADR-0020 cross-aggregate communication.

4. **`session_id` format: UTC ISO-8601 timestamp** (e.g.,
   `2026-05-03T14:32:00Z`). Rationale: human-readable, sortable, no
   external dependency (no ULID library, no git operation required).
   Rejected alternatives: ULID (collision-resistant but opaque), git-style
   short hash (collision-prone at low cardinality), operator-typed string
   (no uniqueness guarantee).

5. **session-log entry order: newest-at-bottom.** True append; new entries
   are appended to the file end. Rationale: matches the append-only
   invariant mechanically — a pre-commit check can verify by `diff
   --unified=0` that only trailing additions exist. Rejected alternative:
   newest-at-top (more journal-like reading, but every new entry rewrites
   the file head, breaking mechanical append-only enforcement).

6. **plan.md linter scope: active branches only, not git history.**
   `plan-lint.sh` runs against `plan.md` on the current branch at hand-off
   time. Historic `plan.md` files in old commits are not in scope and are
   not retroactively gated. Rationale: linter is a hand-off-time check;
   historic plans are not being handed off. The invocation is owned by
   Session Continuity (when to run); the rule definition (what counts as
   a design decision and how ADR-ref is asserted) stays in
   `claude-mini-pipeline`. Resolves discovery Red Hotspot #1.

7. **session-log entry format: markdown prose, not YAML.** Each entry is
   a human-readable narrative paragraph or bullet list. Rationale:
   Principle 8 — structured machine parsing of session-log is not a
   current consumer requirement; the current consumer is a human (or LLM
   reading natural language) trying to resume. Rejected alternative:
   YAML front-matter + structured fields (premature; would force schema
   decisions before there is a parser to break).

8. **session-log and `events.jsonl` (gate-audit) remain separate,
   intentionally.** Different consumers (human resume vs. ROI analysis),
   different formats (markdown narrative vs. structured JSONL),
   different append-only mechanisms. No unification planned. Resolves
   discovery Red Hotspot #4. Rejected alternative: a single unified
   append-only event log; rejected because consumer requirements are
   genuinely orthogonal and unifying the schemas would require forcing
   one of them to accept the other's format.

9. **Stale `STATE.md` detection: WARNING-only at this stage.** When
   `stop-hook` writes a snapshot whose operator-asserted fields
   (`next_3_actions`, `blocked_on`, `open_questions`, `risk_flags`)
   contain TODO placeholders, the hook logs a WARNING line to
   `stop.log`. It does not block. Rationale: hard-block requires
   detection logic that reliably distinguishes "operator chose to leave
   field empty as a valid empty state" (e.g., `risk_flags: []`) from
   "operator did not fill it in"; that disambiguation is not yet
   designed. Hard-block is recorded as a follow-up. Resolves discovery
   Red Hotspot #7 with explicit deferral. Rejected alternative: hard-
   block on TODO placeholders; rejected because false-positives on
   legitimately-empty fields would degrade the pipeline more than the
   silent-failure risk degrades it today.

### Cross-BC communication

Session Continuity holds `active_feature_run_id` as a reference-only
pointer into `claude-mini-pipeline`. Concretely:

* When `STATE.md` is written, `active_feature_run_id` records the GitHub
  issue ref (e.g. `#128`) of the in-flight `FeatureRun` (or `null`).
* When `STATE.md` is read by a resuming session, the reader resolves the
  reference by reading the issue and (if needed) the live `FeatureRun`
  state in `docs/domain/` — Session Continuity does not duplicate
  `FeatureRun` state.
* Session Continuity emits no commands into `claude-mini-pipeline`. It
  consumes pipeline events (`FeaturePipelineStarted`, `DoDSatisfied`,
  `AdvisorReturned`) to know when to update its own snapshot, but it
  does not call back.
* If `active_feature_run_id` resolves to a closed/deleted/reopened issue
  (discovery Red Hotspot #8, undefined), the snapshot stays as recorded;
  resume logic surfaces a "stale reference" warning. The exact warning
  mechanism is implementation detail for `/implement`, not this ADR.

### Scope of artifacts (what this ADR commits to)

Inside Session Continuity BC, after `/implement`:

* `STATE.md` exists at repo root with nine fields: `session_id`,
  `date_iso`, `current_branch`, `last_commit_sha`,
  `active_feature_run_id`, `next_3_actions`, `blocked_on`,
  `open_questions`, `risk_flags`. Cap ≤200 lines.
* `session-log/YYYY/MM/YYYY-MM-DD.md` exists with one file per UTC day,
  newest entry at bottom, markdown prose format.
* `docs/domain/session-continuity/overview.md` exists with the BC Canvas
  derived from `continuity-discovery.md`.
* `docs/domain/vocabulary.md` is extended with the 15 UL terms enumerated
  in `continuity-discovery.md` §"Ubiquitous Language extension".
* `bootstrap/scripts/plan-lint.sh` exists, grep-based, run by
  `stop-hook.sh`.
* `bootstrap/templates/STATE.md.template` exists for `--target`
  installation.
* `docs/runbooks/resume-drill.md` exists with the Human Resume Test
  procedure.

### Positive Consequences

* `Session`, `STATE.md`, `session-log`, `Hand-off`, `Triple Hand-off
  Contract`, `Resume`, `Continuity`, and `Human Resume Test` become
  first-class nouns in the Ubiquitous Language, available for citation
  from runbooks, ADRs, and PR text.
* `FeatureRun`'s aggregate surface stays at its post-ADR-0020 size; the
  recently-resolved God Aggregate problem does not regress.
* Mechanical invariants are checkable without LLMs: `wc -l STATE.md` for
  size cap, `grep` for ADR-ref in `plan-lint.sh`, file-existence checks
  for daily session-log entries.
* The cross-BC reference pattern is consistent with ADR-0020's
  cross-aggregate pattern; future readers see one pattern, not two.
* Document model is reversible: if usage data later justifies B2,
  migration is a structured re-write of existing `STATE.md` history into
  events, not a model overhaul.

### Negative Consequences

* **Cross-BC reference resolution failure is undefined.** If
  `active_feature_run_id` points at a closed, reopened, or deleted issue,
  the resume behaviour is "snapshot stays as recorded plus a warning" —
  the warning mechanism, location, and severity are not specified by
  this ADR. Discovery Red Hotspot #8 is left open.
* **STATE.md replacement is non-atomic with respect to session-log
  append.** `stop-hook` writes session-log first, then replaces
  `STATE.md`; if interrupted between the two, the next session sees a
  fresh log entry pointing at a stale snapshot. Plan §6 risk #3 records
  this; mitigation is order-of-operations (log first, snapshot second),
  not atomicity.
* **WARNING-only stale detection is a documented compromise.** Sub-
  decision 9 explicitly chooses warning over hard-block. Operators who
  ignore WARNING lines in `stop.log` will silently degrade the Human
  Resume Test. Hard-block is a follow-up, not protection delivered by
  this ADR.
* **Document model forecloses event-sourcing migration cheaply only as
  long as session-log stays prose.** If the log later acquires structure
  (sub-decision 7 reversed), every prose entry becomes a migration
  artefact requiring a parser. The cheapness of "B1 → B2 later" is
  conditional on sub-decision 7 holding.
* **Newest-at-bottom imposes a readability cost on every resume.** The
  reader must scroll past prior entries to reach the most recent. This
  is the stated cost of choosing mechanical append-only enforcement
  (sub-decision 5) over journal-like readability.
* **Markdown prose is not machine-parseable.** ROI analysis,
  cross-session aggregation, and structured queries over session history
  are not possible without a YAML/JSONL migration. Sub-decision 7
  records this trade-off intentionally.
* **Linter scope active-branches-only means historic plans escape.**
  `plan.md` files in older commits that lack ADR-ref discipline will
  never be linted. This is recorded scope (sub-decision 6), not a
  feature; it limits the linter's audit value.
* **Two intentionally-separate append-only logs (`session-log` and
  `events.jsonl`) must be maintained forever.** Sub-decision 8 commits
  to non-unification. The cost is two append-only mechanisms, two
  on-disk formats, two consumer audiences — and the discipline to keep
  them from drifting toward overlap.
* **Latent enforcement.** This ADR records the boundary and schema; the
  protection only materialises after `/implement` lands the BC overview,
  vocabulary entries, scripts, templates, and runbook. Between this
  ADR's merge and the implementation PR's merge, the BC is named but
  unmaterialised.
* **Three aggregate roots in `claude-mini-pipeline` plus `STATE.md` in
  Session Continuity is more documented surface than one aggregate
  ever was.** Total cognitive entry cost for new contributors rises
  with each extraction; this ADR adds another root and another BC.

## Pros and Cons of the Options

### Approach A — Embed session state in `FeatureRun`

* Good, because no new BC and no new vocabulary terms; one aggregate to
  reason about.
* Good, because `stop-hook` reads `FeatureRun` directly without
  cross-aggregate query plumbing.
* Bad, because session lifecycle and `FeatureRun` lifecycle are
  orthogonal; one session spans many `FeatureRun`s and vice versa.
  Embedding forces an artificial 1:1 mapping that does not exist.
* Bad, because it re-creates the God Aggregate problem ADR-0020
  resolved less than two weeks ago. The pipeline's recent modelling
  discipline would regress for the sake of avoiding a new BC.
* Bad, because `STATE.md` content includes data not derivable from any
  single `FeatureRun` (`open_questions`, `risk_flags`, prose narrative).
  Forcing those into `FeatureRun` attributes pollutes its invariants.

### Approach B1 — Sibling BC; `STATE.md` as document-model aggregate root

* Good, because lifecycle separation is honest: `Session` and
  `FeatureRun` belong to different bounded contexts because they are
  different things.
* Good, because the cross-BC reference pattern reuses ADR-0020 — one
  pattern for cross-aggregate AND cross-BC reads.
* Good, because document model means mechanical invariants (`wc -l`,
  `grep`) are sufficient — no projection logic, no event store, no
  replay infrastructure. Principle 3 satisfied directly.
* Good, because rollback to A is a delete; rollback from B2 to B1 is a
  schema migration. Choosing B1 first preserves optionality.
* Bad, because three roots in the pipeline plus a new BC root is more
  documentation surface than the project had a month ago.
* Bad, because document model forecloses cheap event-sourcing migration
  only while session-log stays prose; if the log structures, the cost
  reappears.
* Bad, because operator-asserted fields (`next_3_actions`, `blocked_on`,
  etc.) cannot be inferred mechanically — silent omissions degrade the
  Human Resume Test, and the warning-only mitigation is documented
  weakness, not strength.

### Approach B2 — Sibling BC; `Session` as event-sourced aggregate root

* Good, because event-sourcing is the modeling-purist choice: every
  hand-off is an event, `STATE.md` is a deterministic projection,
  history is reconstructible by replay.
* Good, because session-log entries become structured events natively;
  no separate "log vs event" question (Red Hotspot #4 dissolves).
* Bad, because event-sourcing infrastructure (event schema versioning,
  projection rebuilds, replay tooling) costs far more than the current
  scale justifies. Principle 8 violated by 100×.
* Bad, because the projection logic introduces a new failure surface:
  `STATE.md` can be wrong-but-reconstructible, where in B1 it is the
  source of truth and either right or absent.
* Bad, because the operator's mental model of "open the file, read it,
  resume" requires no projection step in B1 — the file is the model. In
  B2 the operator either trusts the projection or learns to replay.

### Approach C — Linter as part of `/plan` skill, not hand-off

* Good, because linter ownership is uncontested: it lives where plans
  are generated; no cross-BC seam (Red Hotspot #1 dissolves).
* Good, because two-leg hand-off contract (STATE.md + session-log) is
  simpler to explain than triple.
* Bad, because plans drift after generation. Operators and agents add
  design decisions to `plan.md` mid-session; without hand-off-time
  re-check, ADR-discipline gaps accumulate undetected until review.
* Bad, because hand-off is the meaningful enforcement boundary: review
  happens after hand-off, and Codex / external reviewers consume the
  plan as part of context. Letting drift through hand-off defeats the
  artifact.
* Bad, because the cross-BC seam (rule in pipeline, invocation in
  Session Continuity) is the honest model — owning the rule and the
  invocation in one BC pretends a coupling that exists between two BCs
  is internal to one.

## Confirmation

After this ADR is accepted and `/implement` lands the corresponding
artifacts, the following are concretely verifiable:

1. **`docs/domain/session-continuity/overview.md` exists** containing the
   Bounded Context Canvas (Purpose, Strategic classification,
   Responsibilities, Not-responsibilities, Inbound events, Outbound
   events, Collaborators, Distance from core) per
   `continuity-discovery.md`.
2. **`docs/domain/vocabulary.md` contains the 15 UL terms** listed in
   `continuity-discovery.md` §"Ubiquitous Language extension"
   (`active_feature_run_id`, `blocked_on`, `Continuity`, `Hand-off`,
   `Human Resume Test`, `next_3_actions`, `open_questions`, `plan.md
   Linter`, `Resume`, `risk_flags`, `Session`, `session-log`,
   `session_id`, `STATE.md`, `Triple Hand-off Contract`).
3. **`STATE.md` exists at repo root with the nine specified fields**,
   `wc -l STATE.md` returns ≤200, all fields present (empty values
   `null` or `[]` are valid; missing keys are not).
4. **`session-log/YYYY/MM/YYYY-MM-DD.md` exists** for the current UTC
   day at hand-off time, with newest entry appended at bottom in
   markdown prose.
5. **`bootstrap/scripts/plan-lint.sh` exists**, is bash, uses only `grep`
   / `awk` / `test` (no LLM), and exits non-zero when `plan.md` §3 or §4
   contains a design-decision line without an `ADR-ref` or an explicit
   `"no ADR — justification: ..."` token.
6. **`bootstrap/templates/STATE.md.template` exists** and is included in
   `bootstrap/universal-setup.sh`'s named-exception list, so `--target`
   installs the template into consumer repos.
7. **`bootstrap/hooks/stop-hook.sh` updates STATE.md mechanical fields
   and appends to session-log**, in that order (log first, snapshot
   second) per Negative Consequence "STATE.md replacement is non-atomic".
   When operator-asserted fields contain TODO placeholders, hook logs a
   WARNING line to `stop.log` (sub-decision 9).
8. **`docs/runbooks/resume-drill.md` exists** with Level 1 (5-minute
   gate) and Level 2 (1–2 hour onboarding-task gate) procedures from
   `plan.md` §5.
9. **`bootstrap/agents/domain-reviewer.md` is updated** to enumerate
   Session Continuity as a fourth distinct check item alongside
   `FeatureRun`, `GovernanceRun`, and `TwoVoiceReview` invariant tables.
   Without this, the structural protection of the new BC is latent —
   the same pattern ADR-0020 documented for its three roots.
10. **Cross-BC reference pattern is documented in
    `docs/domain/session-continuity/overview.md`**: Session Continuity
    reads `FeatureRun` state by ID; never commands `claude-mini-pipeline`.
    The pattern citation is to ADR-0020.

## Re-visit Trigger

Re-open this decision when **any one** is true:

* **Stale STATE.md WARNING fires often enough that hard-block becomes
  necessary.** Threshold: WARNING in `stop.log` on >20% of hand-offs over
  a 4-week window. Drives reversal of sub-decision 9 (and likely a
  follow-up ADR for the disambiguation logic between "valid empty" and
  "operator skipped").
* **Session-log volume or structure demands YAML / JSONL.** Threshold:
  any external consumer (an aggregator, a metric script, an agent
  doing ROI analysis) requests structured fields from session-log; or
  session-log files routinely exceed 1000 lines per day. Drives reversal
  of sub-decision 7.
* **`session-log` and `events.jsonl` prove to be the same family.**
  Threshold: a feature requires querying both as one stream, or schema
  drift between them produces a contradiction. Drives reversal of
  sub-decision 8 (unification ADR).
* **A second concurrent operator becomes real.** `vocabulary.md#Operator`
  defines operator as singular; this ADR inherits that. If multi-operator
  becomes a use case, the document model's "replace on hand-off"
  semantics produce write-conflicts (discovery Red Hotspot #9). Drives
  reversal toward B2 or toward a locking protocol.
* **Document model schema migration becomes painful.** Threshold:
  changing the nine-field schema requires manual migration of
  `STATE.md` files in active consumer repos. Drives evaluation of B2 as
  the new baseline.
* **Cross-BC reference resolution failure (`active_feature_run_id`
  pointing at deleted/closed/reopened issue) becomes a real bug.**
  Threshold: one confirmed resume failure attributable to a stale
  `active_feature_run_id` reference (binary event; a single occurrence
  is sufficient given that the failure mode is silent misdirection, not
  a recoverable warning). When triggered, a follow-up ADR specifies the
  resolution protocol. Discovery Red Hotspot #8.
* **A third hand-off leg is proposed** beyond `STATE.md` + `session-log`
  + `plan-lint.sh`. The Triple Hand-off Contract is binary today; a
  fourth leg makes it Quadruple, and the contract's all-or-nothing
  invariant must be re-stated.

## Links

* GitHub issue #128 — STATE.md + session-log + plan.md triple hand-off
  contract problem statement.
* `docs/decisions/0020-god-aggregate-sub-aggregate-extraction.md` — sub-
  aggregate extraction precedent; this ADR applies the same
  cross-aggregate communication pattern at cross-BC scope (sub-decision
  3).
* `docs/decisions/0021-adopt-nine-principle-hardened-revision.md` — Principle 9 hand-off contract ADR; this BC exists to materialise the continuity obligation Principle 9 mandates. Note: ADR-0021 is currently `proposed`, not `accepted`; the binding authority is `docs/principles.md#9` directly, which is in force regardless of ADR-0021's status.
* `docs/principles.md#9-перехват--контракт` — Principle 9, the hand-off
  contract this BC exists to satisfy.
* `docs/principles.md#8-антихрупкость-по-домену-запас-2-3-не-1000` —
  Principle 8, the basis for choosing document model over event-sourcing
  (sub-decision 2).
* `docs/principles.md#3-сначала-детерминированный-тулинг-потом-может-быть-агент` —
  Principle 3, the basis for `plan-lint.sh` being bash/grep, not LLM.
* `docs/principles.md#что-значит-архитектурно-значимо` — four
  architectural-significance triggers, all four firing for this
  decision.
* `docs/domain/continuity-discovery.md` — `domain-researcher` discovery
  output: 15 UL terms, BC Canvas, 10 Red Hotspots. This ADR resolves
  Hotspots #1, #2, #3, #4, #5, #7; defers #6, #8, #9, #10.
* `docs/domain/vocabulary.md` — current Ubiquitous Language; will be
  extended at `/implement` per Confirmation item 2.
* `docs/domain/overview.md` — `claude-mini-pipeline` BC overview; the
  sibling whose boundary this ADR sets.
* Repo-root `plan.md` — issue #128 plan; §4 records the chosen sub-
  decisions enumerated here.
* `bootstrap/agents/domain-reviewer.md` — load-bearing update site for
  Confirmation item 9 (latent-protection extension).
* `bootstrap/hooks/stop-hook.sh` — implementation site for Confirmation
  item 7.
