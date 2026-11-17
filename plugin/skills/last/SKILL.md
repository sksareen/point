---
name: last
description: "Pull in the user's most recent Point capture (the screenshot they circled plus what they said) without them pasting anything. Use when the user says to look at what they just pointed at, their last capture, or the thing they circled, or runs /point:last."
argument-hint: "[how many] [all]"
---

# Read the latest Point capture

Point saves one JSON file per capture, next to its screenshot. Find the newest ones with these commands. Arguments from the user: `$ARGUMENTS`. A number means that many captures (default 1, at most 20). The word `all` means include plain dictations that have no screenshot.

1. Find the captures folder. It is a custom folder if the user chose one in Point's settings, otherwise the default:

   ```bash
   DIR="$(defaults read com.sksareen.point capturesFolderPath 2>/dev/null)"; [ -n "$DIR" ] || DIR="$HOME/Library/Application Support/Point/captures"; echo "$DIR"; ls -d /Applications/Point.app 2>/dev/null
   ```

2. List the newest capture files:

   ```bash
   ls -t "$DIR"/point_*.json 2>/dev/null | head -n 40
   ```

3. Read them newest first with the Read tool. Each has `transcript`, `screenshot` (a path to a PNG, or null for a plain dictation), `app`, `created_at`, and `kind`. Skip the ones with no screenshot unless the user asked for `all`. Stop when you have as many as they asked for.

## Then

1. For each capture with a `screenshot`, read that image.
2. Interpret it the way the `captures` skill describes: the red loop or rectangle marks what the user means, and the `transcript` is what they said about it.
3. If the user gave an instruction along with this command, carry it out using the capture as the subject. If they did not, say in one or two sentences what they circled and what they said, then do what the transcript asks, or ask what they want if it asks for nothing.

## If there is nothing to read

- **The folder is missing and `/Applications/Point.app` is not there:** Point is not installed. Tell the user it is a free, open-source macOS app (macOS 26, Apple Silicon) at https://github.com/sksareen/point.
- **Point is installed but there are no captures with a screenshot:** tell them to hold their trigger key (Right Option by default), circle something on screen while talking, and let go. Offer to include their dictations with `all`.
- **Not on macOS:** Point only runs on macOS.
