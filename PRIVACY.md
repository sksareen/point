# Privacy

Point is a local app. It has no account, no server, and no analytics.

## The Point app

- **Your voice is transcribed on your Mac** by Apple's on-device speech recognizer. Audio is not sent to us or to anyone else. The first time you use it, macOS may download Apple's speech model from Apple.
- **Everything Point saves stays on your Mac**, in `~/Library/Application Support/Point/` or the captures folder you choose: screenshots, the audio of each capture, transcripts, and your sticky pad.
- **Point makes no network requests.** It contains no telemetry, crash reporting, or update checks.
- **What leaves Point is what you paste.** Point puts your words and screenshot on the clipboard and pastes them into the app you were using. That app, and any AI service behind it, then handles them under its own privacy policy.
- **Optional:** if you have separately installed Sauron, a local tool by the same author, Point registers each screenshot with it on your Mac. Nothing happens if Sauron is not installed.

To delete your data, delete the folder above.

## The Claude Code plugin

The plugin only reads capture files Point already saved on your Mac, when you ask it to. It stores nothing and sends nothing to us. What Claude reads becomes part of your conversation with Claude, under Anthropic's privacy policy.

## Contact

Questions: open an issue at https://github.com/sksareen/point/issues.
