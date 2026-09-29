---
name: simplify
description: Simplify code and remove unnecessary comments, especially explanatory narration. Use when implementing or reviewing changes, refactoring, or when asked to simplify code.
---

# Simplify

Make the code simpler to read and maintain without changing its behavior or
requirements. Be especially aggressive about removing comments: **do not add an
explanation to the code just because you can explain it.** Put the explanation
in the commit message, ticket, or other change context instead.

## Comments are guilty until justified

For each comment in code you touch, ask whether the code itself can be clear
without it. Delete comments that:

- narrate what the next line or block does;
- restate a function, variable, type, or test name;
- explain ordinary control flow or obvious syntax;
- record implementation history, intent already captured by the change, or a
  long rationale that belongs in the ticket or commit message;
- are stale, inaccurate, or describe code that has since changed.

Review the surrounding function and file, not just comment lines in the diff.
Check long file headers, section banners, and docstrings against nearby code and
existing documentation: keep a concise boundary or invariant, not a second
walkthrough of the implementation. Verify claims such as "always," "only,"
or "refuses" rather than shortening an inaccurate comment.

Do not preserve a comment just because it was already there. Do not add a
replacement comment that says the same thing in fewer words. Prefer clear names
and straightforward code; when behavior is hard to understand, first see whether
the code can be made clearer.

Keep or add a comment only when it captures information that is both important
and not reasonably inferable from the code, such as a non-obvious invariant,
external constraint, security or data-loss hazard, compatibility requirement,
or a surprising workaround. Keep that comment as short and specific as possible.
Preserve required license notices, machine-readable directives, generated-code
markers, and documentation that is part of a public API or explicitly required
by the project.

## Simplify the implementation too

- Prefer the smallest change that fully solves the stated problem.
- Remove needless indirection, duplication, defensive scaffolding, and
  abstractions when doing so makes the code easier to follow. In particular,
  if two branches build the same output and differ only in its destination,
  choose the destination once rather than duplicate the output logic.
- Do not replace a few clear lines with a generic framework or helper used once.
- Avoid unrelated cleanup and do not change behavior, contracts, or error
  handling merely to make a diff smaller.
- Preserve safety boundaries before shortening operational code: confirmation,
  fail-closed validation, secret-safe logging, partial-write receipts, and
  retry/timeout behavior can look repetitive but encode distinct guarantees.
  Prove equivalence with focused tests before consolidating them.
- Follow the repository's conventions and tests; local requirements take
  precedence over this skill.

## Finish

Review the diff specifically for comments you added or retained. Remove every
comment that does not meet the exception above. Run the relevant tests or checks
and report what changed and what you verified. If the rationale is useful to
preserve, put it in the commit message or ticket—not in a paragraph beside the
code.
