# tmux Worktree Notice Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a boxed, toggleable notice at the top of every tmux window tied to a git worktree, displaying the issue number and title, and mark those windows in the status bar.

**Architecture:** The window carries its content as tmux user options (`@wt_num`, `@wt_title`, `@wt_branch`), stamped by `cwork`/`cpull` at window creation. A single script `bin/tmux-worktree-notice` renders the box in a 3-row pane split above the work pane and provides `show`/`hide`/`toggle`. A `prefix b` binding toggles it; `.tmux.conf` adds a tab marker keyed on `@wt_branch`.

**Tech Stack:** bash, tmux 3.6, zsh (the `cwork`/`cpull` functions). No test framework — this is a dotfiles repo, so verification uses inline assertions and a detached tmux test session.

**Reference spec:** `docs/superpowers/specs/2026-06-02-tmux-worktree-notice-banner-design.md`

**Environment facts (already verified):**
- `~/bin` is on `PATH` (`.exports:43`).
- `bin/` is symlinked to `~/bin` as a whole directory (`symlink-setup.sh:21`), so a new file under `bin/` appears in `~/bin` immediately — no re-symlink needed, only `chmod +x`.
- tmux is `3.6a`.
- All work happens on the `feature/tmux-worktree-notice` branch.

---

## File Structure

- **`bin/tmux-worktree-notice`** (new) — the whole feature's runtime. Subcommands: `draw` (pure box renderer, testable), `render` (resident in-pane loop), `show`, `hide`, `toggle`. One file, one responsibility (the banner).
- **`.tmux.conf`** (modify) — `bind b` toggle + `⧉` tab marker in `window-status-format` and `window-status-current-format`.
- **`.functions`** (modify) — new `_cwork_tag_window` helper; `_cwork_launch` widened to stamp the window and show the banner; `cwork`/`cpull` call sites pass `num`/`title`.
- **`CLAUDE.md`** (modify) — list the new `bin/` script.

---

## Task 1: Scaffold `bin/tmux-worktree-notice` with the `draw` renderer

**Files:**
- Create: `bin/tmux-worktree-notice`

- [ ] **Step 1: Create the script with helpers, `draw`, and the dispatch table**

Create `bin/tmux-worktree-notice` with exactly this content:

```bash
#!/usr/bin/env bash
# tmux-worktree-notice — boxed issue notice at the top of worktree windows.
# Subcommands: draw | render | show | hide | toggle
# Content lives in window user options @wt_num / @wt_title / @wt_branch,
# stamped by cwork/cpull (see .functions).

set -u

# Absolute path to this script, so we can re-invoke ourselves from tmux
# regardless of the caller's PATH (run-shell uses the tmux server environment).
case "$0" in
  /*)   SELF="$0" ;;
  */*)  SELF="$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")" ;;
  *)    SELF="$(command -v -- "$0" 2>/dev/null || printf '%s' "$0")" ;;
esac

# repeat <count> <string> -> prints <string> <count> times (no trailing newline)
repeat() {
  local n=$1 ch=$2 out='' i
  for (( i = 0; i < n; i++ )); do out+=$ch; done
  printf '%s' "$out"
}

# draw <width> <heading> <body>
# Prints a 3-line box exactly <width> columns wide. ASCII titles assumed
# (character counts approximate display columns; rare CJK titles may misalign).
draw() {
  local w=${1:-46} heading=${2:-} body=${3:-}
  (( w < 12 )) && w=12
  local inner=$(( w - 2 ))          # space between the two vertical borders

  # --- top border:  ┌─ <heading> ───…───┐
  local maxhead=$(( inner - 4 ))
  if (( ${#heading} > maxhead && maxhead > 1 )); then
    heading="${heading:0:maxhead-1}…"
  fi
  local pre="─ ${heading} "
  local dashes=$(( inner - ${#pre} ))
  (( dashes < 0 )) && dashes=0
  printf '┌%s%s┐\n' "$pre" "$(repeat "$dashes" '─')"

  # --- middle:  │ <body padded to field> │
  local field=$(( w - 4 ))
  if (( ${#body} > field && field > 1 )); then
    body="${body:0:field-1}…"
  fi
  local padlen=$(( field - ${#body} ))
  (( padlen < 0 )) && padlen=0
  printf '│ %s%s │\n' "$body" "$(repeat "$padlen" ' ')"

  # --- bottom border
  printf '└%s┘\n' "$(repeat "$inner" '─')"
}

main() {
  local cmd=${1:-}
  shift || true
  case "$cmd" in
    draw)   draw "$@" ;;
    render) render "$@" ;;
    show)   show "$@" ;;
    hide)   hide "$@" ;;
    toggle) toggle "$@" ;;
    *) printf 'usage: tmux-worktree-notice {show|hide|toggle|render|draw}\n' >&2; exit 2 ;;
  esac
}

main "$@"
```

