# 0020. Extract `GovernanceRun` and `TwoVoiceReview` as sub-aggregates of `claude-mini-pipeline`

* Status: accepted
* Date: 2026-04-28
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: domain, bounded-context, aggregate, ddd, modeling
* Related issue: #108

## Context and Problem Statement

`FeatureRun` is the single aggregate root of bounded context `claude-mini-pipeline`.
It owns 19 commands, 23+ events, two independent state machines (`dod_state`,
`two_voice_state`), and four entities. The empirical trigger is the two-voice
state machine being found incomplete twice within a single PR (#102) — a
surface-area symptom, not a documentation-quality symptom. Red Hotspot #2 in
`docs/domain/overview.md` names the candidate split: extract the governance
sub-flow and the two-voice sub-flow as separate aggregate roots within the
same BC. The paper analysis in repo-root `plan.md` confirms clean cleavage on
both proposed boundaries.

The decision is architecturally significant per
`docs/principles.md#что-значит-архитектурно-значимо`: it changes a
cross-aggregate boundary inside a bounded context — i.e., the contract between
sub-domains documented in `docs/domain/`. The change is documentation-only
(this is a meta-repository), but the boundary it draws is binding for all
future domain edits and `domain-reviewer` checks.

## Decision Drivers

* **First-class identity in the ubiquitous language.** A modeling concept that
  warrants its own state machine, command set, and lifecycle deserves a
  named aggregate root in `vocabulary.md` rather than a sub-section of
  another root's table. The two-voice state machine already exists as a
  named invariant of `FeatureRun` — it is an aggregate in everything but
  declaration.
* **Honest cross-aggregate coupling over hidden in-aggregate coupling.**
  `dod_state` already depends on two-voice completion; today the
  dependency is implicit (both attributes live on the same root). Making
  the dependency a cross-aggregate read makes the coupling visible to
  every future domain editor.
* **Documentation-only cost.** No production code, no migration, no schema,
  no runtime behavior. The cost is editorial and reviewer-discipline cost,
  not engineering cost.
* **Boundary clarity already established by paper analysis.** `plan.md`
  resolves the four open questions previously cited as boundary doubts:
  two are settled by `vocabulary.md` (advisor and security/reliability
  command placement), two are intra/cross-aggregate design choices that
  this ADR makes explicit.

## Considered Options

* **Approach A — Full sub-aggregate extraction:** introduce `GovernanceRun`
  and `TwoVoiceReview` as separate aggregate roots within
  `claude-mini-pipeline`. `FeatureRun` references each by run-scoped ID;
  each new root owns its own command/event table, state machine, and
  invariant section.
* **Approach B — Documented sub-sections within `FeatureRun`:** keep
  `FeatureRun` as the sole aggregate root. Add `### Governance flow` and
  `### Two-voice review flow` sub-sections in `overview.md` with their
  own scoped invariant tables; update `domain-reviewer` to check the
  sub-sections as named items.
* **Approach C — Close #108 as premature:** the issue itself states that
  if the boundary is unclear it should be closed. Defer extraction until
  the ambiguity (perceived or actual) resolves.

## Decision Outcome

Chosen option: **Approach A — full sub-aggregate extraction.**

The honest argument is about modeling, not enforcement. Approach B can in
principle deliver comparable regression protection: a scoped sub-section
table plus an updated `domain-reviewer` checklist that names the two
sub-flows as separate check items would catch the same class of miss that
triggered PR #102. The advisor flagged this symmetry explicitly and it must
not be papered over.

What B cannot deliver, and what tips the decision to A, is **first-class
identity in the ubiquitous language**: `TwoVoiceReview` and `GovernanceRun`
become referenceable nouns. `FeatureRun.dod_state` evaluation reads
`TwoVoiceReview.state` by ID, not by reaching into a sibling sub-section
of its own attribute table. Future ADRs, runbooks, and PR descriptions can
say "the GovernanceRun retry semantics" or "TwoVoiceReview's deferred
state" with one canonical referent. Under B, those phrases either name
sub-sections (a documentation construct) or attributes of `FeatureRun` (a
larger-than-necessary root), and the modeling weight of the concepts stays
implicit.

This invokes `docs/principles.md` Principle 4 (knowledge in tools, not
memory): the model in `docs/domain/` is the source of truth, and the
truth being modeled is that two-voice review and governance enforcement
are coherent lifecycles with their own state, not merely sub-flows of a
larger orchestration. Naming them as such is the documentation discipline
the principle demands.

Approach C is rejected: `plan.md` §3 demonstrates that the four items
previously cited as boundary doubts are either already settled by
`vocabulary.md` or are intra/cross-aggregate design decisions this ADR
records. The issue's premature-close clause is not triggered.

### Five decision points recorded explicitly

For traceability — adr-reviewer should be able to locate each:

1. **Yes/no on extraction:** **yes.** `GovernanceRun` and `TwoVoiceReview`
   become aggregate roots within `claude-mini-pipeline`. (This subsection.)
2. **Cross-aggregate DoD evaluation pattern:** `FeatureRun.dod_state`
   transitions to `done` only after reading `TwoVoiceReview.state` by
   run-scoped ID. The relationship is **query, not embed**: `FeatureRun`
   does not own a copy of two-voice state; it references the
   `TwoVoiceReview` aggregate associated with the same run. (Spelled out
   below in "Cross-aggregate communication".)
3. **`GovernanceRun` retry semantics:** **one `GovernanceRun` per
   `FeatureRun`, with an internal retry counter.** A `GovernanceBlocked`
   event increments the counter and remains within the same `GovernanceRun`
   instance; `GovernanceApproved` terminates it. Multiple commit attempts
   within a single feature run share one `GovernanceRun`.
4. **Non-migration of `SecurityReview` / `ReliabilityReview` commands:**
   these stay in `FeatureRun`. They are conditional prod-bound gates
   triggered alongside two-voice review, not part of the two-voice
   protocol. They must not be migrated into `TwoVoiceReview` by future
   editors.
5. **`domain-reviewer` scope update is a consequence of this ADR:** the
   structural protection from extraction is **latent** until
   `bootstrap/agents/domain-reviewer.md` is updated to check `FeatureRun`,
   `GovernanceRun`, and `TwoVoiceReview` invariants as three distinct
   items. This is not optional and is listed in Confirmation below.

### Cross-aggregate communication

`FeatureRun` evaluating `dod_state = done` MUST read `TwoVoiceReview.state`
by ID reference. The two-voice state is **not** copied into `FeatureRun`'s
attributes. Concretely, in `docs/domain/overview.md`:

* `FeatureRun` retains `dod_state`, `advisor_call_count`, `adr_required`,
  and the `issue_ref`.
* `FeatureRun` no longer owns `two_voice_state`; that attribute moves to
  `TwoVoiceReview`.
* The DoD invariant statement reads: "`dod_state` may transition to `done`
  only when the associated `TwoVoiceReview.state ∈ {agreed, reconciled,
  deferred}`."

`GovernanceRun` is consulted similarly: `FeatureRun` reads
`GovernanceRun.state` (must be `approved`) before the DoD checklist
permits merge.

### Scope of extraction (what moves and what stays)

* **Moves to `TwoVoiceReview`:** commands `RequestReview`,
  `RequestCodexReview`, `RecordTwoVoiceResult`; events `ReviewRequested`,
  `CodexReviewRequested`, `CodexReviewSkipped`, `TwoVoiceAgreed`,
  `TwoVoiceDisagreed`, `TwoVoiceReconciled`, `DeferredReviewIssueCreated`;
  attribute `two_voice_state`; entities `ReviewArtifact` of type
  `claude_review` and `codex_review`.
* **Moves to `GovernanceRun`:** command `AttemptCommit`; events
  `CommitAttempted`, `GovernanceBlocked`, `GovernanceApproved`; internal
  retry counter.
* **Stays in `FeatureRun`:** all lifecycle commands not listed above —
  notably `RequestSecurityReview`, `RequestReliabilityReview`,
  `InvokeAdvisor`, `DraftADR`, `RequestADRReview`,
  `DeclareDoDSatisfied`, `CreatePR`, `MergeToMain`, `MergeADR`. Entity
  `ReviewArtifact` of type `advisor_critique` stays in `FeatureRun` (per
  `vocabulary.md`: advisor is not part of two-voice review).

### Positive Consequences

* Red Hotspot #2 in `overview.md` resolves: the two-voice state machine
  lives in its natural home; the governance sub-flow has a named owner.
* `TwoVoiceReview` and `GovernanceRun` become referenceable nouns in the
  ubiquitous language, available to future ADRs, runbooks, and PR text.
* Per-root invariant tables shrink to manageable surface area; reviewer
  completeness checks operate against three small tables instead of one
  large one.

### Negative Consequences

* **DoD evaluation now requires a cross-aggregate read.** `FeatureRun`
  cannot evaluate `dod_state = done` without consulting `TwoVoiceReview`
  (and `GovernanceRun`). The coupling is explicit, not absent — this is
  the cost of separating concerns. Future editors must keep the read
  pattern documented and consistent.
* **`advisor_critique` entity stays in `FeatureRun` while its two sibling
  `ReviewArtifact` types move to `TwoVoiceReview`.** The split is correct
  per `vocabulary.md` ("advisor is not part of two-voice review") but
  unusual: one entity type is now scattered across two aggregates by
  type-discriminator. This is a documented seam and `vocabulary.md` must
  call it out, or a future reader will read it as inconsistency.
* **Latent protection.** Extraction has zero regression-protection effect
  until `bootstrap/agents/domain-reviewer.md` is updated to enumerate the
  three roots as distinct check items. Between this ADR's merge and that
  bootstrap update landing, the model carries the new structure without
  the new enforcement.
* **Three aggregate roots increase the learning surface for new
  contributors.** A reader must understand three lifecycles, three
  invariant sets, and the cross-aggregate references between them, where
  previously one root sufficed. Total content volume rises (small) but
  cognitive entry cost rises with it.
* **Naming and citation churn.** `vocabulary.md` gains two new terms;
  `FeatureRun` and `two_voice_state` entries change; `overview.md`
  command and event tables restructure; existing ADRs and runbooks that
  cite "FeatureRun's two-voice state" remain technically accurate (the
  state still concerns the same FeatureRun) but read as stale.
* **`SecurityReview` and `ReliabilityReview` placement is an honor-system
  invariant.** This ADR records that they stay in `FeatureRun`, but
  nothing mechanically prevents a future editor from migrating them into
  `TwoVoiceReview` on the (incorrect) grounds that they are "also
  reviews". `domain-reviewer`'s checklist must include this as a guard,
  or future drift is inevitable.
* **Throwaway-by-design if BC ever splits.** If `claude-mini-pipeline` is
  later split into multiple bounded contexts (e.g., a separate Governance
  BC), this ADR's intra-BC sub-aggregate boundaries become inter-BC
  context-map relationships, and the cross-aggregate query patterns
  defined here are replaced by anti-corruption-layer translations. The
  split is future-only; this ADR does not anticipate it.

## Pros and Cons of the Options

### Approach A — Full sub-aggregate extraction

* Good, because it gives `TwoVoiceReview` and `GovernanceRun` first-class
  identity in the ubiquitous language, available for reference from any
  future doc, ADR, or PR description.
* Good, because per-root invariant tables are individually enumerable —
  `domain-reviewer` can check each as a distinct item once its scope is
  updated.
* Good, because the cross-aggregate coupling between `FeatureRun.dod_state`
  and `TwoVoiceReview.state` becomes explicit (a documented query) instead
  of implicit (two attributes on the same root).
* Good, because `FeatureRun`'s command/event surface shrinks to the
  ~10 lifecycle commands that are genuinely about the run, not the sub-flows.
* Bad, because three roots are more than one root; total documented
  surface and cross-references both rise.
* Bad, because the `advisor_critique` / `claude_review` / `codex_review`
  entity-type split across two aggregates is a documented seam that
  future readers will probe.
* Bad, because the regression-protection benefit is **latent**: it requires
  `domain-reviewer` to be re-scoped before the structural change pays off,
  and that update is a separate piece of work.

### Approach B — Documented sub-sections within `FeatureRun`

* Good, because no new aggregate roots — fewer concepts to introduce in
  `vocabulary.md`, no cross-aggregate query pattern to specify.
* Good, because `domain-reviewer` can be given the same per-section
  checklist (Governance flow / Two-voice review flow) as a list of
  distinct items, delivering comparable regression protection to A on the
  PR #102 class of miss.
* Good, because no editorial churn outside `overview.md` and the agent
  prompt; existing citations to "`FeatureRun`'s two-voice state" remain
  literally correct.
* Bad, because two-voice review and governance enforcement remain
  sub-flows of `FeatureRun` rather than named aggregates — they cannot be
  referenced by their own names from external docs without a sub-section
  pointer.
* Bad, because `FeatureRun`'s root-level surface (commands, events,
  attributes, invariants) stays at its current size; the per-section
  scoping is a presentation choice, not a model change.
