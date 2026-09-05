#!/usr/bin/env bash
# Run HAL's rewrite eval against an OpenAI-compatible endpoint — the canonical path.
# The model is external by construction: this script never learns where weights live.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Evals/src/endpoint_eval.py"
CASES="$ROOT/Evals/src/cases.json"
PROMPTS="$ROOT/Evals/src/prompts.json"
PYTHON="${HAL_EVAL_PYTHON:-python3}"
ENDPOINT="${HAL_EVAL_ENDPOINT:-${1:-}}"

if [[ -z "$ENDPOINT" ]]; then
  echo "usage: scripts/eval-endpoint-rewrite.sh <chat-completions-url>" >&2
  echo "   or: HAL_EVAL_ENDPOINT=<url> scripts/eval-endpoint-rewrite.sh" >&2
  echo >&2
  echo "Serve any checkpoint yourself, e.g.:" >&2
  echo "  mlx_lm.server --model <dir> --host 0.0.0.0 --port 8901 \\" >&2
  echo "    --chat-template-args '{\"enable_thinking\":false}'" >&2
  exit 2
fi

ARGS=("$SOURCE" --endpoint "$ENDPOINT" --cases "$CASES" --prompts "$PROMPTS")
[[ -n "${HAL_EVAL_MODEL:-}" ]] && ARGS+=(--model "$HAL_EVAL_MODEL")
[[ -n "${HAL_EVAL_LABEL:-}" ]] && ARGS+=(--label "$HAL_EVAL_LABEL")
[[ -n "${HAL_EVAL_REPORT:-}" ]] && ARGS+=(--report "$HAL_EVAL_REPORT")

exec "$PYTHON" "${ARGS[@]}"
