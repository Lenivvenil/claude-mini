# 0008. Strict hardware-vs-universal layer separation

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: architecture, reproducibility, portability

## Context and Problem Statement

Первая серия установочных документов (`mac-mini-claude-code-setup-final.md` и др.) смешивала Mac-specific шаги (Homebrew, LaunchAgents, Screen Sharing kickstart) с hardware-независимыми (агенты, commands, hooks). Воспроизводимость затрудняется: при миграции на Linux в 2027 или при подключении второй машины нельзя одним действием установить только то, что переносимо.

## Decision Drivers

* Горизонт до 2027: возможная миграция с macOS на Linux.
* Возможность multi-machine setup (MacBook Pro M4 + Mac mini 2018 + будущее).
* Прагматическая воспроизводимость: hardware-layer проходится раз в годы, universal — на каждую новую машину/пользователя.
* GUI-зависимые шаги (Full Disk Access, Screen Sharing dialogs) принципиально не автоматизируются.

## Considered Options

* **Option A: Один universal-setup.sh, который platform-detect'ит и делает всё.** Магический скрипт, внешне простой.
* **Option B: Строгое разделение: `bootstrap/hardware/<platform>.md` как manual runbook, `bootstrap/universal-setup.sh` только для universal.** Человек руками проходит hardware один раз.
* **Option C: Гибрид: `bootstrap/hardware/<platform>/install.sh` автоматизированная часть + `manual-steps.md` для GUI-зависимых.** Два файла на платформу.

## Decision Outcome

Chosen option: **Option B**. GUI-зависимые шаги и system-secret-store нельзя честно автоматизировать без лицензионных или security-нарушений (например, unlocking Keychain через script требует пароля plaintext). Гибрид (C) добавляет сложности без полной автоматизации. Опция A скрывает факт нонavtomat'а и создаёт ложное ожидание.

Материально: `bootstrap/universal-setup.sh` в начале проверяет `~/.config/claude-mini/platform.done` флаг и отказывается работать без него. Флаг ставится вручную оператором после прохождения hardware runbook'а (читай "я подтверждаю что выполнил hardware setup").

### Positive Consequences

* Чистая абстракция: каждый артефакт в одном месте, не в двух.
* Миграция macOS → Linux = новый hardware-runbook + тот же universal-setup.sh.
* Universal layer тестируем: на чистой VM можно проверить setup без setup'а всей системы.
* Documentation честная: "Full Disk Access нельзя автоматизировать" явно сказано, не спрятано за скриптом, который всё равно требует click'а.

### Negative Consequences

* Первое прохождение требует чтения длинного hardware runbook'а (не "просто запусти скрипт").
* Разделение hardware vs universal — суждение. Есть grey zone (например, `gh` CLI — hardware или universal? CLI сам по себе universal, но install через brew — hardware).
* Документация растёт: один hardware-runbook на платформу.

## Confirmation

Тест воспроизводимости: на чистой macOS VM после hardware runbook'а, `./bootstrap/universal-setup.sh --install` завершается exit 0 и `./bootstrap/universal-setup.sh --check` не показывает drift.

Тест миграции (будущий): сможет ли Venil на новом Linux-устройстве запустить universal-setup.sh и получить рабочий Claude-стек после прохождения linux-debian.md hardware runbook'а.

## Re-visit Trigger

* Claude Code получает cross-platform declarative setup (например, yaml-декларация того, что должно быть в `~/.claude/`).
* Появляется production-ready infrastructure-as-code tool, который покрывает GUI-зависимые шаги (Ansible + osx modules + workarounds).
* Множественные платформы (>3 hardware-runbook'ов) — тогда пересмотреть не-objединять ли хотя бы часть через IaC.

## Links

* `../architecture/layers.md` — детальное правило отсечки
* `bootstrap/universal-setup.sh`
* `bootstrap/hardware/mac-mini-2018.md`
