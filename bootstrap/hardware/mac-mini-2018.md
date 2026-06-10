# Hardware runbook — Mac mini 2018 (Intel, macOS Sequoia)

> Эту инструкцию нужно пройти **вручную** один раз при настройке новой машины. После прохождения создай flag:
>
> ```bash
> mkdir -p ~/.config/claude-mini
> echo "mac-mini-2018-sequoia-$(date +%Y-%m-%d)" > ~/.config/claude-mini/platform.done
> ```
>
> Только после этого `./bootstrap/universal-setup.sh --install` согласится работать.

## Профиль железа

- Mac mini 2018, Intel i7, 32 GB RAM
- macOS Sequoia 15.7.5 (актуальная версия на апрель 2026)
- Headless (через Tailscale SSH), клавиатуры/монитора только для первичной настройки

## Почему эта часть не автоматизирована

Шаги ниже требуют одного или нескольких из: GUI-диалогов (Full Disk Access), физического доступа (Recovery Mode, первичный login), OS-specific secret stores (Keychain), лицензионного подтверждения (macOS EULA), или интерактивной аутентификации (gh auth, Tailscale sign-in). Автоматизировать честно нельзя. Не пытайся.

## Порядок шагов

### 1. Базовая macOS-настройка (физический доступ к машине)

1. Установить / обновить macOS до Sequoia 15.7.5
2. Создать пользователя `venil` как admin
3. **System Settings → General → Sharing:**
   - ✓ Remote Login (SSH) → Allow access for: `venil`
   - ✓ Screen Sharing
4. **System Settings → Network:**
   - Настроить Wi-Fi `TP-Link_46BB` (или актуальный SSID)
   - Или Ethernet
5. **System Settings → Privacy & Security → Full Disk Access:**
   - ✓ Terminal.app
   - ✓ sshd (если спрашивает при первом SSH)

**Проверка:** из другой машины `ssh venil@<IP>` проходит с паролем.

### 2. Homebrew (Intel path!)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Важно:** на Intel Mac mini путь будет `/usr/local/bin/brew`, не `/opt/homebrew/bin/brew` (последнее только для Apple Silicon). Не смешивать.

Добавить в `~/.zshrc`:
```bash
eval "$(/usr/local/bin/brew shellenv)"
```

### 3. Command Line Tools

```bash
xcode-select --install
```

GUI-диалог. Нажать "Install". Дождаться установки (5-10 минут).

Версия на момент написания: **CLT 16.4**.

### 4. Основные CLI утилиты

```bash
brew install ripgrep jq starship mise
```

### 5. Node.js через pkg (НЕ через brew!)

**Критично.** На Intel Mac mini brew-компиляция Node.js падает на z3/llvm зависимостях. Используй официальный `.pkg`:

```bash
# Скачать Node 22 LTS pkg с nodejs.org и установить через GUI
open "https://nodejs.org/dist/latest-v22.x/"
# Выбрать .pkg для darwin-x64
```

**Проверка:** `node -v` возвращает v22.x.x, `which node` → `/usr/local/bin/node`.

### 6. mise + runtime pinning

```bash
# Activate mise в shell
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc

# Пин глобальных runtime
mise use -g python@3.13 go@1.24
mise install
```

### 7. uv (Python package manager)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Проверка: `uv --version` → `uv 0.11.x` или новее.

### 8. Claude Code (native binary)

```bash
curl -fsSL https://install.claude.ai/claude | sh
# Устанавливается в ~/.local/bin/claude
```

Добавить в `~/.zshrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

Аутентификация:
```bash
claude auth login
# Откроет браузер или предложит device code flow для headless
```

Используй личный Claude Max аккаунт (`venilman@gmail.com` в текущей конфигурации).

### 9. Codex CLI (для `/codex-review`)

```bash
npm i -g @openai/codex
codex login --device-auth
# Откроется URL + code, open в браузере на другой машине, sign-in ChatGPT Plus
```

**Важно:** через обычный `codex login` без `--device-auth` из SSH не пройдёт OAuth flow.

Создать `~/.codex/config.toml`:
```bash
mkdir -p ~/.codex
cat > ~/.codex/config.toml <<'EOF'
model = "gpt-5.5"

[auth]
preferred = "chatgpt"
EOF
```

### 10. GitHub CLI

```bash
brew install gh
gh auth login
# → GitHub.com → HTTPS → Login with browser → code → paste
```

Рекомендую настроить PAT с минимальным scope и сохранить в Keychain:
```bash
# PAT scope: repo, read:org, workflow
security add-generic-password -a venil -s gh_pat -w <TOKEN>
```

### 11. Secrets: age + sops + Keychain

```bash
brew install age sops
```

Сгенерировать age-key:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

**Важно:** забэкапь public key из файла в Apple Passwords или Notes — без privat key зашифрованные `.env.sops.json` файлы не расшифровать.

В `~/.zshrc`:
```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Это **обязательно** — mise-встроенный sops-reader не знает дефолтный macOS-путь.

### 12. Tailscale (system daemon, не App Store)

App Store-версия Tailscale не подходит для headless pre-login startup. Нужна system daemon версия:

```bash
brew install tailscale
sudo tailscale install-system-daemon
sudo tailscale up
# → откроется URL для sign-in, authorise
```

