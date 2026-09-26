#!/usr/bin/env python3
"""mutmut-to-sarif.py — converts mutmut results JSON to SARIF 2.1.0.

Input (stdin or first positional arg): JSON array of mutant objects.
Expected format (produced by the workflow's inline sqlite extraction):
  [
    {
      "id": 1,
      "status": "survived",
      "filename": "src/foo.py",
      "line": 6,
      "original": "x = 5",
      "mutation": "x = 6"
    },
    ...
  ]

Output (stdout): SARIF 2.1.0 JSON — minimal annotation (file + line) for
GitHub Code Scanning. Rich rule metadata deferred to a follow-on issue
per ADR-0025 Negative Consequences §1.

Exit codes: 0 always (converter does not gate).
"""

import json
import sys


def mutant_to_result(m: dict) -> dict:
    filename = m.get("filename", "unknown")
    line = m.get("line", 1)
    mutation = m.get("mutation", "")
    original = m.get("original", "")
    mutant_id = m.get("id", 0)

    return {
        "ruleId": "mutmut/survived-mutant",
        "level": "warning",
        "message": {
            "text": (
                f"Surviving mutant #{mutant_id}: "
                f"`{original.strip()}` → `{mutation.strip()}`. "
                "No test failed on this change — the tested behaviour is not "
                "actually under test here."
            )
        },
        "locations": [
            {
                "physicalLocation": {
                    "artifactLocation": {"uri": filename, "uriBaseId": "%SRCROOT%"},
                    "region": {"startLine": max(1, int(line))},
                }
            }
        ],
    }


def main() -> None:
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            mutants = json.load(f)
    else:
        mutants = json.load(sys.stdin)

    if not isinstance(mutants, list):
        mutants = []

    survived = [m for m in mutants if m.get("status") == "survived"]

    sarif = {
        "version": "2.1.0",
        "$schema": (
            "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/"
            "sarif-v2.1.0-errata01-os-complete.html"
        ),
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "mutmut",
                        "version": "3",
                        "informationUri": "https://mutmut.readthedocs.io/",
                        "rules": [
                            {
                                "id": "mutmut/survived-mutant",
                                "name": "SurvivedMutant",
                                "shortDescription": {
                                    "text": "Surviving mutant — test suite does not detect this change"
                                },
                                "helpUri": "https://mutmut.readthedocs.io/",
                            }
                        ],
                    }
                },
                "results": [mutant_to_result(m) for m in survived],
            }
        ],
    }

    print(json.dumps(sarif, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
