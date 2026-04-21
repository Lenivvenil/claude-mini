# 0005. Two-voice code review with Codex on ChatGPT Plus

* Status: accepted
* Date: 2026-04-21
* Deciders: venil
* Tags: quality, review, cost

## Context and Problem Statement

Single-model review имеет систематические слепые пятна — класс ошибок, которые одно модель-семейство распознаёт плохо, а другое ловит сразу. Для серьёзных личных проектов (где в случае бага переделывать некому) второе независимое мнение повышает качество за нулевую дополнительную стоимость при наличии уже оплаченной ChatGPT Plus подписки с Codex CLI через sign-in-with-ChatGPT (не API billing).

## Decision Drivers

* Independent model family — GPT-5.2/5.3 и Claude Sonnet/Opus ловят разные классы багов.
* Zero marginal cost — ChatGPT Plus уже оплачен на персональный аккаунт.
* Plus-OAuth нестабилен для newest Codex models (intermittent "model not supported" на gpt-5.3-codex per GitHub issues openai/codex#14181, openai/codex#14735) — нужен graceful degradation.
* Лимит ChatGPT Plus: 10-25 Code Reviews per week — hard cap, который может исчерпаться при интенсивной неделе.

## Considered Options

* **Option A: Single-voice, только `/review` от Claude.** Быстро, без graceful degradation issues.
* **Option B: Two-voice Claude + Codex Plus с hard dependency.** Если Codex упал — блокировка merge.
* **Option C: Two-voice с graceful degradation.** Codex упал → open `type:deferred-review` issue, merge не блокируется. Pinned model `gpt-5.2` (стабильнее чем gpt-5.3-codex).
* **Option D: Two-voice Claude + local Qwen3-Coder.** Нет внешних зависимостей, но на Intel Mac mini 3-8 tokens/sec — painful.

## Decision Outcome

Chosen option: **Option C**, с Option D как fallback после нескольких подряд Plus-квота-боям. Graceful degradation критична: без неё Codex-flake блокирует весь pipeline, и это нарушит четвёртую директиву `docs/principles.md` ("knowledge в инструментах"), превратив review-стадию в источник обмана вместо гейта качества.

Pinned `gpt-5.2` стабильнее, чем `gpt-5.3-codex`, — жертвуем чуть меньшим качеством ради предсказуемости. Model-pin в `~/.codex/config.toml`, не hard-coded в скриптах.

### Positive Consequences

* Паттерн уже подтверждён на smoke-test'е: Codex нашёл реальный miss (`pytest` в `pyproject.toml`), который `/review` пропустил.
* Нулевая дополнительная стоимость (Plus уже оплачен).
* Graceful degradation: Codex flake = `type:deferred-review` issue, не блокирует работу.
* `/review` + `/codex-review` агрегируются — Claude видит findings Codex и может откликнуться на расхождения, что повышает engagement обоих ревьюеров.

### Negative Consequences

* Plus limits (10-25 reviews/week) ставят верхнюю границу — при интенсивной работе неделя может закрыться quota-ом, и несколько PR пойдут без two-voice.
* Pinning на `gpt-5.2` жертвует качеством newest Codex; regression не обнаружится пока модель не вернётся.
* Возможная перегрузка findings от двух ревьюеров — при расхождении по minor-пунктам человек теряет время на разрешение.
* Дополнительный внешний сервис в критическом пути — Plus downtime эффективно делает часть PR «недопроверенными».

## Confirmation

Критерий эффективности: за 30 дней работы Codex нашёл ≥ 1 не-false-positive в PR, который `/review` пропустил. Если нет — two-voice не оправдывает себя, возврат к Option A. Если да — продолжать.

Операционный критерий: количество `type:deferred-review` issues < 20% всех PR — иначе Plus flake слишком частый, и мы работаем фактически без второго ревью. При превышении — начать испытание Option D (локальный Qwen3-Coder) как замену.

## Re-visit Trigger

* Anthropic выпускает primitive для multi-provider review (например, Claude Code нативно умеет звать OpenAI).
* Опубликованы надёжные бенчмарки, которые показывают что Plus-stable Codex `gpt-5.2` значимо хуже нового (тогда смена pin).
* Локальный Qwen3-Coder (или аналог) становится производительным на доступном железе (например, апгрейд на Mac mini M5 с NPU).
* `type:deferred-review` issues превышают 20% — Plus-OAuth flake перестал быть редкостью.

## Links

* `graceful-degradation` реализация: `bootstrap/scripts/review-codex.sh`
* Plus model pin: `bootstrap/templates/codex-config.toml`
* GitHub issues по Plus-OAuth flake: openai/codex#14181, openai/codex#14735
