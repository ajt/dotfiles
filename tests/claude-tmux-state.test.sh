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
check "StopFailure state" error "$(opt @claude_state)"
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
run StopFailure
run Idle
check "Idle keeps error" error "$(opt @claude_state)"

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
check "subagent tab" ' #[fg=#af5fff]#{@claude_spinner2}#[default] ' "$(opt @claude_tab)"

run SubagentStop
check "subagent stop -> working tab" ' #[fg=#00d7d7]#{@claude_spinner}#[default] ' "$(opt @claude_tab)"

run Notification
check "waiting tab (unstyled, inherits orange fill)" '  ' "$(opt @claude_tab)"

run PreCompact
check "compacting tab" ' #[fg=#8a8a8a]#{@claude_spinner3}#[default] ' "$(opt @claude_tab)"

run Stop
check "done tab" ' #[fg=#00d700]#[default] ' "$(opt @claude_tab)"

run StopFailure
check "error tab (unstyled, inherits red fill)" '  ' "$(opt @claude_tab)"

run SessionStart
check "idle tab is empty" '' "$(opt @claude_tab)"

# --- @claude_glyph / @claude_color: the unstyled glyph + state color the
# --- current-window pill renders (fill = state color, content inherits fg)
run UserPromptSubmit
check "working glyph" ' #{@claude_spinner} ' "$(opt @claude_glyph)"
check "working color" '#00d7d7' "$(opt @claude_color)"
run SubagentStart
check "subagent glyph" ' #{@claude_spinner2} ' "$(opt @claude_glyph)"
check "subagent color" '#af5fff' "$(opt @claude_color)"
run PreCompact
check "compacting glyph" ' #{@claude_spinner3} ' "$(opt @claude_glyph)"
check "compacting color" '#8a8a8a' "$(opt @claude_color)"
run Notification
check "waiting glyph" '  ' "$(opt @claude_glyph)"
check "waiting color" '#ff8700' "$(opt @claude_color)"
run Stop
check "done glyph" '  ' "$(opt @claude_glyph)"
check "done color" '#00d700' "$(opt @claude_color)"
run StopFailure
check "error glyph" '  ' "$(opt @claude_glyph)"
check "error color" '#d70000' "$(opt @claude_color)"
run SessionStart
check "idle glyph is empty" '' "$(opt @claude_glyph)"
check "idle color is empty" '' "$(opt @claude_color)"

# --- @claude_pane: records the owning pane so tmux hooks can clear dead state ---
run UserPromptSubmit
check "claude pane recorded" "$PANE" "$(opt @claude_pane)"

run SessionEnd
check "SessionEnd unsets tab" '' "$(opt @claude_tab)"
check "SessionEnd unsets pane" '' "$(opt @claude_pane)"
check "SessionEnd unsets glyph" '' "$(opt @claude_glyph)"
check "SessionEnd unsets color" '' "$(opt @claude_color)"

# --- gc: drops state when the recorded claude pane is gone OR has reverted to
# --- a bare shell (claude died hard, pane survived); keeps live non-shell panes
W2="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_state working
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_tab 'X '
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_pane '%999'
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_glyph 'G '
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W2" @claude_color '#00d700'
W3="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' 'sleep 300')"
P3="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$W3" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W3" @claude_state working
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W3" @claude_pane "$P3"
W4="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}')"   # default shell
P4="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$W4" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W4" @claude_state working
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W4" @claude_pane "$P4"
# W5: wrapper launch (cwork/cpull style) — pane is shell-fronted but the real
# workload lives on as a child of pane_pid; gc must NOT clear it
W5="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' 'sleep 300; exec zsh')"
P5="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$W5" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W5" @claude_state working
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$W5" @claude_pane "$P5"
sleep 0.3   # let W4/W5 shells finish exec'ing so pane_current_command is real
PATH="$SHIM:$PATH" TMUX=fake bash "$SCRIPT" gc
check "gc clears dead-pane window state" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W2" @claude_state)"
check "gc clears dead-pane window tab" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W2" @claude_tab)"
check "gc clears dead-pane window glyph" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W2" @claude_glyph)"
check "gc clears dead-pane window color" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W2" @claude_color)"
check "gc keeps live non-shell pane state" working "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W3" @claude_state)"
check "gc clears shell-reverted pane state" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W4" @claude_state)"
check "gc keeps wrapper-launched workload state" working "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$W5" @claude_state)"
"$REAL_TMUX" -L "$SOCK" kill-window -t "$W2" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$W3" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$W4" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$W5" 2>/dev/null

