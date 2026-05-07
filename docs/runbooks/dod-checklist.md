# Runbook: Definition of Done checklist

**Для кого:** PR-автор перед merge. **Когда:** после `/review` и `/codex-review`, перед `gh pr create`.

Изменение **Done** когда все условия истинны:

- [ ] ADR открыт и смерджен, если изменение архитектурно-значимо
- [ ] Domain-доки обновлены, если изменилась граница BC или термин
- [ ] Unit-тесты написаны; integration-тесты для cross-BC путей; coverage ≥ project floor (дефолт 80%)
- [ ] `/review` (Claude) одобрил
- [ ] `adversarial-critic` запущен внутри `/review` (сканирует 8 классов LLM-ленивых паттернов, см. `docs/runbooks/feature-pipeline.md §6`); BLOCK-findings устранены ИЛИ задокументированы как осознанный компромисс в PR-треде
- [ ] `/codex-review` (Codex) одобрил ИЛИ создан `type:deferred-review` issue с обоснованием graceful degradation
- [ ] Разногласия между Claude и Codex разрешены в PR-треде (консенсус или фиксация disagreement)
- [ ] Human self-review выполнен
- [ ] Security scans clean: `uv pip audit` / `cargo audit` / `npm audit --audit-level=high` / `govulncheck` — в зависимости от языка
- [ ] Docs обновлены: README (при публичных изменениях), relevant runbook, CHANGELOG (через release-please)
- [ ] Human-facing docs reviewed: если PR меняет `docs/runbooks/`, `docs/architecture/`, `docs/principles.md`, `README.md` — `docs-reviewer` одобрил ИЛИ изменений в этих путях нет
- [ ] Reliability reviewed: если PR прод-bound (`bootstrap/`, `.github/workflows/`, `.git/hooks/`, label `prod-bound`) — `reliability-reviewer` одобрил ИЛИ изменений в прод-bound путях нет
- [ ] CI зелёный на всех required jobs
- [ ] Conventional Commits; governance-hook проверку прошёл
- [ ] PR body ссылается на issue (`Closes #NNN`) и на ADR (`Implements docs/decisions/NNNN-*.md`) если был

Этот чек-лист копируется в `pull_request_template.md` и проверяется на каждом PR.
