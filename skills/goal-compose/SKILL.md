---
name: goal-compose
description: "Compose a paste-ready condition for Claude Code's built-in /goal command — turn a rough intent into a measurable, self-verifying, self-terminating goal"
allowed-tools: Bash, Read, Grep, Glob
---

# goal-compose

Turn the user's rough intent into a polished condition for Claude Code's
**built-in `/goal` command**, and hand them a ready-to-paste `/goal …` line.

## First, the thing that's easy to forget

`/goal` is a **built-in Claude Code command** (v2.1.139+). It is not this skill,
and Claude cannot trigger it — the user pastes `/goal <condition>`, and Claude
Code then keeps taking turns on its own until the condition is met:

- After each turn a **separate fast model (Haiku) evaluates** whether the
  condition is satisfied. If not, Claude continues automatically.
- The evaluator **only sees what was surfaced in the conversation.** It does
  **not** run commands, read files, or inspect the repo. If the proof isn't in
  Claude's visible output, the goal will never read as met — the work gets done
  and the loop stalls. This is the single most important thing to design around.
- One goal per session, **hard cap of 4,000 characters** — a longer condition is
  rejected with an error (not silently truncated), so an over-written condition
  fails outright.
- `/goal` alone shows status; `/goal clear` cancels.

**This skill's only output is a `/goal <condition>` line for the user to paste.**
Do not try to start the goal loop yourself — you can't.

## What a good condition must have

Because the evaluator is blind to everything but the transcript, build the
condition from four parts:

1. **One measurable end state** — a single, checkable finish line (tests green,
   build exits 0, file exists, queue empty). Not a vibe ("clean up the code").
2. **A stated check** — the exact command or observation that proves it
   (`npm test` exits 0, `git status` clean, `ls dist/app.js` succeeds).
3. **A surface-the-proof instruction** — tell Claude to **paste the evidence
   into its reply each turn** (the test summary, the exit code, the file
   listing). This is the part most people omit, and it's why goals stall: the
   work is done but the evaluator can't see it.
