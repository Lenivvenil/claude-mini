# Runbook: пятничная maintenance

## Раз в неделю (пятница вечером или в субботу)

### 1. Health check

```bash
mini-health
```

Должно быть zero failures и меньше трёх warnings. При failures — разбираемся сразу, не откладывая.

### 2. Backlog grooming

В активных проектах:
```bash
cd ~/projects/<project>
claude --model sonnet
# внутри Claude:
/backlog-review
```

Агент `backlog-groomer` предложит triage (merge duplicates, reprioritise, close stale). Примени те предложения, с которыми согласен — агент сам не мутирует.

### 3. Project health

В каждом активном репо:
```
/project-health
```

Генерирует `docs/metrics/health-YYYY-WW.md`. Проверь пороги:
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
# Claude Code
claude --version
# Если есть новее — обнови

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
