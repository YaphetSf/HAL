#!/usr/bin/env bash
# Compile and run the real-device Foundation Models capability eval used by HAL's
# selection rewrite prototype. This is intentionally separate from xcodebuild test:
# it requires Apple Intelligence, invokes a nondeterministic system model, and is tied
# to the model version shipped by the current macOS release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Evals/src/main.swift"
CASES="$ROOT/Evals/src/cases.json"
PROMPTS="$ROOT/Evals/src/prompts.json"
BUILD="$ROOT/.build/LocalRewriteEval"
BINARY="$BUILD/local-rewrite-eval"

command -v xcrun >/dev/null 2>&1 || { echo "xcrun missing" >&2; exit 2; }
mkdir -p "$BUILD/ModuleCache"

echo "==> compiling HAL local rewrite eval"
xcrun swiftc \
  -parse-as-library \
  -target arm64-apple-macosx26.0 \
  -module-cache-path "$BUILD/ModuleCache" \
  "$SOURCE" \
  -o "$BINARY"

echo "==> running against the current macOS on-device model"
if [[ -n "${HAL_FOUNDATION_REPORT:-}" ]]; then
  "$BINARY" "$CASES" "$PROMPTS" "$HAL_FOUNDATION_REPORT"
else
  "$BINARY" "$CASES" "$PROMPTS"
fi
