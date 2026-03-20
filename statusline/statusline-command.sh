#!/bin/bash

# NOTE: Target Bash 3.2 compatibility (macOS default).
# Avoid: ${var,,}, ${var^^}, local -n, associative arrays, etc.

# Colors (dim/muted variants)
muted_green="\033[2;32m"
muted_yellow="\033[2;33m"
muted_red="\033[2;31m"
color_reset="\033[2;37m"  # dim white (Claude's default)

# TODO: • Added context_window.used_percentage and
#  context_window.remaining_percentage fields to status line input for
#  easier context window display
#
# claude 2.1.6 or .7

# TODO: Plan usage limits (session %, weekly %) not yet in statusline payload.
# Tracking issue: https://github.com/anthropics/claude-code/issues/28999

# Install via the claude-rig installer:
#   bash /path/to/claude-rig/install/claude-installer.sh
#
# Or manually in ~/.claude/settings.json:
# {
#   "statusLine": {
#     "type": "command",
#     "command": "bash /path/to/claude-rig/statusline/statusline-command.sh"
#   }
# }

# Read Claude Code input from stdin and save to temp file
function read_claude_input() {
  local input
  input=$(cat)
  echo "$input" > /tmp/claude-status-input.json
}

# Get current working directory from Claude input, fallback to pwd
function current_dir() {
  local current_dir=$(super -f line -c 'coalesce(workspace.current_dir, "")' /tmp/claude-status-input.json)
  if [[ -z "$current_dir" ]]; then
    current_dir=$(pwd)
  fi
  echo "$current_dir"
}

function get_project_dir() {
  super -f line -c 'coalesce(workspace.project_dir, "")' /tmp/claude-status-input.json
}

# Get project name (basename of project_dir)
function project_name() {
  local project_dir=$(get_project_dir)
  if [[ -z "$project_dir" ]]; then
    echo "."
  else
    basename "$project_dir"
  fi
}

# Get relative subdirectory path from project_dir to current_dir
function relative_dir() {
  local project_dir=$(get_project_dir)
  local current=$(super -f line -c 'coalesce(workspace.current_dir, "")' /tmp/claude-status-input.json)

  if [[ -z "$project_dir" || -z "$current" || "$current" == "$project_dir" ]]; then
    echo "."
    return
  fi

  # Strip project_dir prefix to get relative path
  echo "${current#$project_dir/}"
}



# Get model information from Claude input
function model_name() {
  local model_name=$(super -f line -c 'coalesce(model.display_name, "")' /tmp/claude-status-input.json)
  if [[ -z "$model_name" ]]; then
    model_name="Claude"
  fi

  local effort=""
  # Future-proof: check statusline input first (pending feature request #9488)
  effort=$(super -f line -c 'coalesce(model.reasoning_effort, "")' /tmp/claude-status-input.json 2>/dev/null)
  # Env var override
  if [[ -z "$effort" && -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]]; then
    effort="$CLAUDE_CODE_EFFORT_LEVEL"
  fi
  # Fall back to settings.json.
  # HEADS UP: Claude Code only writes effortLevel to settings.json when it's
  # NOT the default. So if the default changes (it moved from high→medium in
  # ~2.1.69), this field will be absent and we fall through to the empty case
  # below. Update the empty-string default in the case statement to match.
  if [[ -z "$effort" ]]; then
    effort=$(super -f line -c 'coalesce(effortLevel, "")' "$HOME/.claude/settings.json" 2>/dev/null)
  fi
  local dim="\033[38;5;238m"  # dark grey
  local lit="${muted_green}"
  local bars
  case "$(printf '%s' "$effort" | tr '[:upper:]' '[:lower:]')" in
    low)    bars="${lit}▌${dim}▌▌${color_reset}" ;;
    medium) bars="${lit}▌▌${dim}▌${color_reset}" ;;
    high)   bars="${lit}▌▌▌${color_reset}" ;;
    "")     bars="${lit}▌▌${dim}▌${color_reset}" ;;  # default: medium
    *)      bars="$effort" ;;
  esac
  printf "%s %b" "$model_name" "$bars"
}


