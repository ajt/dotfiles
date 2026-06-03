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

# ---- _normalize_title ------------------------------------------------------
assert_eq "$(_normalize_title '  Fix the bug  ')" "Fix the bug" "trims whitespace"
assert_eq "$(_normalize_title $'Line one\nLine two')" "Line one Line two" "flattens newlines"
assert_eq "$(_normalize_title '"Quoted label"')" "Quoted label" "strips surrounding quotes"
assert_eq "$(_normalize_title 'short label')" "short label" "short titles unchanged"
long_out=$(_normalize_title "$(printf 'a%.0s' {1..60})")
assert_contains "$long_out" "…" "long titles get an ellipsis"

# ---- _extract_summary ------------------------------------------------------
assert_eq "$(_extract_summary '{"content":[{"type":"text","text":"Fix flaky test"}]}')" "Fix flaky test" "extracts content text"
assert_empty "$(_extract_summary '{"error":{"type":"overloaded"}}')" "no text on error response"
assert_empty "$(_extract_summary 'not json at all')" "no text on garbage"

# ---- _fallback_title -------------------------------------------------------
assert_eq "$(_fallback_title $'Please refactor the parser\nand add tests')" "Please refactor the parser" "fallback uses first line"

# ---- _api_summary ----------------------------------------------------------
( unset ANTHROPIC_API_KEY; assert_fail _api_summary "do something" "no key short-circuits" ) \
  || fail "subshell: no key should short-circuit"
export ANTHROPIC_API_KEY=test-key
curl() { printf '{"content":[{"type":"text","text":" Add refresh subcommand "}]}'; }
assert_eq "$(_api_summary 'add the refresh subcommand')" "Add refresh subcommand" "api summary normalized"
curl() { return 7; }
assert_fail _api_summary "anything" "curl failure propagates"

# ---- _branch_for -----------------------------------------------------------
assert_empty "$(_branch_for '')" "empty cwd yields empty branch (no fall-through)"
assert_eq "$(_branch_for /no/such/dir/myproj)" "myproj" "non-repo cwd falls back to basename"
git() { printf 'feature/x\n'; }
assert_eq "$(_branch_for /anywhere)" "feature/x" "git repo yields the branch name"
unset -f git

# ---- _normalize_title: interior apostrophe survives quote stripping --------
assert_eq "$(_normalize_title $'"it\'s done"')" "it's done" "keeps interior apostrophe"

# ---- _api_summary: an HTTP error JSON body is treated as failure -----------
curl() { printf '{"type":"error","error":{"type":"authentication_error"}}'; }
assert_fail _api_summary "anything" "http error body propagates as failure"

# ---- hook prints NOTHING to stdout and stamps placeholder + branch ---------
# hook runs via here-string + redirect so it stays in THIS shell and the tmux()
# fake's writes to TMUX_SETOPTS survive (a pipe / $() would subshell it away).
export TMUX_PANE=%3
_window_for_pane() { printf '@5\n'; }
_should_act() { return 0; }
_dispatch_summary() { :; }                   # don't really fork/API in the test
git() { printf 'feature/x\n'; }
tmux-worktree-notice() { :; }                # stub the renderer call
TMUX_SETOPTS=""
tmux() { case "$*" in *set-option*) TMUX_SETOPTS="$TMUX_SETOPTS|$*" ;; *) : ;; esac; }
hookout=$(mktemp)
hook >"$hookout" 2>/dev/null <<<'{"prompt":"fix the thing","cwd":"/repo"}'
assert_empty "$(cat "$hookout")" "hook must print nothing to stdout"
assert_contains "$TMUX_SETOPTS" "@wt_title summarizing…" "hook stamps the placeholder title"
assert_contains "$TMUX_SETOPTS" "@wt_branch feature/x" "hook stamps the branch"
rm -f "$hookout"

# ---- hook is silent and stamps nothing when the guard says no --------------
_should_act() { return 1; }
TMUX_SETOPTS=""
hookout=$(mktemp)
hook >"$hookout" 2>/dev/null <<<'{"prompt":"fix the thing","cwd":"/repo"}'
assert_empty "$(cat "$hookout")" "skipped hook prints nothing"
assert_empty "$TMUX_SETOPTS" "skipped hook stamps nothing"
rm -f "$hookout"

# ---- summarize sets @wt_title and refreshes --------------------------------
export ANTHROPIC_API_KEY=test-key
curl() { printf '{"content":[{"type":"text","text":"Wire up the hook"}]}'; }
REFRESHED=""
tmux-worktree-notice() { REFRESHED="$*"; }
TMUX_SETOPTS=""
tmux() { case "$*" in *set-option*) TMUX_SETOPTS="$*" ;; *) : ;; esac; }
pf=$(mktemp); printf 'wire up the user prompt hook' > "$pf"
summarize @5 /repo "$pf"
assert_contains "$TMUX_SETOPTS" "@wt_title Wire up the hook" "summarize sets the title"
assert_eq "$REFRESHED" "refresh @5" "summarize refreshes the window"
assert_fail test -e "$pf"

pass
