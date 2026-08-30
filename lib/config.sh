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
