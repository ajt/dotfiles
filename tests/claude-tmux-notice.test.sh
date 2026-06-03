#!/usr/bin/env bash
# Tests for bin/claude-tmux-notice.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

CLAUDE_TMUX_NOTICE_SOURCED=1 . "$here/../bin/claude-tmux-notice"

# ---- _should_act guard -----------------------------------------------------
export TMUX=/tmp/fake-tmux-socket
# manual window: no @wt_num, no @wt_title -> act
tmux() { case "$*" in *@wt_num*) printf '' ;; *@wt_title*) printf '' ;; esac; }
assert_ok _should_act @1 "manual window should act"
# issue window: @wt_num set -> skip
tmux() { case "$*" in *@wt_num*) printf '42\n' ;; *@wt_title*) printf '' ;; esac; }
assert_fail _should_act @1 "issue window (@wt_num) should skip"
# already labelled: @wt_title set -> skip
tmux() { case "$*" in *@wt_num*) printf '' ;; *@wt_title*) printf 'Do a thing\n' ;; esac; }
assert_fail _should_act @1 "labelled window (@wt_title) should skip"
# not in tmux -> skip
( unset TMUX; assert_fail _should_act @1 "no TMUX should skip" ) \
  || fail "subshell: no TMUX should skip"

pass
