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
