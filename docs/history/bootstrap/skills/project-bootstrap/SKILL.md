---
name: project-bootstrap
description: Navyk dlya sozdaniya novogo proekta v soglasovannoj strukture. Ispol'zuj pri zaprose "novy proekt", "bootstrap project", "sozdat' repo", "new repository", "nachat' proekt". Sozdaet CLAUDE.md, docs/, .gitignore, mise.toml, templates iz bootstrap/templates/.
---

# Project bootstrap skill

## When to invoke

Invoked when operator says:
- "создай новый проект"
- "bootstrap новый репо"
- "начнём новый проект"
- "create new repository"

Or by script `mini-bootstrap-project` (which wraps this skill).

## Hard prerequisites

1. Project name provided.
2. Project type detected or asked: Python / Go / Node / hybrid.
3. Target GitHub owner (default: lenivvenil).
4. Public or private decided.

## The bootstrap interview

### Step 1: Confirm intent

> Создаём новый проект `<name>` под `<owner>` как `<public|private>`. Stack: `<python|go|node|...>`. Верно?

If any field missing, ask.

### Step 2: Create directory structure

\`\`\`
<name>/
├── README.md
├── CLAUDE.md              (from bootstrap/templates/CLAUDE.md.template)
├── .gitignore             (stack-appropriate)
├── mise.toml              (pinned versions)
├── docs/
│   ├── architecture/
│   ├── decisions/
│   │   └── adr-template.md
│   ├── domain/
│   ├── principles.md      (from template, customized)
│   ├── runbooks/
│   └── metrics/
├── .github/
│   ├── workflows/
│   │   └── ci.yml         (stack-appropriate from bootstrap/templates/)
│   ├── pull_request_template.md
│   └── ISSUE_TEMPLATE/
│       ├── feature.md
│       ├── bug.md
│       └── epic.md
└── src/ or cmd/ or similar (per stack)
\`\`\`

### Step 3: Customize CLAUDE.md

Ask operator:
> Есть ли особые договорённости для этого проекта? Принципы, деноминации, специфика?

Insert into CLAUDE.md "Project-specific conventions" section.

### Step 4: Initial ADR

Write `docs/decisions/0001-baseline-state-at-start.md` — fresh baseline-ADR for this project. Reference `docs/principles.md` which was copied from this meta-project.

### Step 5: Create GitHub repo

\`\`\`bash
gh repo create <owner>/<name> --<public|private> --source=. --remote=origin --push
\`\`\`

### Step 6: Create labels (canonical set)

\`\`\`bash
for label in "needs-triage" "type:adr" "type:deferred-review" "type:epic" "type:feature" "type:bug" "type:spike" "P0-critical" "P1-high" "P2-medium" "P3-low" "estimate/1" "estimate/2" "estimate/3" "estimate/5" "estimate/8" "estimate/13" "blocked" "security" "adr-needed"; do
    gh label create "$label" --force 2>/dev/null || true
done
\`\`\`

### Step 7: Create project board

Ask:
> Создать GitHub Projects v2 board с канонической конфигурацией (Icebox/Backlog/Next Up/In Progress/In Review/Done, Iteration field, Estimate field)?

If yes, use `gh project create` + configure fields.

### Step 8: Initial commit

\`\`\`bash
git add .
git commit -m "chore: initial project bootstrap with claude-mini conventions"
git push
\`\`\`

## Output

Project skeleton ready. Report:

> Проект `<name>` создан:
> - Структура: <path>
> - GitHub: <url>
> - Baseline ADR: <path>/docs/decisions/0001-*.md
>
> Следующий шаг: `cd <name> && claude --model sonnet` и первая задача как `/task-to-issue`.

## Hard rules

- Принципы (`docs/principles.md`) копируются как есть — они универсальны. Изменения — через новый ADR в создаваемом проекте.
- `CLAUDE.md` **customize**, но сохраняя ссылки на источники (`@docs/principles.md` и т.п.).
- Baseline ADR (0001) пишется сразу, не откладывается — без него проект не задокументирован.
- CI workflow берётся из `bootstrap/templates/ci-<stack>.yml`, не пишется с нуля.
