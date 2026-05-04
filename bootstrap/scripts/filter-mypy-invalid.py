#!/usr/bin/env python3
"""filter-mypy-invalid.py — filters mutmut results, removing type-invalid mutants.

mutmut occasionally produces AST-valid but type-invalid mutations (e.g., replacing
an int with a string literal). These pollute the survived count with mutants that
any type-checked codebase would catch at static analysis time, not test-run time.
This script removes them.

Algorithm:
  For each survived/timeout mutant:
    1. Extract the mutated source via `mutmut show <id>` (applies mutation in-memory,
       outputs the modified file to stdout).
    2. Write to a temp file.
    3. Run `mypy --ignore-missing-imports <temp>`.
    4. If mypy exits non-zero with a type error: mutant is invalid → exclude.
  Parallelised via concurrent.futures (default 4 workers, MYPY_WORKERS env override).

Input (stdin): JSON array of mutant objects (same format as mutmut-to-sarif.py input).
Output (stdout): filtered JSON array (same format, type-invalid mutants removed).

Usage:
  python3 filter-mypy-invalid.py < mutants.json > filtered.json
  MYPY_WORKERS=8 python3 filter-mypy-invalid.py < mutants.json > filtered.json

Exit codes: 0 always (filter does not gate).

Note: mypy must be installed and on PATH. If mypy is not found, the filter is
skipped and the full input is passed through with a warning to stderr.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed


WORKERS = int(os.environ.get("MYPY_WORKERS", "4"))


def _mypy_available() -> bool:
    return shutil.which("mypy") is not None


def _mutmut_show(mutant_id: int) -> str | None:
    """Returns the mutated source code for mutant_id, or None on failure."""
    try:
        result = subprocess.run(
            ["mutmut", "show", str(mutant_id)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def _is_type_valid(mutant: dict) -> bool:
    """Returns True if the mutant is type-valid (should be kept), False if mypy rejects it."""
    mutant_id = mutant.get("id")
    if mutant_id is None:
        return True

    source = _mutmut_show(mutant_id)
    if source is None:
        return True

    with tempfile.NamedTemporaryFile(suffix=".py", mode="w", delete=False) as tmp:
        tmp.write(source)
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["mypy", "--ignore-missing-imports", "--no-error-summary", tmp_path],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            if "error:" in result.stdout or "error:" in result.stderr:
                return False
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    finally:
        os.unlink(tmp_path)

    return True


def main() -> None:
    mutants = json.load(sys.stdin)
    if not isinstance(mutants, list):
        mutants = []

    candidates = [m for m in mutants if m.get("status") in ("survived", "timeout")]
    others = [m for m in mutants if m.get("status") not in ("survived", "timeout")]

    if not _mypy_available():
        print(
            "WARNING: mypy not found — skipping type-invalidity filter; "
            "all mutants passed through",
            file=sys.stderr,
        )
        print(json.dumps(mutants, indent=2, ensure_ascii=False))
        return

    valid: list[dict] = list(others)

    with ThreadPoolExecutor(max_workers=WORKERS) as executor:
        future_to_mutant = {executor.submit(_is_type_valid, m): m for m in candidates}
        for future in as_completed(future_to_mutant):
            mutant = future_to_mutant[future]
            try:
                if future.result():
                    valid.append(mutant)
                else:
                    print(
                        f"  filtered type-invalid mutant #{mutant.get('id')} "
                        f"in {mutant.get('filename', '?')}:{mutant.get('line', '?')}",
                        file=sys.stderr,
                    )
            except Exception as exc:
                print(f"  mypy check failed for mutant #{mutant.get('id')}: {exc}", file=sys.stderr)
                valid.append(mutant)

    print(json.dumps(valid, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
