# 0015. Surface domain invariants to `/review` and `adr-reviewer` via loaded context and explicit cross-check instructions

* Status: accepted (2026-06-10)
* Date: 2026-04-24
* Deciders: venil
* Tags: pipeline, agents, domain, review

## Context and Problem Statement

`docs/domain/overview.md` declares four `FeatureRun` invariants (single issue-ref per run, monotonic DoD, two-voice state machine, advisor ≥ 2) and a six-row Policies table. Neither `/review` nor `adr-reviewer` currently consult this file: `/review` loads only the diff, `plan.md`, `principles.md`, and the ADR list; `adr-reviewer` reads `principles.md` but never cross-checks against declared domain invariants. The result is a silent gap — domain contracts are written down but structurally unconsulted, so any PR or ADR that violates them passes review. The gap was noticed during the ADR 0013/0014 sequence where pipeline-contract edits (agent wiring, checklist length) touched the same surface the invariants describe without any reviewer prompting an invariants cross-check. Issue #71 is the trigger: land the wiring now, while the gap is concrete and the two ADRs that exposed it are still fresh.

## Decision Drivers

* **Principle 4 (Knowledge in tools, not memory)** — invariants that live in `docs/domain/overview.md` but aren't loaded by the reviewers are exactly the failure mode Principle 4 names: knowledge in a file that no tool reads is decorative.
* **Reversibility** — the fix must be cheap to roll back if it dilutes review quality or produces false-positives; a prompt-level addition is one-line reversible, a new agent is not.
* **ADR 0014 checklist-length constraint** — Secondary Re-visit Trigger sits at 20 steps; adding a new gating agent in `/feature` spends one of the remaining slots on a gap that can be closed without a new gate.
* **Consistency with existing review loading pattern** — `/review` already loads `plan.md` and `principles.md` as `@file` context; `adr-reviewer` already opens `principles.md` in step 2 of its protocol. Extending the same pattern to `overview.md` is the least-surprise fix.
* **Explicit cross-check, not implicit presence** — loading a file into context does not cause a model to check against it; the prompt must tell the reviewer to do so. This drives Option A to need a two-part change (context + instruction), not one.

## Considered Options

* **Option A: Add `@docs/domain/overview.md` to `/review` context AND add explicit cross-check instructions to both `/review` and `adr-reviewer` prompts.** Two targeted prompt edits: one line added to `/review`'s context block, one instruction paragraph added to each of the two reviewers telling them to cross-check the diff/ADR against the invariants and policies sections. No new agent, no new `/feature` gate. `domain-reviewer`'s prompt is also extended with a parallel instruction (invariant cross-check when invoked) without changing its trigger.
* **Option B: New `contract-reviewer` agent** invoked as an extra gating step inside `/feature` after `/implement`, dedicated to checking diffs against declared invariants. Clean separation of concerns but adds a 7th agent and consumes another slot against ADR 0014's 20-step trigger.
* **Option C: Expand `domain-reviewer`'s trigger scope to also fire on pipeline-contract file changes** (`bootstrap/commands/feature.md`, `CLAUDE.md`, `docs/decisions/`). No new agent, but `domain-reviewer`'s current identity is "reviews domain docs for vocabulary drift"; expanding its trigger to pipeline-contract files creates a semantic mismatch and requires a maintained allowlist of "which files count as pipeline-contract."

## Decision Outcome

Chosen option: **Option A (context + explicit cross-check instruction in both reviewers)**, combined with a targeted *instruction* expansion to `domain-reviewer`'s prompt — not a trigger expansion. When `domain-reviewer` is invoked for any reason, its prompt will also require it to cross-check the current diff against `overview.md` invariants. Its trigger scope (change to `docs/domain/`) is unchanged; only its in-prompt checklist is extended. This is explicitly **not** Option C (trigger expansion), which is rejected: Option C changes when the agent fires, and that is where the semantic mismatch lives.

Rationale:

1. Principle 4 is satisfied at the smallest possible scope — every `/review` and every `adr-reviewer` run will load the invariants and be instructed to cross-check them. No centralization migration, no new wiring step in `/feature`.
2. ADR 0013's pipeline-contract-in-one-file gain is preserved: `/feature` is not touched, so the 16-step checklist does not grow and the ADR 0014 Secondary Re-visit Trigger (20 steps) does not advance.
3. Reversibility is strict: rollback is removing one `@file` line from `review.md` and one instruction paragraph from each of the two reviewer prompts. No agent to delete, no wiring to unthread.

Loading the full 142-line `overview.md` is the starting point. An alternative narrowing — extracting a smaller `docs/domain/contracts.md` containing only the Invariants and Policies sections — is a follow-up reachable without re-opening this ADR if the Primary or Secondary Re-visit Trigger below fires on context-dilution grounds. It is not among the three options above because it is a refinement of Option A's load target, not a peer architectural stance; committing to it now is a speculative optimization without field data from Option A's initial behavior.

Principles invoked: `docs/principles.md#4` (knowledge in tools, not memory), `docs/principles.md#1` (red flags over trade-offs — "just add the reference and hope the model notices" is the red flag; explicit cross-check instruction is the fix).

