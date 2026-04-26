# Runbook: Codex CLI auth recovery

## Симптомы

- Каждый `/codex-review` завершается с `SKIPPED: codex CLI hung on startup`
- `deferred-review` issues накапливаются (>1 за сессию)
- `timeout 2 codex --version` виснет (exit 124), но с большим таймаутом в конечном счёте возвращает `codex-cli X.Y.Z`

## Диагностика

```bash
# 1. Проверить auth.json — когда последний refresh?
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('auth_mode'), d.get('last_refresh'))"

# 2. Подтвердить, что startup зависает
timeout 5 codex --version 2>&1; echo "exit=$?"
# Ожидание при сломанном токене: exit=124 (timeout)
# Ожидание при здоровом токене: "codex-cli X.Y.Z", exit=0
```

Если `auth_mode=chatgpt` и `last_refresh` больше недели назад — это и есть причина. Codex CLI пытается обновить токен при каждом старте, запрос зависает на много минут.

## Исправление

```bash
# Шаг 1: удалить протухший токен
rm ~/.codex/auth.json

# Шаг 2: пройти device-auth заново (откроется браузер)
codex login --device-auth
# Войти в ChatGPT Plus, разрешить доступ

# Шаг 3: убедиться, что startup теперь быстрый
timeout 5 codex --version
# Ожидание: "codex-cli X.Y.Z", exit=0 в пределах 2–3 секунд
```

Если `codex login --device-auth` тоже виснет — вероятно, проблема глубже в бинарнике. Попробуй переустановить через npm (как описано в `bootstrap/hardware/mac-mini-2018.md`, шаг 9):

```bash
npm i -g @openai/codex
codex login --device-auth
```

## После восстановления

После подтверждения работоспособности закрой накопившиеся `type:deferred-review` issues:

```bash
# Список открытых deferred-review
gh issue list --label "type:deferred-review" --state open

# Закрыть все разом (подтверди список перед выполнением!)
gh issue list --label "type:deferred-review" --state open --json number --jq '.[].number' \
  | xargs -I{} gh issue close {} --comment "Closed after Codex auth recovery (see issue #42)"
```

## Профилактика

- `mini-preflight.sh` и `mini-health.sh` оба делают `timeout 10 codex login status` — если startup медленный, они покажут warning вместо зависания.
- `review-codex.sh` делает `timeout 10 codex --version` перед каждым review — если токен протух, скрипт упадёт за 10 секунд (не 120), создаст deferred-review issue с инструкцией по починке.
- Если deferred-review issues снова начинают накапливаться — сразу проверь `last_refresh` в `~/.codex/auth.json`.
