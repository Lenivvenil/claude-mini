# 0009. Feature-branch + PR flow for solo pipeline

* Status: accepted
* Date: 2026-04-23
* Deciders: venil (operator decides; draft by solutions-architect)
* Tags: workflow, governance, process

## Context and Problem Statement

Relates to: #14

Первый реальный прогон `/feature` обнажил рассинхрон между документом и рантаймом: `CLAUDE.md` и `.claude/commands/feature.md` декларируют PR-based flow (step 11: `gh pr create`), но фактический запуск закоммитил напрямую в `main`, потому что feature-ветка никогда не создавалась. `gh pr create` из `main → main` предсказуемо упал. Проект — solo dev + AI-assisted pipeline; нужно решить, какой из двух флоу является каноничным, и выровнять код/доки под него. Решение архитектурно-значимо: меняет Definition of Done (`docs/principles.md#definition-of-done` уже предполагает PR), governance hook (`ADR-0004`), и три runbook'а.

## Decision Drivers

* **Согласованность документ↔рантайм.** DoD, `/feature`, runbook уже написаны под PR-flow. Любое решение должно выровнять все три слоя.
* **Reversibility.** Насколько дёшево откатить плохое изменение до того, как оно попало в публичную историю `main`.
* **Ceremony-per-task cost.** Сколько шагов человек делает на каждую задачу. Solo dev чувствителен к friction больше, чем team.
* **Enforceability governance'а.** Hook должен детерминированно блокировать нарушения; полагаться на дисциплину solo — неустойчиво (третья директива `docs/principles.md` §3: автоматизировать только низкорискованное).
* **Готовность к росту ≥2 контрибьюторов.** Смена флоу позже дороже, чем решение один раз сейчас.
* **Стоимость CI.** Flow, полагающийся на PR-ворота, требует работающего CI; без required checks PR-merge превращается в формальность.

## Considered Options

* **Option A: main-only commit flow.** `/review` + `/codex-review` — единственные ворота; после них `git commit` на `main` + `git push`. Никакой feature-ветки, никакого PR. Issue закрывается по `Closes #NNN` в commit message.
* **Option B: feature-branch + PR flow (canonical).** На каждый task — отдельная ветка `feat/<slug>-<issue>`; после `/review`+`/codex-review` — `gh pr create`; auto-merge при зелёном CI. Текущее заявленное поведение.
* **Option C: feature-branch + fast-forward merge without PR.** Компромисс: ветка создаётся (reversibility до push + изолированная история), но merge идёт `git merge --ff-only` локально, без `gh pr create`. Отпадает CI-gate и PR UI, остаётся структура истории.

## Decision Outcome

