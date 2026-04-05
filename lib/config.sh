#!/usr/bin/env bash

# Shared config for claude-rig scripts
# Source this file: source "$(dirname "$0")/../lib/config.sh"

# Resolve REPO_DIR from this file's location (lib/ is one level under repo root)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

PERMISSIONS_ALLOW="$REPO_DIR/permissions/allow.sup"
PERMISSIONS_DENY="$REPO_DIR/permissions/deny.sup"

CC_AUDIT_RULES_SRC="$REPO_DIR/cc-audit-rules"
CC_AUDIT_RULES_DEST="${CC_AUDIT_DIR:-$HOME/.cc-audit}/rules"

STATUSLINE_SCRIPT="$REPO_DIR/statusline/statusline-command.sh"
DEDICATED_TOOLS_HOOK="$REPO_DIR/hooks/use-dedicated-tools.sh"
ENSURE_SANDBOX_HOOK="$REPO_DIR/hooks/ensure-sandbox.sh"

COMMANDS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
COMMANDS_DEST="$CLAUDE_DIR/commands"
AGENTS_DEST="$CLAUDE_DIR/agents"
RULES_SRC="$REPO_DIR/rules"
RULES_DEST="$CLAUDE_DIR/rules"

LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
