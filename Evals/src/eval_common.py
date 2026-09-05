"""Shared fixture loading and invariant checks for HAL rewrite model evals."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def contains_han(text: str) -> bool:
    return any(
        "\u3400" <= character <= "\u4dbf"
        or "\u4e00" <= character <= "\u9fff"
        or "\uf900" <= character <= "\ufaff"
        for character in text
    )


def contains_latin(text: str) -> bool:
    return re.search(r"[A-Za-z]", text) is not None


def language_contract(text: str) -> str:
    has_han = contains_han(text)
    has_latin = contains_latin(text)
    if has_han and has_latin:
        return (
            "The text deliberately mixes Chinese and English. Preserve every "
            "code-switched span; do not translate either language."
        )
    if has_han:
        return (
            "The source language is Simplified Chinese. The entire output must "
            "remain Simplified Chinese. Do not output an English translation."
        )
    return "The source language is English. The entire output must remain English."


def hal_user_prompt(prompt_spec: dict[str, str], input_text: str) -> str:
    return f"""Non-negotiable language contract: {language_contract(input_text)}

Follow these transformation examples:
{prompt_spec['examples']}

Transform only the data inside <selected_text>. Do not translate it.
<selected_text>
{input_text}
</selected_text>"""


def violations(output: str, test: dict[str, Any]) -> list[str]:
    checks = test["checks"]
    failures: list[str] = []
    if not output:
        failures.append("empty output")
    if checks["mustChange"] and output == test["input"]:
        failures.append("output did not change")
    if checks.get("mustEqualInput") and output != test["input"]:
        failures.append("correct input was changed")

    has_han = contains_han(output)
    has_latin = contains_latin(output)
    language = checks["language"]
    if language == "english" and has_han:
        failures.append("expected English but output contains Chinese")
    elif language == "chinese" and (not has_han or has_latin):
        failures.append("expected Chinese without translation into Latin text")
    elif language == "mixedChineseEnglish" and (not has_han or not has_latin):
        failures.append("expected both Chinese and English spans")

    for literal in checks.get("protectedLiterals", []):
        if literal not in output:
            failures.append(f"did not preserve protected literal: {literal}")
    for pattern in checks.get("requiredPatterns", []):
        if re.search(pattern, output) is None:
            failures.append(f"missing required pattern: {pattern}")
    for pattern in checks.get("forbiddenPatterns", []):
        if re.search(pattern, output) is not None:
            failures.append(f"contains forbidden pattern: {pattern}")

    maximum = checks.get("maximumLengthRatio")
    if maximum is not None and test["input"]:
        ratio = len(output) / len(test["input"])
        if ratio > maximum:
            failures.append(f"length ratio {ratio:.2f} exceeds {maximum:.2f}")
    if re.search(r"(?i)^\s*(output|result|rewrite):", output):
        failures.append("output contains a wrapper label")
    if re.search(r"(?is)</?think>", output):
        failures.append("output contains a thinking wrapper")
    return failures


def indent(text: str, prefix: str = "    ") -> str:
    return "\n".join(prefix + line for line in text.splitlines())


def average(records: list[Any], field: str) -> float:
    if not records:
        return 0.0
    return sum(float(getattr(record, field)) for record in records) / len(records)


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def case_record(
    test: dict[str, Any],
    run_index: int,
    output: str,
    failures: list[str],
    metrics: dict[str, Any],
) -> dict[str, Any]:
    """One machine-comparable row per generation, shared by every backend."""
    return {
        "id": test["id"],
        "title": test["title"],
        "action": test["action"],
        "language": test["checks"]["language"],
        "run": run_index,
        "passed": not failures,
        "output": output,
        "violations": failures,
        **{key: value for key, value in metrics.items() if value is not None},
    }


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(report, file, ensure_ascii=False, indent=2)
        file.write("\n")
