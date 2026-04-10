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

@test "permissions: deny.sup entries are merged when non-empty" {
  echo '"Bash(rm -rf:*)"' > "$BATS_TEST_DIRNAME/permissions/deny.sup.test"
  # Temporarily swap deny.sup
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup" "$BATS_TEST_DIRNAME/permissions/deny.sup.orig"
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup.test" "$BATS_TEST_DIRNAME/permissions/deny.sup"
  run_installer
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup.orig" "$BATS_TEST_DIRNAME/permissions/deny.sup"
  rm -f "$BATS_TEST_DIRNAME/permissions/deny.sup.test" "$BATS_TEST_DIRNAME/permissions/deny.sup.orig"
  [ "$status" -eq 0 ]
  local denys
  denys=$(settings_get 'this.permissions.deny')
  [[ "$denys" == *"Bash(rm -rf:*)"* ]]
}

@test "permissions: empty deny.sup does not add deny key" {
  run_installer
  [ "$status" -eq 0 ]
  # deny key should not exist since deny.sup is empty
  run settings_get 'this.permissions.deny'
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "permissions: existing deny rules are preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git add:*)"],
    "deny": ["Bash(sudo:*)"],
    "defaultMode": "default"
  }
}
EOF
  echo '"Bash(rm -rf:*)"' > "$BATS_TEST_DIRNAME/permissions/deny.sup.test"
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup" "$BATS_TEST_DIRNAME/permissions/deny.sup.orig"
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup.test" "$BATS_TEST_DIRNAME/permissions/deny.sup"
  run_installer
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup.orig" "$BATS_TEST_DIRNAME/permissions/deny.sup"
  rm -f "$BATS_TEST_DIRNAME/permissions/deny.sup.test" "$BATS_TEST_DIRNAME/permissions/deny.sup.orig"
  [ "$status" -eq 0 ]
  local denys
  denys=$(settings_get 'this.permissions.deny')
  [[ "$denys" == *"Bash(sudo:*)"* ]]
  [[ "$denys" == *"Bash(rm -rf:*)"* ]]
}

# ── cc-audit rules ───────────────────────────────────────────────────────────

@test "cc-audit-rules: not installed when no json files" {
  run_installer
  [ "$status" -eq 0 ]
  [ ! -e "${CC_AUDIT_DIR:-$TEST_DIR/.cc-audit}/rules" ]
}

@test "cc-audit-rules: symlinked when json files present" {
  export CC_AUDIT_DIR="$TEST_DIR/.cc-audit"
  mkdir -p "$BATS_TEST_DIRNAME/cc-audit-rules"
  echo '{"safe":[]}' > "$BATS_TEST_DIRNAME/cc-audit-rules/test-rule.json"
  run_installer
  rm -f "$BATS_TEST_DIRNAME/cc-audit-rules/test-rule.json"
  [ "$status" -eq 0 ]
  [ -L "$CC_AUDIT_DIR/rules" ]
  local target
  target=$(readlink "$CC_AUDIT_DIR/rules")
  [[ "$target" == "$BATS_TEST_DIRNAME/cc-audit-rules" ]]
}

# ── Sandbox allowWrite merge ──────────────────────────────────────────────────

@test "sandbox: allowWrite paths are merged" {
  run_installer
  [ "$status" -eq 0 ]
  local paths
  paths=$(settings_get 'join(this.sandbox.filesystem.allowWrite, ",")')
  [[ "$paths" == *"~/.claude/logs"* ]]
  [[ "$paths" == *"~/.claude/contexts"* ]]
}

@test "sandbox: existing allowWrite paths are preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "sandbox": {
    "filesystem": {
      "allowWrite": ["~/.custom/path"]
    }
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  local paths
  paths=$(settings_get 'join(this.sandbox.filesystem.allowWrite, ",")')
  [[ "$paths" == *"~/.custom/path"* ]]
  [[ "$paths" == *"~/.claude/logs"* ]]
}

