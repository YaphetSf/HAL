#!/usr/bin/env bash
# Build a signed, notarized, arm64-only DMG containing HAL.app.
#
# Pipeline (notarize is skipped when HAL_SKIP_NOTARIZE=1; result is an ad-hoc preview DMG
# that must not be published):
#   1. Build arm64 HAL_input.app + HAL.app
#   2. Sign rime plugins -> librime -> HAL_input.app
#   3. Notarize #1: HAL_input.app + staple
#   4. Embed HAL_input.zip in HAL.app + re-sign HAL.app
#   5. Render DMG background
#   6. Notarize #2: HAL.app + staple
#   7. Build DMG with Finder-positioned icon layout
#   8. Sign DMG
#   9. Notarize #3: DMG + staple + validate + spctl
#
# Output:
#   dist/HAL-<version>-arm64.dmg           notarized, signed, arm64-only
#   dist/HAL-<version>-arm64-preview.dmg   ad-hoc, only when HAL_SKIP_NOTARIZE=1
#
# Override:
#   HAL_CODESIGN_IDENTITY="Developer ID Application: ..."
#   HAL_NOTARY_PROFILE=<keychain-profile>     default: QRStudio
#   HAL_SKIP_NOTARIZE=1                       preview DMG, do not distribute
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT=HAL
SCHEME=HAL
APP_NAME=HAL
INPUT_NAME=HAL_input
ENTITLEMENTS="$ROOT/scripts/HAL_input.entitlements"
DERIVED="$ROOT/.build/ReleaseDerivedData"
STAGE="$ROOT/.build/stage"
DMG_ROOT="$STAGE/dmg"
DIST_DIRECTORY="$ROOT/dist"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

NOTARY_PROFILE="${HAL_NOTARY_PROFILE:-QRStudio}"
SKIP_NOTARIZE="${HAL_SKIP_NOTARIZE:-0}"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "$VERSION" ] || { echo "could not read MARKETING_VERSION from project.yml" >&2; exit 1; }
VOLUME="HAL $VERSION"
FINAL_DMG="$DIST_DIRECTORY/HAL-$VERSION-arm64.dmg"
PREVIEW_DMG="$DIST_DIRECTORY/HAL-$VERSION-arm64-preview.dmg"
RW_DMG="$STAGE/HAL-rw.dmg"
MOUNT_DIR="$STAGE/mount"
DMG_DEVICE=""

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is missing" >&2; exit 1; }

IDENTITY="${HAL_CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  if [ "$SKIP_NOTARIZE" = "1" ]; then
    IDENTITY=-
  else
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  fi
fi
[ -n "$IDENTITY" ] || { echo "no Developer ID Application identity" >&2; exit 1; }
if [ "$SKIP_NOTARIZE" != "1" ] && [ "$IDENTITY" = - ]; then
  echo "Developer ID Application identity required when notarizing" >&2
  exit 1
fi
if [ "$SKIP_NOTARIZE" != "1" ] \
   && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "invalid notary profile: $NOTARY_PROFILE" >&2
  exit 1
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

cleanup() {
  if [ -n "$DMG_DEVICE" ]; then
    hdiutil detach -quiet "$DMG_DEVICE" 2>/dev/null || true
  fi
  unregister_repo_copies
}
trap cleanup EXIT

sign() {
  if [ "$IDENTITY" = - ]; then
    codesign --force --timestamp=none --options runtime --sign - "$@"
  else
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"
  fi
}

echo "==> build (Release, identity: $IDENTITY)"
xcodegen generate --quiet
rm -rf "$DERIVED"
xcodebuild -project "$PROJECT.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
  -quiet build 2>&1 | { grep -v DVTDeviceOperation || true; }

PRODUCTS="$DERIVED/Build/Products/Release"
[ -d "$PRODUCTS/$INPUT_NAME.app" ] || { echo "missing $INPUT_NAME.app" >&2; exit 1; }
[ -d "$PRODUCTS/$APP_NAME.app" ] || { echo "missing $APP_NAME.app" >&2; exit 1; }

echo "==> stage"
rm -rf "$STAGE"
mkdir -p "$DMG_ROOT/.background"
ditto "$PRODUCTS/$INPUT_NAME.app" "$STAGE/$INPUT_NAME.app"
ditto "$PRODUCTS/$APP_NAME.app" "$DMG_ROOT/$APP_NAME.app"
INPUT_APP="$STAGE/$INPUT_NAME.app"
HAL_APP="$DMG_ROOT/$APP_NAME.app"

# D20: ship arm64 only. Thicken the layout: anything still carrying x86_64 after the
# thin pass fails the build.
echo "==> arm64"
find "$INPUT_APP" "$HAL_APP" -type f -perm -u+r -print0 | while IFS= read -r -d '' file_path; do
  case "$(file -b "$file_path")" in
    *"Mach-O universal"*)
      lipo -thin arm64 "$file_path" -output "$file_path.arm64"
      mv "$file_path.arm64" "$file_path"
      ;;
  esac
