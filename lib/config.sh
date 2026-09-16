#!/usr/bin/env bash

# Shared config for claude-rig scripts
# Source this file: source "$(dirname "$0")/../lib/config.sh"

# Resolve REPO_DIR from this file's location (lib/ is one level under repo root)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

PERMISSIONS_ALLOW="$REPO_DIR/permissions/allow.sup"
PERMISSIONS_DENY="$REPO_DIR/permissions/deny.sup"

SANDBOX_ALLOW_WRITE="$REPO_DIR/sandbox/allow-write.sup"

CC_AUDIT_RULES_SRC="$REPO_DIR/cc-audit-rules"
CC_AUDIT_RULES_DEST="${CC_AUDIT_DIR:-$HOME/.cc-audit}/rules"

STATUSLINE_SCRIPT="$REPO_DIR/statusline/statusline-command.sh"
DEDICATED_TOOLS_HOOK="$REPO_DIR/hooks/use-dedicated-tools.sh"
INTERNALS_DRIFT_HOOK="$REPO_DIR/hooks/internals-drift.sh"
LEMMA_COMMIT_HOOK="$REPO_DIR/hooks/lemma-commit.sh"
LEMMA_BRIEF_HOOK="$REPO_DIR/hooks/lemma-brief.sh"

SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
SKILLS_DEST="$CLAUDE_DIR/skills"
AGENTS_DEST="$CLAUDE_DIR/agents"
RULES_SRC="$REPO_DIR/rules"
RULES_DEST="$CLAUDE_DIR/rules"

# pi (@earendil-works/pi-coding-agent) discovers skills under its own agent dir.
# PI_CODING_AGENT_DIR is pi's variable, not ours — a machine that relocates pi's
# config for pi relocates it here too, for free.
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PI_SKILLS_DEST="$PI_AGENT_DIR/skills"

# The tool-agnostic shared MCP config. pi-mcp-adapter hardcodes
# ~/.config/mcp/mcp.json — it does not honour XDG_CONFIG_HOME — so this path is
# literal, with an override for the test suite.
MCP_SHARED_SRC="$REPO_DIR/pi/mcp.json"
MCP_SHARED_DEST="${CLAUDE_RIG_MCP_SHARED_CONFIG:-$HOME/.config/mcp/mcp.json}"
