---
description: QA gate — test coverage + docs currency. Fires after /implement, before /review.
allowed-tools: Read, Glob, Grep, Bash(git diff:*), Bash(git show:*), Bash(git status:*), Bash(git log:*), Bash(find:*), Edit, Write
model: claude-sonnet-4-6
---

# /qa

Plan: @plan.md
Principles: @docs/principles.md

## Your task

Two-checklist pass after `/implement`, before `/review`. Produces `qa-report.md` at the repo root.

### Phase 0 — Carve-out check

Get the list of changed files (`git diff --cached --name-only || git diff HEAD --name-only || git show --name-only --format=`).

Evaluate carve-outs strictly in the order below. **If step 1 matches: write the report, stop immediately — do not evaluate step 2.**

1. **ADR-only** (most specific — evaluate first): every changed file matches `docs/decisions/*.md`. If true → write `qa-report.md` with body `## QA\n\nCarve-out: ADR-only diff. No test or docs check required.` Print it. **Exit.** Do not proceed to step 2 or Phase 1.
2. **Docs-only**: every changed file matches `*.md`. If true → write `qa-report.md` with body `## QA\n\nCarve-out: docs-only diff. No test or docs check required.` Print it. **Exit.** Do not proceed to Phase 1.

Always record the carve-out reason — never exit silently.

### Phase 1 — Diff triage

Get the full diff: `git diff --cached` (staged) → `git diff HEAD` (working tree) → `git show HEAD` (last commit). Use first non-empty result.

### Phase 2 — Test coverage

For each modified `.sh`, `.py`, or other logic file in the diff:

1. Extract the filename stem (e.g., `review-codex` from `bootstrap/scripts/review-codex.sh`).
2. Search for a test file: `find . -name "test_${stem}*" -o -name "${stem}_test*" -o -name "*.bats" 2>/dev/null`.
3. Also check for a `tests/` directory at the repo root.
4. **If a test file exists**: grep it for the names of changed functions or identifiers. If the changed logic is exercised → mark ✓. If not → note the gap.
5. **If a gap exists AND a harness exists**: write a minimal smoke test that calls the changed entry point with a representative input and asserts exit code or key output line.
6. **If no harness exists** (no test files found, no `tests/` dir, no `.bats` files): record the fixed escape-hatch notice verbatim:
   > `No test harness for [shell scripts]. Escape hatch applied. Add ## QA section to PR body noting this before merge.`

Do not write large test suites. One smoke test per changed entry point is sufficient. If a **new** `.sh` file was created with no corresponding test, additionally note: "New shell script with no harness detected. Consider introducing bats: `brew install bats-core`."

### Phase 3 — Docs currency

For each changed file, identify public contracts that may have documentation:

- **CLI flags / options**: if a script gained or changed a `--flag` or positional arg, check that `--help` output (if any) and relevant runbook in `docs/runbooks/` still match.
- **Runbook-documented behavior**: search `docs/runbooks/` for the script name; if found, check that the described behavior still matches the diff.
- **CLAUDE.md references**: if the changed file is named in `CLAUDE.md` canonical pipeline or table, check that the description is still accurate.

For each stale doc found: produce the patch inline (edit the runbook or update the `--help` string). State clearly what was updated.

If no public contracts changed: record `Docs: all contracts current.`

### Phase 4 — QA report

Write `qa-report.md` to the repo root:

```markdown
## QA

**Tests:** <one of: "all changed paths covered" | list of gaps + what was written | escape hatch notice>

**Docs:** <one of: "all contracts current" | list of updates made>
```

Print the contents of `qa-report.md` to stdout.

Tell the operator: "Copy the `## QA` section above into the PR body at `gh pr create` time."

## Hard rules

- NEVER exit without writing `qa-report.md`. Every path — carve-out, escape hatch, happy — produces the file.
- NEVER silently skip. Either report ✓, state the escape hatch verbatim, or state the carve-out reason.
- This is advisory: you surface findings. Human self-review is the final gate. Do NOT block the pipeline.
- Carve-outs are file-path based. There is no commit-message carve-out — no commit exists yet at `/qa` time.
- If `/qa` writes a test or runbook patch, state clearly in the report that Claude authored it, so `/review` can attribute correctly.