Note: `render`, `show`, `hide`, `toggle` are added in later tasks. Calling them now would hit the `command not found` path inside bash and error — that's fine; Task 1 only exercises `draw`.

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x bin/tmux-worktree-notice
```

- [ ] **Step 3: Verify `draw` produces a correctly sized box (the test)**

Run:
```bash
bin/tmux-worktree-notice draw 46 '#4231' 'Fix flaky upload retry on slow networks'
```
Expected output (every line exactly 46 display columns wide):
```
┌─ #4231 ─────────────────────────────────────┐
│ Fix flaky upload retry on slow networks      │
└──────────────────────────────────────────────┘
```

- [ ] **Step 4: Verify width math and truncation with assertions**

Run:
```bash
S=bin/tmux-worktree-notice
# every line is exactly 46 chars (python counts characters, not bytes — macOS
# BSD awk/wc count bytes, which would miscount the multibyte box glyphs)
"$S" draw 46 '#4231' 'Fix flaky upload retry on slow networks' \
  | python3 -c 'import sys; print("OK width" if all(len(l)==46 for l in sys.stdin.read().splitlines()) else "FAIL width")'
# long title gets an ellipsis and does not overflow
"$S" draw 24 '#9' 'A very long issue title that will not fit' \
  | sed -n '2p' | grep -q '…' && echo "OK ellipsis" || echo "FAIL ellipsis"
# narrow width is floored, not broken
"$S" draw 4 '#9' 'x' | grep -c '' | grep -q '3' && echo "OK 3 lines" || echo "FAIL line count"
```
Expected:
```
OK width
OK ellipsis
OK 3 lines
```

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-worktree-notice
git commit -m "Add tmux-worktree-notice draw renderer"
```

---

## Task 2: Add the `render` resident loop

**Files:**
- Modify: `bin/tmux-worktree-notice` (insert the `render` function before `main()`)

- [ ] **Step 1: Add the `render` function**

Insert this function into `bin/tmux-worktree-notice` immediately after the `draw` function (before `main()`):

```bash
# render <main-pane-id>
# Runs inside the banner pane. Draws from the window's @wt_* options, redraws on
# resize, and exits when the main pane is gone so the window can close normally.
render() {
  local main=${1:-}

  _redraw() {
    local num title branch heading body w
    num=$(tmux show-options -wqv -t "$TMUX_PANE" @wt_num)
    title=$(tmux show-options -wqv -t "$TMUX_PANE" @wt_title)
    branch=$(tmux show-options -wqv -t "$TMUX_PANE" @wt_branch)
    w=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_width}')

    if [ -n "$num" ]; then heading="#$num"; else heading="$branch"; fi
    if [ -n "$title" ]; then
      body="$title"
    elif [ -n "$num" ]; then
      body=""
    else
      body="(issue-less worktree)"
    fi

    # Print WITHOUT a trailing newline: on a full-height (3-row) pane, a final
    # newline scrolls the top border off-screen. $(...) strips the trailing
    # newline; printf %s leaves the cursor on the last line, so nothing scrolls.
    printf '\033[H\033[J\033[38;5;39m'          # home + clear + accent (color 39 == #00afff)
    printf '%s' "$(draw "${w:-46}" "$heading" "$body")"
    printf '\033[0m'
  }

  trap '_redraw' WINCH
  _redraw

  # Keep alive until the main pane disappears. List panes server-wide (-a): the
  # banner often runs in a background window (cwork opens it with new-window -d),
  # where an unqualified list-panes resolves to the active window and would miss
  # $main. `sleep & wait` so the WINCH trap can interrupt the wait and redraw
  # without killing the loop.
  while tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$main"; do
    sleep 5 &
    wait "$!" 2>/dev/null
  done
}
```

- [ ] **Step 2: Verify the script still parses and `draw` is unaffected**

Run:
```bash
bash -n bin/tmux-worktree-notice && echo "OK parse"
bin/tmux-worktree-notice draw 46 '#1' 'still works' | sed -n '2p'
```
Expected:
```
OK parse
│ still works                                  │
```

