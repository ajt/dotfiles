#!/usr/bin/env bash
# Regression test for the prefix-v binding in .tmux.conf.
#
# The current pane's path MUST reach the popup via display-popup's -d flag,
# which tmux format-expands at RUN time. tmux does NOT format-expand the
# display-popup *shell-command*, so passing '#{pane_current_path}' as an
# argument to the launcher sends it the literal string "#{pane_current_path}"
# (the bug that made the popup print `cannot enter #{pane_current_path}`).
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

command -v tmux >/dev/null 2>&1 || { echo "skip: tmux not installed"; exit 0; }

conf="$here/../.tmux.conf"

# Load the real config into a throwaway server on a private socket — this does
# NOT touch any live tmux session — and read back the parsed prefix-v binding.
sock="vlv-bind-$$"
tmux -L "$sock" -f "$conf" new-session -d -x 200 -y 50 2>/dev/null
binding=$(tmux -L "$sock" list-keys -T prefix 2>/dev/null | grep -- 'display-popup' || true)
tmux -L "$sock" kill-server 2>/dev/null || true

assert_contains "$binding" "display-popup" "prefix-v is bound to display-popup"
assert_contains "$binding" "-d " "the popup sets its working dir via -d"
assert_contains "$binding" "pane_current_path" "the -d dir is #{pane_current_path}"

# The launcher must NOT be handed a #{...} format (tmux won't expand it there).
# tmux renders the shell-command last in list-keys, so any "#{" appearing AFTER
# the script name means a format was wrongly passed as a launcher argument.
case "$binding" in
  *"tmux-valvonta-popup"*"#{"*) launcher_format="present" ;;
  *) launcher_format="absent" ;;
esac
assert_eq "$launcher_format" "absent" "launcher receives no #{...} argument"

pass
