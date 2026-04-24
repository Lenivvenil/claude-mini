# First real feature session log

**Date:** 2026-04-24  
**Issue:** #9 — Phase 2 governance: git-level commit-msg hook  
**Epic:** #5 — First real feature through full pipeline end-to-end  
**PR:** #47 (implementation), #43 (ADR 0011)  
**Pipeline time:** ~1 session (~4h including backlog grooming at session start)

---

## Pipeline stages and what happened

### Stage 1: Sub-task selection via solutions-architect

The `/feature 5` orchestrator invoked `solutions-architect` to choose the right sub-task from the Next Up queue. The agent correctly rejected:
- #11 (docs/domain): wrong agent type — domain work goes through `domain-researcher`, not `/adr`
- #41 (shellcheck CI scope): implementation hygiene, ADR would be theater
- #25 (installer --force): valid but secondary to #9

#9 was chosen because it changes the security model (triggers ADR), is meta-perfect (pipeline running on its own governance extension), and has bounded scope.

**What worked:** solutions-architect gave a clear, well-reasoned recommendation with driver prioritisation.  
**Friction:** none at this stage.

---

### Stage 2: /plan

plan.md was drafted correctly on content, but contained two problems caught later:

1. **Mechanism mismatch with the eventual ADR.** plan.md §4 described "Approach B" as setting `core.hooksPath` per-project. The ADR interview produced direct-copy into `.git/hooks/commit-msg` instead — a different mechanism with different observability and rollback semantics. The plan was not updated before `/implement` began; the pre-done advisor caught it.

2. **Banned language.** plan.md used "employer-owned repositories" which is prohibited in this project. The term was corrected to "сторонние репо" during the ADR interview when the operator flagged it. plan.md is `.gitignore`d and did not commit, but the memory entry `feedback_no_employer_mention.md` was created to prevent recurrence.

**ADR numbering catch:** plan.md correctly identified that issue #9 body says "ADR 0009" but slot 0009 is already `feature-branch-pr-flow.md`. Correct number is 0011. This would have caused a naming collision if missed.

**What worked:** plan caught the ADR numbering conflict early.  
**Friction:** plan-to-ADR mechanism drift is a class of error the pipeline doesn't guard against structurally. The plan is written before the ADR, but the ADR interview can change the implementation approach. plan.md should be treated as a living document updated after the ADR finalises — this didn't happen here.

---

### Stage 3: advisor() on plan

The advisor (pre-implement call) surfaced four substantive items:

1. **Missing option F** (`includeIf` conditional git config) — not in plan's considered options, potentially the right answer. Ended up ruled out by operator on the same principle as A.
2. **Rule 4 parity gap** — should the commit-msg hook enforce "no commits to main"? Not addressed in plan. Resolved by operator: no, by design.
3. **Task #8 wrong issue ref** — the commit task said "Closes #5" (the epic), not "Closes #9" (the implementation issue). Caught and fixed.
4. **Multi-line body search** — Rules 2/3 would only scan the subject line if `msg` variable was the stripped subject. Advisor flagged this as a latent bug (would wrongly block commits with ADR refs in the body). Fixed in implementation.

**What worked:** advisor() added genuine value on every call. Items 3 and 4 would have caused real bugs if missed.  
**Friction:** two advisor calls per non-trivial task means the pipeline has a natural checkpoint before and after implementation. This felt right — not excessive.

---

### Stage 4: /adr 0011 interview

The full 7-step interview ran without shortcuts. Two notable findings:

**New principle created.** No existing principle in `docs/principles.md` covered the isolation invariant ("governance only where installer placed it"). The operator formulated Principle §5 *«Scope инструмента ограничен явной установкой»* during the interview. It was added to `principles.md` as part of the ADR PR — this is the correct process (principles evolve through ADRs, not informally).

**Principles.md §5 Материально was wrong.** The ADR PR committed `principles.md` with `core.hooksPath` in the "Материально" line (reflecting an early option), but the actual implementation used direct-copy. This caused a `/review` BLOCK finding later. The error was introduced because `principles.md` was drafted during the ADR interview before the implementation was built. The lesson: the "Материально" section of a principles entry should be written or verified after implementation is done, not during the ADR interview.

---

### Stage 5: @agent-adr-reviewer

APPROVE — no CRITICAL or WARNING findings. One NIT: title not in imperative mood. Fixed immediately.

**What worked:** reviewer gave a confident clean signal in under 2 minutes.  
**Friction:** none.

---

### Stage 6: /implement

Two real bugs caught by the pre-done advisor():

**Bug 1 — subject/body search.** The hook stripped comment lines and extracted the subject (`msg_subject`) but Rules 2 and 3 then searched only `msg_subject`, not the full body. A commit like:

```
feat: add module (#9)

Implements ADR-0011
```

would have wrongly blocked on Rule 3 (ADR ref not found in subject). Fixed by keeping `msg_body` (full de-commented message) for Rules 2/3, using `msg_subject` only for Rule 1 and exemption checks.