Recommendation presented for operator ratification; final decision reserved to operator per protocol.

### Positive Consequences

* Every `/review` automatically loads domain invariants and is instructed to cross-check; Principle 4 satisfied at minimum scope.
* Every `adr-reviewer` run cross-checks proposed ADRs against the `FeatureRun` invariants and Policies table, catching decisions that contradict declared contracts (e.g. a hypothetical ADR proposing to skip advisor calls would be flagged against the "advisor ≥ 2" invariant).
* No new agent in the roster — ADR 0014's Secondary trigger (20 steps) is unaffected.
* One-line per file reversal; cheapest rollback of the three non-null options.
* `domain-reviewer`'s usefulness is increased when it does fire without changing *when* it fires — no trigger drift, no allowlist maintenance.
* Ad-hoc invocations outside `/feature` (standalone `/review`, standalone `adr-reviewer`) gain coverage automatically — the loading pattern is invocation-path-independent, closing the "skills invoked directly get no agent coverage" gap ADR 0013 acknowledged.

### Negative Consequences

* **Context dilution in `/review`.** `overview.md` is ~142 lines. On large diffs the added context competes for attention; the reviewer may reference invariants pro forma without genuine cross-check. Mitigation: the contracts.md extraction path is held ready and conditioned on the Primary Re-visit Trigger.
* **Explicit cross-check instruction is mandatory, not incidental.** The naive reading of "add `@docs/domain/overview.md` to context" is that loading alone causes checking; it does not. If the prompt-edit half of this ADR is dropped during implementation, the reference becomes decorative — worst of both worlds (context cost without the check). Mitigation: the implementation PR must touch both halves atomically; `/review` invocations in CI should be scanned for the cross-check language in the first 5 runs.
* **Domain doc drift produces false-confidence reviews.** If `overview.md` invariants go stale (the pipeline evolves but the doc doesn't), reviewers will cross-check against a stale contract and approve diffs that violate the real contract. Worse than no check because it inoculates against the correct check. Mitigation: the domain doc's `Version:` header must be bumped in the same PR as any pipeline-contract change (already implied by Policy row `DomainDocsChanged → domain-reviewer`); ADR 0014's coarse staleness test provides a secondary backstop.
* **Ad-hoc context cost on ADR-only work.** Standalone `adr-reviewer` runs against older ADRs — not coupled to a current diff — still pay the `@file` context cost even when no diff cross-check is meaningful. The instruction scopes the check to "when a diff is present," but the file is loaded unconditionally; this is wasted tokens on a non-trivial minority of invocations.
* **No runtime enforcement.** This is a prompt-level intervention. A reviewer ignoring the instruction (model variance, truncation on very large diffs) produces a silent miss. The Primary Re-visit Trigger below measures exactly this, but detection is post-hoc, not preventive.
* **Responsibility drift risk for `domain-reviewer`.** Adding a cross-check-invariants instruction extends the agent's in-prompt scope without renaming it. Readers of the agent's `name: domain-reviewer` may expect the old narrower role. Mitigation: the prompt expansion must be explicit and short; adr-reviewer (the role, not the agent) checks this ADR's clarity on the point.

## Pros and Cons of the Options

### Option A: `@docs/domain/overview.md` context + explicit cross-check instruction in both reviewers (with domain-reviewer instruction expansion)

* Good, because it extends an existing loading pattern (`/review` already `@-`loads plan.md and principles.md); least-surprise fix.
* Good, because reversal is three single-line/single-paragraph edits across three files; cheapest non-null rollback.
* Good, because it does not consume a `/feature` checklist slot; ADR 0014's 20-step Secondary trigger is preserved.
* Good, because `domain-reviewer` becomes more useful when invoked without changing when it fires — no semantic mismatch.
* Bad, because adding 142 lines to every `/review` prompt risks context dilution, especially on large diffs.
* Bad, because prompt-level "please cross-check" instructions are soft — model variance and truncation can silently drop the check.
* Bad, because the `@file` context load is unconditional; ad-hoc `adr-reviewer` runs on older ADRs pay the token cost even when no diff cross-check applies.
* Bad, because the fix is split across two artifacts (context + instruction); if implementation lands only half, the reference becomes decorative without the check.

### Option B: New `contract-reviewer` agent wired into `/feature`

* Good, because it creates a named, auditable capability — "who checks invariants?" has a clean answer.
* Good, because concerns are separated: `domain-reviewer` stays narrow (vocabulary drift), `contract-reviewer` owns invariants.
* Good, because a gating step in `/feature` is harder to silently skip than a prompt-level instruction — failure modes are louder.
* Bad, because it adds a 7th agent to the roster; audit surface and onboarding cost both grow.
* Bad, because it consumes another slot on ADR 0014's 20-step Secondary Re-visit Trigger; room left before 20 is small.
* Bad, because the gating step only fires inside `/feature` — standalone `/review` or `/adr` invocations do not cross-check invariants, reintroducing the ad-hoc-coverage gap ADR 0013 named.
* Bad, because rollback requires deleting an agent file and un-wiring `/feature` — multi-file migration, not a one-line revert.
* Bad, because the justification for the new agent is "prompt-level intervention might not be heavy enough"; this is speculative without field data on Option A's behavior.

### Option C: Expand `domain-reviewer`'s trigger scope to pipeline-contract files

* Good, because no new agent, and expands existing agent's utility.
* Good, because it catches the inverse problem Option A leaves open: pipeline changes without domain doc updates (the ADR 0013/0014 class of edit).
* Bad, because `domain-reviewer`'s current identity is "reviews domain docs"; expanding the *trigger* to pipeline-contract files is a semantic mismatch readers of the agent's description will not expect.
* Bad, because pipeline-contract files are a maintained allowlist (`bootstrap/commands/feature.md`, `CLAUDE.md`, `docs/decisions/`) that drifts over time; new files will be missed.
* Bad, because `domain-reviewer`'s severity ladder is tuned for vocabulary drift and bounded-context violations, not invariant violations; the prompt would need a near-rewrite to also cover invariant-check work.
* Bad, because this does not help `/review` or `adr-reviewer` at all — they still don't load the invariants; a second intervention would still be needed.

## Confirmation

Validation is concrete and manual on the next 5 `/review` and `adr-reviewer` runs after implementation:

1. **Positive cross-check — `/review` on a pipeline-touching diff.** Stage a change to `bootstrap/commands/feature.md` that removes the issue-ref requirement. Run `/review`. Assert the review output references the `FeatureRun` "single issue reference" invariant or the `CommitAttempted without issue-ref → GovernanceBlocked` policy.
2. **Positive cross-check — `adr-reviewer` on an invariant-contradicting ADR.** Draft a test ADR proposing to skip advisor calls. Run `adr-reviewer`. Assert the output flags conflict with the `advisor() called ≥ 2 times` invariant.
3. **Negative baseline — no spurious invariant references.** Stage a docs-only change unrelated to pipeline. Run `/review`. Assert the review does NOT invoke invariants or policies where none apply (false-positive detection).
4. **Installer propagation check.** After `./bootstrap/universal-setup.sh --install`, `diff bootstrap/commands/review.md ~/.claude/commands/review.md` and `diff bootstrap/agents/adr-reviewer.md ~/.claude/agents/adr-reviewer.md` must both be empty.
5. **Atomicity check.** The implementation PR must touch both the `@file` context load AND the cross-check instruction in the same commit for each reviewer; partial landing (context without instruction, or vice versa) fails review.

All five checks are operator-driven, read-only, and produce observable output; no automation is required for this ADR to confirm.

## Re-visit Trigger

Four complementary triggers modeled on ADR 0014's rolling-window pattern (false-negative / false-positive on qualifying runs):

* **Primary (false-negative, cross-check missed).** Across the 10 most recent `/review` runs on pipeline-touching diffs, if ≥2 runs do not reference any `FeatureRun` invariant or Policies row when at least one applies to the diff, reopen this ADR. The prompt-level instruction is not producing deterministic cross-check in practice — consider Option B (named agent with a louder failure surface) or the contracts.md extraction follow-up to tighten signal.
* **Primary (false-positive, spurious invariant reference).** Across the 10 most recent `/review` runs overall, if ≥2 runs reference invariants or policies on a diff that touches none of the pipeline-contract surface, reopen — the loaded context is producing noise rather than signal, and the contracts.md extraction becomes the preferred follow-up.
* **Secondary (context dilution).** If any single `/review` run on a diff >500 lines fails the Positive check in Confirmation §1 with prompt-truncation evidence (model output cites that it did not read the full context), reopen for the contracts.md extraction as the next iteration.
* **Tertiary (staleness).** If a merged PR modifies pipeline-contract surface (`bootstrap/commands/feature.md`, `CLAUDE.md`, `bootstrap/agents/`, `bootstrap/commands/`) without bumping `docs/domain/overview.md`'s `Version:` header, and the following `/review` cross-checks against the stale invariants, reopen — the domain-doc-drift risk named in Negative Consequences has materialized and a stricter coupling (pre-merge check) is warranted.

All four triggers are falsifiable against `/review` output and git history.

## Links

* Closes #71 — domain invariants not consulted during `/review` or `adr-reviewer`
* Related: [0013](0013-agent-invocation-wiring.md) — centralized-in-`/feature` vs decentralized-per-skill axis; this ADR chooses a third path (in-prompt augmentation of existing reviewers) that neither 0013 option spanned
* Related: [0014](0014-feature-checklist-after-agent-wiring.md) — the 20-step Secondary Re-visit Trigger is the constraint that makes Option B (new gating agent) costlier than Option A
* Related: [0007](0007-read-only-critic-agents.md) — read-only critic constraint; Option A's instruction expansion stays within the read-only envelope
* `docs/principles.md#4` — knowledge in tools, not memory (the core driver)
* `docs/principles.md#1` — red flags over trade-offs (applied to reject "just add the reference, the model will notice")
* `docs/domain/overview.md` — source of the invariants and Policies table being surfaced
