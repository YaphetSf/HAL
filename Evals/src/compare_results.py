#!/usr/bin/env python3
"""Compare saved rewrite-eval reports per role rather than as one leaderboard.

Each model is scored only on the slice it claims to support, so a single ranking
would be misleading. This prints a role matrix (action x language) plus cost, and
refuses to mix reports produced by different suite versions.
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

ROLES = (
    ("correct", "english"),
    ("correct", "chinese"),
    ("correct", "mixedChineseEnglish"),
    ("rephrase", "english"),
    ("rephrase", "chinese"),
    ("rephrase", "mixedChineseEnglish"),
)

ROLE_HEADERS = ("cor/en", "cor/zh", "cor/mix", "rep/en", "rep/zh", "rep/mix")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--results",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "results",
        help="Directory of report JSON files (default: <repo>/Evals/results)",
    )
    return parser.parse_args()


def role_cell(cases: list[dict[str, Any]], action: str, language: str) -> str:
    matching = [
        case
        for case in cases
        if case["action"] == action and case["language"] == language
    ]
    if not matching:
        return "  -  "
    passed = sum(1 for case in matching if case["passed"])
    return f"{passed:>2}/{len(matching):<2}"


def main() -> int:
    args = parse_args()
    reports = []
    for path in sorted(args.results.glob("*.json")):
        with path.open(encoding="utf-8") as file:
            reports.append((path.stem, json.load(file)))

    if not reports:
        print(f"No reports in {args.results}")
        return 1

    versions = {report["suiteVersion"] for _, report in reports}
    if len(versions) > 1:
        print(f"WARNING: reports span suite versions {sorted(versions)}; re-run the stale ones.\n")

    name_width = max(len(name) for name, _ in reports)
    header = f"{'model':<{name_width}}  score   runs  " + " ".join(
        f"{head:<6}" for head in ROLE_HEADERS
    ) + "  warm ms   peak GB  backend"
    print(header)
    print("-" * len(header))

    for name, report in reports:
        cases = report["cases"]
        score = report["score"]
        cells = " ".join(
            f"{role_cell(cases, action, language):<6}" for action, language in ROLES
        )
        warm = report["latency"].get("warmTotalMs")
        peak = report.get("peakMemoryGb")
        print(
            f"{name:<{name_width}}  "
            f"{score['passed']:>2}/{score['attempted']:<3} "
            f"{report['runsPerCase']:>4}  "
            f"{cells}  "
            f"{(str(warm) if warm is not None else '-'):>7}  "
            f"{(f'{peak:.1f}' if peak else '-'):>7}  "
            f"{report['backend']}"
        )

    print(
        "\nUnsupported slices are shown as '-' and are never counted as passes. "
        "Cells are passes/attempts,\nso a model sampled over several runs has "
        "proportionally larger denominators than a greedy single-run one."
    )
    for name, report in reports:
        skipped = report["score"]["skipped"]
        if skipped:
            print(f"  {name} skipped {len(skipped)}: {', '.join(skipped)}")

    print("\nRepeated failures across models (case: models failing):")
    failures: dict[str, set[str]] = defaultdict(set)
    for name, report in reports:
        for case in report["cases"]:
            if not case["passed"]:
                failures[case["id"]].add(name)
    for case_id, models in sorted(failures.items(), key=lambda item: -len(item[1])):
        print(f"  {case_id:<28} {len(models)}: {', '.join(sorted(models))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
