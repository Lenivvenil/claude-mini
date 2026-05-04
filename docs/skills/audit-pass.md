# audit-pass skill

**Purpose:** Supervisory quality re-pass for human-authored GitHub tickets (Principle 9). Checks structural completeness and outputs diff suggestions — never auto-edits.

**Script:** `bootstrap/scripts/ticket-audit.sh`  
**Install:** `./bootstrap/universal-setup.sh --install` (skills go to `~/.claude/skills/`)

---

## Usage

```
audit-pass on issue #129
audit-pass on my-ticket.md
```

Labels check is skipped in file mode.

---

## What gets checked

| Field | Rule |
|---|---|
| title | Conventional Commits prefix: `feat\|fix\|docs\|chore\|refactor\|test\|perf\|ci\|build\|revert` |
| priority | `P0`–`P3` present in body |
| labels | ≥1 label (issue mode only) |
| problem-statement | `## Problem statement` with ≥1 non-empty line |
| acceptance-criteria | `## Acceptance criteria` with ≥3 `- [ ]` items |
| non-goals | `## Non-goals` section present |
| references | `## References` with ≥1 `Принцип N` line |
| estimate | `Estimate: S`, `M`, or `L` in body (bold format handled) |

---

## Human accept-or-reject

Suggestions are output only. Apply via `gh issue edit <N> --title "..."` or manual edit. Reject by doing nothing.

---

## Installation note

Skills install globally via `--install`, not per-project via `--target`. To use:

```bash
./bootstrap/universal-setup.sh --install
```
