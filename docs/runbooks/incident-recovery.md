# Runbook: что-то сломалось

## Категории проблем

### Claude Code не отвечает / зависает

1. `claude --version` — запускается ли CLI
2. `claude auth status`
3. Новая сессия: `exec claude --model sonnet`
4. Если повторяется — проверь `~/.claude/settings.json`:
   ```bash
   jq . ~/.claude/settings.json
   ```
   Невалидный JSON → откат из бэкапа (`universal-setup.sh` делает backup перед патчем).

### Governance hook блокирует всё

**Симптомы:** каждый `git commit` падает с deny, даже корректные сообщения.

**Диагностика:**
```bash
echo '{"tool_input":{"command":"git commit -m \"feat: test (#1)\""},"cwd":"'"$PWD"'"}' \
    | ~/.claude/hooks/pre-commit-governance.sh
echo "exit=$?"
# Ожидание: exit=0 для валидного сообщения
```

**Возможные причины:**
1. `jq` не установлен → hook падает
2. Путь в `settings.json` с тильдой `~` вместо абсолютного — hook не вызывается молча, но если это не тот случай:
3. В `settings.json` есть другой PreToolUse hook, который deny'ит

**Временный bypass:**
```bash
jq 'del(.hooks.PreToolUse[] | select(.matcher == "Bash"))' \
    ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json

# commit
git commit -m "..."

# восстановить
cd ~/projects/claude-mini && ./bootstrap/universal-setup.sh --install
# Если exit 4: diff выше покажет что отличается.
# Запусти с --force чтобы перезаписать, или восстанови файлы вручную перед re-run.
#   ./bootstrap/universal-setup.sh --install --force
```

### Governance hook молчит (пропускает всё)

**Симптомы:** плохие коммиты (без CC prefix, без issue-ref) проходят без ошибки — Claude коммитит что угодно.

**Отличие от "hook blocks everything":** там hook активен, но слишком строгий. Здесь hook вообще не вызывается.

**Быстрая диагностика:**
```bash
# Проверяет hook binary напрямую — минуя settings.json и Claude Code
bash ~/.claude/scripts/test-governance-hook.sh
# Ожидание: All tests passed.
# Если failed → hook binary сломан (см. ниже).
# Если passed → hook binary рабочий, но Claude Code его не вызывает (см. tilde path).
```

**Причина 1: Tilde path в settings.json (самая частая)**
```bash
jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.type == "command") | .command' \
    ~/.claude/settings.json
# Если видишь "~/.claude/hooks/..." вместо "/Users/venil/.claude/hooks/..."
# → Claude Code передаёт command в exec без shell expansion, тильда остаётся literal
```

Исправление:
```bash
# Пересмотри hook path в settings.json — должен быть абсолютным
# Или переустанови:
cd ~/projects/claude-mini && ./bootstrap/universal-setup.sh --install
```

**Причина 2: Hook не выставлен исполняемым**
```bash
ls -la ~/.claude/hooks/pre-commit-governance.sh
# Должен быть -rwxr-xr-x
chmod +x ~/.claude/hooks/pre-commit-governance.sh
```

**Причина 3: jq не установлен**
```bash
which jq || echo "NOT FOUND"
# Без jq hook падает молча: input не парсится, command пуст, hook пропускает всё
brew install jq   # macOS
```

**Причина 4: PreToolUse hook не прописан в settings.json вообще**
```bash
jq '.hooks.PreToolUse' ~/.claude/settings.json
# Должен быть непустым массивом с matcher: "Bash"
# Если null → переустанови: ./bootstrap/universal-setup.sh --install
```

**Важно:** `test-governance-hook.sh` тестирует hook binary напрямую. Он не может обнаружить tilde-path проблему (hook вызывается, значит binary рабочий). Если тест прошёл, но плохие коммиты всё равно проходят через Claude — проблема в settings.json, не в hook.

### Format Check Hook не выдаёт предупреждений

**Симптомы:** Claude пишет файлы с lint-ошибками или форматированием, но предупреждение в `additionalContext` не появляется.

**Быстрая диагностика:**
```bash
# Проверить что hook прописан в settings.json
jq '.hooks.PostToolUse[]? | select(.matcher == "Edit|MultiEdit|Write")' ~/.claude/settings.json

# Прогнать тест напрямую
bash ~/.claude/scripts/test-posttooluse-hook.sh
# Ожидание: === Results: N passed, 0 failed, N skipped ===
# (skipped — это нормально: ruff/prettier/gofmt не установлены)

# Проверить лог последнего запуска
tail -20 ~/.claude/hooks/posttooluse.log
```

**Причина 1: Hook не прописан в settings.json**
```bash
# Переустановить:
cd ~/projects/claude-mini && ./bootstrap/universal-setup.sh --install
```

**Причина 2: Инструмент не установлен (ruff / prettier / gofmt)**
```bash
# Python: pip install ruff  или  brew install ruff
# JS/TS:  npm install -g prettier eslint
# Go:     входит в стандартный дистрибутив Go
```
Hook деградирует gracefully (exit 0, запись в лог вида `SKIP ruff not found: /path/to/file.py`). Инструмент не обязателен — но без него hook молчит.

**Причина 3: Tilde-path в settings.json**


