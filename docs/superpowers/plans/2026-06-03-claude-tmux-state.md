# Per-tab Claude State Indicator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each Claude Code session's current state (working / subagent / compacting / waiting / done / idle) on its tmux window tab.

**Architecture:** Claude Code hooks invoke a new `bin/claude-tmux-state <HookEvent>` helper, which writes `@claude_state` (and a `@claude_subagents` depth counter) on the window owning `$TMUX_PANE` and refreshes the status line. `.tmux.conf` renders `@claude_state` with a tiered look — loud full-tab orange for `waiting`, quiet colored bar + glyph for the rest. Focused tab is left unchanged.

**Tech Stack:** Bash, tmux window options & formats, Claude Code hooks (settings.json), `jq` for JSON validation.

**Design doc:** `docs/superpowers/specs/2026-06-03-claude-tmux-state-design.md`

**Pre-flight (read before starting):**
- `bin/` is symlinked to `$HOME` as a whole directory, so `~/bin/claude-tmux-state` is live the moment the file exists in the repo — no re-run of `symlink-setup.sh` needed.
- `~/.claude/settings.json` is the **live** config (git-ignored, outside the repo): editing it takes effect immediately. `claude/settings.example.json` is the repo's **public template** that mirrors it; keep both in sync.
- `CLAUDE.md` and `.claude/` are **git-ignored** in this repo. Edits to `CLAUDE.md` are local-only — do **not** attempt to commit them.
- Confirm git identity is `ajt <github@thorntonindustries.com>` before committing (`git config user.email`). If it shows `ci@perfect.local`, run `git checkout .gitconfig` first — an external process corrupted it this session.

---

### Task 1: `claude-tmux-state` helper + test harness (TDD)

**Files:**
- Create: `bin/claude-tmux-state`
- Create: `tests/test-claude-tmux-state.sh`

- [ ] **Step 1: Write the test harness (failing)**

Create `tests/test-claude-tmux-state.sh`:

```bash
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
```

Make it executable:

