# Does pointing help? A small benchmark

Point's claim is that a screenshot with a mark on it tells an agent *which* thing you mean. This folder tests that, and reports what it found, including the part that doesn't flatter Point.

## Setup

- **The page** (`app/`): a small marketing site full of lookalikes: five "Get started" buttons, three pricing cards, two "New" badges, three "Contact" links, four FAQ questions.
- **Eight tasks** (`tasks.json`), each a change to exactly one of the lookalikes: "Make this button green", "Remove this badge", "Hide this one", and so on.
- **Four ways of asking:**

| Condition | What the agent gets | Example |
|---|---|---|
| vague | The sentence you'd say while pointing, with nothing else | "Make this button green." |
| short | A words-only request of at most 8 words | "Make the Pro pricing card's "Get started" button green." |
| described | A words-only request of up to 25 words | "Make the "Get started" button in the Pro ($12) card of the "Simple pricing" section green, leaving the Starter and Team buttons blue." |
| pointed | The vague sentence plus `[Screenshot: path]` with a red loop on the target, which is what Point pastes into a terminal | "Make this button green." + screenshot |

- **The agent:** Claude Code in `--safe-mode` (no plugins, skills, or CLAUDE.md), model alias `sonnet`, allowed to read and edit files. Each run starts from a fresh copy of the page.
- **Scoring:** computed styles and text read from headless Chrome before and after. A run is a **hit** when the target changed and no lookalike did; **overbroad** when the target and others changed; **no-change** when nothing changed (usually the agent asked which one).

## Result (2026-11-21, 3 runs per task and condition, 96 runs)

| Condition | Hits | Overbroad | No change | Words typed or said |
|---|---:|---:|---:|---:|
| vague | 3 / 24 | 5 | 16 | 4.2 |
| short | 24 / 24 | 0 | 0 | 9.2 |
| described | 24 / 24 | 0 | 0 | 22.6 |
| **pointed** | **24 / 24** | 0 | 0 | **4.2** |

Raw records, with every prompt and the agent's final message, are in `results/`.

## What this shows

- **A mark turns a vague sentence into a precise one.** "Make this button green" alone hit 3 of 24. The same four words plus a marked screenshot hit 24 of 24.
- **A precise sentence works just as well.** Naming the element in nine words also hit 24 of 24. On this page, pointing did not beat careful typing on accuracy.
- **So the measured benefit is effort, not accuracy:** the same result from 4 words as from 9 to 23, without having to work out how to name the thing.
- The agent never changed the *wrong* element. When it lacked the "where", it asked, or changed all the lookalikes.

## Limits

- **The page is easy to describe.** Every target has text or sits in a named card. Pointing should matter more where things are hard to name: icons, spacing, charts, dense dashboards. That isn't tested here.
- **The words-only requests were written by a model that could see the answer** (the marked screenshot) and was told to be clear. People typing in a hurry are often less precise.
- One model, one page, eight tasks, three runs each. This is a pilot, not a study.
- Runs are not timed for the human. Speaking four words while circling is probably faster than typing nine, but this measures the agent, not the person.

## Run it

Needs macOS with Google Chrome, [uv](https://docs.astral.sh/uv/), and Claude Code.

```sh
uv run bench/bench.py shots      # render the marked screenshots into bench/shots/
uv run bench/bench.py describe   # write the words-only requests into bench/described.json
uv run bench/bench.py run 3      # 96 agent runs; saves bench/results/run-<time>.json
uv run bench/bench.py report     # summarize everything in bench/results/
```
