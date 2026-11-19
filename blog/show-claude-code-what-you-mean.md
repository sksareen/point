---
title: How to show Claude Code (or Cursor) a UI bug
description: Every way to get a screenshot of a bug into Claude Code or Cursor, which ones are fastest, and how to mark exactly which part you mean.
date: 2026-11-18
draft: true
---

<!-- DRAFT. Savar: check the Cursor section against your own version. -->

Describing a UI bug in words is slow and easy to misread. A screenshot is faster, but only if the agent can tell which part of it you mean. This is a practical guide to getting the picture in, and marking it so there's no ambiguity.

## Getting a screenshot into Claude Code

Claude Code's [documentation](https://code.claude.com/docs/en/common-workflows) lists three ways to add an image to a conversation:

1. **Drag and drop** the image file into the Claude Code window.
2. **Paste it** with `Ctrl+V`. Note: on a Mac it's Control-V, not Command-V. On Windows and WSL it's `Alt+V`.
3. **Give it a path** in your message, like `look at /Users/me/Desktop/bug.png and fix the overlap`.

All three work. The catch is the steps around them. A typical loop is: take a screenshot, open it, draw on it in Preview or the screenshot tool, save or copy it, switch back, paste or drag it in, then type your request. That's six or seven steps for one bug, and most people skip the marking step because it's the slowest. That's the step that matters most.

## Getting a screenshot into Cursor

Cursor's chat accepts images by paste, drag and drop, or by referencing a saved file with `@` and its path. In practice, which one works can depend on your Cursor version: the [Cursor forum](https://forum.cursor.com/t/getting-screenshots-into-cursor-is-driving-me-a-bit-crazy-whats-your-workflow/162024) has a long-running thread from people trying to settle on a reliable screenshot workflow. If paste doesn't attach the image, dragging a saved file in, or `@`-referencing its path, is the usual fallback.

## Mark it, or it's a new question

A full-screen screenshot with no mark tells the agent *what you're looking at*, not *what you mean*. On a busy page that's dozens of candidates. Draw on it:

- **A circle or box** around the one element. Red stands out against almost any UI.
- **One mark per problem.** If there are two issues, send two marks with a sentence for each.
- **Crop only if the context doesn't matter.** A full screenshot with a mark beats a tight crop, because the agent can see which page and which state you're in.

## What to say with it

Let the mark carry the *where*, and keep the words to the *what*:

| Instead of | Say (with a mark) |
|---|---|
| "The second button in the card row on the pricing page has extra padding on the left" | "Extra padding on the left of this one." |
| "The heading under the hero, not the main one, the smaller one, is in the wrong font" | "Wrong font here. Should match the other headings." |
| "On mobile the text in the footer gets cut off on the right side" | "This is cut off on mobile." |

You don't need to name the component or find the file. Claude Code and Cursor can match the visible text and layout in the screenshot to your code.

## The one-gesture version

[Point](https://www.pointandtell.app) collapses all of this into one gesture: hold a key, talk, and circle the thing on screen. When you let go:

- **In Claude Code or Cursor**, it pastes what you said plus the path to a screenshot with your circle drawn on it. Both read files from disk, so the path is enough.
- **In claude.ai, ChatGPT, or Slack**, it pastes your words and then the image itself.

Point also has a Claude Code plugin. It teaches Claude to open the screenshot first and treat your circle as "this", and adds `/point:last` to pull in your most recent capture without pasting:

```
/plugin install point --marketplace sksareen/point
```

Point is free and open source, for macOS 26 on Apple Silicon.
