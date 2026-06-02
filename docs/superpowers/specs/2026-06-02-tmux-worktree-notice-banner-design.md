# Worktree notice banner for tmux

**Date:** 2026-06-02
**Status:** Approved (design)

## Summary

Give every tmux window that is associated with a git worktree a visually distinct,
boxed notice area at the top of the window describing the issue being worked on, and
a keystroke to show/hide it. Worktree windows are also marked in the status bar tab
so they are scannable even when the box is hidden.

Worktree windows are created by the existing `cwork` and `cpull` shell functions
(in `.functions`), which already have the issue context (number, title, branch) in
hand at window-creation time. This feature stamps that context onto the window and
renders it.

## Goals

- A boxed, multi-line notice at the **top** of each worktree window showing the
  issue **number** and **title**.
- **Visible by default** when a worktree window is created.
- A keybinding (`prefix b`) to **toggle** the box off/on per window.
- A small marker on the **window tab** so worktree windows are visually distinct
  in the status bar even with the box hidden.
- Graceful behavior for issue-less worktrees (`cwork -B`) and `cpull` branch mode.

## Non-goals

- Live updates of the issue (title/state can change upstream; the box reflects what
  was captured at window creation). No polling of GitHub.
- Showing branch / state / labels / URL in the box (explicitly scoped out — issue #
  and title only). Branch is still stamped as a fallback heading for issue-less
  worktrees.
- Working in any multiplexer other than tmux.

## Source of truth: window options

