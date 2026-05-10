#!/bin/bash
#
# work-context - Show git worktrees and Claude activity
#
# Usage: work-context [command] [args]
#

set -euo pipefail

export ASDF_SUPERDB_VERSION=0.51231

# Colors
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
RESET='\033[0m'

# Cloud session branch pattern (Claude web sessions use claude/ prefix or 13-digit timestamps)
CLOUD_SESSION_BRANCH_PATTERN='(^claude/|[0-9]{13}$)'

# Config file (SuperJSON format) - check new name first, fall back to old yah.sup
if [[ -n "${WORK_CONTEXT_CONFIG:-}" ]]; then
    wc_config="$WORK_CONTEXT_CONFIG"
elif [[ -f "$HOME/.config/work-context.sup" ]]; then
    wc_config="$HOME/.config/work-context.sup"
elif [[ -f "$HOME/.config/yah.sup" ]]; then
    wc_config="$HOME/.config/yah.sup"
else
    wc_config=""
fi

# Load config with super
repos_to_check=()
github_orgs=()
standup_script=""
tz_offset_hours=-6

if [[ -n "$wc_config" ]] && [[ -f "$wc_config" ]]; then
    # Read repos array
    while IFS= read -r repo; do
        # Expand ~ to $HOME
        repos_to_check+=("${repo/#\~/$HOME}")
    done < <(super -f line -c "unnest repos" "$wc_config" 2>/dev/null)

    # Read standup script (optional field)
    standup_script=$(super -f line -c "grep('standup_script', typeof(this)::string) ? standup_script : ''" "$wc_config")
    standup_script="${standup_script/#\~/$HOME}"

    # Read timezone offset (optional field)
    tz_offset_hours=$(super -f line -c "grep('tz_offset_hours', typeof(this)::string) ? tz_offset_hours : -6" "$wc_config")

    # Read github_orgs array (optional)
    while IFS= read -r org; do
        [[ -n "$org" ]] && github_orgs+=("$org")
    done < <(super -f line -c "where has(github_orgs) | unnest github_orgs" "$wc_config" 2>/dev/null)
fi

