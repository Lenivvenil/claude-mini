#!/usr/bin/env bash
# mini-bootstrap-project <name> [--public|--private] [--stack python|go|node]
#
# Создаёт скелет нового проекта с соглашениями claude-mini:
# README, CLAUDE.md, docs/{architecture,decisions,domain,runbooks,metrics},
# principles.md, adr-template, .gitignore, mise.toml, CI workflow, PR template,
# issue templates, labels, GitHub repo.
#
# После завершения напоминает запустить claude-mini/bootstrap для agents/skills/commands.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/projects}"
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/.claude/templates/claude-mini}"

# --- Parse args ---

if [ $# -lt 1 ]; then
    cat <<USAGE
Usage: mini-bootstrap-project <name> [options]
Options:
  --public             Создать public repo (default: private)
  --stack <type>       python|go|node|bare (default: bare)
  --owner <owner>      GitHub owner (default: lenivvenil)
USAGE
    exit 1
fi

NAME="$1"; shift
VISIBILITY="private"
STACK="bare"
OWNER="lenivvenil"

while [ $# -gt 0 ]; do
    case "$1" in
        --public) VISIBILITY="public"; shift ;;
        --private) VISIBILITY="private"; shift ;;
        --stack) STACK="$2"; shift 2 ;;
        --owner) OWNER="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

TARGET="$PROJECT_ROOT/$NAME"

if [ -e "$TARGET" ]; then
    echo "Target already exists: $TARGET" >&2
    exit 1
fi

echo "=== Bootstrapping project: $NAME ==="
echo "Location: $TARGET"
echo "Visibility: $VISIBILITY"
echo "Stack: $STACK"
echo "Owner: $OWNER"
echo ""

# --- Create structure ---

mkdir -p "$TARGET"/{docs/{architecture,decisions,domain,runbooks,metrics},.github/{workflows,ISSUE_TEMPLATE}}

cd "$TARGET"

# --- README ---

cat > README.md <<EOF
# $NAME

> Short one-line description.

## Status

