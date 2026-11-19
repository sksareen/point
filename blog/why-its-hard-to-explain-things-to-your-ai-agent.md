---
title: Why it's so hard to explain things to your AI agent
description: Coding agents are good at the what and bad at the where. Why "fix the button on the left" goes wrong, and the habits that fix it.
date: 2026-11-18
slug: why-its-hard-to-explain-things-to-your-ai-agent
draft: false
---


You ask your agent to fix "the heading that looks off in the second section." It confidently fixes a different heading. You explain again, more carefully. It fixes a third one.

The agent isn't being dumb. You're asking it to find something it can't see, using only words, and words are bad at one specific job.

## Every request has a what and a where

Almost every change you ask for has two parts:

- **The what:** what's wrong, or what you want. "Too much padding." "Wrong font." "Should be blue."
- **The where:** which thing on screen you mean. "This button." "That card." "The second heading."

Language is very good at the *what*. You can say "the spacing feels cramped" and a model knows what to do with it.

Language is bad at the *where*. "The button on the left" depends on whose left and which buttons. "The second card" depends on what counts as a card. "The heading" depends on which of the eleven headings on the page you're looking at. You resolve all of this instantly, because you're looking at the screen. The agent is reading your code and guessing which part of it produces the thing you're describing.

That's why agents so often get the change right and the location wrong. They nail the *what* and miss the *where*.

## You're describing a picture in words

Most frustrating prompts have the same shape: you're looking at something visual and translating it into a paragraph. The more precise you try to be, the longer the paragraph gets, and the more likely one phrase is read differently than you meant.

People don't work this way with each other. If a colleague sits next to you, you point at the screen and say "this one." The pointing carries the *where*, and the words only have to carry the *what*. The conversation takes three seconds.

## The fix: let something other than words carry the where

The pattern that works is the one you'd use with a person:

1. **Show it.** Give the agent a screenshot of what you're looking at.
2. **Mark it.** Circle or box the exact thing. A full screenshot with no mark is a new question: which of these forty things?
3. **Say it.** One sentence about the *what*: "this is misaligned with the card above it."

Each part does one job. The screenshot gives context, the mark gives the *where*, and the sentence gives the *what*. None of them has to do the others' work, so none of them gets long.

## Habits that help even without tools

- **Name things by their visible text.** "The button that says Pay now" beats "the blue button." The agent can search the code for the exact string.
- **Describe one change per request.** Two *wheres* in one prompt doubles the chance of a mix-up.
- **Say what's wrong, not just what to do.** "This overlaps the footer on mobile" gives the agent a way to check its own fix. "Move this up" doesn't.
- **When it guesses wrong, show instead of re-explaining.** A second, longer paragraph rarely helps. A screenshot with a circle almost always does.

## Where Point fits

We built [Point](https://www.pointandtell.app) because the show-mark-say loop took too many steps: screenshot, open it, draw on it, save it, attach it, then type the sentence. With Point you hold a key, talk, and circle the thing on screen. When you let go, your agent gets your words and a screenshot with your circle on it. It's free and open source, for the Mac.

Even if you never use it, the habit is worth stealing: stop describing where things are, and point.
