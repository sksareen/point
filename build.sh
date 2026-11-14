#!/bin/bash
# Build Point.app (default: ./build/Point.app). Override with APP_DIR=...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-$SCRIPT_DIR/build/Point.app}"

# Optional local override of the signing identity (gitignored), e.g.
#   echo 'POINT_SIGN_ID="My Existing Cert"' > .signing.local
[ -f "$SCRIPT_DIR/.signing.local" ] && source "$SCRIPT_DIR/.signing.local"
SIGN_ID="${POINT_SIGN_ID:-Point Dev}"

echo "Building Point..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/"

# Build number = commit count + short sha (+dirty), shown in the menu.
BUILD="$(git -C "$SCRIPT_DIR" rev-list --count HEAD 2>/dev/null || echo 0)"
SHA="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"
git -C "$SCRIPT_DIR" diff --quiet HEAD 2>/dev/null || SHA="$SHA+dirty"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD.$SHA" "$APP_DIR/Contents/Info.plist"

swiftc -O \
    -o "$APP_DIR/Contents/MacOS/Point" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework Speech \
    -framework ServiceManagement \
    -swift-version 5 \
    "$SCRIPT_DIR"/Sources/*.swift

# Sign with a stable identity so macOS privacy grants survive rebuilds.
if security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
    codesign --force --sign "$SIGN_ID" "$APP_DIR"
    echo "Signed with: $SIGN_ID"
else
    codesign --force --sign - "$APP_DIR"
    echo "⚠️  Signing identity '$SIGN_ID' not found — ad-hoc signed."
    echo "    macOS will forget Point's permissions on every rebuild. Run ./make-signing-cert.sh once."
fi

echo "Built: $APP_DIR"
