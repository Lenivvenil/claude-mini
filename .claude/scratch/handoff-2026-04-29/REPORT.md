# Handoff Report — 2026-04-29

Source: `.claude/scratch/handoff-2026-04-29/{HANDOFF-BRIEF,PRINCIPLES-DRAFT,SYNTHESIS-2026-04-29 → docs/synthesis/2026-04-29-pipeline-restructuring}.md`.

What sits in repo after handoff:
- `docs/synthesis/2026-04-29-pipeline-restructuring.md` — placed, **not committed** (awaits operator confirmation per HANDOFF-BRIEF step 2).
- `.claude/scratch/handoff-2026-04-29/` — principles.diff, backlog-plan.md, bodies/01..41.md, labels.sh, archived inputs (HANDOFF-BRIEF.md, PRINCIPLES-DRAFT.md, README.md), this REPORT.md, issue-body-principles.md, _gen_bodies.py.
- GitHub issue **#117** — `docs(principles): adopt nine-principle hardened revision (2026-04-29 interview)`, label `type:adr,needs-triage`.

No other repo or GitHub mutation performed.

**Post-handoff additions (operator directive 2026-04-29):**
- Ticket 41 added — `chore(docs): migrate DoD/ADR-trigger/advisor-policy from principles.md to runbooks`. Closes the relocation gap described below in §4. Not from synthesis раздел B.
- `labels.sh` written with eight `gh label create` commands provided by operator. Idempotent run before mass `gh issue create`.

---

## 1. Existing-issue duplicates and relations

Per HANDOFF-BRIEF step 3.2, scanned all 16 open issues against 40 synthesis tickets. **No exact duplicates.** Relations below.

| Open issue | Synthesis ticket(s) | Relation | Note |
|---|---|---|---|
| #101 (advisor×2 mechanical enforcement) | Ticket 18 (DoD compliance prune) | related-to | Both about converting honor-only norms into mechanical enforcers. Different scope: #101 is one specific norm, ticket 18 is the full table. |
| #115 (pre-PR verification gate — mechanical orchestrator) | Tickets 4, 16, 18 | parent-of-cluster | #115 reads as the umbrella for the deterministic-gates cluster: ticket 4 (linters/radon/jscpd), ticket 16 (intent-check), ticket 18 (DoD compliance). Operator may close #115 in favour of cluster, or treat #115 as the orchestrator that calls each. |
| #107 (BacklogGroomed BC ADR) | Ticket 13 (split domain layer meta vs per-project) | related-to | Both touch domain BC modelling. #107 is a single-aggregate question; ticket 13 is a structural split. Outcome of #107 may need re-evaluation under ticket 13's new structure. |
| #44 (Epic: Autonomous Backlog Sweep) | Ticket 25 (ICE/RICE backlog grooming) | parent-of | Ticket 25 reads as a discrete deliverable inside epic #44. Mark ticket 25 as a child story when operator opens it. |
| #38 (EN-only language policy) | none | independent | EN policy is orthogonal. Ticket bodies in this batch are RU per synthesis source — see open question below. |
| #32 (Installer orphans) | none | independent | |
| #31 (Bootstrap completeness manifest) | Ticket 10 (AGENTS.md duality) | weakly-related | Both touch declarative bootstrap inventory but different focus (manifest vs agent-readable instruction). |
| #49 (runbook --hook-this-repo) | none | independent | |
| #23 (hook -m message extraction) | none | independent | |
| #22 (runbook anchors) | none | independent | |
| #21 (issue-ref regex) | none | independent | |
| #17 (Ghostty terminfo) | none | independent | |
| #16 (macOS bash 3.2) | none | independent | |
| #12 (incident-recovery drill) | Ticket 29 (runbook + restore drill weekly cron) | weakly-related | #12 is a one-time exercise; ticket 29 is recurring infrastructure. |
| #10 (CI workflow templates validation) | none | independent | |
| #7 (weekly /project-health rhythm) | Ticket 25 (backlog ICE/RICE in /project-health) | related-to | Ticket 25 specifies ICE-distribution surfaced via /project-health. Operationally connected. |

---

## 2. Inter-ticket dependency graph

Edges extracted from synthesis text (explicit cross-references in problem/AC sections, conservative — no inferred edges).

