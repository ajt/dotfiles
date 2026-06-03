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

pass
