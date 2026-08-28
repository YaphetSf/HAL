#!/usr/bin/env bash
# Dev loop: rebuild -> ad-hoc sign -> ditto over installed locations -> restart.
#
# The canonical install locations stay at the same paths after every rebuild, so Launch
# Services + Text Input Manager keep resolving the bundle ID to the live binary and no
# System Settings detour is needed between edits.
#
# Override config / signing identity via env:
#   HAL_CODESIGN_IDENTITY="Developer ID Application: ..."   (default: ad-hoc)
#   CONFIG=Debug                                            (default: Release)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT=HAL
SCHEME=HAL
APP_NAME=HAL_input
CONTROL_CENTER=HAL
CONFIG="${CONFIG:-Release}"
DERIVED="$ROOT/.build/DerivedData"
DEST="$HOME/Library/Input Methods"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen missing" >&2; exit 1; }

# Local builds are ad-hoc unless explicitly overridden.
IDENTITY="${HAL_CODESIGN_IDENTITY:--}"

echo "==> xcodegen"
xcodegen generate --quiet

echo "==> xcodebuild ($CONFIG, identity: $IDENTITY)"
xcodebuild -project "$PROJECT.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
  -quiet build 2>&1 | { grep -v "DVTDeviceOperation" || true; }

INPUT_APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$INPUT_APP" ] || { echo "missing build product: $INPUT_APP" >&2; exit 1; }

CONTROL_CENTER_BUILD="$DERIVED/Build/Products/$CONFIG/$CONTROL_CENTER.app"
CONTROL_CENTER_DEST="$HOME/Applications/$CONTROL_CENTER.app"

# The control center ships HAL_input as a payload for its repair/update flow. Refresh it
# on every rebuild so the carried binary matches the one we just installed.
if [ -d "$CONTROL_CENTER_BUILD" ]; then
  PAYLOAD="$CONTROL_CENTER_BUILD/Contents/Resources/HAL_input.zip"
  rm -f "$PAYLOAD"
  ditto -c -k --keepParent --sequesterRsrc "$INPUT_APP" "$PAYLOAD"
  codesign --force --timestamp=none --options runtime --sign "$IDENTITY" "$CONTROL_CENTER_BUILD"
fi

echo "==> stopping $APP_NAME / $CONTROL_CENTER"
/usr/bin/killall -q "$APP_NAME" 2>/dev/null || true
/usr/bin/killall -q "$CONTROL_CENTER" 2>/dev/null || true

echo "==> installing into $DEST"
mkdir -p "$DEST"
ditto "$INPUT_APP" "$DEST/$APP_NAME.app"

if [ -d "$CONTROL_CENTER_BUILD" ]; then
  echo "==> installing $CONTROL_CENTER.app into $HOME/Applications"
  mkdir -p "$HOME/Applications"
  ditto "$CONTROL_CENTER_BUILD" "$CONTROL_CENTER_DEST"
fi

# Every build product carries the same bundle ID as the installed copy, so Launch Services
# can resolve com.hal.inputmethod.HAL to a DerivedData build and System Settings stops
# offering HAL under Input Sources. Same hazard for the control center.
unregister_repo_copies() {
  for id in com.hal.inputmethod.HAL com.hal.inputmethod.HALSettings; do
    "$LSREGISTER" -dump 2>/dev/null \
      | awk -v want="$id" '
          /^path:/       { p = $0; sub(/^path:[ \t]*/, "", p); sub(/ \([0-9a-fx]+\)$/, "", p) }
          /^identifier:/ { if ($2 == want && p != "") print p; p = "" }
        ' \
      | sort -u \
      | awk -v root="$ROOT/" 'index($0, root) == 1' \
      | while IFS= read -r stray; do
          "$LSREGISTER" -u "$stray" >/dev/null 2>&1 || true
        done
  done
}

echo "==> unregistering DerivedData copies"
unregister_repo_copies

[ -d "$CONTROL_CENTER_DEST" ] && "$LSREGISTER" -f "$CONTROL_CENTER_DEST" >/dev/null 2>&1 || true

echo "==> registering input source"
"$DEST/$APP_NAME.app/Contents/MacOS/$APP_NAME" --register

echo "==> launching"
/usr/bin/open "$DEST/$APP_NAME.app"

echo "Done. Edit and re-run."
