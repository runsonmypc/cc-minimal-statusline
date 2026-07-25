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
# Effort level (nested: "effort":{"level":"high"}) - absent when the model
# doesn't support the effort parameter, in which case it's simply not shown
effort=$(echo "$json" | grep -o '"effort":{[^}]*}' | sed -n 's/.*"level":"\([^"]*\)".*/\1/p' | head -1)
# Extract context_window.used_percentage specifically (not rate_limits.*.used_percentage)
# First extract the context_window block (with nested current_usage), then grab used_percentage from it
used_pct=$(echo "$json" | grep -o '"context_window":{[^{]*{[^}]*}[^}]*}' | grep -o '"used_percentage":[0-9]*' | head -1 | grep -o '[0-9]*')
lines_added=$(get_number_value "total_lines_added")
lines_removed=$(get_number_value "total_lines_removed")
current_dir=$(get_string_value "current_dir")
session_id=$(get_string_value "session_id")
transcript_path=$(get_string_value "transcript_path")

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

# Detect ultracode (xhigh effort plus standing workflow orchestration).
# Claude Code reports it as plain "xhigh" in the status line JSON, so read the
# session transcript instead. Two signals, most recent one wins:
#   1. /effort's own output, written the moment you toggle:
#      "content":"<local-command-stdout>Set effort level to ultracode ...
#   2. the reminder attachments, written on the first prompt after a toggle:
#      "attachment":{"type":"ultra_effort_enter"|"ultra_effort_exit"...
# Signal 1 keeps the indicator in sync immediately; signal 2 is authoritative
# and also covers ultracode enabled at launch via --settings. Both anchors
# include a leading unescaped quote, so the same text quoted inside a tool
# result (where JSON escapes it) can't trigger a false positive.
ULTRA_SIGNALS='"attachment":\{"type":"ultra_effort_(enter|exit)"|"content":"<local-command-stdout>(Set effort level to [a-z]+|Effort level set to auto)'
ultracode="false"
ultra_cache="/tmp/.claude-ultracode-${session_id:-$(basename "${transcript_path:-unknown}" .jsonl)}"

reverse_cat() {
    if command -v tac >/dev/null 2>&1; then
        tac "$1"
    else
        tail -r "$1"
    fi
}

# "true" if the matched signal means ultracode is on
classify_signal() {
    case "$1" in
        *ultra_effort_enter*) echo "true" ;;
        *"Set effort level to ultracode"*) echo "true" ;;
        *) echo "false" ;;
    esac
}

detect_ultracode() {
    # Ultracode always resolves to xhigh, so any other effort skips the scan
    [ "$effort" = "xhigh" ] || return
    [ -n "$transcript_path" ] && [ -f "$transcript_path" ] || return

    local size=$(wc -c < "$transcript_path" 2>/dev/null | tr -d ' ')
    [ -z "$size" ] && return

    local cached_size=0
    local cached_state="false"
    if [ -f "$ultra_cache" ]; then
        cached_size=$(head -1 "$ultra_cache" 2>/dev/null)
        cached_state=$(tail -1 "$ultra_cache" 2>/dev/null)
        case "$cached_size" in ''|*[!0-9]*) cached_size=0 ;; esac
        [ "$cached_state" = "true" ] || cached_state="false"
    fi

    local signal=""
    local state="$cached_state"
    if [ "$cached_size" -eq "$size" ]; then
        # Transcript untouched since the last check - reuse the verdict
        echo "$cached_state"
        return
    elif [ "$cached_size" -gt 0 ] && [ "$cached_size" -lt "$size" ]; then
        # Scan only what was appended. Rewind 4KB so an entry that was
        # half-written at the last check isn't missed.
        local from=$((cached_size - 4096))
        [ $from -lt 0 ] && from=0
        signal=$(tail -c "+$((from + 1))" "$transcript_path" 2>/dev/null \
                 | grep -oE "$ULTRA_SIGNALS" | tail -1)
    else
        # First run, or the transcript shrank - walk back from the end and stop
        # at the newest signal
        signal=$(reverse_cat "$transcript_path" 2>/dev/null \
                 | grep -m1 -oE "$ULTRA_SIGNALS")
        state="false"
    fi

    [ -n "$signal" ] && state=$(classify_signal "$signal")

    printf '%s\n%s\n' "$size" "$state" > "$ultra_cache" 2>/dev/null
    echo "$state"
}

ultracode=$(detect_ultracode)
[ "$ultracode" = "true" ] || ultracode="false"

# Show raw used_percentage from Claude Code as-is

# ANSI 256 color codes (as literal strings - interpreted only at final echo -e)
C_RESET='\033[0m'
C_DIM='\033[38;5;239m'        # Dim gray - version, separators
C_ORANGE='\033[38;2;230;113;78m'  # #E6714E - model
C_BLUE='\033[38;5;75m'        # Soft blue - directory
C_CYAN='\033[38;5;80m'        # Cyan - worktree flask
C_PURPLE='\033[38;5;141m'     # Purple - branch
C_GREEN='\033[38;5;108m'      # Muted green - lines added
C_RED='\033[38;5;167m'        # Muted red - lines removed
C_EFFORT='\033[38;5;245m'     # Muted gray - effort level
C_ULTRA='\033[38;2;175;135;255m'  # rgb(175,135,255) - Claude Code's ultracode violet

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

