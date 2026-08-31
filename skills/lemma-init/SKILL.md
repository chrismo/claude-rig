---
name: lemma-init
description: "Seed an empty lemmalog store from the reasoning already in a repo's git history, so day one has a store worth querying. Invoked as /lemma-init, once per repo."
allowed-tools: Bash, Read
---

# lemma-init

An empty store is a store with no reason to query it — and therefore no reason
to write to it either. That is the cold start, and it is why stores die in week
one rather than month six: `/lemma-drain` asserts a fact or two per session, so
the store does not become worth asking for months, and nobody keeps feeding
something that has never answered anything.

This front-loads it. The reasoning is already in the repo; it is just in prose,
in commit bodies, unreachable by anything but reading.

Run once per repo. Then `/lemma-drain` keeps it current.

## The trap, which is the whole difficulty

A repo has hundreds of commits. Mining them all is the obvious move and it is
wrong. This repo has already made that mistake once, in
`experiments/lemmalog/README.md`:

> The first version of this model hand-transcribed the doc's verification
> claims, which inherited the doc's staleness and gave it a proof tree — worse
> than the markdown table, because it looked authoritative.

**Bulk import is worse than an empty store.** An empty store is honestly empty.
A store with 60 unreviewed facts looks like knowledge, answers queries with
noise, and buries the six facts that mattered. The bar from `/lemma-drain`
applies here unchanged, and it is a high one:

> conclusions, decisions and state changes land in the engine; activity does not

Expect to assert **single digits** from a hundred commits. If you are proposing
thirty, your bar is wrong.

## Mine git history, not the docs

Seed from commit bodies only. Not `docs/`, not `CLAUDE.md`, not READMEs — even
though they look richer, and that is exactly the trap. A commit body is
*evidence*: it records a decision someone actually made, at a moment you can
date and anchor to a sha. A doc is a *claim*, and it may have been stale for a
year with nothing to reveal that. Asserting a stale claim gives it a proof tree
and makes it worse than the markdown it came from.

The same split runs through the rest of this system: `bin/contract-record` and
`bin/lemma-queue` capture exact rows from things that ran, and judgement is
applied afterwards.

## Procedure

1. **Check the store is actually cold.** `bin/lemma-info`. If it already holds
   facts for this repo, stop and say so — an already-seeded repo is
   `/lemma-drain`'s job, and re-running this proposes the same history again.

2. **Find the commits that argue.** A commit whose body argues for a choice is
   the one worth reading; a commit fully explained by its own diff is not:

       git log -i --format='%h %s' \
         --grep='ruled out' --grep='rejected' --grep='rather than' \
         --grep='instead of' --grep='abandoned' --grep='turned out' \
         --grep='measured' --grep='does not work'

   Tune the terms to the repo. Report the count before reading anything — it
   sets expectations for both of you about how much is being dropped.

3. **Read the bodies, in batches.** `git show -s --format=%B <sha>`. Work in
   batches of roughly ten, oldest first. Oldest first matters: early decisions
   are the ones later work rests on, and the ones most likely to be re-proposed
   because nobody remembers them.

4. **Propose, never assert unattended.** Show chrismo the handful in each batch
   you think carry a fact, with the fact you would assert and the sha it came
   from, and say how many you dropped. chrismo confirms or corrects; you assert.
   Early batches are calibrating the bar, so the corrections matter more than
   the facts.

   Highest value, in order: a decision that **rejected** an alternative; a
   constraint discovered the hard way; a load-bearing assumption about something
   outside your control; an approach abandoned after real effort.

5. **Assert via `lemmalog_observe`.** Line protocol, `S --rel[conf]--> O`, one
   per line. **The repo is a first-class dimension** — one global store, so a
   fact that does not name its repo is unreachable later:

       claude-rig --ruled_out--> per-repo-lemmalog-stores
       per-repo-lemmalog-stores --because--> "LEMMALOG_MCP_PATH is read once at startup"

   Anchor provenance with `located(Entity, "repo@sha")` so the proof tree leads
   back to something readable. Tag inferences `[0.4]`–`[0.7]`; leave facts you
   read and verified untagged.

6. **End by asking it three questions.** This is not decoration — it is the
   point. Run three `lemmalog_query` calls that return something real, and show
   the answers. A store that has never answered anything is one nobody will
   write to again, and the whole reason to front-load the seeding is to skip the
   months where that is true.

## What this does not do

It does not touch the pending queue. `hooks/lemma-commit.sh` queues new commits
and `/lemma-drain` works through those; this reaches backwards, into history
that predates the hook. Some overlap is harmless — re-asserting a fact merges
annotations rather than duplicating.

## If the tools are missing

If `lemmalog_*` is not available, say so and stop. `bin/lemma-info` reports what
is missing and `bin/lemma-install` fixes it. MCP servers connect at session
start, so a server registered mid-session is not available until the next one —
say which it is rather than reporting a failure.
