# Runbook: Sprint Sweep

> ⚠️ **СТАТУС: ЗАМОРОЖЕН (2026-06-10).** Оркестратор экспериментальный: spike #227 не завершён, известный баг #243 открыт, production-прогонов не было. Разморозка — по реальному трению в digest-проекте, не по календарю (решение оператора, #255). Код не удаляется; runbook остаётся справочным.

> **ADR:** [`docs/decisions/0030-sprint-orchestrator.md`](../decisions/0030-sprint-orchestrator.md)
> **Design doc:** [`docs/architecture/sprint-orchestrator.md`](../architecture/sprint-orchestrator.md)
> **Script:** `bootstrap/scripts/sprint.sh`
> **Related:** issues [#44](https://github.com/Lenivvenil/claude-mini/issues/44) (Phase-0), [#80](https://github.com/Lenivvenil/claude-mini/issues/80) (git worktree), [#81](https://github.com/Lenivvenil/claude-mini/issues/81) (side-effects verify)

Операционная инструкция для оператора. Архитектурный rationale — в ADR-0030; детали реализации — в design doc.

---

## Когда запускать

**Условия:**

- В канбан-статусе `Sprint` накопилось ≥ 2 тикетов с AC (acceptance criteria)
- Каждый тикет в очереди: чёткий Problem statement, testable AC, нет label `blocked`
- Оценка времени: baseline из калибровки [#228](https://github.com/Lenivvenil/claude-mini/issues/228) — ~400K токенов / тикет (meta/chore тип, высокий cache_read). Feature-тикеты ожидаемо выше; данных по ним пока нет. **Предварительно, ревизия после N≥3 тикетов ([#244](https://github.com/Lenivvenil/claude-mini/issues/244)).**
- Допустимо запускать ночью / в фоне — sweep эскалирует, а не молча падает

**Pre-flight чек-лист:**

```bash
# 1. Убедиться что gh авторизован
gh auth status

# 2. Убедиться что claude CLI доступен
claude --version

# 3. Проверить очередь — сколько тикетов будет обработано
bash bootstrap/scripts/sprint.sh --dry-run
# Пример вывода:
# DRY-RUN: reading Sprint queue (label: Sprint)
# DRY-RUN: would process tickets in order:
#   1. #221 — feat(adr): sprint orchestrator decision
#   2. #222 — docs(arch): sprint-orchestrator.md
```

**Состояние канбана до запуска:**

- Тикеты с label `Sprint` — открытые, без `blocked`, без `needs-human`
- Лейблы приоритета (`P0-critical`, `P1-high`, `P2-medium`) — sprint.sh сортирует по ним; без лейбла — тикет идёт последним
- Тикеты с `needs-human` автоматически пропускаются (T7); убрать label если хочешь включить в sweep

---

## Запуск

```bash
# Запустить sweep по всем Sprint-тикетам
bash bootstrap/scripts/sprint.sh

# Продолжить прерванный sweep
bash bootstrap/scripts/sprint.sh --resume

# Dry-run (без запуска claude-сессий)
bash bootstrap/scripts/sprint.sh --dry-run

# Один тикет (debug / после эскалации)
bash bootstrap/scripts/sprint.sh --ticket 222

# Sweep с бюджетным лимитом (мягкий: останавливает новые тикеты, не прерывает текущий)
bash bootstrap/scripts/sprint.sh --budget 2000000

# Sweep с нестандартным лейблом
bash bootstrap/scripts/sprint.sh --sprint-label "Ready"
```

**Переменные окружения (все опциональны — есть дефолты):**

| Переменная | Дефолт | Назначение |
|---|---|---|
| `CLAUDE_BIN` | `claude` | путь к claude CLI |
| `GH_BIN` | `gh` | путь к gh CLI |
| `REPO_ROOT` | `git rev-parse --show-toplevel` | корень репо |
| `BUDGET_SPIKE_THRESHOLD` | `600000` | порог токенов на один тикет для warn-уведомления (T5) |
| `CONSECUTIVE_FAILURE_THRESHOLD` | `3` | сколько ошибок подряд abort'ят sweep (T6) |
| `MAX_TURNS` | `200` | лимит turns одной claude-сессии |
| `NTFY_TOPIC` | *(не установлено)* | топик ntfy.sh для push-уведомлений на телефон |

**Ожидаемый вывод в терминале:**

```
INFO: Queue ready (3 tickets)
[TICKET #221] starting /feature session
[TICKET #221] merged OK (394045 tokens)
[TICKET #222] starting /feature session
[TICKET #222] escalated: no_pr_after_session (critical)
[TICKET #223] T7 pre_existing_needs_human — skipping
```

---

## Поведение при остановке (триггеры T1–T10)

Когда sprint.sh вешает label `needs-human` — это эскалация. Оркестратор оставил комментарий на issue с trigger-именем и фрагментом контекста (≤200 символов).

**Общая схема:**
1. `gh issue view <N>` — прочитать комментарий sprint.sh: строка `sprint.sh escalation: trigger=...`
2. Устранить причину (таблица ниже)
3. Снять label: `gh issue edit <N> --remove-label "needs-human"`
4. Продолжить: `bash bootstrap/scripts/sprint.sh --resume`

**Таблица триггеров:**

| T# | Имя | Severity | Условие | Действие оператора |
|----|-----|----------|---------|-------------------|
| T1 | `process_error` | **critical** | `claude -p` завершился с exit ≠ 0 | Открой `.sprint-logs/<sweep_id>/<N>-session.json`, найди stderr. Если governance hook — почини формат коммита. Если claude CLI-ошибка — проверь `claude --version`, `gh auth status`, свободное место. Потом `--resume`. |
| T2 | `no_pr_after_session` | **critical** | Сессия завершилась, PR не создан (нет open/merged PR с `Closes #N`) | Запусти `bash bootstrap/scripts/sprint.sh --ticket <N>` вручную и следи за сессией. Скорее всего pipeline не дошёл до `gh pr create` (BLOCK в review, advisor calls, governance hook). Разбери что именно в логе; потом `--resume`. |
| T3 | `issue_not_closed` | **warn** | PR смержен, но issue открыт | Открой PR, убедись что body содержит `Closes #N`. Если нет — добавь: `gh pr edit <PR> --body "..."`. После следующего merge issue закроется автоматически. |
| T4 | `governance_block` | **warn** (non-terminal) | stdout содержит `governance hook blocked` или `commit rejected` | Sprint продолжает работу — T4 не останавливает тикет. Проверь что pipeline всё же создал PR (если нет — будет T2). Если PR есть — ничего делать не надо. |
| T5 | `budget_spike` | **warn** (non-terminal) | Токены тикета > `BUDGET_SPIKE_THRESHOLD` (600K) | Sprint продолжает работу. Уведомление информационное. Если хочешь понять почему тикет дорогой: `jq -Rr '(try fromjson // null) \| select(. != null and .type == "result") \| .usage' .sprint-logs/<sweep_id>/<N>-session.json \| tail -1` |
| T6 | `consecutive_failures` | **critical** | ≥3 тикетов подряд в failed/escalated | Sweep прерван. Читай последние N тикетов в `.sprint-state`, открывай их сессионные логи. Скорее всего системная проблема (claude недоступен, gh auth протух, репо сломан). Устрани корень, потом `--resume`. |
| T7 | `pre_existing_needs_human` | **warn** | Label `needs-human` уже был на тикете до старта сессии | Тикет пропущен, sweep продолжил. Прочитай тикет — он уже ждёт внимания. После разбора: `gh issue edit <N> --remove-label "needs-human"` и `--resume` если хочешь включить в sweep. |
| T8 | `no_commits_in_session` | **critical** | *(отложен — трекинг: [#44](https://github.com/Lenivvenil/claude-mini/issues/44))* | Сейчас subsumed by T2: если нет коммитов и нет PR — сработает T2. T8 как самостоятельный триггер появится в рамках Phase-0 условий #44. |
| T9 | `state_file_corrupt` | **critical** | `.sprint-state` не парсится как JSON | Sweep прерван немедленно. Удали повреждённый файл: `rm .sprint-state`. Потом `--resume` — recovery использует GitHub как источник правды. |
| T10 | `usage_limit` | **critical** | *(отложен — трекинг: [#240](https://github.com/Lenivvenil/claude-mini/issues/240))* | Rate-limit от Anthropic. Пока T10 не реализован, `claude -p` при лимите скорее всего вернёт non-zero exit → сработает T1. Подожди сброса лимита (почасовой), потом `--resume`. |

---

## Как сбросить эскалацию вручную

Если тикет был ошибочно помечен `needs-human`:

```bash
# 1. Убрать label на GitHub
gh issue edit <N> --remove-label "needs-human"

# 2. Найти и удалить escalation-комментарий sprint.sh (опционально)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
COMMENT_ID=$(gh api "repos/${REPO}/issues/<N>/comments" \
  --jq '.[] | select(.body | startswith("sprint.sh escalation:")) | .id' | head -1)
[ -n "$COMMENT_ID" ] && gh api "repos/${REPO}/issues/comments/${COMMENT_ID}" -X DELETE

# 3. Удалить запись из .sprint-state (ключ — номер тикета без #, например "221")
# Проверь ключи: jq 'keys' .sprint-state
jq 'del(.tickets["<N>"])' .sprint-state > .sprint-state.tmp && mv .sprint-state.tmp .sprint-state

# 4. Продолжить sweep
bash bootstrap/scripts/sprint.sh --resume
```

---

## Логи

### `.sprint-state` — прогресс sweep'а

Создаётся в корне репо, не коммитится (добавлен в `.gitignore`). Источник правды — GitHub; `.sprint-state` — кэш для restart-recovery.

```bash
# Быстрый обзор sweep'а
jq '{total: .summary.total, merged: .summary.merged, escalated: .summary.escalated, failed: .summary.failed}' .sprint-state

# Все тикеты с их статусами
jq '.tickets | to_entries[] | "\(.key): \(.value.state) (\(.value.reason))"' -r .sprint-state

# Retro-дайджест (суммарные токены)
jq '{
  total: .summary.total,
  merged: .summary.merged,
  escalated: .summary.escalated,
  failed: .summary.failed,
  total_tokens: ([.tickets[].tokens_used] | add // 0)
}' .sprint-state

# Найти самый дорогой тикет
jq '.tickets | to_entries | sort_by(-.value.tokens_used) | .[0] | "\(.key): \(.value.tokens_used) tokens"' -r .sprint-state
```

State enum: `running` | `merged` | `escalated` | `escalation_failed` | `failed`.

### `.sprint-logs/<sweep_id>/` — сессионные логи

Каждый тикет пишет JSON-лог сессии Claude Code: `.sprint-logs/<sweep_id>/<N>-session.json`. Не коммитится. Audit trail — не удалять до ретроспективы.

```bash
# Список sweep'ов
ls .sprint-logs/

# Список тикетов конкретного sweep'а
ls .sprint-logs/2026-05-10T14:00:00Z/

# Прочитать usage тикета (compact output чтобы tail -1 получил весь объект, не только '}')
jq -Rrc '(try fromjson // null) | select(. != null and .type == "result") | .usage' \
  .sprint-logs/<sweep_id>/<N>-session.json | tail -1 | jq .

# Найти последнее сообщение Claude (для диагностики T2 — почему не дошло до PR)
jq -Rr '(try fromjson // null) | select(. != null and .type == "assistant") | .message.content[-1].text // empty' \
  .sprint-logs/<sweep_id>/<N>-session.json 2>/dev/null | tail -5

# Найти причину остановки (для T1)
grep -a "exit\|governance hook blocked\|commit rejected" .sprint-logs/<sweep_id>/<N>-session.json | tail -10
```

---

## Ретроспектива (ручная)

После каждого sweep'а — просматривать `.sprint-state` и `.sprint-logs/`. Автоматизация (`/sprint-retro` skill) — запланирована отдельным тикетом после 2–3 реальных спринтов.

```bash
# 1. Cycle time (длительность сессий в секундах)
jq '.tickets | to_entries[] | "\(.key): \(.value.session_duration_sec // "?")s"' -r .sprint-state

# 2. Escalation breakdown (по trigger-именам)
jq '[.tickets | to_entries[]
  | select(.value.state == "escalated" or .value.state == "failed")
  | .value.reason]
  | group_by(.)
  | map({reason: .[0], count: length})' .sprint-state

# 3. Средний spend vs порог BUDGET_SPIKE_THRESHOLD
jq --argjson threshold 600000 '
  [.tickets | to_entries[] | select(.value.state == "merged")] |
  {
    count: length,
    avg_tokens: (if length > 0 then ([.[].value.tokens_used] | add / length | floor) else 0 end),
    threshold: $threshold,
    spikes: [.[] | select(.value.tokens_used > $threshold) | .key]
  }' .sprint-state

# 4. AC alignment — проверяется вручную: открой каждый merged PR,
#    посмотри intent-check таблицу в PR body
```

**Что смотреть:**
- Много эскалаций по T2 → pipeline не доходит до PR; ищи паттерн в логах
- Много эскалаций по T4 → часто non-fatal; убедись что PR всё же создался
- Средний tokens_used растёт → пересмотри `BUDGET_SPIKE_THRESHOLD` (#244 после N≥3)
- Escalation rate > 30% → trigger для пересмотра ADR-0030 (см. `## Re-visit Trigger` в `docs/decisions/0030-sprint-orchestrator.md`)

---

## Известные ограничения

- `gh_comment_id` в `.sprint-state` не пишется — TODO([#238](https://github.com/Lenivvenil/claude-mini/issues/238))
- T8 (`no_commits_in_session`) и T10 (`usage_limit`) отложены — трекинг [#44](https://github.com/Lenivvenil/claude-mini/issues/44), [#240](https://github.com/Lenivvenil/claude-mini/issues/240)
- Baseline токенов (600K threshold) основан на N=1 тикете (#228, meta/chore с высоким cache_read) — ревизия [#244](https://github.com/Lenivvenil/claude-mini/issues/244)
