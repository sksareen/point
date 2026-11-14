#!/bin/bash
# Build → /Applications/Point.app → launch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/Point.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

APP_DIR="$STAGE/Point.app" "$SCRIPT_DIR/build.sh"

echo "Installing to $DEST..."
pkill -x Point 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$STAGE/Point.app" "$DEST"
codesign --verify --strict "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
open "$DEST"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist")"
cat <<MSG

Point $VERSION ($BUILD) installed and running.
  hold Right ⌥ + talk        → dictate at your text cursor
  … and draw a loop          → + screenshot with your loop on it
  double-tap Right ⌥ / ⌃⇧N   → sticky pad
First run: grant Accessibility, Microphone, and (on first loop) Screen Recording.
MSG
