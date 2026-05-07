# Onboarding metrics

Метрики успеха для `docs/onboarding/`. Все измеряются вручную — без instrumentation, без кода.

**Обновлять при:** изменении `bootstrap/universal-setup.sh`, добавлении новых команд, изменении требований тиров.

---

## Метрики minimal tier

| Метрика | Цель | Как измерить |
|---|---|---|
| Время от `git clone` до первого зелёного `/review` | ≤ 30 минут | Секундомер: старт — команда clone, финиш — вывод `/review` без BLOCK |
| Количество шагов troubleshooting | 0 | Прошёл `minimal.md` без обращения к troubleshooting-секции |
| Длина `minimal.md` | ≤ 200 строк | `wc -l docs/onboarding/minimal.md` |

## Метрики standard tier

| Метрика | Цель | Как измерить |
|---|---|---|
| Время до первого `/feature` с полным чеклистом | ≤ 2 часа | Секундомер: старт — начало шага 1, финиш — "PR готов к human review" |
| Governance hook срабатывает на плохом коммите | Да | `echo "bad" \| bash .git/hooks/commit-msg /dev/stdin; echo $?` → 1 |
| MCP-серверы подключены | Все 3 | В Claude Code: проверить что GitHub/Serena/Context7 отвечают |

## Метрики full tier

| Метрика | Цель | Как измерить |
|---|---|---|
| CI зелёный на первом тестовом PR | Да | GitHub Actions: все required jobs ✓ |
| Mutation testing запускается | Да | `gh workflow run mutation.yml` → статус succeeded |
| ADR-0001 (baseline) создан | Да | `test -f docs/decisions/0001-*.md` |

---

## Drift detection

При каждом изменении `bootstrap/universal-setup.sh`:
1. Перечитать `docs/onboarding/minimal.md` — все команды актуальны?
2. Перечитать `docs/onboarding/standard.md` — шаги `--install` и `--target` не устарели?
3. Обновить соответствующие строки + зафиксировать в том же PR.

Ответственный: автор PR затрагивающего `bootstrap/`.

---

## История замеров

| Дата | Тир | Время | Примечание |
|---|---|---|---|
| 2026-05-07 | — | — | Первая версия метрик; замеры ещё не проводились |
