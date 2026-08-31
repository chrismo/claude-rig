#!/usr/bin/env bats

# Test suite for install.sh
#
# Overrides CLAUDE_DIR to a temp directory so tests
# don't touch real ~/.claude/ settings. Each test gets a fresh dir.

INSTALLER="$BATS_TEST_DIRNAME/install.sh"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/install-test.XXXXXX")"
  export CLAUDE_DIR="$TEST_DIR/.claude"
  # Keep bin symlinks hermetic — otherwise the installer writes into the real
  # ~/.local/bin during tests.
  export LOCAL_BIN="$TEST_DIR/local-bin"
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

@test "fresh install: SessionStart carries the drift and lemmalog hooks" {
  # SessionStart was retired once, then brought back by d220e69 for
  # internals-drift.sh. This suite asserted the retirement long after it
  # stopped being true; it now asserts what the installer actually writes.
  run_installer
  [ "$status" -eq 0 ]
  local count drift brief
  count=$(settings_get 'len(this.hooks.SessionStart)')
  [ "$count" -eq 2 ]
  drift=$(settings_get 'this.hooks.SessionStart[0].hooks[0].command')
  [[ "$drift" == *"internals-drift.sh"* ]]
  brief=$(settings_get 'this.hooks.SessionStart[1].hooks[0].command')
  [[ "$brief" == *"lemma-brief.sh"* ]]
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

@test "hooks: a user's own SessionStart entry is replaced by ours on re-install" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": "/old/ensure-sandbox.sh"}]}
    ]
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  # A named key after the ...this.hooks spread replaces that event's array
  # wholesale, so claude-rig owns SessionStart outright: the stale entry is
  # gone and both of ours are present.
  local count cmd matcher
  count=$(settings_get 'len(this.hooks.SessionStart)')
  [ "$count" -eq 2 ]
  cmd=$(settings_get 'this.hooks.SessionStart[0].hooks[0].command')
  [[ "$cmd" != *"/old/ensure-sandbox.sh"* ]]
  # And the rest of the settings survived the replacement.
  matcher=$(settings_get 'this.hooks.PreToolUse[0].matcher')
  [ "$matcher" = "Bash" ]
}

@test "hooks: user-managed hook event types are preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "hooks": {
    "SubagentStop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "/my/custom-hook.sh"}]}
    ]
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(settings_get 'this.hooks.SubagentStop[0].hooks[0].command')
  [ "$cmd" = "/my/custom-hook.sh" ]
  # And claude-rig's hooks are also installed alongside
  local matcher
  matcher=$(settings_get 'this.hooks.PreToolUse[0].matcher')
  [ "$matcher" = "Bash" ]
}

@test "fresh install: PostToolUse carries the lemmalog commit hook" {
  # Appended alongside the tab-status entry rather than replacing it: the
  # hook queues commits for later assertion into lemmalog.
  run_installer
  [ "$status" -eq 0 ]
  local count cmd matcher
  count=$(settings_get 'len(this.hooks.PostToolUse)')
  [ "$count" -eq 2 ]
  matcher=$(settings_get 'this.hooks.PostToolUse[1].matcher')
  [ "$matcher" = "Bash" ]
  cmd=$(settings_get 'this.hooks.PostToolUse[1].hooks[0].command')
  [[ "$cmd" == *"lemma-commit.sh"* ]]
}

@test "fresh install: the lemmalog commit hook has no if: prefilter" {
  # `if: "Bash(git commit *)"` would stop the hook spawning for non-matching
  # commands, but it is a prefix STRING match with no shell parsing, so it
  # misses `cd <repo> && git commit ...` -- the common shape here. The script
  # filters on tool_input.command instead.
  run_installer
  [ "$status" -eq 0 ]
  run settings_get 'this.hooks.PostToolUse[1].hooks[0].if'
  [ "$status" -ne 0 ] || [ "$output" = "error(\"missing\")" ]
}

@test "fresh install: Stop hook includes claude-tabs save" {
  run_installer
  [ "$status" -eq 0 ]
  local count cmd
  count=$(settings_get 'len(this.hooks.Stop)')
  [ "$count" -eq 2 ]
  cmd=$(settings_get 'this.hooks.Stop[1].hooks[0].command')
  [[ "$cmd" == *"claude-tabs save"* ]]
}

@test "fresh install: Stop hook resolves status via tab-status stop (bg-aware)" {
  run_installer
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(settings_get 'this.hooks.Stop[0].hooks[0].command')
  [[ "$cmd" == *"tab-status --hook stop"* ]]
}

@test "fresh install: UserPromptSubmit engages (clears the bg reminder)" {
  run_installer
  [ "$status" -eq 0 ]
  local cmd
  cmd=$(settings_get 'this.hooks.UserPromptSubmit[0].hooks[0].command')
  [[ "$cmd" == *"tab-status --hook engage"* ]]
}

