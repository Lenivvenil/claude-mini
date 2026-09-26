# Banned terms

Authoritative list of terms that must not appear in `plan.md`, ADR drafts, agent prompts, PR descriptions, or any other project artifact.

Scan is **case-insensitive**. Each entry lists the banned form, the required substitution, and the rationale.

---

## Employer / company reference

**Scannable pattern:** `employer-owned repositories` (case-insensitive)

**Human-author guidance (no machine pattern — use judgment):**
- Do not name the employer or company anywhere in artifacts. Use "сторонние репо", "не-pet-проекты", or "third-party repositories" instead.

| Banned form | Use instead |
|---|---|
| `employer-owned repositories` | "сторонние репо", "не-pet-проекты", or "third-party repositories" |

---

## How to use this list

In `/implement` Phase 1, before reading any project files:

```
Read this file. For each banned term above, check plan.md (case-insensitive).
If any match: STOP. Fix plan.md before continuing.
```

In the operator checklist (`docs/runbooks/feature-pipeline.md` step 2): verify plan.md is clean before calling advisor or running `/implement`.