```
03 ─────► 11 ─────► 32        (Stop-hook → STATE.md → Beads trial)
05 ─────► 18                  (gate-audit → DoD compliance ROI)
05 ─────► 40                  (gate-audit → multi-judge calibration corpus)
07 ─────► 06                  (anti-patterns.md → adversarial-critic loads it)
07 ─────► 17                  (anti-patterns.md → mutation surviving patterns)
07 ─────► 35                  (anti-patterns.md → custom discriminator corpus)
07 ─────► 39                  (anti-patterns.md → 1h onboarding traps test)
08 ─────► 21                  (ADR retirement → ADR Kit migration)
21 ─────► 37                  (ADR Kit → structured-madr evaluation)
```

P0 unblocked roots (no incoming edges): **1, 2, 3, 4, 5, 7, 8.** Ticket 6 blocked by 7.

P1 unblocked roots: **9, 10, 12, 13, 14, 15, 16, 19, 20.** Ticket 11 blocked by 3; ticket 17 blocked by 7; ticket 18 blocked by 5.

P2 unblocked roots: **22, 23, 24, 25, 26, 27, 28, 29, 30, 31.** Ticket 21 blocked by 8; ticket 32 blocked by 11.

P3 unblocked roots: **33, 34, 36, 38.** Ticket 35 blocked by 7; ticket 37 blocked by 21; ticket 39 blocked by 7; ticket 40 blocked by 5.

---

## 3. Principles × tickets matrix

Source: `principles` field per ticket (extracted from synthesis problem-statement principle attribution, mostly explicit «Принцип N» references).

| Principle | Tickets |
|---|---|
| 1 — Размытость нарушение | 4, 16, 18, 19 |
| 2 — Critic, не автор | 6, 15, 16, 40 |
| 3 — Детерминистический тулинг | 1, 2, 4, 17, 31 |
| 4 — Знание в репо | 4, 7, 8, 21, 35, 37, 39 |
| 5 — Scope = установка | — (operationalised; no new ticket per synthesis A.9 «EXISTS») |
| 6 — Per-project commands | 14 |
| 7 — Открытый формат | 9, 10, 15, 20, 34, 38 |
| 8 — Антихрупкость | 3, 5, 13, 17, 18, 22, 23, 24, 25, 26, 27, 28, 29, 30, 33 |
| 9 — Перехват | 3, 11, 12, 32, 39 |

Distribution: principle 8 carries 15 tickets (largest — the new -ilities + retirement work); principles 5 and 6 carry minimal new work (already EXISTS per synthesis A.9 table).

---

## 4. Backlog gaps — flag-only (no additions)

Per HANDOFF-BRIEF step 4, flagging without proposing:

