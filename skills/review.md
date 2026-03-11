---
name: review
description: "Spawn quality review agents before committing changes"
---

# Review

**IMMEDIATELY spawn these agents in parallel:**

1. **code-quality** - Find debug artifacts, duplication, complexity issues, AI slop
2. **bash-reviewer** - Catch bash style violations and common errors (if bash files changed)
3. **security-reviewer** - Check for secrets, exposed URLs, security issues
4. **test-expert** - Verify test coverage, fixture patterns, test design

## Focus Areas

Review the staged/changed files for:
- Debug output left in code
- Duplicated code patterns
- Style violations
- Fail-fast violations (error-swallowing patterns)
- Security concerns
- Test coverage for changed code

**Check project's CLAUDE.md for project-specific review patterns.**

## Expected Output

Each agent should provide:
- Issues found with file:line references
- Severity (Critical > High > Medium > Low)
- Specific fixes needed

**Do not commit until all critical/high issues are resolved.**
