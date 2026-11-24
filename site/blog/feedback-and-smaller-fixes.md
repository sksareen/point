# Feedback in one click, and four smaller fixes

The big change this week was [connecting Point to your AI agents](/blog/connect-your-ai-agents.html). Here's everything else, most of it from using Point all day and noticing what got in the way.

## Send feedback from inside Point

There was no way to tell us something was wrong, short of finding the GitHub repo and filing an issue. Most people won't do that, and they shouldn't have to.

Now there's **Send feedback…** in the menu bar, in Settings, and on the last welcome screen. It's one text box. Hold your key and say what's wrong, or type it.

![The feedback window: a message box, Attach my last capture, an optional email, and Send](/blog-images/feedback-window.png)

The useful part is **Attach my last capture**. Most Point bugs are about one specific capture: a word it misheard, a paste that went to the wrong place, a slow start. Attaching it sends what Point heard, which app you were in, and how long each step took, so we can see the problem instead of guessing. The screenshot is included only if you leave its box ticked, and you see everything before you send it. The audio recording is never sent.

Sending is the only time Point uses the network, and only when you press Send.

## Switch back to Point with Command-Tab

Point lives in the menu bar, so it had no Dock icon, and macOS leaves apps like that out of Command-Tab. Open Settings, switch to another app, and there was no way to switch back except clicking the menu bar again.

Now, while one of Point's windows is open, Point shows up in the Dock and in Command-Tab. When you close the last window, it goes back to living only in the menu bar. Command-W closes the window, and copy and paste work in its text boxes.

## Click a capture to copy it

The Captures window shows everything you've said and circled. Before, getting one back out meant selecting it and then clicking a copy button on the right.

Now clicking a capture copies it. You get what you said, plus the screenshot when there is one: apps that take images get the picture, and terminals get the file path. Opening the window doesn't touch your clipboard; only a click or the arrow keys do.

## Circle or rectangle, from the menu bar

You could already switch from drawing a loop to dragging a box, but only in Settings. Now it's in the menu bar too, under **Mark with**, next to the trigger key. The hint line in the menu changes to match: "draw" or "drag".

## See the welcome again

If you skipped the welcome walkthrough, or want to show it to someone, it's in **Settings → General → Welcome walkthrough → Show again**.

## Get it

All of this is in [Point 0.1.5](https://github.com/sksareen/point/releases/latest). And if something's off, you know where the feedback button is now.
