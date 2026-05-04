---
name: audit-pass
description: Supervisory quality re-pass for human-authored GitHub tickets (Principle 9). Invoke when asked to "audit-pass", "audit pass", "check ticket quality", "supervisory re-pass", or "lift ticket #N". Runs structural completeness check and outputs diff suggestions.
---

# audit-pass skill

## When to invoke

- Operator asks: "run audit-pass on issue #N", "check ticket quality", "supervisory re-pass #N"
- After a human-authored ticket is created between LLM sessions (Principle 9 interception contract)
- Before running `/plan` on a ticket authored without LLM pipeline assistance

## Two-layer structure (ADR-0023)

Layer 1 (deterministic): `bootstrap/scripts/ticket-audit.sh` checks 8 structural fields.
Layer 2 (LLM): for each FAIL field, generate a targeted diff suggestion.

If all fields PASS: report clean — no diff suggestions.

## How to run

### Step 1 — ask operator for the ticket reference

> "Issue number or local file path?"

### Step 2 — run Layer 1

**By issue number (preferred — fetches live from GitHub):**

```bash
bash bootstrap/scripts/ticket-audit.sh <N>
```

**By local file:**

```bash
bash bootstrap/scripts/ticket-audit.sh path/to/ticket.md
```

Labels check is skipped in file mode (documented in output).

### Step 3 — Layer 2: generate diff suggestions for FAIL fields

For each line in the script output that starts with `FAIL`:

1. Identify the field name and the failure reason.
2. Generate a fenced markdown diff block showing what to add or replace.
3. When in issue-number mode, append a ready-to-copy `gh issue edit` command.

Do not generate suggestions for PASS or SKIP fields.

### Step 4 — present the full report

Show the raw script output first (Layer 1), then the diff suggestions (Layer 2).

## Output

```
## Audit results — issue #<N> (or <file>)

<raw ticket-audit.sh output — PASS/FAIL/SKIP table>

## Suggested fixes

### <field-name> (if FAIL)

<explanation of what's missing or malformed>

\`\`\`diff
- <current value or "(missing)">
+ <suggested replacement>
\`\`\`

<gh issue edit command if issue-number mode>
```

If all fields pass:

```
## Audit results — issue #<N>

<raw ticket-audit.sh output — all PASS>

All fields pass. No suggestions needed.
```

## Hard rules

- Do NOT auto-edit the issue. Output suggestions only. The operator decides whether to apply each suggestion via `gh issue edit` or manual edit.
- Do NOT block ticket creation or pipeline flow. This skill is a lift, not a gate — Principle 9 "не блокирует, а лифтит".
- Do NOT fabricate issue content. Run the script; read the actual output.
- Labels SKIP in file mode is expected and correct. Do not treat it as a failure.
- Do NOT run the script without confirming the issue number or file path with the operator first.
