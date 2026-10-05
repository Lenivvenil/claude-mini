# Runbook: пятничная maintenance

## Раз в неделю (пятница вечером или в субботу)

### 1. Health check

Команда запускается для каждого проекта, где включён MACH.
```bash
~/projects/mach/setup/harness verify --project ~/projects/<project>
```

Она проверяет оба слоя. На машине это программы git, python3, jq, claude, gh, codex, node и вход в gh, claude и codex. В проекте это включённый плагин и строки в git exclude. Код выхода 0 значит, что всё готово, а код 5 значит, что не готов обязательный пункт. Причину и способ исправить отчёт пишет в разделах «Broken» и «Not done», которые при `output.language: ru` называются «Сломано» и «Не сделано». Разбираемся сразу, не откладывая.

Службы Mac mini setup не проверяет, поэтому их смотрим отдельно.
```bash
launchctl list | grep -iE 'tmux|plex|transmission|caffeinate'
```

### 2. Backlog grooming

В активных проектах:
```bash
cd ~/projects/<project>
claude
# внутри Claude, в проекте с включённым плагином MACH:
/mach:backlog-review
```

Роль `backlog-groomer` предложит разбор: дубли, приоритеты, устаревшие задачи. Выполняются только те команды, которые ты одобрил.

### 3. Project health

В каждом активном репо:
```
/mach:project-health
```

Отчёт приходит в чат. Проверь пороги:
- Review cycle time P90 < 48h
- Open issues P90 age < 60 days
- Open ADRs < 3

Выше — красный флаг. Открой issue «housekeeping: address backlog staleness».

### 4. Dependency updates

По каждому репо:
```bash
gh api repos/{owner}/{repo}/dependabot/alerts \
    --jq '.[] | {severity: .security_advisory.severity, package: .dependency.package.name}'
```

HIGH/CRITICAL → action той же недели.

### 5. Claude Code / Codex updates

```bash
# версия Claude Code на машине и версия, закреплённая в CI
claude --version
grep -o 'claude-code@[0-9.]*' ~/projects/mach/.github/workflows/ci.yml
```

Если на машине версия новее закреплённой, прогони в клоне MACH `claude plugin validate plugin --strict` и тесты из `AGENTS.md`. Новая версия Claude Code уже ломала харнесс, когда 2.1.289 запретила имена плагинов на `claude-` (ADR-0034). Если всё зелёное, подними версию в `ci.yml` отдельным PR `chore(ci): pin Claude Code <версия>`. Если красное, заведи issue с выводом проверки. Пока его не закрыли, плагин на этой версии может работать неправильно, и на остальных машинах Claude Code лучше не обновлять.

```bash
# Codex
npm outdated -g @openai/codex
npm update -g @openai/codex 2>/dev/null

# mise runtime
mise upgrade
```

### 6. macOS updates

```bash
softwareupdate -l
```

Если есть обновления — аккуратно через GUI (не через SSH при критичной сессии).

### 7. Disk space check

```bash
df -h /
du -sh ~/Movies ~/Downloads ~/.npm 2>/dev/null
```

Plex и Transmission могут незаметно съесть диск.

### 8. Backup verification

- [ ] age private key забэкаплен в Apple Passwords / Notes
- [ ] iCloud Keychain синкает (проверь с другой Apple-устройства)
- [ ] Все важные репо запушены на origin

### 9. Retrospection (опционально)

В `~/notes/weekly-YYYY-WW.md`:
- Что сработало
- Что не сработало
- Что попробую в следующую неделю

Можно попросить Claude собрать скелет:
> Опираясь на git log за неделю по всем репо в ~/projects/, составь ретроспективу в ~/notes/weekly-YYYY-WW.md.