# --- @claude_bg: a finished turn (done/idle/waiting) whose pane still has a live
# --- background bash worker (argv carries the shell-snapshots/snapshot signature
# --- as a descendant of pane_pid) gets the blue overlay flag; it clears when the
# --- worker exits, never lights for a non-matching descendant or an active turn.
#
# Build a "background worker" the same way Claude does: a helper executable whose
# path (hence full argv) contains shell-snapshots/snapshot, launched as a child
# of the window's pane_pid so it shows up as a descendant in the ps tree.
SNAPDIR="$SHIM/.claude/shell-snapshots"
mkdir -p "$SNAPDIR"
WORKER="$SNAPDIR/snapshot-worker.sh"             # argv contains shell-snapshots/snapshot
# Sleep WITHOUT exec, so this bash process's own argv keeps the snapshot path —
# mirroring Claude's long-lived `zsh -c 'source …/shell-snapshots/snapshot…'`
# wrapper whose argv carries the signature for the whole background task.
cat > "$WORKER" <<EOF
#!/usr/bin/env bash
sleep 300
EOF
chmod +x "$WORKER"

# WB1: done window whose pane_pid has the signature worker as a live descendant.
# The pane shell runs the worker in the background then blocks, so pane_pid (the
# shell) is the worker's ancestor and pane_current_command stays non-shell.
WB1="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' "$WORKER & sleep 300")"
PB1="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$WB1" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB1" @claude_state done
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB1" @claude_pane "$PB1"
# WB2: done window whose only descendant is a NON-matching process (a plain
# sleep, like an MCP server) — must NOT light the overlay.
WB2="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' 'sleep 300')"
PB2="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$WB2" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB2" @claude_state done
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB2" @claude_pane "$PB2"
# WB3: ACTIVE turn (working) with the matching worker — overlay must stay unset
# (it already animates as working; the overlay is only for finished turns).
WB3="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' "$WORKER & sleep 300")"
PB3="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$WB3" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB3" @claude_state working
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB3" @claude_pane "$PB3"
# WBE: a turn that ended in ERROR with the matching worker — error stays red
# (not overridden by the overlay), so @claude_bg must remain unset.
WBE="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' "$WORKER & sleep 300")"
PBE="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$WBE" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WBE" @claude_state error
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WBE" @claude_pane "$PBE"
sleep 0.4   # let the pane shells spawn the worker / sleep children
PATH="$SHIM:$PATH" TMUX=fake bash "$SCRIPT" gc
check "gc sets @claude_bg for done window with live worker" 1 "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WB1" @claude_bg)"
check "gc keeps done state under the overlay" done "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WB1" @claude_state)"
check "gc no @claude_bg for non-matching descendant" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WB2" @claude_bg)"
check "gc no @claude_bg for active (working) turn" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WB3" @claude_bg)"
check "gc no @claude_bg for error state with worker" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WBE" @claude_bg)"

# WB1 worker exits -> next gc clears the overlay (the only descendant is gone).
"$REAL_TMUX" -L "$SOCK" send-keys -t "$WB1" C-c
"$REAL_TMUX" -L "$SOCK" kill-window -t "$WB1" 2>/dev/null
# Re-create WB1 as a done window with NO worker to prove the clear path directly.
WB4="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}' 'sleep 300')"
PB4="$("$REAL_TMUX" -L "$SOCK" display-message -p -t "$WB4" '#{pane_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB4" @claude_state done
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB4" @claude_pane "$PB4"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB4" @claude_bg 1   # stale flag from a prior tick
sleep 0.3
PATH="$SHIM:$PATH" TMUX=fake bash "$SCRIPT" gc
check "gc clears @claude_bg once the worker is gone" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WB4" @claude_bg)"

# dead-claude clear also drops a stale @claude_bg (pane gone entirely).
WB5="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB5" @claude_state done
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB5" @claude_pane '%998'   # nonexistent pane
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WB5" @claude_bg 1
PATH="$SHIM:$PATH" TMUX=fake bash "$SCRIPT" gc
check "gc dead-claude clear also unsets @claude_bg" "" "$("$REAL_TMUX" -L "$SOCK" show-options -wqv -t "$WB5" @claude_bg)"

"$REAL_TMUX" -L "$SOCK" kill-window -t "$WB2" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$WB3" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$WBE" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$WB4" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$WB5" 2>/dev/null

