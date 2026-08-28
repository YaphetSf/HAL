#!/usr/bin/env bash
# Stop the process and remove ~/Library/Input Methods/HAL_input.app.
set -euo pipefail

APP_NAME="HAL_input"
DEST="$HOME/Library/Input Methods/$APP_NAME.app"

killall -q "$APP_NAME" 2>/dev/null || true

# HAL remaps Caps Lock to F18 while it runs; hand the key back even if it was killed hard.
hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || true

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  echo "removed $DEST"
else
  echo "not installed: $DEST does not exist"
fi

echo "Also remove HAL under System Settings > Keyboard > Text Input > Input Sources."
echo "User data (~/Library/Application Support/HAL) is kept; delete it by hand if you want it gone."
