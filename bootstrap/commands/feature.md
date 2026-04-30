---
description: Master orchestrator for feature work. Ведёт по всем стадиям pipeline через TodoWrite.
argument-hint: <issue-number>
allowed-tools: Bash(gh issue view:*), Bash(gh project item-list:*), Bash(gh project item-edit:*), Read, TodoWrite
model: claude-sonnet-4-6
---

# /feature

Issue: !`gh issue view $ARGUMENTS --json number,title,body,labels,milestone`

<!-- Project: claude-mini (PVT_kwHOAD4W5M4BVPoL, #5) | Field: Status (PVTSSF_lAHOAD4W5M4BVPoLzhQsxg4) | Options: In Progress=47fc9ee4  In review=b5178a00 -->

**On startup — check pipeline version drift.** Run as first startup step. Warn and continue regardless of result.

```bash
_pv_baked="@@PIPELINE_VERSION@@"
# If _pv_baked still contains @@ the file was loaded without --target baking; skip check.
if ! echo "$_pv_baked" | grep -qF '@@'; then
  _pv_file="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/pipeline-version"
  if [ ! -f "$_pv_file" ]; then
    echo "⚠ Pipeline not installed per-project (.claude/pipeline-version missing)."
    echo "  Run from claude-mini bootstrap repo: ./bootstrap/universal-setup.sh --target $(git rev-parse --show-toplevel 2>/dev/null)"
  else
    _installed="$(cat "$_pv_file")"
    if [ "$_installed" = "$_pv_baked" ]; then
      : # current — silent
    elif [ "$(printf '%s\n%s\n' "$_installed" "$_pv_baked" | sort -V | head -1)" = "$_installed" ] && [ "$_installed" != "$_pv_baked" ]; then
      echo "⚠ Pipeline drift: project at $_installed, this command is $_pv_baked."
      echo "  Run from claude-mini bootstrap repo: ./bootstrap/universal-setup.sh --target $(git rev-parse --show-toplevel 2>/dev/null)"
    fi
    # future state (_installed > _pv_baked): treated as current — silent
  fi
fi
unset _pv_baked _pv_file _installed
```

**On startup — move issue to In Progress.** Run immediately before creating the checklist. Graceful: warn and continue on any failure.

```bash
if [ -z "$ARGUMENTS" ]; then
  echo "⚠ No issue number — skipping status transition"
else
  ITEM_ID=$(gh project item-list 5 --owner Lenivvenil --format json \
    --jq ".items[] | select(.content.number == ($ARGUMENTS | tonumber)) | .id" 2>/dev/null)
  if [ -n "$ITEM_ID" ]; then
    gh project item-edit --project-id PVT_kwHOAD4W5M4BVPoL \
      --id "$ITEM_ID" --field-id PVTSSF_lAHOAD4W5M4BVPoLzhQsxg4 \
      --single-select-option-id 47fc9ee4 \
    && echo "✓ Issue #$ARGUMENTS → In Progress" \
    || echo "⚠ Status transition failed — continuing"
  else
    echo "⚠ Issue #$ARGUMENTS not found in claude-mini project — status not updated"
  fi
fi
```

## Your task

You are an **orchestrator**, not an executor. You do not run `/plan`, `/implement` etc. yourself — the operator does, explicitly. Your role is to hold the checklist and nudge.

### Step 1: Create TodoWrite checklist

\`\`\`
[ ] 1. Read issue #$ARGUMENTS acceptance criteria
[ ]    1b. Only if docs/domain/ is empty, or the issue scope obviously diverges
[ ]        from docs/domain/vocabulary.md: invoke @agent-domain-researcher
[ ]        (run after reading the issue so you know whether the domain is in scope)
[ ] 2. Run /plan $ARGUMENTS
[ ] 3. Call advisor() to critique plan
[ ] 4. Determine if ADR needed (principle: architecturally significant?)
[ ]    4a. If yes: invoke @agent-solutions-architect → /adr
[ ]    4b. After ADR draft: invoke @agent-adr-reviewer; wait for APPROVE verdict
[ ]    4c. Merge ADR PR before /implement
[ ]    4d. If ADR was authored: re-sync `plan.md §4` with merged ADR per `docs/runbooks/adr-workflow.md` step 6
[ ] 5. Run /implement
[ ]    5a. (inside /implement) Call advisor() before declaring done — MANDATORY for non-trivial
[ ]    5b. Only if docs/domain/ was modified during /implement:
[ ]        invoke @agent-domain-reviewer; wait for APPROVE verdict
[ ] 6. Run /qa
[ ]    6a. Review qa-report.md; resolve test gaps or confirm escape hatch accepted
[ ]    6b. Copy ## QA section from qa-report.md — paste into PR body at step 11
[ ] 7. Run /review
[ ]    7a. Only if PR touches prod-bound paths (bootstrap/, .github/workflows/,
[ ]        .git/hooks/) or is labelled prod-bound:
[ ]        invoke @agent-security-reviewer AND @agent-reliability-reviewer inside this review phase
[ ]    7b. Only if PR touches human-facing docs (docs/runbooks/, docs/architecture/,
[ ]        docs/principles.md, README.md) — and not exclusively docs/decisions/ or docs/domain/:
[ ]        invoke @agent-docs-reviewer inside this review phase
[ ]    7c. Always (after Layer 1 passes): invoke @agent-adversarial-critic — pass the diff
[ ]        as context; wait for verdict; BLOCK findings must be resolved before merge
[ ]        If agent unavailable (not installed): document in PR thread as graceful-degradation;
[ ]        run ./bootstrap/universal-setup.sh --install to restore
[ ] 8. Run /codex-review
[ ] 9. Resolve findings; decide on disagreements
[ ] 10. git commit (governance hook checks)
[ ] 11. gh pr create with "Closes #$ARGUMENTS" — include ## QA section in PR body
[ ] 12. PR ready for human review
\`\`\`

### Step 2: Nudge operator through stages

After each stage:
- **Confirm completion** — ask "Did /plan produce plan.md? Did you call advisor?"
- **Block bad transitions** — "You're about to /implement but plan.md doesn't exist. Run /plan first."
- **Recognize ADR branches** — if plan discusses library choice or BC boundary, push hard: "This is ADR territory. Don't skip step 4a."

### Step 2b: Step 11 completion — In Review transition

Immediately after `gh pr create` succeeds (step 11) and before marking step 11 complete, run:

```bash
if [ -z "$ARGUMENTS" ]; then
  echo "⚠ No issue number — skipping status transition"
else
  ITEM_ID=$(gh project item-list 5 --owner Lenivvenil --format json \
    --jq ".items[] | select(.content.number == ($ARGUMENTS | tonumber)) | .id" 2>/dev/null)
  if [ -n "$ITEM_ID" ]; then
    gh project item-edit --project-id PVT_kwHOAD4W5M4BVPoL \
      --id "$ITEM_ID" --field-id PVTSSF_lAHOAD4W5M4BVPoLzhQsxg4 \
      --single-select-option-id b5178a00 \
    && echo "✓ Issue #$ARGUMENTS → In Review" \
    || echo "⚠ Status transition failed — continuing"
  else
    echo "⚠ Issue #$ARGUMENTS not found in claude-mini project — status not updated"
  fi
fi
```

### Step 3: Finish

When all 12 items checked, report:
> PR #<N> opened for issue #$ARGUMENTS. DoD status: {X}/{Y} criteria met. Outstanding: {list}.

## Hard rules

- You do NOT execute `/plan`, `/implement`, etc. — operator runs them.
- You do NOT mark a step complete without verification (e.g., file exists, advisor visible in recent tool calls).
- You DO remind operator about advisor if plan is nontrivial — it's the most common missed step.
