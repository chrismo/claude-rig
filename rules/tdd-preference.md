## Prefer TDD when possible

When modifying code that has an existing test suite, write a failing test first, then make it pass (red-green-refactor).

If the repo has no tests or poor coverage for the area being changed, note it briefly ("no existing tests for this area") rather than silently skipping. Don't force TDD into a codebase that isn't set up for it, but flag the gap so the user can decide.

Check the project's CLAUDE.md for repo-specific TDD instructions (test frameworks, commands, conventions).
