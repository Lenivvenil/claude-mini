# Runbook: onboarding existing repo

Как принять уже существующий репо в соглашения claude-mini.

## Предпосылки

- Репо уже существует на GitHub
- У тебя есть write-доступ
- Установлен `claude-mini` universal layer (`./bootstrap/universal-setup.sh --install`)

## Шаги

### 1. Clone и оцени состояние

```bash
cd ~/projects
gh repo clone <owner>/<repo>
cd <repo>
```

После clone — установи pipeline-команды в этот репо (ADR-0018):
```bash
cd ~/projects/claude-mini
./bootstrap/universal-setup.sh --target ~/projects/<repo>
```

Проверь:
- [ ] Есть ли `CLAUDE.md`?
- [ ] Есть ли `docs/decisions/`?
- [ ] Есть ли `docs/principles.md`?
- [ ] Настроены ли GitHub labels?
- [ ] Есть ли PR template?

### 2. Добавить CLAUDE.md

```bash
cp ~/.claude/templates/claude-mini/CLAUDE.md.template CLAUDE.md
# Отредактируй: замени <PROJECT_NAME>, добавь project-specific правила
```

### 3. Добавить principles.md

```bash
mkdir -p docs
cp ~/.claude/templates/claude-mini/principles.md.template docs/principles.md
# Отредактируй section "Project-specific deltas"
```

### 4. Добавить ADR template и baseline

```bash
mkdir -p docs/decisions docs/architecture docs/domain docs/runbooks docs/metrics
cp ~/.claude/templates/claude-mini/adr-template.md docs/decisions/

# Baseline ADR (эквивалент 0001 в claude-mini)
# Объясняет текущее состояние как данность
claude "Создай docs/decisions/0001-baseline-state-at-onboarding.md по шаблону docs/decisions/adr-template.md. Опиши что уже есть в репо (stack, зависимости, архитектурные выборы) как данность, перечисли что считается принятым решением без возможности для легкого пересмотра."
```

### 5. Добавить PR template и issue templates

```bash
mkdir -p .github/ISSUE_TEMPLATE
cp ~/.claude/templates/claude-mini/pr-template.md .github/pull_request_template.md
# Issue templates — из bootstrap/scripts/mini-bootstrap-project.sh, адаптируй
```

### 6. Labels

```bash
for label in "needs-triage" "type:adr" "type:deferred-review" "type:epic" "type:feature" "type:bug" "type:spike" "P0-critical" "P1-high" "P2-medium" "P3-low" "blocked" "security" "adr-needed"; do
    gh label create "$label" --force
done
```

### 7. Projects v2 board

Вручную через UI или:
```bash
gh project create --owner @me --title "<repo> backlog"
# Настройка статусов, iterations, estimate field — через UI
```

### 8. CI workflow (если нет)

```bash
mkdir -p .github/workflows
cp ~/.claude/templates/claude-mini/ci-<stack>.yml .github/workflows/ci.yml
# Отредактируй под структуру проекта
```

### 9. Commit onboarding

```bash
git checkout -b chore/onboarding-claude-mini
git add .
git commit -m "chore: onboard to claude-mini conventions"
gh pr create --title "chore: onboard to claude-mini" \
             --body "Adopts CLAUDE.md, principles, ADR framework, governance."
```

### 10. Merge и настройка protection

После merge:
```bash
# Требовать PR reviews, CI success перед merge в main
gh api -X PUT "repos/{owner}/{repo}/branches/main/protection" \
    --input - <<EOF
{
  "required_pull_request_reviews": {"required_approving_review_count": 1},
  "required_status_checks": {"strict": true, "contexts": ["CI / verify"]},
  "enforce_admins": false,
  "restrictions": null
}
