# 0021. Adopt the nine-principle hardened revision of `docs/principles.md`

* Status: proposed
* Date: 2026-04-29
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: principles, governance, documentation, contract
* Related issue: #117

## Context and Problem Statement

`docs/principles.md` is the governance contract of this repository. Every ADR
references it; every gate reads from it; the cold-start test in §4 ("a colleague
restores context from the repo in one hour, no chat") is the project's
acceptance criterion for documentation completeness. The current file captures
six principles written at project inception and has not been revisited since.

A structured research interview on 2026-04-29 produced a hardened nine-principle
revision (`.claude/scratch/handoff-2026-04-29/PRINCIPLES-DRAFT.md`). Principles
1–4 tighten existing language: P1 forbids the bare phrase "this is a trade-off"
without naming what was chosen; P2 names the lazy-LLM failure mode and the
seven critic agents (now including `security-reviewer` and `reliability-reviewer`,
ADR-0007); P3 reframes from "automate only low-risk" to "deterministic tooling
first, LLM second" with a one-minute reversibility test for the approval
boundary; P4 adds an anti-patterns registry (`docs/anti-patterns.md`) and the
one-hour cold-start test. Principles 5–6 are unchanged in substance. Principles
7, 8, 9 are new: vendor-independent open-format artefacts (P7), operational
maturity across seven dimensions with a 2–3× margin discipline (P8), and an
interception/continuity contract that fixes hand-off as a three-level artefact
obligation (P9).

The DRAFT is a replacement of the principles list, but it does **not** include
three operational sections from the current file: `Definition of Done`, "что
значит архитектурно-значимо", and "что значит нетривиальная задача". The DRAFT
also references `docs/anti-patterns.md`, which does not yet exist. The DRAFT
itself states that its final merge passes through `/adr` operator authority, so
this ADR is the instrument that closes both questions.

The decision is architecturally significant per `docs/principles.md#что-значит-архитектурно-значимо`:
it imposes a constraint that will be hard to remove inside six months — every
new ADR, every domain edit, every gate is written against this list.

## Decision Drivers

* **The DRAFT is the substantive output of a structured interview** and must
  not be silently re-edited; reconciliation work that goes beyond closing the
  three explicit open questions is interpretation creep, which P2 forbids.
* **The three carry-over sections are referenced by stable URL fragments** in
  `CLAUDE.md` (line 20: `#definition-of-done`) and `docs/domain/overview.md`
  (lines 140, 270, 407, 433). Dropping them silently breaks those references;
  moving them to a separate file in the same PR breaks them louder. The choice
  must keep cross-links intact.
* **Principles must be enforceable on the next PR after merge.** A principle
  whose only mechanism is "the operator remembers it" is vapor; P8 in
  particular introduces seven operational dimensions that need a stated scope
  of application or every existing ADR becomes retroactively non-compliant.
* **Bad-Consequences ≥ Good-Consequences is a hard rule** (`docs/decisions/adr-template.md`).
  A nine-principle expansion has obvious upside; the downsides — retroactive
  audit pressure, soft-reference drift in nine prior ADRs, mechanism-less
  principles like P9's STATE.md — must be named explicitly and accepted, not
  hidden.
* **`docs/anti-patterns.md` is referenced by P4 but does not exist.** Merging a
  principle that names a non-existent file is a self-inflicted P1 violation
  ("размытость — нарушение") on day one. The ADR must decide who creates the
  stub and when.

## Considered Options

* **Option A — Adopt DRAFT verbatim; carry the three operational sections forward unchanged into the new file**
* **Option B — Adopt DRAFT; reconcile the three carry-over sections to align with P7–P9 in the same PR**
* **Option C — Adopt DRAFT only; extract `Definition of Done` and the two trigger criteria into a separate `docs/standards.md`**

## Decision Outcome

Chosen option: **Option A — adopt the DRAFT verbatim, carry the three operational sections (`Definition of Done`, "архитектурно-значимо", "нетривиальная задача") forward into `docs/principles.md` without modification**, because it is the only option that (a) respects the DRAFT as the substantive output of the 2026-04-29 interview without re-editing it, (b) preserves every existing cross-reference URL fragment so `CLAUDE.md:20` and the four `docs/domain/overview.md` references stay green, and (c) keeps the implementation PR's blast radius to a single file. Reconciling the carry-over sections with P7–P9 (Option B) is interpretation work that should follow the first one to two ADRs that actually invoke P7 or P8 — empirically grounding the reconciliation rather than guessing at it. Splitting the file (Option C) is correct long-term separation of concerns but breaks every cross-reference simultaneously and is properly a separate decision.

The ADR also resolves three sub-questions:

1. **`docs/anti-patterns.md` stub is created in the implementation PR for #117.** Merging the principle that names the file without the file existing is a P1 violation. The stub is a 5–10 line markdown header that establishes the format ("one pattern per entry: trigger, symptom, correct response") and is empty otherwise. Population is operator work over time; the file must exist on the merge of #117.

2. **P8's scope of application is forward-only.** P8's seven-dimension operational maturity gate binds decisions taken **after this ADR merges**. Existing ADRs (0001–0020) continue under the operational conventions in force when they were written; they are not retroactively non-compliant. An ADR that pre-dates this one may be voluntarily reopened to add a P8 gate articulation, but it is not required. This avoids gate-inflation backwash across the existing decision record.

3. **The DRAFT's preamble paragraph is removed in the implementation PR.** The DRAFT opens with a meta-comment ("Эта редакция — выход интервью research-Claude от 2026-04-29...") that is appropriate for a hand-off artefact, not for the live `docs/principles.md`. The merged file opens with the same one-line contract sentence as today: *"Этот документ — контракт. Каждое решение сверяется с ним; каждое нарушение должно быть осознанным и зафиксированным в ADR."*

The principle renumbering is preserved as in the DRAFT: nine principles, then `Definition of Done`, then the two trigger-criteria sections, then the `Operational rules (НЕ принципы)` block from the DRAFT's tail. Carry-over sections retain their current heading text so URL fragments survive byte-identically.

### Positive Consequences

* The 2026-04-29 interview output ships intact — the substantive work that produced P1–P9 is not diluted by reconciliation prose written without empirical grounding.
* Every existing cross-reference in `CLAUDE.md` and `docs/domain/overview.md` continues to resolve; no follow-on link-fix PR is required.
* P7 (vendor independence) and P9 (interception contract) are now explicit governance, surfacing two failure modes — vendor lock-in for artefacts; LLM-outage continuity — that the prior six-principle file did not name.
* P8's forward-only scope clause prevents an audit-storm against prior ADRs while still binding all future ones.
* `docs/anti-patterns.md` becomes a real file on day one of the merge, closing the broken-reference loop before P4 can be invoked anywhere.
* The implementation PR is single-file (plus the stub), single-purpose, and re-reviewable in under thirty minutes — the cold-start test from P4 is satisfiable on the resulting file.

### Negative Consequences

* **Soft-reference drift in nine prior ADRs.** ADRs 0002, 0005, 0007, 0012, 0013, 0014, 0015, 0017, 0019 reference principles by old prose names ("Красные флаги", "Душный напарник", "Автоматизировать только низкорискованное"). None are hyperlinks, so none break — but new readers will find a name in an ADR that does not appear in `docs/principles.md`. A targeted rename audit is deferred to a follow-on issue.
* **Carry-over sections were written against the old six-principle vocabulary.** The ADR-trigger list does not mention P7 (vendor lock-in for an artefact) or P8 (operational-maturity gap on a domain-critical path), and the nontrivial-task list does not require explicit operational gate articulation. The latent inconsistency is accepted in this ADR and queued for the audit triggered after the first two P7/P8-invoking ADRs merge (see Re-visit Trigger).
* **P9 introduces STATE.md as a required hand-off artefact, but no skill writes it and no DoD checklist item gates it.** The principle is on the books; the mechanism is not. The gap is intentional in this PR — wiring is a separate decision (which skill produces STATE.md, what fields it carries, when it is updated) — but it means P9 cannot be enforced by gate until that follow-on lands.
* **`docs/anti-patterns.md` becomes a new maintenance obligation.** Without operator discipline to add an entry per caught pattern, the file ossifies into a stub and P4's intent fails silently. Without `/gate-audit` integration, drift is invisible.
* **P8's seven dimensions risk over-application to small decisions.** A trivial config tweak should not have to articulate observability, recoverability, and auditability gates. The DRAFT's text says "глубина проверки — пропорционально домену", but proportionality is judgement, not rule. First post-merge ADRs must establish the calibration empirically; expect at least one ADR where P8 is over-applied and one where it is under-applied before the band stabilises.
* **`pull_request_template.md` is not audited in this PR.** The current `Definition of Done` section states it is copied into the PR template; if the template has drifted, this ADR does not catch it. Audit deferred to the implementation PR (#117) plan §6 risk #7.
* **The DRAFT-preamble removal is operator work and is not byte-tracked.** The implementation PR diff will show a deletion that is not in this ADR's outcome list at the line level; reviewers must trust the operator's discretion that what they removed was preamble and not principle.

## Pros and Cons of the Options

### Option A — Adopt DRAFT verbatim; carry-over sections unchanged

* Good, because the DRAFT — the structured interview output — ships without reinterpretation, honouring P2 ("Claude doesn't close trade-offs that the operator hasn't framed as decisions").
* Good, because every existing URL fragment in `CLAUDE.md` and `docs/domain/overview.md` survives byte-identically.
* Good, because the implementation PR is single-file (plus a 10-line `anti-patterns.md` stub) and reviewable in one sitting.
* Good, because the latent inconsistency between carry-over sections and P7–P9 is bounded and named, not silently absorbed.
* Bad, because the ADR-trigger list and nontrivial-task list are written against the old six-principle vocabulary and now diverge from the principles they are meant to operationalise.
* Bad, because P9's STATE.md is a principle without a current mechanism — enforceability lags adoption until a follow-on wiring decision lands.
* Bad, because the rename audit across nine prior ADRs is deferred and may never happen if no PR touches them.

### Option B — Adopt DRAFT; reconcile carry-over sections with P7–P9 in this PR

* Good, because the resulting `docs/principles.md` is internally consistent end-to-end — ADR-trigger criteria mention P7 and P8 explicitly, nontrivial-task criteria require P8 articulation, no latent gap.
* Good, because there is no follow-on issue to track for the reconciliation; it ships and closes.
* Bad, because reconciliation prose is written without an empirical case to ground it — what counts as "vendor lock-in for an artefact" or "operational-maturity gap" must be guessed from P7 and P8 text alone, not from a real ADR that invoked them.
* Bad, because the DRAFT explicitly does not contain that prose; adding it is interpretation creep, which P2 ("Claude does not close trade-offs the operator has not framed") forbids when the operator has not asked for it.
* Bad, because it expands the implementation PR's diff beyond what this ADR is chartered to authorise (the DRAFT and the three carry-over sections as written).

### Option C — Adopt DRAFT only; extract DoD and trigger criteria into `docs/standards.md`

* Good, because separation of concerns is clean: principles in one file, operational standards in another, future evolution decoupled.
* Good, because future expansion of the standards file does not pollute the principles diff history.
* Bad, because every existing cross-reference to `docs/principles.md#definition-of-done`, `docs/principles.md#что-значит-архитектурно-значимо`, and `docs/principles.md#что-значит-нетривиальная-задача` breaks simultaneously: `CLAUDE.md` line 20 and four lines in `docs/domain/overview.md` at minimum, plus prose references in nine prior ADRs.
* Bad, because the implementation PR's blast radius grows from one file to at least three (`docs/principles.md`, `docs/standards.md`, `CLAUDE.md`, `docs/domain/overview.md`), and the cold-start test in P4 (one hour, no chat) becomes harder to satisfy on a multi-file refactor than on a single-file replacement.
* Bad, because the right time to make this split is after a second non-principle operational concept arrives (currently the only candidates are DoD and the two trigger lists — three items do not yet justify a separate file).

## Confirmation

Validation is structural and runs at merge time of #117:

1. **Principle count.** `grep -c "^## [0-9]\." docs/principles.md` returns exactly **9**.
2. **Carry-over headings preserved.** `grep -E "^## (Definition of Done|Что значит «архитектурно-значимо»|Что значит «нетривиальная задача»)" docs/principles.md` returns three lines.
3. **URL fragments unbroken.** `grep -rn "principles.md#" docs/ CLAUDE.md` lists every reference; for each, the corresponding heading slug exists in the new `docs/principles.md` (manual diff against the current file's slugs — they must match byte-for-byte for the three carry-over sections).
4. **Anti-patterns stub exists.** `test -f docs/anti-patterns.md && wc -l docs/anti-patterns.md` returns at least 5 lines and the file contains the format header described in Decision Outcome §1.
5. **DRAFT preamble removed.** `grep -c "выход интервью research-Claude" docs/principles.md` returns **0**.
6. **`docs-reviewer` agent APPROVE** on the implementation PR (PR touches `docs/principles.md` — gate is mandatory per `CLAUDE.md` orchestration table).
7. **`adr-reviewer` agent APPROVE** on this ADR PR before merge.

Failures of any of 1–5 block the implementation PR. Failures of 6 or 7 block the corresponding PR.

## Re-visit Trigger

Reconsider this decision when **any** of the following becomes true:

* **Two ADRs after this one explicitly invoke P7 or P8** in their Decision Drivers or Decision Outcome — at that point the carry-over `Definition of Done` and ADR-trigger criteria can be reconciled empirically against real cases, and Option B becomes a grounded follow-on.
* **A skill or DoD checklist item is added that produces or gates STATE.md (per P9)** — P9's mechanism gap is closed, and its enforceability changes; the principle text may need a pointer to the mechanism.
* **`docs/anti-patterns.md` accumulates more than ten entries** — the file may need format evolution (categories, severity, links to triggering PRs) that the current minimal stub does not support.
* **A vendor-independence test (P7) fails on a real artefact** — e.g., a Projects v2 field-ID is found hardcoded in a script, or a Cursor rule has no markdown twin. The principle text or the operational criteria may need sharper enforceability language.
* **More than two ADRs in a row close with "I don't know, requires empirical verification" (P1) on the same class of question** — signals that the principles list is silent on a recurring decision class and may need a tenth principle.
* **`/gate-audit`'s weekly run** (per the `Operational rules (НЕ принципы)` section at the tail of the DRAFT) reports a gate that fires on something the nine principles do not cover.

## Out of Scope

* **Rename audit across prior ADRs** (0002, 0005, 0007, 0012, 0013, 0014, 0015, 0017, 0019). Old prose names ("Красные флаги", "Душный напарник") remain in those files and are not updated in this PR. Tracked as a separate follow-on issue; not blocking.
* **STATE.md skill wiring (P9 mechanism).** Which skill writes it, what fields it carries, when it is updated — separate decision. P9 records the principle; the mechanism is a follow-on ADR.
* **Retroactive P8 application to ADRs 0001–0020.** The forward-only scope clause in Decision Outcome §2 binds future ADRs only. Voluntary reopening of prior ADRs to add P8 articulation is permitted but not required.
* **`README.md` audit for old principle names.** Plan §6 risk #9 flags this; in-scope for the implementation PR if found, but not for this ADR's outcome.
* **`pull_request_template.md` realignment.** The current DoD section claims the template mirrors the checklist. If the template has drifted, the implementation PR fixes it in scope; this ADR does not pre-decide the fix.
* **Splitting `Definition of Done` and trigger criteria into `docs/standards.md` (Option C).** Deferred until a second non-principle operational concept arrives that justifies the separate file.
* **Reconciliation of carry-over sections with P7–P9 (Option B).** Deferred to the post-merge audit triggered by two ADRs invoking P7 or P8 (see Re-visit Trigger).
* **CI enforcement of any new principle.** No GitHub Actions check is added in #117. Enforcement remains human (operator + critic agents) until `/gate-audit` cadence demands automation.

## Links

* Implements: issue #117 (`docs(principles): adopt nine-principle hardened revision (2026-04-29 interview)`)
* DRAFT source: `.claude/scratch/handoff-2026-04-29/PRINCIPLES-DRAFT.md` (interview output, 2026-04-29)
* Plan: repo-root `plan.md` for #117 — names the Option A/B/C trade-off this ADR closes
* Related: ADR-0007 (read-only critic agents) — P2 names `security-reviewer` and `reliability-reviewer`; ADR-0007 is the source-of-truth for the critic-agent inventory referenced by P2
* Related: ADR-0018 (per-project command installation) — P6 cites it directly; carry-over unchanged in the new file
* Related: ADR-0020 (sub-aggregate extraction) — `docs/domain/overview.md` references that this ADR's URL-fragment preservation must protect remain valid
* Supersedes: none. The current `docs/principles.md` is replaced in scope but not by ADR-numbered supersession (it was the project baseline, not an ADR-recorded decision).
