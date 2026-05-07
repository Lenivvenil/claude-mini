# Getting Started with claude-mini

claude-mini добавляет в Claude Code набор готовых команд: планирование, ревью, полный цикл задачи — через один вызов в Claude Code.

Вместо того чтобы объяснять Claude что делать с нуля при каждой задаче — запускаешь `/feature 42`, и Claude ведёт по всему процессу: от GitHub issue до PR. Результат каждого шага пишется в файл, поэтому между сессиями ничего не теряется.

Три варианта установки — выбери свой:

| Вариант | Время | Что получишь | Кому подходит |
|---|---|---|---|
| **[Minimal](minimal.md)** | ~30 мин | `/plan` + `/review` на тестовом проекте | Первый раз |
| **[Standard](standard.md)** | ~1-2 ч | Всё выше + проверка формата коммитов + MCP | Регулярная работа |
| **[Full / Paranoid mode](full.md)** | ~3-4 ч | Всё выше + CI + mutation testing + все агенты | Продакшн-значимые проекты |

Не уверен какой выбрать? → [decision-matrix.md](decision-matrix.md)

---

**Уже установлено? Дальше:**
- Ежедневный флоу: [`docs/runbooks/daily-session.md`](../runbooks/daily-session.md)
- Новая фича: [`docs/runbooks/feature-pipeline.md`](../runbooks/feature-pipeline.md)
- Что сломалось: [`docs/runbooks/incident-recovery.md`](../runbooks/incident-recovery.md)
