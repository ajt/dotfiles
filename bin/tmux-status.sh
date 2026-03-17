#!/usr/bin/env sh
# Helper for tmux status bar — called via #(~/bin/tmux-status.sh <cmd>)

case "$1" in
  battery)
    batt=$(pmset -g batt 2>/dev/null | grep -Eo '\d+%' | head -1 | tr -d '%')
    [ -z "$batt" ] && exit 0
    charging=$(pmset -g batt 2>/dev/null | grep -q 'AC Power' && echo 1)
    icon="↓"
    [ "$charging" = "1" ] && icon="↑"
    # gradient colors per segment: red → orange → yellow → green
    colors="colour196 colour202 colour208 colour214 colour220 colour226 colour190 colour154 colour118 colour82"
    filled=$((batt / 10))
    bar=""
    i=1
    for c in $colors; do
      if [ $i -le $filled ]; then
        bar="${bar}#[fg=${c}]◼"
      else
        bar="${bar}#[fg=${c}]◻"
      fi
      i=$((i+1))
    done
    # set tmux user variables (styles are interpreted from variables, not #() output)
    tmux set -g @battery_bar "$bar" 2>/dev/null
    tmux set -g @battery_status "$icon" 2>/dev/null
    tmux set -g @battery_percentage "${batt}%" 2>/dev/null
    ;;
  uptime)
    if command -v sysctl >/dev/null 2>&1; then
      boot=$(sysctl -n kern.boottime 2>/dev/null | sed -E 's/^\{ sec = ([0-9]+).*/\1/')
      now=$(date +%s)
      secs=$((now - boot))
    else
      secs=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
    fi
    [ -z "$secs" ] && exit 0
    days=$((secs / 86400))
    hours=$(( (secs % 86400) / 3600 ))
    mins=$(( (secs % 3600) / 60 ))
    out="↑"
    [ "$days" -gt 0 ] && out="$out ${days}d"
    [ "$hours" -gt 0 ] && out="$out ${hours}h"
    out="$out ${mins}m"
    printf "%s" "$out"
    ;;
esac
