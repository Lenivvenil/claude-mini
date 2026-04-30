# 0019. Verify installer side-effects inline; mandate `--check` after install in `/implement`

* Status: accepted
* Date: 2026-04-28
* Deciders: Lenivvenil (operator decides; draft by solutions-architect)
* Tags: installer, contract, idempotency, verification, pipeline
* Related issue: #81

## Context and Problem Statement

ADR-0010 fixed one class of installer dishonesty (`copy_file()` warn-and-skip on
drift) by introducing exit code 4 and an explicit `--force` escape hatch. Three
other code paths in `bootstrap/universal-setup.sh` still exit 0 even when their
core work was silently skipped or failed:

1. `copy_file()` (lines 272–306) warns on "source missing" but does **not**
   increment `DRIFT` and does **not** fail. Currently dead code — every call
   site guards loop entry with `[ -f "$f" ] || continue` — but the unreachable
   branch is a latent regression: any future call site that omits the guard
   re-introduces silent skip.
2. `--hook-this-repo` (lines 92–129) calls `cp "$STAGED_HOOK" "$DEST_HOOK"`
   and exits 0 with no post-copy verification. A failed copy is
   indistinguishable from a successful one. Reachable today.
3. `--target` copy loop (lines 158–182) calls `cp "$baked" "$dst"` with no
   check on the cp exit code — disk-full or permission errors silently pass.
   Reachable today.

