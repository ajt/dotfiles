#!/usr/bin/env bash
# Tests for the `refresh` subcommand of bin/tmux-worktree-notice.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

# Source the script as a library (guard keeps main() from running).
TMUX_WORKTREE_NOTICE_SOURCED=1 . "$here/../bin/tmux-worktree-notice"

# --- refresh signals the banner pane's render pid with SIGWINCH -------------
KILLED=""
kill() { KILLED="$*"; }          # capture instead of really signalling
tmux() {                         # banner-present fake
  case "$*" in
    *"display-message -p"*window_id*) printf '@7\n' ;;
    *"display-message -p"*pane_pid*)  printf '4242\n' ;;
    *"list-panes"*)                   printf '%%9 1\n' ;;  # pane %9 has @wt_banner=1
  esac
}
refresh @7
assert_eq "$KILLED" "-WINCH 4242" "refresh signals render pid with WINCH"

# --- refresh is a no-op when there is no banner pane ------------------------
KILLED=""
tmux() {
  case "$*" in
    *"display-message -p"*window_id*) printf '@7\n' ;;
    *"list-panes"*)                   printf '%%9 0\n' ;;  # nothing flagged
  esac
}
assert_ok refresh @7
assert_empty "$KILLED" "refresh does not signal without a banner pane"

pass
