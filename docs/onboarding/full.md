# Paranoid mode: полный стек (~3-4 часа)

**Предпосылка:** пройден [standard.md](standard.md).

**Что получишь сверх standard:**
- CI workflows: lint (ShellCheck, markdown-links, MCP config check), ADR staleness audit, gate-audit
- Mutation testing (mutmut / Stryker / cargo-mutants — по языку)
- Все 9 агентов активны и настроены
- ADR baseline для нового проекта
- Hardware layer задокументирован (если Mac Mini или аналог)

**Почему это называется "paranoid mode":** каждый коммит и каждый PR проходят максимальный набор автоматических проверок. Ложноположительных срабатываний больше; зато пропущенных дыр — меньше. Оправдано для продакшн-значимых репо.

---

## Шаг 1: Установить CI workflows

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

Отредактируй `ci.yml` и `mutation.yml` под свой проект (пути, переменные).

---

## Шаг 2: Создать baseline ADR (опционально, рекомендуется)

ADR-0001 фиксирует текущее состояние проекта как данность перед началом работы. Запуск:

```bash
cd /path/to/your/project
claude
```

Внутри Claude Code используй `/adr` skill — он проведёт через структурированное интервью по шаблону `docs/decisions/adr-template.md` и запишет файл в `docs/decisions/0001-*.md`. Это не одна команда — это диалог: `/adr` задаёт вопросы, ты отвечаешь.

---

## Шаг 3: Настроить все агенты

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

---

## Шаг 4: Документировать hardware layer (опционально)

Если у тебя специфичное железо (headless-станция, нестандартный GPU, ограниченная RAM):

```bash
mkdir -p /path/to/your/project/bootstrap/hardware
# Создай <platform>.md по образцу:
cat ~/claude-mini/bootstrap/hardware/mac-mini-2018.md
```

Документируй: платформа, RAM, особенности PATH, зависимости, команда запуска `universal-setup.sh`.

---

## Шаг 5: Настроить PR template

```bash
mkdir -p /path/to/your/project/.github
cp ~/claude-mini/bootstrap/templates/pr-template.md \
   /path/to/your/project/.github/pull_request_template.md
```

---

## Шаг 6: Проверить полный pipeline на тестовом issue

```bash
cd /path/to/your/project
claude
```

```
/feature 1
```

Пройди все 12 шагов чеклиста (включая `/codex-review`, `adversarial-critic`, `security-reviewer` если PR prod-bound).

---

## Что означает "всё настроено"

- `./bootstrap/universal-setup.sh --check` → нет drift warnings
- CI зелёный на тестовом PR
- governance hook блокирует плохой коммит
- `/feature 1` доходит до "PR готов к human review"

---

## Дополнительно

- Метрики и ROI: [`docs/metrics/onboarding.md`](../../metrics/onboarding.md)
- Еженедельная maintenance: [`docs/runbooks/weekly-maintenance.md`](../runbooks/weekly-maintenance.md)
- Перенос на новую машину: [`docs/runbooks/vendor-migration.md`](../runbooks/vendor-migration.md)
