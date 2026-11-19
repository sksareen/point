---
title: Talk to your coding agent instead of typing to it
description: Speaking is about three times faster than typing, and spoken prompts carry more context. What changes when you talk to Claude Code or Cursor, and where voice breaks.
date: 2026-11-18
slug: talk-to-your-coding-agent
draft: false
---


Most people type their prompts to coding agents. That's a habit from search boxes, where short is better. Agents are the opposite: they do better with more context, and typing is the slowest way to give it.

## Speaking is a lot faster than typing

The numbers are rough but consistent. People speak conversationally at around 150 words per minute. A study of about 168,000 people taking online typing tests put average keyboard typing at about 52 words per minute, and many estimates for typical users are closer to 40. In a Stanford, Baidu and University of Washington study, voice input was about three times faster than typing on a phone keyboard. ([Summary of the research](https://www.lesswrong.com/posts/ZpG6AdeXuZy4JbWrH/how-much-faster-is-speaking-compared-to-typing-on-laptop-vs).)

Three times faster matters less for one-line commands and a lot for real requests, which is what agents need.

## Spoken prompts carry more context

When you type, you compress. "Fix the login bug." When you talk, you explain the way you would to a person: what you saw, what you expected, what you already tried, what you suspect.

That extra context is exactly what agents are missing. A spoken prompt naturally includes:

- **What you expected** versus what happened.
- **How you got there**: the steps, the page, the state.
- **Your hunch**: "I think it's the new caching, it started after that."
- **Constraints**: "don't touch the API, just the frontend."

You'd rarely type all of that. You'll say it without thinking.

## Where voice breaks

Voice isn't free. The common problems, and fixes:

- **Code names get misheard.** "useEffect" becomes "use effect", "Supabase" becomes "super base." Agents often recover from the context, and many dictation tools, Point included, let you add a vocabulary list of your project's names.
- **Rambling.** Spoken prompts can wander. That's mostly fine, since the agent filters, but end with one clear sentence: "So: make the error message show under the field."
- **You can't edit as you go.** Look over the transcript before you send if the request is risky, like a migration or a delete.
- **It's still blind.** Voice carries the *what* beautifully and the *where* as badly as typing does. "The button on the left" is just as ambiguous out loud.

## Voice plus pointing

That last problem is why voice alone isn't enough for UI work. You need something to carry the *where*: a screenshot with the thing marked on it. (More on that in [why it's so hard to explain things to your agent](/blog/why-its-hard-to-explain-things-to-your-ai-agent.html).)

[Point](https://www.pointandtell.app) does both in one gesture. Hold a key and talk to dictate into any app; keep holding and circle something on screen, and your agent also gets a screenshot with your circle on it. Transcription runs on your Mac with Apple's speech recognizer, so your voice doesn't leave your machine. It's free and open source.

You don't need Point to start, though. Turn on your Mac's built-in dictation, talk your next prompt instead of typing it, and see how much more you end up saying.
