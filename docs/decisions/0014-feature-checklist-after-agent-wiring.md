# 0014. Accept longer inline checklist and correct domain-researcher trigger

* Status: accepted
* Date: 2026-04-24
* Deciders: venil
* Tags: pipeline, orchestration, agents
* Supersedes in part: [0013](0013-agent-invocation-wiring.md) — canonical map row for `domain-researcher` trigger; refines 0013 Re-visit Trigger

> **Note on 0013 status coupling:** ADR 0013 is currently `proposed`. 0013 is expected to reach `accepted` status in the same implementation PR as this ADR (issue #60), or before this ADR is accepted. Until then, "supersedes in part" refers to the intended final state, not the current one.

## Context and Problem Statement

Two issues surfaced during `/plan` for issue #60 that block completion of the agent-wiring work authorized by ADR 0013:

1. **`domain-researcher` trigger is misstated in ADR 0013.** The canonical stage → agent map says `greenfield BC only`. The BC documentation (`docs/domain/overview.md` Red Hotspot #1) and operational reality say the correct trigger is `docs/domain/ missing or stale`. "Greenfield only" would mean the agent fires once per BC ever; "missing or stale" lets the agent re-engage whenever domain docs drift from the code, which is the actual need. The plan for #60 cannot wire `domain-researcher` correctly until this is settled.

2. **ADR 0013 Re-visit Trigger fires on first implementation.** 0013 says: *"If `/feature` TodoWrite grows beyond 12 steps total (agents included), reconsider Option A (decentralize per-skill)."* The plan for #60 adds `adr-reviewer`, `domain-reviewer`, `security-reviewer`, and `domain-researcher` invocations. Even with conservative inlining, the checklist grows to 15–16 steps. The trigger fires on the very first merge that implements 0013. Walking past a Re-visit Trigger without a ruling is a governance smell — it destroys the contract that triggers are real constraints.

## Decision Drivers

* **Principle 4 (Knowledge in tools, not memory)** — the wiring must land somewhere deterministic; deferring leaves agents in documentation only.
* **Principle 1 (Red flags over trade-offs)** — the Re-visit Trigger fired; we must rule on it, not equivocate. "Both options are fine" is the red flag itself.
* **Auditability of ADR 0013's checklist-length trigger** — if a trigger can be ignored on first fire without written justification, all future triggers lose weight.
* **Operator cognitive load on `/feature` invocation** — a 16-step checklist is heavier to scan than a 12-step one; the trigger existed because this cost is real.
* **Pipeline-over-fanout (ADR 0002)** — whatever shape we choose must not fragment the pipeline contract into multiple uncoordinated locations.
* **Reversibility** — the 6 weeks of ADR 0013 in force have not produced field data; the chosen shape should be cheap to reverse if it fails in practice.

## Considered Options

The central architectural decision is the shape of the feature checklist after agent gates are added. Decision #1 (domain-researcher trigger) is a scope correction to ADR 0013 and is not up for three-way debate — it is settled by the domain doc and included here as a coupled supersede.

* **Option A: Accept the longer inline checklist (stay with ADR 0013 Option B, consciously override the Re-visit Trigger).** `/feature` TodoWrite grows to ~16 steps; all agent gates remain inline as numbered steps. Override is justified in writing: the trigger measured the wrong thing.
* **Option B: Decentralize to per-skill agent invocation (ADR 0013 Option A, i.e. honor the Re-visit Trigger literally).** `/feature` checklist stays at ~12 steps. Each skill (`/adr`, `/plan`, `/implement`, `/review`) invokes its own agent internally. Revert ADR 0013's central decision.
* **Option C: Hybrid — `/feature` orchestrates pipeline stages; skills own their agent invocations within each stage.** `/feature` holds 12 coarse-grained stage steps; per-skill agent invocation is documented inside each skill's file. The orchestrator contract shrinks; the pipeline contract is split across `/feature` + 4 skill files.

## Decision Outcome

Chosen option: **Option A (accept the longer inline checklist, override the Re-visit Trigger with written justification)**, because of three independent reasons:

1. ADR 0013's Re-visit Trigger measured raw step count as a proxy for cognitive load, but the dominant cost in a checklist is conditional-branch density, not line count. Four of the added steps are guarded by clear conditions (`adr-needed` label, `docs/domain/` path touched, prod-bound PR, `docs/domain/` missing-or-stale) and are skipped on most runs — they occupy screen space but not decision space.
2. Options B and C both fragment the pipeline contract across skill files, which reintroduces the exact problem ADR 0013 solved — a Principle 4 violation where no single location holds the full pipeline.
3. ADR 0013's Negative Consequences already acknowledged "/feature grows more complex" and judged it acceptable. The 12-step trigger was a safeguard against runaway growth, not a prediction that 12 would be sufficient forever. Overriding it on the first fire is defensible if and only if the override is justified in writing (this ADR) and replaced with a better-measured trigger (see Re-visit Trigger below).

Recommendation presented for operator ratification; final decision reserved to operator per protocol.

Principles invoked: `docs/principles.md#4` (knowledge in tools, not memory), `docs/principles.md#1` (red flags over trade-offs — refuse the "both are fine" framing).

### Scope clarification and partial supersede of ADR 0013

The canonical stage → agent map row for `domain-researcher` is corrected to:

| Pipeline stage | Agent | Condition |
|---|---|---|
| pre-`/plan` | `domain-researcher` | `docs/domain/` missing for the affected BC, OR stale per operational test below |

"Greenfield BC only" as stated in ADR 0013 is retired. The implementation PR for #60 wires this corrected trigger into `/feature` and updates `CLAUDE.md`'s agents table accordingly.

**Operational test for "stale":** a domain doc is stale if **either** (a) the BC's source code or pipeline-level contracts have changed since the domain doc's last `Version:` header date AND no domain-doc update accompanied those changes, **or** (b) the operator declares it stale during `/plan`. The test is deliberately coarse — mechanical staleness detection is out of scope for this ADR. A finer test may be added if false positives/negatives accumulate (see Re-visit Trigger).

### Re-visit Trigger refinement for ADR 0013

ADR 0013's "beyond 12 steps" trigger is refined, not silently retired. The refined trigger (effective for both 0013 and this ADR) appears in the Re-visit Trigger section below.

### Positive Consequences

* Pipeline contract remains in one file (`bootstrap/commands/feature.md`); Principle 4 preserved.
* `domain-researcher` wiring in issue #60 is unblocked.
* The Re-visit Trigger fire is ruled on in writing — precedent is preserved: triggers force a decision, not a reflex.

### Negative Consequences

* **Precedent risk: overriding a Re-visit Trigger on first fire.** If this override is not tightly justified, future triggers become decorative. Mitigation: the refined trigger below is measurable on actual behaviour (gating accuracy), not a proxy (raw step count).
* **Operator cognitive load increases on every `/feature` run.** 16 steps vs 12 is ~33% more lines to scan. Conditional-skip reasoning is not free even when the condition evaluates to false — the operator still reads the line.
* **Failure surface of `/feature` expands.** More orchestration logic = more ways `/feature` can misfire (wrong condition evaluated, step skipped that shouldn't be). Failure in `/feature` still breaks all agent invocations simultaneously, as noted in 0013.
* **False-positive invocations for `solutions-architect` and `security-reviewer` remain possible.** Their conditions (`adr-needed`, "prod-bound") are natural-language checks; underspecified conditions lead to either spurious invocations or missed ones.
* **`domain-researcher` trigger change widens agent activity.** "Missing or stale" fires more often than "greenfield only". The operational test above is coarse; edge cases (recent BC code change but no semantic drift, old doc but still accurate) will miscategorise. Risk of agent fatigue if triggered too aggressively.
* **Split responsibility for the trigger refinement.** ADR 0013 retains its Re-visit Trigger text in-file; this ADR refines it. Readers of 0013 alone may miss the refinement — mitigation is a note appended to 0013's Links section in the implementation PR.

## Pros and Cons of the Options

### Option A: Accept the longer inline checklist

* Good, because pipeline contract stays in one file (0013's Option B is preserved, Principle 4 intact).
* Good, because conditional gating logic has full `/feature`-level context (labels, file paths, PR target) — skills invoked standalone do not have this.
* Good, because reversal cost is one PR editing one checklist block, same as 0013 already noted.
* Bad, because it overrides a Re-visit Trigger on first fire — governance precedent is dangerous.
* Bad, because 16 steps really are harder to scan than 12, independent of conditional density.
* Bad, because operators invoking skills directly (outside `/feature`) still get no agent coverage.

### Option B: Decentralize to per-skill agent invocation

* Good, because it literally honors 0013's Re-visit Trigger — no precedent erosion.
* Good, because skills become self-contained: `/adr` standalone still gets `adr-reviewer`.
* Good, because `/feature` stays at 12 steps — lighter cognitive scan.
* Bad, because wiring is scattered across `/plan`, `/adr`, `/implement`, `/review` — no single audit location, re-introducing 0013's root problem (Principle 4 violation).
* Bad, because skills have no `/feature`-level context — `/plan` cannot distinguish "this plan triggers `adr-needed`" from "this is a trivial plan"; result is over-invocation.
* Bad, because this reverts ADR 0013 Option B after ~6 weeks in force without field evidence that centralization failed — churn without data.

### Option C: Hybrid — `/feature` orchestrates stages, skills invoke agents

* Good, because `/feature` stays short (12 stage-level steps).
* Good, because skills become reusable outside `/feature` with their agent coverage intact.
* Bad, because the pipeline contract is now split across 5 files (`/feature` + 4 skills) — worse than either A or B for auditing.
* Bad, because conditional logic (`prod-bound`, `adr-needed`) lives at `/feature` level for some agents (`security-reviewer`) and at skill level for others (`adr-reviewer`) — inconsistency.
* Bad, because the split hides the ADR 0013 trigger: "hybrid" feels like it honored the trigger, but the real checklist length (across files) is the same.
* Bad, because reversal cost is now higher than 0013 estimated: migrating invocation logic back and forth across 5 files is a multi-PR effort.

## Confirmation

Validation is empirical on the next 5 `/feature` runs after the #60 implementation PR merges. Concrete checks:

1. Run that touches `docs/domain/` must show `domain-reviewer` invocation in the task log.
2. Run bound for a prod-affecting PR must show `security-reviewer` invocation inside the `/review` phase.
3. Run where `docs/domain/` is missing or stale for the affected BC (per the operational test above) must show `domain-researcher` invocation pre-`/plan`.
4. Run with `adr-needed` label or ADR-significant decision must show both `solutions-architect` (pre-draft) and `adr-reviewer` (post-draft).
5. Run that is none of the above (trivial bug-fix, docs typo) must show zero agent invocations — no false positives.

If any qualifying run misses a required invocation, or any trivial run spawns a spurious invocation, reopen this ADR. The check is visual inspection of `/feature` task-log history; no automation is required for this ADR to confirm.

## Re-visit Trigger

Refined trigger replacing ADR 0013's raw step-count measure. This trigger governs both 0013 and this ADR.

The trigger counts **qualifying runs** — runs whose inputs make a given gate applicable (e.g., only prod-bound runs are qualifying for `security-reviewer`). Non-qualifying runs are excluded from the denominator so the trigger cannot silently become unfireable on naturally-uneven traffic.

* **Primary (false-negative):** Across the 10 most recent qualifying runs for any single gate (rolling window, reset per gate), if ≥2 runs skip that gate when its condition held, reopen both 0013 and 0014 — the centralization model is not producing deterministic gating in practice.
* **Primary (false-positive):** Across the 10 most recent runs overall, if ≥2 runs invoke any agent whose condition did not hold, reopen both 0013 and 0014 — conditions are underspecified and centralization is amplifying noise.
* **Secondary:** If `/feature` TodoWrite total steps (conditional steps counted) exceeds 20, reconsider Option C (hybrid); 20 is the point where operator scan-time dominates conditional-density benefits.
* **Tertiary:** If 3 or more consecutive sessions bypass `/feature` entirely and invoke skills directly (indicating `/feature` is perceived as too heavy), reopen 0013's Option A — per-skill invocation becomes the only way to preserve agent coverage for ad-hoc work.
* **Quaternary (staleness test):** If the operational "stale" test above produces ≥2 false classifications (either direction) within any 10-week window, reopen the operational test clause — the coarse test has outlived its usefulness and a finer one is warranted.

## Links

* Supersedes in part: [0013](0013-agent-invocation-wiring.md) — corrects `domain-researcher` trigger row; refines Re-visit Trigger
* Related: [0007](0007-read-only-critic-agents.md) — read-only critic constraint; agent wiring sits on top of this
* Related: [0002](0002-pipeline-over-fanout.md) — pipeline-over-fanout; Option C was rejected partly on the pipeline-fragmentation argument
* Closes: blocker for issue #60 (cannot wire `domain-researcher` without trigger correction; cannot add inline gates without ruling on the Re-visit Trigger)
* `docs/principles.md#4` — knowledge in tools, not memory
* `docs/principles.md#1` — red flags over trade-offs
* `docs/domain/overview.md` — Red Hotspot #1 is the source of the corrected `domain-researcher` trigger
