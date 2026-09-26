# Sprint Orchestrator Test Fixtures

> **ADR-0030 §Confirmation:** dry-run против fixture sprint'а из 3 тикетов с заранее известными terminal-состояниями. Полный mock-gh end-to-end прогон — деferred на TODO(#44) `type:scope-deferral`.
>
> Этот файл документирует ожидаемые terminal-состояния трёх сценариев для будущего автоматического теста.

---

## Сценарий 1: merged

**Условие:** issue открыт с label `Sprint`, claude-сессия завершилась успешно, PR создан и смержен, issue закрыт.

**Ожидаемый terminal state:**
```json
{
  "state": "merged",
  "reason": "",
  "tokens_used": <N>,
  "pr_number": <M>,
  "session_duration_sec": <T>
}
```

**Что `verify_outcome` должен найти:** `gh issue view N --json state` → `CLOSED`; `gh pr list --search "Closes #N" --state merged` → length > 0.

---

## Сценарий 2: escalated (T2 — no_pr_after_session)

**Условие:** issue открыт с label `Sprint`, claude-сессия завершилась с exit 0, но PR не создан, issue остался открытым.

**Ожидаемый terminal state:**
```json
{
  "state": "escalated",
  "reason": "no_pr_after_session",
  "tokens_used": <N>
}
```

**Что `escalate` должен сделать:** label `needs-human` добавлен; комментарий с `trigger=no_pr_after_session severity=critical`; notify.sh вызван с `critical`.

---

## Сценарий 3: failed (T1 — process_error)

**Условие:** issue открыт с label `Sprint`, claude-сессия завершилась с exit ≠ 0.

**Ожидаемый terminal state:**
```json
{
  "state": "failed",
  "reason": "claude exit 2",
  "tokens_used": 0
}
```

**Что `run_ticket` должен сделать:** label `needs-human` добавлен; комментарий с `T1 process_error — claude exit 2`; `.sprint-state["N"].state = "failed"` (не "escalated").

---

## Как запустить (после реализации mock-gh)

```bash
# TODO(#44): mock-gh + fixtures end-to-end test
# bootstrap/tests/verify/sprint-orchestrator.sh --fixtures bootstrap/tests/fixtures/sprint-orchestrator/
```
