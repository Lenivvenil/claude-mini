# Getting Started with claude-mini

claude-mini добавляет в Claude Code набор готовых команд: планирование, ревью, полный цикл задачи — через один вызов в Claude Code.

Вместо того чтобы объяснять Claude что делать с нуля при каждой задаче — запускаешь `/feature 42`, и Claude ведёт по всему процессу: от GitHub issue до PR. Результат каждого шага пишется в файл, поэтому между сессиями ничего не теряется.

Установка — три яруса в этом документе, каждый следующий надстраивается над предыдущим. Документ для оператора, ставящего claude-mini на свою машину и подключающего к своим проектам; для контрибуции в сам claude-mini см. AGENTS.md.

| Ярус | Время | Что получишь | Кому подходит |
|---|---|---|---|
| **[Minimal](#minimal-30-мин)** | ~30 мин | `/plan` + `/review` на тестовом проекте | Первый раз |
| **[Standard](#standard-1-2-ч)** | ~1–2 ч | Всё выше + проверка формата коммитов + MCP | Регулярная работа |
| **[Full / Paranoid mode](#full--paranoid-mode-3-4-ч)** | ~3–4 ч | Всё выше + CI + mutation testing + все агенты | Продакшн-значимые проекты |

**Правило выбора:** первое знакомство → Minimal. Работаешь с проектом регулярно и хочешь автоматическую проверку коммитов / MCP → Standard. Проект идёт в продакшн или содержит важную логику → Full. Всё ещё не ясно → начни с Minimal: 30 минут дадут ответ на практике.

---

## Minimal (~30 мин)

От git clone до первого `/review`. Без проверки формата коммитов, MCP, CI и агентов — это всё в [Standard](#standard-1-2-ч).

### Перед началом

Убедись что инструменты есть:

```bash
claude --version   # Claude Code
gh auth status     # GitHub CLI — должен сказать "Logged in to github.com"
jq --version       # нужен для установщика
```

Нет Claude Code → [claude.ai/code](https://claude.ai/code)
Нет `gh` → `brew install gh`, потом `gh auth login`
Нет `jq` → `brew install jq`

### Шаг 1: Скачать claude-mini

```bash
git clone https://github.com/Lenivvenil/claude-mini.git ~/claude-mini
cd ~/claude-mini
```

### Шаг 2: Установить команды и skills (один раз на машине)

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

### Шаг 3: Подключить команды к твоему проекту

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

### Шаг 4: Создать GitHub репозиторий и тестовый issue

`gh issue create` требует GitHub-репозиторий с remote. Создай его:

```bash
cd ~/my-project
gh repo create my-project --private --source=. --remote=origin
```

Теперь создай тестовый issue:

```bash
gh issue create --title "test: hello onboarding" --body "Тестовый issue для проверки pipeline"
```

Запомни номер — например `#1`.

### Шаг 5: Запустить Claude Code и написать план

```bash
cd ~/my-project
claude
```

Внутри Claude Code напиши:

```
/plan 1
```

Claude создаст `plan.md` — он нужен для следующего шага.

### Шаг 6: Сделать изменение и запустить /review

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

### Хочешь увидеть pipeline изнутри?

Запусти демо-тур — он создаёт изолированный проект, устанавливает pipeline и покажет что делает каждая команда:

```bash
bash ~/claude-mini/bootstrap/scripts/mini-bootstrap-demo.sh
```

Не требует GitHub. Занимает ~40 минут. Артефакты остаются в `~/claude-mini-demo/` для изучения.

---

## Standard (~1-2 ч)

**Предпосылка:** пройден [Minimal](#minimal-30-мин) или ты уже знаком с Claude Code и базовыми командами.

Что добавится:
- Governance hook — Claude Code будет проверять формат коммитов: правильный префикс (`feat:`, `fix:`...) и ссылку на issue (`#42`). Плохой коммит будет заблокирован автоматически.
- MCP-серверы: GitHub (работа с issues и PR прямо из Claude), Serena (навигация по коду), Context7 (актуальная документация библиотек)
- Правильная конфигурация Claude Code settings

### Перед началом

```bash
jq --version       # нужен для настройки settings.json
codex --version    # Codex CLI — второй голос; нужен на шаге /codex-review внутри /feature
```

Нет `jq` → `brew install jq`
Нет `codex` → `npm install -g @openai/codex` (только для личных/OSS проектов; см. CLAUDE.md)

### Шаг 1: Установить universal layer

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

### Шаг 2: Установить pipeline-команды в проект

```bash
./bootstrap/universal-setup.sh --target /path/to/your/project
```

Проверь:
```bash
cat /path/to/your/project/.claude/pipeline-version
# должно совпасть с: cat ~/claude-mini/bootstrap/VERSION
```

### Шаг 3: Установить governance hook

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

### Шаг 4: Подключить MCP-серверы

Скопируй `.mcp.json` в проект:
```bash
cp ~/claude-mini/.mcp.json /path/to/your/project/.mcp.json
```

Перезапусти Claude Code (`/exit` → `claude`) — MCP подключится автоматически.

### Шаг 5: Проверить что всё работает

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

## Full / Paranoid mode (~3-4 ч)

**Предпосылка:** пройден [Standard](#standard-1-2-ч).

**Что получишь сверх Standard:**
- CI workflows: lint (ShellCheck, markdown-links, MCP config check), ADR staleness audit, gate-audit
- Mutation testing (mutmut / Stryker / cargo-mutants — по языку)
- Все 9 агентов активны и настроены
- ADR baseline для нового проекта
- Hardware layer задокументирован (если Mac Mini или аналог)

**Почему это называется "paranoid mode":** каждый коммит и каждый PR проходят максимальный набор автоматических проверок. Ложноположительных срабатываний больше; зато пропущенных дыр — меньше. Оправдано для продакшн-значимых репо.

### Шаг 1: Установить CI workflows

```bash
cd /path/to/your/project
mkdir -p .github/workflows

# Выбери ОДИН шаблон под свой стек:
```

**Python:**
```bash
cp ~/claude-mini/bootstrap/templates/ci-python.yml .github/workflows/ci.yml
```

**Node/TS:**
```bash
cp ~/claude-mini/bootstrap/templates/ci-node.yml .github/workflows/ci.yml
```

**Go:**
```bash
cp ~/claude-mini/bootstrap/templates/ci-go.yml .github/workflows/ci.yml
```

**Mutation testing (все стеки):**
```bash
cp ~/claude-mini/bootstrap/templates/mutation.yml .github/workflows/mutation.yml
```

Отредактируй `ci.yml` и `mutation.yml` под свой проект — в первую очередь `paths:` и версию языка в `ci.yml`, и путь к мутируемым файлам (`src/`) в `mutation.yml`.

### Шаг 2: Создать baseline ADR (опционально, рекомендуется)

ADR-0001 фиксирует текущее состояние проекта как данность перед началом работы. Запуск:

```bash
cd /path/to/your/project
claude
```

Внутри Claude Code используй `/adr` skill — он проведёт через структурированное интервью по шаблону `docs/decisions/adr-template.md` и запишет файл в `docs/decisions/0001-*.md`. Это не одна команда — это диалог: `/adr` задаёт вопросы, ты отвечаешь.

### Шаг 3: Настроить все агенты

Проверить что все 9 агентов установлены:
```bash
ls ~/.claude/agents/
# adr-reviewer.md  adversarial-critic.md  backlog-groomer.md
# docs-reviewer.md  domain-researcher.md  domain-reviewer.md
# reliability-reviewer.md  security-reviewer.md  solutions-architect.md
```

Если каких-то нет:
```bash
cd ~/claude-mini
./bootstrap/universal-setup.sh --install --force
```

### Шаг 4: Документировать hardware layer (опционально)

Если у тебя специфичное железо (headless-станция, нестандартный GPU, ограниченная RAM):

```bash
mkdir -p /path/to/your/project/bootstrap/hardware
# Создай <platform>.md по образцу:
cat ~/claude-mini/bootstrap/hardware/mac-mini-2018.md
```

Документируй: платформа, RAM, особенности PATH, зависимости, команда запуска `universal-setup.sh`.

### Шаг 5: Настроить PR template

```bash
mkdir -p /path/to/your/project/.github
cp ~/claude-mini/bootstrap/templates/pr-template.md \
   /path/to/your/project/.github/pull_request_template.md
```

### Шаг 6: Проверить полный pipeline на тестовом issue

```bash
cd /path/to/your/project
claude
```

```
/feature 1
```

Пройди все 12 шагов чеклиста (включая `/codex-review`, `adversarial-critic`, `security-reviewer` если PR prod-bound).

### Что означает "всё настроено"

- `./bootstrap/universal-setup.sh --check` → нет drift warnings
- CI зелёный на тестовом PR
- governance hook блокирует плохой коммит
- `/feature 1` доходит до "PR готов к human review"

---

## Что дальше

- Структурировать первую неделю: [first-week.md](first-week.md)
- Попробовать полный цикл: `/feature 1` вместо ручного `/plan` + `/review`
- Ежедневный флоу: [`docs/runbooks/daily-session.md`](../runbooks/daily-session.md)
- Новая фича: [`docs/runbooks/feature-pipeline.md`](../runbooks/feature-pipeline.md)
- Что сломалось: [`docs/runbooks/incident-recovery.md`](../runbooks/incident-recovery.md)
- Метрики и ROI: [`docs/metrics/onboarding.md`](../metrics/onboarding.md)
- Еженедельная maintenance: [`docs/runbooks/weekly-maintenance.md`](../runbooks/weekly-maintenance.md)
- Перенос на новую машину: [`docs/runbooks/vendor-migration.md`](../runbooks/vendor-migration.md)

---

## Что-то пошло не так?

**Установщик завершился с ошибкой на Шаге 2 §Minimal**
Проверь: `cat ~/.config/claude-mini/platform.done` должен вывести одну строку.
Также нужен `jq` → `brew install jq`.

**`/plan` не найден внутри Claude Code**
Проверь: `ls ~/my-project/.claude/commands/plan.md`. Если файла нет — повтори Шаг 3 §Minimal.

**`/review` не найден**
Повтори Шаг 2 §Minimal (`--install`).

**`gh issue create` завершился с ошибкой**
Проверь: `gh auth status` — нужен активный логин. Убедись, что Шаг 4 §Minimal (`gh repo create`) выполнен — без remote этот шаг падает.

**`/review` говорит "plan.md not found"**
Сначала нужен `/plan 1` (Шаг 5 §Minimal) — ревью опирается на план.
