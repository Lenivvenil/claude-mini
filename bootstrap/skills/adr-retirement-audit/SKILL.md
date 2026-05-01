---
name: adr-retirement-audit
description: Weekly ADR staleness audit. Checks each ADR for incoming refs, superseded-by chain consistency, and dep presence. Emits keep|mark-deprecated|mark-superseded recommendations. Invoke when asked to "run adr audit", "check stale ADRs", or "adr-retirement-audit".
---

# ADR retirement audit skill

## When to invoke

- Weekly CI cron (see `.github/workflows/ci.yml` `adr-retirement-audit-weekly` job)
- Manually: "run adr audit", "check stale ADRs", "adr-retirement-audit"

## Prerequisites

- `bootstrap/scripts/adr-retirement-audit.sh` available
- Running inside a git repository with `docs/decisions/` present

## How to run

### Report only (read-only, no writes)

```bash
bash bootstrap/scripts/adr-retirement-audit.sh
```

### Apply recommendations to specific ADRs

After reviewing the report, apply status updates to named ADRs (append-only, operator-confirmed):

```bash
bash bootstrap/scripts/adr-retirement-audit.sh --apply 0004,0013
```

`--apply` only updates `* Status:` and `* Superseded-by:` frontmatter fields. Content is never modified.

### Override threshold (days)

```bash
bash bootstrap/scripts/adr-retirement-audit.sh --threshold 60
```

## Output

Report written to stdout as markdown. Columns: ADR number, title, current status, superseded-by, incoming-ref count, recent-ref count (within threshold days), recommendation.

Recommendation values:

| Value | Meaning |
|---|---|
| `keep` | ADR is actively referenced or superseded-by chain is consistent |
| `mark-deprecated` | Zero incoming refs; tech may no longer apply |
| `mark-superseded` | `superseded-by` field is set; target file exists and is consistent |

## Notes

- `--apply` requires zero-padded 4-digit ADR numbers (e.g. `0004`) or bare integers (e.g. `4`) — both accepted.
- ADRs created before this feature (lacking `* Superseded-by:` field) are handled gracefully — field is treated as `~`. When `--apply mark-superseded` runs, the field is inserted after `* Status:`.

## Hard rules

- Do NOT auto-apply recommendations without operator review. `--apply` requires explicit ADR numbers.
- Do NOT modify ADR content — only `* Status:` and `* Superseded-by:` frontmatter fields.
- Do NOT delete ADR files. Status `deprecated` or `superseded` is the only retirement mechanism.
- `mark-deprecated` is a recommendation, not a command. Operator decides and confirms.
- Do NOT treat `keep` as proof the ADR is correct — only that it is currently referenced.
