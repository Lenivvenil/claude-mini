# Anti-patterns

Накопленный реестр ленивых решений, которые LLM воспроизводит повторно.
Источник записей — реактивные пинки оператора (Принцип 4).

**Как добавить запись:** при каждом manual catch — добавить строку в Ranked summary и раздел ниже в том же коммите. `commit-msg-governance.sh` напоминает об этом если коммит содержит code-файлы, а файл не трогался на ветке. Формат: заполни все шесть полей (Pattern, Frequency, Severity, Detectability, Detector, Example, Fix); выставь Score по формуле; пересортируй Ranked summary по убыванию Score.

*`adversarial-critic` (`bootstrap/agents/adversarial-critic.md`, issue #123) загружает этот файл в context автоматически при каждом `/review`.*

---

## Scoring rubric

Each field is an integer **1–5**, assigned by the operator at time of entry:

| Field | 1 | 3 | 5 |
|---|---|---|---|
| **Frequency** | Seen once | Seen 2–4× | Seen 5+ times or in every sprint |
| **Severity** | Cosmetic, caught immediately | Needs rework, passed initial review | Would reach production undetected |
| **Detectability** | Caught by deterministic gate | Requires LLM critic | Requires human re-read or escapes all gates |

**Score = Frequency × 2 + Severity × 2 + Detectability**  
Maximum score = 25. Patterns are listed in descending score order.

---

## Ranked summary

| # | Pattern | Freq | Sev | Det | Score |
|---|---|---|---|---|---|
| 1 | `truncated-file` | 4 | 5 | 4 | **22** |
| 2 | `symptom-fix-not-root` | 4 | 4 | 4 | **20** |
| 3 | `narrow-special-case` | 3 | 4 | 4 | **18** |
| 4 | `adr-drift` | 3 | 4 | 3 | **17** |
| 5 | `hedging-in-plan` | 4 | 3 | 3 | **17** |
| 6 | `todo-without-ticket` | 5 | 2 | 1 | **15** |
| 7 | `commented-block` | 4 | 2 | 1 | **13** |

---

## Pattern entries

---

### truncated-file

**Frequency:** 4 | **Severity:** 5 | **Detectability:** 4 | **Score:** 22

**Detector:** Read the file immediately after Write/Edit. If file is shorter than
expected or ends abruptly, flag. Adversarial-critic checks for files < 10 lines
where the plan implied 30+. No deterministic gate catches this reliably.

**Example:**  
Plan says "write complete bootstrap/hooks/stop-hook.sh with 6 test cases."
Model writes the file, 8 lines, ends at `set -uo pipefail`. Claims "done."
Caught by reading the file post-write; model had hit a context limit mid-output
and silently stopped.

**Fix:**  
After every Write/Edit, Read the file back. Assert line count is plausible.
If truncated: re-issue the Write with explicit instruction "write the COMPLETE
file, do not truncate." Root cause: context window pressure causes silent
truncation; model does not signal this.

---

### symptom-fix-not-root

**Frequency:** 4 | **Severity:** 4 | **Detectability:** 4 | **Score:** 20

**Detector:** Adversarial-critic with explicit instruction: "does this fix address
the root cause or only the observable symptom?" No deterministic gate.

**Example:**  
Hook fails on empty stdin with "jq: null". Fix: add `|| true` to silence the
error. Root cause: caller passes empty string, not empty JSON object. Correct
fix: validate stdin before parsing, return early with log message.
Symptom fix would pass all tests; root cause fix prevents the class of errors.

**Fix:**  
Before writing the fix, ask: "what input condition causes this?" Change the
condition, not the output. Add a test that reproduces the root cause input.

---

### narrow-special-case

**Frequency:** 3 | **Severity:** 4 | **Detectability:** 4 | **Score:** 18

**Detector:** Adversarial-critic: "does this implementation handle only the example
input or the general case?" Property-based tests (Hypothesis) surface this.

**Example:**  
Plan: "parse commit message to extract issue reference." Implementation uses
`grep -E '#[0-9]+'` on the first line only. All AC examples have the issue ref
in the subject. Test passes. Body-only refs (multi-line messages) silently fail.
Caught when a real commit with `Closes #9` in the body was incorrectly blocked.

**Fix:**  
Read the full message, not just the subject. Write property-based tests that
generate messages with refs in all valid positions. Adversarial-critic prompt
must include "test with ref in body, not just subject."

---

### adr-drift

**Frequency:** 3 | **Severity:** 4 | **Detectability:** 3 | **Score:** 17

**Detector:** adr-reviewer agent compares implementation diff against the merged
ADR. But this fires only if adr-reviewer is invoked — it is not automatic.
Pre-commit hook (Rule 3) enforces ADR reference on decision-type staged changes
but does not verify implementation matches ADR content.

**Example:**  
ADR-0011 specifies `exit 1` for denied commits. Implementation uses `exit 2`
(JSON output pattern from PostToolUse hook, copied from wrong template).
Both exit codes block the commit; test passes; drift is invisible until a
consumer checks the exit code explicitly.

**Fix:**  
After /implement, run adr-reviewer against every ADR referenced in the plan.
Assert each §Decision Outcome constraint is satisfied in the diff.
Root cause: model copies from the most recent similar file rather than reading
the ADR that governs the current context.

---

### hedging-in-plan

**Frequency:** 4 | **Severity:** 3 | **Detectability:** 3 | **Score:** 17

**Detector:** `advisor()` pre-check (Principle 1 mandate). No current
deterministic gate — `lint-prompts.sh` only checks `bootstrap/agents/`,
`bootstrap/commands/`, `bootstrap/skills/` and does not scan `plan.md`.
A future `lint-prompts.sh` extension for `plan.md` hedging terms would
lower Detectability to 1.

**Example:**  
plan.md §4: "The hook could use either `exit 0` or `exit 1` depending on
context." No decision is made. /implement picks exit 0 arbitrarily. Caught
at /review when reviewer asks "which did you choose and why?"

**Fix:**  
Principle 1: no sentence in plan.md ends without a decision. Replace every
"could/might" with either "(a) correct choice + rationale" or "(b) `not known
— empirical test needed: <describe test>`." Advisor flags this during
plan pre-check; fix plan.md before /implement.

---

### todo-without-ticket

**Frequency:** 5 | **Severity:** 2 | **Detectability:** 1 | **Score:** 15

**Detector:** semgrep rule `llm-todo-without-ticket`
(`bootstrap/templates/.semgrep/llm-antipatterns.yaml`). Fires on `TODO` or
`FIXME` without `#NNN` or a URL on the same line. Deterministic gate, layer 1
of /review.

**Example:**  
`# TODO: handle edge case where stdin is empty` committed without issue ref.
Next session has no trace of this. The edge case is never handled.

**Fix:**  
Every TODO in committed code must reference an issue: `# TODO(#124): handle
edge case`. If no issue exists, create one first. Semgrep gate blocks commit
if rule fires.

---

### commented-block

**Frequency:** 4 | **Severity:** 2 | **Detectability:** 1 | **Score:** 13

**Detector:** semgrep rule `llm-commented-block`
(`bootstrap/templates/.semgrep/llm-antipatterns.yaml`). Fires on 5+ consecutive
lines starting with `#`. Known false-positive on multi-line documentation
blocks — can be suppressed per-file with `# nosemgrep`. Deterministic gate,
layer 1 of /review.

**Example:**  
Old implementation of a hook section left in as a comment "for reference."
Six lines, preceded by the new implementation. No indication of why it's kept.
Committed as-is. Reader cannot tell if the commented block is intentional
backup or forgotten cleanup.

**Fix:**  
Delete commented-out code. If it matters, it's in git history. If keeping it
is intentional (e.g., disabled-by-design escape hatch), replace with a single
explanatory comment: `# Disabled: <reason> (re-enable via <condition>)`.
Root cause: model defaults to preservation over deletion under uncertainty.
