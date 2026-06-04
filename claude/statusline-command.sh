#!/usr/bin/env bash
# Claude Code status line — Pure-style prompt
# Input: JSON via stdin from Claude Code

input=$(cat)

user=$(whoami)
host=$(hostname -s)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# Shorten home directory to ~
home="$HOME"
display_dir="${cwd/#$home/\~}"

# Git branch (skip optional locks to avoid stalling)
branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)
fi

# Context window
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_part=""
if [ -n "$used" ]; then
  ctx_int=$(printf '%.0f' "$used")
  ctx_part=" ctx:${ctx_int}%"
fi

# Model display name (short)
model=$(echo "$input" | jq -r '.model.display_name // empty')

# Usage quota (Claude.ai Pro/Max only; absent on other plans and before the
# first API response of a session). Claude's real limits are a 5-hour rolling
# window and a 7-day weekly window — there is no "daily" limit.
fivehr=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
sevenday=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Build "5h:NN% 7d:NN%" — dim under 70%, yellow 70–89%, red 90%+.
quota=""
add_quota() {  # $1=raw percentage  $2=label
  [ -z "$1" ] && return
  local p color sep=""
  p=$(printf '%.0f' "$1")
  if   [ "$p" -ge 90 ]; then color='0;31'
  elif [ "$p" -ge 70 ]; then color='0;33'
  else color='2'
  fi
  [ -n "$quota" ] && sep=" "
  quota="${quota}${sep}$(printf '\033[%sm%s:%s%%\033[0m' "$color" "$2" "$p")"
}
add_quota "$fivehr"   '5h'
add_quota "$sevenday" '7d'

# Assemble one line: user@host  dir  branch  |  model  ctx  5h  7d
# ANSI: bold cyan for user@host, normal for dir, magenta for branch, dim for rest
printf '\033[0;36m%s@%s\033[0m  \033[0;1m%s\033[0m' "$user" "$host" "$display_dir"
[ -n "$branch" ] && printf '  \033[0;35m%s\033[0m' "$branch"
printf '  \033[2m%s%s\033[0m' "$model" "$ctx_part"
[ -n "$quota" ] && printf ' %s' "$quota"
exit 0
