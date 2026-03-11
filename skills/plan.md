---
name: plan
description: "Spawn pre-implementation agents to review architecture and design before writing code"
---

# Plan

**IMMEDIATELY spawn these agents in parallel:**

1. **architecture-reviewer** - Understand infrastructure, existing patterns, design rationale
2. **design-reviewer** - Catch design issues, data flow problems, file cohesion
3. **test-expert** - Design tests for the feature (TDD), choose test approach

## What to Review

Have the agents analyze:
- The feature/task being implemented
- Existing code patterns in the relevant area
- Potential design issues
- Data query/fetch patterns (avoid duplicate queries)
- File placement for new functions
- What tests are needed
- Test fixture requirements

## Expected Output

Each agent should provide:
- Summary of relevant architecture
- Patterns to follow
- Potential pitfalls to avoid
- Recommended reading (docs/code)

**Do not write code until agents complete their review.**