Та же проблема что у Governance Hook. Hook должен иметь абсолютный путь (`/Users/…`, не `~/…`). Переустанови через `./bootstrap/universal-setup.sh --install`.

**Примечание по доверию:** ESLint загружает плагины и конфигурации из `node_modules` текущего репозитория. При работе с незнакомым репозиторием hook выполняет произвольный JavaScript из его `eslintrc`. Если репозиторий не доверенный — отключи hook до завершения работы: удали запись `PostToolUse` из `~/.claude/settings.json`, затем восстанови через `./bootstrap/universal-setup.sh --install`.

### MCP server не отвечает

**Симптомы:** `@mcp__github__...` fails, Serena не индексирует.

**Диагностика:** в Claude Code — `/mcp` выведет список серверов со статусом.

**Recovery:**
1. Serena: `uvx serena --version` — если не стартует, `uvx --reinstall serena`
2. GitHub MCP: проверь PAT в Keychain: `security find-generic-password -s gh_mcp -w`
3. Context7: проверь URL в settings.json

### Codex `/codex-review` постоянно SKIPPED

**Причины:**
1. ChatGPT Plus квота исчерпана (10-25 reviews/week)
2. Plus OAuth flake для newer model
3. Сеть

**Проверка:**
```bash
codex login status
codex exec --model gpt-5.2 "say hello"
```

**Если flake стабильный:** временно изменить pinned model в `~/.codex/config.toml` на `gpt-4.1`.

### `/adr` не создаёт файл

**Причина:** `~/.claude/skills/adr-author/scripts/next_adr_number.sh` не executable или путь неверен.

```bash
ls -la ~/.claude/skills/adr-author/scripts/
chmod +x ~/.claude/skills/adr-author/scripts/next_adr_number.sh
```

### LaunchAgent не стартует после reboot (macOS)

```bash
launchctl list | grep local.
# Пусто — агенты не загрузились
launchctl load ~/Library/LaunchAgents/local.tmux-main.plist
```

### SSH с macbook → mini падает

```bash
# С другой машины (не с mini)
tailscale status
# Mini должен быть в списке peers

# Если нет — на самом mini с физическим доступом:
sudo tailscale up --force-reauth
```

### macOS upgrade через SSH зависает

**Известная проблема.** GUI-диалоги (Transmission «Donate», Zoom update) блокируют reboot.

**Подготовка:**
```bash
osascript -e 'tell application "Transmission" to quit'
osascript -e 'tell application "Zoom" to quit'
# и другие GUI apps

# Держи второй SSH window открытым на случай отвала первого
```

## Rollback universal-setup

Если universal-setup сломал окружение:

```bash
# Бэкап settings.json
ls ~/.claude/settings.json.bak* 2>/dev/null

# Бэкап zshrc
ls ~/.zshrc.bak* 2>/dev/null

# Ручное восстановление
cp ~/.claude/settings.json.bak ~/.claude/settings.json
source ~/.zshrc
```

Если бэкапа нет — откат к предыдущему коммиту `claude-mini`:
```bash
cd ~/projects/claude-mini
git log --oneline -10
git checkout <commit-before-incident>
./bootstrap/universal-setup.sh --install --force
```

**Примечание (ADR-0018):** `--install` не устанавливает slash-команды в `~/.claude/commands/`. Если команды недоступны в проекте, запусти из claude-mini:
```bash
./bootstrap/universal-setup.sh --target <path-to-repo>
# Команды будут установлены в <path-to-repo>/.claude/commands/
```

## Эскалация

Если проблема воспроизводима и блокирующая:

1. Собери diagnostic bundle:
   ```bash
   mkdir /tmp/claude-diag
   claude --version > /tmp/claude-diag/version.txt
   # redact секреты перед отправкой!
   jq 'del(.mcpServers[].env[]?)' ~/.claude/settings.json > /tmp/claude-diag/settings.json.redacted
   mini-health > /tmp/claude-diag/health.txt 2>&1
   ```
2. Открой issue в claude-mini с `type:bug`
3. Если специфично для Claude Code — https://github.com/anthropics/claude-code/issues

---

## Project board sync — issue не попал на доску

### Симптомы
- Новый issue открыт, но отсутствует на project board
- Workflow `project-board-sync` показывает красный статус в Actions

### Причины и действия

**1. Секрет `ADD_TO_PROJECT_TOKEN` не настроен**
- Workflow имеет `if: secrets.ADD_TO_PROJECT_TOKEN != ''` — молча пропустит
- Добавить PAT: repo Settings → Secrets → Actions → `ADD_TO_PROJECT_TOKEN` (scope: `project`)

**2. PAT истёк или не имеет `project` scope**
- Проверить: `GH_TOKEN=<pat> gh project item-list 5 --owner Lenivvenil --limit 1`
- Пересоздать PAT: github.com/settings/tokens → Classic → project ✓

**3. Добавить пропущенный issue вручную**
```bash
gh project item-add 5 --owner Lenivvenil --url https://github.com/Lenivvenil/claude-mini/issues/<N>
```

**4. Backfill всех пропущенных issues**
```bash
gh issue list --state open --json number,url --limit 100 | \
  jq -r '.[].url' | \
  while read url; do
    gh project item-add 5 --owner Lenivvenil --url "$url" 2>/dev/null && echo "✓ $url" || echo "⚠ $url"
  done
```