```bash
chmod +x tests/test-claude-tmux-state.sh
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test-claude-tmux-state.sh; echo "exit=$?"`
Expected: many `FAIL:` lines (the helper doesn't exist yet) and a non-zero `exit=1`.

- [ ] **Step 3: Write the helper**

Create `bin/claude-tmux-state`:

```bash
#!/usr/bin/env bash
# claude-tmux-state — reflect Claude Code session state on its tmux window tab.
#
# Invoked by Claude Code hooks with the hook event name as $1, e.g.
#   ~/bin/claude-tmux-state UserPromptSubmit
# Sets the window options @claude_state and @claude_subagents on the window that
# owns $TMUX_PANE, then refreshes the status line. Renders nothing itself — the
# tab appearance lives in .tmux.conf's window-status-format. No-op outside tmux.
set -u

ev=${1:-}
pane=${TMUX_PANE:-}

# Not inside tmux (Claude launched in a plain terminal): do nothing, succeed.
[ -n "${TMUX:-}" ] && [ -n "$pane" ] || exit 0

set_state() { tmux set-option -w -t "$pane" @claude_state "$1" 2>/dev/null; }
set_count() { tmux set-option -w -t "$pane" @claude_subagents "$1" 2>/dev/null; }
clear_all() {
  tmux set-option -uw -t "$pane" @claude_state 2>/dev/null
  tmux set-option -uw -t "$pane" @claude_subagents 2>/dev/null
}

# current subagent depth, sanitised to a non-negative integer
n=$(tmux show-options -wqv -t "$pane" @claude_subagents 2>/dev/null)
case "$n" in ''|*[!0-9]*) n=0 ;; esac

case "$ev" in
  SessionStart)     set_count 0; set_state idle ;;
  UserPromptSubmit) set_count 0; set_state working ;;
  PreToolUse)       if [ "$n" -gt 0 ]; then set_state subagent; else set_state working; fi ;;
  Notification)     set_state waiting ;;
  SubagentStart)    n=$((n + 1)); set_count "$n"; set_state subagent ;;
  SubagentStop)
    n=$((n - 1)); [ "$n" -lt 0 ] && n=0
    set_count "$n"
    if [ "$n" -gt 0 ]; then set_state subagent; else set_state working; fi
    ;;
  PreCompact)       set_state compacting ;;
  Stop)             set_count 0; set_state done ;;
  SessionEnd)       clear_all ;;
  *)                exit 0 ;;
esac

tmux refresh-client -S 2>/dev/null
exit 0
```

Make it executable:

```bash
chmod +x bin/claude-tmux-state
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test-claude-tmux-state.sh; echo "exit=$?"`
Expected: no `FAIL:` lines, final line `23 passed, 0 failed`, `exit=0`.

- [ ] **Step 5: Lint the helper**

Run: `command -v shellcheck >/dev/null && shellcheck bin/claude-tmux-state tests/test-claude-tmux-state.sh || echo "shellcheck not installed — skipping"`
Expected: no errors (or the skip message). Fix any warnings that indicate real bugs.

- [ ] **Step 6: Commit**

```bash
git add bin/claude-tmux-state tests/test-claude-tmux-state.sh
git commit -m "Add claude-tmux-state helper for per-tab Claude state"
```

---

### Task 2: tmux tab rendering

**Files:**
- Modify: `.tmux.conf:142` (the `window-status-format` line)

Leave `window-status-current-format` (line ~150) and `window-status-current-style` unchanged — the focused tab shows no Claude state by design.

- [ ] **Step 1: Replace the `window-status-format` line**

Find this exact line (line 142):

```tmux
setw -g window-status-format '#{?@claude_waiting,#[fg=#080808]#[bg=#ff8700]▎#[fg=#000000]#[bold] #I #{=14:window_name} ,#[fg=#080808]#[bg=default]▎#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} }'
```

Replace it with (single line — keep it on one line):

```tmux
setw -g window-status-format '#{?#{==:#{@claude_state},waiting},#[fg=#080808]#[bg=#ff8700]▎#[fg=#000000]#[bold] ? #{?@wt_branch,⧉ ,}#I #{=14:window_name} ,#{?#{==:#{@claude_state},working},#[bg=default]#[fg=#00d7d7]▎◐#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} ,#{?#{==:#{@claude_state},subagent},#[bg=default]#[fg=#af5fff]▎⊕#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} ,#{?#{==:#{@claude_state},compacting},#[bg=default]#[fg=#8a8a8a]▎⟳#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} ,#{?#{==:#{@claude_state},done},#[bg=default]#[fg=#00d700]▎✓#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} ,#[fg=#080808]#[bg=default]▎#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} }}}}}'
```

(Branch order: `waiting` → `working` → `subagent` → `compacting` → `done` → default/idle. The five `}` at the end close the five nested `#{?...}` conditionals.)

- [ ] **Step 2: Verify the config parses**

Run: `tmux -L cfgcheck new-session -d \; source-file ~/.tmux.conf \; kill-server 2>&1; echo "exit=$?"`
Expected: no error output about line 142 / unknown format; `exit=0`. (A `no server`-type message after kill is fine.)

- [ ] **Step 3: Verify the conditional logic matches each state**

Run:
```bash
tmux -L fmtcheck new-session -d -s t -x 100 -y 24
for s in working subagent compacting waiting done; do
  tmux -L fmtcheck set-option -w -t t @claude_state "$s"
  printf '%-11s -> %s\n' "$s" "$(tmux -L fmtcheck display-message -p -t t '#{?#{==:#{@claude_state},'"$s"'},MATCH,no}')"
done
tmux -L fmtcheck kill-server 2>/dev/null
```
Expected: each line prints `MATCH` (confirms `#{==:#{@claude_state},…}` resolves correctly).

- [ ] **Step 4: Visual smoke test (manual)**

In your real tmux: `tmux source-file ~/.tmux.conf`, then in a **non-focused** window run `tmux set-option -w -t <window> @claude_state working` (and `subagent`/`compacting`/`waiting`/`done`) and confirm the tab shows the right glyph/color from the legend; `tmux set-option -uw -t <window> @claude_state` returns it to normal. Confirm a worktree window (`@wt_branch` set) still shows `⧉`.

- [ ] **Step 5: Commit**

```bash
git add .tmux.conf
git commit -m "Render Claude state on tmux tabs via @claude_state"
```

---

### Task 3: Wire the Claude Code hooks

**Files:**
- Modify (live, NOT committed): `~/.claude/settings.json`
- Modify (repo template): `claude/settings.example.json`

Both files currently contain an identical `"hooks"` block that uses `@claude_waiting`. Replace the **entire `"hooks"` object** in **both** files with the block below. It preserves the existing `adversarial-completion-review` hooks (`hook-gate.sh` on `PreToolUse`/Bash and `hook-challenge.sh` on `UserPromptSubmit`) and swaps every `@claude_waiting` one-liner for a `~/bin/claude-tmux-state` call, adding `SessionStart`, `SubagentStart`, `SubagentStop`, and `PreCompact`.

- [ ] **Step 1: Replace the `"hooks"` block in `~/.claude/settings.json`**

New `"hooks"` value:

```json
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SessionStart" } ] }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "bash ~/.agents/skills/adversarial-completion-review/hook-gate.sh" } ]
      },
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state PreToolUse" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash ~/.agents/skills/adversarial-completion-review/hook-challenge.sh" } ] },
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state UserPromptSubmit" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state Notification" } ] }
    ],
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SubagentStart" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SubagentStop" } ] }
    ],
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state PreCompact" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state Stop" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SessionEnd" } ] }
    ]
  },
```

- [ ] **Step 2: Validate the live JSON**

Run: `jq empty ~/.claude/settings.json && echo "valid JSON"`
Expected: `valid JSON` (no parse error).

- [ ] **Step 3: Apply the identical `"hooks"` block to the repo template**

Make the same replacement in `claude/settings.example.json` (same `"hooks"` object as Step 1).

- [ ] **Step 4: Validate the template JSON**

Run: `jq empty claude/settings.example.json && echo "valid JSON"`
Expected: `valid JSON`.

- [ ] **Step 5: End-to-end check against a real session's pane**

Run (from inside a tmux pane): `~/bin/claude-tmux-state Stop && tmux show-options -wqv @claude_state`
Expected: prints `done`. Then `~/bin/claude-tmux-state SessionEnd && tmux show-options -wqv @claude_state` prints an empty line.

- [ ] **Step 6: Commit the template (live file is not committed)**

> NOTE: `claude/` is currently **untracked** working-tree state. This step begins tracking only `claude/settings.example.json`. If the user prefers to commit the whole `claude/` directory (README, statusline, example) themselves, SKIP this commit and surface it instead.

```bash
git add claude/settings.example.json
git commit -m "Update settings template hooks to drive claude-tmux-state"
```

---

### Task 4: Document the helper (local-only)

**Files:**
- Modify (git-ignored — local only, do NOT commit): `CLAUDE.md`

- [ ] **Step 1: Add a bullet under "Utility Scripts (`bin/`)"**

After the `tmux-worktree-notice` bullet, add:

```markdown
- `claude-tmux-state` — sets the `@claude_state` tmux window option (working/subagent/compacting/waiting/done/idle) from Claude Code hooks so each window tab shows what Claude is doing. Wired in `~/.claude/settings.json` hooks; rendered by `.tmux.conf` `window-status-format`. Maintains a `@claude_subagents` depth counter for subagent detection.
```

- [ ] **Step 2: Verify it is git-ignored (so it is correctly left uncommitted)**

Run: `git check-ignore CLAUDE.md && echo "ignored (correct — leave uncommitted)"`
Expected: `CLAUDE.md` then `ignored (correct — leave uncommitted)`.

---

## Final verification (after all tasks)

- [ ] `bash tests/test-claude-tmux-state.sh` → `23 passed, 0 failed`.
- [ ] `git log --oneline` shows commits for Task 1, Task 2, and (if taken) Task 3 — all authored by `ajt <github@thorntonindustries.com>`.
- [ ] Live behavior: in a real Claude session, the background tab transitions `working` → `done` across a turn, a `Notification` turns it orange, and the focused tab stays blue. (Restart/`/resume` the session if needed so the new hooks load.)
- [ ] Surface to the user: whether to commit the rest of the untracked `claude/` dir, and the reminder that `~/.claude/settings.json` + `CLAUDE.md` changes are intentionally uncommitted.
