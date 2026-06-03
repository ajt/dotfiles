#!/usr/bin/env bash
# tests/test-claude-tmux-state.sh — unit tests for bin/claude-tmux-state.
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

# --- outside tmux: no error, exit 0 ---
TMUX= TMUX_PANE= bash "$SCRIPT" Stop; rc=$?
check "no-tmux exit code" 0 "$rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
