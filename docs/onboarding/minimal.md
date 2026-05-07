# Minimal: от git clone до первого /review (~30 минут)

**Что получишь:** `/plan`, `/review` и остальные pipeline-команды + skills глобально. Один тестовый прогон review на staged diff.

**Что НЕ входит в minimal:** governance hook, MCP-серверы, CI, агенты. Всё это — в [standard.md](standard.md).

---

## Предпосылки

```bash
claude --version   # Claude Code установлен
git --version      # ≥ 2.39
gh --version       # GitHub CLI установлен
gh auth status     # Logged in to github.com
```

Если `claude` не найден → [claude.ai/code](https://claude.ai/code)
Если `gh` не найден → `brew install gh` (macOS) или [cli.github.com](https://cli.github.com)

---

## Шаг 1: Клонировать claude-mini

```bash
git clone https://github.com/Lenivvenil/claude-mini.git ~/claude-mini
cd ~/claude-mini
```

---

## Шаг 2: Установить universal layer (глобально, один раз)

```bash
# Создать platform flag (обходит hardware layer check для не-Mac Mini машин):
mkdir -p ~/.config/claude-mini
echo "generic-$(date +%Y-%m-%d)" > ~/.config/claude-mini/platform.done

# Установить skills, agents, hooks глобально:
./bootstrap/universal-setup.sh --install
```

Ожидаемый результат: серия `✓ ...` строк, exit 0.
Если exit 4 → `./bootstrap/universal-setup.sh --install --force` (overwrite drift).

---

## Шаг 3: Установить pipeline-команды в твой проект

```bash
# Если проекта ещё нет:
mkdir ~/my-project && cd ~/my-project && git init && cd ~/claude-mini

# Установить команды в проект:
./bootstrap/universal-setup.sh --target ~/my-project
```

Проверь:
```bash
ls ~/my-project/.claude/commands/
# plan.md  implement.md  feature.md  ...
```

---

## Шаг 4: Создать тестовый issue

```bash
cd ~/my-project
gh issue create \
  --title "test: hello onboarding" \
  --body "Тестовый issue для проверки pipeline" \
  --label "needs-triage" 2>/dev/null \
  || gh issue create --title "test: hello onboarding" --body "Тестовый issue"
```

Запомни номер (например `#1`).

---

## Шаг 5: Открыть Claude Code и запустить /plan

```bash
cd ~/my-project
claude
```

Внутри Claude Code:

```
/plan 1
```

Результат: `plan.md` в корне проекта (6 разделов).

---

## Шаг 6: Сделать изменение и запустить /review

```bash
# В терминале (вне Claude Code):
echo "# Hello claude-mini" >> README.md
git add README.md
```

Вернись в Claude Code:

```
/review
```

Ожидаемый результат: Layer 1 (детерминированные проверки) + Layer 2 (LLM review) без BLOCK-findings.

---

## Готово

Ты прошёл minimal tier. Что дальше:

- Попробовать полный цикл: `/feature 1` вместо ручного `/plan` + `/review`
- Добавить governance hook и MCP → [standard.md](standard.md)

---

## Troubleshooting

**`./bootstrap/universal-setup.sh: exit 1` на шаге 2**
Проверь что `platform.done` создан:
```bash
cat ~/.config/claude-mini/platform.done   # должен вывести строку
```
Если файл есть но exit 1 — проверь `jq --version` (нужен для settings.json patch).

**`/plan: command not found` внутри Claude Code**
Pipeline не установлен в проект. Проверь `ls ~/my-project/.claude/commands/plan.md`.
Если нет — перезапусти шаг 3.

**`/review: unknown command`**
Skills не установлены. Перезапусти шаг 2 (`--install`).

**`gh issue create` требует label `needs-triage`, которого нет**
Убери `--label "needs-triage"` — достаточно заголовка.

**`/review` говорит "plan.md not found"**
Сначала запусти `/plan <issue-num>` (шаг 5).
