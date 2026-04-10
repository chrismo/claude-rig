#!/usr/bin/env bash

set -euo pipefail

# Load shared config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"

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
    }, {
      matcher: '',
      hooks: [{
        type: 'command',
        command: 'claude-tabs save > /dev/null 2>&1 || true',
        timeout: 5000
      }]
    }],
    PreToolUse: [{
      matcher: 'Bash',
      hooks: [{
        type: 'command',
        command: '${DEDICATED_TOOLS_HOOK}'
      }]
    }],
    SessionStart: [{
      matcher: 'startup',
      hooks: [{
        type: 'command',
        command: '${ENSURE_SANDBOX_HOOK}'
      }]
    }, {
      matcher: 'resume',
      hooks: [{
        type: 'command',
        command: '${ENSURE_SANDBOX_HOOK}'
      }]
    }, {
      matcher: 'clear',
      hooks: [{
        type: 'command',
        command: '${ENSURE_SANDBOX_HOOK}'
      }]
    }]
  }" "$SETTINGS_FILE"
)

echo "$new_settings" > "$SETTINGS_FILE"

echo "✓ Installed hooks (UserPromptSubmit, PostToolUse, PermissionRequest, Stop, PreToolUse, SessionStart)"
echo ""

# Merge permissions/allow.sup into settings.json (idempotent via sort | uniq)
if [[ -f "$PERMISSIONS_ALLOW" ]]; then
  if grep -q '"permissions"' "$SETTINGS_FILE"; then
    new_settings=$(
      super -J -c 'values {
        ...this,
        permissions: {
          ...this.permissions,
          allow: (
            unnest [...this.permissions.allow, ...(from "'"$PERMISSIONS_ALLOW"'" | collect(this))]
            | sort this | uniq | collect(this)
          )
        }
      }' "$SETTINGS_FILE"
    )
  else
    new_settings=$(
      super -J -c 'values {
        ...this,
        permissions: {
          allow: (
            unnest (from "'"$PERMISSIONS_ALLOW"'" | collect(this))
            | sort this | uniq | collect(this)
          )
        }
      }' "$SETTINGS_FILE"
    )
  fi
  echo "$new_settings" > "$SETTINGS_FILE"
  echo "✓ Merged permissions from allow.sup"
  echo ""
fi

# Merge permissions/deny.sup into settings.json (idempotent via sort | uniq)
if [[ -f "$PERMISSIONS_DENY" ]] && grep -q '[^[:space:]]' "$PERMISSIONS_DENY"; then
  if grep -q '"deny"' "$SETTINGS_FILE"; then
    new_settings=$(
      super -J -c 'values {
        ...this,
        permissions: {
          ...this.permissions,
          deny: (
            unnest [...this.permissions.deny, ...(from "'"$PERMISSIONS_DENY"'" | collect(this))]
            | sort this | uniq | collect(this)
          )
        }
      }' "$SETTINGS_FILE"
    )
  else
    new_settings=$(
      super -J -c 'values {
        ...this,
        permissions: {
          ...this.permissions,
          deny: (
            unnest (from "'"$PERMISSIONS_DENY"'" | collect(this))
            | sort this | uniq | collect(this)
          )
        }
      }' "$SETTINGS_FILE"
    )
  fi
  echo "$new_settings" > "$SETTINGS_FILE"
  echo "✓ Merged permissions from deny.sup"
  echo ""
fi


# Merge sandbox/allow-write.sup into settings.json (idempotent via sort | uniq)
if [[ -f "$SANDBOX_ALLOW_WRITE" ]]; then
  if grep -q '"sandbox"' "$SETTINGS_FILE"; then
    new_settings=$(
      super -J -c 'values {
        ...this,
        sandbox: {
          ...this.sandbox,
          filesystem: {
            ...this.sandbox.filesystem,
            allowWrite: (
              unnest [...coalesce(this.sandbox.filesystem.allowWrite, []), ...(from "'"$SANDBOX_ALLOW_WRITE"'" | collect(this))]
              | sort this | uniq | collect(this)
            )
          }
        }
      }' "$SETTINGS_FILE"
    )
  else
    new_settings=$(
      super -J -c 'values {
        ...this,
        sandbox: {
          filesystem: {
            allowWrite: (
              unnest (from "'"$SANDBOX_ALLOW_WRITE"'" | collect(this))
              | sort this | uniq | collect(this)
            )
          }
        }
      }' "$SETTINGS_FILE"
    )
  fi
  echo "$new_settings" > "$SETTINGS_FILE"
  echo "✓ Merged sandbox allowWrite from allow-write.sup"
  echo ""