- [ ] **Step 3: Verify `render` lives and dies with the main pane (integration)**

This uses a throwaway detached tmux session. Run:
```bash
tmux kill-session -t wtntest 2>/dev/null
tmux new-session -d -s wtntest -x 80 -y 24 'sleep 600'   # the "main" pane
WIN=$(tmux display-message -p -t wtntest '#{window_id}')
MAIN=$(tmux display-message -p -t wtntest '#{pane_id}')
tmux set-option -w -t "$WIN" @wt_num 4231
tmux set-option -w -t "$WIN" @wt_title 'Fix flaky upload retry'
tmux set-option -w -t "$WIN" @wt_branch 'bug/4231-fix-flaky-upload'
# split a banner pane running render, like `show` will
BP=$(tmux split-window -vb -l 3 -t "$MAIN" -P -F '#{pane_id}' "$PWD/bin/tmux-worktree-notice render $MAIN")
sleep 1
echo "panes now: $(tmux list-panes -t "$WIN" | wc -l | tr -d ' ')"   # expect 2
tmux capture-pane -p -t "$BP" | grep -q '#4231' && echo "OK banner drawn" || echo "FAIL banner content"
# kill the main pane -> render should notice within ~5s and the window should close
tmux kill-pane -t "$MAIN"
sleep 7
tmux has-session -t wtntest 2>/dev/null && { echo "FAIL window lingered"; tmux kill-session -t wtntest; } || echo "OK window closed"
```
Expected:
```
panes now: 2
OK banner drawn
OK window closed
```

- [ ] **Step 4: Commit**

```bash
git add bin/tmux-worktree-notice
git commit -m "Add render loop to tmux-worktree-notice"
```

---

## Task 3: Add `show`, `hide`, `toggle` and their helpers

**Files:**
- Modify: `bin/tmux-worktree-notice` (insert helpers + the three subcommands before `main()`)

- [ ] **Step 1: Add the helpers and subcommands**

Insert these functions into `bin/tmux-worktree-notice` after `render` (before `main()`):

```bash
# _win [target] -> resolves a window id (active window if no target)
_win() {
  if [ -n "${1:-}" ]; then
    tmux display-message -p -t "$1" '#{window_id}'
  else
    tmux display-message -p '#{window_id}'
  fi
}

# _is_worktree <window-id> -> success if any @wt_* option is set
_is_worktree() {
  local v
  v="$(tmux show-options -wqv -t "$1" @wt_branch)$(tmux show-options -wqv -t "$1" @wt_num)$(tmux show-options -wqv -t "$1" @wt_title)"
  [ -n "$v" ]
}

# _banner_pane <window-id> -> prints the pane id flagged @wt_banner, if any
_banner_pane() {
  tmux list-panes -t "$1" -F '#{pane_id} #{@wt_banner}' 2>/dev/null \
    | awk '$2 == "1" { print $1; exit }'
}

# show [target]
show() {
  local win main bp
  win=$(_win "${1:-}") || return 1
  if ! _is_worktree "$win"; then
    tmux display-message 'tmux-worktree-notice: not a worktree window'
    return 1
  fi
  [ -n "$(_banner_pane "$win")" ] && return 0      # idempotent
  main=$(tmux display-message -p -t "$win" '#{pane_id}')
  # Quote $SELF: the command is one string handed to sh -c, so an install path
  # with a space would otherwise split into command + args. ($main is a %N id.)
  bp=$(tmux split-window -vb -l 3 -t "$main" -P -F '#{pane_id}' "$(printf '%q' "$SELF") render $main") || return 1
  tmux set-option -p -t "$bp" @wt_banner 1
  tmux select-pane -t "$main"
}

# hide [target]
hide() {
  local win bp
  win=$(_win "${1:-}") || return 1
  bp=$(_banner_pane "$win")
  [ -n "$bp" ] && tmux kill-pane -t "$bp"
  return 0
}

# toggle [target]
toggle() {
  local win
  win=$(_win "${1:-}") || return 1
  if [ -n "$(_banner_pane "$win")" ]; then
    hide "$win"
  else
    show "$win"
  fi
}
```

- [ ] **Step 2: Verify parse**

Run:
```bash
bash -n bin/tmux-worktree-notice && echo "OK parse"
```
Expected: `OK parse`

- [ ] **Step 3: Verify show / toggle / hide end-to-end (integration)**

