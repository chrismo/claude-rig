#!/bin/bash

# Set Ghostty tab title dynamically:
#   - In git repo: dir_name (branch)
#   - Not in git repo: dir_name, or dir_name (command) while command runs
#   - Home directory shows as ~
#   - Status emoji prefix if set via tab-status command
#
# Usage: Source from shell rc and hook into precmd/preexec
#
# Zsh (~/.zshrc):
#   source ~/.config/ghostty/set-title.sh
#   precmd_functions+=(ghostty_title)
#   preexec_functions+=(ghostty_preexec)
#
# Bash (~/.bashrc):
#   source ~/.config/ghostty/set-title.sh
#   PROMPT_COMMAND="ghostty_title; $PROMPT_COMMAND"
#   # Note: Bash preexec requires bash-preexec or trap DEBUG
#
# To limit to Ghostty only (skip in JetBrains, etc.):
#   ghostty_title_wrapper() { [[ "$TERM_PROGRAM" == "ghostty" ]] && ghostty_title; }
#   ghostty_preexec_wrapper() { [[ "$TERM_PROGRAM" == "ghostty" ]] && ghostty_preexec "$@"; }
#   precmd_functions+=(ghostty_title_wrapper)
#   preexec_functions+=(ghostty_preexec_wrapper)
#
# Also add to ghostty config:
#   shell-integration-features = cursor,sudo,no-title
#
# Status prefixes (set via tab-status command):
#   🟡 waiting  - waiting on external (data team, PR review)
#   🟢 active   - actively working
#   🔵 paused   - paused, will return later
#   🔴 blocked  - blocked, needs attention

__ghostty_dir_name() {
  if [[ "$PWD" == "$HOME" ]]; then
    echo "~"
  else
    basename "$PWD"
  fi
}

# Get status emoji for current worktree
__ghostty_status_prefix() {
  local worktree status_file wt_status
  worktree=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
  status_file="$HOME/.claude/tab-status/$worktree"

  if [[ -f "$status_file" ]]; then
    wt_status=$(cat "$status_file")
    case "$wt_status" in
      waiting) echo "🟡 " ;;
      active)  echo "🟢 " ;;
      idle)    echo "⚪ " ;;
      paused)  echo "🔵 " ;;
      blocked) echo "🔴 " ;;
    esac
  fi
}

# Called before command executes - show command in title (non-git only)
ghostty_preexec() {
  local cmd="${1%% *}"

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    printf '\e]0;%s\a' "$(__ghostty_dir_name) (${cmd})"
  fi
}

# Called after command finishes - reset to normal title
ghostty_title() {
  local dir_name
  local branch
  local title
  local prefix

  dir_name=$(__ghostty_dir_name)
  prefix=$(__ghostty_status_prefix)

  if git rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    title="${prefix}${dir_name} (${branch})"
  else
    title="${prefix}${dir_name}"
  fi

  printf '\e]0;%s\a' "$title"
}
