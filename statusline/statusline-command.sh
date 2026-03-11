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

# Install with ~/.claude/settings.json
#
# ... but don't overwrite existing settings.json
#
# {
#   ...
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/.claude/statusline-command.sh"
#   }
# }

# install with this:
#   new_settings=$(
#     super -J -c "statusLine:={type:'command',command:'bash $(pwd)/statusline-command.sh'}" \
#       ~/.claude/settings.json
#   )
#   mv -v ~/.claude/settings.json ~/.claude/settings-bak.json
#   echo "$new_settings" >~/.claude/settings.json

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


# Get cost information formatted with duration
function cost_info() {
  local cost_usd=$(super -f line -c 'coalesce(cost.total_cost_usd, 0)' /tmp/claude-status-input.json)
  local duration_ms=$(super -f line -c 'coalesce(cost.total_duration_ms, 0)' /tmp/claude-status-input.json)
  local api_duration_ms=$(super -f line -c 'coalesce(cost.total_api_duration_ms, 0)' /tmp/claude-status-input.json)

  # Convert milliseconds to duration - SuperDB handles formatting automatically
  local formatted_duration=$(super -f line -c "values $duration_ms / 1000 | f'{this}s'::duration")
  local formatted_api_duration=$(super -f line -c "values $api_duration_ms / 1000 | f'{this}s'::duration")

  printf "\$%.2f | %s (api: %s)" "$cost_usd" "$formatted_duration" "$formatted_api_duration"
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

# Get lines added/removed stats
function lines_changed() {
  local added=$(super -f line -c 'coalesce(cost.total_lines_added, 0)' /tmp/claude-status-input.json)
  local removed=$(super -f line -c 'coalesce(cost.total_lines_removed, 0)' /tmp/claude-status-input.json)

  echo -e "${muted_green}+${added}${color_reset}/${muted_red}-${removed}${color_reset}"
}

# Get context window usage as percentage
function context_usage() {
  local input_tokens=$(super -f line -c 'coalesce(context_window.total_input_tokens, 0)' /tmp/claude-status-input.json)
  local output_tokens=$(super -f line -c 'coalesce(context_window.total_output_tokens, 0)' /tmp/claude-status-input.json)
  local window_size=$(super -f line -c 'coalesce(context_window.context_window_size, 200000)' /tmp/claude-status-input.json)

  local total=$((input_tokens + output_tokens))
  local percent=$((total * 100 / window_size))

  local color="$muted_green"
  if [[ $percent -ge 90 ]]; then
    color="$muted_red"
  elif [[ $percent -ge 80 ]]; then
    color="$muted_yellow"
  fi

  echo -e "${color}ctx: ${percent}%${color_reset}"
}

# Main execution
read_claude_input

cd "$(current_dir)" 2>/dev/null || true

printf "%s | %s | %s | Claude %s | %s | %s\n" "$(project_name)" "$(git_status)" "$(relative_dir)" "$(claude_version)" "$(model_name)" "$(sandbox_status)"
printf "%s | %s | %s | %s\n" "$($HOME/.local/bin/hud bar 2>/dev/null)" "$(cost_info)" "$(lines_changed)" "$(context_usage)"
# MAX WIDTH ON LAPTOP ------------------------> ... keep going off the right edge ----->                                                                          --------->|"
# keep in mind, Claude will sometimes use the right side to put its own messages, so that can interfere with The Perfect Layout