fi

# Clean up deprecated ~/.claude/commands/ entries that claude-rig installed
# (only remove entries matching our skill names, not other tools' files)
LEGACY_COMMANDS_DIR="$CLAUDE_DIR/commands"
if [[ -d "$LEGACY_COMMANDS_DIR" ]] && [[ -d "$SKILLS_SRC" ]]; then
  legacy_count=0
  for cmd_file in "$SKILLS_SRC"/*.md; do
    if [[ -f "$cmd_file" ]]; then
      legacy="$LEGACY_COMMANDS_DIR/$(basename "$cmd_file")"
      if [[ -L "$legacy" ]] || [[ -f "$legacy" ]]; then
        rm "$legacy"
        legacy_count=$((legacy_count + 1))
      fi
    fi
  done
  for subdir in "$SKILLS_SRC"/*/; do
    if [[ -d "$subdir" ]]; then
      legacy="$LEGACY_COMMANDS_DIR/$(basename "$subdir")"
      if [[ -L "$legacy" ]] || [[ -d "$legacy" ]]; then
        rm -rf "$legacy"
        legacy_count=$((legacy_count + 1))
      fi
    fi
  done
  if [[ $legacy_count -gt 0 ]]; then
    echo "✓ Cleaned up $legacy_count entry(s) from deprecated ~/.claude/commands/"
    echo ""
  fi
fi

# Install user-level skills
if [[ -d "$SKILLS_SRC" ]]; then
  mkdir -p "$SKILLS_DEST"
  count=0

  # Install top-level skills (*.md -> /user:<name>)
  for cmd_file in "$SKILLS_SRC"/*.md; do
    if [[ -f "$cmd_file" ]]; then
      filename=$(basename "$cmd_file")
      dest_file="$SKILLS_DEST/$filename"

      if [[ -L "$dest_file" ]] || [[ -f "$dest_file" ]]; then
        rm "$dest_file"
      fi

      ln -s "$cmd_file" "$dest_file"
      count=$((count + 1))
    fi
  done

  # Install namespaced skills by symlinking subdirectories
  for subdir in "$SKILLS_SRC"/*/; do
    if [[ -d "$subdir" ]]; then
      namespace=$(basename "$subdir")
      dest_subdir="$SKILLS_DEST/$namespace"

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

# Install user-level rules
if [[ -d "$RULES_SRC" ]]; then
  mkdir -p "$RULES_DEST"
  count=0

  for rule_file in "$RULES_SRC"/*.md; do
    if [[ -f "$rule_file" ]]; then
      filename=$(basename "$rule_file")
      dest_file="$RULES_DEST/$filename"

      if [[ -L "$dest_file" ]] || [[ -f "$dest_file" ]]; then
        rm "$dest_file"
      fi

      ln -s "$rule_file" "$dest_file"
      count=$((count + 1))
    fi
  done

  if [[ $count -gt 0 ]]; then
    echo "✓ Installed $count user-level rule(s):"
    for rule_file in "$RULES_DEST"/*.md; do
      if [[ -L "$rule_file" ]]; then
        name=$(basename "$rule_file" .md)
        echo "  $name"
      fi
    done
    echo ""
  fi
fi

# Install cc-audit personalized rules
if [[ -d "$CC_AUDIT_RULES_SRC" ]]; then
  json_count=$(find "$CC_AUDIT_RULES_SRC" -maxdepth 1 -name "*.json" | wc -l | tr -d ' ')
  if [[ "$json_count" -gt 0 ]]; then
    mkdir -p "$(dirname "$CC_AUDIT_RULES_DEST")"

    if [[ -L "$CC_AUDIT_RULES_DEST" ]] || [[ -d "$CC_AUDIT_RULES_DEST" ]]; then
      rm -rf "$CC_AUDIT_RULES_DEST"
    fi

    ln -s "$CC_AUDIT_RULES_SRC" "$CC_AUDIT_RULES_DEST"
    echo "✓ Installed cc-audit rules -> $CC_AUDIT_RULES_DEST ($json_count rule files)"
    echo ""
  fi
fi

echo "settings.json:"
cat "$SETTINGS_FILE"