function permission_mode() {
  local mode=""

  # Check project-local settings first (higher precedence)
  local local_settings="$(get_project_dir)/.claude/settings.local.json"
  if [[ -f "$local_settings" ]]; then
    mode=$(super -f line -c 'coalesce(permissions.defaultMode, "")' "$local_settings" 2>/dev/null)
  fi

  # Fall back to shared project settings
  if [[ -z "$mode" ]]; then
    local project_settings="$(get_project_dir)/.claude/settings.json"
    if [[ -f "$project_settings" ]]; then
      mode=$(super -f line -c 'coalesce(permissions.defaultMode, "")' "$project_settings" 2>/dev/null)
    fi
  fi

  # Fall back to user settings
  if [[ -z "$mode" ]]; then
    mode=$(super -f line -c 'coalesce(permissions.defaultMode, "")' "$HOME/.claude/settings.json" 2>/dev/null)
  fi

  # Default to "default" if not set anywhere
  if [[ -z "$mode" ]]; then
    mode="default"
  fi

  case "$mode" in
    default)     echo "mode: default" ;;
    acceptEdits) echo "${muted_green}mode: acceptEdits${color_reset}" ;;
    plan)        echo "${muted_yellow}mode: plan${color_reset}" ;;
    dontAsk)     echo "${muted_green}mode: dontAsk${color_reset}" ;;
    bypassPermissions) echo "${muted_red}mode: BYPASS${color_reset}" ;;
    *)           echo "mode: $mode" ;;
  esac
}

function sandbox_status() {
  # this file is actually local to the dir launched in, but ... I always launch
  # from project root
  local settings_file="$(get_project_dir)/.claude/settings.local.json"
  local sandbox_status=""

  if [[ -f "$settings_file" ]]; then
    local sandbox_enabled=$(super -f line -c 'coalesce(sandbox.enabled, false)' "$settings_file")
    if [[ "$sandbox_enabled" == "true" ]]; then
      local auto=$(super -f line -c 'coalesce(sandbox.autoAllowBashIfSandboxed, false)' "$settings_file")
      if [[ "$auto" == "true" ]]; then
        sandbox_status="${muted_green}sandbox: auto${color_reset}"
      else
        sandbox_status="sandbox: on"
      fi
    else
      sandbox_status="${muted_red}sandbox: off${color_reset}"
    fi
  fi
  echo -e "$sandbox_status"
}

function claude_version() {
  super -f line -c "values version" /tmp/claude-status-input.json
}

# Get git branch and status info
function git_status() {
  local dir=$(current_dir)
  if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
    echo ""
    return
  fi

  local branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  local status_flags=""

  # Check for uncommitted changes
  if ! git -C "$dir" diff --quiet 2>/dev/null; then
    status_flags+="*"  # modified
  fi
  if ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
    status_flags+="+"  # staged
  fi
  if [[ -n $(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null) ]]; then
    status_flags+="?"  # untracked
  fi
  local stash_count=$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$stash_count" -gt 0 ]]; then
    status_flags+="\$${stash_count}"  # stash with count
  fi

  # Check ahead/behind remote
  local upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [[ -n "$upstream" ]]; then
    local ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    local behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
    if [[ "$ahead" -gt 0 ]]; then
      status_flags+="↑${ahead}"
    fi
    if [[ "$behind" -gt 0 ]]; then
      status_flags+="↓${behind}"
    fi
  fi

  echo "git: ${branch}${status_flags}"
}


# Run line 2 plugins from plugins.d/ directory.
# Each plugin is an executable that outputs a single segment.
# Empty output = segment skipped. Sorted by filename (use numeric prefixes).
# Plugins receive CLAUDE_STATUS_INPUT env var pointing to the session JSON.
function run_plugins() {
  local plugin_dir="${STATUSLINE_PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugins.d}"
  local segments=()

  if [[ -d "$plugin_dir" ]]; then
    for plugin in "$plugin_dir"/*; do
      [[ -x "$plugin" ]] || continue
      local output
      output=$("$plugin" 2>/dev/null)
      if [[ -n "$output" ]]; then
        segments+=("$output")
      fi
    done
  fi

  # Join segments with " | "
  local line=""
  for seg in "${segments[@]}"; do
    if [[ -n "$line" ]]; then
      line+=" | $seg"
    else
      line="$seg"
    fi
  done
  printf "%s" "$line"
}

# Main execution
read_claude_input
export CLAUDE_STATUS_INPUT="/tmp/claude-status-input.json"

cd "$(current_dir)" 2>/dev/null || true

# Line 1: core session info (project, git, dir, version, model, mode, sandbox)
printf "%s | %s | %s | Claude %s | %s | %s | %s\n" "$(project_name)" "$(git_status)" "$(relative_dir)" "$(claude_version)" "$(model_name)" "$(permission_mode)" "$(sandbox_status)"
# Line 2: assembled from plugins.d/ scripts (cost, lines, context, etc.)
printf "%s\n" "$(run_plugins)"

