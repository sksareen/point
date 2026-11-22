# Install Point (instructions for an AI agent)

You are installing **Point** for the user. Point is a free, open-source Mac app: the user holds a key, talks, and circles something on screen, and Point pastes their words plus a screenshot with their mark on it into the app they're using. Source: https://github.com/sksareen/point (MIT).

Work through the steps in order. Don't ask the user anything unless a step says to. Run each command yourself and read its output. End with the single report described in step 6.

## 1. Check the Mac

```bash
sw_vers -productVersion; uname -m
```

Point needs **macOS 26 or later** and **Apple Silicon** (`arm64`). If either is missing, stop and tell the user Point can't run on this Mac yet, and why. Don't install anything.

## 2. Check for an existing install

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Point.app/Contents/Info.plist 2>/dev/null || echo "not installed"
curl -fsSL https://api.github.com/repos/sksareen/point/releases/latest | grep -m1 '"tag_name"'
```

If the installed version equals the latest release tag (without the `v`), skip step 3: Point is already current.

## 3. Install the app

Download the latest release, put it in Applications, and open it. This replaces an older copy of Point and keeps the user's captures and settings, which live elsewhere.

```bash
TMP="$(mktemp -d)" && \
curl -fsSL https://github.com/sksareen/point/releases/latest/download/Point.zip -o "$TMP/Point.zip" && \
ditto -x -k "$TMP/Point.zip" "$TMP" && \
pkill -x Point 2>/dev/null; sleep 1; \
rm -rf /Applications/Point.app && \
ditto "$TMP/Point.app" /Applications/Point.app && \
xattr -dr com.apple.quarantine /Applications/Point.app 2>/dev/null; \
open /Applications/Point.app && rm -rf "$TMP" && echo "installed"
```

Point isn't notarized by Apple yet. Removing the quarantine flag (the `xattr` line) is what lets it open without the "Apple could not verify" block. It's the same thing the project's own [`get.sh`](get.sh) installer does.

## 4. Install the Claude Code plugin (Claude Code only)

Skip this step if you are not Claude Code.

```bash
claude plugin marketplace add sksareen/point && claude plugin install point@point-mac
```

If it was already installed, bring it up to date:

```bash
claude plugin marketplace update point-mac && claude plugin update point@point-mac
```

Either way, the plugin teaches Claude to read Point captures and adds `/point:last`, which pulls in the user's latest capture without pasting. It takes effect in new sessions, or after `/reload-plugins`.

## 5. Confirm it's running

```bash
pgrep -x Point >/dev/null && echo "running" || echo "not running"
```

If it isn't running, run `open /Applications/Point.app` once more and check again.

## 6. Report to the user

Reply with one short report, and nothing else:

- **Installed:** the Point version now in /Applications (or "already up to date"), and whether the Claude Code plugin is installed.
- **Three permissions, which macOS asks for as they're needed.** The user has to click Allow themselves; you can't do it for them:
  - **Accessibility**, right away, so Point can notice the key. If no prompt appeared, they can open System Settings → Privacy & Security → Accessibility and turn on Point.
  - **Microphone**, the first time they hold the key and talk.
  - **Screen Recording**, the first time they circle something. macOS may ask them to quit and reopen Point after granting it.
- **How to use it:** hold **Left Control** and talk to dictate. Keep holding and circle something on screen to add a screenshot. Let go to paste. Double-tap Left Control for a sticky pad. On first launch Point opens a short welcome that walks through the permissions. The trigger key can be changed from the menu bar icon (a pointing hand).
- If you installed the plugin: "Circle something in any app, then in Claude Code type `/point:last fix this`."

Website: https://www.pointandtell.app
