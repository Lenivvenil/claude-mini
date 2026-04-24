# 0010. Abort installer on drift unless --force is passed

* Status: accepted
* Date: 2026-04-23
* Deciders: venil
* Tags: installer, contract, idempotency, safety
* Related issue: #26

## Context and Problem Statement

`bootstrap/universal-setup.sh --install` сегодня поступает нечестно, когда файл в
`~/.claude/` существует и отличается от репо-источника: печатает `warn
"... exists, not overwriting; use --force"` и **завершает установку с exit 0**,
оставляя stale-файл на месте. То есть «установка прошла» при фактическом drift —
пользователь видит зелёный выход, но `~/.claude/` не синхронизирован с репо.

Это противоречит сразу двум явно зафиксированным инвариантам:

1. **ADR-0001 Confirmation:** baseline подтверждается тем, что на чистой машине
   `--install` завершается exit 0 **и** `--check` не показывает drift. Если
   `--install` молча пропускает отличающиеся файлы, то комбинация
   «`--install` → 0, `--check` → drift > 0» становится штатным состоянием и
   baseline-verification теряет смысл.
2. **Principle 1 («красные флаги вместо трейдоффов»):** exit 0 при наличии
   несинхронизированных файлов — это замаскированный drift, не компромисс.
3. **ADR-0008 philosophy of honesty:** «Documentation честная: "Full Disk Access
   нельзя автоматизировать" явно сказано, не спрятано за скриптом». Installer
   должен придерживаться той же планки — не прятать состояние за зелёным exit.

Решить нужно: при расхождении между `src` и `dst` в режиме `--install` без
`--force` — что делает скрипт? Сегодняшнее «warn + continue + exit 0» держать
нельзя; чем заменить.

**Scope:** этот ADR касается только whole-file copy через `copy_file()`
(agents, skills, commands, hooks, scripts, templates). `~/.claude/settings.json`
патчится через jq-merge — это отдельная семантика (идемпотентный merge по
ключам, не byte-equality), вне scope. Если в будущем jq-merge начнёт менять
существующие значения, это предмет отдельного ADR.

## Decision Drivers

* Сохранить идемпотентность: identical bytes → silent skip → exit 0
  (это свойство уже используется в ADR-0001 confirmation и не обсуждается).
* Не разрушать локальные правки оператора без явного согласия
  (Principle 3: destructive actions — в категории «с approval»).
* Поддерживать non-interactive режим: скрипт вызывается из CI
  (`baseline-verification` job), `/bootstrap` slash-команды, будущих runbook'ов.
* Exit code должен различать «успех», «drift требует решения», «crash».
* Сделать drift видимым. Оператор должен узнать о расхождении при первой же
  попытке установки, а не при следующем явном `--check`.

## Considered Options

* **Option 0 — Status quo: warn-and-skip, exit 0.** `--install` без `--force`
  печатает warning и идёт дальше. Пересматриваемое состояние.
* **Option A — `--force` становится default для `--install`.** Любое отличие
  перезаписывается источником молча. Флаг `--force` остаётся синонимом / no-op
  для совместимости.
* **Option B — Abort-on-drift: exit 3 (или новый exit 4) + diff, если нет
  `--force`.** При обнаружении первого расхождения (либо после обхода всего
  дерева — см. ниже под-вариант) скрипт печатает unified diff и выходит с
  ненулевым кодом. Чтобы применить — оператор явно передаёт `--force`.
* **Option C — Раздельные глаголы: `--install` только создаёт отсутствующее,
  `--update` перезаписывает существующее.** Расхождение в `--install` больше
  не проблема скрипта — это проблема того, что оператор не вызвал `--update`.

Interactive prompt (y/n per файл) рассмотрен и отвергнут до голосования:
требует TTY, ломает CI `baseline-verification` (ADR-0001) и `/bootstrap`
автомат. Если когда-нибудь понадобится — под флагом `--interactive`, отдельно.

## Decision Outcome

Chosen option: **Option B — abort-on-drift with --force escape hatch.**

Rationale:

* Сохраняет идемпотентность (identical → exit 0).
* Переводит деструктивное действие в категорию «с approval» из Principle 3:
  перезапись локальных правок требует явного `--force` на каждом запуске.
* Surface'ит drift через ненулевой exit и diff — оператор узнаёт о расхождении
  в момент запуска, не постфактум.
* Совместим с CI: `baseline-verification` на чистой машине расхождений не даёт,
  `--install` → 0.
* Легче откатить, чем Option A: «случайно перезаписали локальные правки»
  невозможно получить молча.

Option A отвергается как симметричный к статус-кво вид нечестности: Status Quo
прячет stale-файлы за зелёным exit; Option A прячет потерянные локальные
правки за зелёным exit. Оба варианта нарушают Principle 1.

Option C отвергается как расширение публичного API без достаточного повода:
два глагола вместо одного с флагом — лишняя surface area, и `--update` всё
равно придётся обогащать семантикой drift-detection.

### Implementation sketch (for Option B)

Предметно (не реализация — намерение, которое ADR фиксирует):

* `copy_file()` в режиме `--install` без `--force` при `cmp -s` → false:
  печатает `diff -u dst src`, инкрементирует `DRIFT`, **не завершает скрипт
  немедленно** — продолжает обход, чтобы показать полный список drift.
* После финального обхода: если `DRIFT > 0` — exit 4 (новый код, отличается
  от «3 = generic error»).
* С `--force`: старое поведение (overwrite).
* Help-текст `--force` меняется с «опасно» на «required to overwrite existing
  files that differ from the repo source».
