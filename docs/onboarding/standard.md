# Standard: полная установка (~1-2 часа)

**Предпосылка:** пройден [minimal.md](minimal.md) или ты уже знаком с Claude Code и базовыми командами.

**Что получишь сверх minimal:**
- Governance hook — блокирует коммиты без Conventional Commits prefix + issue-ref
- MCP-серверы: GitHub (issues/PR), Serena (навигация по коду), Context7 (актуальная документация)
- Claude Code settings с правильными permission allowlist
- Полный set агентов-критиков (`docs-reviewer`, `adversarial-critic`, `security-reviewer` и др.)

---

## Предпосылки

```bash
jq --version       # нужен для патча settings.json
codex --version    # Codex CLI (второй голос в /review)
```

Если `jq` не найден → `brew install jq`
Если `codex` не найден → `npm install -g @openai/codex`

---

## Шаг 1: Установить universal layer

```bash
cd ~/claude-mini
./bootstrap/universal-setup.sh --check   # посмотреть что будет
./bootstrap/universal-setup.sh --install
```

Что делает `--install`:
- Копирует агентов, skills, commands в `~/.claude/`
- Патчит `~/.claude/settings.json` (PreToolUse/PostToolUse hooks через абсолютные пути)
- Создаёт `~/bin/mini-*` symlinks на session-скрипты

Exit codes:
- **exit 0** — успех (в т.ч. «уже установлено»)
- **exit 1** — hardware layer не готов → создай `~/.config/claude-mini/platform.done` (см. `minimal.md` шаг 2)
- **exit 2** — отсутствуют зависимости (`jq`, `gh`, `claude`) → установи
- **exit 3** — ошибка копирования или jq-патча → проверь права и место на диске
- **exit 4** — drift (файлы отличаются от источника) → добавь `--force`

---

## Шаг 2: Установить pipeline-команды в проект

```bash
./bootstrap/universal-setup.sh --target /path/to/your/project
```

Проверь:
```bash
cat /path/to/your/project/.claude/pipeline-version
# должно совпасть с: cat ~/claude-mini/bootstrap/VERSION
```

---

## Шаг 3: Установить governance hook

```bash
# Запускать из директории целевого проекта:
cd /path/to/your/project
~/claude-mini/bootstrap/universal-setup.sh --hook-this-repo
# или вручную (использует staged-копию из --install, не source):
cp ~/.claude/git-hooks/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

Проверка:
```bash
echo "bad message without prefix" | bash /path/to/your/project/.git/hooks/commit-msg /dev/stdin
# exit 1 — заблокировано

echo "feat: add feature #1" | bash /path/to/your/project/.git/hooks/commit-msg /dev/stdin
# exit 0 — пропущено
```

---

## Шаг 4: Подключить MCP-серверы

Скопируй `.mcp.json` из claude-mini в свой проект:
```bash
cp ~/claude-mini/.mcp.json /path/to/your/project/.mcp.json
```

Или подключи только GitHub MCP (минимальный вариант):
```bash
gh auth token   # скопируй токен
```

Затем в Claude Code: перезапусти (`/exit` → `claude`) — MCP подключится автоматически.

---

## Шаг 5: Проверить что всё работает

```bash
cd /path/to/your/project
claude
```

Внутри Claude Code:
```
/feature 1
```

Ожидаемый результат: чеклист pipeline с 12 шагами, issue переходит в "In Progress".

---

## Что идёт дальше

- Попробовать полный pipeline с реальной задачей
- Подключить CI workflows → [full.md](full.md)
- Посмотреть метрики → [`docs/metrics/onboarding.md`](../../metrics/onboarding.md)
