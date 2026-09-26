# Runbook: Property-Based Testing with Hypothesis in /qa

## What this is

The `/qa` skill includes a 6-step PBT workflow (Phase 2.5) that fires on Python diffs when `conftest.py` is present. This runbook explains the mechanism, profiles, and shows one worked example.

**Prerequisite:** `hypothesis` in dev-dependencies **before** running the installer:
```bash
uv add --dev hypothesis
./bootstrap/universal-setup.sh --target <repo>
```

**Recovery (if you ran installer first and broke your test suite):**
```bash
# either install hypothesis:
uv add --dev hypothesis
# or back out the template if you don't want PBT:
rm conftest.py
```

The shipped `conftest.py` imports `hypothesis` at module load with a guarded error. Running `pytest` without `hypothesis` installed will fail with a clear directive message — but it WILL fail (collection abort), so don't deliver `conftest.py` until the dependency is in place.

## Profile selection

`conftest.py` (installed by `./bootstrap/universal-setup.sh --target <repo>`) selects a profile automatically:

| Trigger | Profile | Examples | When |
|---|---|---|---|
| `HYPOTHESIS_PROFILE=nightly` | nightly | 5000 | GitHub Actions cron (03:00 UTC) |
| `CI=true` | ci | 500 | GitHub Actions push/PR |
| default | dev | 50 | Local `uv run pytest` |

Override locally: `HYPOTHESIS_PROFILE=ci uv run pytest`

## Running only PBT tests

Tag your Hypothesis tests with `@pytest.mark.hypothesis`:

```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.hypothesis
@given(st.integers())
def test_property(x: int) -> None:
    ...
```

Register the marker in `pyproject.toml` to avoid `PytestUnknownMarkWarning`:

```toml
[tool.pytest.ini_options]
markers = ["hypothesis: property-based tests using Hypothesis"]
```

Then:

```bash
uv run pytest -m hypothesis --tb=short
```

## Worked example: `normalize_path`

**Function under test:**
```python
import os

def normalize_path(p: str) -> str:
    """Return absolute, normalized path. Empty string → current dir."""
    if not p:
        return os.getcwd()
    return os.path.normpath(os.path.abspath(p))
```

**Six-step PBT application:**

1. **Analyze** — `normalize_path(str) → str`. Input is any string, output is an absolute path. Side effect: reads `os.getcwd()` on empty input.

2. **Understand** — Invariant: applying `normalize_path` twice to any non-empty string must produce the same result (idempotence). A normalized absolute path is already normalized.

3. **Propose** — Pattern: `idempotence`.

4. **Write:**
```python
import os
from hypothesis import given, example, strategies as st

# --- function under test (inline for the example; in practice: import from your module) ---
def normalize_path(p: str) -> str:
    if not p:
        return os.getcwd()
    return os.path.normpath(os.path.abspath(p))
# ---

@given(st.text(min_size=1))
@example("/foo/../bar")       # classic normalization case
@example("./relative")        # relative path
@example("a" * 255)           # max-length component
def test_normalize_path_idempotent(p: str) -> None:
    once = normalize_path(p)
    twice = normalize_path(once)
    assert once == twice, f"Not idempotent: {p!r} → {once!r} → {twice!r}"
```

5. **Execute:**
```bash
uv run pytest tests/test_normalize.py -m hypothesis -x --tb=short
```

6. **Triage** — If Hypothesis finds `p = "\x00"` breaks the invariant: add `@example("\x00")`, fix the function, re-run.

## Counterexample replay and the nightly artifact

Hypothesis stores shrunk failing inputs in the in-repo `.hypothesis/` directory. On every subsequent local or CI run, those counterexamples replay first (Phase.reuse) — that's how a once-found failing case is never lost.

The nightly CI job (only on `schedule:` events) additionally uploads `.hypothesis/` as a GitHub Actions artifact with 7-day retention. This is a backup against accidental deletion of the in-repo cache, not the replay mechanism itself.

> **Security warning:** never let `@given` strategies draw values from secrets, credentials, or env-var-loaded sensitive fixtures. Hypothesis persists discovered counterexamples to `.hypothesis/` and uploads them as a CI artifact — a leaked secret would survive there for 7 days.

## References

- ADR-0022: `docs/decisions/0022-pbt-integration-via-installer-template.md`
- Issue #118
- Hypothesis docs: https://hypothesis.readthedocs.io/
