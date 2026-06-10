#!/usr/bin/env bash
# tests/claude-tmux-state.test.sh — unit tests for bin/claude-tmux-state.
# Spins up a private tmux server, routes the helper's bare `tmux` to it via a
# PATH shim, drives hook events, and asserts the resulting window options.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/bin/claude-tmux-state"
SOCK="claude-state-test-$$"
SHIM="$(mktemp -d)"
REAL_TMUX="$(command -v tmux)"

cleanup() { "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SHIM"; }
trap cleanup EXIT

# shim so the helper's bare `tmux` talks to our throwaway server
cat > "$SHIM/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCK" "\$@"
EOF
chmod +x "$SHIM/tmux"

"$REAL_TMUX" -L "$SOCK" new-session -d -s t -x 80 -y 24
PANE="$("$REAL_TMUX" -L "$SOCK" display-message -p -t t '#{pane_id}')"

pass=0; fail=0
run()   { PATH="$SHIM:$PATH" TMUX=fake TMUX_PANE="$PANE" bash "$SCRIPT" "$1"; }
opt()   { "$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$PANE" "$1"; }
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf 'FAIL: %s — expected [%s], got [%s]\n' "$1" "$2" "$3"; fi
}

# --- lifecycle basics ---
run SessionStart
check "SessionStart state" idle "$(opt @claude_state)"
check "SessionStart count" 0 "$(opt @claude_subagents)"

run UserPromptSubmit
check "UserPromptSubmit state" working "$(opt @claude_state)"

run Notification
check "Notification state" waiting "$(opt @claude_state)"

run PreToolUse
check "PreToolUse clears waiting" working "$(opt @claude_state)"

run Stop
check "Stop state" done "$(opt @claude_state)"
check "Stop count" 0 "$(opt @claude_subagents)"

# --- subagent counter & precedence ---
run SubagentStart
check "SubagentStart state" subagent "$(opt @claude_state)"
check "SubagentStart count" 1 "$(opt @claude_subagents)"

run SubagentStart
check "nested count" 2 "$(opt @claude_subagents)"

run PreToolUse
check "PreToolUse keeps subagent" subagent "$(opt @claude_state)"

run SubagentStop
check "one stop -> still subagent" subagent "$(opt @claude_state)"
check "count decremented" 1 "$(opt @claude_subagents)"

run SubagentStop
check "last stop -> working" working "$(opt @claude_state)"
check "count zero" 0 "$(opt @claude_subagents)"

run SubagentStop
check "stop floors at 0" 0 "$(opt @claude_subagents)"

# --- counter resets on turn boundaries ---
run SubagentStart; run SubagentStart
run Stop
check "Stop resets counter" 0 "$(opt @claude_subagents)"
run SubagentStart
run UserPromptSubmit
check "UserPromptSubmit resets counter" 0 "$(opt @claude_subagents)"

# --- late SubagentStop after the turn ended must not resurrect "working" ---
run Stop
run SubagentStop
check "late SubagentStop keeps done" done "$(opt @claude_state)"

# --- StopFailure (API-error turn end) counts as a finished turn ---
run UserPromptSubmit
run StopFailure
check "StopFailure state" done "$(opt @claude_state)"
check "StopFailure count" 0 "$(opt @claude_subagents)"

# --- Idle (Notification idle_prompt): quiets a stale busy state only ---
run UserPromptSubmit
run Idle
check "Idle demotes stuck working" idle "$(opt @claude_state)"
run UserPromptSubmit; run SubagentStart
run Idle
check "Idle demotes stuck subagent" idle "$(opt @claude_state)"
run UserPromptSubmit; run Stop
run Idle
check "Idle keeps done" done "$(opt @claude_state)"
run Notification
run Idle
check "Idle keeps waiting" waiting "$(opt @claude_state)"

# --- compaction + teardown ---
run PreCompact
check "PreCompact state" compacting "$(opt @claude_state)"

run SessionEnd
check "SessionEnd unsets state" "" "$(opt @claude_state)"
check "SessionEnd unsets count" "" "$(opt @claude_subagents)"

# --- unknown event is a no-op ---
run UserPromptSubmit
run BogusEvent
check "unknown event leaves state" working "$(opt @claude_state)"

# --- @claude_tab: pre-styled glyph fragment consumed by window-status-format ---
run UserPromptSubmit
check "working tab" ' #[fg=#00d7d7]#{@claude_spinner}#[default] ' "$(opt @claude_tab)"

run SubagentStart
check "subagent tab" ' #[fg=#af5fff]#[default] ' "$(opt @claude_tab)"

run SubagentStop
check "subagent stop -> working tab" ' #[fg=#00d7d7]#{@claude_spinner}#[default] ' "$(opt @claude_tab)"

run Notification
check "waiting tab (unstyled, inherits orange fill)" '  ' "$(opt @claude_tab)"

run PreCompact
check "compacting tab" ' #[fg=#8a8a8a]#[default] ' "$(opt @claude_tab)"

run Stop
check "done tab" ' #[fg=#00d700]#[default] ' "$(opt @claude_tab)"

run SessionStart
check "idle tab is empty" '' "$(opt @claude_tab)"

# --- @claude_pane: records the owning pane so tmux hooks can clear dead state ---
run UserPromptSubmit
check "claude pane recorded" "$PANE" "$(opt @claude_pane)"

run SessionEnd
check "SessionEnd unsets tab" '' "$(opt @claude_tab)"
check "SessionEnd unsets pane" '' "$(opt @claude_pane)"

# --- gc: drops state only for windows whose recorded claude pane is gone ---
run UserPromptSubmit   # live window: state working, @claude_pane = $PANE (alive)
W2="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_state working
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_tab 'X '
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_pane '%999'
PATH="$SHIM:$PATH" TMUX=fake bash "$SCRIPT" gc
check "gc clears dead-pane window state" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W2" @claude_state)"
check "gc clears dead-pane window tab" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W2" @claude_tab)"
check "gc keeps live-pane window state" working "$(opt @claude_state)"
"$REAL_TMUX" -L "$SOCK" kill-window -t "$W2"

# --- animator: a detached loop cycles @claude_spinner while a window works ---
gopt() { "$REAL_TMUX" -L "$SOCK" show-options -gqv "$1"; }

run UserPromptSubmit
sp=''
for i in $(seq 1 40); do sp=$(gopt @claude_spinner); [ -n "$sp" ] && break; sleep 0.1; done
case "$sp" in ⣾|⣽|⣻|⢿|⡿|⣟|⣯|⣷) frame_ok=1 ;; *) frame_ok=0 ;; esac
check "animator sets a spinner frame" 1 "$frame_ok"

run Stop
cleared=0
for i in $(seq 1 40); do [ -z "$(gopt @claude_spinner_pid)" ] && { cleared=1; break; }; sleep 0.1; done
check "animator exits once nothing is working" 1 "$cleared"

# --- outside tmux: no error, exit 0 ---
TMUX= TMUX_PANE= bash "$SCRIPT" Stop; rc=$?
check "no-tmux exit code" 0 "$rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
