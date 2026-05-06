---
name: review
description: Two-layer code review of staged diff against plan.md and docs/principles.md. Layer 1: deterministic gates via verify.sh. Layer 2: LLM review with adversarial critique. Use when reviewing a feature branch before commit, after /qa, or when asked to "review", "run review", or "check the diff". Requires plan.md and claude-mini pipeline installed.
---

# Review skill

## When to invoke

- "run review", "review the diff", "check the diff"
- After `/qa`, before commit
- "проверь изменения", "запусти ревью"
- When a feature branch has staged or committed changes and `plan.md` is present

## Prerequisites

- `plan.md` present in repo root
- `~/.claude/scripts/verify.sh` installed (via `./bootstrap/universal-setup.sh --install`) — Layer 1 gate
- `docs/principles.md` and `docs/domain/meta/overview.md` present

## Steps

Layer-1 gate: `bash ~/.claude/skills/review/scripts/layer1-gate.sh 2>&1`
Diff: `git diff --cached HEAD 2>/dev/null || git diff HEAD 2>/dev/null || git show HEAD`
Plan: @plan.md
Principles: @docs/principles.md
ADRs: `ls docs/decisions/ 2>/dev/null`
Domain contracts: @docs/domain/meta/overview.md

### LAYER 1 GATE RULE — READ THIS FIRST

Scan the Layer-1 gate output for the string `LAYER1_FAILED`.

**If `LAYER1_FAILED` is present:**
1. Copy the full gate output into a fenced code block labelled `[LAYER1-BLOCK]`.
2. End with: "Fix layer-1 findings before re-running review. Do not proceed to LLM review."
3. **STOP. Do not analyse the diff. Do not write any review sections.**

**If the gate output contains `LAYER1_SKIPPED`:**
`verify.sh` is not installed. **STOP.** Do not proceed to Layer 2. Tell the operator:
> "Layer 1 gate was skipped — `verify.sh` not installed. Run `./bootstrap/universal-setup.sh --install`, then re-run review. To override and proceed without deterministic gates, explicitly say so."
Only continue to Layer 2 if the operator explicitly acknowledges the skip.

**If `LAYER1_FAILED` is NOT present and `LAYER1_SKIPPED` is NOT present (gate shows `LAYER1_PASSED`):**
All deterministic gates passed. Proceed to Layer 2 below.

---

### Layer 2 — LLM review (only if Layer 1 passed)

Review the diff against the plan, principles, and domain contracts. Return markdown with sections:

- **Correctness** — does it do what the plan says?
- **Security** — obvious red flags (sql/cmd injection, secret leaks, missing auth)?
- **Performance** — any N+1, accidental quadratic, sync-in-async?
- **Style** — consistent with existing codebase patterns?
- **Tests** — present, meaningful, covering edge cases?
- **Plan/ADR deviation** — any implicit drift from written artefacts?
- **Domain invariants** — does the diff violate any `FeatureRun` invariant or contradict a row in the Policies table from `docs/domain/meta/overview.md`? Check: single issue-ref per run, monotonic DoD checklist, two-voice state machine, advisor ≥ 2 on nontrivial tasks. If the diff does not touch pipeline-contract files, state "N/A — diff does not affect pipeline contracts" and move on.
- **AC alignment** — run `/intent-check <issue-number>` (or invoke inline if issue number is available from plan.md or branch name). For each AC item, classify as `covered | partial | missing`; diff hunks without a matching AC item are reported in a separate "Unrelated changes" block. Output the result table. If any item is `missing`, flag as SUGGEST unless operator has already documented it as a conscious scope gap in the PR thread.

### Severity convention

- **BLOCK** — must fix before merge
- **SUGGEST** — improve if trivial, else note in PR
- **NIT** — optional

### Layer 3 — Adversarial critique (always, after Layer 1)

After Layer 1 passes, the operator invokes `@agent-adversarial-critic` and passes the diff as context. Layer 3 runs independently of Layer 2 — its findings are available as input when Layer 2 executes.

The adversarial-critic scans for LLM lazy patterns (duplicate code, symptom-fix, narrow special-case, copy-paste, truncated files, magic constants, TODO-without-ticket, commented-out code). It loads `docs/anti-patterns.md` at startup. Its findings feed into the `claude_review` artifact — they are not a separate review voice.

**Gate rule:** A BLOCK finding from adversarial-critic must be resolved before merge OR explicitly documented as a conscious compromise in the PR thread (operator signs off, explains why).

**Sanity check:** Verify that the agent's `**Diff reviewed:** N files, M lines added` matches the actual PR. An APPROVE on an empty or partial diff is not a valid approval.

**Failure handling:** If invocation fails (model error, context overflow) or `docs/anti-patterns.md` is unavailable, re-invoke. If failure persists, document in PR thread as graceful-degradation: `adversarial-critic skipped — <reason>`. This does not substitute for a passing review.

**Audit trail:** Append the adversarial-critic findings section verbatim into the `claude_review` artifact (or PR thread), even when verdict is APPROVE, so the scan is visible to future readers.

## Output

Markdown review artifact with all Layer 2 sections populated. Final line: `**Verdict: APPROVE | REQUEST CHANGES**` with summary of blocking findings (if any).

## Hard rules

- Do NOT approve "LGTM" without an actual scan. Empty findings is only valid if nothing found AFTER full scan.
- Do NOT nitpick style unless the codebase itself has a consistent pattern being violated.
- DO flag plan drift loudly — "implementation diverged from plan" is a BLOCK severity even if the divergence is an improvement, because plan should be updated first.