done

echo "==> sign $INPUT_NAME.app"
for dylib in "$INPUT_APP/Contents/Frameworks/rime-plugins/"*.dylib; do
  sign "$dylib"
done
sign "$INPUT_APP/Contents/Frameworks/librime.1.dylib"
sign --entitlements "$ENTITLEMENTS" "$INPUT_APP"
codesign --verify --deep --strict "$INPUT_APP"

STRAYS="$STAGE/arch-strays.txt"
: > "$STRAYS"
find "$INPUT_APP" "$HAL_APP" -type f -print0 | while IFS= read -r -d '' file_path; do
  case "$(file -b "$file_path")" in
    *Mach-O*)
      archs="$(lipo -archs "$file_path")"
      [ "$archs" = arm64 ] || echo "$file_path [$archs]" >> "$STRAYS"
      ;;
  esac
done
if [ -s "$STRAYS" ]; then cat "$STRAYS" >&2; exit 1; fi

if [ "$SKIP_NOTARIZE" != "1" ]; then
  echo "==> notarize $INPUT_NAME.app"
  ditto -c -k --keepParent --sequesterRsrc "$INPUT_APP" "$STAGE/$INPUT_NAME-notary.zip"
  xcrun notarytool submit "$STAGE/$INPUT_NAME-notary.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$INPUT_APP"
fi

# Embedding changes HAL.app's signature; re-sign before presenting it for notarize #2.
echo "==> embed $INPUT_NAME"
ditto -c -k --keepParent --sequesterRsrc "$INPUT_APP" \
  "$HAL_APP/Contents/Resources/$INPUT_NAME.zip"
sign "$HAL_APP"
codesign --verify --deep --strict "$HAL_APP"

echo "==> render DMG background"
/usr/bin/swift -module-cache-path "$STAGE/SwiftModuleCache" \
  "$ROOT/scripts/dist/render-background.swift" \
  "$ROOT/scripts/dist/dmg-background.svg" "$DMG_ROOT/.background/background.png"

if [ "$SKIP_NOTARIZE" != "1" ]; then
  echo "==> notarize $APP_NAME.app"
  ditto -c -k --keepParent --sequesterRsrc "$HAL_APP" "$STAGE/$APP_NAME-notary.zip"
  xcrun notarytool submit "$STAGE/$APP_NAME-notary.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$HAL_APP"
fi

# DMG layout uses AppleScript to drive Finder; needs a logged-in GUI session.
build_dmg() {
  local destination="$1"
  rm -f "$destination" "$RW_DMG"
  hdiutil create -volname "$VOLUME" -srcfolder "$DMG_ROOT" \
    -ov -format UDRW -quiet "$RW_DMG"
  rm -rf "$MOUNT_DIR"
  mkdir -p "$MOUNT_DIR"
  DMG_DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen \
    -mountpoint "$MOUNT_DIR" "$RW_DMG" \
    | awk '/Apple_APFS|Apple_HFS/ {print $1; exit}')"
  [ -n "$DMG_DEVICE" ] || { echo "could not mount DMG" >&2; exit 1; }

  osascript <<APPLESCRIPT
set dmgFolder to POSIX file "$MOUNT_DIR" as alias
set bgPicture to POSIX file "$MOUNT_DIR/.background/background.png"
tell application "Finder"
  activate
  open dmgFolder
  delay 2
  set dmgWindow to front window
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to {100, 100, 760, 550}
  set viewOptions to icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 112
  set text size of viewOptions to 13
  set shows icon preview of viewOptions to false
  set background picture of viewOptions to bgPicture
  set position of item "$APP_NAME.app" of dmgFolder to {330, 225}
  delay 2
  close dmgWindow
end tell
APPLESCRIPT

  rm -rf "$MOUNT_DIR/.fseventsd"
  sync
  hdiutil detach -quiet "$DMG_DEVICE"
  DMG_DEVICE=""
  hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 \
    -o "$destination" -quiet
  rm -f "$RW_DMG"
}

mkdir -p "$DIST_DIRECTORY"
if [ "$SKIP_NOTARIZE" = "1" ]; then
  echo "==> preview DMG"
  build_dmg "$PREVIEW_DMG"
  echo "$PREVIEW_DMG"
  exit 0
fi

echo "==> final DMG"
build_dmg "$FINAL_DMG"
codesign --force --timestamp --sign "$IDENTITY" "$FINAL_DMG"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"
spctl -a -vv -t open --context context:primary-signature "$FINAL_DMG"
echo "$FINAL_DMG"