Run:
```bash
tmux kill-session -t wtntest 2>/dev/null
tmux new-session -d -s wtntest -x 80 -y 24 'sleep 600'
WIN=$(tmux display-message -p -t wtntest '#{window_id}')
tmux set-option -w -t "$WIN" @wt_num 7
tmux set-option -w -t "$WIN" @wt_title 'Add the thing'
tmux set-option -w -t "$WIN" @wt_branch 'feature/7-add-the-thing'
S="$PWD/bin/tmux-worktree-notice"

"$S" show "$WIN"; sleep 1
echo "after show:   $(tmux list-panes -t "$WIN" | wc -l | tr -d ' ')"   # expect 2
"$S" show "$WIN"; sleep 1
echo "after re-show:$(tmux list-panes -t "$WIN" | wc -l | tr -d ' ')"   # expect 2 (idempotent)
"$S" toggle "$WIN"; sleep 1
echo "after toggle: $(tmux list-panes -t "$WIN" | wc -l | tr -d ' ')"   # expect 1
"$S" toggle "$WIN"; sleep 1
echo "after toggle2:$(tmux list-panes -t "$WIN" | wc -l | tr -d ' ')"   # expect 2

# non-worktree window: show is a no-op
tmux new-window -d -t wtntest -n plain 'sleep 600'
PWIN=$(tmux list-windows -t wtntest -F '#{window_id} #{window_name}' | awk '$2=="plain"{print $1}')
"$S" show "$PWIN"; sleep 1
echo "plain panes:  $(tmux list-panes -t "$PWIN" | wc -l | tr -d ' ')"  # expect 1

tmux kill-session -t wtntest
```
Expected:
```
after show:   2
after re-show:2
after toggle: 1
after toggle2:2
plain panes:  1
```

- [ ] **Step 4: Commit**

```bash
git add bin/tmux-worktree-notice
git commit -m "Add show/hide/toggle to tmux-worktree-notice"
```

---

## Task 4: Wire the keybinding and tab marker in `.tmux.conf`

**Files:**
- Modify: `.tmux.conf` (key bindings section ~line 40-86; window status ~line 139 and 147-151)

- [ ] **Step 1: Add the toggle keybinding**

In `.tmux.conf`, find the reload binding:
```tmux
# reload config
bind r source-file ~/.tmux.conf \; display '~/.tmux.conf sourced'
```
Immediately after it, add:
```tmux
# toggle the worktree issue notice box (worktree windows only)
bind b run-shell '~/bin/tmux-worktree-notice toggle'
```

- [ ] **Step 2: Add the `⧉` marker to the non-current window tab**

Replace the existing `window-status-format` line (currently line 139):
```tmux
setw -g window-status-format '#{?@claude_waiting,#[fg=#080808]#[bg=#ff8700]▎#[fg=#000000]#[bold] #I #{=14:window_name} ,#[fg=#080808]#[bg=default]▎#[default] #I #{=14:window_name} }'
```
with:
```tmux
setw -g window-status-format '#{?@claude_waiting,#[fg=#080808]#[bg=#ff8700]▎#[fg=#000000]#[bold] #I #{=14:window_name} ,#[fg=#080808]#[bg=default]▎#[default] #{?@wt_branch,#[fg=#00afff]⧉ #[default],}#I #{=14:window_name} }'
```
(The only change: `#{?@wt_branch,#[fg=#00afff]⧉ #[default],}` inserted before `#I` in the non-waiting branch.)

- [ ] **Step 3: Add the `⧉` marker to the current window tab**

Replace the existing `window-status-current-format` block (currently lines 147-150):
```tmux
setw -g window-status-current-format '\
#[fg=#080808,bg=#00afff]\
#[fg=#000000,bg=#00afff,bold] #I #{=14:window_name} \
#[fg=#00afff,bg=#080808]'
```
with:
```tmux
setw -g window-status-current-format '\
#[fg=#080808,bg=#00afff]\
#[fg=#000000,bg=#00afff,bold] #{?@wt_branch,⧉ ,}#I #{=14:window_name} \
#[fg=#00afff,bg=#080808]'
```
(The only change: `#{?@wt_branch,⧉ ,}` inserted before `#I`.)

- [ ] **Step 4: Verify the config sources cleanly and the binding exists**

Run (safe even outside tmux — it parses the file in a throwaway server):
```bash
tmux -L wtncheck -f .tmux.conf start-server \; list-keys \; kill-server 2>&1 | grep -E 'bind-key.* b .*worktree-notice' && echo "OK binding"
```
Expected: a line containing `tmux-worktree-notice toggle`, then `OK binding`.