Chosen option: **Option B (feature-branch + PR flow)**. **Reversibility classification: reversible door** — the decision can be walked back to Option A at any time while the project remains solo; it becomes a one-way door at ≥2 contributors (see Re-visit Trigger #1).

Обоснование: документированный контракт проекта (`docs/principles.md` DoD пп. "CI зелёный на всех required jobs" и "PR body ссылается на issue и ADR"; `CLAUDE.md` hard rule #3 "Cross-ref в PR"; `/feature` step 11; `docs/runbooks/feature-pipeline.md` §10) уже предполагает PR-flow на трёх уровнях. Сбой в runtime — это drift, не ошибка контракта. Выравнивание runtime к документу дешевле, чем переписывание документа, DoD, и runbook под Option A, и сохраняет готовность к multi-contributor без миграции. Ссылка на принципы: четвёртая директива (`docs/principles.md` §4 «Knowledge в инструментах, не в памяти») — PR-артефакт в GitHub — это durable knowledge с threaded review, advisor/codex findings прикрепляются к PR-комментам и переживают сессию; main-only flow теряет этот слой. Уникальность репо («проект документирует и устанавливает сам себя») усиливает: pipeline должен уметь произвести любой артефакт — в том числе PR для самого себя.

Option A отклонён как рационализация текущего runtime-сбоя: «раз упало на PR, давайте уберём PR». Это инверсия причинности. Option C отклонён как полумера — он даёт reversibility, но не даёт threaded review, CI-gate, или артефакт для future archaeology; экономия 1 шага (`gh pr create`) не оправдывает потерю.

### Positive Consequences

* Runtime выравнивается с уже написанным контрактом — никакой ретро-правки DoD, `CLAUDE.md`, runbook.
* Reversibility: ошибочную ветку можно закрыть без merge; плохой `main`-commit откатывается только force-push или revert-коммитом (hostile к archaeology).
* Advisor/codex-review findings живут на PR-странице как threaded comments — durable knowledge, соответствует 4-й директиве.
* CI gate срабатывает до попадания в `main`; `required checks` делают DoD-пункт «CI зелёный» enforceable, а не аспирационным.
* Zero migration cost при переходе к ≥2 контрибьютора.

### Negative Consequences

* **+2–3 шага на каждую задачу:** `git checkout -b`, `gh pr create`, `gh pr merge`. Для solo dev с 5–10 задач/неделю — 10–30 дополнительных действий; на длинной дистанции создаёт усталость и соблазн срезать.
* **Требует изменения governance hook (`ADR-0004`):** добавить правило «deny commit when `branch == main`», иначе защита только декларативная. Hook amendment входит в scope этого PR (#14) — отдельный ADR не нужен.
* **Требует рабочего CI с required checks.** Если CI нет / он сломан / он медленный — PR-merge деградирует в rubber-stamp. Сейчас CI в репо в зачаточном состоянии — факт, который нужно закрыть параллельно, иначе PR-flow даёт false sense of safety.
* **Auto-merge на Claude Max solo — ceremonial theatre.** «Сам себе ревьювер» через PR UI — это cosplay командного процесса; риск, что оператор начнёт мерджить не читая, потому что «всё равно мои же коммиты». Mitigation — advisor и codex-review должны реально отрабатывать до merge; если они skip'аются, PR-flow теряет смысл.
* **`/implement` нужно явно учить создавать ветку до первого edit.** Забыть — значит воспроизвести текущий баг; требуется enforcement (hook "not on main" ловит это после факта, но лучше early-fail в `/implement` Phase 1).

## Pros and Cons of the Options

### Option A: main-only commit flow

* Good, потому что минимальная ceremony — 1 команда `git commit` вместо 3.
* Good, потому что нет зависимости от CI/PR-UI — работает офлайн.
* Good, потому что honest для solo: никакой cosplay «командного review».
* Bad, потому что теряется reversibility — плохой commit уже в публичной истории; revert ≠ never-happened.
* Bad, потому что конфликтует с `docs/principles.md` DoD (CI, PR body, Closes, Implements-ADR) — требует переписывания DoD, `CLAUDE.md` hard rule #3, `/feature` step 11, `docs/runbooks/feature-pipeline.md` §10, `.github/pull_request_template.md`. Doc-surface impact значительно больше, чем «3 файла».
* Bad, потому что governance hook (`ADR-0004`) полагается на `branch` как источник issue-ref; при `branch == main` issue-ref обязателен **только** в message — забыл `#NNN` = hard block, и это станет частой блокировкой.
* Bad, потому что advisor/codex findings теряют durable surface (нет PR-комментов) — остаются только в локальной сессии Claude. Регресс против 4-й директивы.
* Bad, потому что миграция к ≥2 контрибьюторам требует полного reverse решения.

### Option B: feature-branch + PR flow (chosen)

* Good, reversibility до push + до merge.
* Good, durable artefact (PR) с threaded review — 4-я директива.
* Good, CI-gate enforceable, а не декларативный.
* Good, zero rewrite действующих доков (DoD, runbook, `/feature`).
* Good, готовность к multi-contributor без миграции.
* Bad, +2–3 шага на task; solo dev friction.
* Bad, требует поправки hook'а («not on main») и обучения `/implement` создавать ветку.
* Bad, требует минимального рабочего CI; без него PR-flow — театр.
* Bad, auto-merge solo = self-review; нужен явный guardrail что advisor/codex отработали.
* Bad, форж-lock-in: `gh pr create`, auto-merge, PR-template жёстко привязывают pipeline к GitHub; миграция на GitLab/Gitea/Forgejo потребует переписывания команд и runbook'ов.

### Option C: feature-branch + fast-forward merge without PR

* Good, reversibility до локального merge (можно удалить ветку).
* Good, изолированная история до готовности.
* Good, экономит 2 шага по сравнению с B (нет `gh pr create`/`gh pr merge`).
* Good, не требует CI — как и A.
* Bad, теряет durable review artefact — ветка удаляется, комментариев нет.
* Bad, не enforceable CI-gate — как A.
* Bad, гибрид, который документируется сложнее, чем каждый из чистых вариантов.
* Bad, всё равно требует hook-правила «not on main» и обучения `/implement` ветке — стоимость как у B, польза как у A.

## Confirmation

Критерии валидации решения после принятия:

1. **Runtime match.** Следующий реальный прогон `/feature <N>` завершается merged PR, а не commit в `main`. Проверка: `git log main --first-parent -5` показывает merge-commits, не direct commits.
2. **Hook enforcement.** Rule 4 добавлена в `bootstrap/hooks/pre-commit-governance.sh`: `if branch == "main" && msg не matching ^(chore|build):.*\b(bootstrap|initial)\b: deny`. После merge запустить `./bootstrap/universal-setup.sh --install` для обновления установленного hook'а. Smoke-test (как в ADR-0004) с `main` checkout и плохим input'ом — exit 2.
3. **`/implement` early-fail.** `.claude/commands/implement.md` Phase 1 явно включает `git checkout -b feat/<slug>-<issue>` как первый шаг; если ветка уже `main` — STOP.
4. **Runbook sync.** `docs/runbooks/feature-pipeline.md` §5 (Implementation) упоминает создание ветки; §10 остаётся как есть.
5. **Ceremony budget.** Через 30 дней проверить skip-rate PR-ceremony. Если skip-rate >20% за месяц → см. Re-visit Trigger #4.
6. **Forge-abstraction audit.** Все GitHub-specific команды (`gh pr create`, `gh pr merge`, `gh pr view`, PR-template) перечислены в `docs/runbooks/feature-pipeline.md` §11 «Forge lock-in surface». Цель — при будущей миграции forge scope замены известен заранее, а не обнаруживается по ошибкам.

## Re-visit Trigger

Решение пересматривается при выполнении хотя бы одного:

* **Рост до ≥2 контрибьюторов.** Option A/C становятся невалидны — Option B единственный вариант, ADR закрывается как «superseded by reality».
* **CI становится медленнее 60 сек на merge И <1 revert в месяц за 3 месяца подряд.** PR-gate перестаёт окупаться — пересмотр в пользу C.
* **Claude Code получает native governance для workflow (branch policy в `settings.json`).** Hook-правила мигрируют туда, формулировка ADR обновляется.
* **Skip-рейт PR-ceremony >20% за месяц** (оператор коммитит напрямую в main в обход pipeline). Значит friction реально превышает ценность — честно пересмотреть в пользу A, не делая вид что всё работает.
* **Миграция с GitHub на другой forge.** Лок-ин материализуется — ADR пересматривается с учётом tooling нового forge.

## Links

* `0004-governance-via-prehook.md` — governance hook; требует поправки «deny commit on main» при принятии Option B.
* `0002-pipeline-over-fanout.md` — single-author pipeline; neither option conflicts, но Option B сохраняет invariant «один автор на PR».
* `0005-two-voice-review-codex-plus.md` — Claude + Codex review; findings лучше living в PR-комментах (B) чем в эфемерной сессии (A/C).
* `../principles.md#definition-of-done` — уже предполагает PR-flow; Option A требует его правки.
* `../principles.md#что-значит-архитектурно-значимо` — смена модели безопасности/процесса merge попадает под «ограничение, которое трудно снять через 6 месяцев».
* `../runbooks/feature-pipeline.md` §10 — должен остаться как есть при B, переписан при A.
* `.claude/commands/feature.md` step 11 — `gh pr create` остаётся при B, удаляется при A.
* `.claude/commands/implement.md` — Phase 1 дополняется `git checkout -b` при B/C.
* Issue #14 — acceptance criteria этого ADR.
