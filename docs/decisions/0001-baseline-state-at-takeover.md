# 0001. Baseline state at takeover

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: architecture, bootstrap, baseline

## Context and Problem Statement

Проект `claude-mini` создаётся не с нуля. Ему предшествовала серия сессий по настройке Mac mini 2018 под Claude Code, миграция на enterprise workflow (14-day path), и end-to-end smoke-test на `Lenivvenil/venil-smoketest-20260420`. Все эти решения приняты неявно или разбросаны по документам вне этого репо (`mac-mini-claude-code-setup.md`, `mini-enterprise-workflow-state.md`, `Claude_Code_Enterprise_Workflow.md`). Без baseline-ADR они не существуют как decisions в формальном смысле: через 6 месяцев кто-то (включая нас) откроет debate заново.

Этот ADR фиксирует контекст-как-есть на момент рождения репо, чтобы служить якорем для последующих ADR.

## Decision Drivers

* Отсутствие baseline = невозможность различить «это давно так» и «это надо переосмыслить».
* Документы-источники (в `mac-mini-claude-code-setup-final.md` и `mini-enterprise-workflow-state.md`) смешивают hardware, universal и decisions — их нельзя прямо импортировать как ADR.
* При миграции на Linux или при подключении второго оператора baseline-ADR — единственный способ быстро понять что принято, а что открыто.

## Considered Options

* **Option A: Импортировать существующие документы как есть в `docs/decisions/` разбив на ADR вручную.** Каждый технический выбор → отдельный ADR.
* **Option B: Один ADR-baseline, перечисляющий принятое-как-есть без детальной защиты каждого пункта; детальные ADR пишутся только для решений, которые ожидается пересмотреть.**
* **Option C: Не писать ADR-baseline; начать писать ADR только для новых решений, принимаемых в этом репо.**

## Decision Outcome

Chosen option: **Option B**, потому что (1) полное импортирование (A) занимает недели и воссоздаёт обоснования задним числом, что нарушает принцип «ADR пишется до решения, не после» из `docs/principles.md`; (2) отсутствие baseline (C) создаёт вакуум, в котором будущие решения будут бесконечно спрашивать «а почему базовая архитектура такая». Option B — компромисс: baseline документирует что-есть без back-rationalization, ключевые решения получают отдельные ADR.

### Positive Consequences

* Будущие ADR имеют точку отсчёта.
* Вновь пришедший в проект видит границы «данности» и «открытого».
* Не требует многодневного рерайтинга обоснований.

### Negative Consequences

* Этот ADR — не MADR 4.0 в строгом смысле: для большинства пунктов «Считавшихся Опций» не было в формальном процессе; они накопились органически.
* Откладывается работа по decomposition: часть будущих ADR будет рассматривать пункты из этого списка как «данность», что может скрыть слабости раннего выбора.
* При миграции (например, на Linux) придётся повторно оценить baseline — то, что сейчас задаётся данностью.

## Baseline inventory (на 21 апреля 2026)

Следующие выборы принимаются как данность. Каждый может быть открыт для пересмотра через отдельный ADR.

**Hardware / OS:**

* Mac mini 2018 Intel i7 32 GB RAM (детально см. `bootstrap/hardware/mac-mini-2018.md`)
* macOS Sequoia 15.7.5
* Headless-режим через Tailscale SSH

**AI стек:**

* Claude Code native binary (`~/.local/bin/claude`) v2.1.114+
* Claude Max подписка, Opus 4.7 (1M context) как advisor, Sonnet 4.6 как main loop
* Codex CLI через ChatGPT Plus для two-voice review (pinned model `gpt-5.2`)

**Tooling:**

* Homebrew `/usr/local` (Intel path)
* mise для runtime management (Python 3.13, Go 1.24, Node 22)
* uv 0.11.7 для Python проектов
* ripgrep, jq, starship, Ghostty

**Secrets:**

* macOS Keychain + age 1.3.1 / sops 3.12.2
* `SOPS_AGE_KEY_FILE` экспортирован в `~/.zshrc`

**MCP servers (user-scope):**

* Serena (uvx) — семантическая навигация
* GitHub (HTTP, PAT из Keychain)
* Context7 (HTTP, без auth)

**Claude Code config:**

* RTK 0.37.1 как PreToolUse hook на Bash
* deny-rules: `.env*`, `secrets/**`, `~/.ssh/**`, age-key paths
* auto-mode + `disableBypassPermissionsMode=true`

## Confirmation

Baseline подтверждается тем, что `./bootstrap/universal-setup.sh --check` на чистой машине (после hardware-runbook) возвращает exit 0 и сообщает «no drift from baseline». Автоматический тест добавляется в CI как job `baseline-verification`.

## Re-visit Trigger

Этот ADR пересматривается или расширяется при:

* Миграции на новую hardware-платформу (например, Linux после 2027)
* Мажорном обновлении Claude Code с изменением расположения конфигурации
* Появлении официального Anthropic tooling'а, который вытесняет часть этого baseline (например, нативный governance)
* Смене модели подписки (Plus → Business, или Claude Max → Enterprise)

## Links

* Архитектурный overview: `../architecture/overview.md`
* Слои: `../architecture/layers.md`
* Источники: внешние документы `mac-mini-claude-code-setup-final.md`, `mini-enterprise-workflow-state.md`, `Claude_Code_Enterprise_Workflow.md` (из project knowledge)