* Bad, because the modeling argument that two-voice review *is* a
  coherent lifecycle (it has its own state machine, command set, and
  invariants) is suppressed rather than recognised.

### Approach C — Close #108 as premature

* Good, because zero immediate work; defers a structural change until a
  clearer trigger emerges.
* Good, because no risk of mis-extracting (e.g., placing
  `SecurityReview` in the wrong aggregate) under time pressure.
* Bad, because `plan.md` already resolves the boundary clarity question;
  the issue's premature-close clause is not triggered by the current
  evidence.
* Bad, because Red Hotspot #2 stays open; the model continues to flag
  itself as suspect for the same reason that already produced one PR-102
  class miss.
* Bad, because deferring requires re-doing the paper analysis at a later
  date when the surrounding context may have moved.

## Confirmation

After this ADR is accepted and `/implement` lands the corresponding
domain-doc updates:

1. **`docs/domain/overview.md`** has three distinct invariant sections
   for `FeatureRun`, `GovernanceRun`, and `TwoVoiceReview`. Each lists
   commands, events, and invariants at the per-root scope. The cross-
   aggregate query pattern for DoD evaluation is documented in
   `FeatureRun`'s section.
2. **`docs/domain/vocabulary.md`** contains entries for `GovernanceRun`
   and `TwoVoiceReview` as aggregate roots. `FeatureRun` and
   `two_voice_state` entries are updated to reflect the extraction. The
   `advisor_critique` documented seam is called out in the
   `ReviewArtifact` entry.
