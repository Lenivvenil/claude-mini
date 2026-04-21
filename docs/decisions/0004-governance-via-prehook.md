# 0004. Enforce commit governance via PreToolUse hook with absolute path

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: governance, security, hooks

## Context and Problem Statement

Четвёртая директива `docs/principles.md` — «автоматизировать только низкорискованное». Commit в main-ветку с неправильным сообщением или без issue-ref — высокорисковое событие: портит traceability, ломает release-please/changelog, затрудняет archaeology через 6 месяцев. Нужен механизм, который не может быть обойдён случайно.

## Decision Drivers

* Human memory ненадёжен под давлением — люди забывают добавить `#NNN` когда спешат.
* Claude под `autoMode` будет коммитить то, что ему даёт человек; если человек не следил — plain bad commit.
* Детерминированность важнее интеллекта: «коммит соответствует CC-regex» — да/нет, не интерпретация.
* Smoke-test показал ложно-положительный pass (PreToolUse hook с тильдой в path не выполнялся, но Claude не коммитил плохого) — значит нужна проверка с заведомо плохим input'ом.

## Considered Options

* **Option A: Полагаться на Claude следовать `CLAUDE.md` без enforcement.** Доверие к instruction-following.
* **Option B: PreToolUse hook на matcher `Bash`, проверяющий каждый `git commit`.** Jetisoning bad commit возвратом `{"hookSpecificOutput": {"permissionDecision": "deny"}}`.
* **Option C: Git-level `commit-msg` hook через `core.hooksPath`.** Работает и при прямом `git commit` из терминала минуя Claude.
* **Option D: Оба: B + C.** Двойная защита.

## Decision Outcome

Chosen option: **Option B как phase 1, Option D как target state**. PreToolUse hook (B) закрывает 95% случаев — коммиты идут через Claude. Git-level hook (C) добавляется после того, как workflow стабилизирован — он более инвазивный (требует `core.hooksPath` на каждом репо) и может мешать неожиданно. Option A отклонён: smoke-test показал, что Claude корректно писал хорошие commits не из-за CLAUDE.md, а из-за случайности. Без enforcement ложно-положительный вывод неизбежен.

Критично: **path в settings.json должен быть абсолютным** (`/Users/venil/.claude/hooks/pre-commit-governance.sh`), не с тильдой. Claude Code передаёт `command` напрямую exec, без shell expansion — тильда остаётся literal и hook молча фейлится (exit 0 без блокировки).

### Positive Consequences

* Плохой commit через Claude детерминированно блокируется.
* Правила (CC prefix, issue-ref, ADR-ref) видны в одном файле — легко аудировать.
* `disableBypassPermissionsMode=true` не позволяет даже `--dangerously-skip-permissions` обойти.

### Negative Consequences

* Не покрывает direct `git commit` из терминала — известный gap до phase 2 (C).
* Ложно-положительные: редкие валидные коммиты (например, urgent hotfix без issue) блокируются. Escape valve — временно закомментировать hook.
* Отладка сложнее: если hook сломан, Claude в logs видит `exit 2` без stderr к пользователю напрямую.
* Диагностика требует ручного smoke-test с плохим input'ом — нельзя доверять happy path verification.

## Confirmation

Smoke-test с заведомо плохим input'ом:

\`\`\`bash
echo '{"tool_input":{"command":"git commit -m \"bad msg\""},"cwd":"'"$PWD"'"}' \
  | /Users/venil/.claude/hooks/pre-commit-governance.sh; echo "exit=$?"
# exit=2 — hook рабочий
# exit=0 — hook сломан
\`\`\`

Добавлено как check в `mini-health` script. Запускается раз в неделю как часть `/project-health`.

## Re-visit Trigger

* Claude Code получает native governance (commit-templates, validation rules в `settings.json`). Тогда hook становится fallback.
* Количество ложно-положительных блокировок > 2-3 на 100 коммитов — правила слишком жёсткие.
* Выход на командную работу >1 человек — phase 2 (D) становится обязательным для защиты от не-Claude коммитов.

## Links

* Hook код: `bootstrap/hooks/pre-commit-governance.sh`
* Diagnostics: `mini-enterprise-workflow-state.md §5.1` (tilde expansion gotcha из project knowledge)
* `../principles.md#definition-of-done`
