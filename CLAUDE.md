# claude-rig

Claude Code hooks, statusline, skills, and configuration.

## Development

This is a TDD repo. When modifying testable code (hooks, scripts), write a failing test first, then make it pass. Test suites use [bats](https://github.com/bats-core/bats-core):

```bash
bats hooks/use-dedicated-tools.bats
```

**Important:** The hook writes logs to `~/.claude/logs/`, which is outside the sandbox write-allow list. Bats tests must run with sandbox disabled (`dangerouslyDisableSandbox: true`) or they will all fail because the hook crashes on the blocked log writes.