Bootstrap from \`claude-mini\` conventions. See \`CLAUDE.md\` and \`docs/principles.md\` for workflow.

## Quickstart

\`\`\`bash
mise install  # установит нужные runtime
# ... stack-specific setup
\`\`\`

## Development

См. \`docs/runbooks/\` для пошаговых сценариев.
EOF

# --- CLAUDE.md ---

cp "$TEMPLATES_DIR/CLAUDE.md.template" CLAUDE.md 2>/dev/null || cat > CLAUDE.md <<'EOF'
# Project conventions — <name>

Наследует соглашения `claude-mini`: pipeline `/plan → /adr? → /implement → /review → /codex-review`, read-only critic agents, governance hook на commits, Definition of Done из `docs/principles.md`.

## Source of truth

- Backlog: GitHub Issues + Projects v2 этого репо
- Architecture decisions: `docs/decisions/` (MADR 4.0)
- Domain: `docs/domain/`
- Principles: `docs/principles.md`

## Project-specific conventions

<!-- Добавь сюда что уникально для этого проекта -->
EOF

# --- principles.md (ссылка на мастер) ---

cat > docs/principles.md <<'EOF'
# Principles

Этот проект наследует четыре директивы из `claude-mini`:

1. Красные флаги вместо трейдоффов
2. Claude — душный напарник, не эксперт
3. Автоматизировать только низкорискованное
4. Knowledge в инструментах, не в памяти

Детали и Definition of Done — см. полный документ в `claude-mini` репо: `docs/principles.md`.

## Project-specific deltas

<!-- Ниже — отличия от мастер-документа, если есть. Пустой список = полное наследование. -->

- (нет отличий)
EOF

# --- ADR template ---

cp "$TEMPLATES_DIR/adr-template.md" docs/decisions/adr-template.md 2>/dev/null || \
    touch docs/decisions/.keep

# --- Stack-specific .gitignore ---

case "$STACK" in
    python)
        cat > .gitignore <<'EOF'
__pycache__/
*.py[cod]
.venv/
venv/
env/
.env
.env.*
!.env.sops.json
*.egg-info/
dist/
build/
.pytest_cache/
.coverage
.mypy_cache/
.ruff_cache/
.python-version
EOF
        ;;
    go)
        cat > .gitignore <<'EOF'
bin/
*.test
*.out
*.prof
coverage.txt
vendor/
.env
.env.*
!.env.sops.json
EOF
        ;;
    node)
        cat > .gitignore <<'EOF'
node_modules/
dist/
build/
.next/
.cache/
*.log
.env
.env.*
!.env.sops.json
coverage/
EOF
        ;;
    *)
        cat > .gitignore <<'EOF'
.DS_Store
.env
.env.*
!.env.sops.json
*.log
EOF
        ;;
esac

# --- mise.toml ---

case "$STACK" in
    python) cat > mise.toml <<'EOF'
[tools]
python = "3.13"
uv = "latest"
EOF
        ;;
    go) cat > mise.toml <<'EOF'
[tools]
go = "1.24"
EOF
        ;;
    node) cat > mise.toml <<'EOF'
[tools]
node = "22"
EOF
        ;;
    *) cat > mise.toml <<'EOF'
[tools]
# Add runtimes as needed
EOF
        ;;
esac

# --- CI workflow ---

CI_TEMPLATE="$TEMPLATES_DIR/ci-$STACK.yml"
if [ -f "$CI_TEMPLATE" ]; then
    cp "$CI_TEMPLATE" .github/workflows/ci.yml
else
    # Fallback bare CI
    cat > .github/workflows/ci.yml <<'EOF'
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: No-op
        run: echo "CI not yet configured for this stack"
EOF
fi

# --- PR template ---

cp "$TEMPLATES_DIR/pr-template.md" .github/pull_request_template.md 2>/dev/null || \
    cat > .github/pull_request_template.md <<'EOF'
## What & Why

Closes #

<!-- Implements docs/decisions/NNNN-*.md (если был ADR) -->

## Definition of Done
- [ ] ADR merged (если архитектурно значимо)
- [ ] Domain docs обновлены (если граница BC изменилась)
- [ ] Тесты: unit / integration / coverage ≥ floor
- [ ] /review прошёл
- [ ] /codex-review прошёл (или deferred-review issue открыт)
- [ ] Разногласия между ревьюерами разрешены
- [ ] Security scans clean
- [ ] Docs обновлены (README / runbook / CHANGELOG если релиз)
- [ ] CI зелёный
- [ ] Conventional Commit + issue-ref
EOF

# --- Issue templates ---

cat > .github/ISSUE_TEMPLATE/feature.md <<'EOF'
---
name: Feature
about: Новая функциональность
labels: type:feature, needs-triage
---

## Context

## Acceptance criteria
- [ ]

## References
EOF

cat > .github/ISSUE_TEMPLATE/bug.md <<'EOF'
---
name: Bug
about: Ошибка в существующей функциональности
labels: type:bug, needs-triage
---

## Что сломано

## Шаги воспроизведения

## Ожидаемое поведение

## Фактическое поведение

## Environment
EOF

cat > .github/ISSUE_TEMPLATE/epic.md <<'EOF'
---
name: Epic
about: Крупная инициатива с sub-issues
labels: type:epic, needs-triage
---

## Цель

## Scope (in)

## Scope (out)

## Sub-issues
- [ ] #

## Success metric
EOF

# --- Initial ADR (baseline) ---

cat > docs/decisions/0001-baseline-state-at-start.md <<EOF
# 0001. Baseline state at project start

* Status: accepted
* Date: $(date +%Y-%m-%d)
* Deciders: venil
* Tags: bootstrap, baseline

## Context and Problem Statement

Проект \`$NAME\` создан через \`mini-bootstrap-project\` с соглашениями из \`claude-mini\`. Этот ADR фиксирует baseline как отправную точку для будущих решений.

## Decision Drivers

* Проектные ADR требуют точки отсчёта (см. \`claude-mini/docs/decisions/0001-*\`).
* Новый проект начинается со соглашениями, а не с пустоты.

## Considered Options

* Option A: Без baseline ADR — начать писать ADR только когда появится первое решение.
* Option B: Импортировать все ADR из claude-mini.
* Option C: Baseline-ADR, ссылающийся на claude-mini как источник соглашений.

## Decision Outcome

**Chosen: Option C.** Проект наследует соглашения \`claude-mini\` по ссылке. Новые ADR пишутся при появлении решений, специфичных для этого проекта. Те ADR из claude-mini, которые здесь не применяются, отмечаются в отдельном ADR (например, "мы не используем Codex для этого проекта").

### Positive Consequences
* Точка отсчёта для будущих решений.
* Новый оператор видит наследование соглашений.

### Negative Consequences
* Привязка к claude-mini как внешнему источнику — при его эволюции этот проект может отстать.

## Confirmation

\`docs/principles.md\` существует и ссылается на claude-mini. \`CLAUDE.md\` присутствует.

## Re-visit Trigger

* Проект перестаёт применять соглашения claude-mini → нужен отдельный decision.
* claude-mini deprecated / заменён — нужен migration plan.

## Links

* Meta-project: https://github.com/lenivvenil/claude-mini
EOF

# --- Git init & first commit ---

git init -q -b main
git add .
git commit -q -m "chore: initial project bootstrap from claude-mini conventions" \
    -m "Bootstrapped via mini-bootstrap-project with stack=$STACK."

# --- GitHub repo create ---

if command -v gh >/dev/null 2>&1; then
    echo ""
    echo "Creating GitHub repo $OWNER/$NAME ($VISIBILITY)..."
    if gh repo create "$OWNER/$NAME" --"$VISIBILITY" --source=. --remote=origin --push 2>/dev/null; then
        echo "✓ Repo created and pushed"

        # Labels
        echo "Creating canonical labels..."
        for label in "needs-triage" "type:adr" "type:deferred-review" "type:epic" "type:feature" "type:bug" "type:spike" "P0-critical" "P1-high" "P2-medium" "P3-low" "estimate/1" "estimate/2" "estimate/3" "estimate/5" "estimate/8" "estimate/13" "blocked" "security" "adr-needed"; do
            gh label create "$label" --force >/dev/null 2>&1 || true
        done
        echo "✓ Labels created"
    else
        echo "! gh repo create failed — сделай вручную: gh repo create $OWNER/$NAME --$VISIBILITY --source=. --remote=origin --push"
    fi
else
    echo "! gh CLI не найдена — создай repo и push вручную"
fi

# --- Done ---

echo ""
echo "=== Готово ==="
echo ""
echo "Проект: $TARGET"
if command -v gh >/dev/null 2>&1 && [ -n "${OWNER:-}" ]; then
    echo "GitHub: https://github.com/$OWNER/$NAME"
fi
echo ""
echo "Следующие шаги:"
echo "  cd $TARGET"
echo "  mise install"
echo "  claude --model sonnet"
echo ""
echo "Внутри Claude: начать с /task-to-issue для первой задачи."