# A real hook event drops the overlay so resuming activity reverts instantly;
# gc re-derives it next tick if the worker is still running.
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$PANE" @claude_bg 1
run UserPromptSubmit
check "UserPromptSubmit unsets @claude_bg" "" "$(opt @claude_bg)"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$PANE" @claude_bg 1
run SessionEnd
check "SessionEnd (clear_all) unsets @claude_bg" "" "$(opt @claude_bg)"

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

# --- animator also covers subagent state, cycling the pie spinner ---
run SubagentStart
sp2=''; pid_ok=0
for i in $(seq 1 40); do
  sp2=$(gopt @claude_spinner2); pid=$(gopt @claude_spinner_pid)
  [ -n "$sp2" ] && [ -n "$pid" ] && { pid_ok=1; break; }; sleep 0.1
done
check "animator runs for subagent state" 1 "$pid_ok"
case "$sp2" in 󰪞|󰪟|󰪠|󰪡|󰪢|󰪣|󰪤|󰪥) pie_ok=1 ;; *) pie_ok=0 ;; esac
check "pie spinner frame valid" 1 "$pie_ok"
run Stop
cleared=0
for i in $(seq 1 40); do [ -z "$(gopt @claude_spinner_pid)" ] && { cleared=1; break; }; sleep 0.1; done
check "animator exits after subagent turn ends" 1 "$cleared"

# --- animator also covers compacting, cycling the orbit spinner ---
run PreCompact
sp3=''; pid_ok=0
for i in $(seq 1 40); do
  sp3=$(gopt @claude_spinner3); pid=$(gopt @claude_spinner_pid)
  [ -n "$sp3" ] && [ -n "$pid" ] && { pid_ok=1; break; }; sleep 0.1
done
check "animator runs for compacting state" 1 "$pid_ok"
case "$sp3" in ⠉|⠘|⠰|⢠|⣀|⡄|⠆|⠃) orbit_ok=1 ;; *) orbit_ok=0 ;; esac
check "orbit spinner frame valid" 1 "$orbit_ok"
run Stop
cleared=0
for i in $(seq 1 40); do [ -z "$(gopt @claude_spinner_pid)" ] && { cleared=1; break; }; sleep 0.1; done
check "animator exits after compacting ends" 1 "$cleared"

# --- animator also keeps cycling for a backgrounded (overlay-only) window ---
# No working/subagent/compacting window exists; only @claude_bg=1 should hold
# the animator alive so the blue overlay's spinner animates.
WBA="$("$REAL_TMUX" -L "$SOCK" new-window -d -t t -P -F '#{window_id}')"
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WBA" @claude_state done
"$REAL_TMUX" -L "$SOCK" set-option -w -t "$WBA" @claude_bg 1
"$REAL_TMUX" -L "$SOCK" set-option -gu @claude_spinner_pid 2>/dev/null
PATH="$SHIM:$PATH" TMUX=fake bash "$SCRIPT" animate >/dev/null 2>&1 &
ANIM=$!
# A bg-only window must hold the animator alive: its pid stays claimed, and the
# spinner keeps advancing through distinct frames (only true if the loop runs).
seen=''; frames=0
for i in $(seq 1 40); do
  f=$(gopt @claude_spinner)
  case "$f" in ⣾|⣽|⣻|⢿|⡿|⣟|⣯|⣷) case "$seen" in *"$f"*) ;; *) seen="$seen$f"; frames=$((frames+1)) ;; esac ;; esac
  [ "$frames" -ge 2 ] && break; sleep 0.1
done
alive=0; kill -0 "$ANIM" 2>/dev/null && alive=1
check "animator stays alive for an overlay-only (bg) window" 1 "$alive"
[ "$frames" -ge 2 ] && cyc=1 || cyc=0
check "bg overlay cycles the braille spinner" 1 "$cyc"
"$REAL_TMUX" -L "$SOCK" set-option -uw -t "$WBA" @claude_bg
cleared=0
for i in $(seq 1 40); do [ -z "$(gopt @claude_spinner_pid)" ] && { cleared=1; break; }; sleep 0.1; done
check "animator exits once the bg overlay clears" 1 "$cleared"
wait "$ANIM" 2>/dev/null
"$REAL_TMUX" -L "$SOCK" kill-window -t "$WBA" 2>/dev/null

# --- outside tmux: no error, exit 0 ---
TMUX= TMUX_PANE= bash "$SCRIPT" Stop; rc=$?
check "no-tmux exit code" 0 "$rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