* Exit codes документируются в header комментарии и в `--help`:
  * 0 — ok (identical everywhere, или overwritten with `--force`)
  * 1 — hardware layer не пройден
  * 2 — отсутствуют обязательные зависимости
  * 3 — script/runtime crash
  * 4 — drift detected, `--force` required

### Positive Consequences

* Честный exit code. «Зелёный» означает «синхронизировано», не «я попытался».
* ADR-0001 Confirmation-тест снова работает предсказуемо: на чистой машине
  `--install` exit 0, повторный `--install` exit 0, разошедшиеся файлы видны.
* Оператор не теряет локальные правки случайно: для перезаписи нужен явный
  `--force` с осознанием, что именно будет перезаписано (diff уже показан).
* CI-friendly: job падает на drift без human-in-the-loop.
* Симметрия с `--check`: `--check` печатает drift и exit 0 (diagnostic);
  `--install` печатает тот же drift и exit 4 (actionable) — один и тот же
  сигнал, разные режимы ответа.

### Negative Consequences

* **Новые пользователи могут получить exit 4 на первом запуске**, если в
  `~/.claude/` что-то уже лежит (например, прошлый ручной setup, или артефакты
  другого инструмента, перезаписавшего наши файлы). Пункт в runbook про
  «если видишь exit 4 — просмотри diff и реши: `--force` или снять файл».
* **Двусмысленность при первой миграции на эту семантику.** Пользователи,
  которые полагались на старое warn-and-skip поведение и имеют локально
  изменённые файлы в `~/.claude/`, при обновлении скрипта внезапно получат
  exit 4. Требуется migration note в CHANGELOG + upgrade-runbook.
* **Новый exit code 4** — это публичный API. Любой downstream (CI job,
  другой скрипт, `/bootstrap` command) должен знать о нём. Изменение контракта
  → версионирование (минимум bump в commit message scope; желательно —
  зафиксировать semver скрипта, которого пока нет).
* **Diff-спам для больших расхождений.** Если drift на 30 файлах —
  unified diff * 30 может быть нечитаем. Mitigation: `head -20` per файл,
  как уже сделано в `--check`; финальная сводка «N files differ, run `--check`
  for full diff».
* **Теряется свойство «always succeeds».** Скрипты / автоматизации, которые
  игнорировали exit code из `--install` в предположении «оно всегда 0 если
  ничего не крашится», сломаются. Нужно явное сообщение в PR issue #26.
* **Не решает deeper проблему source-of-truth.** Если оператор хочет, чтобы
  его локальная правка в `~/.claude/agents/foo.md` **жила** — сейчас нет
  механизма: repo всегда побеждает. ADR не обещает решить это; он честно
  фиксирует «локальные правки `~/.claude/` не поддерживаются, репо — единственный
  источник истины; хочешь править — правь в репо и запускай `--install`».
* **Reversibility:** rollback requires reverting exit-code-4 semantics in `universal-setup.sh`, updating any CI jobs that check the installer exit code, and communicating the change to operators; estimated effort: low (single-file change, no data migration).

## Confirmation

На `main` после merge этого ADR и реализации:

1. На чистой машине после hardware runbook: `--install` → exit 0, `--check` →
   exit 0, no drift. (тот же критерий что в ADR-0001)
2. Модифицировать вручную `~/.claude/agents/adr-reviewer.md` (добавить пробел),
   запустить `--install`: exit 4, diff виден, файл не перезаписан.
3. Повторить (2) с `--force`: exit 0, файл перезаписан.
4. `--check` после (3): exit 0, no drift.
5. Модифицировать `~/.claude/settings.json` через jq-merge (добавить ключ,
   который уже есть в целевой конфигурации): `--install` остаётся idempotent,
   exit 0 (подтверждает, что jq-merge путь не тригерит exit 4).

Интеграционный тест добавляется в тот же `baseline-verification` CI job.
Перед merge'ем проверить, что CI job трактует любой non-zero exit как failure
(иначе exit 4 проигнорируется и smoke-тест драйверит ложный green).

**Note (2026-04-24):** `baseline-verification` CI job does not yet exist in `.github/workflows/`. Confirmation items 1–4 above are verified locally only. Creating the CI job is tracked separately.

## Re-visit Trigger

* Появится требование поддерживать локальные правки `~/.claude/` как первого
  класса (например, per-user overrides без форка репо). Тогда — новый ADR про
  merge-strategy / layered config.
* Появится `--interactive` режим (прямо сейчас отвергнут); если войдёт —
  пересмотреть exit code matrix.
* Переход на declarative setup (yaml-манифест `~/.claude/` содержимого) —
  см. ADR-0008 re-visit trigger; тогда семантика `--install` уходит целиком.
* Если exit code 4 начнёт конфликтовать с соглашением какого-то внешнего
  инструмента, встроенного в pipeline.

## Links

* `docs/decisions/0001-baseline-state-at-takeover.md` — Confirmation clause,
  которую этот ADR укрепляет.
* `docs/decisions/0008-hardware-universal-split.md` — philosophy of honesty
  over hidden automation.
* `docs/principles.md#четыре-директивы` — Principle 1 (красные флаги),
  Principle 3 (автоматизировать только низкорискованное).
* `docs/principles.md#что-значит-архитектурно-значимо` — критерий «публичный
  API» и «ограничение, которое трудно снять через 6 месяцев».
* GitHub issue #26 — исходная постановка.
* `bootstrap/universal-setup.sh` — `copy_file()` function, exit code header.
