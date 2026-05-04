# Ubiquitous Language Draft — Third Voice Review (issue #132)

**Status:** scratch draft, not authoritative. Input for a future `vocabulary.md` update and the ADR that will accompany the third-voice introduction.
**Scope:** new terms introduced by issue #132, plus existing terms whose definitions or invariants the feature would change.
**Format:** matches `docs/domain/vocabulary.md` style — bold header, one-sentence definition, discriminating note where confusion is likely.

---

## New terms

### Voice

A reviewer participating in the gating review protocol of a `FeatureRun`. Each voice is one independent review source whose output (approve/block/deferred) contributes to the protocol's terminal verdict. Currently two: Claude `/review` (first voice), Codex `/codex-review` (second voice); issue #132 introduces a third.

*Discriminating note:* a voice is not the same as an Agent, a Critic, or an Advisor. Agents (e.g., `adversarial-critic`, `security-reviewer`) feed findings into a voice's review; the Advisor sits outside the review protocol entirely (per `vocabulary.md#Advisor`). "Voice" specifically denotes participation in the review-gate protocol with verdict authority.

---

### Voice family

A grouping of voices by training-lineage and provider. A family shares enough underlying model heritage that two voices in the same family exhibit correlated bias patterns rather than independent error modes. Examples treated as distinct families: Anthropic Claude, OpenAI GPT/Codex, Moonshot Kimi, DeepSeek, Alibaba Qwen.

