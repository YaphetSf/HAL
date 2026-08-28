#!/usr/bin/env bash
# Live HAL logs (D14: subsystem com.hal.inputmethod, categories imk/engine/panel).
set -euo pipefail
exec /usr/bin/log stream --style compact --level debug \
  --predicate 'subsystem == "com.hal.inputmethod"'
