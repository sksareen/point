# Your AI agents can now ask Point what you circled

Until now, Point did one thing with a capture: it pasted it. You held the key, talked, circled something, let go, and your words and screenshot landed in whatever box your cursor was in.

That still works, and it's still the default. We wrote about why in [the clipboard is the universal context layer for AI](/blog/the-universal-interface-is-paste.html): paste reaches every app, with no setup.

But it has one annoying gap. You have to be in the right place when you let go. If you circle a bug in your browser and then switch to Claude Code, the paste already happened in the browser.

So now your agents can ask for it.

## What changed

In **Settings → AI agents**, Point lists the agents it finds on your Mac and connects the ones you pick: Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI, and opencode. It's also a step in the welcome when you first install.

Once an agent is connected, you can say "what did I just circle?" or "fix this" in it, and it fetches your latest capture from Point: what you said, the app you were in, and the screenshot with your mark on it.

## How it works

Each of these agents keeps a list of tools it's allowed to use, in a settings file on your Mac. Connecting adds one entry to that list. In Cursor's file it looks like this:

```json
"point": {
  "command": "/Applications/Point.app/Contents/MacOS/Point",
  "args": ["--mcp"]
}
```

That says: there's a tool called point, and to use it, run Point with `--mcp`. When the agent starts, it runs that command in the background and asks what it can do. Point answers with one tool, `last_capture`. When you mention something on your screen, the agent calls it, and Point reads your newest capture from its folder and hands it back.

Point doesn't have to be open for this. The agent starts it, and it only reads files that are already on your Mac.

The protocol is [MCP](https://modelcontextprotocol.io), which all of these agents support. That's why one small piece covers six different tools.

## What we chose not to do

The obvious way to make an agent "know about" a tool is to add a paragraph to its instructions file: your `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`. We didn't. Those files are yours, and they get long enough already.

It turned out we didn't need to. When an agent starts, it reads the description of every connected tool. Point's description says when to use it ("when the user says this, what I circled, or refers to something on screen you can't see"), so the agent knows about Point without any instructions from us.

## What it changes on your Mac

- **One entry per agent, named `point`.** Nothing else in those files changes. Your other tools stay where they were.
- **A backup first.** Before the first change, Point saves the original file beside it as `<file>.point-backup`.
- **Disconnect removes the entry.** The file goes back to how it was.
- **Point won't edit a file it can't read.** If a settings file has comments or something unexpected in it, Point leaves it alone and tells you.
- **Restart the agent after connecting.** Agents read their tool list when they start.

## Privacy

Point itself still sends nothing anywhere. But when a connected agent asks for a capture, the agent does what it does with anything you give it, which usually means sending it to its AI provider. That only happens when the agent asks, typically because you said "this" or "what I circled". The details are in [PRIVACY.md](https://github.com/sksareen/point/blob/master/PRIVACY.md).

## What's not covered

Apps that don't have a tool system, like the ChatGPT app, can't be connected this way. Point still pastes into them, the same as before.

We've tested the whole path in Claude Code: ask "what did I just circle?" and it calls Point, gets the screenshot, and describes it. Gemini CLI, opencode, and Codex list Point as connected. If an agent can't show the screenshot itself, it still gets the file's path.

## Try it

Update to [Point 0.1.5](https://github.com/sksareen/point/releases/latest), open **Settings → AI agents**, connect what you use, and restart those agents. Then circle something and ask "what did I just circle?"

If something doesn't connect, use **Send feedback…** in the menu bar. It goes straight to us.
