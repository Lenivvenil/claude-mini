# Standard: полная установка (~1-2 часа)

**Предпосылка:** пройден [minimal.md](minimal.md) или ты уже знаком с Claude Code и базовыми командами.

Что добавится к minimal:
- Governance hook — Claude Code будет проверять формат коммитов: правильный префикс (`feat:`, `fix:`...) и ссылку на issue (`#42`). Плохой коммит будет заблокирован автоматически.
- MCP-серверы: GitHub (работа с issues и PR прямо из Claude), Serena (навигация по коду), Context7 (актуальная документация библиотек)
- Правильная конфигурация Claude Code settings

---

## Перед началом

```bash
jq --version       # нужен для настройки settings.json
codex --version    # Codex CLI — второй голос; нужен на шаге /codex-review внутри /feature
```

Нет `jq` → `brew install jq`  
Нет `codex` → `npm install -g @openai/codex` (только для личных/OSS проектов; см. CLAUDE.md)

---

## Шаг 1: Установить universal layer

```bash
cd ~/claude-mini
./bootstrap/universal-setup.sh --check   # посмотреть что будет сделано
./bootstrap/universal-setup.sh --install
```

Что делает `--install`:
- Копирует агентов, skills, commands в `~/.claude/`
- Прописывает hooks в `~/.claude/settings.json`
- Создаёт ярлыки `~/bin/mini-*` для session-скриптов

Если после установки что-то выглядит не так — добавь `--force` и запусти снова.

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

Этот шаг подключает автоматическую проверку коммитов в конкретный проект:

```bash
cd /path/to/your/project
~/claude-mini/bootstrap/universal-setup.sh --hook-this-repo
```

Проверь что hook работает — попробуй плохой и хороший коммит-сообщения:

```bash
echo "bad message without prefix" | bash .git/hooks/commit-msg /dev/stdin
# заблокирует: Exit code 1

echo "feat: add feature #1" | bash .git/hooks/commit-msg /dev/stdin
# пропустит: Exit code 0
```

---

## Шаг 4: Подключить MCP-серверы

Скопируй `.mcp.json` в проект:
```bash
cp ~/claude-mini/.mcp.json /path/to/your/project/.mcp.json
```

Перезапусти Claude Code (`/exit` → `claude`) — MCP подключится автоматически.

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

Ожидаемый результат: чеклист из 12 шагов. Переход issue в «In Progress» срабатывает только для issues на доске проекта claude-mini (upstream); в твоём проекте команда тихо пропустит этот шаг.

---

## Что идёт дальше

- Попробовать полный pipeline с реальной задачей
- Подключить CI workflows → [full.md](full.md)
- Посмотреть метрики → [`docs/metrics/onboarding.md`](../metrics/onboarding.md)
