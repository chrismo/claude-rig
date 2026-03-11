# Slack MCP Server Options

Research on MCP servers for Slack integration with Claude (2026-01-29).

## Options Evaluated

### 1. @modelcontextprotocol/server-slack (Anthropic)

**Status:** Archived (no longer actively maintained)

- **Source:** [npm](https://www.npmjs.com/package/@modelcontextprotocol/server-slack) | [GitHub (archived)](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/slack)
- **License:** MIT

**Required Bot Scopes:**
- `channels:history` - read messages
- `channels:read` - view channel info
- `chat:write` - send messages
- `reactions:write` - add emoji reactions
- `users:read` / `users.profile:read` - view user info

**Config Example:**
```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-your-bot-token",
        "SLACK_TEAM_ID": "T01234567",
        "SLACK_CHANNEL_IDS": "C01234567,C76543210"
      }
    }
  }
}
```

**Pros:** Trusted source (Anthropic), simple setup
**Cons:** Archived/unmaintained

---

### 2. korotovsky/slack-mcp-server (Community)

**Status:** Actively maintained

- **Source:** [GitHub](https://github.com/korotovsky/slack-mcp-server)
- **Stats:** 1.2k stars, 200 forks, 28 contributors, 30k+ monthly visitors
- **License:** MIT
- **Language:** Go (96%)

**Features:**
- Stdio, SSE, HTTP transports
- DMs, Group DMs support
- Smart history fetch (by date or count)
- GovSlack support (FedRAMP)
- Message posting disabled by default

**Auth Methods:**

| Method | Token | Pros | Cons |
|--------|-------|------|------|
| OAuth | `xoxb-` (bot) or `xoxp-` (user) | Secure, long-lived, proper scopes | Requires Slack App + admin approval |
| Stealth/Browser | `xoxc-` + `xoxd-` cookie | No admin approval, quick setup | Less secure, tokens expire, gray area TOS |

**Pros:** Active development, more features, good community
**Cons:** Third-party, no formal security audit

---

### 3. Official Slack MCP Server

**Status:** Coming summer 2026

- **Source:** [Slack Developer Docs](https://docs.slack.dev/ai/mcp-server/)
- Currently rolling out to select partners

---

## Stealth Mode Explained

The korotovsky server's "no permissions required" mode works by extracting tokens from your browser session:

1. Log into Slack web
2. Extract `xoxc-...` token (session) and `xoxd-...` cookie from dev tools
3. Server uses these to make API calls as you

**What this means:**
- Access limited to what *you* can see (no privilege escalation)
- Bypasses workspace governance/audit trails
- Tokens can expire when you log out or Slack rotates
- Not using official APIs as intended (TOS gray area)

**Verdict:** Fine for personal automation. Not appropriate for work Slack where IT/compliance matters.

---

## Recommendation

For **work Slack** (e.g., dscout): Use OAuth flow with proper bot scopes and admin approval. Either the Anthropic package (simpler, archived) or korotovsky (maintained, more features) work.

For **personal Slack**: Stealth mode is quick and easy if you accept the trade-offs.

---

## Setup TODO

- [ ] Create Slack app in workspace
- [ ] Request admin approval for bot scopes
- [ ] Generate bot token (`xoxb-...`)
- [ ] Add to Claude settings.json
- [ ] Test with limited channel access first