4. **A stop clause** — a turn cap or give-up condition so a stuck goal doesn't
   loop forever ("if not met after 15 turns, stop and summarize what's
   blocking").

Optional but often valuable: **constraints that must hold** ("without modifying
any other test file", "don't touch the public API").

**Keep it well under the 4,000-character cap.** A good condition is a few tight
sentences, not an essay. If a draft balloons toward the limit, that's the signal
the goal is doing too much — split it into chained goals (see anti-patterns).

## When a plan or spec is in play

Often the intent is already captured — a `spec.md`, a design doc, or a plan
Claude wrote earlier this session. Use it as the source of the finish line:

- **Reference the file by path in the condition** (`…per plan.md`) so the working
  Claude re-grounds itself each turn. How much you spell out depends on the plan:
  - If the plan's phase already defines its own crisp, checkable "done" (a
    "Phase 2 Goal" with a stated verification), keep the condition **short** —
    just point to it: "Complete the Phase 2 Goal in plan.md and paste the
    verification output it specifies." No need to re-spell what the plan already
    nails down.
  - If the phase's done criteria are vague, distill a concrete,
    transcript-checkable end state into the condition yourself. "Complete phase 2
    per plan.md" alone isn't verifiable; "phase 2 done — `npm test` green and the
    migration script exists, per plan.md" is.

  Either way, keep the **surface-the-proof** instruction: the evaluator can't
  open the plan, so it judges from the proof Claude pastes, not from the file.
- **A phased plan is not one goal.** Each phase is its own finish line, so it
  gets its own `/goal`, composed with all four parts and run in sequence: paste
  phase 1, let it clear, paste phase 2. Cramming a multi-phase plan into one
  condition breaks "one measurable end state" and bloats the cap.

## Process

1. **Get the intent.** Use the user's args as the rough goal. If they invoked
   this with nothing, or with something too vague to make measurable, ask 1–3
   sharp questions — focus on: *what's the finish line*, *how would you check it
   by hand*, and *what must NOT change*.

2. **Check for a plan or spec.** If the user linked a `.md`, or a plan/spec is
   already in the conversation, treat it as the source of the finish line(s) —
   see "When a plan or spec is in play". Note whether it's phased.

3. **Find the real check.** Don't guess the verification command — look. Inspect
   the repo for how things are actually verified here:
   - test runner / scripts (`package.json`, `Makefile`, `*.bats`,
     `pyproject.toml`, CI config)
   - build and lint commands
   - whatever the user named as their hand-check

   Prefer a command with an unambiguous exit code or a greppable summary line.
   Respect repo conventions found in `CLAUDE.md` (e.g. tests that must run with
   the sandbox disabled).

4. **Draft the condition(s)** from the four parts above — one goal, or one goal
   per phase for a phased plan. Keep each tight and imperative. Bake in "show the
   output" explicitly.

5. **Present it** in the output format below.

## Output format

```
## Paste this

/goal <the composed condition>

## Why it's shaped this way
- End state: <…>
- Check: <command/observation>
- Proof surfaced: <what Claude will paste each turn>
- Stop clause: <turn cap / give-up>
- Constraints: <or "none">
```

Keep the explanation to a few lines. The paste line is the product.

For a phased plan, present an **ordered sequence** instead — one `/goal` block
per phase, with a note to run them one at a time (paste the next only after the
previous clears).

## Examples

Rough intent → composed `/goal`:

- *"get the auth tests passing"*
  → `/goal All tests under test/auth pass. After each change run \`npm test -- test/auth\` and paste the summary line (pass/fail counts) into your reply. Don't modify tests outside test/auth. If still failing after 15 turns, stop and summarize the remaining failures.`

- *"finish the changelog for this week"*
  → `/goal CHANGELOG.md has an entry for every PR merged in the last 7 days. Each turn, list the merged PRs you found (\`gh pr list --state merged --search "merged:>=<date>"\`) and which are still missing from CHANGELOG.md, then add them. Done when that missing list is empty — show the empty list. Stop after 10 turns if blocked.`

- *"make the bats suite green"* (repo-aware: honors CLAUDE.md)
  → `/goal \`bats hooks/use-dedicated-tools.bats\` exits 0 with zero failures. Run it each turn with the sandbox disabled (per CLAUDE.md) and paste the final tally. Don't weaken assertions to pass. If not green after 12 turns, stop and report what's failing.`

- *phased plan in `plan.md`* → one goal per phase, run in order:
  1. *(plan defines the Phase 1 goal+check, so point to it — short)*
     `/goal Complete the Phase 1 Goal in plan.md and paste the verification output it specifies each turn. Stop after 15 turns if blocked.`
  2. *(plan's Phase 2 done-criteria are vague, so distill them)*
     `/goal Phase 2 done per plan.md: the CLI wires the parser in and \`npm test\` is fully green. Paste the summary each turn. Don't touch the parser module. Stop after 15 turns if blocked.`
  (…paste each only after the previous clears.)

## Anti-patterns to steer the user away from

- **Unmeasurable end states** — "improve performance", "make it robust". Pin it
  to a number or a passing check.
- **No proof in the transcript** — the work happens but Claude never prints the
  result, so the evaluator never sees completion. Always include "paste/show the
  output".
- **No stop clause** — an impossible or flaky condition loops until the user
  notices. Always cap turns.
- **Multiple finish lines in one goal** — "tests pass and docs updated and PR
  opened" is three conditions; the evaluator can't reason about partial credit.
  Pick the one that matters, or chain goals one at a time.
- **Blowing the 4,000-char cap** — stuffing step-by-step working instructions
  into the condition. The condition is a finish line, not a plan. If it's getting
  long, the detail belongs in the conversation, and the goal probably needs
  splitting.
