# Bounded Context: claude-mini-pipeline

**Version:** 2026-04-24
**Status:** draft — pending domain-reviewer approval

## Purpose

This BC owns the workflow choreography for AI-assisted software development: pipeline stages, agent invocation, governance enforcement, ADR discipline, and the Definition of Done. It does NOT own the source code of projects where claude-mini is installed, Claude Code internals, or Anthropic model internals.

---

## Actors

| Actor | Role | Authority |
|---|---|---|
| **Operator** | Human running Claude Code; sole final decision-maker and author of production code | Full write, merge, approve |
| **Main Loop** (Sonnet) | Orchestrates all pipeline actions under operator direction | Write authority within repo |
| **Advisor** (Opus) | Consulted via `advisor()` before substantive work and before declaring done; two calls minimum on nontrivial tasks | Read-only; returns critique, not edits |
| **Read-only Critic** (subagent) | `adr-reviewer`, `domain-reviewer`, `security-reviewer`, `backlog-groomer` — evaluate artifacts, return markdown reports | Read-only; never writes to filesystem or mutates GitHub |
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
- Two-voice state machine: `{pending → agreed | disagreed → reconciled | disagreed → deferred}`
- `advisor()` called ≥ 2 times when task is nontrivial (per `docs/principles.md`)

**Note:** `BacklogGroomed` belongs to a separate out-of-band aggregate (weekly backlog run). It is not part of `FeatureRun`.

---

## Policies

| Trigger event/condition | Policy |
|---|---|
| `DomainDocsChanged` | Invoke `domain-reviewer` |
| `ADRDrafted` | Invoke `adr-reviewer` |
| PR contains prod-bound change | Invoke `security-reviewer` inside `/review` phase |
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

## Red Hotspots

Unresolved questions left explicit — not papered over:

1. **`domain-researcher` has no pipeline stage trigger.** ADR 0013 names this gap. Correct trigger is "docs/domain/ missing or stale", not "greenfield only". Resolution requires ADR 0014. Tracked in issue #60.
2. **24 events may indicate God BC.** `BacklogGroomed` and the governance sub-flow (`CommitAttempted` / `GovernanceBlocked` / `GovernanceApproved`) are candidates for a separate BC. Not split here — decision deferred until the aggregate proves unwieldy in practice.
3. **Fan-out boundary is human judgement.** "Embarrassingly parallel" (ADR 0002) is defined by examples, not a mechanical rule. No automation path identified.
4. **Codex skip ≠ Codex disapproval.** DoD requires a `deferred-review` issue on skip, but the gate between skip and fail is operator judgement. Not modelled formally.
5. **Nontrivial-task criterion for advisor-×-2** is enumerated in `docs/principles.md` but requires judgement at the margin.
6. **Skill vs agent distinction can drift.** ADR 0007 is normative but subtle; new contributors may conflate them.
7. **ADR 0013 cited in domain policies is `proposed`, not `accepted`.** Policy `DomainDocsChanged → domain-reviewer` is contingent on ADR 0013 being accepted. This doc should be updated once ADR 0013 status changes.
