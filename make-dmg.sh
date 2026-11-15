#!/bin/bash
# Build Point.dmg: open it, drag Point onto Applications. Output: ./build/Point.dmg
# Uses dmgbuild (via uvx), which writes the Finder window layout directly,
# so no Finder scripting or Automation permission is needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/build/Point.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

APP_DIR="$STAGE/Point.app" "$SCRIPT_DIR/build.sh"

mkdir -p "$SCRIPT_DIR/build"
rm -f "$OUT"
uvx dmgbuild -s "$SCRIPT_DIR/Resources/dmg-settings.py" -D app="$STAGE/Point.app" -D bg="$SCRIPT_DIR/Resources/dmg-background.png" -D icon="$SCRIPT_DIR/Resources/Point.icns" "Point" "$OUT"

echo "Built: $OUT"