Проверить: `tailscale ip -4` возвращает IP вида `100.x.x.x`.

### 13. Screen Sharing (опциональный VNC на local)

На Monterey+ включение через System Settings требует GUI-клика. Если ты уже на SSH headless:

```bash
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
    -activate -configure -access -on \
    -configure -allowAccessFor -specifiedUsers \
    -configure -users venil -privs -all \
    -restart -agent -menu
```

Подключение с другой машины на local: `open vnc://<local-ip>`.

### 14. Power management (всегда on)

```bash
# Отключить sleep
sudo pmset -a sleep 0 displaysleep 10

# Автоперезапуск после power loss
sudo pmset -a autorestart 1

# Wake on LAN (для wake из sleep через Tailscale)
sudo pmset -a womp 1
```

### 15. LaunchAgents (tmux, media services)

Создать `~/Library/LaunchAgents/local.tmux-main.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.tmux-main</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/tmux</string>
        <string>new-session</string>
        <string>-d</string>
        <string>-s</string><string>main</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/local.tmux-main.plist
```

Аналогично для Plex, Transmission, caffeinate — см. existing конфигурацию в `mini-health.sh`.

### 16. Ghostty terminal + terminfo

Если работаешь через Ghostty:
```bash
# На локальной машине (Mac) — terminfo уже есть
# На удалённой mini — пробросить terminfo:
infocmp -x | ssh mini tic -x -
```

Без этого `nano` и другие ncurses-утилиты на mini будут падать с "xterm-ghostty: unknown terminal type".

**Known gotcha:** Ghostty + SSH paste ломает multiline backslash-continuations (превращает в literal `\n`). Workaround: для длинных команд используй heredoc или `vim :set paste`.

### 17. Firewall для Plex (если нужен media server)

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
    --add "/Applications/Plex Media Server.app"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw \
    --unblockapp "/Applications/Plex Media Server.app"
```

### 18. Проверка окружения

```bash
# Все должны вернуть installed version
brew --version
node --version
python --version  # через mise
go version
uv --version
claude --version
codex --version
gh --version
tailscale version
age --version
sops --version
jq --version
rg --version
```

### 19. SSH connection stability (keepalive)

SSH connections drop during long advisor calls (30–90s silent) when the client has no keepalive configured. Apply on both sides.

**На mini (server-side) — `/etc/ssh/sshd_config`:**

Add or update (do not append a duplicate) the following lines:
```
ClientAliveInterval 60
ClientAliveCountMax 3
```

Restart sshd:
```bash
sudo launchctl kickstart -k system/com.openssh.sshd
```

Verify effective config (first-match wins; checks include files):
```bash
sudo sshd -T | grep -i clientalive
# Expected: clientaliveinterval 60 / clientalivecountmax 3
# Total detection window: 3 minutes
```

**На MacBook (client-side) — `~/.ssh/config`:**

Add or update the `Host mini` block (do not append a duplicate block):
```
Host mini
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

**Проверка через preflight:** `mini-preflight.sh` проверяет наличие `ClientAliveInterval` в sshd config и покажет `✓` если всё верно.

### 20. Создать platform.done flag

После успешного прохождения всех предыдущих шагов:

```bash
mkdir -p ~/.config/claude-mini
cat > ~/.config/claude-mini/platform.done <<EOF
platform: mac-mini-2018
os: macOS Sequoia 15.7.5
setup_date: $(date +%Y-%m-%d)
hostname: $(hostname)
EOF
```

**Теперь** можно запускать:
```bash
cd ~/projects/claude-mini
./bootstrap/universal-setup.sh --check
./bootstrap/universal-setup.sh --install
```

## Известные острые углы

**Keychain lock при SSH login.** После каждого `ssh venil@mini` Keychain не разблокирован автоматически. Нужно:
```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```
Один раз на сессию SSH. Встроено в `mini-preflight`.

**Heredoc обрезание через Ghostty+SSH.** Для файлов > 100 строк используй `vim :set paste` вместо heredoc при редактировании файлов на mini через SSH. Heredoc в bash_tool из Claude Code работает — обрезание только при интерактивной SSH-вставке.

**macOS major upgrade через SSH блокируется GUI-диалогами.** Unrelated apps (Transmission "Donate" popup, Zoom update) могут блокировать перезагрузку. Перед upgrade — закрыть все GUI apps руками через `osascript`, и держать открытым второй SSH window на случай если первый умрёт.

**Homebrew для Node.js на Intel.** НЕ устанавливай Node через brew на Intel Mac mini. Зависимости z3/llvm компилируются часами и часто падают. Используй только `.pkg` с nodejs.org.

## Миграция на Linux (будущее)

Когда перейдёшь на Linux, этот runbook **не применяется**. Вместо него — `linux-<distro>.md` (TBD). Аналоги компонентов:

| macOS | Linux |
|---|---|
| Homebrew | apt / pacman / dnf |
| LaunchAgents | systemd user units |
| Keychain | libsecret / gnome-keyring |
| `pmset` | systemd-logind |
| Tailscale daemon | systemd service |
| `security` CLI | `secret-tool` |

Universal layer (`~/.claude/`, ADR-schema, commands) остаётся без изменений.
