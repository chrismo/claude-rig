---
name: kaomoji
description: Summon a Japanese-style emoticon (kaomoji) and put it on the clipboard. Pick one that fits the mood — the user's, the moment's, or the conversation's. Invoked as /kaomoji, optionally with a mood or a free-text vibe.
allowed-tools: Bash
model: haiku
effort: low
---

# kaomoji — summon a face

`kaomoji` holds mood-grouped emoticons and copies your pick to the clipboard
with `pbcopy`. **You** choose which face; the script just supplies candidates
and does the clipboard write.

## The one thing that matters

The user asked for a face because they want *the right face*. Read the room —
what they just said, what just happened in the session, how the day is going —
and pick accordingly. A random draw is the fallback, not the goal.

## How to do it

1. See what's available:

   ```
   kaomoji --list          # mood names
   kaomoji --list shrug    # every face in one mood
   kaomoji --all           # everything, grouped
   ```

2. Pick a face and copy it. To copy an exact face you chose:

   ```
   printf '%s' '¯\_(ツ)_/¯' | pbcopy
   ```

   Single-quote it — these are full of backslashes and parens.

3. Or let the script draw from a mood you picked, when any face in that mood
   would do:

   ```
   kaomoji table-flip      # prints and copies one
   kaomoji -n 5 happy      # prints 5, copies the first
   ```

4. Show the user what landed on the clipboard. One line, the face itself, and
   maybe half a sentence about why that one. Don't write a paragraph about an
   emoticon.

## Reading the argument

- `/kaomoji` with nothing — infer the mood from the session. Just shipped
  something? `celebrate`. Third failed test run? `table-flip`. Friday
  afternoon? `friday`. When genuinely nothing stands out, run bare `kaomoji`.
- `/kaomoji shrug` — a real mood name. Use that mood.
- `/kaomoji this deploy is cursed` — free text, not a mood name. Map it to the
  closest mood yourself (that one's `rage` or `table-flip`), or hand-pick from
  `--all`.

## Adding faces

Faces live in the `MOODS` array in `bin/kaomoji` in the claude-rig repo — edit
there, never `~/.local/bin/kaomoji` (a symlink). New moods need no other
change; the tests iterate over whatever `--list` reports. Re-run:

```
PATH="/opt/homebrew/opt/bash/bin:$PATH" bats bin/kaomoji.bats
```

(bash 4+ needed for associative arrays, same as `ticket-sort`.)
