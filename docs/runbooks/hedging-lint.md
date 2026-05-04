# Runbook: hedging-lint false-positive process

**Gate:** `hedging-lint` (Rule H in `pre-commit-governance.sh`, Gate 8 in `verify.sh`)

**Principle:** 1 («размытость — нарушение»)

**Config:** `.semgrep/hedging.yml`

---

## Что делает gate

Сканирует `plan.md`, `STATE.md`, `docs/decisions/*.md` на наличие:
- Запрещённых слов: `maybe`, `possibly`, `could`, `might`, `perhaps`
- `depends` без явного условия ветвления на той же строке

Срабатывает в:
1. **Pre-commit governance hook** — при попытке закоммитить staged target-файлы
2. **verify.sh Gate 8** — внутри `/review` (только изменённые файлы)

---

## Когда gate блокирует законно

Фраза «this might work» или «depends on preferences» в `plan.md` — настоящее нарушение Принципа 1. Перепиши до конкретики:

- «this might work» → «this works when X; fails on Y»
- «depends on context» → «depends when input < 100 then A; when input ≥ 100 then B»

---

## Когда gate блокирует ложно (false positive)

### Кейс 1: Цитируешь banned term как пример (описательный контекст)

Файл описывает правила или содержит список запрещённых слов как примеры.

**Решение:** inline `<!-- nosemgrep: hedging-banned-terms -->` на строке с цитатой.

```markdown
Use `could` sparingly. <!-- nosemgrep: hedging-banned-terms -->
```

Аналогично для `depends`:
```markdown
The word `depends` alone is banned. <!-- nosemgrep: hedging-depends-without-branch -->
```

### Кейс 2: Целый файл содержит banned terms по дизайну (тест-фикстуры, примеры)

Добавь файл в `.semgrepignore` с reason-comment:

```
bootstrap/scripts/test-hedging-lint.sh  # reason: test fixtures contain banned terms by design
docs/runbooks/hedging-lint.md           # reason: runbook quotes banned terms as examples
```

Этот runbook сам добавлен в `.semgrepignore` — см. файл.

### Кейс 3: Нужно `depends` на одной строке, ветвление — на следующей

Правило работает per-line. Перепиши так, чтобы ветвление было на той же строке:

```
# Вместо:
This step depends
when input is valid then A, when invalid then B.

# Напиши:
This step depends when input is valid then A, when invalid then B.
```

---

## Добавление в `.semgrepignore`

Формат:
```
path/to/file  # reason: <почему файл содержит banned terms легитимно>
```

Правила:
1. Reason-comment обязателен (иначе PR блокируется docs-reviewer)
2. Предпочитай inline `<!-- nosemgrep -->` для конкретных строк; `.semgrepignore` — для целых файлов
3. Коммитай `.semgrepignore` в том же коммите, что и исключаемый файл

---

## Диагностика

```bash
# Проверить конкретный файл вручную
bash bootstrap/scripts/hedging-lint.sh ./plan.md

# Проверить все target-файлы разом
bash bootstrap/scripts/hedging-lint.sh ./plan.md ./STATE.md

# Запустить тесты gate'а
bash bootstrap/scripts/test-hedging-lint.sh
```
