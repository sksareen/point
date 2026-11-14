#!/bin/bash
# Install Point in one line:
#   curl -fsSL https://raw.githubusercontent.com/sksareen/point/master/get.sh | bash
#
# Downloads the latest release into /Applications and launches it. Files fetched
# with curl aren't quarantined, so macOS doesn't show the "unidentified developer"
# block that browser downloads of un-notarized apps get.
set -euo pipefail

fail() { echo "Point: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Point only runs on macOS."
VER="$(sw_vers -productVersion)"
[ "${VER%%.*}" -ge 26 ] || fail "Point needs macOS 26 or later (this Mac has $VER)."
[ "$(uname -m)" = "arm64" ] || fail "Point currently needs an Apple Silicon Mac."

URL="https://github.com/sksareen/point/releases/latest/download/Point.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Point..."
curl -fsSL "$URL" -o "$TMP/Point.zip" || fail "couldn't download $URL"
ditto -x -k "$TMP/Point.zip" "$TMP"
[ -d "$TMP/Point.app" ] || fail "the download didn't contain Point.app"

echo "Installing to /Applications..."
pkill -x Point 2>/dev/null && sleep 1 || true
rm -rf /Applications/Point.app
ditto "$TMP/Point.app" /Applications/Point.app
xattr -dr com.apple.quarantine /Applications/Point.app 2>/dev/null || true
open /Applications/Point.app

cat <<'MSG'

Point is installed and running. Look for the ☝ in your menu bar.
Grant Accessibility and Microphone when asked, and Screen Recording the
first time you draw a loop. Then hold Right Option and talk.
MSG
