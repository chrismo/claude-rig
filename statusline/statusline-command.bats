#!/usr/bin/env bats

# Integration tests for the statusline plugin loader.

SCRIPT="$BATS_TEST_DIRNAME/statusline-command.sh"

setup() {
  TEST_DIR="$(mktemp -d "$TMPDIR/statusline-loader-test.XXXXXX")"
  PLUGINS="$TEST_DIR/plugins"
  mkdir -p "$PLUGINS"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_plugin() {
  local path=$1 message=$2
  cat > "$path" <<EOF
#!/bin/bash
echo "$message"
EOF
  chmod +x "$path"
}

run_loader() {
  STATUSLINE_PLUGIN_DIR="$PLUGINS" bash "$SCRIPT" <<<'{}'
}

@test "runs an executable plugin in the plugin dir" {
  write_plugin "$PLUGINS/1.10-hello" "HELLO"

  run run_loader
  [[ "$output" == *"HELLO"* ]]
}

@test "skips a non-executable plugin" {
  write_plugin "$PLUGINS/1.10-hello" "HELLO"
  chmod -x "$PLUGINS/1.10-hello"

  run run_loader
  [[ "$output" != *"HELLO"* ]]
}

@test "skips a subdirectory like plugins.d/disabled/" {
  mkdir -p "$PLUGINS/disabled"
  write_plugin "$PLUGINS/1.10-active" "ACTIVE"
  write_plugin "$PLUGINS/disabled/1.20-inactive" "INACTIVE"

  run run_loader
  [[ "$output" == *"ACTIVE"* ]]
  [[ "$output" != *"INACTIVE"* ]]
}
