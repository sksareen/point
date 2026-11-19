---
title: How to show Claude Code exactly what you mean
description: Describing a UI bug in words is slow and lossy. Here are the ways to give Claude Code a screenshot of the problem, and how to mark exactly which part you mean.
date: 2026-11-18
draft: true
---

<!-- DRAFT. Savar: rewrite the opening in your own words, and check the
     "Ways to give Claude Code a screenshot" section against your own setup. -->

You're vibe coding a site. One heading is in the wrong font. You type "the heading in the second section looks off," and Claude Code fixes a different heading.

The words weren't the problem. The pointing was. A person sitting next to you would just tap the screen and say "this one." Agents can't see what you're looking at, so you end up writing a paragraph to describe a thing you could point at in a second.

## Why words lose

A UI bug has a *what* and a *where*. Words handle the *what* well ("too much padding", "wrong font"). They handle the *where* badly. "The button on the left" depends on which left. "The second card" depends on what counts as a card. Every ambiguity is a chance for the agent to fix the wrong thing confidently.

A screenshot fixes the *where*, but only if the agent knows which part of it you mean. A full-screen screenshot with no mark on it is a new question: which of these forty things?

The reliable version is three parts:

1. **A screenshot** of what you're looking at.
2. **A mark** on it: a circle or a box around the exact thing.
3. **A sentence** saying what's wrong with it.

## Ways to give Claude Code a screenshot

- **Paste or drag an image into the session.** Claude Code accepts images: drag a screenshot file in, or paste one. Take the screenshot, mark it up in Preview or the screenshot tool, save it, then bring it in. It works, but it's five or six steps for one bug.
- **Give it a file path.** Claude Code can read an image from disk. Save the screenshot and type its path along with your request.
- **Point.** Hold a key, talk, and circle the thing on screen. When you let go, [Point](https://www.pointandtell.app) pastes what you said plus the path to a screenshot with your circle drawn on it. One gesture covers all three parts: screenshot, mark, sentence.

Whichever you use, the mark is what makes it work. Claude reads "fix this" plus a red circle around one button far more reliably than a paragraph of directions.

## What to say with the mark

Keep the words about the *what*, and let the mark carry the *where*:

- "This is misaligned with the card above it." (circle the element)
- "Make this match the other buttons." (circle the odd one out)
- "This text is cut off on mobile." (box the clipped text)

You don't need to name the component or find the file. Claude Code can match visible text and layout in the screenshot to your code.

## If you use Point with Claude Code

Point's Claude Code plugin adds two things: it teaches Claude to open the screenshot first and treat your mark as "this", and it adds `/point:last`, which pulls in your most recent capture without pasting anything.

```
/plugin install point --marketplace sksareen/point
```

Circle something in any app, switch to Claude Code, and type `/point:last fix this`.