3. **`bootstrap/agents/domain-reviewer.md`** enumerates three distinct
   check items: "FeatureRun invariants", "GovernanceRun invariants",
   "TwoVoiceReview invariants". Without this update the structural
   protection is latent. This is the load-bearing item; a passing
   `domain-reviewer` run after the next `docs/domain/` edit must show
   the three checks operating distinctly.
4. **Red Hotspot #2** in `overview.md` is marked resolved with an inline
   reference to `docs/decisions/0020-god-aggregate-sub-aggregate-extraction.md`.
5. **`SecurityReview` / `ReliabilityReview` placement check** is included
   in `domain-reviewer`'s checklist as an explicit invariant: these
   commands belong to `FeatureRun`, not `TwoVoiceReview`. A future PR
   that attempts to migrate them must trigger a `domain-reviewer` BLOCK.
6. **Manual command coverage check.** All 17 in-BC commands (13 in
   `FeatureRun`, 1 in `GovernanceRun`, 3 in `TwoVoiceReview`) are
   accounted for after extraction — none disappear, none are duplicated.
   The pre-extraction `overview.md` had 17 in-BC commands (the issue
   statement estimated 19; the actual pre-extraction count was 17).
   `PromoteTaskToIssue` is out-of-band and not counted here.
7. **`TwoVoiceReview` monotonicity invariant is enumerated explicitly.**
   `TwoVoiceReview`'s invariant section in `overview.md` states: the
   state machine has no backward transitions out of `agreed`, `reconciled`,
   or `deferred`. This property is load-bearing for the cross-aggregate
   DoD evaluation pattern — `FeatureRun` reads `TwoVoiceReview.state` and
   trusts it to be terminal-stable. Without this invariant stated, the
   coupling documented in decision-point 2 is incomplete.
