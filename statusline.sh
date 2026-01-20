#!/bin/bash

# Claude Code Status Line - Sunset Minimal Design
# Reads JSON from stdin and outputs a formatted status line

# Read JSON from stdin
json=$(cat)

# Parse JSON fields - extract string value after a key
get_string_value() {
    echo "$json" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

get_number_value() {
    echo "$json" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1
}

# Extract fields
version=$(get_string_value "version")
model=$(get_string_value "display_name")
used_pct=$(get_number_value "used_percentage")
lines_added=$(get_number_value "total_lines_added")
lines_removed=$(get_number_value "total_lines_removed")
current_dir=$(get_string_value "current_dir")

# Fallback values
[ -z "$version" ] && version="?.?.?"
[ -z "$model" ] && model="Claude"
[ -z "$used_pct" ] && used_pct="0"
[ -z "$lines_added" ] && lines_added="0"
[ -z "$lines_removed" ] && lines_removed="0"
[ -z "$current_dir" ] && current_dir="$PWD"

# Check if we're on latest version (cached, background refresh)
is_outdated="false"
cache_file="/tmp/.claude-code-latest-version"
cache_max_age=3600  # 1 hour

check_latest_version() {
    local now=$(date +%s)
    local cached_version=""
    local cached_time=0

    # Read cache if it exists
    if [ -f "$cache_file" ]; then
        cached_time=$(head -1 "$cache_file" 2>/dev/null)
        cached_version=$(tail -1 "$cache_file" 2>/dev/null)
    fi

    # If cache is stale, trigger background refresh (non-blocking)
    if [ $((now - cached_time)) -gt $cache_max_age ] || [ -z "$cached_version" ]; then
        # Background fetch - writes to cache, doesn't block
        (npm show @anthropic-ai/claude-code version 2>/dev/null | {
            read latest
            if [ -n "$latest" ]; then
                echo "$(date +%s)" > "$cache_file"
                echo "$latest" >> "$cache_file"
            fi
        }) &>/dev/null &
    fi

    # Compare using cached version (may be stale, that's ok)
    if [ -n "$cached_version" ] && [ "$version" != "$cached_version" ]; then
        # Check if current < latest
        if [ "$(printf '%s\n' "$version" "$cached_version" | sort -V | head -1)" = "$version" ] && [ "$version" != "$cached_version" ]; then
            echo "true"
            return
        fi
    fi
    echo "false"
}

is_outdated=$(check_latest_version)

# Check if autocompact is enabled (default: true)
# Setting is "autoCompactEnabled" in ~/.claude.json
autocompact_enabled="true"
if [ -f ~/.claude.json ]; then
    # Check for "autoCompactEnabled": false (with flexible whitespace)
    if grep -q '"autoCompactEnabled"[[:space:]]*:[[:space:]]*false' ~/.claude.json 2>/dev/null; then
        autocompact_enabled="false"
    fi
fi

# Adjust for autocompact buffer (22.5% reserved = 77.5% usable)
# Only apply when autocompact is enabled
if [ "$autocompact_enabled" = "true" ] && [ "$used_pct" -gt 0 ] 2>/dev/null; then
    used_pct=$((used_pct * 100 / 77))
    [ "$used_pct" -gt 100 ] && used_pct=100
fi

# ANSI 256 color codes (as literal strings - interpreted only at final echo -e)
C_RESET='\033[0m'
C_DIM='\033[38;5;239m'        # Dim gray - version, separators
C_ORANGE='\033[38;2;230;113;78m'  # #E6714E - model
C_BLUE='\033[38;5;75m'        # Soft blue - directory
C_CYAN='\033[38;5;80m'        # Cyan - worktree flask
C_PURPLE='\033[38;5;141m'     # Purple - branch
C_GREEN='\033[38;5;108m'      # Muted green - lines added
C_RED='\033[38;5;167m'        # Muted red - lines removed

# Nerd Font icons (using printf for reliable UTF-8 output)
ICON_BRANCH=$(printf '\xee\x9c\xa5')      # U+E725 git branch
ICON_WORKTREE=$(printf '\xef\x83\x83')    # U+F0C3 flask
ICON_FILES=$(printf '\xef\x85\x9b')       # U+F15B file
ICON_UPDATE=$(printf '\xef\x81\xa2')      # U+F062 fa-arrow-up
ICON_COMPACT=$(printf '\xf3\xb0\x98\x95') # U+F0615 md-arrow_collapse
# Bar colors - 20-step gradient (every 5%)
# Green (0%) → Gold (50%) → Model color #C15F3C (75%) → Red (100%)
BAR_COLORS=(
    '\033[38;2;70;200;70m'    # 0-4%:   Green
    '\033[38;2;89;200;63m'    # 5-9%
    '\033[38;2;107;200;56m'   # 10-14%
    '\033[38;2;126;200;49m'   # 15-19%
    '\033[38;2;144;200;42m'   # 20-24%
    '\033[38;2;163;200;35m'   # 25-29%
    '\033[38;2;181;200;28m'   # 30-34%
    '\033[38;2;200;200;21m'   # 35-39%
    '\033[38;2;218;200;14m'   # 40-44%
    '\033[38;2;237;200;7m'    # 45-49%
    '\033[38;2;255;200;0m'    # 50-54%: Gold
    '\033[38;2;243;179;12m'   # 55-59%
    '\033[38;2;230;158;24m'   # 60-64%
    '\033[38;2;218;137;36m'   # 65-69%
    '\033[38;2;205;116;48m'   # 70-74%
    '\033[38;2;193;95;60m'    # 75-79%: Model color
    '\033[38;2;200;86;60m'    # 80-84%
    '\033[38;2;207;78;60m'    # 85-89%
    '\033[38;2;213;69;60m'    # 90-94%
    '\033[38;2;220;60;60m'    # 95-100%: Red
)

# Smart directory truncation
truncate_path() {
    local path="$1"
    # Remove home directory prefix
    path="${path/#$HOME/~}"

    if [ ${#path} -le 20 ]; then
        echo "$path"
        return
    fi

    # Split into segments
    IFS='/' read -ra segments <<< "$path"
    local count=${#segments[@]}

    # For ~ paths, need at least 4 segments to truncate (~ + 3 dirs)
    # For other paths, need at least 3 segments
    if [[ "$path" == ~* ]]; then
        [ $count -le 4 ] && { echo "$path"; return; }
    else
        [ $count -le 2 ] && { echo "$path"; return; }
    fi

    local last="${segments[$((count-1))]}"

    # For paths starting with ~, show ~/first/second/…/last
    if [[ "$path" == ~* ]]; then
        local dirs=()
        for ((i=0; i<count; i++)); do
            if [ -n "${segments[$i]}" ] && [ "${segments[$i]}" != "~" ]; then
                dirs+=("${segments[$i]}")
                [ ${#dirs[@]} -ge 2 ] && break
            fi
        done
        echo "~${dirs[0]}/${dirs[1]}/…/$last"
    else
        local first="${segments[0]}"
        [ -z "$first" ] && first="${segments[1]}"
        echo "$first/…/$last"
    fi
}

# Get git info (includes untracked files, unlike Claude Code's built-in footer)
get_git_info() {
    local dir="$1"
    [ -z "$dir" ] && return

    local branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && return

    # Check if we're in a worktree (not main working tree)
    local git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
    local worktree_name=""

    if [[ "$git_dir" == *".git/worktrees/"* ]]; then
        # Extract worktree name from path (git_dir is like /repo/.git/worktrees/wt-name)
        worktree_name=$(basename "$git_dir" 2>/dev/null)
    fi

    # Get current uncommitted changes (staged + unstaged)
    local diff_stat=$(git -C "$dir" diff --numstat HEAD 2>/dev/null | awk '{files++; add+=$1; del+=$2} END {print files"|"add"|"del}')
    local tracked_files="${diff_stat%%|*}"
    local rest="${diff_stat#*|}"
    local added="${rest%%|*}"
    local removed="${rest##*|}"
    [ -z "$tracked_files" ] && tracked_files="0"
    [ -z "$added" ] && added="0"
    [ -z "$removed" ] && removed="0"

    # Count untracked files and their lines
    local untracked_files=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)
    local untracked=0
    local untracked_lines=0
    if [ -n "$untracked_files" ]; then
        untracked=$(echo "$untracked_files" | wc -l | tr -d ' ')
        # Count lines in untracked files (all count as additions)
        untracked_lines=$(echo "$untracked_files" | while IFS= read -r f; do
            wc -l < "$dir/$f" 2>/dev/null
        done | awk '{sum+=$1} END {print sum+0}')
    fi
    local files=$((tracked_files + untracked))
    added=$((added + untracked_lines))

    echo "${branch}|${worktree_name}|${files}|${added}|${removed}"
}

# Generate progress bar (returns literal escape sequences, not interpreted)
generate_bar() {
    local pct=$1
    local bar_len=30
    local filled=$((bar_len * pct / 100))
    [ $filled -gt $bar_len ] && filled=$bar_len
    local empty=$((bar_len - filled))

    # Select color based on percentage (20 color stages, every 5%)
    local idx=$((pct / 5))
    [ $idx -gt 19 ] && idx=19
    local bar_color="${BAR_COLORS[$idx]}"

    # Build bar with literal escape sequences
    local bar=""
    if [ $filled -gt 0 ]; then
        bar="${bar_color}$(printf '━%.0s' $(seq 1 $filled))"
    fi
    if [ $empty -gt 0 ]; then
        bar="${bar}${C_DIM}$(printf '━%.0s' $(seq 1 $empty))"
    fi

    # Return literal string (no echo -e here!)
    printf '%s' "$bar"
}

# Build the status line
build_status() {
    local sep="${C_DIM}│${C_RESET}"
    local path_display=$(truncate_path "$current_dir")
    local git_info=$(get_git_info "$current_dir")
    local bar=$(generate_bar "$used_pct")

    # Parse git info (branch|worktree|files|added|removed)
    local branch=""
    local worktree=""
    local git_files="0"
    local git_added="0"
    local git_removed="0"
    if [ -n "$git_info" ]; then
        branch=$(echo "$git_info" | cut -d'|' -f1)
        worktree=$(echo "$git_info" | cut -d'|' -f2)
        git_files=$(echo "$git_info" | cut -d'|' -f3)
        git_added=$(echo "$git_info" | cut -d'|' -f4)
        git_removed=$(echo "$git_info" | cut -d'|' -f5)
        [ -z "$git_files" ] && git_files="0"
        [ -z "$git_added" ] && git_added="0"
        [ -z "$git_removed" ] && git_removed="0"
    fi

    # Version (with update icon if outdated)
    local version_display="v${version}"
    [ "$is_outdated" = "true" ] && version_display="${version_display} ${C_ORANGE}${ICON_UPDATE}"
    local out="${C_DIM}${version_display}${C_RESET}"

    # Model
    out="${out} ${sep} ${C_ORANGE}${model}${C_RESET}"

    # Directory (blue) - prepend cyan flask icon if in worktree
    if [ -n "$worktree" ]; then
        path_display="${C_CYAN}${ICON_WORKTREE}${C_BLUE}${path_display}"
    fi
    out="${out} ${sep} ${C_BLUE}${path_display}${C_RESET}"

    # Branch (purple)
    if [ -n "$branch" ]; then
        out="${out} ${C_PURPLE}${ICON_BRANCH}${branch}${C_RESET}"
    fi

    # Files and lines changed from git status (only show if there are uncommitted changes)
    if [ "$git_files" != "0" ] || [ "$git_added" != "0" ] || [ "$git_removed" != "0" ]; then
        out="${out} ${sep} ${C_DIM}${ICON_FILES} ${git_files}${C_RESET} ${C_GREEN}+${git_added}${C_DIM}/${C_RED}-${git_removed}${C_RESET}"
    fi

    # Context percentage and bar (with compress icon if autocompact enabled)
    local compact_indicator=""
    [ "$autocompact_enabled" = "true" ] && compact_indicator=" ${C_DIM}${ICON_COMPACT}"
    out="${out} ${sep} ${C_DIM}${used_pct}%${C_RESET} ${bar}${compact_indicator}${C_RESET}"

    # Single echo -e at the end interprets ALL escape sequences
    echo -e "$out"
}

# Output the status line
build_status