# ── Permissions merge ──────────────────────────────────────────────────────────

@test "permissions: allow.sup entries are merged" {
  run_installer
  [ "$status" -eq 0 ]
  local allows
  allows=$(settings_get 'this.permissions.allow')
  # Edit(), not Write() - Claude Code warns that Write() rules gate nothing,
  # so 13e56e7 dropped them from allow.sup as pure duplicates.
  [[ "$allows" == *"Edit(.claude/tmp/*)"* ]]
  [[ "$allows" == *"Edit(tmp/*)"* ]]
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
  [[ "$allows" == *"Edit(.claude/tmp/*)"* ]]
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
  count=$(settings_get 'unnest this.permissions.allow | where this == "Edit(.claude/tmp/*)" | count()')
  [ "$count" -eq 1 ]
}

# ── Symlinks: skills ──────────────────────────────────────────────────────────

@test "skills: directory-based skills are symlinked" {
  run_installer
  [ "$status" -eq 0 ]
  # Check that at least one skill directory was installed
  local count
  count=$(find "$CLAUDE_DIR/skills" -maxdepth 1 -type l -not -name ".*" | wc -l | tr -d ' ')
  [ "$count" -gt 0 ]
}

@test "skills: symlinks point to repo source" {
  run_installer
  [ "$status" -eq 0 ]
  for link in "$CLAUDE_DIR/skills"/*/; do
    if [ -L "${link%/}" ]; then
      local target
      target=$(readlink "${link%/}")
      [[ "$target" == "$BATS_TEST_DIRNAME/skills/"* ]]
    fi
  done
}

@test "skills: stale bare-file symlinks are cleaned up" {
  mkdir -p "$CLAUDE_DIR/skills"
  # Simulate a stale goal-compose.md symlink from before restructuring
  ln -s "/some/old/path/goal-compose.md" "$CLAUDE_DIR/skills/goal-compose.md"
  run_installer
  [ "$status" -eq 0 ]
  # Stale .md symlink should be gone
  [ ! -e "$CLAUDE_DIR/skills/goal-compose.md" ]
  # Directory symlink should exist instead
  [ -L "$CLAUDE_DIR/skills/goal-compose" ]
}

@test "skills: dangling symlink for a deleted skill is pruned" {
  run_installer
  [ "$status" -eq 0 ]
  # Simulate a skill removed from the repo: a symlink in dest pointing into
  # SKILLS_SRC at a name that no longer has a source directory.
  ln -s "$BATS_TEST_DIRNAME/skills/deleted-skill/" "$CLAUDE_DIR/skills/deleted-skill"
  [ -L "$CLAUDE_DIR/skills/deleted-skill" ]
  run_installer
  [ "$status" -eq 0 ]
  # Prune should remove the orphaned symlink
  [ ! -L "$CLAUDE_DIR/skills/deleted-skill" ]
}

@test "skills: a user's broken symlink pointing outside the repo is left alone" {
  run_installer
  [ "$status" -eq 0 ]
  # A broken symlink the user created, pointing somewhere other than SKILLS_SRC.
  ln -s "/some/other/place/my-skill" "$CLAUDE_DIR/skills/my-skill"
  run_installer
  [ "$status" -eq 0 ]
  # Prune must only touch symlinks pointing into the repo skills dir.
  [ -L "$CLAUDE_DIR/skills/my-skill" ]
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

# ── Symlinks: bin commands ──────────────────────────────────────────────────

@test "bin: claude-tabs is symlinked from bin/" {
  run_installer
  [ "$status" -eq 0 ]
  [ -L "$LOCAL_BIN/claude-tabs" ]
  local target
  target=$(readlink "$LOCAL_BIN/claude-tabs")
  [[ "$target" == "$BATS_TEST_DIRNAME/bin/claude-tabs" ]]
}

@test "bin: ticket-sort is symlinked from bin/" {
  run_installer
  [ "$status" -eq 0 ]
  [ -L "$LOCAL_BIN/ticket-sort" ]
  local target
  target=$(readlink "$LOCAL_BIN/ticket-sort")
  [[ "$target" == "$BATS_TEST_DIRNAME/bin/ticket-sort" ]]
}

@test "bin: claude-src is symlinked from bin/" {
  run_installer
  [ "$status" -eq 0 ]
  [ -L "$LOCAL_BIN/claude-src" ]
  local target
  target=$(readlink "$LOCAL_BIN/claude-src")
  [[ "$target" == "$BATS_TEST_DIRNAME/bin/claude-src" ]]
}

@test "bin: analysis scripts in bin/ are not installed as commands" {
  # The install list is an allowlist for exactly this reason - adding a
  # user-facing command means adding it there, and a new .sh left in bin/
  # must not silently become a user command.
  run_installer
  [ "$status" -eq 0 ]
  [ ! -e "$LOCAL_BIN/harvest.sh" ]
  [ ! -e "$LOCAL_BIN/ticket-sort.bats" ]
  [ ! -e "$LOCAL_BIN/wt-new.bats" ]
}

@test "bin: wt-new is symlinked from bin/" {
  run_installer
  [ "$status" -eq 0 ]
  [ -L "$LOCAL_BIN/wt-new" ]
  local target
  target=$(readlink "$LOCAL_BIN/wt-new")
  [[ "$target" == "$BATS_TEST_DIRNAME/bin/wt-new" ]]
}

@test "bin: wt is symlinked from bin/" {
  run_installer
  [ "$status" -eq 0 ]
  [ -L "$LOCAL_BIN/wt" ]
  local target
  target=$(readlink "$LOCAL_BIN/wt")
  [[ "$target" == "$BATS_TEST_DIRNAME/bin/wt" ]]
}

@test "bin: tab-status is symlinked from tab-status/" {
  run_installer
  [ "$status" -eq 0 ]
  [ -L "$LOCAL_BIN/tab-status" ]
  local target
  target=$(readlink "$LOCAL_BIN/tab-status")
  [[ "$target" == "$BATS_TEST_DIRNAME/tab-status/tab-status" ]]
}

@test "bin: a stale tab-status symlink (e.g. to another repo) is replaced" {
  # Models the brain takeover: an existing symlink pointing elsewhere must be
  # repointed at claude-rig's copy.
  mkdir -p "$LOCAL_BIN"
  ln -s "/some/other/repo/xdg/.local/bin/tab-status" "$LOCAL_BIN/tab-status"
  run_installer
  [ "$status" -eq 0 ]
  local target
  target=$(readlink "$LOCAL_BIN/tab-status")
  [[ "$target" == "$BATS_TEST_DIRNAME/tab-status/tab-status" ]]
}

# ── shell/rig.zsh entrypoint ────────────────────────────────────────────────
# shell/rig.zsh holds the cd-wrappers for wt-new and wt (a subprocess cannot cd
# its caller's shell, so those halves have to live in a sourced file). It only
# takes effect if .zshrc sources it — but .zshrc is not in the installer's
# symlink set and the installer does not own files outside that set. So it
# VERIFIES and instructs; it must never edit .zshrc itself.

@test "zshrc: instructs the user when the rig.zsh source line is missing" {
  export ZSHRC="$TEST_DIR/zshrc"
  printf 'export PATH=/usr/bin\n' > "$ZSHRC"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *"shell/rig.zsh"* ]]
  [[ "$output" == *"source"* ]]
}

@test "zshrc: does not modify .zshrc when the source line is missing" {
  export ZSHRC="$TEST_DIR/zshrc"
  printf 'export PATH=/usr/bin\n' > "$ZSHRC"
  local before
  before=$(cat "$ZSHRC")
  run_installer
  [ "$status" -eq 0 ]
  [ "$(cat "$ZSHRC")" = "$before" ]
}

@test "zshrc: does not create .zshrc when it does not exist" {
  export ZSHRC="$TEST_DIR/no-such-zshrc"
  run_installer
  [ "$status" -eq 0 ]
  [ ! -e "$ZSHRC" ]
  [[ "$output" == *"shell/rig.zsh"* ]]
}

@test "zshrc: confirms when the source line is already present" {
  export ZSHRC="$TEST_DIR/zshrc"
  printf 'source %s/shell/rig.zsh\n' "$BATS_TEST_DIRNAME" > "$ZSHRC"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *"rig.zsh"* ]]
  [[ "$output" != *"Add this to"* ]]
}

@test "zshrc: a commented-out source line does not count as present" {
  export ZSHRC="$TEST_DIR/zshrc"
  printf '# source %s/shell/rig.zsh\n' "$BATS_TEST_DIRNAME" > "$ZSHRC"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *"Add this to"* ]]
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

# ── Env vars ──────────────────────────────────────────────────────────────────

@test "env: fresh install does not set CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" {
  run_installer
  [ "$status" -eq 0 ]
  ! grep -q 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$CLAUDE_DIR/settings.json"
}

# Removed, not merely left unmanaged: the var still changes when Claude Code
# auto-compacts, so a value left behind in settings.json would go on acting on
# every machine that ever ran the old installer.
@test "env: an existing CLAUDE_AUTOCOMPACT_PCT_OVERRIDE is removed" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "64"
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  ! grep -q 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$CLAUDE_DIR/settings.json"
}

@test "env: unrelated env keys are preserved" {
  cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "64"
  }
}
EOF
  run_installer
  [ "$status" -eq 0 ]
  local val
  val=$(settings_get 'this.env.CLAUDE_CODE_DISABLE_TERMINAL_TITLE')
  [ "$val" = "1" ]
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