8. **Policies table migration decision recorded in `overview.md`.**
   The current BC-wide Policies table contains rows triggered by events
   that migrate to `TwoVoiceReview` (`TwoVoiceDisagreed → deferred-review
   issue`) and `GovernanceRun` (`CommitAttempted without issue-ref →
   GovernanceBlocked`). The updated `overview.md` must explicitly state
   one of: (a) the Policies table remains BC-wide and is not per-aggregate,
   with a note that policy trigger ownership follows the owning aggregate;
   or (b) each root's section includes a per-root Policies sub-table.
   Either choice is valid; the choice must be stated so `domain-reviewer`
   has unambiguous guidance on policy-to-root alignment checks.
9. **ADR 0013 contingency noted.** Confirmation item 3 (domain-reviewer
   scope update) relies on `domain-reviewer` being invoked when
   `docs/domain/` changes. That invocation is governed by the policy
   `DomainDocsChanged → domain-reviewer`, which ADR 0013 formalises. ADR
   0013 status is `proposed`, not `accepted`. If ADR 0013 remains
   `proposed` when `bootstrap/agents/domain-reviewer.md` is updated, the
   structural protection from item 3 is contingent on honor-system
   invocation only — not on an accepted automated policy trigger.

## Re-visit Trigger

Re-open this decision when **any one** is true:

