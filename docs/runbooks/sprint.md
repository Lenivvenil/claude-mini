# Runbook: Sprint Sweep

> **Design doc:** [`docs/architecture/sprint-orchestrator.md`](../architecture/sprint-orchestrator.md)
> **Script:** `bootstrap/scripts/sprint.sh` (not yet implemented — see #44 Phase-0 conditions)

> **NOT FUNCTIONAL YET.** `bootstrap/scripts/sprint.sh` не существует. Команды ниже — будущий интерфейс после закрытия #44 Phase-0. До тех пор пользуйся design doc выше.

*Этот runbook заполняется после первого реального прогона `sprint.sh`.*

---

## Быстрый старт (после реализации sprint.sh)

```bash
# Запустить sweep по всем Sprint-тикетам
./bootstrap/scripts/sprint.sh

# Продолжить прерванный sweep
./bootstrap/scripts/sprint.sh --resume

# Dry-run (без запуска claude-сессий)
./bootstrap/scripts/sprint.sh --dry-run

# Один тикет (debug)
./bootstrap/scripts/sprint.sh --ticket 222
```

---

## TODO(#44): заполнить после первого прогона

- Типовые проблемы и решения
- Как читать `.sprint-state`
- Как вручную закрыть тикет если sweep завис
- Как сбросить эскалацию (`needs-human` → убрать label, удалить запись из `.sprint-state`)
