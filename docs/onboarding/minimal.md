# Minimal: от git clone до первого /review (~30 минут)

Для тех, кто хочет попробовать claude-mini прежде чем разбираться со всеми настройками. Установим команды, создадим тестовый issue и запустим ревью на реальном изменении.

Что здесь **не** будет: проверка формата коммитов, MCP-серверы, CI, агенты. Это всё — в [standard.md](standard.md).

---

## Перед началом

Убедись что инструменты есть:

```bash
claude --version   # Claude Code
gh auth status     # GitHub CLI — должен сказать "Logged in to github.com"
```

Нет Claude Code → [claude.ai/code](https://claude.ai/code)  
Нет `gh` → `brew install gh`, потом `gh auth login`

---

## Шаг 1: Скачать claude-mini

```bash
git clone https://github.com/Lenivvenil/claude-mini.git ~/claude-mini
cd ~/claude-mini
```

---

## Шаг 2: Установить команды и skills (один раз на машине)

Сначала скажи установщику что с железом всё в порядке (без этого он ожидает отдельной hardware-настройки):

```bash
mkdir -p ~/.config/claude-mini
echo "generic-$(date +%Y-%m-%d)" > ~/.config/claude-mini/platform.done
```

Запусти установку:

```bash
./bootstrap/universal-setup.sh --install
```

Ты увидишь строки с галочками — команды, skills и агенты копируются в `~/.claude/`. Если появится сообщение про `drift` — добавь `--force` к команде и запусти снова.

Нужен `jq`? → `brew install jq`

---

## Шаг 3: Подключить команды к твоему проекту

Каждый проект подключается отдельно. Если тестового проекта ещё нет:

```bash
mkdir ~/my-project && cd ~/my-project && git init && cd ~/claude-mini
```

Подключи claude-mini к проекту:

```bash
./bootstrap/universal-setup.sh --target ~/my-project
```

Проверь что всё на месте:

```bash
ls ~/my-project/.claude/commands/
# увидишь: plan.md  implement.md  feature.md  ...
```

---

## Шаг 4: Создать тестовый issue

```bash
cd ~/my-project
gh issue create --title "test: hello onboarding" --body "Тестовый issue для проверки pipeline"
```

Запомни номер — например `#1`.

---

## Шаг 5: Запустить Claude Code и написать план

```bash
cd ~/my-project
claude
```

Внутри Claude Code напиши:

```
/plan 1
```

Claude создаст `plan.md` — он нужен для следующего шага.

---

## Шаг 6: Сделать изменение и запустить /review

В соседнем терминале (не в Claude Code):

```bash
echo "# Hello claude-mini" >> README.md
git add README.md
```

Вернись в Claude Code:

```
/review
```

Claude проверит staged изменение и напишет ревью. Если в конце написано `APPROVE` — ты прошёл minimal tier.

---

## Готово. Что дальше

- Попробовать полный цикл: `/feature 1` вместо ручного `/plan` + `/review`
- Добавить проверку коммитов и MCP → [standard.md](standard.md)

---

## Что-то пошло не так?

**Установщик завершился с ошибкой на шаге 2**  
Проверь: `cat ~/.config/claude-mini/platform.done` должен вывести одну строку.  
Также нужен `jq` → `brew install jq`.

**`/plan` не найден внутри Claude Code**  
Проверь: `ls ~/my-project/.claude/commands/plan.md`. Если файла нет — повтори шаг 3.

**`/review` не найден**  
Повтори шаг 2 (`--install`).

**`gh issue create` завершился с ошибкой про label**  
Убери `--label "needs-triage"` из команды — label может отсутствовать в репозитории.

**`/review` говорит "plan.md not found"**  
Сначала нужен `/plan 1` (шаг 5) — ревью опирается на план.