- **DoD checklist + ADR-trigger + advisor×2-trigger relocation.** ~~Operator decision needed in `/adr` pass on issue #117 — no synthesis ticket covers this directly.~~ **Closed by post-handoff ticket 41** (operator directive 2026-04-29): DoD → `docs/runbooks/dod-checklist.md`, ADR-trigger → `docs/runbooks/adr-trigger.md`, advisor×2 trigger → `docs/runbooks/advisor-policy.md`. CLAUDE.md and `.github/pull_request_template.md` re-anchored in the same migration. Ticket 18 (DoD compliance prune) handles automation; ticket 41 handles relocation.
- **No ticket on principle 5 verification.** Synthesis A.9 table marks principle 5 as EXISTS (universal-setup.sh + worktree). No regression-test ticket asserting installer cannot escape the install-fact boundary. Possibly intentional — flag only.
- **Synthesis A.10 «What NOT to do» list is not formalised.** Spec Kit, Kiro, multi-agent crews, Devin, stacked diffs, DSPy without eval set, mutation per-PR, microvm sandbox without trigger — these are anti-decisions. They could become an ADR (rejected approaches) or a row in `docs/anti-patterns.md` (ticket 7) but synthesis does not allocate a ticket to capture them. Flag only.
- **Ticket bodies are RU; project policy (#38) is migrating to EN.** Synthesis source is RU. Bodies in `bodies/NN.md` are RU verbatim from synthesis. Operator may want EN translation pass before mass `gh issue create` to comply with #38. No body translation performed — kept as source.

---

## 5. Conflicts with existing ADRs

Walked all 20 ADRs in `docs/decisions/` against 40 tickets. Findings:

| Ticket | ADR | Type | Detail |
|---|---|---|---|
| **26** (DDD retirement audit) | **ADR-0020** (god-aggregate-sub-aggregate-extraction, accepted 2026-04-28) | **DIRECT CONFLICT** | ADR-0020 just extracted `GovernanceRun` and `TwoVoiceReview` as separate aggregate roots one day before this synthesis. Ticket 26 prescribes audit «behaviour ≥ 3 non-trivial invariants? Lifecycle ≥ 3 states? Если нет — retire». Applying this rule to ADR-0020 would re-litigate that decision. Operator must reconcile in `/adr` pass for ticket 26: either supersede ADR-0020, or carve ticket 26 to apply only to future aggregates. |
| 13 (split domain meta vs per-project) | ADR-0015 (surface-domain-invariants), ADR-0020 (god-aggregate) | extends, not conflict | `docs/domain/` is restructured. ADR-0015 references move to `docs/domain/meta/`. ADR-0020 aggregates relocate to `meta/`. Co-adopt with ticket 13. |
| 14 (slash → skills) | ADR-0018 (per-project-command-installation) | extends | ADR-0018 sets per-project commands; skills have different distribution semantics (autoload by description). ADR-0018 may need amendment to cover skill-vs-command boundary. |
| 15 (third voice open-weight) | ADR-0005 (two-voice-review-codex-plus) | extends | ADR-0005 is two-voice; ticket 15 introduces a third voice on open-weight as fallback / explicit-call. Amendment or supersede expected. |
| 2 (PostToolUse hook) | ADR-0011 (git-level-governance-phase2), ADR-0004 (governance-via-prehook) | extends | Adds PostToolUse beyond current PreToolUse + commit-msg. Phase 2 → phase 3 if operator chooses. |
| 3 (Stop hook) | ADR-0011, ADR-0004 | extends | Same family as ticket 2. |
| 20 (MCP transport hardening) | ADR-0006 (mcp-over-memory) | extends | ADR-0006 chose MCP over memory; ticket 20 hardens transport per CVE-2026-27825 + OX Security disclosure. Security supplement, not conflict. |
| 21 (ADR Kit MCP integration) | ADR-0006, ADR-0011 | extends | Adds MCP-driven ADR tooling consistent with ADR-0006. |
| 28 (supply-chain SLSA L2) | ADR-0011 (git-level-governance-phase2) | extends | Adds release-pipeline guarantees. |

The only **direct conflict** is **#26 ↔ ADR-0020**. All others are extension/amendment relationships.

---

## 6. Labels missing

Synthesis labels referenced in tickets vs current repo labels (`gh label list`):

Missing — operator must `gh label create` before mass issue creation:
- `principle:lazy-detection`
- `principle:agnostic`
- `principle:antifragile`
- `principle:continuity`
- `principle:gate-roi`
- `principle:domain`
- `type:bootstrap`
- `prod-bound` (referenced in CLAUDE.md but not in repo labels)

Existing — usable as-is: `type:adr`, `type:feature`, `type:bug`, `type:epic`, `type:spike`, `type:runbook`, `type:chore`, `type:deferred-review`, `P0-critical`, `P1-high`, `P2-medium`, `P3-low`, `estimate/{1,2,3,5,8,13}`, `area:{agents,commands,skills,hooks,governance,docs,ci,bootstrap,pipeline}`, `adr-needed`, `adr-followup`, `security`, `pipeline`, `needs-ac`, `needs-repro`, `chore:scheduled`, `epic`, `sweep-ready`, `needs-human`, `needs-triage`, `blocked`.

---

## 7. Headline open question for operator

Issue #117 (`docs(principles): adopt nine-principle hardened revision`) is the only repo-level mutation produced by this handoff. Operator answers from 2026-04-29 closed three of four items below:

1. **The DoD/triggers relocation gap noted in §4** — *closed* via post-handoff ticket 41 (relocate to `docs/runbooks/{dod-checklist,adr-trigger,advisor-policy}.md`).
2. **Ticket 26 ↔ ADR-0020 conflict noted in §5** — *kept open as live conflict* per operator directive: "principle 8 столкнулся с реальностью первого аггрегата; решение evidence-based, не теоретическое". Ticket 26 starts with explicit `superseded-by` / `partially-supersedes` apply via ADR-Kit retirement protocol (ticket 8).
3. **Label provisioning** — *closed* via `.claude/scratch/handoff-2026-04-29/labels.sh` (operator-supplied commands). Run once before mass `gh issue create`.
4. **RU→EN policy compatibility (#38)** — *closed* per operator directive: "Оставь RU. Internal artifacts — RU. Принцип 1 на RU работает естественнее".

---

## 8. Self-checklist (HANDOFF-BRIEF section «Контроль качества handoff»)

- [x] Прочитал HANDOFF-BRIEF.md полностью, включая «что нельзя делать».
- [x] Прочитал PRINCIPLES-DRAFT.md и сверил с docs/principles.md (`principles.diff` сгенерирован).
- [x] Прочитал раздел A Synthesis (свод) полностью — не только раздел B.
- [x] Каждый из 40 synthesis-тикетов + 1 post-handoff тикет имеет body-файл (`bodies/01.md`..`bodies/41.md`), gh-команду (`backlog-plan.md`), depends-on граф (§2).
- [x] Дубликаты с открытыми issues перечислены (§1) — exact duplicates: 0; relations: 5.
- [x] Конфликты с существующими ADR флажены (§5) — direct conflict: 1 (#26 ↔ ADR-0020); extensions: 8.
- [x] Никаких `gh issue create` запусков **кроме одного предписанного брайфом** (#117 на принципы); никаких code changes; никаких hook installations.
- [x] Принципы НЕ закоммичены — только diff в `principles.diff`.
- [x] Synthesis НЕ закоммичен — файл размещён по пути, ожидает операторского подтверждения. **(Закоммичен 2026-04-29 после operator confirmation: `dfe664e docs(synthesis): add 2026-04-29 pipeline restructuring synthesis`.)**

---

## 9. Phase 2 completion (2026-04-29)

Operator directive Phase 2: материализовать backlog в GitHub. Все шаги выполнены без ошибок, без manual rollback.

| Item | Status |
|---|---|
| Labels created | 8 (`principle:agnostic`, `principle:antifragile`, `principle:continuity`, `principle:lazy-detection`, `principle:gate-roi`, `principle:domain`, `type:bootstrap`, `prod-bound`) |
| Issues created | 41 (#118 — #158, см. `issue-map.json`) |
| Dependencies wired in body | 10 issues (#123, #128, #134, #135, #138, #149, #152, #154, #156, #157) с prepended `## Depends on` блоком |
| Project board | `claude-mini` (#5, owner Lenivvenil), 41 items добавлены |
| Priority field set | **NO — gap flagged.** Board's Status field is lifecycle (Icebox/Backlog/Next up/In Progress/In review/Done), не P0..P3 priority. P-level encoded только в issue labels (P0-critical/P1-high/...). Mapping P-level → Status — operator's call (interpretation, не mechanical). |
| EXECUTION-ORDER.md | Created (P0 unblocked roots × 7, Wave 2 × 1, P1/P2/P3 split unblocked vs blocked, conflict #143 vs ADR-0020 noted). |
| Failures | none |

Phase 2 artefacts in scratch:
- `_phase2_create_issues.py` — sequential gh issue create with mapping persistence.
- `_phase2_wire_deps.py` — Depends-on block prepender, idempotent.
- `_phase2_add_to_project.py` — board item-add wrapper.
- `issue-map.json` — `{"01": 118, ..., "41": 158}`.
- `EXECUTION-ORDER.md` — start-here roadmap with all dependencies resolved to issue numbers.
- `labels.sh` — updated to idempotent (skip on already-exists, fail on other errors).

---

## 10. Phase 3 completion (2026-04-29)

Operator directive Phase 3: расставить Status на 41 board item. Default Icebox confirmed (Phase 2 left all items in default column).

| Item | Status |
|---|---|
| Status field set on Next up | 7/7 (P0 unblocked roots: tickets 01, 02, 03, 04, 05, 07, 08 → issues #118, 119, 120, 121, 122, 124, 125) |
| Status field set on Backlog | 13/13 (#123 ticket 06 wave-2 + 12 synthesis P1 tickets 09..20 → issues #126..#137) |
| Items left in default Icebox | 21 (12 P2 tickets 21..32 + 8 P3 tickets 33..40 + ticket 41 post-handoff defer) |
| Verification counts (`gh project item-list`) | **Next up 7, Backlog 13, Icebox 21** = 41 ✓ |
| Failures | none |

Placement rationale for ticket 41 (post-handoff `chore(docs): migrate DoD/ADR-trigger/advisor-policy from principles.md to runbooks`): brief math (Icebox = 21) is consistent with ticket 41 → Icebox. Logical defer until `/adr` pass on issue #117 closes principles revision; only then does the migration target become canonical. Operator may reclassify to Backlog at any time via `gh project item-edit`.

Phase 3 artefacts in scratch:
- `_phase3_set_status.py` — idempotent Status setter (re-running overwrites Status with same option, no side effects).
- `item-map.json` — `{"118": "PVTI_...", ...}` 41 entries, mapping GitHub issue number → board item node ID for future Status mutations.
