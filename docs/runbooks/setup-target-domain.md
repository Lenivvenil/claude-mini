# Runbook: Setup target domain documentation in a pet-project

**Audience:** A developer starting a new pet-project who wants to integrate with the claude-mini meta-pipeline framework and needs to set up domain documentation for that project.

**Applies to:** Any pet-project that uses claude-mini as its AI pipeline framework.
**Context:** ADR-0027 (Domain Inversion: meta vs target BC). Each pet-project lives independently; its domain docs live in its own repo, not in claude-mini.

---

## When to use this runbook

Use this when starting work on a pet-project that:
- Has no `docs/domain/` directory yet, or
- Has a `docs/domain/` that mixes pipeline vocabulary with the project's own domain vocabulary, or
- You are running `/domain-discovery` for the first time in that project.

---

## What you are setting up

The `/domain-discovery` skill produces a single file per bounded context:

```
<your-project>/
└── docs/
    └── domain/
        └── <bc-name>/
            └── overview.md     ← BC overview: Purpose, Actors, Aggregates, UL, Context Map
        └── context-map.md      ← How this project's BC relates to meta-pipeline BC (ACL arrow)
```

The `overview.md` file contains all bounded context documentation including vocabulary (UL terms), aggregate roots, commands, events, policies, and context map edges — as one structured document. There is no separate `vocabulary.md` from the skill; vocabulary lives inside `overview.md` as a section.

---

## Step 1 — Check if domain work is needed

Not every pet-project warrants full DDD strategic design. Apply this heuristic:

| Project type | Domain docs needed? |
|---|---|
| Domain-rich (complex business rules, multiple aggregates, invariants that matter) | Yes — run `/domain-discovery` |
| CRUD / simple tooling (no meaningful invariants, no bounded context boundary) | No — skip domain docs; note the decision in CLAUDE.md |

If unsure: run `/domain-discovery` anyway; the structured interview will reveal whether a real bounded context exists.

---

## Step 2 — Run domain-discovery

In the pet-project repo, invoke the `domain-discovery` skill via structured five-phase interview:

```
/domain-discovery
```

The skill will:
1. Interview you about actors, events, boundary, vocabulary, and context map edges (5 phases, ~60 min)
2. Write the output to `docs/domain/<bc-name>/overview.md` (where `<bc-name>` is the BC name you agree on during the interview)

**Do not skip the interview.** The skill refuses to proceed without ≥ 5 events and ≥ 5 UL terms.

---

## Step 3 — Add context-map.md

Every pet-project's context-map must include at minimum one relationship to `meta-pipeline BC`. AACL = "Anti-Corruption Layer over Conformist": your project conforms to the pipeline schema, and the pipeline validates your artifacts before accepting them.

```markdown
# Context Map — <project-name>

## <project-name> BC ↔ meta-pipeline BC

Relationship: **AACL (Anti-Corruption Layer over Conformist)**

- Your project (target BC) conforms to meta-pipeline BC schema: pipeline stages,
  governance rules, artifact formats (plan.md, ADR, qa-report, commit-message).
- meta-pipeline BC validates incoming target artifacts through ACL before accepting them
  (plan-lint.sh, governance hook, @agent-domain-reviewer).
- meta-pipeline BC does NOT know your domain vocabulary (it only knows "an artifact
  exists and conforms to schema").

See: docs/decisions/0027-domain-inversion-meta-vs-target-bc.md in the claude-mini repo.
```

For the full Mermaid diagram of this relationship, see `docs/domain/context-map.md` in the claude-mini repo.

---

## Step 4 — Keep domain docs in the project repo

**Do not** put `docs/domain/<project-name>/` inside the claude-mini repo.
Each project's domain lives in that project's own `docs/domain/`.

When working on a pet-project from within a claude-mini session, load the project's domain docs via explicit Read or `@` import:

```
@/path/to/myproject/docs/domain/<bc-name>/overview.md
```

**Note:** `@`-import syntax is Claude Code-specific. If using Codex CLI, Goose, or another agent tool, use explicit file Read instead of `@` imports.

---

## Step 5 — Register the domain in CLAUDE.md (optional)

If you want the project's domain loaded automatically when working on it, add an `@` import in the project's `CLAUDE.md` (Claude Code-specific):

```markdown
@docs/domain/<bc-name>/overview.md
```

---

## Checklist

- [ ] Decided whether project is domain-rich (if not, document the decision in CLAUDE.md and stop)
- [ ] `/domain-discovery` run: `docs/domain/<bc-name>/overview.md` created with ≥ 5 UL terms and ≥ 5 domain events
- [ ] `docs/domain/context-map.md` created and includes AACL relationship to meta-pipeline BC
- [ ] Domain docs live in the project's repo, not in claude-mini
- [ ] `@agent-domain-reviewer docs/domain/<bc-name>/overview.md` run inside that project's session (not from claude-mini)

---

## References

- `docs/decisions/0027-domain-inversion-meta-vs-target-bc.md` — decision that mandates this separation
- `docs/domain/meta/vocabulary.md` — meta-pipeline BC vocabulary (reference, do not copy)
- `bootstrap/skills/domain-discovery/SKILL.md` — the skill this runbook invokes