**Bug 2 — hardcoded `.git/` path.** The `--hook-this-repo` mode used `[ ! -d ".git" ]` and `DEST_HOOK=".git/hooks/commit-msg"`. This breaks in git worktrees (where `.git` is a file, not a directory) and when invoked from a subdirectory. Fixed by using `git rev-parse --git-dir` throughout.

Both bugs were caught by the mandatory pre-done advisor() call — not by the tests (which only ran from the repo root with a standard `.git/` directory). This validates the advisor × 2 policy for non-trivial tasks.

---

### Stage 7: /review

One BLOCK: `docs/principles.md` §5 "Материально" said `core.hooksPath устанавливается per-project` but implementation uses direct-copy with no `core.hooksPath` call. Fixed.

One SUGGEST (missing `--hook-this-repo` installer tests): fixed, 6 new test cases added.

One NIT (CC regex `\s` vs `[[:space:]]` divergence between the two hooks): fixed, both now use POSIX `[[:space:]]`.

---

### Stage 8: /codex-review

**Skipped twice** — Plus quota timeout (exit 124) on both attempts. Issues #45 and #46 opened as `type:deferred-review`. This is the same systemic problem tracked in issue #42 ("Codex Plus quota exhausted: backlog of 4 deferred reviews").

Two-voice DoD criterion not satisfied. Gap recorded in PR #47 body per ADR-0005 graceful degradation.

---

### Stage 9: Commit + PR

Commit passed governance hook (PreToolUse phase 1) on first try. PR #47 created with full Closes/Implements cross-refs and deferred-review gap documented.

---

## What the pipeline caught (not caught in code review)

| Finding | Stage caught | Severity | Would have shipped? |
|---|---|---|---|
| ADR numbering conflict (0009 taken → 0011) | /plan | BLOCK | Yes — naming collision on first install |
| Missing Approach F (includeIf) in ADR options | advisor() pre-plan | SUGGEST | Omission in ADR, not a runtime bug |
| Task #8 wrong issue ref (Closes #5 not #9) | advisor() pre-plan | BLOCK | Wrong cross-ref in PR |
| Multi-line body search bug (Rules 2/3 miss body refs) | advisor() pre-done | BUG | Yes — valid commits wrongly blocked |
| Hardcoded `.git/` path (breaks worktrees) | advisor() pre-done | BUG | Yes — failure in non-standard repo layout |
| principles.md §5 wrong mechanism | /review | BLOCK | Yes — docs lie about how the tool works |
| Missing installer tests | /review | SUGGEST | Yes — regression risk on `--hook-this-repo` |
| CC regex divergence | /review | NIT | Yes — portability risk on BSD grep |

---

## Gaps found in the pipeline itself

### Gap 1: plan.md and ADR can diverge silently

The plan describes an approach before the ADR interview. The ADR interview can change the approach (it did here: `core.hooksPath` → direct-copy). There is no step in the pipeline that re-validates plan.md against the finalised ADR before `/implement` starts.

**Recommendation:** after ADR is merged, re-read plan.md and update §4 (Chosen approach) to match. Add a checklist item to the ADR-workflow runbook. The pre-implement advisor call partially compensates, but it shouldn't be the only gate.

### Gap 2: Codex Plus quota is persistently exhausted

Five deferred-review issues (#29, #33, #35, #37, #45/#46) in two weeks. The two-voice review DoD criterion is functionally dead until the quota resets or the mechanism changes. Issue #42 tracks the decision (wait / switch to API key / accept as graceful degradation). This gap affects every PR until resolved.

### Gap 3: principles.md "Материально" written during ADR, not after implementation

The "Материально" section of a new principle is written during the ADR interview (before implementation), which means it can describe the chosen option's mechanism before the mechanism is built. When the implementation diverges (even acceptably), the principles doc is wrong. This caused a /review BLOCK.

**Recommendation:** treat "Материально" in new principle entries as a TODO during ADR, and fill it in as part of the implementation PR rather than the ADR PR.

### Gap 4: plan.md may contain banned terms

plan.md is `.gitignored` but visible to all review tools (advisor, /review, /codex-review) that read working-tree files. Banned terms in plan.md pollute those contexts. If review-codex.sh includes plan.md in its diff context, this could leak.

**Recommendation:** add a lint step (or explicit checklist item) to clean plan.md of banned terms before `/implement`.

---

## New issues to open

Based on this session:

| Issue | Description | Priority |
|---|---|---|
| Add plan-vs-ADR validation step to pipeline | After ADR merges, re-validate plan.md §4 against ADR decision. Runbook checklist item. | P3 |
| Automate `--hook-this-repo` in onboarding-repo runbook | Step-by-step for activating the commit-msg hook in a new pet project. | P3 |

Issue #42 (Codex quota) already exists and is the highest-priority gap.
