#!/usr/bin/env bash

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
STATUSLINE_SCRIPT="$REPO_DIR/statusline/statusline-command.sh"
DEDICATED_TOOLS_HOOK="$REPO_DIR/hooks/use-dedicated-tools.sh"
COMMANDS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
COMMANDS_DEST="$CLAUDE_DIR/commands"
AGENTS_DEST="$CLAUDE_DIR/agents"

# Ensure .claude directory exists
mkdir -p "$CLAUDE_DIR"

# Check if super is installed
if ! command -v super &>/dev/null; then
  echo "Error: 'super' command not found. Please install it first:"
  echo "  brew install super"
  exit 1
fi

# Check if statusline-command.sh exists
if [[ ! -f "$STATUSLINE_SCRIPT" ]]; then
  echo "Error: statusline-command.sh not found at $STATUSLINE_SCRIPT"
  exit 1
fi

# Create default settings.json if it doesn't exist
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "{}" > "$SETTINGS_FILE"
  echo "Created new settings.json"
fi

# Backup existing settings
backup_file="$CLAUDE_DIR/settings-bak-$(date +%Y%m%d-%H%M%S).json"
cp "$SETTINGS_FILE" "$backup_file"
echo "Backed up existing settings to: $backup_file"

# Merge the statusLine setting using super
new_settings=$(
  super -J -c "statusLine:={type:'command',command:'bash $STATUSLINE_SCRIPT'}" \
    "$SETTINGS_FILE"
)

# Write the merged settings
echo "$new_settings" > "$SETTINGS_FILE"

echo "✓ Installed statusLine configuration"
echo "  Command: bash $STATUSLINE_SCRIPT"
echo ""

# Merge tab-status hooks using super
# These hooks auto-update Ghostty tab colors during Claude sessions
HOOK_CMD_PREFIX="tab-status --hook"
TITLE_CMD="tab-status --title > /dev/tty 2>/dev/null || true"

new_settings=$(
  super -J -c "hooks:={
    UserPromptSubmit: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: '${HOOK_CMD_PREFIX} active > /dev/null; ${TITLE_CMD}'
      }]
    }],
    PermissionRequest: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: '${HOOK_CMD_PREFIX} waiting > /dev/null; ${TITLE_CMD}'
      }]
    }],
    PostToolUse: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: '${HOOK_CMD_PREFIX} active > /dev/null; ${TITLE_CMD}'
      }]
    }],
    Stop: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: '${HOOK_CMD_PREFIX} idle > /dev/null; ${TITLE_CMD}'
      }]
    }],
    PreToolUse: [{
      matcher: 'Bash',
      hooks: [{
        type: 'command',
        command: '${DEDICATED_TOOLS_HOOK}'
      }]
    }]
  }" "$SETTINGS_FILE"
)

echo "$new_settings" > "$SETTINGS_FILE"

echo "✓ Installed hooks (UserPromptSubmit, PostToolUse, PermissionRequest, Stop, PreToolUse)"
echo ""

# Install skill scripts to ~/.local/bin
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
for script in "$COMMANDS_SRC"/*.sh; do
  if [[ -f "$script" ]]; then
    name=$(basename "$script" .sh)
    dest="$LOCAL_BIN/$name"
    if [[ -L "$dest" ]] || [[ -f "$dest" ]]; then
      rm "$dest"
    fi
    ln -s "$script" "$dest"
    echo "✓ Linked $name -> ~/.local/bin/"
  fi
done
echo ""

# Install user-level skills
if [[ -d "$COMMANDS_SRC" ]]; then
  mkdir -p "$COMMANDS_DEST"
  count=0

  # Install top-level skills (*.md -> /user:<name>)
  for cmd_file in "$COMMANDS_SRC"/*.md; do
    if [[ -f "$cmd_file" ]]; then
      filename=$(basename "$cmd_file")
      dest_file="$COMMANDS_DEST/$filename"

      if [[ -L "$dest_file" ]] || [[ -f "$dest_file" ]]; then
        rm "$dest_file"
      fi

      ln -s "$cmd_file" "$dest_file"
      count=$((count + 1))
    fi
  done

  # Install namespaced skills by symlinking subdirectories
  for subdir in "$COMMANDS_SRC"/*/; do
    if [[ -d "$subdir" ]]; then
      namespace=$(basename "$subdir")
      dest_subdir="$COMMANDS_DEST/$namespace"

      if [[ -L "$dest_subdir" ]] || [[ -d "$dest_subdir" ]]; then
        rm -rf "$dest_subdir"
      fi

      ln -s "$subdir" "$dest_subdir"
      subcount=$(find "$subdir" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
      count=$((count + subcount))
    fi
  done

  if [[ $count -gt 0 ]]; then
    echo "✓ Installed $count user-level skill(s)"
    echo ""
  fi
fi

# Install user-level agents
if [[ -d "$AGENTS_SRC" ]]; then
  mkdir -p "$AGENTS_DEST"
  count=0

  for agent_file in "$AGENTS_SRC"/*.md; do
    if [[ -f "$agent_file" ]]; then
      filename=$(basename "$agent_file")
      dest_file="$AGENTS_DEST/$filename"

      # Remove existing symlink or file
      if [[ -L "$dest_file" ]] || [[ -f "$dest_file" ]]; then
        rm "$dest_file"
      fi

      # Create symlink
      ln -s "$agent_file" "$dest_file"
      count=$((count + 1))
    fi
  done

  if [[ $count -gt 0 ]]; then
    echo "✓ Installed $count user-level agent(s):"
    for agent_file in "$AGENTS_DEST"/*.md; do
      if [[ -L "$agent_file" ]]; then
        name=$(basename "$agent_file" .md)
        echo "  $name"
      fi
    done
    echo ""
  fi
fi

echo "settings.json:"
cat "$SETTINGS_FILE"