If you are inside tmux, also run `tmux source-file ~/.tmux.conf` and confirm no error is displayed.

- [ ] **Step 5: Commit**

```bash
git add .tmux.conf
git commit -m "Add prefix-b toggle and worktree tab marker"
```

---

## Task 5: Stamp and show the banner from `cwork`/`cpull`

**Files:**
- Modify: `.functions` — `_cwork_launch` (lines 208-236), add `_cwork_tag_window` helper, and the two call sites (line 505 in `cwork`, line 654 in `cpull`)

- [ ] **Step 1: Add the `_cwork_tag_window` helper**

In `.functions`, immediately **before** the `_cwork_launch` function (before its leading comment at line ~204), insert:

```zsh
# Stamp a tmux window with the worktree's issue context and show the notice box.
# Args: <window-id> <num> <title> <branch>
_cwork_tag_window() {
  emulate -L zsh
  local wid=$1 num=$2 title=$3 branch=$4
  [[ -n $wid ]] || return 0
  tmux set-option -w -t "$wid" @wt_num    "$num"
  tmux set-option -w -t "$wid" @wt_title  "$title"
  tmux set-option -w -t "$wid" @wt_branch "$branch"
  command -v tmux-worktree-notice >/dev/null 2>&1 && tmux-worktree-notice show "$wid"
}
```

- [ ] **Step 2: Rewrite `_cwork_launch` to capture the window id, stamp it, and show the banner**

Replace the entire `_cwork_launch` function body (lines 208-236) — keep its preceding comment block — with:

```zsh
_cwork_launch() {
  emulate -L zsh
  local wt=$1 branch=$2 foreground=$3 prompt=$4 num=$5 title=$6
  if (( foreground )); then
    cd "$wt" || return
    if [[ -n $prompt ]]; then claude "$prompt"; else claude; fi
    return
  fi
  local win=${branch##*/}
  local sess=${CWORK_SESSION:-cwork}
  local cmd
  if [[ -n $prompt ]]; then
    cmd="cd ${(q)wt} && claude ${(q)prompt}; exec ${SHELL:-zsh}"
  else
    cmd="cd ${(q)wt} && claude; exec ${SHELL:-zsh}"
  fi
  local wid
  if [[ -n $TMUX ]]; then
    wid=$(tmux new-window -d -P -F '#{window_id}' -n "$win" "$cmd")
    _cwork_tag_window "$wid" "$num" "$title" "$branch"
    print -- "opened tmux window: ${win}"
  else
    if tmux has-session -t "$sess" 2>/dev/null; then
      wid=$(tmux new-window -t "$sess" -P -F '#{window_id}' -n "$win" "$cmd")
    else
      wid=$(tmux new-session -d -s "$sess" -P -F '#{window_id}' -n "$win" "$cmd")
    fi
    _cwork_tag_window "$wid" "$num" "$title" "$branch"
    print -- "attaching to tmux session '${sess}', window: ${win}"
    tmux attach -t "$sess"
  fi
}
```

- [ ] **Step 3: Update the `cwork` call site**

In `cwork`, find (line ~505):
```zsh
  _cwork_launch "$wt" "$branch" "$foreground" "$prompt"
```
Replace with:
```zsh
  _cwork_launch "$wt" "$branch" "$foreground" "$prompt" "$num" "$title"
```

- [ ] **Step 4: Update the `cpull` call site**

In `cpull`, find (line ~654):
```zsh
  _cwork_launch "$wt" "$branch" "$foreground" "$prompt"
```
Replace with:
```zsh
  _cwork_launch "$wt" "$branch" "$foreground" "$prompt" "$num" "$title"
```
(In `cpull`, `num` is set at line ~583 as `${issue_num:-$pr_num}` and `title` is in scope.)

- [ ] **Step 5: Verify `.functions` parses and `_cwork_launch` stamps + shows (integration)**

