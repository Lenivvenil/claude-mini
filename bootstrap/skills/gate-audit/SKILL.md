---
name: gate-audit
description: Weekly gate ROI audit skill. Run weekly to aggregate events.jsonl, produce docs/gate-audit/YYYY-WW.md, and emit REMOVE/KEEP/INSUFFICIENT_DATA recommendations. Invoke when asked to "run gate audit", "check gate ROI", or "gate-audit report".
---

# Gate audit skill

## When to invoke

- Operator runs `/gate-audit`
- Weekly CI cron job (see `.github/workflows/ci.yml` `gate-audit` job)
- After manually tagging events with `forge gate-tag`

## Prerequisites

- `bootstrap/scripts/gate-audit-aggregate.sh` installed (via `./bootstrap/universal-setup.sh --install`)
- `python3` available
- `docs/gate-audit/events.jsonl` committed with recent events

## How to run

### Weekly report (CI or manual)

```bash
bash ~/.claude/scripts/gate-audit-aggregate.sh
# output: docs/gate-audit/YYYY-WW.md and docs/gate-audit/aggregate.jsonl
```

Dry-run (prints to stdout, writes nothing):

```bash
bash ~/.claude/scripts/gate-audit-aggregate.sh --dry-run
```

### Tagging a gate event post-hoc

After a gate fires, the hook prints:
```
[gate-audit] event_id: abc12345def67890 (gate: pre-commit-governance, outcome: blocked)
```

Tag it as a real block:
```bash
bash ~/.claude/scripts/forge.sh gate-tag abc12345def67890 --real
```

Tag it as a false positive:
```bash
bash ~/.claude/scripts/forge.sh gate-tag abc12345def67890 --false-positive
```

Tag the most recent unclassified event:
```bash
bash ~/.claude/scripts/forge.sh gate-tag --latest --real
```

Then commit the updated `docs/gate-audit/events.jsonl`:
```bash
git add docs/gate-audit/events.jsonl
git commit -m "chore(gate-audit): tag events YYYY-WW #122"
```

## Output

Weekly report written to `docs/gate-audit/YYYY-WW.md` with one section per gate showing:
- Retention recommendation: `KEEP` / `REMOVE` / `INSUFFICIENT_DATA`
- Per-week table: frequency, real blocks, FP, bypasses, estimated cost

Aggregate JSONL written to `docs/gate-audit/aggregate.jsonl`. Schema documented in
`docs/gate-audit/schema.md`.

### Interpreting REMOVE

A `REMOVE` recommendation means `real / (real + fp + bypass) < 0.2` for 4 consecutive
qualifying weeks. This is a signal to review the gate, not an automatic deletion.
Human approval is required before removing any gate.

## Hard rules

- Do NOT automatically remove a gate. Open a PR for human review.
- Do NOT treat `INSUFFICIENT_DATA` as KEEP or REMOVE. Wait for more data.
- Do NOT commit aggregate.jsonl or YYYY-WW.md without first reviewing them for correctness.
- Events from direct `git commit` (bypassing Claude Code) are not captured. Acknowledge this
  measurement bias in any analysis.
- `est_cost_min` is operator-estimated and often null. Do not treat null as zero cost.