The window itself holds the content via window-scoped tmux user options. This is the
same pattern `.tmux.conf` already uses for `@claude_waiting`. Storing content on the
window (rather than baking it into the pane's command) is what makes the toggle
reliable: re-showing the box rebuilds it from these options, so it survives
hide/show cycles and client detach/reattach.

| Option       | Meaning                                                        |
|--------------|---------------------------------------------------------------|
| `@wt_num`    | Issue number, e.g. `4231`. Empty for issue-less worktrees.    |
| `@wt_title`  | Issue title. Empty when there is no issue.                    |
| `@wt_branch` | Branch name. Used as the box heading when `@wt_num` is empty. |

A window is "a worktree window" iff at least one of these options is set.

## Components

### 1. `bin/tmux-worktree-notice` (new script)

A single POSIX/zsh script with subcommands. Keeping the logic here (not inline in
`.tmux.conf` or `.functions`) keeps both call sites thin and matches the repo's
`bin/` convention (`tmux-status.sh`, etc.). It is symlinked to `$HOME` by the
existing `symlink-setup.sh` `bin/` rule, so `~/bin/tmux-worktree-notice` resolves.

Subcommands:

- **`render`** — runs *inside* the header pane. Resolves its own window from
  `$TMUX_PANE` (`tmux show-options -wqv -t "$TMUX_PANE" @wt_num`, etc.), draws the
  box sized to the current pane width, and stays resident:
  - Redraws immediately on `SIGWINCH` (terminal/pane resize) by re-running the draw.
  - Every ~5s, checks that the **main pane** (id passed in by `show`) still exists;
    if it is gone, `render` exits. This guarantees the window tears down normally
    when `claude`/the shell in the main pane exits — a resident banner pane must not
    keep an otherwise-empty window alive.
  - Title is truncated with an ellipsis to fit `pane_width − borders − padding`.

  Box layout (heading = `#<num>`, or branch name when issue-less):
  ```
  ┌─ #4231 ───────────────────────────────────┐
  │ Fix flaky upload retry on slow networks    │
  └────────────────────────────────────────────┘
  ```
  Styling uses the repo's existing accent (`#00afff` cyan) for the border so it
  reads as a distinct notice area.

- **`show [target-window]`** — idempotent. If the target already has a banner pane,
  do nothing. Otherwise:
  1. Verify the window is a worktree window (has `@wt_num`/`@wt_title`/`@wt_branch`);
     if not, print a short message and exit non-zero.
  2. Record the current active pane id (the "main" pane).
  3. `tmux split-window -vb -l 3 -t <main>` to create a 3-row pane **above** it,
     running `tmux-worktree-notice render <main-pane-id>`.
  4. `tmux set-option -p -t <banner-pane> @wt_banner 1` to mark it.
  5. `tmux select-pane -t <main>` to return focus, so `prefix h/j/k/l` start from the
     main pane.

- **`hide [target-window]`** — find the pane flagged `@wt_banner 1` in the window
  (`tmux list-panes -F '#{pane_id} #{@wt_banner}'`) and `kill-pane` it. No-op if none.

- **`toggle [target-window]`** — `hide` if a banner pane is present, else `show`.
  Defaults to the active window. In a non-worktree window, prints a brief message.

### 2. `.tmux.conf` changes

- **Keybinding** (prefix is `C-b`; `b` is currently unbound):
  ```tmux
  bind b run-shell '~/bin/tmux-worktree-notice toggle'
  ```
- **Tab marker** — extend `window-status-format` (line 139) with a conditional on
  `@wt_branch` (mirroring the existing `@claude_waiting` conditional) so worktree
  window tabs carry a leading glyph (`⧉`). `@wt_branch` is stamped for *every*
  worktree window (issue and issue-less), so this covers all of them. The
  `@claude_waiting` styling takes precedence when both are set.
  `window-status-current-format` (line 147) gets the same glyph so the marker is
  visible whether or not the worktree window is the active one.

### 3. `.functions` changes

`_cwork_launch` is the single launch path for both `cwork` and `cpull`. Two changes:

1. **Widen the signature** to receive issue context:
   `_cwork_launch <worktree> <branch> <foreground 0|1> <prompt> [num] [title]`.
   - `cwork` call site (line 505) passes `"$num" "$title"`.
   - `cpull` call site (line 654) passes `"$num" "$title"` (`num` is
     `${issue_num:-$pr_num}`; both are in scope).
   - Foreground mode (`-f`) ignores num/title — no tmux window exists.

2. **Stamp + show** in each tmux branch of `_cwork_launch`. Capture the new window id
   with `-P -F '#{window_id}'`, set the three options on it, then show the banner:
   ```zsh
   wid=$(tmux new-window -d -P -F '#{window_id}' -n "$win" "$cmd")
   tmux set-option -w -t "$wid" @wt_num    "$num"
   tmux set-option -w -t "$wid" @wt_title  "$title"
   tmux set-option -w -t "$wid" @wt_branch "$branch"
   tmux-worktree-notice show "$wid"
   ```
   The same applies to the out-of-tmux path (`new-session` / `new-window -t "$sess"`),
   stamping before `tmux attach`.

## Data flow

```
cwork/cpull  ──(num,title,branch)──▶  _cwork_launch
   _cwork_launch  ──set-option @wt_*──▶  new tmux window
   _cwork_launch  ──show──▶  tmux-worktree-notice show
        show  ──split-window-▶ banner pane runs: tmux-worktree-notice render
        render  ──show-options @wt_*──▶  draws the box from the window's options
prefix b  ──▶  tmux-worktree-notice toggle  ──▶  hide/show on the active window
```

## Edge cases

- **Issue-less worktree (`cwork -B`)**: `@wt_num`/`@wt_title` empty, `@wt_branch` set.
  Box heading falls back to the branch name; body shows `(issue-less worktree)`.
- **`cpull` branch mode with extractable issue**: already populates `num`/`title`;
  behaves like the issue case.
- **Main pane exits** (claude + shell quit): `render` notices the main pane id is gone
  within ~5s and exits, so the window closes normally instead of lingering as a lone
  banner.
- **Resize**: `render` redraws on `SIGWINCH`; the box re-fits the new pane width.
- **Toggle in a non-worktree window**: brief "not a worktree window" message, no split.
- **show called twice / double-show**: idempotent — existing banner pane is detected
  and left alone.
- **Window split by the user**: the banner is a top pane; the user's splits sit below
  it as normal. `hide` removes only the `@wt_banner`-flagged pane.

## Verification (manual — this is a dotfiles repo, no test harness)

1. `tmux source ~/.tmux.conf`.
2. `cwork <some open issue#>` → new window opens with the boxed notice at the top
   showing `#<num>` and the title; focus is in the main (claude) pane; the tab shows
   the `⧉` marker.
3. `prefix b` hides the box; `prefix b` again restores it (rebuilt from options).
4. Resize the pane/terminal → box re-fits width.
5. Exit claude and the shell in the main pane → window closes (no lingering banner).
6. `cwork -B feature/spike` → box shows the branch heading and `(issue-less worktree)`.
7. `cpull <PR#>` → box shows the linked issue (or PR) number and title.
8. In a plain (non-worktree) window, `prefix b` prints the no-op message.

## Files touched

- `bin/tmux-worktree-notice` — new.
- `.tmux.conf` — `bind b`, tab-marker conditionals in `window-status-format` and
  `window-status-current-format`.
- `.functions` — `_cwork_launch` signature + stamping; `cwork`/`cpull` call sites.
- `CLAUDE.md` — add `tmux-worktree-notice` to the `bin/` utility-scripts list.
