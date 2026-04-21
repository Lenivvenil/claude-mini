# Архитектурные слои: hardware vs universal

Воспроизводимость сетапа требует чёткой отсечки между тем, что **специфично для конкретного железа и ОС**, и тем, что **универсально** и переносится между машинами. Этот документ фиксирует границу.

## Правило отсечки

Артефакт или шаг установки относится к **hardware/OS layer**, если истинно хотя бы одно:

- Требует конкретной модели процессора или графической подсистемы
- Требует конкретной версии ОС или дистрибутива
- Взаимодействует с системным keychain/secret store конкретной ОС
- Настраивает power management, launch agents, systemd units, или иные OS-specific службы
- Использует проприетарные протоколы (Screen Sharing, Tailscale daemon install на macOS)
- Запускает GUI-приложения или требует физического/эмулированного дисплея

Всё остальное относится к **universal layer**.

## Hardware/OS layer

Живёт в `bootstrap/hardware/<platform>.md` **как инструкция** (не скрипт) — потому что эти шаги часто требуют GUI-диалогов, физического доступа или ручных решений, которые нельзя идемпотентно автоматизировать.

Поддерживаемые платформы:

- **`mac-mini-2018.md`** — Intel Mac mini 2018, macOS Monterey → Sequoia. Текущая primary-станция.
- **`linux-debian.md`** — планируется к концу 2027 при миграции.

### Что входит в hardware layer (Mac mini)

| Компонент | Почему hardware |
|---|---|
| Homebrew установка на Intel (`/usr/local`) | Путь зависит от архитектуры (Intel vs Apple Silicon в `/opt/homebrew`) |
| CLT 16.4 (`xcode-select --install`) | macOS-only; через GUI-диалог |
| Node.js через `.pkg` вместо brew | Intel-specific workaround для z3/llvm compile issues |
| Tailscale system daemon (vs App Store version) | macOS-specific; требуется для pre-login startup |
| Screen Sharing через ARD `kickstart` | macOS-only CLI workaround |
| LaunchAgents / LaunchDaemons (tmux, Plex, Transmission, caffeinate) | macOS-native; аналог systemd на Linux |
| `pmset` настройки (no-sleep, autorestart) | macOS-only power management |
| macOS Keychain через `security` CLI | OS-specific secret store |
| Full Disk Access GUI-настройка для SSH/Screen Sharing | Требует физического GUI |
| Firewall whitelist для Plex | macOS System Preferences или CLI |
| Ghostty + `xterm-ghostty` terminfo | Terminal emulator-specific |
| Workarounds paste'а через Ghostty+SSH (multiline backslash bug) | Ghostty-specific |

### Что входит в hardware layer (будущий Linux)

| Компонент | Аналог macOS |
|---|---|
| Пакетный менеджер дистрибутива (apt/pacman/dnf) | Homebrew |
| Systemd user units | LaunchAgents |
| `gnome-keyring` / `kwallet` / `libsecret` | macOS Keychain |
| Wayland/X11 display manager (если нужен GUI) | Screen Sharing |
| Tailscale systemd unit | Tailscale daemon на macOS |

**Important:** переход Mac → Linux делается **по соответствующему hardware-runbook'у**, а не автоматикой. Причина: Keychain на macOS и keyring на Linux настолько разные API, что скрывать эту разницу за абстракцией — дороже, чем написать два runbook'а.

## Universal layer

Всё, что не требует железа или ОС. Устанавливается **одним и тем же** `./bootstrap/universal-setup.sh --install` на любой машине, где уже выполнен hardware-runbook.

### Что входит в universal layer

| Компонент | Где живёт |
|---|---|
| Claude Code **конфигурация** (не установка бинаря — это hardware step) | `~/.claude/settings.json`, `CLAUDE.md`, `RTK.md` |
| Агенты | `~/.claude/agents/*.md` |
| Skills | `~/.claude/skills/<name>/SKILL.md` |
| Slash commands | `~/.claude/commands/*.md` |
| Hooks | `~/.claude/hooks/*.sh` |
| Scripts (утилиты) | `~/.claude/scripts/*.sh` |
| MCP server configs (Serena, GitHub, Context7) | `~/.claude/settings.json` под `mcpServers` |
| Codex CLI конфиг | `~/.codex/config.toml` |
| `gh` CLI aliases | через `gh alias set` |
| Templates для новых проектов | `bootstrap/templates/` копируется при `mini-bootstrap-project` |
| Session helper scripts | symlinks `~/bin/mini-*` |
| Env vars для Claude Code (`CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`) | Добавляются в `~/.zshrc` или `~/.bashrc` идемпотентно |

### Принципы идемпотентности universal layer

Любой запуск `universal-setup.sh --install`:

1. **Не перезаписывает существующие файлы** без `--force`. Разница показывается как diff.
2. **Проверяет наличие бинарей** (`claude`, `gh`, `codex`, `jq`, `rg`) — если чего-то нет, `setup` сообщает что именно hardware-layer пропустил, и ссылается на hardware-runbook.
3. **Патчит `settings.json` через jq**, добавляя недостающие ключи, не удаляя существующие (например, RTK hook, если он уже был).
4. **Резервирует существующие `~/.zshrc` / `~/.bashrc`** перед изменением.
5. **Возвращает exit 0** даже если часть шагов пропустилась из-за уже-сделанного — это не ошибка.

## Почему такая отсечка

Первичная альтернатива — «один большой универсальный скрипт, который различает платформу сам». Она отклонена по двум причинам:

1. **Hardware-шаги часто требуют GUI-диалога или физического доступа** (Full Disk Access, Wi-Fi настройки через GUI на Monterey, выход в Recovery Mode для smc reset). Автоматизировать это честно нельзя — можно только обмануть себя.
2. **Hardware-шаги редки по сравнению с universal**. Hardware проходится при покупке машины или при миграции на новую платформу — раз в годы. Universal ставится на каждую новую машину/пользователя и должен быть быстрым. Смешение дискриминирует оба пути.

## Практическая проверка границы

Если вы редактируете скрипт из `bootstrap/scripts/` и появляется проверка вида `if [ "$(uname)" = "Darwin" ]` — **стоп**. Скрипт либо должен быть platform-agnostic через абстракцию (например, `$SECRET_GET_CMD` устанавливается в hardware-runbook), либо переехать в `bootstrap/hardware/<platform>/` как отдельный артефакт.

Единственное допустимое платформо-различающее место — `bootstrap/universal-setup.sh`, и только для **выбора какой hardware-runbook проверить** («если запуск на Darwin, проверь что `mac-mini-runbook passed=true` флаг есть в `~/.config/claude-mini/platform.done`»).
