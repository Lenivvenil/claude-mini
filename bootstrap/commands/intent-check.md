---
description: Compare acceptance criteria from a GitHub issue against the current branch diff. Reports each AC item as covered | partial | missing | unrelated-changes.
argument-hint: <issue-number>
allowed-tools: Bash(gh issue view:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(grep:*)
model: claude-sonnet-4-6
---

# /intent-check

**Pipeline version drift check.** Run first; warn and continue.

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

**Inputs:**

```bash
# Validate issue number (must be numeric)
case "$ARGUMENTS" in
  ''|*[!0-9]*) echo "❌ /intent-check requires a numeric issue number (e.g. /intent-check 133)"; exit 2 ;;
esac

# Deterministic AC extraction — pipe to grep; result is empty if no checklist items
gh issue view "$ARGUMENTS" --json body -q '.body' | grep -E '^\s*-\s*\[[ x]\]'

# Full issue body (needed for fallback to ## Acceptance criteria section)
gh issue view "$ARGUMENTS" --json body -q '.body'

# Diff to evaluate
git diff main...HEAD
```

## Your task

### Step 1 — Extract AC items (deterministic)

The grep output from Inputs is your primary AC list. If it is empty (zero lines), fall back: locate the `## Acceptance criteria` section in the full issue body and use its text as the AC source for Step 2.

### Step 2 — Classify each AC item (semantic)

For each AC item, read the full diff and assign exactly one status:

- **`covered`** — the diff directly implements this criterion; functional code or tests are present and clearly address it
- **`partial`** — the diff touches the relevant area but does not fully satisfy the criterion (e.g. wiring exists but no test, or one of two required paths handled)
- **`missing`** — no part of the diff addresses this criterion

`unrelated-changes` is a diff-level finding, not a per-AC status — see Step 3.

### Step 3 — Output

Produce a markdown table (three statuses only: `covered`, `partial`, `missing`):

```
| # | AC item (shortened) | Status | Evidence (file:line or "none") |
|---|---|---|---|
| 1 | ... | covered | bootstrap/commands/intent-check.md:1 |
| 2 | ... | partial | bootstrap/commands/feature.md:78 (wiring present, no test) |
| 3 | ... | missing | none |
```

Then one summary line:

```
Summary: X/Y covered or partial; Z missing.
```

If `missing > 0`: list the missing items explicitly so the operator can decide whether to fix or document as a conscious scope gap.

**Unrelated changes:** After the table, add a separate `### Unrelated changes` block listing diff hunks (files) that have no corresponding AC item. If none, omit the block.

## Non-goals

- Does NOT generate tests or implementation suggestions.
- Does NOT replace manual review or `/review`.
- Does NOT block the pipeline: output is advisory; operator decides action on `missing` items.
- Does NOT handle diffs >1000 changed lines well (context limits); future issue can add `--stat` pre-filtering.
- Does NOT produce useful output when run on `main` directly (diff will be empty — run on a feature branch).
- Does NOT recover from `gh` auth failures or malformed issue numbers (fails with a `gh` error; fix auth/number and rerun).
- Does NOT handle issues with no `## Acceptance criteria` section and no `- [ ]` items (outputs "No AC items found").
- Does NOT parse AC written as plain bullets (`- text`) or numbered lists (`1. text`) deterministically — only GitHub task-list syntax (`- [ ]` / `- [x]`) is parsed via grep; other formats fall back to LLM free-text extraction without a warning.
- Assumes default branch is named `main` (`git diff main...HEAD`); projects using `master` or another name must adjust or will get an empty diff.

## Hard rules

- You MUST list every AC item found — omitting one item is worse than a noisy table.
- You MUST provide `Evidence (file:line)` for any `covered` or `partial` claim. "none" is only valid for `missing`.
- A `covered` claim without file:line evidence is not valid.
- You do NOT auto-block the pipeline. Every verdict is advisory.
