I recommend starting with **advisory plan lint, ADR-trigger detection in shadow mode, and Jev-assisted critic grading outside the development path**. These offer bounded questions, reversible outcomes, and useful calibration data.

Read-only research completed; no files were edited or created. I read the [port map](docs/port/PORT-MAP.md) first, inspected repository mechanisms/history, and read the requested TypeSafe documentation and cookbooks. The `.md` endpoints failed through the web tool; their live HTML equivalents were accessible.

All proposed behavior, thresholds, workload estimates, and benefits below are **not verified** by execution or calibration. Repository and documentation facts have source links.

**Verified constraints that shape the design**

- Jev makes typed judgments; it does not generate explanations or code. Calibration describes groups of predictions, not guaranteed correctness of an individual answer. [System One](https://docs.typesafe.ai/concepts/system-one)
- **Choice** selects one option; **Noul** returns `P(yes)` without separate confidence; **Score** returns a probability-weighted position on descriptive levels. Choice/Score confidence derives from their distributions—it is not an independent second opinion. [Choice](https://docs.typesafe.ai/primitives/choice), [Noul](https://docs.typesafe.ai/primitives/noul), [Score](https://docs.typesafe.ai/primitives/score), [Confidence](https://docs.typesafe.ai/confidence)
- Current documented model: `jev-1.13.0`; input **$0.042/MTok**, output free. Limits: 64k tokens/request and 32k for state plus longest question. English currently performs best; Russian/mixed-language accuracy here is **not verified**. [Models](https://docs.typesafe.ai/models)
- The quoted **70–500 ms** range and local p95/p99 are **not verified**. Documentation says most queries take about 100 ms; that is insufficient evidence for a hook deadline. [Building with System One](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)

For the estimates below, one “call” means one HTTP request containing several questions. Assumptions—**not verified**: one issue/plan, one or two review rounds, approximately ten ACs/findings, and one or two commits. Token estimates include state and questions. Cost = input tokens × `$0.042 / 1,000,000`; missing key and cache hits incur zero API calls. Shared-stage batches must not be double-counted.

1. **Issue type/priority triage — accept suggestions; defer automatic priority changes.**
   - **Current:** the issue prompt infers labels and restricts them to existing labels: [task-to-issue.md:20](bootstrap/commands/task-to-issue.md:20), [:36](bootstrap/commands/task-to-issue.md:36). Priority audit checks presence, not correctness: [ticket-audit.sh:86](bootstrap/scripts/ticket-audit.sh:86).
   - **Question/state:** Choice for type; Score for priority using project descriptions from routine work through active incident. State: title, body, ACs, current labels, label definitions, impact, urgency, dependencies. Ask about demonstrated impact, not emphatic wording.
   - **Threshold/fallback — not verified:** suggest type/priority only when winning probability ≥0.90 and confidence ≥0.80; possible incident probability ≥0.20 routes to existing triage. Unknown impact also escalates. Offline: preserve labels and deterministically report missing fields; never invent a priority.
   - **Calls/cost — not verified:** 1 × 2k ≈ **$0.000084/feature**. Calibrate against reviewed label/priority decisions, preserving historical policy versions.

2. **“Is an ADR needed?” — accept at planning; reject Jev as sole waiver.**
   - **Current:** v1 uses filename substrings: [governance-rules-lib.sh:25](bootstrap/hooks/governance-rules-lib.sh:25), [:94](bootstrap/hooks/governance-rules-lib.sh:94). Actual semantic triggers are in [adr-trigger.md:5](docs/runbooks/adr-trigger.md:5). **The plugin already removed this path enforcement:** [commit-msg-check.sh:11](plugin/scripts/commit-msg-check.sh:11).
   - **Question/state:** one Noul per trigger: cross-cutting dependency, context contract, infrastructure, public API, hard-to-reverse constraint, security/data model. State: issue, chosen approach, before/after contracts, dependency changes, relevant ADR excerpts.
   - **Threshold/fallback — not verified:** any trigger ≥0.20 sends that trigger to the reasoning architect; ≥0.80 marks a strong recommendation. Low probabilities never waive the checklist. Offline: deterministic trigger checklist and path hints produce `needs_review/unknown`, then existing planning review decides. Do not multiply trigger probabilities.
   - **Calls/cost — not verified:** 1–2 × 4k ≈ **$0.000168–0.000336**. Calibrate against independently reviewed ADR necessity, including changes with misleading filenames.

3. **Which critics to invoke — accept additional recommendations; defer omission of required critics.**
   - **Current:** domain/prod-bound/docs paths and labels choose specialists; adversarial critic always runs: [feature.md:78](bootstrap/commands/feature.md:78), [:86](bootstrap/commands/feature.md:86). Current requirements remain in [dod-checklist.md:11](docs/runbooks/dod-checklist.md:11).
   - **Question/state:** one applicability Noul per available critic. State: critic responsibilities, actual diff, affected contracts, issue intent, mandatory-review policy. Ask whether a specific risk falls within each critic’s remit; several or none may apply.
   - **Threshold/fallback — not verified:** ≥0.80 adds an optional critic; 0.20–0.80 routes selection to the reasoning reviewer; ≤0.20 makes no addition. Mandatory reviewers remain deterministic. Offline: existing configured roster/path rules.
   - **Calls/cost — not verified:** 1–2 × 8k ≈ **$0.000336–0.000672**. Label relevance and missed consequential findings using full-roster comparisons. Hierarchical classification adds unnecessary complexity for this roster; batched Nouls fit multi-selection better. [Fan-out](https://docs.typesafe.ai/patterns/fan-out), [Hierarchical classification](https://docs.typesafe.ai/cookbooks/hierarchical_classification)

4. **Severity/duplicate triage of critic and Codex findings — accept visible annotations and grouping.**
   - **Current:** reviewer severity rubric and preserved critic output: [review/SKILL.md:62](bootstrap/skills/review/SKILL.md:62), [:80](bootstrap/skills/review/SKILL.md:80). Codex findings require individual agree/disagree/unsure judgments: [codex-review/SKILL.md:29](plugin/skills/codex-review/SKILL.md:29). Dedicated semantic deduplication is **not verified**.
   - **Question/state:** Score for impact; Noul per shortlisted duplicate pair. State: original findings, cited code, reproduction evidence, project severity rubric. Duplicate means the same defect and remedy—not merely the same file.
   - **Threshold/fallback — not verified:** duplicate ≥0.95 suggests grouping; retain every original. Severity requires confidence ≥0.80 for an annotation; serious-level probability ≥0.20 or disagreement escalates. Never automatically downgrade/block-dismiss. Offline: preserve original severity/order and group only exact duplicates.
   - **Calls/cost — not verified:** 1–2 × 12k ≈ **$0.000504–0.001008** for the assumed small batch; larger pair sets require more batches. Labels: adjudicated impact, validity, and duplicate pairs.

5. **AC coverage / intent-check — accept evidence classification; reject proof of completion.**
   - **Current:** deterministic AC extraction followed by LLM `covered/partial/missing` classification and file evidence: [intent-check.md:42](bootstrap/commands/intent-check.md:42), [:58](bootstrap/commands/intent-check.md:58).
   - **Question/state:** Choice per atomic AC: `supports / partial / contradicts / no_evidence`. State: exact criterion, retrieved source/test spans, diff revision, observed test results. Verify cited paths/spans deterministically before asking Jev. This adapts the citation-check pattern; textual support alone does not prove runtime behavior. [Citation check](https://docs.typesafe.ai/cookbooks/citation_check)
   - **Threshold/fallback — not verified:** `supports` probability ≥0.95 and confidence ≥0.80 permits provisional evidence annotation. Everything else goes to the reasoning reviewer; compound criteria require decomposition. Offline: retain the AC checklist, validate links, mark semantic coverage `unassessed`, and use existing review.
   - **Calls/cost — not verified:** 1–2 × 12k ≈ **$0.000504–0.001008**. Calibrate per-AC evidence judgments separately from implementation correctness.

6. **Plan quality lint — accept narrow semantic checks.**
   - **Current:** section/content checks plus per-line keyword/ADR-reference heuristics: [plan-lint.sh:59](bootstrap/scripts/plan-lint.sh:59), [:83](bootstrap/scripts/plan-lint.sh:83). This is not comprehensive plan-quality assessment.
   - **Question/state:** separate Nouls for unsupported design assertions, claimed ADR support absent from the cited excerpt, and ACs lacking a described verification method. State: issue/ACs, relevant plan sections, referenced decisions, project requirements. Keep section/link validation in code.
   - **Threshold/fallback — not verified:** defect probability ≥0.80 produces an advisory finding; 0.20–0.80 requests reasoning review; below 0.20 adds no finding. Offline: structural lint plus explicit semantic `unassessed`. Jev never silently overrides an authoritative existing block.
   - **Calls/cost — not verified:** 1 × 6k ≈ **$0.000252**. Calibrate allegations against accepted/rejected planning-review findings. Atomic defect checks follow the SDE verification pattern. [SDE cascade](https://docs.typesafe.ai/cookbooks/sde_cascade)

7. **Hedging lint — accept contextual qualification; reject probabilistic word banning.**
   - **Current:** Semgrep execution and word/conditional rules: [hedging-lint.sh:34](bootstrap/scripts/hedging-lint.sh:34), [hedging.yml:6](.semgrep/hedging.yml:6).
   - **Question/state:** Choice: `explicit_condition / honest_uncertainty / unsupported_vagueness / irrelevant`. State: flagged sentence, surrounding paragraph, document role, cited evidence. Distinguish an acknowledged unknown with a validation path from an evasive assertion.
   - **Threshold/fallback — not verified:** vagueness probability ≥0.90 and confidence ≥0.80 adds advice; uncertainty goes to the author/reviewer. Offline: show lexical matches with their context and existing policy outcome. Changing blocking policy requires explicit repository policy adoption.
   - **Calls/cost — not verified:** 0–1 × 3k ≈ **$0–0.000126**. Label true/false lint allegations, including legitimate “may,” quoted text, and Russian equivalents.

8. **Ticket audit — accept semantic testability checks; keep structural checks deterministic.**
   - **Current:** title/priority checks, a three-AC quota, and literal principle-reference checks: [ticket-audit.sh:77](bootstrap/scripts/ticket-audit.sh:77), [:134](bootstrap/scripts/ticket-audit.sh:134), [:154](bootstrap/scripts/ticket-audit.sh:154).
   - **Question/state:** Noul per AC for missing observable outcome; separate Noul for contradictory scope. State: problem, goals/non-goals, ACs, project ticket conventions. Do not translate arbitrary count quotas into semantic quality.
   - **Threshold/fallback — not verified:** ≥0.80 raises advice; intermediate results go to issue refinement. Offline: project-required structural checks and semantic `unassessed`; no automatic issue rewriting.
   - **Calls/cost — not verified:** 1 × 3k ≈ **$0.000126**, potentially shared with intake. Calibrate against reviewed ticket corrections and false-positive audit findings.

9. **Commit type suggestion — technically suitable; defer for low incremental value.**
   - **Current:** deterministic allowed-type/format validation: [commit-msg-check.sh:62](plugin/scripts/commit-msg-check.sh:62). Semantic type suggestion is **not verified**.
   - **Question/state:** Choice over project types plus `mixed/unclear`; state: staged diff, issue intent, type definitions. Ask which user-visible change the commit primarily represents.
   - **Threshold/fallback — not verified:** winning probability ≥0.90 and confidence ≥0.80 offers a suggestion; otherwise retain the author’s choice. Offline: validate grammar only. Never rewrite a message or reject valid syntax because Jev prefers another type.
   - **Calls/cost — not verified:** recommended **0 / $0**; if enabled, 1–2 × 4k ≈ **$0.000168–0.000336**. Calibrate against reviewed final commit types. Closed-set selection follows the function-calling cookbook. [Function calling](https://docs.typesafe.ai/cookbooks/function_calling)

10. **Flaky versus real test failure — reject as a pass/fail decision; defer investigation routing.**
    - **Current:** test exit/timeout handling blocks on failure: [stop-hook.sh:225](bootstrap/hooks/stop-hook.sh:225). A historical flakiness classifier/corpus is **not verified**.
    - **Question/state, if later explored:** Choice `product_regression / test_nondeterminism / infrastructure / unknown`; state: failure signature, exact revision, environment, seed, repeated runs, relevant diff and confirmed previous incidents.
    - **Threshold/fallback — not verified:** ≥0.95 probability and ≥0.80 confidence may route investigation only; any result leaves the test failure unresolved. Offline: retain failure and existing diagnosis procedure. Passing on retry alone cannot establish a flaky label.
    - **Calls/cost — not verified:** recommended **0 / $0**; experimental classification 1 × 6k ≈ **$0.000252/failure**. Labels require root-cause confirmation.

11. **Handoff: “is there unfinished work?” — accept residual-obligation advice; reject Jev-owned completion.**
    - **Current:** mechanical handoff metadata/TODO warnings and preflight session/CI/issue/PR summaries: [stop-hook.sh:72](bootstrap/hooks/stop-hook.sh:72), [:161](bootstrap/hooks/stop-hook.sh:161), [mini-preflight.sh:125](bootstrap/scripts/mini-preflight.sh:125).
    - **Question/state:** Noul per recorded obligation: “Does the supplied evidence leave this obligation unresolved?” State: task-specific commitments, AC statuses, unresolved findings, git/CI facts, next actions. Dirty-tree/open-blocker checks stay deterministic.
    - **Threshold/fallback — not verified:** ≥0.20 keeps an obligation visible for reasoning review; low probability cannot establish completion when evidence is missing. Offline: deterministic unfinished-work inventory; missing metadata becomes `unknown`.
    - **Calls/cost — not verified:** 0–1 × 4k ≈ **$0–0.000168**. Calibrate against verified continuation needs. Run during explicit handoff, preserving the port map’s removal of unconditional Stop writes.

12. **Eval grading of critics — accept as an assisted semantic grader.**
    - **Current:** an LLM PASS/FAIL causal rubric and separate deterministic invocation check: [finds-mismatch.md:2](plugin/evals/worktree-hook-mismatch/graders/finds-mismatch.md:2), [used-critic.md:2](plugin/evals/worktree-hook-mismatch/graders/used-critic.md:2).
    - **Question/state:** Nouls for each required causal claim; optional separate Scores for grounding/actionability. State: reviewed gold defect, rubric, critic response, relevant source. Calculate recall, precision, invocation, and aggregate results in code; a weighted quality score must not hide a missed critical defect. [Composite scoring](https://docs.typesafe.ai/patterns/composite-scoring)
    - **Threshold/fallback — not verified:** all required claims ≥0.95 permits provisional pass; any ≤0.05 permits provisional fail; the middle or disagreement goes to the existing grader/reviewer. Offline: deterministic invocation checks plus semantic `ungraded`; never manufacture a grade.
    - **Calls/cost — not verified:** normally **0/feature**; a critic-change evaluation with `N` cases and two arms uses approximately `2N × 4k`, or **$0.000336N**—$0.00672 for 20 cases. Fresh Jev grading requires network/key; dataset preparation and cached replay can be offline.

For the **plugin architecture**, I recommend the following design—**not verified or implemented**:

- **One Python 3 CLI**, such as `plugin/scripts/jev.py`, using standard-library HTTPS/JSON and a small explicit response validator. Python is already required by [commit-msg-check.sh:47](plugin/scripts/commit-msg-check.sh:47). Avoid another daemon, MCP server, runtime installer, or per-agent client.
- Call documented `POST https://api.typesafe.ai/v1/systemone` with Bearer authentication; validate expected IDs/types, finite probabilities, ranges, and allowed options before returning an internal result. [API](https://docs.typesafe.ai/api)
- **Versioned definitions:** `plugin/questions/jev/*.v1.json` containing instructions, criteria, required state fields and examples; separate versioned threshold/fallback policy. Put the complete question in `instructions`: question IDs are not visible to the model. [Primitives](https://docs.typesafe.ai/primitives)
- **Project ownership:** configuration, secrets, logs, cache and temporary files under the effective project/worktree’s `.claude/claude-mini/jev/`. Validate containment after resolving symlinks and effective Git target. Plugin assets remain read-only. No `~/.claude`, shell-profile edits, or global installation.
- **Key lookup:** owner-created project secret file first; explicitly configured owner-created OS Keychain entry second; otherwise `unavailable:no_key`. Pass keys only in memory to HTTPS. No automatic keychain creation/unlocking, broad credential search, or command-line secrets. Keychain behavior on this machine is **not verified**.
- **No-key operation:** determine availability before collecting sensitive state. Return structured `unavailable/timeout/invalid_response/oversized_state` plus a deterministic fallback route. These statuses never mean “no ADR,” “clean,” or “complete”; existing reasoning stages continue.
- **Deadlines:** proposed skill-call total deadline 3 seconds, no automatic retries initially. A future hook call gets at most 1.5 seconds network time and a 2-second outer process deadline covering startup, key lookup, DNS and logging. Cancellation behavior is **not verified**. SDK defaults would need overriding: Python documents a 10-second per-operation timeout and configurable retries. [SDK constants](https://docs.typesafe.ai/sdk/python/api/constants), [Retries](https://docs.typesafe.ai/sdk/python/api/retries)
- **Logging:** ignored project-local run records containing exact redacted state sent, question/model/policy versions, raw answers, decision, fallback reason, source SHA/content hashes, latency, usage and later outcome labels. Never log credentials. Use per-run files to avoid concurrent append collisions; storage failure leaves the normal workflow usable.
- **Caching:** hash canonical redacted state + complete questions + pinned model + adapter schema. Cache successful raw answers; reapply current thresholds on hits. Changes to diff, evidence or questions invalidate the key. Never cache an outage as a semantic answer. Pin `jev-1.13.0` and record the response model; aliases can move. [Models](https://docs.typesafe.ai/models)
- **State construction:** callers supply small, relevant evidence packets; no whole-repository upload merely to batch questions. Oversized/incomplete evidence escalates instead of silently truncating. State can contain adversarial instructions; known limitations also include numerical reasoning and inconsistent cross-question identities. Keep commands, arithmetic, policy and side effects in code. [State](https://docs.typesafe.ai/concepts/state), [Known limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13)

Skills call the CLI at explicit intake/plan/review/handoff checkpoints and consume JSON. Agents use it for bounded classification, then retain reasoning responsibility. The existing hook has a verified **10-second timeout**: [hooks.json:13](plugin/hooks/hooks.json:13).

**Hook policy—proposal, not verified:** initially consume only fresh cached annotations. Later, commit-type advice or qualification of already-extracted hedging matches could use one bounded best-effort request. Keep ADR decisions, critic selection, findings reconciliation, AC coverage, test-failure diagnosis, evals and handoff outside live hooks. Jev must not control commit permission, merge, issue closure, destructive operations, or mandatory-review waivers.

For **calibration**, the repository provides useful seeds but not an existing validated dataset:

- Local commit `cd4c6bb` records the #305 worktree mismatch missed by critics and caught by Codex; `48867dc` records #309 parser findings/repairs; `0828e10` records documentation BLOCKs and fixes. Narrative catches also appear in [first-feature-session-log.md:121](docs/runbooks/first-feature-session-log.md:121).
- [grooming-2026-04-24.md:14](docs/backlog/grooming-2026-04-24.md:14) offers duplicate-versus-related examples; [:94](docs/backlog/grooming-2026-04-24.md:94) records conflicting label schemes.
- There are only three allowed, unclassified [gate events](docs/gate-audit/events.jsonl:1); critic gates are explicitly uninstrumented: [schema.md:36](docs/gate-audit/schema.md:36).
- The inspected eval reports no Agent invocation and equal scores in both arms: [aggregate-result.json:82](plugin/evals/results/2026-09-25T19-09-21-760Z/aggregate-result.json:82), [:251](plugin/evals/results/2026-09-25T19-09-21-760Z/aggregate-result.json:251). It does not establish critic benefit.
- Plans, QA reports and eval results are ignored: [.gitignore:9](.gitignore:9). Complete historical availability is **not verified**. GitHub API reads failed; remote review/issue contents were **not verified**.

The proposed evaluation procedure—**not verified**—is:

1. Enumerate local history and, when accessible, paginate PRs, issues, review threads and CI outcomes. Preserve before/after SHAs, policy version, original finding, disposition and supporting repair. Do not use “merged,” “fixed” or “closed” as automatic truth labels.
2. Build separate datasets for each question above. Prefer existing reviewed dispositions; adjudicate consequential ambiguities. Add clean negatives, withdrawn findings, insufficient evidence, Russian/mixed-language cases and injected instructions.
3. Use only evidence available at decision time as input. Keep entire PRs, repair chains and near-duplicates together; split chronologically into development, threshold-tuning and untouched test sets.
4. Compare current heuristics/reasoning judgments with Jev in shadow mode. Measure per-question error rates, serious-miss recall, false escalations, abstention, calibration/Brier score, latency and actual tokens. Sample confident negatives as well as positive alerts.
5. Select thresholds against observed error costs and uncertainty intervals. Insufficient data keeps the decision advisory. Never transfer thresholds between primitives, rewritten questions, model versions or substantially different languages.
6. Evaluate **Jev’s grading accuracy** against adjudicated labels separately from **critic effectiveness** against known defects. Invoke critics directly, score invocation deterministically, and preserve both misses and false alarms.
7. Measure user burden, rework, recovery during outages and downstream reasoning calls. Recalibrate after version changes; one project switch disables Jev and restores the existing path.

The recommended **rollout order—benefit/risk not verified**—is:

1. **Advisory plan lint:** small evidence packets, existing heuristics to compare, no runtime decision authority.
2. **Critic-grader evaluation alongside it:** reuse the existing causal rubric, add near-misses and real historical cases, and establish trustworthy labels before claiming critic improvements.
3. **ADR-trigger shadowing:** target the brittle v1 heuristic while preserving the semantic checklist, independent reasoning review and separate ADR approval/merge.

Then consider AC evidence classification and finding grouping. Defer critic omission, automatic priority changes, live hook inference, commit-type suggestions, flaky-test classification and semantic completion decisions until their measured benefit justifies their maintenance and failure costs.