* The cross-aggregate DoD coupling proves unworkable in practice — for
  example, a future domain edit drives `dod_state` and
  `TwoVoiceReview.state` out of sync because the read pattern is unclear
  or a future reader interprets the relationship as embedded rather than
  queried.
* A third sub-aggregate candidate emerges within `claude-mini-pipeline`
  (e.g., the prod-bound review flow grows its own state machine and
  command set). The extraction pattern then generalises and this ADR
  should be re-stated as a pattern (or a follow-up ADR records the third
  extraction explicitly).
* `claude-mini-pipeline` itself is split into multiple bounded contexts.
  At that point the intra-BC sub-aggregate boundaries here become
  inter-BC context-map relationships, and the cross-aggregate query
  patterns defined here must be replaced by anti-corruption layers.
* `domain-reviewer`'s per-root checklist proves insufficient — i.e., a
  PR introduces an invariant violation that the three-root scope still
  misses. Then the model granularity itself, not just the agent
  scoping, requires re-evaluation.

## Links

* GitHub issue #108 — God Aggregate problem statement and premature-close
  clause.
* `docs/decisions/0007-read-only-critic-agents.md` — defines `domain-reviewer`
  as a read-only critic; the consequence of this ADR (item 5) extends its
  scope.
* ADR 0013 (proposed; cited by number per `overview.md` Red Hotspots #1
  and #7) — `domain-researcher` trigger; status `proposed`, not
  `accepted`. Noted here only because the cross-aggregate query pattern
  for DoD relies on `domain-reviewer` being invoked when `docs/domain/`
  changes (the policy ADR 0013 formalises).
* `docs/decisions/0019-installer-post-run-verification.md` — most recent
  ADR; structural reference for MADR 4.0 style.
* `docs/domain/overview.md` — current `FeatureRun` aggregate, command and
  event tables, Red Hotspot #2 (the symptom this ADR addresses).
* `docs/domain/vocabulary.md` — entries for `FeatureRun`, `Advisor`,
  `Two-voice Review`, `two_voice_state`, `ReviewArtifact` — sources for
  the boundary clarity arguments above.
* `docs/principles.md#4-знание-живёт-в-репо-в-репо-или-нигде` — Principle 4 (knowledge in tools,
  not memory): naming the modeled concepts in the ubiquitous language is
  a discipline this principle demands.
* `docs/principles.md#что-значит-архитектурно-значимо` — BC boundary /
  cross-context contract trigger.
* Repo-root `plan.md` — paper analysis confirming clean cleavage on both
  proposed boundaries.
* `bootstrap/agents/domain-reviewer.md` — load-bearing update site for
  the latent-protection consequence (item 5).
