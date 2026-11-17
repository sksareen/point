# Point plugin for Claude Code

[Point](https://github.com/sksareen/point) is a free, open-source macOS app: hold a key, talk, and circle something on your screen. Your agent gets your words plus a screenshot with your mark on it.

This plugin makes Claude Code better at using those captures.

```
/plugin install point --marketplace sksareen/point
```

- **`captures` skill:** Claude opens the screenshot first, treats your red loop or rectangle as "this", and allows for dictation mishearings.
- **`/point:last`:** pulls in your most recent capture without pasting. `/point:last fix this`, or `/point:last 3` for the last three, or `/point:last all` to include plain dictations.

Requires the Point app (macOS 26, Apple Silicon). The plugin only reads files Point already saved on your Mac; it sends nothing anywhere.
