# Runbook: ежедневная сессия

## Когда

Каждое утро перед началом работы.

## Шаги

```bash
# 1. SSH на mini (если работаешь с macbook)
ssh mini

# 2. Войти в tmux
tmux attach -t main

# 3. Preflight-check
mini-preflight
```

Preflight выдаст зелёный статус по: Keychain, SOPS_AGE_KEY_FILE, gh auth, codex auth, Claude Code env vars, Tailscale. Если есть красные/жёлтые — разбираемся до начала.

```bash
# 4. Переход в проект и старт сессии
mini-session <project-name>
```

Это: `cd ~/projects/<name>`, активация mise для pinned runtime, переименование tmux window, `exec claude --model sonnet`.

## Внутри Claude

1. Если есть GitHub issue для текущей задачи:
   ```
   /issue-to-task <N>
   ```
2. Если нет:
   ```
   /task-to-issue <short-title>
   ```
3. Дальше по pipeline — см. `feature-pipeline.md`.

## Завершение дня

```bash
# Внутри Claude
/project-health
```

Сгенерирует недельный отчёт (если ещё не был).

Вне Claude:
```bash
git status         # не забыл ли unstaged
gh pr list --author @me
```

Если в tmux — просто detach (`Ctrl-b d`). Сессия, Claude context, Plex, Transmission продолжают работать на mini.
