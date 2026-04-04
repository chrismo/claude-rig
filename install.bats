#!/usr/bin/env bats

# Test suite for install.sh
#
# Overrides CLAUDE_DIR and LOCAL_BIN to a temp directory so tests
# don't touch real ~/.claude/ settings. Each test gets a fresh dir.

INSTALLER="$BATS_TEST_DIRNAME/install.sh"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/install-test.XXXXXX")"
  export CLAUDE_DIR="$TEST_DIR/.claude"
  export LOCAL_BIN="$TEST_DIR/.local/bin"
  mkdir -p "$CLAUDE_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Run the installer, capturing output
run_installer() {
  run bash "$INSTALLER"
}

# Read a key from settings.json using super
settings_get() {
  super -f line -c "$1" "$CLAUDE_DIR/settings.json"
}

# ── Fresh install ──────────────────────────────────────────────────────────────

@test "fresh install: creates settings.json from scratch" {
  run_installer
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_DIR/settings.json" ]
}

@test "fresh install: statusLine is configured" {
  run_installer
  [ "$status" -eq 0 ]
  local type
  type=$(settings_get 'this.statusLine.type')
  [ "$type" = "command" ]
}

@test "fresh install: PreToolUse hook is configured" {
  run_installer
  [ "$status" -eq 0 ]
  local matcher
  matcher=$(settings_get 'this.hooks.PreToolUse[0].matcher')
  [ "$matcher" = "Bash" ]
}

@test "fresh install: SessionStart hooks are configured (startup, resume, clear)" {
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(settings_get 'len(this.hooks.SessionStart)')
  [ "$count" -eq 3 ]
}

@test "fresh install: all four event hooks are configured" {
  run_installer
  [ "$status" -eq 0 ]
  for event in UserPromptSubmit PermissionRequest PostToolUse Stop; do
    local count
    count=$(settings_get "count(this.hooks.$event)")
    [ "$count" -ge 1 ]
  done
}

# ── Permissions merge ──────────────────────────────────────────────────────────

@test "permissions: allow.sup entries are merged" {
  run_installer
  [ "$status" -eq 0 ]
  local allows
  allows=$(settings_get 'this.permissions.allow')
  [[ "$allows" == *"Write(.claude/tmp/*)"* ]]
  [[ "$allows" == *"Edit(.claude/tmp/*)"* ]]
}

@test "permissions: existing allow rules are preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git add:*)"],
    "defaultMode": "default"
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  local allows
  allows=$(settings_get 'this.permissions.allow')
  [[ "$allows" == *"Bash(git add:*)"* ]]
  [[ "$allows" == *"Write(.claude/tmp/*)"* ]]
}

@test "permissions: existing defaultMode is preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git add:*)"],
    "defaultMode": "default"
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  local mode
  mode=$(settings_get 'this.permissions.defaultMode')
  [ "$mode" = "default" ]
}

# ── Idempotency ────────────────────────────────────────────────────────────────

@test "idempotent: running twice produces same settings" {
  run_installer
  [ "$status" -eq 0 ]
  local first_run
  first_run=$(cat "$CLAUDE_DIR/settings.json")

  run_installer
  [ "$status" -eq 0 ]
  local second_run
  second_run=$(cat "$CLAUDE_DIR/settings.json")

  [ "$first_run" = "$second_run" ]
}

@test "idempotent: permissions not duplicated on re-run" {
  run_installer
  [ "$status" -eq 0 ]
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(settings_get 'unnest this.permissions.allow | where this == "Write(.claude/tmp/*)" | count()')
  [ "$count" -eq 1 ]
}

# ── Symlinks: skills ──────────────────────────────────────────────────────────

@test "skills: top-level .md files are symlinked" {
  run_installer
  [ "$status" -eq 0 ]
  # Check that at least one skill was installed
  local count
  count=$(find "$CLAUDE_DIR/commands" -maxdepth 1 -name "*.md" -type l | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

@test "skills: symlinks point to repo source" {
  run_installer
  [ "$status" -eq 0 ]
  for link in "$CLAUDE_DIR/commands"/*.md; do
    if [ -L "$link" ]; then
      local target
      target=$(readlink "$link")
      [[ "$target" == "$BATS_TEST_DIRNAME/skills/"* ]]
    fi
  done
}

# ── Symlinks: agents ──────────────────────────────────────────────────────────

@test "agents: .md files are symlinked" {
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(find "$CLAUDE_DIR/agents" -maxdepth 1 -name "*.md" -type l | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

@test "agents: symlinks point to repo source" {
  run_installer
  [ "$status" -eq 0 ]
  for link in "$CLAUDE_DIR/agents"/*.md; do
    if [ -L "$link" ]; then
      local target
      target=$(readlink "$link")
      [[ "$target" == "$BATS_TEST_DIRNAME/agents/"* ]]
    fi
  done
}

# ── Symlinks: rules ──────────────────────────────────────────────────────────

@test "rules: .md files are symlinked" {
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(find "$CLAUDE_DIR/rules" -maxdepth 1 -name "*.md" -type l | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

# ── Symlinks: bin scripts ─────────────────────────────────────────────────────

@test "bin: scripts are symlinked to ~/.local/bin" {
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(find "$TEST_DIR/.local/bin" -type l | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

# ── Backup ─────────────────────────────────────────────────────────────────────

@test "backup: creates timestamped backup of settings.json" {
  echo '{"existing": true}' > "$CLAUDE_DIR/settings.json"
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(find "$CLAUDE_DIR" -name "settings-bak-*.json" | wc -l | tr -d ' ')
  [ "$count" -ge 1 ]
}

# ── Existing user settings ────────────────────────────────────────────────────

@test "existing settings: non-installer keys are preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "spinnerVerbs": {"mode": "replace", "verbs": ["Jamming"]},
  "alwaysThinkingEnabled": true
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  local thinking
  thinking=$(settings_get 'this.alwaysThinkingEnabled')
  [ "$thinking" = "true" ]
  local verb
  verb=$(settings_get 'this.spinnerVerbs.verbs[0]')
  [ "$verb" = "Jamming" ]
}
