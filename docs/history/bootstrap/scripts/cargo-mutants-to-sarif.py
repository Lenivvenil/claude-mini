#!/usr/bin/env python3
"""cargo-mutants-to-sarif.py — converts cargo-mutants outcomes.json to SARIF 2.1.0.

Input: path to cargo-mutants outcomes.json (first positional arg) or stdin.
cargo-mutants outcomes.json format (v25+):
  [
    {
      "type": "mutant",
      "mutant": {
        "source_file": "src/lib.rs",
        "function_name": "add",
        "return_type": "i32",
        "mutation_type": "replace_with_true",
        "line": 5,
        "col": 5
      },
      "outcome": "survived",
      "duration": {"secs": 2, "nanos": 0}
    },
    ...
  ]

Output (stdout): SARIF 2.1.0 JSON — minimal annotation for GitHub Code Scanning.

Exit codes: 0 always (converter does not gate).
"""

import json
import sys


MUTATION_TYPE_DESCRIPTIONS = {
    "replace_with_true": "return value replaced with `true`",
    "replace_with_false": "return value replaced with `false`",
    "replace_with_default": "return value replaced with `Default::default()`",
    "replace_with_zero": "numeric return value replaced with `0`",
    "replace_with_one": "numeric return value replaced with `1`",
    "replace_with_empty_string": "string return value replaced with `\"\"`",
    "binary_operator": "binary operator mutated (e.g. `+` → `-`, `>` → `>=`)",
    "unary_minus": "negation added or removed",
}


def outcome_to_result(entry: dict) -> dict | None:
    # "missed" = no test caught the mutation (survived) — per cargo-mutants docs
    if entry.get("outcome") != "missed":
        return None

    mutant = entry.get("mutant", {})
    source_file = mutant.get("source_file", "unknown")
    function_name = mutant.get("function_name", "?")
    mutation_type = mutant.get("mutation_type", "unknown")
    line = mutant.get("line", 1)
    col = mutant.get("col", 1)

    description = MUTATION_TYPE_DESCRIPTIONS.get(
        mutation_type, f"mutation type: {mutation_type}"
    )

    return {
        "ruleId": "cargo-mutants/survived-mutant",
        "level": "warning",
        "message": {
            "text": (
                f"Surviving mutant in `{function_name}`: {description}. "
                "No test failed on this change — this code path is not "
                "meaningfully tested."
            )
        },
        "locations": [
            {
                "physicalLocation": {
                    "artifactLocation": {"uri": source_file, "uriBaseId": "%SRCROOT%"},
                    "region": {
                        "startLine": max(1, int(line)),
                        "startColumn": max(1, int(col)),
                    },
                }
            }
        ],
    }


def main() -> None:
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            entries = json.load(f)
    else:
        entries = json.load(sys.stdin)

    # Handle both top-level list and {"outcomes": [...]} wrapper (cargo-mutants version variance)
    if isinstance(entries, dict):
        entries = entries.get("outcomes", [])
    if not isinstance(entries, list):
        entries = []

    results = [r for entry in entries if (r := outcome_to_result(entry)) is not None]

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
                        "name": "cargo-mutants",
                        "version": "25",
                        "informationUri": "https://mutants.rs/",
                        "rules": [
                            {
                                "id": "cargo-mutants/survived-mutant",
                                "name": "SurvivedMutant",
                                "shortDescription": {
                                    "text": "Surviving mutant — test suite does not detect this change"
                                },
                                "helpUri": "https://mutants.rs/",
                            }
                        ],
                    }
                },
                "results": results,
            }
        ],
    }

    print(json.dumps(sarif, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
