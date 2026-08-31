---
name: lemma-backfill
description: "Mine reasoning out of git history into lemmalog — scoped to a path or subsystem when given one, and when given nothing, measure the repo and ask chrismo what to cover rather than sweeping everything. Invoked as /lemma-backfill, optionally with a scope."
allowed-tools: Bash, Read
---

# lemma-backfill

`hooks/lemma-commit.sh` only ever sees commits made after it was installed.
Everything decided before that is in the repo, in commit bodies, unreachable by
anything but reading. This reaches back for it.

Named backfill and not init because it is not one-time setup. It is repeatable,
it is worth scoping, and the most useful time to run it is not day one — it is
the moment you are about to work on something and want to know what was already
decided about it.

    /lemma-backfill                 measure first, then ask (see below)
    /lemma-backfill tf/             scoped to a path
    /lemma-backfill "the runner"    scoped to a subsystem

## What this actually costs, measured

Reading is cheap. All 220 candidate commits in `questor` are ~305K chars, about
**85K tokens** — one pass, no batching required. Do not design around token cost;
that was measured and it is not the constraint.

Two things are expensive, and neither is tokens:

- **chrismo's attention.** An earlier version of this skill confirmed every
  batch of ten. On `questor` that was six rounds of dense prose for one repo.
  That is the cost to avoid.
- **store quality.** A broad sweep produces a lot of mediocre facts, and a store
  with sixty unreviewed facts is worse than an empty one — it looks like
  knowledge and buries the six that mattered. `experiments/lemmalog/README.md`
  records this repo already making that mistake:

  > worse than the markdown table, because it looked authoritative

So: read broadly, assert at a high bar, and escalate narrowly.

## With no scope: measure, then ask

Do **not** start sweeping. Run the numbers for this repo and put the choice to
chrismo, because it depends on things only chrismo knows:

    git rev-list --count HEAD
    git log -i --format='%h %ad %s' --date=short \
      --grep='ruled out' --grep='rejected' --grep='rather than' \
      --grep='instead of' --grep='abandoned' --grep='turned out' \
      --grep='measured' --grep='does not work' | wc -l

Then say plainly what that implies here, and offer scopes. Real spread across
chrismo's repos, so you know what to expect:

| repo | commits | candidates | shape |
|---|---|---|---|
| `clabs` | 293 over 13 years | 1 | old and terse — a full backfill is trivial |
| `clwiki` | 213 over 14 years | 3 | same |
| `brain` | 945 over 9 years | 37 | moderate |
| `claude-rig` | 202 | 71 | dense, all recent |
| `questor` | 1508 | 220 | dense — scope it |

**Age is not the variable; prose density is.** Old repos self-limit because terse
commit messages do not match the grep. The repos that blow up are the recent
ones, from the era where commit bodies got long. A 14-year-old repo is the easy
case, not the hard one.

If the count is small (under ~20), just say so and offer to do all of it. If it
is large, say the number and offer scopes — by path, by subsystem, or by "the
last N months" — and let chrismo pick. A full sweep is chrismo's call to make
knowingly, not your default.

## Mine commit bodies, not docs

Not `docs/`, not `CLAUDE.md`, not READMEs — even though they look richer, which
is the trap. A commit body is *evidence*: a decision someone made, datable,
anchorable to a sha. A doc is a *claim* that may have been stale for a year with
nothing to reveal it. Asserting a stale claim gives it a proof tree and makes it
worse than the markdown it came from.

Same split as `bin/contract-record` and `bin/lemma-queue`: exact rows in,
judgement after.

## The bar

Inherited unchanged from `/lemma-drain`:

> conclusions, decisions and state changes land in the engine; activity does not

Highest value first: a decision that **rejected** an alternative; a constraint
discovered the hard way; a load-bearing assumption about something outside your
control; an approach abandoned after real effort.

**Verify before asserting.** The single biggest failure here is asserting
something that was true when written and is not now. A backfill run on
`claude-rig` found a three-commit chain ruling out heredocs and `-m` flags for
commit messages — all of it inert, the denial no longer fires. Check the claim
against the current tree, and drop or downgrade what you cannot confirm. A fact
you could not verify is a `[0.4]`–`[0.7]` inference at best.

## Assert, then escalate what is genuinely uncertain

Do not gate every batch on chrismo. Facts are retractable and re-asserting
merges annotations, so a mediocre assertion costs a retraction, not an evening.

1. Read the scoped candidate set in one pass. `git show -s --format=%B <sha>`.
2. Assert what clearly clears the bar, via `lemmalog_observe`. Line protocol,
   `S --rel[conf]--> O`, one per line. **The repo is a first-class dimension** —
   one global store, so a fact that does not name its repo is unreachable:

       claude-rig --ruled_out--> per-repo-lemmalog-stores
       per-repo-lemmalog-stores --because--> "LEMMALOG_MCP_PATH is read once at startup"

   Anchor provenance with `located(Entity, "repo@sha")`.
3. **Escalate only the calls chrismo's judgement would change** — a claim you
   could not verify, a fact that might be scoped wrong, a bar question. Expect a
   handful, not one per commit. One line each; chrismo can ask "why" on any of
   them and should not have to read the why for all of them.
4. Report one line: how many asserted, how many read, how many dropped.
5. **Ask it three questions.** Run three `lemmalog_query` calls that return
   something real and show the answers. A store that has never answered anything
   is one nobody writes to again — that is the whole reason to backfill rather
   than wait for `/lemma-drain` to accumulate.

## What this does not do

It does not touch the pending queue — `/lemma-drain` owns that. This reaches
backwards; drain keeps up with forwards. Overlap is harmless.

## If the tools are missing

Say so and stop. `bin/lemma-info` reports what is missing, `bin/lemma-install`
fixes it. MCP servers connect at session start, so one registered mid-session is
not available until the next — say which it is rather than reporting a failure.
