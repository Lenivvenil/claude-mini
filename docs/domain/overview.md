# Bounded Context: claude-mini-pipeline

**Version:** 2026-04-28
**Status:** current as of PR #102; approved by domain-reviewer (pass 3)

## Table of Contents

- [Purpose](#purpose)
- [Actors](#actors)
- [Commands and Domain Events](#commands-and-domain-events)
- [Boundary](#boundary)
- [Aggregate Root](#aggregate-root)
- [Policies](#policies)
- [Context Map](#context-map)
- [Use Cases](#use-cases)
- [Domain Data Model](#domain-data-model)
- [Interface Contracts](#interface-contracts)
- [NFR](#nfr)
- [Internal Compliance](#internal-compliance)
- [Security](#security)
- [Red Hotspots](#red-hotspots)

---

## Purpose

This BC owns the workflow choreography for AI-assisted software development: pipeline stages, agent invocation, governance enforcement, ADR discipline, and the Definition of Done. It does NOT own the source code of projects where claude-mini is installed, Claude Code internals, or Anthropic model internals.

---

## Actors

| Actor | Role | Authority |
|---|---|---|
| **Operator** | Human running Claude Code; sole final decision-maker and author of production code | Full write, merge, approve |
| **Main Loop** (Sonnet) | Orchestrates all pipeline actions under operator direction | Write authority within repo |
| **Advisor** (Opus) | Consulted via `advisor()` before substantive work and before declaring done; two calls minimum on nontrivial tasks | Read-only; returns critique, not edits |
| **Read-only Critic** (subagent) | `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `reliability-reviewer`, `backlog-groomer`, `docs-reviewer` — evaluate artifacts, return markdown reports | Read-only; never writes to filesystem or mutates GitHub |
| **Author-gateway** (subagent) | `domain-researcher`, `solutions-architect` — invoke write-capable skills for docs artifacts only | Limited write via skill (docs only, not production code) |
| **Skill** | Slash-command (`/plan`, `/adr`, `/implement`, `/review`, `/feature`, etc.) executing under main-loop authority | Main-loop authority |
| **GitHub MCP** | MCP server invocable from inside the pipeline; ACL layer over GitHub platform | Pipeline-scoped GitHub API calls |
| **Codex CLI** | Second voice in two-voice review; accessed via ChatGPT Plus device-auth OAuth | Read-only output (review text) |

---

## Commands and Domain Events

Commands are what mutate the `FeatureRun` aggregate. Each command emits one or more events.

### FeatureRun commands (lifecycle)

| Command | Emits |
|---|---|
| `StartFeaturePipeline(issue)` | `FeaturePipelineStarted` |
| `DraftPlan` | `PlanDrafted` |
| `InvokeAdvisor` | `AdvisorInvoked`, `AdvisorReturned` |
| `DraftADR` | `ADRDrafted` |
| `RequestADRReview` | `ADRReviewRequested` |
| `StartImplementation` | `ImplementationStarted` |
| `ModifyDomainDocs` | `DomainDocsChanged` |
| `RequestReview` | `ReviewRequested` |
| `RequestCodexReview` | `CodexReviewRequested` \| `CodexReviewSkipped` |
| `RecordTwoVoiceResult(agreed\|disagreed)` | `TwoVoiceDisagreed` \| `TwoVoiceReconciled` \| `DeferredReviewIssueCreated` |
| `RequestSecurityReview` | `SecurityReviewRequested` |
| `RequestReliabilityReview` | `ReliabilityReviewRequested` |
| `AttemptCommit` | `CommitAttempted` → `GovernanceBlocked` \| `GovernanceApproved` |
| `CreatePR` | `PRCreated` |
| `DeclareDoDSatisfied` | `DoDSatisfied` |
| `MergeToMain` | `MergedToMain` |
| `MergeADR` | `ADRMerged` |

### Out-of-band commands (not part of FeatureRun)

| Command | Emits | Notes |
|---|---|---|
| `PromoteTaskToIssue` | `TaskPromotedToIssue` | Pre-pipeline; no FeatureRun yet |
| `RunBacklogGroomer` | `BacklogGroomed` | Weekly cron; independent aggregate |

---

## Boundary

**In scope:**
- Feature pipeline choreography (stages, ordering, gates)
- Agent invocation rules (who, when, conditions)
- Governance hooks (commit-msg enforcement)
- ADR lifecycle (draft → review → merge)
- Domain model lifecycle (this BC maintains its own docs/domain/)
- Definition of Done enforcement
- Advisor policy (when to invoke, minimum count)
- Two-voice review protocol
- Fan-out rules (what is and isn't parallelizable)
- Issue-first discipline

**Out of scope:**
- Source code of downstream projects where claude-mini is installed
- Claude Code engine internals (tool dispatch, context window management)
- GitHub platform internals (Actions runner mechanics, PR merge algorithms)
- Anthropic API (abstracted by Claude Code; pipeline never calls it directly)
- RTK proxy (infrastructure below the BC line)

**Terms that change meaning at the boundary:**

| Term | Inside this BC | Outside |
|---|---|---|
| `review` | `/review` + `/codex-review` two-voice gate | GitHub web UI PR review |
| `issue` | Backlog item with `#NNN` reference | "A problem" (generic English) |
| `agent` | Claude Code subagent: read-only critic or author-gateway (ADR 0007) | Any AI agent |
| `pipeline` | This BC's canonical feature pipeline | CI/CD pipeline |
| `skill` | Slash-command running under main-loop authority | Generic capability |

---

## Aggregate Root

**`FeatureRun`** — one complete invocation of `/feature <issue-number>`.

Invariants:
- Exactly one issue reference (`Closes #NNN`) per run
- DoD checklist is monotonic: checkboxes flip false → true only, never reversed within a run
- Two-voice state machine: `{pending → agreed | pending → deferred | pending → disagreed | disagreed → reconciled | disagreed → deferred}` — `disagreed` entered via `RecordTwoVoiceResult(disagreed)`; `deferred` reachable from `pending` (Codex skip) and from `disagreed` (skip after unresolved conflict)
- `advisor()` called ≥ 2 times when task is nontrivial (per `docs/principles.md`)

**Note:** `BacklogGroomed` belongs to a separate out-of-band aggregate (weekly backlog run). It is not part of `FeatureRun`.

---

## Policies

| Trigger event/condition | Policy |
|---|---|
| `DomainDocsChanged` | Invoke `domain-reviewer` |
| `ADRDrafted` | Invoke `adr-reviewer` |
| PR contains prod-bound change | Invoke `security-reviewer` and `reliability-reviewer` inside `/review` phase |
| PR touches human-facing docs (`docs/runbooks/`, `docs/architecture/`, `docs/principles.md`, `README.md`) | Invoke `docs-reviewer` inside `/review` phase |
| `TwoVoiceDisagreed` and unresolved at PR time | Create deferred-review issue (`type:deferred-review`) |
| `CommitAttempted` without issue-ref | `GovernanceBlocked` |
| `CommitAttempted` on ADR-significant change without ADR-link | `GovernanceBlocked` |

---

## Context Map

| External BC | DDD Pattern | Notes |
|---|---|---|
| **GitHub platform** (Issues, PRs, Projects, Actions) | Customer/Supplier + Open Host Service | Pipeline is customer. ACL via GitHub MCP server + `gh` CLI. Translates GitHub model into domain terms (issue-ref, PR body contract). |
| **ChatGPT Plus / Codex CLI** | Conformist | Pipeline takes device-auth OAuth output as-is; no translation layer. Corporate repo restriction is an operator access-gate, not a DDD pattern. |
| **Git hook system** | Customer/Supplier | `.git/hooks/` is the physical installation boundary per Principle 5. Pipeline supplies the hook; git is the consumer. |
| **Anthropic API** | Separate Ways | Claude Code abstracts it; this BC never integrates with Anthropic API directly. Both systems operate independently from the domain's perspective. |

---

## Use Cases

### UC-01: Happy Path — Feature Delivered to Main

**Actor:** Operator
**Preconditions:** GitHub issue exists with acceptance criteria; no feature branch for this issue; main is current with remote.
**Main scenario:**
1. Operator runs `/feature <N>` → issue moved to In Progress.
2. `/plan` reads issue and referenced files; produces `plan.md`.
3. `advisor()` called (pre-check): plan validated.
4. `/implement` executes plan; `advisor()` called again (pre-done).
5. `/qa` runs test coverage and docs currency checks; produces `qa-report.md`.
6. `/review` (Claude) scans diff against plan, principles, domain contracts.
7. `/codex-review` (Codex CLI) produces second-voice review.
8. Operator resolves findings; commits via governance hook.
9. `gh pr create` with `Closes #N`; issue moved to In Review.
10. Human self-review; PR merged to main.

**Alternatives:**
- (a) ADR needed: STOP after `/plan`; invoke `@agent-solutions-architect`, merge ADR, re-sync `plan.md §4`, then resume `/implement`.
- (b) `advisor()` returns STOP finding: update `plan.md` before continuing.
- (c) Two-voice disagrees: disagreement documented in PR thread; reconciled before merge.

**Postconditions:** PR merged; issue closed; `FeatureRun.dod_state = done`; all DoD boxes checked.

---

### UC-02: Codex Skip — Deferred Two-Voice Review

**Actor:** Operator (Codex CLI unavailable or quota-exhausted)
**Preconditions:** PR at `/codex-review` stage; Codex CLI is installed but unreachable (Plus OAuth stale or quota at limit).
**Main scenario:**
1. `/codex-review` invokes `bootstrap/scripts/review-codex.sh`.
2. Startup check: `timeout 10 codex --version` times out (exit 124) → SKIPPED marker.
3. `gh issue create --label type:deferred-review` opened automatically.
4. Script outputs `SKIPPED` to stdout; exits 0 (does not block pipeline).
5. Operator records skip in PR body; DoD grace clause satisfied.

**Alternatives:**
- (a) Quota exhausted (exit 4): same path as timeout.
- (b) `gh` CLI unavailable: issue creation silently skipped; SKIPPED marker still output.
- (c) Codex not installed: SKIPPED with install instruction; no issue created.

**Postconditions:** `FeatureRun.two_voice_state = deferred`; `type:deferred-review` issue exists; PR body documents the gap.

---

### UC-03: Governance Block — Commit Rejected

**Actor:** Operator (via Main Loop issuing `git commit` via Bash tool)
**Preconditions:** `/implement` complete; operator triggers commit via Claude Code.
**Main scenario:**
1. Claude Code PreToolUse hook fires; `pre-commit-governance.sh` receives JSON on stdin.
2. Rule 4: branch is not main → proceed.
3. Rule 1: commit message checked against Conventional Commits regex.
4. Rule 2: issue-ref `#NNN` checked in message or branch name.
5. Rule 3: staged files checked for decision markers; ADR-ref required if found.
6. Any rule fails → `json_deny` with reason; exit 2; commit blocked.

**Alternatives:**
- (a) Commit directly on main: Rule 4 fires first with "create a feature branch" message.
- (b) `--amend`: strict check skipped; exit 0.
- (c) `adr:` prefix: issue-ref and ADR-ref rules waived.
- (d) All rules pass: exit 0; commit proceeds (`GovernanceApproved`).
- (e) `jq` not installed / stdin not valid JSON: hook may fail-open (see `docs/runbooks/incident-recovery.md`).

**Postconditions:** `GovernanceBlocked` event; commit not created; operator fixes message and retries.

---

### UC-04: ADR-Significant Detection — Architecture Gate

**Actor:** Operator (running `/plan` via Main Loop)
**Preconditions:** Issue describes a change meeting at least one trigger in `docs/principles.md` (section "Что значит «архитектурно-значимо»").
**Main scenario:**
1. `/plan` reads issue and existing code.
2. Plan evaluation: at least one architectural trigger matches (new integration, BC boundary change, storage choice, etc.).
3. STOP emitted: `plan.md` includes "ADR required" notice.
4. `@agent-solutions-architect` invoked → ADR draft written to `docs/decisions/NNNN-*.md`.
5. `@agent-adr-reviewer` invoked → returns APPROVE or BLOCK findings.
6. Operator resolves findings; ADR PR merged.
7. `plan.md §4` re-synced with merged ADR; `/implement` proceeds.

**Alternatives:**
- (a) `adr-reviewer` returns BLOCK: revisions made before ADR PR merge.
- (b) Operator judges not architectural despite trigger: justification recorded in `plan.md`; no ADR authored.

**Postconditions:** `ADRMerged` event; `plan.md §4` references the ADR number; `/implement` may proceed.

---

### UC-05: Prod-Bound PR — Security and Reliability Gates

**Actor:** Operator (PR touches prod-bound paths)
**Preconditions:** PR diff touches `bootstrap/`, `.github/workflows/`, or `.git/hooks/`; or issue labeled `prod-bound`.
**Main scenario:**
1. `/review` reads diff and detects prod-bound paths.
2. `@agent-security-reviewer` invoked inside `/review` phase.
3. `@agent-reliability-reviewer` invoked inside `/review` phase.
4. Both return markdown reports (BLOCK / SUGGEST / NIT findings).
5. Operator resolves all BLOCK items before commit.

**Alternatives:**
- (a) `security-reviewer` returns BLOCK: fix required; merge blocked until resolved.
- (b) `reliability-reviewer` returns SUGGEST only: operator decides whether to address.
- (c) Both agents return no findings: review passes with no action required.

**Postconditions:** `SecurityReviewRequested` + `ReliabilityReviewRequested` events; all BLOCK items resolved; findings documented in PR description. Note: resolving BLOCK items before merge is enforced by honor — the governance hook does not mechanically block on reviewer findings (see Internal Compliance table).

---

## Domain Data Model

No storage schema. Attributes reflect domain invariants only.

### Entities

| Entity | Key Attributes | Valid States |
|---|---|---|
| **FeatureRun** | `issue_ref` (string, `#NNN`, exactly one per run); `dod_state` (enum); `two_voice_state` (enum); `advisor_call_count` (int ≥ 0); `adr_required` (bool) | `in_progress → review_pending → done` (monotonic; no reversal within a run) |
| **DomainEvent** | `name` (string, PastTense); `emitted_by` (Command); `timestamp` | No state; append-only log |
| **ReviewArtifact** | `type` (enum: `claude_review \| codex_review \| advisor_critique`); `content` (markdown); `verdict` (enum, null for `advisor_critique` — see issue #104) | `pending → approved \| blocked \| deferred` (advisor_critique: verdict always null) |
| **Policy** | `trigger` (DomainEvent or condition); `action` (agent invocation or governance rule); `active` (bool) | `active \| waived` (waiver requires explicit justification) |

### FeatureRun invariant enforcement

| Invariant | Enforcement |
|---|---|
| Exactly one `issue_ref` per run | Governance hook Rule 2; `/feature` reads single issue number |
| `dod_state` monotonic (false→true only, never reversed) | Honor system — no artifact |
| `two_voice_state` machine: see Aggregate Root invariant (canonical definition) | `review-codex.sh` drives `pending → deferred` path; reconciliation is operator judgment |
| `advisor_call_count ≥ 2` on nontrivial tasks | Honor system — no artifact; see Internal Compliance table |

---

## Interface Contracts

Sourced empirically from `bootstrap/scripts/review-codex.sh`, `bootstrap/hooks/pre-commit-governance.sh`, `bootstrap/commands/feature.md`, `bootstrap/universal-setup.sh`.

### External dependencies

| Interface | Operations used | Handled failures | Unhandled failures |
|---|---|---|---|
| **GitHub MCP** | MCP tools loaded and available (`issue_read/write`, PR read/review write, project item list/edit); current pipeline scripts route most ops through `gh` CLI directly — MCP acts as fallback and exploratory layer | Item not found in project → warn and continue (per `feature.md` startup block) | GitHub API rate limit; auth token expiry; MCP server unavailable — no retry in any case |
| **gh CLI** | `gh issue view`, `gh issue create --label`, `gh project item-list`, `gh project item-edit`, `gh project item-add`, `gh pr create`, `gh pr edit` | Project item not found → warn and continue; `gh` absent → SKIPPED with install instruction | Token expired → non-zero exit propagates to caller; rate limit → no retry; network failure → non-zero exit |
| **Codex CLI** | `codex --version` (startup check, 10s timeout); `codex --model gpt-5.2 exec <prompt>` (default 120s timeout) | Startup timeout (exit 124) → SKIPPED + `type:deferred-review` issue; quota (exit 4) → SKIPPED + issue; any other non-zero → SKIPPED + issue; `codex` not installed → SKIPPED; `timeout` binary absent → SKIPPED | Successful run with malformed output → not validated; device-auth token rotation needed → falls through to startup check failure |

### Internal integration points (owned by this BC)

| Mechanism | Operations | Handled failure modes | Unhandled failure modes |
|---|---|---|---|
| **pre-commit governance hook** | Invoked as Claude Code PreToolUse on `git commit`; reads stdin JSON (`tool_input.command`, `cwd`); enforces Conventional Commits (Rule 1), issue-ref (Rule 2), ADR-ref for decision-type staged files (Rule 3), no-commit-to-main (Rule 4). Also installed at `.git/hooks/commit-msg` for terminal commits via `--hook-this-repo` (ADR-0011). | `--amend` → skip strict check; `adr:` prefix → waive issue-ref/ADR-ref; detached HEAD → fail-open; `cd $cwd` fails → fail-open | stdin not valid JSON → `jq` returns empty strings; malformed command string → message extraction may fail; hook file removed or corrupted → no enforcement at either level (see Red Hotspot #8) |
| **universal-setup.sh** | `--install` (global skills/hooks/scripts); `--target <repo>` (per-project commands + pipeline-version); `--hook-this-repo` (copies staged hook to `.git/hooks/commit-msg`); `--check` (drift report, exits 0 always) | cp failure → `die` (exit 3); post-copy `cmp -s` mismatch → `die`; source file missing → `drift()` counter incremented | `--check` always exits 0 even with drift (use stdout, not exit code, for diagnostics) — see ADR-0019 |

---

## NFR

| Requirement | Measure | Enforcement artifact | Source |
|---|---|---|---|
| Every commit carries issue-ref (`#NNN`) and passes Conventional Commits | Commit rejected (exit 2) if any rule fails | `pre-commit-governance.sh` (PreToolUse hook + `.git/hooks/commit-msg`) | ADR-0004, ADR-0011 |
| All shell scripts in `bootstrap/` pass ShellCheck with no warnings | CI job exits non-zero on any ShellCheck warning | `.github/workflows/` ShellCheck step | ADR-0012 |
| Installer exit 0 is an honest success signal — no silent partial failures | Test harness `test-install-verification.sh` — 13 assertions; all must pass | `bootstrap/scripts/test-install-verification.sh` | ADR-0019 |
| No direct commits to main | Pre-commit-governance.sh Rule 4 blocks `git commit` when branch is `main` | `pre-commit-governance.sh` | ADR-0009 |

Constraints lacking a mechanical check (two-voice review completion, human self-review, `advisor ×2` on nontrivial) appear in the Internal Compliance table with honor-system designation.

---

## Internal Compliance

Every norm from `docs/principles.md` Definition of Done. **Enforcement type:** `automated` = script/CI always runs without human action; `agent-triggered` = agent invoked when condition met; `honor` = human commitment, no artifact enforces it.

| Norm | Enforcement type | Artifact | Honor-system gap? |
|---|---|---|---|
| ADR merged before implementation, if architecturally significant | Automated (partial) | `pre-commit-governance.sh` Rule 3 blocks commit without ADR-ref when decision-type files staged | Partial — Rule 3 fires only when ADR files are staged; whether an ADR was needed is human judgment |
| Domain docs updated if BC boundary or term changed | Agent-triggered | `domain-reviewer` invoked when `docs/domain/` changes | Yes — detecting *when* an update is needed is human judgment |
| Unit tests written; coverage ≥ 80% | Honor | None | Yes — no CI coverage gate in this repo |
| `/review` (Claude) approved | Honor | `/review` skill output (markdown, no merge gate) | Yes |
| `/codex-review` approved OR `type:deferred-review` issue created | Automated (partial) | `review-codex.sh` creates deferred issue on skip/quota | Partial — "approved" is human judgment; deferred-issue creation is automated |
| Disagreements between Claude and Codex resolved in PR thread | Honor | PR body convention | Yes |
| Human self-review performed | Honor | None | Yes |
| Security scans clean | Honor | None — no language-specific audit (pure shell/markdown repo) | Yes |
| Docs updated (README, runbook, CHANGELOG) | Agent-triggered (conditional) | `docs-reviewer` invoked when human-facing docs change | Partial — trigger detection is human judgment |
| Human-facing docs reviewed by `docs-reviewer` | Agent-triggered (conditional) | `docs-reviewer` invoked inside `/review` | Partial — trigger is honor; review itself is automated once triggered |
| Reliability reviewed by `reliability-reviewer` on prod-bound PRs | Agent-triggered (conditional) | `reliability-reviewer` invoked inside `/review` | Partial — prod-bound detection is honor; review itself is automated once triggered |
| CI green on all required jobs | Automated | `.github/workflows/` (ShellCheck, lint-prompts, etc.) | No |
| Conventional Commits; governance hook passed | Automated | `pre-commit-governance.sh` (PreToolUse + commit-msg) | No |
| PR body cross-references issue (`Closes #NNN`) | Honor | PR body convention | Yes |
| PR body cross-references ADR if one was authored | Automated (partial) | `pre-commit-governance.sh` Rule 3 requires ADR-ref in commit message | Partial — commit is enforced; PR body is honor |
| `advisor()` called ≥ 2× on nontrivial tasks (per advisor policy, `docs/principles.md` §6 — beyond DoD checklist but included here for completeness) | Honor | None | Yes — no mechanical enforcement; tracked in issue #101 |

**Meta-result:** 8 norms are full honor-system gaps; 6 are partially automated (trigger detection or approval step is human judgment); only 2 are fully automated (CI, governance hook). This table documents a partially aspirational DoD — not a description of a fully automated quality gate.

---

## Security

Security model summary: governance is enforced at the physical installation boundary (per-repo, not global); no global git config is mutated; system-secret-store and GUI-dependent steps are explicitly excluded from automation. Known unmitigated gap: governance hook fails open when `jq` is missing or stdin is malformed (see Red Hotspot #8).

Authoritative sources — no duplication here:

- **ADR-0008** (`docs/decisions/0008-hardware-universal-split.md`) — hardware layer vs. universal layer split; rationale for why GUI-dependent steps and system-secret-store operations are excluded from automation.
- **ADR-0011** (`docs/decisions/0011-git-level-governance-phase2.md`) — per-repository commit-msg hook installation; isolation principle (scope limited to explicit installation); rationale for no global git config.
- **Governance hook docs** — source: `bootstrap/hooks/pre-commit-governance.sh`; recovery procedures: `docs/runbooks/incident-recovery.md`.

---

## Red Hotspots

Unresolved questions left explicit — not papered over:

1. **`domain-researcher` has no pipeline stage trigger.** ADR 0013 names this gap. Correct trigger is "docs/domain/ missing or stale", not "greenfield only". Resolution requires ADR 0014. Tracked in issue #60.
2. **25 events may indicate God BC.** `BacklogGroomed` and the governance sub-flow (`CommitAttempted` / `GovernanceBlocked` / `GovernanceApproved`) are candidates for a separate BC. Not split here — decision deferred until the aggregate proves unwieldy in practice.
3. **Fan-out boundary is human judgement.** "Embarrassingly parallel" (ADR 0002) is defined by examples, not a mechanical rule. No automation path identified.
4. **Codex skip ≠ Codex disapproval.** DoD requires a `deferred-review` issue on skip, but the gate between skip and fail is operator judgement. Not modelled formally.
5. **Nontrivial-task criterion for advisor-×-2** is enumerated in `docs/principles.md` but requires judgement at the margin.
6. **Skill vs agent distinction can drift.** ADR 0007 is normative but subtle; new contributors may conflate them.
7. **ADR 0013 cited in domain policies is `proposed`, not `accepted`.** Policy `DomainDocsChanged → domain-reviewer` is contingent on ADR 0013 being accepted. This doc should be updated once ADR 0013 status changes.
8. **Governance hook fails open on malformed input.** If `jq` is not installed or stdin is not valid JSON, `pre-commit-governance.sh` exits 0 (fail-open), bypassing all commit policy rules. Documented in `docs/runbooks/incident-recovery.md` but not mechanically mitigated. Tracked in issue #109.
9. **`BacklogGroomed` placement in Commands and Domain Events is unresolved.** It appears in the table with an "out-of-band" label, implying it does not belong there. The organisational question is whether it should be in this table at all or replaced with a one-line cross-reference to a separate aggregate. Both "out-of-band" and "separate aggregate" mean the same thing; the tension is structural, not logical. Tracked in issue #107 for ADR resolution.
10. **Worktree isolation (ADR-0017) not modelled.** `bootstrap/scripts/sweep-worktree*.sh` implements per-ticket git worktree isolation (merged). It appears in neither Boundary nor Commands/Events. If sweep is in scope for this BC, add it. If out of scope, say so explicitly. Tracked in issue #110.