*Discriminating note:* family is coarser than model name and finer than vendor. Two Claude variants (Sonnet, Opus) are the same family; Claude and GPT are different families. The boundary is empirical — when reviewer outputs are statistically correlated beyond chance, the voices are in the same family for diversity purposes (per Panickssery 2024 and EMNLP 2025 findings cited in issue #132).

---

### Open-weight (model)

A reviewer model whose weights are publicly distributable, allowing inference via either a hosted API (OpenRouter) or local runtime (Ollama). Examples in scope for the third voice: Kimi K2.6, DeepSeek V4, Qwen3-Coder.

*Discriminating note:* "open-weight" is not the same as "open-source". A model can have published weights (open-weight) without an OSI-compatible licence on training data or pipeline. The distinction matters here only insofar as open-weight enables operator-controlled inference (no vendor account required), which is the property that lets the third voice exist as a Codex fallback.

---

### Closed-weight (model)

A reviewer model accessible only through the vendor's hosted API, with weights not distributable. The first two voices (Claude via Claude Code, Codex via ChatGPT Plus OAuth) are closed-weight.

*Discriminating note:* the open/closed-weight axis is orthogonal to the family axis. Cross-family diversity is the invariant the protocol enforces; open-weight is a property that happens to enable the third family in practice but is not itself the diversity guarantee.

---

### Third Voice Review

The third voice in the review protocol: an open-weight, cross-family reviewer invoked when (a) Codex is unavailable, or (b) the operator explicitly requests it. Backed by an open-weight model from a family disjoint from Claude (first voice) and Codex (second voice). Lives under `.claude/skills/third-voice-review/SKILL.md`.

*Naming note:* "Third Voice Review" is the protocol/concept. `ThirdVoiceReview` (if it becomes an aggregate) is the persisted lifecycle. `third_voice_review` (snake_case) is the `ReviewArtifact` type if one is introduced. Three forms, one concept — same pattern as Deferred Review.

*Discriminating note:* the third voice is not a tiebreaker. Under minority-veto strategy, it has equal blocking authority with the first two voices. It is also not a fallback in the sense of "second-best" — when invoked, its verdict is binding on the same terms as Claude's or Codex's.

---

### Fallback Third Voice

The trigger path in which the third voice fires automatically because Codex is unavailable (timeout, quota, missing install). Substitutes for the second voice; the protocol still has three voices when Claude + Codex + third-voice all run, or two voices (Claude + third) when Codex is skipped.

*Discriminating note:* fallback-third-voice does not eliminate the `type:deferred-review` issue mechanically. Whether the deferred-review issue is still created when the third voice substitutes for Codex is a Red Hotspot (see below) — the brief does not specify and Principle 1 forbids guessing.

---

### Invoked Third Voice

The trigger path in which the operator explicitly requests the third voice while Codex is also available. Produces a three-voice review with all three voices contributing verdicts under minority-veto.

*Discriminating note:* invoked-third-voice is the only path where all three voices run simultaneously. Fallback-third-voice replaces the second voice; invoked adds a third on top of two. The state-machine implications differ and may need distinct terminal states.

---

### Cross-family Panel

The composition rule for a multi-voice review: every voice in the panel must come from a distinct Voice Family. A panel that pairs two Claude variants is intra-family and does not qualify; a panel of Claude + Codex + Kimi is cross-family.

*Discriminating note:* cross-family is a panel-level invariant, not a per-voice property. A specific model is not cross-family by itself; it is cross-family relative to the rest of the panel. Adding a fourth voice from an existing family violates the invariant even if the original three were diverse.

---

### Minority Veto

The aggregation strategy in which any single voice returning a blocking verdict blocks the entire review, regardless of how the other voices voted. Two approves and one block → blocked. Sourced from arxiv 2510.11822.

*Discriminating note:* minority-veto is not majority-rule and not unanimous-approve. Majority-rule would let two approves override one block; unanimous-approve would require all voices to actively approve (a single deferred would block). Minority-veto requires no active block — a deferred or skipped voice does not itself block, only an active block does. The exact treatment of "deferred" under three voices is a Red Hotspot.

---

### Position Bias

The tendency of an LLM reviewer to weight findings differently based on the order in which artifacts (files, diff hunks, commits) are presented in the prompt. Earlier-presented hunks receive disproportionate attention; later hunks receive less. Documented in Panickssery 2024 and the EMNLP 2025 follow-up referenced by issue #132.

*Discriminating note:* position bias is a property of one voice's output, not of the panel. Cross-family diversity does not cancel position bias because all transformer-based LLMs share it to some degree. Mitigation requires per-voice intervention (Swap-and-Rejudge), not just panel composition.

---

### Swap-and-Rejudge

The position-bias mitigation procedure: when a voice issues a finding marked critical (typically a block), the diff is reordered (first hunk moved to last, or a defined permutation applied) and the same voice is re-prompted. If the verdict is unstable across orderings, the finding is treated as position-bias-induced rather than substantive; the operator decides whether to keep it.

*Discriminating note:* swap-and-rejudge is per-voice, post-hoc, and triggered only on critical findings — not a default re-prompt of every review. It does not change the Minority Veto rule; it only validates whether a particular block is robust to artifact ordering before letting that block veto the panel.

---

## Existing terms whose definitions extend or shift

### Two-voice Review (concept)

Currently defined as "Claude `/review` + Codex `/codex-review`" in `vocabulary.md`. With a third voice introduced, "two-voice" becomes the *degenerate case* of the multi-voice protocol — the panel size when only two voices are configured or available. The concept retains its name only for that case.

*Discriminating note:* whether to keep "two-voice" as a protocol name when three voices are possible, or to rename the protocol to "multi-voice review" with "two-voice" reserved for the panel-size-2 instance, is a Red Hotspot. Resolution requires an ADR; vocabulary cannot make this call unilaterally.

---

### TwoVoiceReview (aggregate)

The current aggregate root owns `claude_review` and `codex_review` ReviewArtifact types and a state machine over `{pending, agreed, deferred, disagreed, reconciled}`. A third voice is incompatible with the literal name and may be incompatible with the state machine (a three-way disagreement is not just "disagreed" between two parties). Three structural options exist:

1. Rename to `MultiVoiceReview`, generalize the state machine to N voices, retain a single aggregate.
2. Keep `TwoVoiceReview` for two-voice mode and introduce a distinct `ThreeVoiceReview` aggregate for the three-voice path; `FeatureRun` references whichever was used.
3. Keep `TwoVoiceReview` and add a sub-entity `ThirdVoice` that piggybacks on the existing aggregate without renaming.

*Discriminating note:* this is an aggregate-boundary change and is therefore ADR-significant per `docs/principles.md#что-значит-архитектурно-значимо`. The vocabulary draft cannot pick — see Red Hotspots.

---

### two_voice_state

Current valid transitions (`pending → agreed | deferred | disagreed → reconciled | deferred`) assume a 2-element verdict tuple. With three voices under minority-veto, the verdict space changes: any voice blocking → blocked outcome; need a state representing "all approve except deferred"; need to disambiguate "two agreed, one deferred" from "all three agreed".

*Discriminating note:* the precise revised transition diagram depends on the aggregate-restructuring choice above. Vocabulary records the open question; the actual transitions belong in the ADR.

---

### Deferred Review

Currently means "the second voice could not complete; a `type:deferred-review` issue is created; DoD graceful-degradation clause satisfied." With a third voice that fires automatically on Codex unavailability, the semantics shift: when the third voice runs successfully as fallback, is the review still "deferred"? Two possibilities:

1. Successful third-voice fallback ⇒ no deferred-review issue created; the panel is two-voice (Claude + third) and proceeds normally. "Deferred" then means *both* second-voice paths failed.
2. Codex skip always creates a deferred-review issue regardless of third-voice success, on the principle that the closed-weight Codex voice was the one originally specified by the protocol.

*Discriminating note:* this is a substantive policy decision, not a naming choice. Belongs in the ADR alongside aggregate restructuring.

---

### ReviewArtifact

Currently has a stable type set of three: `claude_review`, `codex_review`, `advisor_critique` (the last owned by `FeatureRun`, the first two by `TwoVoiceReview`). Third-voice introduces at least one new type (`third_voice_review`) and possibly more if each open-weight model produces a distinguishable artifact (`kimi_review`, `deepseek_review`, `qwen_review`). The "stable at three" invariant in `overview.md#TwoVoiceReview` is broken by either choice.

*Discriminating note:* the cardinality question (one type for all open-weight third voices, or one per model) is a domain decision that affects how panel-composition is recorded and audited. Belongs in the ADR.

---

### Codex CLI (Context Map entry)

Currently classified as Conformist in the context map. The third voice introduces a second external review interface (OpenRouter API and/or Ollama local runtime). These are new external BCs — they do not collapse into the Codex entry.

*Discriminating note:* OpenRouter and Ollama are different integration types (hosted-API vs. local-process) and may warrant separate context-map rows even though they serve the same domain function. The Anthropic API is currently mapped as Separate Ways via Claude Code abstraction; the third-voice integrations have no equivalent abstracting layer at the moment, so the relationship type is genuinely open.

---

## Bounded context fit

The third voice fits inside `claude-mini-pipeline` BC. Reasoning:

- **Same actors** — Operator, Main Loop, and the existing review skills/agents. No new principal.
- **Same lifecycle binding** — every third-voice review is scoped to one `FeatureRun`, the same way `TwoVoiceReview` is. There is no third-voice activity outside the feature pipeline.
- **Same purpose** — the review-gate role of the BC is preserved; what changes is the panel composition, not the pipeline's responsibility.
- **Infrastructure is below the BC line** — OpenRouter API and Ollama runtime sit at the same conceptual level as Anthropic API in the existing context map (`overview.md#Context-Map`): below the boundary, accessed through abstracting layers, classified as Separate Ways or Conformist depending on whether an ACL is built.

What is genuinely new and worth flagging without escalating: the cross-family-diversity rule is a new *kind* of policy. Existing policies in this BC are event-triggered (`DomainDocsChanged → invoke domain-reviewer`); the diversity rule is a structural composition invariant on the review panel itself, not a trigger-action pair. It belongs in the BC but stretches the current Policies table format. The ADR should decide whether to extend the Policies table or introduce a separate "Composition rules" section.

---

## Aggregate impact

Three aggregates in `claude-mini-pipeline` BC could be touched, in decreasing order of disruption:

**`TwoVoiceReview` is the primary impact site.** Adding a third voice changes (a) the aggregate's name (literal "two-voice" no longer accurate), (b) the `ReviewArtifact` type set it owns (currently two types `claude_review` + `codex_review`; potentially three or more), and (c) the state machine (`two_voice_state` transitions assume binary agreement). All three changes are aggregate-boundary or aggregate-invariant changes and are therefore ADR-significant per the principles. The vocabulary draft does not pick a structural option — the choice between rename/extend/split is a Red Hotspot.

**`FeatureRun` is touched lightly but unavoidably.** Its DoD invariant currently reads `TwoVoiceReview.state ∈ {agreed, reconciled, deferred}`. If the aggregate is renamed or split, this reference must update. If the state machine grows new terminal states (e.g., `vetoed` to capture minority-veto block), the DoD condition must enumerate them. `FeatureRun` does not gain new commands or invariants beyond this reference update.

**`GovernanceRun` is unaffected.** Commit governance has no opinion on review-panel composition. The third voice does not change Conventional Commits enforcement, issue-ref enforcement, or ADR-ref enforcement. Confirmed by inspection of the GovernanceRun invariants in `overview.md#GovernanceRun`.

What is *not* added at the aggregate level: the third voice does not introduce a fourth aggregate root. The third-voice lifecycle is the lifecycle of one panel within one `TwoVoiceReview` (or its successor), not an independent process worth its own aggregate. This stays consistent with ADR-0020's rationale for the existing three roots.

---

## Red Hotspots (open questions for the ADR)

1. **Aggregate restructuring path.** Three structural options enumerated under "TwoVoiceReview (aggregate)" above — rename to `MultiVoiceReview`, split into `TwoVoiceReview` + `ThreeVoiceReview`, or extend `TwoVoiceReview` with a sub-entity. Decision is ADR-significant; not a vocabulary call.

2. **Deferred-review-issue policy under third-voice fallback.** When Codex is unavailable and the third voice runs successfully, is `type:deferred-review` still created? Two policies possible (enumerated under "Deferred Review" above); the choice has audit-trail and DoD-grace-clause implications.

3. **`ReviewArtifact` type cardinality for the third voice.** One type (`third_voice_review`) covering all open-weight models, or one type per model (`kimi_review`, `deepseek_review`, `qwen_review`). Affects panel-composition auditability and the "stable at three types" invariant currently in `overview.md`.

4. **Treatment of `deferred` under minority-veto with three voices.** Does a deferred third voice (e.g., OpenRouter quota exhausted) block the panel, count as approve, or require fallback to two-voice? Minority-veto literature does not specify; this is a project-level policy choice.

5. **Cross-family-diversity enforcement mechanism.** The rule is asserted in the brief; no mechanism is named. Honor-system, agent-checked at runtime, or static-config-validated. Belongs in the ADR's Internal Compliance section.

6. **OpenRouter vs Ollama context-map classification.** Currently undefined. Hosted-API (OpenRouter) is structurally similar to Codex CLI (Conformist); local-runtime (Ollama) is closer to a self-hosted dependency with no current analogue in the context map. May need two new rows or one combined.

7. **Position-bias mitigation scope.** Swap-and-Rejudge is described in the brief as applied "on critical findings". The threshold for "critical" is not domain-defined yet — block-only? block+suggest? block+suggest+nit? Affects compute cost and review latency.