Run (this exercises the real `_cwork_launch`/`_cwork_tag_window` with a dummy work command, no GitHub needed). It uses an isolated tmux socket (`-L wtftest`) so `list-panes -a` only sees this test's panes, and because `_cwork_launch` creates the banner in a new, *unfocused* window, the count must be server-wide (`-a`), not current-window:
```bash
zsh -n .functions && echo "OK parse"
tmux -L wtftest kill-server 2>/dev/null
tmux -L wtftest new-session -d -s s -x 80 -y 24
tmux -L wtftest send-keys -t s \
  "source $PWD/.functions; _cwork_launch /tmp 'feature/7-demo' 0 '' 7 'Demo issue title' >/dev/null 2>&1; sleep 1; tmux list-panes -a -F '#{@wt_banner}' | grep -cx 1 > /tmp/wtf_banner_count" Enter
sleep 3
echo "banner panes created: $(cat /tmp/wtf_banner_count 2>/dev/null)"   # expect 1
tmux -L wtftest kill-server 2>/dev/null
rm -f /tmp/wtf_banner_count
```
Expected:
```
OK parse
banner panes created: 1
```
The inner `tmux` calls (from the sourced `_cwork_launch`, including the `show`) inherit `$TMUX`, so they target the `wtftest` socket automatically. The launch uses `claude` as its window command; whether or not `claude` is installed, the banner is stamped and shown first, so the count is valid. The `sleep 1` inside gives `show` time to split.

- [ ] **Step 6: Commit**

```bash
git add .functions
git commit -m "Stamp worktree windows and show notice from cwork/cpull"
```

---

## Task 6: Document the new script in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (the `## Utility Scripts (\`bin/\`)` list)

- [ ] **Step 1: Add the bullet**

In `CLAUDE.md`, find the `## Utility Scripts (\`bin/\`)` list and add this bullet after the `tmux-status.sh` entry:
```markdown
- `tmux-worktree-notice` — draws/toggles the boxed issue notice at the top of tmux worktree windows (issue # + title). Stamped onto windows by `cwork`/`cpull` via `@wt_num`/`@wt_title`/`@wt_branch`; toggle with `prefix b`
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -q 'tmux-worktree-notice' CLAUDE.md && echo "OK documented"
```
Expected: `OK documented`

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Document tmux-worktree-notice in CLAUDE.md"
```

---

## Task 7: Final end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Source the live config**

If you are inside tmux, run:
```bash
tmux source-file ~/.tmux.conf && echo "OK sourced"
```
Expected: `OK sourced` and no red error message in tmux.

- [ ] **Step 2: Full simulated worktree window (no GitHub required)**

Run:
```bash
tmux kill-session -t wtne2e 2>/dev/null
tmux new-session -d -s wtne2e -x 100 -y 30 'sleep 600'
WIN=$(tmux display-message -p -t wtne2e '#{window_id}')
tmux set-option -w -t "$WIN" @wt_num 4231
tmux set-option -w -t "$WIN" @wt_title 'Fix flaky upload retry on slow networks'
tmux set-option -w -t "$WIN" @wt_branch 'bug/4231-fix-flaky-upload'
~/bin/tmux-worktree-notice show "$WIN"; sleep 1
echo "--- banner pane content ---"
BP=$(tmux list-panes -t "$WIN" -F '#{pane_id} #{@wt_banner}' | awk '$2==1{print $1}')
tmux capture-pane -p -t "$BP"
echo "--- tab marker ---"
tmux list-windows -t wtne2e -F '#{window_id} #{?@wt_branch,WORKTREE,plain}'
tmux kill-session -t wtne2e
```
Expected: a three-line box containing `#4231` and the title; the window line ends in `WORKTREE`.

- [ ] **Step 3: Confirm the working tree is clean and review the branch**

Run:
```bash
git status --short
git log --oneline feature/tmux-worktree-notice ^main
```
Expected: empty `git status`; the log shows the spec commit plus the six implementation commits.

- [ ] **Step 4: Real smoke test (manual, optional — requires a repo with `gh` + `make worktree-add`)**

In a real project repo on a machine with `claude`/`gh`: run `cwork <open-issue#>`, switch to the new window, confirm the box shows `#<num>` and the title with focus in the work pane and a `⧉` on the tab, press `prefix b` to hide, `prefix b` to restore, then exit the work pane and confirm the window closes.

---

## Notes for the implementer

- **Box glyphs / locale:** `draw` counts characters for width; in a UTF-8 locale (the default in these terminals) each box-drawing glyph is one column. CJK titles can misalign by a column — acceptable per the spec's non-goals.
- **`show` is idempotent** — safe to call from both `cwork` and a manual `prefix b`.
- **Teardown** is handled by `render` polling the main pane id; do not add `remain-on-exit` hacks.
- **Do not** re-run `symlink-setup.sh` — `bin/` is already a directory symlink, so the new file is live in `~/bin` once it is executable.
