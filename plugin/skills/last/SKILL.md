---
name: last
description: Pull in the user's most recent Point capture (the screenshot they circled plus what they said) without them pasting anything. Use when the user says "look at what I just pointed at", "my last capture", "the thing I circled", or runs /point:last.
argument-hint: "[how many] [all]"
---

# Read the latest Point capture

Run this script. It prints the most recent captures, newest first:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/latest.sh" $ARGUMENTS
```

- With no arguments it prints the single most recent capture that has a screenshot.
- A number prints that many, for example `3`.
- `all` also includes plain dictations that have no screenshot.

## Then

1. For each capture that lists a `screenshot` path, read that image.
2. Interpret it the way the `captures` skill describes: the red loop or rectangle marks what the user means, and the `transcript` is what they said about it.
3. If the user gave an instruction along with this command, carry it out using the capture as the subject. If they did not, state in one or two sentences what they circled and what they said, then do what the transcript asks, or ask what they want if it asks for nothing.

## If the script reports a status instead

- `POINT_STATUS: not installed`: Point is not on this Mac. Tell the user it is a free, open-source macOS app (macOS 26, Apple Silicon) and that they can get it at https://github.com/sksareen/point.
- `POINT_STATUS: installed, no captures with a screenshot yet`: tell them to hold their trigger key (Right Option by default), circle something on screen while talking, and let go. Offer to rerun with `all` if they want their dictations.
- `POINT_STATUS: installed, no captures yet`: same instruction as above.
- `POINT_STATUS: unsupported`: Point only runs on macOS.