# Truncate a single name to 15 chars max
truncate_segment() {
    local seg="$1"
    local max=15
    if [ ${#seg} -gt $max ]; then
        echo "${seg:0:$max}…"
    else
        echo "$seg"
    fi
}

# Smart directory truncation
truncate_path() {
    local path="$1"
    # Remove home directory prefix
    path="${path/#$HOME/~}"

    # Split into segments
    IFS='/' read -ra segments <<< "$path"
    local count=${#segments[@]}

    # Truncate each individual segment (skip ~ prefix)
    for ((i=0; i<count; i++)); do
        if [ "${segments[$i]}" != "~" ] && [ -n "${segments[$i]}" ]; then
            segments[$i]=$(truncate_segment "${segments[$i]}")
        fi
    done

    # Rebuild path with truncated segments
    local rebuilt=""
    for ((i=0; i<count; i++)); do
        if [ $i -eq 0 ]; then
            rebuilt="${segments[$i]}"
        else
            rebuilt="${rebuilt}/${segments[$i]}"
        fi
    done

    if [ ${#rebuilt} -le 20 ]; then
        echo "$rebuilt"
        return
    fi

    # For ~ paths, need at least 4 segments to collapse middle (~ + 3 dirs)
    # For other paths, need at least 3 segments
    if [[ "$path" == ~* ]]; then
        [ $count -le 4 ] && { echo "$rebuilt"; return; }
    else
        [ $count -le 2 ] && { echo "$rebuilt"; return; }
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
    local bar_len=25
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

# Measure the visible (on-screen) width of a string by stripping the literal
# \033[...m color sequences and counting the remaining characters. In a UTF-8
# locale ${#s} counts code points, so box-drawing and Nerd Font mono glyphs
# each count as one cell - which matches how the target font renders them.
visible_width() {
    local s
    s=$(printf '%s' "$1" | sed -E 's/\\033\[[0-9;]*m//g')
    printf '%s' "${#s}"
}

# Build the status line
build_status() {
    local gap="  "   # spacing between segments (colors carry the separation)
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

    # --- Group 1: core (version + model + effort) - always stays on line 1 ---
    local version_display="v${version}"
    [ "$is_outdated" = "true" ] && version_display="${version_display} ${C_ORANGE}${ICON_UPDATE}"
    local core="${C_DIM}${version_display}${C_RESET}${gap}${C_ORANGE}${model}${C_RESET}"
    # Effort level to the right of the model, if the model supports it.
    # Ultracode reports as "xhigh", so it gets its own label and violet accent.
    if [ "$ultracode" = "true" ]; then
        core="${core} ${C_ULTRA}ultra${C_RESET}"
    elif [ -n "$effort" ]; then
        core="${core} ${C_EFFORT}${effort}${C_RESET}"
    fi

    # --- Group 2: loc (directory + branch + changed files) ---
    # Prepend cyan flask icon if in a worktree
    if [ -n "$worktree" ]; then
        path_display="${C_CYAN}${ICON_WORKTREE}${C_BLUE}${path_display}"
    fi
    local loc="${C_BLUE}${path_display}${C_RESET}"
    if [ -n "$branch" ]; then
        branch=$(truncate_segment "$branch")
        loc="${loc} ${C_PURPLE}${ICON_BRANCH}${branch}${C_RESET}"
    fi
    # Files and lines changed from git status (only if there are uncommitted changes)
    if [ "$git_files" != "0" ] || [ "$git_added" != "0" ] || [ "$git_removed" != "0" ]; then
        loc="${loc}${gap}${C_DIM}${git_files}${ICON_FILES}${C_RESET} ${C_GREEN}+${git_added}${C_DIM}/${C_RED}-${git_removed}${C_RESET}"
    fi

    # --- Group 3: ctx (context percentage + bar + autocompact indicator) ---
    local compact_indicator=""
    [ "$autocompact_enabled" = "true" ] && compact_indicator=" ${C_DIM}${ICON_COMPACT}"
    local ctx="${C_DIM}${used_pct}%${C_RESET} ${bar}${compact_indicator}${C_RESET}"

    # Progressively fold groups onto a second line as the terminal narrows.
    # Claude Code sets $COLUMNS to the terminal width; when it's unset (older
    # Claude Code) we keep the original single-line behavior. Priority:
    #   wide    ->  core  loc  ctx          (everything on one line)
    #   medium  ->  core  loc               (context bar drops to line 2)
    #               ctx
    #   narrow  ->  core                     (path + branch drop down too)
    #               loc  ctx
    local join="${gap}"
    local cols="${COLUMNS:-0}"
    case "$cols" in ''|*[!0-9]*) cols=0 ;; esac

    # Single echo -e per line interprets ALL escape sequences
    local line_all="${core}${join}${loc}${join}${ctx}"
    if [ "$cols" -le 0 ] || [ "$(visible_width "$line_all")" -le "$cols" ]; then
        echo -e "$line_all"
    elif [ "$(visible_width "${core}${join}${loc}")" -le "$cols" ]; then
        echo -e "${core}${join}${loc}"
        echo -e "$ctx"
    else
        echo -e "$core"
        echo -e "${loc}${join}${ctx}"
    fi
}

# Output the status line
build_status
