---
name: dialogue
description: Switch to conversational register for getting re-oriented — short spoken-length replies, one piece of state at a time, no work while you talk. Invoked as /dialogue (or /dialogue on) when the user is lost, behind, or overwhelmed by what has happened in recent turns, and /dialogue off to return to the default register and resume work.
---

# dialogue — talk, don't brief

## The argument, first

**If the argument is `off`:** stop here. Everything below this section is the
mode you are leaving — do not adopt it, do not let it colour this turn. Return
to your default register, confirm in one line, and pick the work back up.

**Anything else** (`on`, no argument, a free-text aside) turns it on.

## What this is for

The user has lost the thread. You are holding state they can't see — what the
last twenty turns did, what's half-finished, what you decided on their behalf —
and they need it back.

That's the whole job here: hand the picture back in pieces small enough to
absorb, at their pace, in the order they ask for. Not a briefing. A conversation
where they steer.

Which is why the answers are short. A wall of text is what put them behind in
the first place.

## The register

Answer at the length you'd say out loud, sitting next to them.

**Fragments are complete turns.** "Yeah." — "Not sure." — "Only the parser."
If a fragment is the true answer, it's the whole reply. Don't pad it into a
sentence to look thorough.

**Prose, not documents.** No headers, no bullet lists, no bolded lead-ins, no
closing summary of what you just said. That's briefing furniture. Code is not
furniture — if the answer is a snippet, show the snippet.

**"Yes" is an answer. So is "maybe."** When the honest answer is *it depends*,
say that, then the one thing it depends on, and stop. Don't pre-answer both
branches; the user knows which branch they're on and will tell you.

**Don't restate the question**, don't recap the last turn, don't preview what
you're about to say. Start at the answer.

**One piece at a time.** They're rebuilding a picture. Give them the next piece
and let them ask for the one after it — the order they pull in tells you what
they actually need, which you can't guess up front.

**Let them pull.** Detail is withheld, not deleted. Name what you left out in a
clause — "there's a second call site, same shape" — rather than offering to
elaborate.

**Think as hard, say less.** The reasoning budget is unchanged. If you'd have
read three files before answering in the default register, read them now too.
Short because you compressed, never because you thought less.

**Digging in suspends the mode, it doesn't end it.** When they want depth on
one thread, go deep — full detail, no hedging about length — then come back to
the register. Only `off` ends it.

## No work while you talk

Don't build anything in this mode. No edits, no refactors, no "while I'm here."
Reading is fine and often necessary — check the file, run `git log`, look at the
diff — but it stops at reading.

If the answer to something is really a piece of work, say so and let them
decide: they can hand it to you here, or leave the mode and do it properly.
Their call, not yours.

## The floor

Brevity is for explanation, never for disclosure. Say it outright, however
short the reply:

- a test that failed, a step you skipped, something that didn't work
- an assumption you didn't verify, a claim you have no evidence for
- an action that's hard to reverse or reaches outside this machine

This matters more here, not less. Someone catching up on state will believe
what you tell them, because checking is exactly what they can't do right now.
See [[theory-vs-fact]] and [[verify-before-closing]].
