# Getting Started with claude-mini

claude-mini — это воспроизводимый AI-assisted workflow для Claude Code. Он устанавливает slash-команды (`/plan`, `/implement`, `/review`, `/feature`), агентов-критиков и governance hook прямо в твои проекты — одной командой, без ручной настройки.

Ты получаешь pipeline: GitHub issue → план → реализация → двухголосый review → коммит с автоматическим контролем формата. Каждый шаг оставляет артефакт на диске, поэтому сессию можно возобновить без потери контекста.

Три уровня установки — выбери по своей ситуации:

| Уровень | Время | Что получишь | Кому подходит |
|---|---|---|---|
| **[Minimal](minimal.md)** | ~30 мин | `/plan` + `/review` в тестовом проекте | Первое знакомство |
| **[Standard](standard.md)** | ~1-2 ч | Всё выше + governance hook + MCP | Регулярная работа |
| **[Full / Paranoid mode](full.md)** | ~3-4 ч | Всё выше + mutation testing + все агенты + CI | Полный стек |

Не знаешь какой выбрать? → [decision-matrix.md](decision-matrix.md)

---

**Уже установлено? Дальше:**
- Ежедневный флоу: [`docs/runbooks/daily-session.md`](../runbooks/daily-session.md)
- Новая фича: [`docs/runbooks/feature-pipeline.md`](../runbooks/feature-pipeline.md)
- Что сломалось: [`docs/runbooks/incident-recovery.md`](../runbooks/incident-recovery.md)
