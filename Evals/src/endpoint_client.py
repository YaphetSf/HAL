"""Transport for the OpenAI-compatible endpoint HAL speaks to.

Kept separate from `eval_common` (fixtures and invariants) because this is the one
place that knows about the wire. Standard library only: the eval must run wherever
HAL runs, and HAL ships no Python.
"""

from __future__ import annotations

import json
import statistics
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any


class EndpointError(RuntimeError):
    """A transport or contract failure that is the endpoint's fault, not the model's."""


@dataclass(frozen=True)
class Reply:
    text: str
    elapsed_ms: int
    prompt_tokens: int | None
    completion_tokens: int | None


@dataclass(frozen=True)
class ChatClient:
    url: str
    model: str | None = None
    timeout: float = 120.0

    def describe(self) -> str:
        return f"{self.url} · model {self.model if self.model else '(omitted — server default)'}"

    def _post(self, body: dict[str, Any]) -> tuple[dict[str, Any], int]:
        payload = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(self.url, data=payload, method="POST")
        request.add_header("Content-Type", "application/json")
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:400]
            raise EndpointError(f"HTTP {error.code}: {detail}") from error
        except urllib.error.URLError as error:
            raise EndpointError(f"cannot reach endpoint: {error.reason}") from error
        elapsed_ms = round((time.perf_counter() - started) * 1_000)
        try:
            return json.loads(raw), elapsed_ms
        except json.JSONDecodeError as error:
            raise EndpointError(f"endpoint returned non-JSON: {raw[:200]!r}") from error

    def chat(self, messages: list[dict[str, str]], max_tokens: int) -> Reply:
        body: dict[str, Any] = {
            "messages": messages,
            "temperature": 0.0,
            "max_tokens": max_tokens,
            "stream": False,
        }
        # An empty model string makes mlx_lm.server try to load a model named "".
        if self.model:
            body["model"] = self.model

        data, elapsed_ms = self._post(body)
        choices = data.get("choices") or []
        if not choices:
            raise EndpointError(f"no choices in response: {json.dumps(data)[:300]}")
        message = choices[0].get("message") or {}
        text = (message.get("content") or "").strip()
        if not text:
            reasoning = (message.get("reasoning") or message.get("reasoning_content") or "").strip()
            if reasoning:
                raise EndpointError(
                    "server returned empty content with a populated reasoning field — start it "
                    "with thinking disabled (mlx_lm.server: "
                    "--chat-template-args '{\"enable_thinking\":false}')"
                )
        usage = data.get("usage") or {}
        return Reply(
            text=text,
            elapsed_ms=elapsed_ms,
            prompt_tokens=usage.get("prompt_tokens"),
            completion_tokens=usage.get("completion_tokens"),
        )

    def transport_floor(self, samples: int = 5) -> dict[str, Any]:
        """Cost of a near-empty completion: round trip plus server fixed overhead.

        Subtracting this separates 'the model is slow' from 'the link is slow', which
        matters because a remote endpoint's jitter can exceed the difference between
        two candidate models.
        """
        timings: list[int] = []
        for _ in range(samples):
            try:
                timings.append(self.chat([{"role": "user", "content": "hi"}], max_tokens=1).elapsed_ms)
            except EndpointError:
                return {"samples": 0}
        return {
            "samples": len(timings),
            "medianMs": round(statistics.median(timings)),
            "minMs": min(timings),
            "maxMs": max(timings),
            "jitterMs": max(timings) - min(timings),
        }
