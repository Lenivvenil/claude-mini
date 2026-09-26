"""
Hypothesis property-based testing profiles.

REQUIRES `hypothesis` in dev-dependencies (fail-loud on missing — intentional):
    uv add --dev hypothesis

Usage:
    dev (50 examples):    run normally — `uv run pytest`
    ci  (500 examples):   set CI=true — automatically selected in GitHub Actions
    nightly (5000 ex):    HYPOTHESIS_PROFILE=nightly uv run pytest

Ref: claude-mini ADR-0022, issue #118.
"""

import os

try:
    from hypothesis import HealthCheck, Phase, settings
except ModuleNotFoundError as e:
    raise ModuleNotFoundError(
        "conftest.py requires hypothesis. Install: uv add --dev hypothesis. "
        "If you do not want PBT in this repo: rm conftest.py."
    ) from e

settings.register_profile(
    "dev",
    max_examples=50,
    suppress_health_check=[HealthCheck.too_slow],
)

settings.register_profile(
    "ci",
    max_examples=500,
    suppress_health_check=[HealthCheck.too_slow],
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target, Phase.shrink],
)

settings.register_profile(
    "nightly",
    max_examples=5000,
    suppress_health_check=[HealthCheck.too_slow],
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target, Phase.shrink],
)

_profile = os.getenv("HYPOTHESIS_PROFILE") or ("ci" if os.getenv("CI") == "true" else "dev")
settings.load_profile(_profile)
