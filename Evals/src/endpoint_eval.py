#!/usr/bin/env python3
"""Run HAL's rewrite eval against an OpenAI-compatible endpoint.

This is the canonical runner: it sends the request HAL sends, so what it measures is
what the product experiences. The model is external by construction — a server the
user operates, here or anywhere else. Nothing in this repository knows where weights
live, which runtime loads them, or how they are quantized, and nothing needs to.

Adding a model to the eval is adding a URL, never a checkpoint path.
"""

from __future__ import annotations

import argparse
import os
import platform
import re
import statistics
import sys
from pathlib import Path
from typing import Any

from endpoint_client import ChatClient, EndpointError
from eval_common import (
    case_record,
    hal_user_prompt,
    indent,
    load_json,
    utc_timestamp,
    violations,
    write_report,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", required=True,
                        help="Chat-completions URL, e.g. http://127.0.0.1:8901/v1/chat/completions")
    parser.add_argument("--model", default=None,
                        help="Model name the server expects. Omitted from the request when unset.")
    parser.add_argument("--label", default=None, help="Name for this endpoint in the report")
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--prompts", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--max-tokens", type=int, default=512)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    suite = load_json(args.cases)
    prompt_suite = load_json(args.prompts)
    cases = suite["cases"]
    client = ChatClient(
        url=args.endpoint,
        model=args.model,
        timeout=args.timeout,
    )
    label = args.label or args.model or args.endpoint

    requested_case = os.environ.get("HAL_REWRITE_EVAL_CASE")
    if requested_case:
        cases = [test for test in cases if test["id"] == requested_case]
        if not cases:
            raise ValueError(f"No eval case matched HAL_REWRITE_EVAL_CASE={requested_case}")

    runs = int(os.environ.get("HAL_REWRITE_EVAL_RUNS", "1"))
    if not 1 <= runs <= 20:
        raise ValueError("HAL_REWRITE_EVAL_RUNS must be between 1 and 20")

    for test in cases:
        if test["action"] not in prompt_suite["actions"]:
            raise ValueError(f"No prompt for action {test['action']}")
        for key in ("requiredPatterns", "forbiddenPatterns"):
            for pattern in test["checks"].get(key, []):
                re.compile(pattern)

    print(f"{suite['suite']} v{suite['version']}")
    print(f"Prompt: {prompt_suite['version']}")
    print(f"Endpoint: {client.describe()}")
    print(f"Client: {platform.platform()}")
    print(f"Runs per case: {runs}")

    floor = client.transport_floor()
    if floor.get("samples"):
        print(f"Transport floor: {floor['medianMs']} ms median · "
              f"{floor['minMs']}-{floor['maxMs']} ms · jitter {floor['jitterMs']} ms")
    else:
        print("Transport floor: unavailable")

    passed = 0
    case_records: list[dict[str, Any]] = []
    timings: list[int] = []
    for test in cases:
        prompt_spec = prompt_suite["actions"][test["action"]]
        messages = [
            {"role": "system", "content": prompt_spec["instructions"]},
            {"role": "user", "content": hal_user_prompt(prompt_spec, test["input"])},
        ]
        for run_index in range(1, runs + 1):
            try:
                reply = client.chat(messages, args.max_tokens)
            except EndpointError as error:
                print(f"\n[ERROR] {test['id']} · run {run_index}/{runs}: {error}")
                case_records.append(case_record(test, run_index, "", [f"endpoint error: {error}"], {}))
                continue
            timings.append(reply.elapsed_ms)
            failures = violations(reply.text, test)
            if not failures:
                passed += 1
            model_ms = max(reply.elapsed_ms - floor["medianMs"], 0) if floor.get("samples") else None
            case_records.append(case_record(test, run_index, reply.text, failures, {
                "totalMs": reply.elapsed_ms,
                "modelMs": model_ms,
                "promptTokens": reply.prompt_tokens,
                "generatedTokens": reply.completion_tokens,
            }))
            status = "PASS" if not failures else "FAIL"
            print(f"\n[{status}] {test['id']} · {test['title']} · run {run_index}/{runs} · "
                  f"{reply.elapsed_ms} ms total"
                  + (f" · ~{model_ms} ms model" if model_ms is not None else ""))
            print("  output:")
            print(indent(reply.text))
            if failures:
                print("  violations:")
                for failure in failures:
                    print(f"    - {failure}")

    attempted = len(timings)
    if not attempted:
        print("\nNo successful requests — the endpoint never answered.")
        return 2

    print(f"\nSummary: {passed}/{attempted} passed · average total {statistics.mean(timings):.0f} ms")
    if floor.get("samples"):
        print(f"Average model time (total minus {floor['medianMs']} ms transport floor): "
              f"{statistics.mean(timings) - floor['medianMs']:.0f} ms")

    if args.report:
        write_report(args.report, {
            "suite": suite["suite"],
            "suiteVersion": suite["version"],
            "promptVersion": prompt_suite["version"],
            "promptStyle": "hal",
            "backend": "openai-compatible",
            "endpoint": args.endpoint,
            "platform": platform.platform(),
            "model": label,
            "profile": "hal",
            "recordedAt": utc_timestamp(),
            "runsPerCase": runs,
            "transportFloor": floor,
            "score": {"passed": passed, "attempted": attempted, "skipped": []},
            "latency": {
                "meanTotalMs": round(statistics.mean(timings)),
                "medianTotalMs": round(statistics.median(timings)),
                "minTotalMs": min(timings),
                "maxTotalMs": max(timings),
                "meanModelMs": (round(statistics.mean(timings) - floor["medianMs"])
                                if floor.get("samples") else None),
            },
            "cases": case_records,
        })
        print(f"Structured report: {args.report}")

    if os.environ.get("HAL_REWRITE_EVAL_STRICT") == "1" and passed != attempted:
        print("Strict mode: failed")
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EndpointError as error:
        print(f"endpoint error: {error}", file=sys.stderr)
        raise SystemExit(2) from error
    except Exception as error:
        print(f"eval error: {error}", file=sys.stderr)
        raise SystemExit(2) from error
