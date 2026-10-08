#!/usr/bin/env bash
# Check UTC conversion and the opt-in branches in the real tmux configuration.
set -eu
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

sandbox=$(mktemp -d)
sock="$sandbox/tmux.sock"
cleanup() {
  tmux -S "$sock" kill-server 2>/dev/null || true
  rm -rf "$sandbox"
}
trap cleanup EXIT

# Pin date's input, but use the platform's real timezone conversion. This
# instant is New Year's Eve in New York and New Year's Day in UTC and Tokyo.
export REAL_DATE
REAL_DATE=$(command -v date)
mkdir -p "$sandbox/bin"
if "$REAL_DATE" -u -r 0 +%s >/dev/null 2>&1; then
  cat >"$sandbox/bin/date" <<'EOF'
#!/bin/sh
exec "$REAL_DATE" -r 1767227400 "$@"
EOF
else
  cat >"$sandbox/bin/date" <<'EOF'
#!/bin/sh
exec "$REAL_DATE" -d @1767227400 "$@"
EOF
fi
chmod +x "$sandbox/bin/date"

assert_eq "$(TZ=EST5EDT LC_ALL=C "$sandbox/bin/date" '+%d %b %H:%M')" \
  '31 Dec 19:30' 'fixture crosses the local/UTC date and year boundary'
for zone in EST5EDT JST-9 UTC0; do
  actual=$(TZ="$zone" LC_ALL=C PATH="$sandbox/bin:$PATH" \
    sh "$here/../bin/tmux-status.sh" utc)
  assert_eq "$actual" 'UTC 01 Jan 00:30' "UTC is independent of local zone $zone"
done

command -v tmux >/dev/null 2>&1 || { echo 'skip: tmux configuration checks (tmux not installed)'; pass; exit 0; }

# A disposable server and home avoid loading user settings or running personal
# shell startup files. display-message does not render asynchronous #() jobs;
# substitute the independently verified UTC result to test the format branches.
env -u TMUX -u TMUX_SHOW_UTC HOME="$sandbox" TZ=UTC0 \
  tmux -S "$sock" -f "$here/../.tmux.conf" new-session -d -s utc-test 'sleep 300'
status=$(tmux -S "$sock" show-options -gv status-right)
assert_contains "$status" '#(~/bin/tmux-status.sh utc)' 'status uses the UTC helper'
status=${status//'#(~/bin/tmux-status.sh utc)'/'UTC 01 Jan 00:30'}
# Stable labels preserve the date/time grouping without racing a minute or day
# boundary while tmux expands strftime tokens in display-message output.
status=${status//'%Z'/'LOCAL_ZONE'}
status=${status//'%d %b'/'LOCAL_DATE'}
status=${status//'%R'/'LOCAL_TIME'}
tmux -S "$sock" set-option -g status-right "$status"

clock_format() {
  tmux -S "$sock" display-message -p '#{E:status-right}'
}
assert_local_only() {
  local actual
  actual=$(clock_format)
  assert_contains "$actual" '| LOCAL_TIME | LOCAL_DATE ' "$1: preserves the existing local clock"
  case "$actual" in *UTC*) fail "$1: UTC must be hidden" ;; esac
}

assert_local_only 'unset by default'
tmux -S "$sock" set-environment -g TMUX_SHOW_UTC 1
assert_contains "$(clock_format)" '| LOCAL_ZONE LOCAL_DATE LOCAL_TIME | #[fg=#000000]#[bg=#00afff]#[bold] UTC 01 Jan 00:30 #[default] ' \
  'enabled: grouped timestamps, blue UTC block, and style reset before user/host'
for value in 0 false true invalid ''; do
  tmux -S "$sock" set-environment -g TMUX_SHOW_UTC "$value"
  assert_local_only "value '$value'"
done
tmux -S "$sock" set-environment -gu TMUX_SHOW_UTC
assert_local_only 'removed after enabling'

pass