@test "sandbox: allowWrite not duplicated on re-run" {
  run_installer
  [ "$status" -eq 0 ]
  run_installer
  [ "$status" -eq 0 ]
  local count
  count=$(settings_get 'unnest this.sandbox.filesystem.allowWrite | where this == "~/.claude/logs" | count()')
  [ "$count" -eq 1 ]
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

# ── Harvest ──────────────────────────────────────────────────────────────────

HARVESTER="$BATS_TEST_DIRNAME/bin/harvest.sh"

# Save and restore .sup files around harvest tests
harvest_setup() {
  cp "$BATS_TEST_DIRNAME/permissions/allow.sup" "$TEST_DIR/allow.sup.orig"
  cp "$BATS_TEST_DIRNAME/permissions/deny.sup" "$TEST_DIR/deny.sup.orig"
}

harvest_teardown() {
  cp "$TEST_DIR/allow.sup.orig" "$BATS_TEST_DIRNAME/permissions/allow.sup"
  cp "$TEST_DIR/deny.sup.orig" "$BATS_TEST_DIRNAME/permissions/deny.sup"
}

@test "harvest: extracts allow rules from settings.json" {
  harvest_setup
  # Start with empty allow.sup so count is predictable
  : > "$BATS_TEST_DIRNAME/permissions/allow.sup"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Write(.claude/tmp/*)", "Bash(git add:*)", "Edit(.claude/tmp/*)"]
  }
}
EOF
  run bash "$HARVESTER"
  harvest_teardown
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 allow rules"* ]]
}

@test "harvest: extracts deny rules from settings.json" {
  harvest_setup
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Write(.claude/tmp/*)"],
    "deny": ["Bash(sudo:*)", "Bash(rm -rf:*)"]
  }
}
EOF
  run bash "$HARVESTER"
  harvest_teardown
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 deny rules"* ]]
}

@test "harvest: dry-run does not modify files" {
  harvest_setup
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git add:*)", "Write(.claude/tmp/*)"]
  }
}
EOF
  run bash "$HARVESTER" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== permissions/allow.sup"* ]]
  # File should be unchanged
  diff "$BATS_TEST_DIRNAME/permissions/allow.sup" "$TEST_DIR/allow.sup.orig"
  harvest_teardown
}

@test "harvest: handles missing deny gracefully" {
  harvest_setup
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Write(.claude/tmp/*)"]
  }
}
EOF
  run bash "$HARVESTER"
  harvest_teardown
  [ "$status" -eq 0 ]
  [[ "$output" == *"No deny rules"* ]]
}

@test "harvest: merges with existing allow.sup entries" {
  harvest_setup
  # Seed allow.sup with an entry NOT in settings.json
  echo '"Bash(launchctl load:*)"' > "$BATS_TEST_DIRNAME/permissions/allow.sup"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Write(.claude/tmp/*)"]
  }
}
EOF
  run bash "$HARVESTER"
  local result
  result=$(cat "$BATS_TEST_DIRNAME/permissions/allow.sup")
  harvest_teardown
  [ "$status" -eq 0 ]
  # Both the existing entry and the harvested entry should be present
  [[ "$result" == *'"Bash(launchctl load:*)"'* ]]
  [[ "$result" == *'"Write(.claude/tmp/*)"'* ]]
}

@test "harvest: merges with existing deny.sup entries" {
  harvest_setup
  # Seed deny.sup with an entry NOT in settings.json
  echo '"Bash(sudo:*)"' > "$BATS_TEST_DIRNAME/permissions/deny.sup"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "deny": ["Bash(rm -rf:*)"]
  }
}
EOF
  run bash "$HARVESTER"
  local result
  result=$(cat "$BATS_TEST_DIRNAME/permissions/deny.sup")
  harvest_teardown
  [ "$status" -eq 0 ]
  [[ "$result" == *'"Bash(sudo:*)"'* ]]
  [[ "$result" == *'"Bash(rm -rf:*)"'* ]]
}

@test "harvest: deduplicates entries" {
  harvest_setup
  # Seed allow.sup with an entry that's also in settings.json
  echo '"Write(.claude/tmp/*)"' > "$BATS_TEST_DIRNAME/permissions/allow.sup"
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Write(.claude/tmp/*)", "Bash(git add:*)"]
  }
}
EOF
  run bash "$HARVESTER"
  local result
  result=$(cat "$BATS_TEST_DIRNAME/permissions/allow.sup")
  harvest_teardown
  [ "$status" -eq 0 ]
  # Write(.claude/tmp/*) should appear exactly once
  local count
  count=$(echo "$result" | grep -c 'Write(.claude/tmp/\*)')
  [ "$count" -eq 1 ]
}
