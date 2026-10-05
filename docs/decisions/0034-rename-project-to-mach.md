# 0034. Rename the project, plugin and marketplace to MACH

* Status: accepted (2026-10-04, PR #362 merged)
* Superseded-by: ~
* Date: 2026-10-04
* Deciders: Lenivvenil (operator); draft by Claude
* Tags: governance, plugin, deploy

## Context and Problem Statement

Claude Code 2.1.289 отклоняет имя плагина `claude-mini`: `claude plugin validate plugin --strict` пишет, что имя зарезервировано, потому что сторонний плагин не может начинаться с `claude-`. CI проходит только потому, что закрепил версию 2.1.283 (`.github/workflows/ci.yml:111`). Первый же подъём этой версии делает CI красным для каждого PR. Проект публичный, под MIT, и рассчитан на чужих пользователей, поэтому имя нужно международное и короткое. У владельца есть своё имя для этой темы: MACH, Managed AI-Assisted Change. Под ним весной 2026 были два закрытых репозитория с методологией (`Lenivvenil/mach`, `Lenivvenil/mach-1`), без реализации.

## Decision Drivers

* `claude plugin validate plugin --strict` проходит на текущей версии Claude Code, и закрепление версии в CI можно поднимать.
* Одно имя у репозитория, плагина, marketplace, команд и файлов в развёрнутых проектах. Два имени у одной вещи путают пользователя и расходятся в документации.
* Развёрнутые проекты (Mac mini, likec4) переходят на новое имя одной командой `setup/harness apply`, без ручной правки файлов.
* Имя понятно без русского контекста и не занято среди харнессов для Claude Code.

## Considered Options

* **Option A.** Всё становится MACH: репозиторий, плагин, marketplace, файл конфига проекта, каталог состояния, переменные окружения. `setup/harness apply` переносит старые записи развёрнутого проекта на новые. Старые репозитории `mach` и `mach-1` архивируются.
* **Option B.** Меняются только имя плагина и marketplace на `mach`. Репозиторий, конфиг `claude-mini.json`, каталог состояния и переменные остаются со старым именем.
* **Option C.** Новое придуманное слово вместо MACH, например `jig` или `stanok`.

## Decision Outcome

Chosen option: **Option A**, because только он даёт одно имя (драйвер 2). Опция B снимает поломку CI, но оставляет пользователю плагин `mach`, который читает `.claude/claude-mini.json`, и это та же путаница двух текстов об одном, что описана в ADR-0033. Опция C отклонена владельцем: MACH уже несёт смысл проекта, а `jig` занят консольным агентом, `stanok` непонятен вне русского языка.

Содержание решения.

1. Имена. Репозиторий `Lenivvenil/mach`. Плагин `mach`, marketplace `mach`, идентификатор `mach@mach`, команды `/mach:feature` и так далее. Расшифровка в README: «MACH — Managed AI-Assisted Change». В README одна строка о том, что проект не связан с MACH Alliance (Microservices, API-first, Cloud-native, Headless).
2. Файлы в развёрнутом проекте. `.claude/claude-mini.json` становится `.claude/mach.json`. Каталог состояния и журнал намерений `claude-mini/` становятся `mach/`, каталог прогона `.claude-mini-run` становится `.mach-run`. Записи `enabledPlugins["claude-mini@claude-mini"]` и `extraKnownMarketplaces["claude-mini"]` заменяются на `mach@mach` и `mach`.
3. Переменные окружения `CLAUDE_MINI_*` становятся `MACH_*`. Элемент Связки ключей для тестов `claude-mini-test-oauth` становится `mach-test-oauth`.
4. Миграция. `setup/harness apply` находит старые записи из п. 2 и переносит их на новые в той же транзакции, что и остальные пункты, с записью в журнал намерений. `uninstall` убирает и старые, и новые записи, которые ставил харнесс. Плагин читает только новые имена. Если в проекте лежит старый конфиг, а нового нет, хук коммитов отказывает с текстом: запустите `setup/harness apply`. Постоянного чтения старых имён нет: развёрнутых проектов два, и запасной путь в коде остался бы навсегда.
5. Порядок на GitHub. Старый `Lenivvenil/mach` переименовывается в `mach-framework-2026` и архивируется. `mach-1` архивируется. Затем `Lenivvenil/claude-mini` переименовывается в `Lenivvenil/mach`. GitHub перенаправляет старые адреса, поэтому постоянные ссылки на коммиты в `docs/history/` и ADR продолжают работать.
6. Что не меняется. Принятые ADR не правятся (правило 4 AGENTS.md), старое имя в них и в `docs/history/` остаётся как запись прошлого. Тексты методологии из старых репозиториев в этот репозиторий не переносятся.
7. Локальные копии. Каталог `~/projects/claude-mini` на машинах владельца переименовывается в `~/projects/mach`, а remote перенастраивается на новый адрес. Шаги описаны в DEPLOY.md.

### Positive Consequences

* Закрепление версии Claude Code в CI снова можно поднимать.
* Одно имя во всех местах, где его видит пользователь.
* Перенос развёрнутого проекта делается той же командой, что и развёртывание.

### Negative Consequences

* Около 190 упоминаний старого имени вне `docs/history/` и `docs/decisions/` меняются одним PR, и его ревью тяжелее обычного.
* Пользователь, который не запустит `apply` после обновления, получит отказ хука коммитов до запуска.
* Поиск «MACH framework» в первую очередь выдаёт MACH Alliance. Строка в README снимает путаницу только у тех, кто дошёл до README.
* Память Claude Code привязана к пути проекта. После переименования каталога заметки из `~/.claude/projects/-Users-venil-projects-claude-mini/` нужно перенести вручную.

## Pros and Cons of the Options

### Option A

* Good, because одно имя везде.
* Good, because миграция идёт через существующий механизм транзакций `setup/harness`.
* Bad, because большой PR и разовый шаг для каждого развёрнутого проекта.

### Option B

* Good, because маленький PR, развёрнутые проекты почти не трогаются.
* Bad, because плагин `mach` читает файлы `claude-mini`, и документация обречена объяснять два имени.

### Option C

* Good, because новое слово можно выбрать заведомо свободным.
* Bad, because теряется готовый смысл MACH, а проверенные свободные слова либо заняты по смыслу, либо непонятны вне русского языка.

## Confirmation

* `claude plugin validate plugin --strict` проходит на текущей версии Claude Code, закрепление в `.github/workflows/ci.yml` поднято до неё.
* `git grep claude-mini -- . ':!docs/history' ':!docs/decisions'` находит только код миграции из п. 4 и его тесты.
* `tests/setup/run.sh` проверяет перенос проекта со старыми записями и `uninstall` после переноса.
* Приёмка режима B на Mac mini проходит после переименования. likec4 работает с `mach@mach`.
