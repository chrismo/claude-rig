# Multi-Session Claude Coordination

Notes on orchestrating multiple Claude Code sessions working together.

## Current Approach: mtm/mta Skills

- `mtm:setup` - Create shared context for coordinated work
- `mta:join` - Join a shared context
- `mta:update` - Write progress to shared context
- `mta:read` - Read what other sessions have done

Shared context lives in markdown files. Human orchestrates by directing each session.

## Improvement Ideas

### Blast Command

Send commands to all Ghostty windows at once via AppleScript:

```bash
#!/bin/bash
# blast.sh - send a command to all Ghostty windows

CMD="${1:-/mta:update}"

osascript -e "
tell application \"Ghostty\"
    repeat with w in windows
        repeat with t in tabs of w
            tell t to keystroke \"$CMD\" & return
        end repeat
    end repeat
end tell
"
```

Usage: `blast.sh` or `blast.sh "/mta:read"`

### Hooks for Auto-Read

Use Claude Code hooks to auto-inject shared context. Available events:

| Event | When | Use Case |
|-------|------|----------|
| SessionStart | Session begins | Read context once at start |
| UserPromptSubmit | Each prompt | Re-read on every turn (expensive) |
| SessionEnd | Session closes | Auto-write final state |
| PostToolUse | After tool succeeds | Write after significant actions |

#### Smart Hook (Only When Changed)

Avoids token waste by only injecting when context file changed:

```bash
#!/bin/bash
# .claude/hooks/read-if-changed.sh
CONTEXT=".claude/shared/context.md"
HASH_FILE="/tmp/claude-context-hash-$$"

[ ! -f "$CONTEXT" ] && exit 0

NEW_HASH=$(md5 -q "$CONTEXT")
OLD_HASH=$(cat "$HASH_FILE" 2>/dev/null)

if [ "$NEW_HASH" != "$OLD_HASH" ]; then
  echo "$NEW_HASH" > "$HASH_FILE"
  echo "=== Updated shared context ==="
  cat "$CONTEXT"
fi

exit 0
```

#### Hook Config

In `.claude/settings.json` or `.claude/settings.local.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/read-if-changed.sh"
          }
        ]
      }
    ]
  }
}
```

### Recommended Workflow

1. **SessionStart hook** → auto-read shared context once
2. **Work independently** in each session
3. **Blast `/mta:update`** → all sessions write their progress
4. **Blast `/mta:read`** or rely on next SessionStart → everyone gets fresh context

## Why Not Use Existing Frameworks?

Evaluated: LangGraph, CrewAI, AutoGen, OpenAI Agents SDK, etc.

All are **programmatic orchestration** — you write code that controls agents autonomously.

Our use case is **interactive orchestration** — human directs multiple CLI sessions in real-time.

Different paradigms:

| | Frameworks | mtm/mta |
|---|---|---|
| Control | Code | Human |
| Interface | API calls | CLI sessions |
| Flexibility | Pre-defined graph | Ad-hoc direction |

The shared-context-via-markdown approach is simple and matches the actual workflow.

## References

- Claude Code hooks: 12 events available (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, etc.)
- Hook output: exit 0 + stdout → injected as context
- LangGraph: Open source, works with Claude via `langchain-anthropic` package
