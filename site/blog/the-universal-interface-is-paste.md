# The clipboard is the universal context layer for AI

Watch how people actually use AI on a computer. They copy an error from the terminal and paste it into a chat. They copy a paragraph from a doc, a stack trace from a log, a screenshot from the desktop. Before any agent sees your problem, it passes through one place: the clipboard.

That isn't a workaround. It's the only context channel that every app on your computer already shares. Your editor, your browser, your terminal and your chat apps don't integrate with each other, but they all read and write the clipboard. The tools that win will treat it as the context layer it already is.

Point is built on that idea: it captures what you say and what you point at, and puts it where all context already goes.

The obvious alternative, if you build a tool for AI agents today, is an integration: run an MCP server, have the agent call a tool like `get_latest_screenshot`, and pass the capture in as structured data. It's clean, and it's how most new agent tools are built. Here's why Point doesn't start there.

## Integrations are one agent at a time

An MCP server, a plugin, or an extension works with exactly the clients that support it, once each one is set up. That's fine if you live in one tool. Most people don't. In a single afternoon you might talk to:

- Claude Code in a terminal
- Cursor's chat
- claude.ai or ChatGPT in a browser
- a teammate in Slack, about the same bug

Each integration has to be installed, configured, and kept working in each place. Some of those places will never support it: a Slack message box or a web form doesn't call tools. And whatever agent comes out next month starts at zero.

The thing you want to send is the same everywhere: *here's what I'm looking at, here's what I mean, here's what I want.* It shouldn't need a different pipe for every destination.

## Every app already has the interface

Every text box on your Mac accepts paste. Every agent, chat app, terminal, and editor. Today's, and the ones that don't exist yet. Paste needs no setup, no API, and no permission from the app vendor.

It's also honest in a way integrations often aren't. What gets pasted is exactly what the agent sees, in the box, in front of you, before you send it. Nothing is happening in a background channel you can't inspect.

So Point's core does three things: record what you say, capture what you circled, and paste both where your cursor is. That's the whole interface.

## What paste costs, and how Point handles it

Paste isn't free. Three real problems, and what we did about each:

- **The clipboard holds one thing at a time.** Your words and your screenshot are two things. In chat apps, Point pastes your words, waits a moment for the app to read them, then pastes the image. The image stays on the clipboard so you can paste it again somewhere else.
- **Terminals can't take an image.** Pasting a picture into a terminal does nothing. So Point checks which app is in front. In terminals and code editors it pastes your words plus the screenshot's file path instead, because Claude Code and Cursor read files from disk. Same gesture, the right format for each app.
- **Paste carries no structure.** A tool call can say "this is a screenshot, this is the transcript, this is the app it came from." Pasted text can't. In practice agents read `[Screenshot: /path/to/file.png]` without help. For people who want more, Point has an optional Claude Code plugin that teaches Claude how to read a capture and pulls in the latest one with `/point:last`. It's a layer on top, never a requirement.

## Integrations should be extras, not the foundation

None of this is an argument against MCP. It's very good at what it's for: letting an agent reach out and fetch data, call services, and act. That's the agent's side of the conversation.

Your side, what you say and what you point at, is different. It has to reach every app you use, starting today, with no setup. The one mechanism that does that is the oldest one on your computer.

Build the universal version first. Add integrations where they genuinely help. Don't make the user's words depend on them.

---

[Point](https://www.pointandtell.app) is free and open source for the Mac. Hold a key, talk, and circle what you mean. It pastes into any app.
