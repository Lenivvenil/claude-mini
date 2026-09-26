---
name: plan
description: Plan a change against a GitHub issue before writing code. Writes plan.md with considered approaches, test strategy and risks; does not touch code.
argument-hint: "[issue-number]"
allowed-tools: Bash(gh issue view:*) Read Glob Grep Write Bash(${CLAUDE_PLUGIN_ROOT}/bin/jev-check:*)
---

# /plan

Issue: !`gh issue view $ARGUMENTS --json number,title,body,labels 2>/dev/null || echo "no issue given or gh unavailable — ask the user what to plan"`

Project rules: read `AGENTS.md` (and `CLAUDE.md` if it adds anything). If `docs/decisions/` exists, list it and read the ADRs the change touches.

## Your task

Write `plan.md` in the repo root with exactly these sections:

1. **Problem restatement** — one paragraph in your own words, not a copy of the issue.
2. **Affected files** — paths, grounded in the code you actually read.
3. **Considered approaches** — at least two with trade-offs, or one with an explicit reason why it is the only one.
4. **Chosen approach and why** — cite ADRs or project rules where they decide it, quoting the sentence you rely on.
5. **Test strategy** — what fails before the change and passes after; which existing tests must stay green.
6. **Risks and unknowns** — an honest list; "none" is a smell.

If the change is architecturally significant by the project's own rules (a new cross-cutting dependency, a changed public API or contract, a hard-to-reverse constraint, a security or data-model change), say so at the top of plan.md and suggest `/claude-mini:adr-author` before implementation.

## Advisory check

After writing `plan.md`, run it with the issue on stdin, so the check sees the acceptance criteria:

```bash
gh issue view <N> --json title,body -q '.title + "\n\n" + .body' | "${CLAUDE_PLUGIN_ROOT}/bin/jev-check" plan.md -
```

Without an issue, run `"${CLAUDE_PLUGIN_ROOT}/bin/jev-check" plan.md`. Read its one-line JSON.
- `ok` with findings: append a section `## Advisory (Jev)` to `plan.md`, one line per finding with its probability. Review each and fix the plan where you agree. Advice only: it does not block, approve or waive anything.
- Any other status (`disabled`, `unavailable`, `timeout`, `invalid_response`, `oversized_state`): mention it in the chat line. It says nothing about plan quality.

## Output

`plan.md` in the repo root with the six sections above, and one line in chat: the path, the chosen approach, and whether an ADR is suggested.

## Hard rules

- Do not write code. Only `plan.md`.
- Every claim about the code cites `path:line`.
- Do not commit `plan.md` unless the project tracks plans.
