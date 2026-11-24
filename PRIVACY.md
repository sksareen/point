# Privacy

Point is a local app. It has no account, no server, and no analytics.

## The Point app

- **Your voice is transcribed on your Mac** by Apple's on-device speech recognizer. Audio is not sent to us or to anyone else. The first time you use it, macOS may download Apple's speech model from Apple.
- **Everything Point saves stays on your Mac**, in `~/Library/Application Support/Point/` or the captures folder you choose: screenshots, the audio of each capture, transcripts, and your sticky pad.
- **Point makes no network requests on its own.** It contains no telemetry, crash reporting, or update checks. The one exception is feedback you choose to send (below).
- **What leaves Point is what you paste.** Point puts your words and screenshot on the clipboard and pastes them into the app you were using. That app, and any AI service behind it, then handles them under its own privacy policy.
- **Optional:** if you have separately installed Sauron, a local tool by the same author, Point registers each screenshot with it on your Mac. Nothing happens if Sauron is not installed.

To delete your data, delete the folder above.

## Feedback you send

The menu bar icon has **Send feedback…**. Nothing is sent until you press Send. When you do, Point sends one request to pointandtell.app with:

- your message, and your email address if you typed one;
- Point's version, your macOS version, and which trigger key you use.

If you click **Attach my last capture**, it also sends what the window shows you first: what Point heard, the app you were in, when, and how long each step took. The screenshot is included only if its checkbox is ticked, and it is your whole screen as it was at that moment. **The audio recording is never sent.**

Feedback is stored as an issue in a private GitHub repository that only the author can read. To have yours deleted, open an issue or say so in a new feedback message.

## AI agents you connect

In Settings → AI agents you can connect agents on your Mac (Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI, opencode). Connecting adds one entry named "point" to that agent's settings file, and keeps a copy of the original beside it (`<file>.point-backup`). Disconnect removes the entry.

A connected agent can ask Point for your latest capture: what you said, the app you were in, when, and the screenshot. Point answers from files on your Mac and sends nothing itself. The agent then handles that capture like anything else you give it, which usually means sending it to its AI provider, under that provider's privacy policy. Agents only get a capture when they ask for one, typically because you said "this" or "what I circled".

## The Claude Code plugin

The plugin only reads capture files Point already saved on your Mac, when you ask it to. It stores nothing and sends nothing to us. What Claude reads becomes part of your conversation with Claude, under Anthropic's privacy policy.

## Contact

Questions: open an issue at https://github.com/sksareen/point/issues.