# Fallback defaults if no config or empty repos
if [[ ${#repos_to_check[@]} -eq 0 ]]; then
    repos_to_check=(
        "$HOME/dev/myproject"
    )
fi

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

function gh_available() {
    command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1
}

function get_github_remote() {
    local repo_dir="$1"
    # Extract owner/repo from git remote (handles SSH and HTTPS)
    git -C "$repo_dir" remote get-url origin 2>/dev/null \
        | sed -E 's|.*github\.com[:/]||; s|\.git$||'
}

# ─────────────────────────────────────────────────────────────────────────────
# Worktree data collection
# ─────────────────────────────────────────────────────────────────────────────

function emit_repo_json() {
    local repo_dir="$1"
    cd "$repo_dir" 2>/dev/null || return

    local branch commit_ts commit_msg short_name dirty
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return
    commit_ts=$(git log -1 --format='%ct' 2>/dev/null) || return
    commit_msg=$(git log -1 --format='%s' 2>/dev/null | head -c 50)
    short_name=$(basename "$repo_dir")
    dirty="false"
    [[ -n $(git status --porcelain 2>/dev/null) ]] && dirty="true"

    # Escape quotes in commit message for JSON
    commit_msg="${commit_msg//\\/\\\\}"
    commit_msg="${commit_msg//\"/\\\"}"

    printf '{"name":"%s","branch":"%s","commit_ts":%s,"commit_msg":"%s","dirty":%s}\n' \
        "$short_name" "$branch" "$commit_ts" "$commit_msg" "$dirty"
}

function collect_worktree_data() {
    for repo in "${repos_to_check[@]}"; do
        [[ ! -d "$repo" ]] && continue

        emit_repo_json "$repo"

        if [[ -d "$repo/.git/worktrees" ]]; then
            for wt in "$repo/.git/worktrees"/*; do
                if [[ -f "$wt/gitdir" ]]; then
                    wt_path=$(super -i line -f line -c "replace(this, '/.git', '')" "$wt/gitdir")
                    [[ -d "$wt_path" ]] && emit_repo_json "$wt_path"
                fi
            done
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloud session data collection
# ─────────────────────────────────────────────────────────────────────────────

function emit_cloud_branch_json() {
    local repo_dir="$1"
    local branch="$2"
    local is_remote="$3"  # "true" or "false"
    local pr_number="$4"  # empty if no PR
    local pr_title="$5"

    local commit_ts age_ref
    if [[ "$is_remote" == "true" ]]; then
        age_ref="origin/$branch"
    else
        age_ref="$branch"
    fi
    commit_ts=$(git -C "$repo_dir" log -1 --format='%ct' "$age_ref" 2>/dev/null || echo "0")

    # Escape quotes in PR title for JSON
    pr_title="${pr_title//\\/\\\\}"
    pr_title="${pr_title//\"/\\\"}"

    # Emit JSON record
    printf '{"repo":"%s","branch":"%s","is_remote":%s,"commit_ts":%s,"pr_number":%s,"pr_title":"%s"}\n' \
        "$(basename "$repo_dir")" "$branch" "$is_remote" "$commit_ts" \
        "${pr_number:-null}" "$pr_title"
}

function collect_cloud_branches() {
    for repo in "${repos_to_check[@]}"; do
        [[ ! -d "$repo" ]] && continue

        local github_remote
        github_remote=$(get_github_remote "$repo")
        [[ -z "$github_remote" ]] && continue

        # Get PRs for this repo (if gh available)
        local prs="[]"
        if gh_available; then
            prs=$(gh pr list -R "$github_remote" --state open --limit 20 \
                --json number,title,headRefName 2>/dev/null || echo "[]")
        fi

        # Get local branches matching pattern
        local local_branches
        local_branches=$(git -C "$repo" branch 2>/dev/null | sed 's/^\* //' | tr -d ' ' \
            | grep -E "$CLOUD_SESSION_BRANCH_PATTERN" 2>/dev/null || true)

        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            # Look up PR for this branch
            local pr_num="" pr_title=""
            if [[ "$prs" != "[]" ]]; then
                local pr_info
                pr_info=$(echo "$prs" | super -f line -c \
                    "unnest this | where headRefName == '$branch' | values {number, title}" 2>/dev/null || true)
                if [[ -n "$pr_info" ]]; then
                    pr_num=$(echo "$pr_info" | super -f line -c "values number" 2>/dev/null || true)
                    pr_title=$(echo "$pr_info" | super -f line -c "values title" 2>/dev/null || true)
                fi
            fi
            emit_cloud_branch_json "$repo" "$branch" "false" "$pr_num" "$pr_title"
        done <<< "$local_branches"

        # Get remote-only branches matching pattern
        local remote_branches
        remote_branches=$(git -C "$repo" branch -r 2>/dev/null | grep "origin/" | sed 's|.*origin/||' | tr -d ' ' \
            | grep -E "$CLOUD_SESSION_BRANCH_PATTERN" 2>/dev/null || true)

        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            # Skip if we already have it locally
            git -C "$repo" branch --list "$branch" 2>/dev/null | grep -q . && continue
            # Look up PR
            local pr_num="" pr_title=""
            if [[ "$prs" != "[]" ]]; then
                local pr_info
                pr_info=$(echo "$prs" | super -f line -c \
                    "unnest this | where headRefName == '$branch' | values {number, title}" 2>/dev/null || true)
                if [[ -n "$pr_info" ]]; then
                    pr_num=$(echo "$pr_info" | super -f line -c "values number" 2>/dev/null || true)
                    pr_title=$(echo "$pr_info" | super -f line -c "values title" 2>/dev/null || true)
                fi
            fi
            emit_cloud_branch_json "$repo" "$branch" "true" "$pr_num" "$pr_title"
        done <<< "$remote_branches"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Open PR data collection
# ─────────────────────────────────────────────────────────────────────────────

function collect_open_prs() {
    if ! gh_available; then
        return
    fi

    if [[ ${#github_orgs[@]} -eq 0 ]]; then
        return
    fi

    for org in "${github_orgs[@]}"; do
        gh pr list --author @me --state open --limit 50 \
            --search "org:${org}" \
            --json number,title,headRefName,url,reviewDecision,headRepository,createdAt,updatedAt,isDraft \
            2>/dev/null || true
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────

function worktrees() {
    local now
    now=$(date +%s)

    echo -e "${CYAN}${BOLD}🌳 GIT WORKTREES STATUS${RESET}"
    echo -e "${DIM}───────────────────────────────────────────────────────────────${RESET}"

    # Recent worktrees (<=14 days, not staging)
    collect_worktree_data | super -f json -c "
      put age_days := ((${now} - commit_ts) / 86400)::int64
      | put dirty_mark := dirty ? '*' : ''
      | where not grep('^staging', branch)
      | where age_days <= 14
      | sort age_days
      | put age_str := age_days == 0 ? 'today' : f'{age_days}d'
      | put wt := f'{name}{dirty_mark}'
      | cut wt, age_str, branch, commit_msg
    " - | mlr --j2p --barred cat

    # Stale worktrees (>14 days), oldest last
    local stale
    stale=$(collect_worktree_data | super -f json -c "
      put age_days := ((${now} - commit_ts) / 86400)::int64
      | put dirty_mark := dirty ? '*' : ''
      | where not grep('^staging', branch)
      | where age_days > 14
      | sort age_days
      | put wt := f'{name}{dirty_mark}'
      | put age := f'{age_days}d'
      | cut wt, age, branch
    " - | mlr --j2p --headerless-csv-output cat)

    if [[ -n "$stale" ]]; then
        echo -e "\n${DIM}Stale (>2w):${RESET}"
        echo -e "${DIM}${stale}${RESET}"
    fi
    echo
}

function collect_session_data() {
    # Collect session data from per-conversation JSONL files
    # Each .jsonl has type=user messages with sessionId, gitBranch, timestamp, message.content
    local days_filter="${1:-30}"
    local projects_dir="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
    [[ -d "$projects_dir" ]] || return

    local now
    now=$(date +%s)
    local cutoff_mtime=$((now - (days_filter + 1) * 86400))

    (
        for jsonl_file in "$projects_dir"/*/*.jsonl; do
            [[ -f "$jsonl_file" ]] || continue

            # Skip files not modified within the filter window
            local file_mtime
            file_mtime=$(stat -f %m "$jsonl_file")
            [[ $file_mtime -lt $cutoff_mtime ]] && continue

            # Extract project name from path (e.g., -Users-jdoe-dev-wt1 -> wt1)
            local project_dir project_name
            project_dir=$(dirname "$jsonl_file")
            project_name=$(basename "$project_dir" | sed 's/.*-dev-//' | sed "s/-Users-$(whoami)$//")

            # Count user messages (fast grep, handles varying JSON whitespace)
            local msg_count
            msg_count=$(grep -cE '"type"\s*:\s*"user"' "$jsonl_file" 2>/dev/null) || msg_count=0

            # Skip files with no user messages (e.g., subagent files)
            [[ $msg_count -eq 0 ]] && continue

            # Emit session record from first user message
            # Cast message.content to string to ensure slicing works downstream
            super -f line -c "
              where type == 'user'
              | head 1
              | put firstPrompt := message.content::string
              | put messageCount := ${msg_count}
              | put project := '${project_name}'
              | put created := timestamp
              | cut sessionId, created, gitBranch, firstPrompt, messageCount, project
            " "$jsonl_file" 2>/dev/null
        done
    )
}

function conversations() {
    local days="${1:-7}"

    echo -e "${CYAN}${BOLD}📝 RECENT CLAUDE CONVERSATIONS (last ${days} days)${RESET}"
    echo -e "${DIM}───────────────────────────────────────────────────────────────${RESET}"

    local projects_dir="$HOME/.claude/projects"
    if [[ -d "$projects_dir" ]]; then
        :  # exists, continue
    else
        echo -e "${DIM}(Claude projects not found at $projects_dir)${RESET}"
        return
    fi

    conversations_json "$days" | super -f json -c "
      cut date, time, project, msgs:=messageCount, prompt:=first_prompt[0:80]
    " - 2>/dev/null | mlr --j2p --barred cat

    echo
}

function search() {
    local term="${1:?Usage: search <term> [days]}"
    local days="${2:-30}"
    local history_file="$HOME/.claude/history.jsonl"

    echo -e "${CYAN}${BOLD}🔍 SEARCHING CONVERSATIONS: '${term}' (last ${days} days)${RESET}"
    echo -e "${DIM}───────────────────────────────────────────────────────────────${RESET}"

    if [[ ! -f "$history_file" ]]; then
        echo -e "${DIM}(Claude history not found at $history_file)${RESET}"
        return
    fi

    # Timezone offset in milliseconds (from config)
    local tz_offset_ms=$((${tz_offset_hours#-} * 3600 * 1000))

    # Search for term in display field, return matches with context
    super -f json -c "
      put ts:=((timestamp - ${tz_offset_ms})*1000000)::time
      | where ts >= now() - '${days}d'::duration
      | where grep('(?i)${term}', display)
      | put date:=strftime('%Y-%m-%d %H:%M', ts)
      | put project:=split(project, '/')[-1]
      | put prompt:=replace(display[0:100], '\n', ' ')
      | cut date, project, sessionId, prompt
      | sort -date
    " "$history_file" 2>/dev/null | mlr --j2p --barred cat

    echo
}

function diag() {
    # Quick canary check of Claude internals assumptions.
    # Prints warnings only when something unexpected is found.
    local projects_dir="$HOME/.claude/projects"
    local history_file="$HOME/.claude/history.jsonl"
    local warnings=0

    # 1. Projects dir exists
    if [[ ! -d "$projects_dir" ]]; then
        echo -e "${BOLD}⚠ DIAG:${RESET} $projects_dir missing" >&2
        warnings=$((warnings + 1))
    fi

    # 2. history.jsonl exists and was touched recently (last 24h)
    if [[ ! -f "$history_file" ]]; then
        echo -e "${BOLD}⚠ DIAG:${RESET} $history_file missing" >&2
        warnings=$((warnings + 1))
    else
        local hist_mtime now age_hours
        now=$(date +%s)
        hist_mtime=$(stat -f %m "$history_file")
        age_hours=$(( (now - hist_mtime) / 3600 ))
        if [[ $age_hours -gt 24 ]]; then
            echo -e "${BOLD}⚠ DIAG:${RESET} history.jsonl last modified ${age_hours}h ago" >&2
            warnings=$((warnings + 1))
        fi
    fi

    # 3. Recent JSONL conversation files exist
    local recent_jsonl
    recent_jsonl=$(find "$projects_dir" -name "*.jsonl" -mtime -1 -print -quit 2>/dev/null)
    if [[ -z "$recent_jsonl" ]]; then
        echo -e "${BOLD}⚠ DIAG:${RESET} No .jsonl conversation files modified in last 24h" >&2
        warnings=$((warnings + 1))
    else
        # 4. Spot-check: most recent JSONL has expected user message structure
        local newest_jsonl
        newest_jsonl=$(ls -t "$projects_dir"/*/*.jsonl 2>/dev/null | head -1 || true)
        if [[ -n "$newest_jsonl" ]]; then
            local has_fields
            has_fields=$(super -f line -c "
              where type == 'user'
              | head 1
              | values has(sessionId) and has(timestamp) and has(message) and has(gitBranch)
            " "$newest_jsonl" 2>/dev/null) || true
            if [[ "$has_fields" != "true" ]]; then
                echo -e "${BOLD}⚠ DIAG:${RESET} Newest JSONL user message missing expected fields (sessionId/timestamp/message/gitBranch)" >&2
                echo -e "${DIM}  file: $(basename "$newest_jsonl")${RESET}" >&2
                warnings=$((warnings + 1))
            fi
        fi
    fi

    # 5. sessions-index.json canary: warn if it comes BACK to life
    local revived_index
    revived_index=$(find "$projects_dir" -name "sessions-index.json" -mtime -7 -print -quit 2>/dev/null)
    if [[ -n "$revived_index" ]]; then
        echo -e "${BOLD}⚠ DIAG:${RESET} sessions-index.json was modified in the last 7 days — Claude may have revived it" >&2
        echo -e "${DIM}  file: $revived_index${RESET}" >&2
        warnings=$((warnings + 1))
    fi

    # 6. history.jsonl canary: check for sessionId field (added ~Feb 2026)
    if [[ -f "$history_file" ]]; then
        local has_session_id
        has_session_id=$(super -f line -c "tail 1 | values has(sessionId)" "$history_file" 2>/dev/null) || true
        if [[ "$has_session_id" != "true" ]]; then
            echo -e "${BOLD}⚠ DIAG:${RESET} history.jsonl latest entry missing sessionId field" >&2
            warnings=$((warnings + 1))
        fi
    fi

    if [[ $warnings -eq 0 ]]; then
        echo -e "${DIM}diag: ok${RESET}" >&2
    fi

    return 0
}

function all() {
    local days="${1:-7}"

    diag

    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  YOU ARE HERE (last ${days} days)${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo

    standup
    worktrees
    open_prs
    cloud_sessions
    conversations "$days"
}

function standup() {
  local -r duration="${1:-30h}"

  if [[ -n "$standup_script" && -x "$standup_script" ]]; then
    "$standup_script" standup "$duration"
  fi
}

function cloud_sessions() {
    local now
    now=$(date +%s)

    echo -e "${CYAN}${BOLD}☁️  CLOUD SESSIONS${RESET}  ${DIM}(claude.ai branches)${RESET}"
    echo -e "${DIM}───────────────────────────────────────────────────────────────${RESET}"

    if ! gh_available; then
        echo -e "${DIM}(gh CLI not available or not authenticated - run 'gh auth login')${RESET}"
        echo
        return
    fi

    local data
    data=$(collect_cloud_branches)

    if [[ -z "$data" ]]; then
        echo -e "${DIM}(no Claude branches found)${RESET}"
        echo
        return
    fi

    echo "$data" | super -f json -c "
      put age_days := ((${now} - commit_ts) / 86400)::int64
      | put location := is_remote ? 'remote' : 'local'
      | put has_pr := !is(pr_number, <null>)
      | put pr := has_pr ? f'PR #{pr_number}' : '-'
      | put age_str := age_days == 0 ? 'today' : f'{age_days}d'
      | sort age_days
      | cut repo, branch, location, age_str, pr
    " - | mlr --j2p --barred cat

    echo
}

function open_prs() {
    echo -e "${CYAN}${BOLD}📋 OPEN PRs${RESET}"
    echo -e "${DIM}───────────────────────────────────────────────────────────────${RESET}"

    if [[ ${#github_orgs[@]} -eq 0 ]]; then
        echo -e "${DIM}(no github_orgs configured in ${wc_config:-~/.config/work-context.sup})${RESET}"
        echo
        return
    fi

    if ! gh_available; then
        echo -e "${DIM}(gh CLI not available or not authenticated - run 'gh auth login')${RESET}"
        echo
        return
    fi

    local data
    data=$(collect_open_prs)

    if [[ -z "$data" || "$data" == "[]" ]]; then
        echo -e "${DIM}(no open PRs found)${RESET}"
        echo
        return
    fi

    echo "$data" | super -f json -c "
      unnest this
      | put repo := headRepository.name
      | put review := has(reviewDecision) and reviewDecision != '' ? reviewDecision : 'PENDING'
      | put draft := isDraft ? 'draft' : ''
      | put pr := f'#{number}'
      | put title_short := title[0:50]
      | sort repo, -updatedAt
      | cut repo, pr, title_short, review, draft
    " - | mlr --j2p --barred cat

    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Machine-readable output for AI consumption
# ─────────────────────────────────────────────────────────────────────────────

function worktrees_json() {
    local now show_all=false
    now=$(date +%s)

    for arg in "$@"; do
        case "$arg" in
            --all) show_all=true ;;
        esac
    done

    local filter=""
    [[ "$show_all" == "false" ]] && filter="| where not grep('^staging', branch)"

    collect_worktree_data | super -f json -c "
      put age_days := ((${now} - commit_ts) / 86400)::int64
      ${filter}
      | sort age_days
    " -
}

function conversations_json() {
    local days="${1:-7}"
    local projects_dir="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

    [[ -d "$projects_dir" ]] || return

    # Calculate cutoff as local midnight N days ago, expressed in UTC
    # days=0 means "today", days=1 means "today+yesterday", etc.
    # Use local time to get the right calendar date, then convert to UTC
    local days_back=$days
    local local_date
    local_date=$(date -v-${days_back}d +"%Y-%m-%d" 2>/dev/null || \
                 date -d "${days_back} days ago" +"%Y-%m-%d")
    local utc_midnight_hour=$((0 - tz_offset_hours))
    local cutoff="${local_date}T$(printf '%02d' $utc_midnight_hour):00"

    # Each conversation as separate record with full metadata
    # Convert UTC to local time using tz_offset_hours
    collect_session_data "$days" | super -f json -c "
      where created >= '${cutoff}'
      | put local_time:=created::time + '${tz_offset_hours}h'::duration
      | put date:=strftime('%Y-%m-%d', local_time)
      | put time:=strftime('%H:%M', local_time)
      | put first_prompt:=replace(firstPrompt[0:300], '\\n', ' ')
      | put conv_summary:=replace(has(summary) ? summary : '', '\\n', ' ')
      | sort -created
      | cut sessionId, date, time, project, messageCount, gitBranch, first_prompt, conv_summary
    " - 2>/dev/null
}

function cloud_sessions_json() {
    if ! gh_available; then
        return
    fi

    local now
    now=$(date +%s)

    collect_cloud_branches | super -f json -c "
      put age_days := ((${now} - commit_ts) / 86400)::int64
      | sort age_days
    " -
}

function open_prs_json() {
    local data
    data=$(collect_open_prs)

    if [[ -z "$data" || "$data" == "[]" ]]; then
        return
    fi

    echo "$data" | super -f json -c "
      unnest this
      | put repo := headRepository.name
      | sort repo, -updatedAt
      | cut number, title, headRefName, url, reviewDecision, isDraft, repo, createdAt, updatedAt
    " -
}

function data() {
    local days="${1:-7}"

    diag

    # Collect data into SUP format
    local worktrees_data conversations_data standup_data cloud_sessions_data open_prs_data

    worktrees_data=$(worktrees_json | super -s -c "collect(this)" -)
    cloud_sessions_data=$(cloud_sessions_json | super -s -c "collect(this)" -)
    open_prs_data=$(open_prs_json | super -s -c "collect(this)" -)
    conversations_data=$(conversations_json "$days" | super -s -c "collect(this)" -)
    standup_data=$(standup "30h" 2>/dev/null | super -i line -s -c "collect(this) | join(this, '\n')" -)

    # Build output with super
    super -f json -c "values {
        yah_data: {
            worktrees: ${worktrees_data:-[]},
            cloud_sessions: ${cloud_sessions_data:-[]},
            open_prs: ${open_prs_data:-[]},
            conversations: ${conversations_data:-[]},
            standup: ${standup_data:-''}
        }
    }"
}

function config() {
    local config_display="${wc_config:-~/.config/work-context.sup}"
    echo -e "${CYAN}${BOLD}Work Context Configuration${RESET}"
    echo -e "${DIM}Config file: ${config_display}${RESET}"
    echo

    if [[ -z "$wc_config" ]] || [[ ! -f "$wc_config" ]]; then
        echo -e "${DIM}No config file found. Using defaults.${RESET}"
        echo
    fi

    echo "Repos:"
    for repo in "${repos_to_check[@]}"; do
        if [[ -d "$repo" ]]; then
            echo "  $repo"
        else
            echo -e "  $repo ${DIM}(not found)${RESET}"
        fi
    done

    echo
    echo "GitHub orgs:"
    if [[ ${#github_orgs[@]} -gt 0 ]]; then
        for org in "${github_orgs[@]}"; do
            echo "  $org"
        done
    else
        echo -e "  ${DIM}(none configured)${RESET}"
    fi

    echo
    echo -e "Standup script: ${standup_script:-${DIM}(none)${RESET}}"
    echo "Timezone offset: UTC${tz_offset_hours}"

    if [[ -z "$wc_config" ]] || [[ ! -f "$wc_config" ]]; then
        echo
        echo -e "${DIM}Create ~/.config/work-context.sup (SuperJSON) to customize.${RESET}"
    fi
}

function usage() {
    cat <<-EOF
	Usage: work-context <command> [args]

	Commands:
	  all [days]            Show worktrees, PRs, cloud sessions, and conversations (default: 7)
	  worktrees             Show git worktree status only
	  worktrees_json --all  JSON worktree list including staging branches
	  open_prs              Show open PRs for configured github_orgs
	  cloud_sessions        Show Claude web session branches and PRs
	  conversations [days]  Show Claude conversations only (default: 7)
	  search <term> [days]  Search conversation prompts (default: 30)
	  data [days]           Output JSON for AI consumption (default: 7)
	  diag                  Check Claude internals assumptions (canary)
	  config                Show current configuration
	  usage                 Show this help

	Days (zero-based, from local midnight):
	  0 = today only
	  1 = today + yesterday
	  2 = today + 2 days back
	  etc.

	Configuration:
	  Settings in ~/.config/work-context.sup (SuperJSON format).
	  Run 'work-context config' to see current settings.

	Cloud Sessions:
	  Tracks branches matching Claude web session patterns:
	  - claude/* branches (e.g., claude/feature-xyz)
	  - Branches ending with 13-digit timestamps
	  Requires gh CLI to be installed and authenticated.

	Examples:
	  work-context                   # default: all 7
	  work-context conversations 0   # today only
	  work-context conversations 1   # today + yesterday
	  work-context all 2             # today + 2 days back
	  work-context search mcp
	  work-context search "fivetran" 7
	  work-context data 1            # JSON output for skills
	EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

# Only run main when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        -h|--help)
            usage
            ;;
        "")
            all
            ;;
        *)
            "$@"
            ;;
    esac
fi
