# Первая неделя с claude-mini

Семь дней — от «установил» до «первый PR через полный pipeline». Каждый день — конкретное действие и конкретный артефакт.

---

## День 1 — Ориентация (~30 мин)

**Прочитать:**
- `docs/principles.md` — девять принципов (контракт проекта)
- [`docs/onboarding/GETTING-STARTED.md`](GETTING-STARTED.md) §Minimal — минимальная установка

**Сделать:**
- [ ] `./bootstrap/universal-setup.sh --install` — установить pipeline
- [ ] `./bootstrap/universal-setup.sh --target ~/my-project` — подключить pipeline-команды к проекту
- [ ] Установить governance hook в проект (команды устанавливаются отдельно):
  ```bash
  cd ~/my-project   # hook устанавливается в .git/ текущего каталога
  ~/claude-mini/bootstrap/universal-setup.sh --hook-this-repo
  ```
- [ ] `./bootstrap/universal-setup.sh --check` — убедиться, что drift нет

**Результат:** pipeline установлен, governance hook активен, нет warning-сообщений.

---

## День 2 — Демо-тур (~40 мин)

**Сделать:**
- [ ] Запустить setup-фазу демо:
  ```bash
  bash ~/claude-mini/bootstrap/scripts/mini-bootstrap-demo.sh
  ```
- [ ] Открыть Claude Code в `~/claude-mini-demo/`, создать feature branch, запустить `/implement`
- [ ] Запустить `/review` — посмотреть как вердикт выглядит
- [ ] Запустить финал:
  ```bash
  bash ~/claude-mini/bootstrap/scripts/mini-bootstrap-demo.sh --finalize
  ```
- [ ] Изучить артефакты в `~/claude-mini-demo/`: plan.md, CONTRIBUTING.md, git log

**Результат:** понимание что делает каждый шаг pipeline.

---

## День 3 — Первый issue (~20 мин)

**Прочитать:**
- `docs/runbooks/adr-trigger.md` — когда нужен ADR
- `docs/anti-patterns.md` — ловушки, в которые падает LLM

**Сделать:**
- [ ] Создать первый issue в своём проекте (одна небольшая задача)
- [ ] Запустить `/plan <номер issue>` внутри Claude Code
- [ ] Прочитать plan.md — все 6 разделов заполнены?

**Результат:** `plan.md` в корне вашего проекта.

---

## День 4 — Реализация (~60 мин)

**Сделать:**
- [ ] Создать feature branch: `git checkout -b feat/что-делаете-NN`
- [ ] Запустить `/implement` — Claude читает plan.md и реализует
- [ ] Вызвать `advisor()` **до начала** (проверить план на дыры)
- [ ] Вызвать `advisor()` **перед объявлением done** (второй голос обязателен)
- [ ] Убедиться что план соответствует реализации

**Результат:** изменения в коде/docs на feature branch.

---

## День 5 — QA и ревью (~30 мин)

**Сделать:**
- [ ] Запустить `/qa` — проверить coverage и docs currency
- [ ] Прочитать `qa-report.md`
- [ ] Запустить `/review` — Claude проверит изменение
- [ ] Если PR prod-bound (`bootstrap/`, `.github/workflows/`, `.git/hooks/`, или label `prod-bound`): дождаться `security-reviewer` и `reliability-reviewer`
- [ ] Для личных/OSS проектов: запустить `/codex-review` — второй голос (Codex CLI)

**Результат:** `qa-report.md`, вердикт `/review`.

---

## День 6 — Commit и PR (~20 мин)

**Сделать:**
- [ ] Git commit через governance hook (два `-m` флага, не heredoc):
  ```bash
  git commit -m "feat(scope): что сделали" -m "Closes #NN"
  ```
- [ ] Убедиться что hook прошёл (exit 0)
- [ ] `gh pr create` с `Closes #NN` в body
- [ ] Вставить секцию `## QA` из qa-report.md в PR body

**Результат:** PR открыт, issue закрыт после merge.

---

## День 7 — Maintenance (~20 мин)

**Прочитать:**
- `docs/anti-patterns.md` — что нашли за неделю, стоит ли дополнить

**Сделать:**
- [ ] Запустить `/project-health` — первый базовый health-report
- [ ] Проверить открытые issues: есть ли Icebox-кандидаты
- [ ] Опционально: запустить `/backlog-review` если issues > 10

**Результат:** `docs/metrics/health-YYYY-WW.md`, базовый ритм maintenance.

---

## Быстрый справочник

| Команда | Когда | Тип |
|---|---|---|
| `/plan <N>` | Перед любой задачей | command |
| `/implement` | После `/plan`, на feature branch | command |
| `/qa` | После `/implement` | skill |
| `/review` | После `/qa` | skill |
| `/codex-review` | После `/review` (второй голос, только личные/OSS проекты) | skill |
| `/project-health` | Еженедельно | skill |
| `/backlog-review` | Еженедельно, если issues > 10 | skill |
| `advisor()` | Внутри `/implement`: до начала и перед done | встроенный |
