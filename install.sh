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

# Merge claude-rig hooks into settings.json.
#
# Pattern: `put hooks := {} | drop hooks.X | values {...this, hooks: {...this.hooks, Y: [...], Z: [...]}}`
#   - `put hooks := {}` ensures hooks exists (no-op if it already does — put merges
#     records). Needed so `drop` and `this.hooks` work on a fresh settings.json.
#   - `drop hooks.X` removes hook event types claude-rig used to manage but no longer
#     does (otherwise stale entries would linger forever — spread can't subtract).
#   - `...this.hooks` preserves any hook event types claude-rig does NOT manage (e.g.,
#     user's own SubagentStop, PreCompact, etc.).
#   - Named keys after the spread (Y, Z, ...) override per-event-type: claude-rig owns
#     those event types entirely, replacing whatever was there.
# When retiring a hook event type from claude-rig, ADD it to the `drop` list so it
# disappears from existing settings.json on next install.
# tab-status --title sets the Ghostty tab title itself (resolves the pane's pts
# and uses Ghostty's set_tab_title action via osascript). It must NOT redirect
# to /dev/tty: hooks run with no controlling terminal, so opening /dev/tty fails
# and the command would never execute.
HOOK_CMD_PREFIX="tab-status --hook"
TITLE_CMD="tab-status --title > /dev/null 2>&1 || true"

new_settings=$(
  super -J -c "put hooks := {} | drop hooks.SessionStart | values {...this, hooks: {...this.hooks,
    UserPromptSubmit: [{
      matcher: '',
      hooks: [{
        type: 'command',
        command: '${HOOK_CMD_PREFIX} engage > /dev/null; ${TITLE_CMD}'
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
        command: '${HOOK_CMD_PREFIX} stop > /dev/null; ${TITLE_CMD}'
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
    }]
  }}" "$SETTINGS_FILE"
)

echo "$new_settings" > "$SETTINGS_FILE"

echo "✓ Installed hooks (UserPromptSubmit, PostToolUse, PermissionRequest, Stop, PreToolUse)"
echo ""

# Set CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=16 for Opus 4.7 on the 1M tier.
# Pre-2.1.117, Claude Code computed /context against 200K for Opus 4.7
# and auto-compacted at 80% (~160K, i.e. 16% of 1M). 2.1.117 fixed the
# window calculation, letting context grow to ~800K before compact --
# which quadruples per-turn cache_read burn. 16 restores the prior
# feel. Existing user-set value wins so overrides persist.
if grep -q '"env"' "$SETTINGS_FILE"; then
  new_settings=$(
    super -J -c 'values {
      ...this,
      env: {
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "16",
        ...this.env
      }
    }' "$SETTINGS_FILE"
  )
else
  new_settings=$(
    super -J -c 'values {
      ...this,
      env: { CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "16" }
    }' "$SETTINGS_FILE"
  )
fi
echo "$new_settings" > "$SETTINGS_FILE"
echo "✓ Set env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (default 16, preserves existing)"
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

      # Clean up stale bare-file symlink if skill was restructured into a directory
      stale_md="$SKILLS_DEST/${namespace}.md"
      if [[ -L "$stale_md" ]] || [[ -f "$stale_md" ]]; then
        rm "$stale_md"
      fi

      if [[ -L "$dest_subdir" ]] || [[ -d "$dest_subdir" ]]; then
        rm -rf "$dest_subdir"
      fi

      ln -s "$subdir" "$dest_subdir"
      subcount=$(find "$subdir" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
      count=$((count + subcount))
    fi
  done

  # Prune orphaned symlinks for skills deleted from the repo. The loops above
  # only add/update; without this a removed skill lingers as a dangling symlink.
  # Scope to broken links pointing into $SKILLS_SRC so the user's own symlinks
  # (pointing elsewhere) are never touched.
  for dest in "$SKILLS_DEST"/*; do
    if [[ -L "$dest" ]] && [[ ! -e "$dest" ]] && [[ "$(readlink "$dest")" == "$SKILLS_SRC/"* ]]; then
      rm "$dest"
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

# Install bin/* helper commands as symlinks in ~/.local/bin/
# Explicit allowlist (not a glob) so ad-hoc analysis scripts in bin/
# (harvest.sh, session-*.sh, etc.) don't get installed as user commands.
# When adding a new user-facing command to bin/, add it here.
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
mkdir -p "$LOCAL_BIN"
for cmd in claude-slot claude-tabs claude-search claude-pod work-context gt ticket-sort; do
  src="$REPO_DIR/bin/$cmd"
  dest="$LOCAL_BIN/$cmd"
  if [[ -f "$src" ]]; then
    if [[ -L "$dest" ]] || [[ -f "$dest" ]]; then
      rm "$dest"
    fi
    ln -s "$src" "$dest"
    echo "✓ Linked $cmd -> $LOCAL_BIN/"
  fi
done

# tab-status lives in tab-status/ (not bin/) but is a user-facing command used
# by the title hooks. Link it the same way so claude-rig owns
# ~/.local/bin/tab-status — historically this symlink pointed at a stale copy
# in the brain repo, so an existing (possibly cross-repo) symlink is replaced.
ts_src="$REPO_DIR/tab-status/tab-status"
ts_dest="$LOCAL_BIN/tab-status"
if [[ -f "$ts_src" ]]; then
  if [[ -L "$ts_dest" ]] || [[ -f "$ts_dest" ]]; then
    rm "$ts_dest"
  fi
  ln -s "$ts_src" "$ts_dest"
  echo "✓ Linked tab-status -> $LOCAL_BIN/"
fi
echo ""

echo "settings.json:"
cat "$SETTINGS_FILE"
