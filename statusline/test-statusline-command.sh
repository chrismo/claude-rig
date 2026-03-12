#!/usr/bin/env bash

# Test the statusline-command.sh script with sample data

function _script_dir() {
  dirname "${BASH_SOURCE[0]}"
}

cat "$(_script_dir)/sample-input.json" | bash "$(_script_dir)/statusline-command.sh"
