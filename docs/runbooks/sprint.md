# Runbook: Sprint Sweep

> **Design doc:** [`docs/architecture/sprint-orchestrator.md`](../architecture/sprint-orchestrator.md)
> **Script:** `bootstrap/scripts/sprint.sh` (Phase-0 реализация; известные ограничения в разделе ниже, #238)

*Для оператора, запускающего недельный sprint sweep. Этот runbook дополняется после первого реального прогона. Детальные troubleshooting-сценарии — #238.*

---

## Быстрый старт

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

## Как читать `.sprint-state`

`.sprint-state` — локальный JSON-кэш прогресса sweep'а. Источник правды — GitHub.

```bash
# Быстрый обзор sweep'а
jq '{total: .summary.total, merged: .summary.merged, escalated: .summary.escalated, failed: .summary.failed}' .sprint-state

# Все тикеты с их статусами
jq '.tickets | to_entries[] | "\(.key): \(.value.state) (\(.value.reason))"' -r .sprint-state

# Retro-дайджест (из design doc B.10)
jq '{total: .summary.total, merged: .summary.merged, escalated: .summary.escalated, failed: .summary.failed, total_tokens: ([.tickets[].tokens_used] | add // 0)}' .sprint-state
```

State enum: `running` | `merged` | `escalated` | `escalation_failed` | `failed`.

---

## Как сбросить эскалацию

Если тикет был ошибочно помечен `needs-human`:

```bash
# 1. Убрать label на GitHub
gh issue edit <N> --remove-label "needs-human"

# 2. Найти и удалить escalation-комментарий sprint.sh
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
COMMENT_ID=$(gh api "repos/${REPO}/issues/<N>/comments" \
  --jq '.[] | select(.body | startswith("sprint.sh escalation:")) | .id' | head -1)
gh api "repos/${REPO}/issues/comments/${COMMENT_ID}" -X DELETE

# 3. Удалить запись из .sprint-state (ключ — номер тикета без #, например "221")
# Проверь ключи: jq 'keys' .sprint-state
jq 'del(.tickets["<N>"])' .sprint-state > .sprint-state.tmp && mv .sprint-state.tmp .sprint-state

# 4. Продолжить sweep
./bootstrap/scripts/sprint.sh --resume
```

---

## Известные ограничения

- `gh_comment_id` в `.sprint-state` не пишется — TODO(#238).

---

## Заполнить после первого прогона (#238)

- Типовые проблемы и решения
- Как вручную закрыть тикет если sweep завис на `running`
