#!/bin/bash
# Print the most recent Point captures, newest first. Usage: latest.sh [count] [all]
# By default only captures with a screenshot (you circled something) are shown;
# pass "all" to include plain dictations too.
# Point (https://github.com/sksareen/point) saves one JSON per capture next to its screenshot.
set -u

COUNT="${1:-1}"
ALL="${2:-}"
[ "$COUNT" = "all" ] && { ALL="all"; COUNT=1; }
case "$COUNT" in ''|*[!0-9]*) COUNT=1 ;; esac
[ "$COUNT" -lt 1 ] && COUNT=1
[ "$COUNT" -gt 20 ] && COUNT=20

if [ "$(uname -s)" != "Darwin" ]; then
    echo "POINT_STATUS: unsupported (Point is a macOS app)"
    exit 0
fi

DIR="$(defaults read com.sksareen.point capturesFolderPath 2>/dev/null || true)"
[ -n "$DIR" ] || DIR="$HOME/Library/Application Support/Point/captures"

if [ ! -d "$DIR" ]; then
    if [ -d "/Applications/Point.app" ]; then
        echo "POINT_STATUS: installed, no captures yet"
    else
        echo "POINT_STATUS: not installed"
    fi
    exit 0
fi

field() { plutil -extract "$1" raw -o - "$2" 2>/dev/null || true; }

FOUND=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    shot="$(field screenshot "$f")"
    case "$shot" in *.png) ;; *) shot="" ;; esac
    [ -n "$shot" ] || [ "$ALL" = "all" ] || continue
    [ -z "$shot" ] || [ -f "$shot" ] || shot=""
    FOUND=$((FOUND + 1))
    echo "--- capture $FOUND ---"
    echo "when: $(field created_at "$f")"
    echo "app: $(field app "$f")"
    echo "kind: $(field kind "$f")"
    echo "screenshot: ${shot:-none (dictation only)}"
    echo "transcript: $(field transcript "$f")"
    [ "$FOUND" -lt "$COUNT" ] || break
done < <(ls -t "$DIR"/point_*.json 2>/dev/null)

if [ "$FOUND" -eq 0 ]; then
    if [ "$ALL" = "all" ]; then echo "POINT_STATUS: installed, no captures yet"
    else echo "POINT_STATUS: installed, no captures with a screenshot yet"; fi
fi