`/implement` invokes the installer between tickets during sweep work
(Epic #44). A silent partial install in ticket N leaves a corrupted
environment that ticket N+1 inherits — invisible to the orchestrator, which
sees only exit 0. The decision is architecturally significant per
`docs/principles.md#что-значит-архитектурно-значимо` because it modifies the
public exit-code contract of `universal-setup.sh` (codified in ADR-0010) and
adds a mandatory step to a pipeline command (`/implement` Phase 3) that all
future feature work depends on.

This ADR **complements** ADR-0010 (does not supersede it). The exit-code matrix
0–4 stays as-is; this ADR fixes code paths that were supposed to honor it but
did not.

## Decision Drivers

* **Honesty of exit code (`docs/principles.md` Principle 1 — "красные флаги
  вместо трейдоффов").** Exit 0 must mean "synchronized," not "I tried."
  This is the same principle ADR-0010 enforces; this ADR extends its reach
  to two more reachable code paths and one defensive case.
* **No new public API unless forced.** ADR-0010 already established
  `--check` as the standalone read-back path. Adding a second verb when the
  existing one fits is API surface inflation.
* **Sweep safety.** A mandatory post-install verification step in `/implement`
  Phase 3 must catch silent-skip regressions before ticket N+1 inherits a
  corrupted environment.
* **Minimum diff to fix the demonstrated problem.** Three specific code gaps
  exist; the fix should target those gaps, not redesign the installer.
* **Composability with future declarative-manifest work** (ADR-0008 re-visit
  trigger). Whatever is added now must not entrench whole-file copy semantics
  more deeply than necessary.

## Considered Options

* **Approach A — Inline fixes (cmp/die/DRIFT-increment) plus `--check` mandate
  in `/implement` Phase 3** (chosen)
* **Approach B — Add a dedicated `--verify` flag to `universal-setup.sh`**
* **Approach C — Extend `mini-health` to assert post-install file presence**
* **Approach D — Structured JSON output from installer scripts**

## Decision Outcome

Chosen option: **Approach A — inline fixes + `--check` mandate.**

The three gaps are not a design problem; they are three missing lines
(`|| die`, `cmp -s`, DRIFT-increment) in code paths that were already supposed
to honor ADR-0010's exit-code contract. The right response is to add those
lines, not introduce a new verb. ADR-0010 already established `--check` as the
standalone read-back path that exits non-zero on drift; the only gap is that
`/implement` does not currently require calling it after installer
invocations. Adding one sentence to `/implement` Phase 3 closes the
sweep-safety hole without API change.

This decision invokes `docs/principles.md` Principle 1 directly: a script that
exits 0 after a failed `cp` is the canonical "красный флаг" — exit 0 lying
about state. The fix is structural (verify, then exit), not a trade-off.

Approach B (`--verify` flag) is additive and remains available if the
inline fixes prove insufficient or if a manifest-based verification path is
later required. Starting with B now front-loads public API design for
what is fundamentally three missing defensive lines.

### Positive Consequences

* Exit codes regain honesty across all three reachable paths. `--hook-this-repo`
  and `--target` join `--install`'s ADR-0010 contract.
* No new public API surface. Exit-code matrix from ADR-0010 unchanged.
* `/implement` Phase 3 now has a mandatory readback step, so silent-skip
  regressions in any future installer code path surface during sweep.
* Symmetry restored: `--check` becomes the single canonical post-install
  verifier, used by both CI (per ADR-0010 Confirmation §1) and `/implement`.
* Defensive hardening of `copy_file()` "source missing" branch: even if a
  future call site omits the `[ -f ]` guard, the failure becomes loud
  (exit 4) rather than silent.

### Negative Consequences

* **Behavior change in `copy_file()`:** "source missing" goes from `warn` to
  DRIFT increment (exit 4). Any workflow that relied on tolerant pass-through
  for absent sources will fail loudly. Mitigation: today this branch is dead
  code (every call site guards with `[ -f ]`), and the change is documented
  in CHANGELOG with upgrade note. But the contract change is real.
* **Mandatory `--check` in `/implement` Phase 3 adds sweep latency.** Read-only
  file comparisons are fast, but per-operation overhead accumulates over a
  multi-ticket sweep. The convention specifies `--check` only after
  `--install`/`--hook-this-repo`/`--target`, not after every script, to
  contain this cost.
* **Gap #1 fix is defensive against dead code.** Adding a DRIFT increment to
  an unreachable branch is a tech-debt smell — the right long-term answer is
  a manifest-driven installer (ADR-0008 re-visit trigger), not patching
  unreachable warnings. This ADR accepts that smell for now.
* **Out-of-scope, but lurking:** `mini-health.sh` exits 0 when `warnings ≤ 3`
  — a partial install surfacing as 2 warnings would still pass mini-health.
  This is the same class of dishonesty as the spike's main subject. This ADR
  does not fix it; tracked separately. Operators reading this ADR may assume
  mini-health is now reliable for install verification — it is not.
* **Manifest completeness remains implicit.** This ADR fixes copy-loop gaps
  but does not address the "file added to repo but not picked up by glob"
  class of bug (tracked in #31/#32). Verification is bounded by what the
  install loops touch.
* **Future declarative-manifest direction.** If `bootstrap/` later moves to a
  yaml-manifest of expected `~/.claude/` contents (ADR-0008 re-visit trigger),
  the inline `cmp -s` and `|| die` lines added here become redundant — the
  manifest reader replaces them. This ADR's fixes are throwaway in that
  future, by design.
* **Reversibility:** rollback requires reverting three small hunks in
  `universal-setup.sh` and one bullet in `bootstrap/commands/implement.md`;
  effort low, no data migration.

## Pros and Cons of the Options

### Approach A — Inline fixes + `--check` mandate

* Good, because minimum diff: three specific code gaps get three specific
  defensive lines.
* Good, because no new public API; reuses `--check` from ADR-0010.
* Good, because consistent with ADR-0010 philosophy: "Зелёный означает
  синхронизировано."
* Good, because `/implement` Phase 3 readback closes the sweep-N+1 inherit
  gap with one operative sentence.
* Bad, because "source missing → DRIFT" is a contract change that affects any
  workflow tolerating partial source trees (today none, but the contract bit
  is real).
* Bad, because it patches code paths that a future manifest-driven installer
  would replace; the fix is throwaway-by-design.
* Bad, because it does not address `mini-health`'s own exit-0-with-warnings
  gap, which is the same class of issue.

### Approach B — `--verify` flag

* Good, because clean separation of install and verify; composable; operators
  can call verify any time, independent of `--install`.
* Good, because forces an explicit expected-file manifest, which is a
  prerequisite for any future declarative-manifest direction.
* Bad, because new public-API surface — extends the exit-code matrix and flag
  contract documented in ADR-0010, requiring a contract bump.
* Bad, because the three inline fixes are still needed regardless: `--verify`
  cannot retroactively make a failed `cp` in `--hook-this-repo` honest.
* Bad, because front-loading API design for what is fundamentally three
  missing defensive lines violates the "minimum public API" driver.
* Bad, because additive — can be added later under Approach A's umbrella if
  the inline fixes prove insufficient.

### Approach C — Extend `mini-health`

* Good, because single trusted health-check tool; operators already know it.
* Bad, because it conflates session health (weekly cadence) with install
  completeness (per-operation cadence). The two have different SLOs.
* Bad, because `mini-health` has no knowledge of what the installer is
  expected to deploy; coupling them requires either a manifest (which is
  Approach B in disguise) or tight import of installer logic (which couples
  two scripts that should be independent).
* Bad, because `mini-health.sh` exits 0 for `warnings ≤ 3` — a partial install
  with 2 missing files would still pass. The tool itself has the same
  dishonesty bug this ADR is trying to eliminate.

### Approach D — Structured JSON output

* Good, because machine-readable diagnostics; rich `{status, operations[]}`
  payload usable by tooling.
* Bad, because breaking change to all existing consumers of `universal-setup.sh`
  output (humans reading terminal, CI grep, `/bootstrap`).
* Bad, because does not fix the underlying exit-code honesty issue: exit 0 is
  still exit 0 regardless of payload shape.
* Bad, because over-engineered for three specific code gaps; introduces a
  parser dependency for callers that today need none.

## Confirmation

After implementation lands on `main`:

1. **Gap #2 (`--hook-this-repo`)** — In a clean test repo, run
   `bootstrap/universal-setup.sh --hook-this-repo`. Verify exit 0 and that
   `cmp -s "$STAGED_HOOK" .git/hooks/commit-msg` returns 0. Then truncate
   `.git/hooks/commit-msg` to 0 bytes and re-run `--hook-this-repo`; verify
   exit 0 and post-copy `cmp -s` succeeds (the new readback fires after cp).
2. **Gap #3 (`--target` cp failure)** — Run
   `bootstrap/universal-setup.sh --target /tmp/readonly-repo` where
   `/tmp/readonly-repo/.claude/commands/` is `chmod 000`. Expect non-zero exit
   with a `die` message naming the failed destination, not exit 0.
3. **Gap #1 (`copy_file()` source missing)** — Construct a synthetic call site
   that passes a non-existent source path to `copy_file()`. Expect `DRIFT > 0`
   in the running counter and final exit 4, not exit 0 with a warning.
4. **`/implement` Phase 3 instruction snapshot** — `bootstrap/commands/implement.md`
   contains a Phase 3 bullet requiring `--check` after any installer
   invocation with install semantics, before declaring the step done.
5. **Regression** — `test-governance-hook.sh` and `test-commit-msg-governance.sh`
   pass unchanged; `mini-health.sh` behavior unchanged (this ADR does not
   touch it).
6. **CI integration** — `baseline-verification` job (when it lands; see
   ADR-0010 note 2026-04-24) treats any non-zero exit as failure. Until then,
   confirmation 1–3 verified locally per the same convention as ADR-0010.

## Re-visit Trigger

Re-open this decision when **any one** is true:

* `bootstrap/` migrates to a declarative manifest of expected `~/.claude/`
  contents (ADR-0008 re-visit trigger fires). Inline `cmp -s` / `|| die` /
  DRIFT-increment lines are then replaced by the manifest reader; this ADR's
  fixes become redundant.
* `--check` itself proves unreliable as the standalone post-install verifier
  — for example, if a class of drift surfaces that `--check` cannot detect
  with byte-equality. Then Approach B (`--verify` with manifest) re-enters
  consideration.
* Sweep latency from mandatory `--check` after every installer invocation
  exceeds an operationally tolerable bound (operator defines threshold;
  candidate: > 5s aggregate over a 10-ticket sweep). Then re-evaluate
  whether `--check` should be sampled rather than mandatory.
* `mini-health`'s own exit-0-with-warnings gap is fixed in a separate ADR;
  re-visit whether this ADR should fold mini-health into the post-install
  verification flow at that point.
* A new installer code path is added that copies state but cannot be covered
  by `--check` (e.g., remote-fetch, or a non-file artifact). Then the
  inline-readback convention needs extension or replacement.

## Links

* `docs/decisions/0010-installer-drift-behavior.md` — establishes exit-code
  matrix (0–4) and abort-on-drift; this ADR complements (does not supersede) it.
* `docs/decisions/0008-hardware-universal-split.md` — philosophy of honesty
  over hidden automation; same principle applied here.
* `docs/decisions/0018-per-project-command-installation.md` — `--target`
  installation mode, gap #3 above.
* `docs/principles.md#четыре-директивы` — Principle 1 (красные флаги вместо
  трейдоффов): exit 0 lying about state is the canonical red flag.
* `docs/principles.md#что-значит-архитектурно-значимо` — public API contract
  modification trigger.
* GitHub issue #81 — original spike framing.
* `bootstrap/universal-setup.sh` — `copy_file()` (lines 272–306),
  `--hook-this-repo` block (lines 92–129), `--target` copy loop
  (lines 158–182).
* `bootstrap/commands/implement.md` — Phase 3 verification step landing site.
* `bootstrap/scripts/mini-health.sh` — out-of-scope here; tracked separately
  for its own exit-0-with-warnings gap.
* GitHub issues #31, #32 — manifest completeness (out of scope for this ADR).
