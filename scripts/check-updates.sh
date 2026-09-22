#!/bin/bash
# Fetch latest claude-code version from npm registry and cache it
# Designed to run in the background (e.g., via launchd or cron) every 5 minutes

cache_file="/tmp/.claude-code-latest-version"
lock_dir="/tmp/.claude-code-version.lock"

# Atomic lock to prevent overlapping runs
if ! mkdir "$lock_dir" 2>/dev/null; then
    now=$(date +%s)
    lock_age=$(( now - $(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo "$now") ))
    if [ $lock_age -gt 60 ]; then
        rmdir "$lock_dir" 2>/dev/null
        mkdir "$lock_dir" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

latest=""
# Fast HTTP fetch via curl with hard 5s timeout
if command -v curl &>/dev/null; then
    latest=$(curl -s --max-time 5 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

# Fallback to npm show if curl failed or returned empty
if [ -z "$latest" ] && command -v npm &>/dev/null; then
    latest=$(npm show @anthropic-ai/claude-code version 2>/dev/null | head -1)
fi

if [ -n "$latest" ]; then
    tmp_cache="${cache_file}.tmp.$$"
    echo "$(date +%s)" > "$tmp_cache"
    echo "$latest" >> "$tmp_cache"
    mv "$tmp_cache" "$cache_file"
fi
