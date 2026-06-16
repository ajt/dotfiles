# tmux background-worker tab indicator — design

Date: 2026-06-16. Approved interactively.

## Problem

When a Claude turn ends but a background bash task (`run_in_background`) is
still running, the window tab shows `done` (green ✓) / `idle` / `waiting` — it
looks finished, hiding that the window is still doing work. The user wants a
distinct, animated indicator for "turn over, but a background worker is still
running."

## Constraints (from research)

- **No hook fires when a background bash task completes** — so reverting the
  indicator can't be hook-driven; it must be polled.
- On this machine/version a background task is a **live descendant of `claude`**:
  `claude → /bin/zsh -c 'source …/.claude/shell-snapshots/snapshot-… && … eval
  "<cmd>"' → <cmd>`. (Some Claude builds reparent to PID 1; see Caveats.)
- The wrapper's argv reliably contains the signature **`shell-snapshots/snapshot`**,
  which distinguishes a Bash-tool shell from MCP servers / subagents / other
  persistent `claude` children.
- `status-interval` is **10s** and `#(~/bin/claude-tmux-state gc)` already runs
  on that tick — a ready-made polling hook.

## Design — an overlay flag, not a new state

Add a per-window option **`@claude_bg`** (set to `1` or unset). Background is a
*rendering overlay*: the real `@claude_state` (done/idle/waiting) is left intact,
so revert is automatic when the flag clears. Nothing stashes or restores state.

### 1. Detection — extend `gc` (`bin/claude-tmux-state`)

`gc` already iterates windows carrying `@claude_pane`, clears dead ones, and
keeps live ones. After the existing alive-check, for each **live** window whose
`@claude_state ∈ {done, idle, waiting}`:

- Set `@claude_bg=1` iff some live process whose command (full argv) contains
  `shell-snapshots/snapshot` is a **descendant of that window's `pane_pid`**;
  otherwise unset `@claude_bg`.
- Windows that are `working`/`subagent`/`compacting` (turn active) or have no
  live claude are left with `@claude_bg` unset — they already animate or are
  gone. `error` is NOT overridden (a failed turn must stay red).
- When `gc` sets `@claude_bg=1`, it calls `ensure_animator` so the spinner runs.

Implementation notes: `gc` already loads `ps`; extend it to capture
`pid ppid command` (currently `ppid comm`). Find candidate processes by the
signature, then walk each candidate's `ppid` chain to test whether `pane_pid`
is an ancestor (descendant test). Few candidates exist, so this is cheap. Order:
do the dead-claude clear first; only run bg-detection for windows kept alive.
Add `@claude_bg` to the set of options the dead-claude branch unsets.

### 2. Rendering — `@claude_bg` takes precedence in both window-status formats

`.tmux.conf`: wrap each format with an `@claude_bg` branch that renders a blue
(`#5fafff`) braille spinner pill, overriding the underlying state's visual.

- `window-status-format` (background tabs): when `@claude_bg`, render the dark
  pill + blue glyph:
  `#[default] #[fg=#5fafff]#{@claude_spinner}#[default] #I <title> ` — else the
  existing expression unchanged.
- `window-status-current-format` (current window): when `@claude_bg`, render the
  blue fill + black glyph:
  `#[fg=#000000]#[bg=#5fafff]#[bold] #{@claude_spinner} #I <title> ` — else the
  existing expression unchanged.

`<title>` is the existing `#{s/^[^a-zA-Z0-9] //;=20:pane_title}`. Reuses the
shared `@claude_spinner` (braille) so the blue spinner animates in lockstep with
foreground `working`; the only visible difference from `working` is the hue.
No `_tab_for`/`_glyph_for`/`_color_for` entries are needed (the formats render
the overlay inline).

### 3. Animator — stay alive while any window is backgrounded

`animate`'s run/exit condition (currently matches `working|subagent|compacting`)
must also keep cycling while any window has `@claude_bg=1`. Change the probe to
e.g. `tmux list-windows -a -F '#{@claude_state} bg=#{@claude_bg}'` and match
`*working*|*subagent*|*compacting*|*bg=1*`. `@claude_spinner` is already what the
blue overlay renders, so no new spinner option is needed.

### 4. Hooks clear the overlay

`set_state` unsets `@claude_bg` whenever a hook sets a real state, so resuming
activity (UserPromptSubmit → `working`) instantly drops the overlay; `gc`
re-sets it on the next tick if a task still runs after a turn ends. `clear_all`
(SessionEnd) unsets `@claude_bg` too. (A ≤10s flicker showing `done` after a
turn ends before `gc` flips to background is acceptable.)

### 5. Precedence (user's choice)

Background overrides `done`, `idle`, AND `waiting` — a churning window always
reads active. Accepted trade-off: a genuine permission/question prompt is
visually masked while a task runs. `error` is not overridden.

## Caveats

- **Detection assumes the background task is a live descendant of the pane's
  process tree** (confirmed here). If a future Claude Code build detaches
  background processes to PID 1, detection silently stops; the test pins the
  current assumption so a regression surfaces.
- **~10s latency** (the status tick) to appear and to clear.
- The signature `shell-snapshots/snapshot` is how Bash-tool shells are
  identified on this setup; it also matches foreground tool shells, which is why
  detection only runs for turn-ended windows.

## Testing (extend `tests/claude-tmux-state.test.sh`, real-process style)

Mirror the existing gc tests (real panes + real child processes, `tmux` shim):

- **sets the flag:** a window with `@claude_state=done` whose `pane_pid` has a
  live descendant whose argv contains `shell-snapshots/snapshot` (e.g. run a
  helper script created under a `…/shell-snapshots/snapshot…` path) → `gc` sets
  `@claude_bg=1`.
- **clears the flag:** once that descendant exits → `gc` unsets `@claude_bg`.
- **no false positive:** a turn-ended window whose only descendant is a non-
  matching process (MCP-like, e.g. a plain `sleep`) → `@claude_bg` stays unset.
- **skips active turns:** a `working` window with a matching descendant →
  `@claude_bg` stays unset.
- **animator:** stays alive (claims `@claude_spinner_pid`, cycles
  `@claude_spinner`) for a window that has only `@claude_bg=1` (no working
  window), and exits once it clears.
- **hooks clear it:** after `@claude_bg=1`, a `UserPromptSubmit` (→working)
  unsets `@claude_bg`.
- **dead-claude clear:** the dead-pane branch also unsets `@claude_bg`.

Formats are tmux config — verified live (source + visual check), per repo
convention.

## Implementation steps (TDD — test first for each)

1. **`tests/claude-tmux-state.test.sh`** — add the cases above (real panes +
   descendant processes carrying the signature).
2. **`bin/claude-tmux-state`** — `gc` bg-detection (capture `pid ppid command`,
   signature + descendant-of-pane_pid test, set/unset `@claude_bg`,
   `ensure_animator` on set, add `@claude_bg` to the dead-claude unset list);
   `set_state`/`clear_all` unset `@claude_bg`; extend the `animate` run/exit
   condition with `bg=1`.
3. **`.tmux.conf`** — wrap `window-status-format` and
   `window-status-current-format` with the `@claude_bg` precedence branch.
4. Run `bash tests/run.sh` green; source `~/.tmux.conf` and visually confirm a
   background task flips the tab to the blue spinner and reverts when it ends.

## Deploy (after merge to main)

`bin/` and `.tmux.conf` are symlinked from the main checkout, so the script is
live on the next hook/gc tick; run `tmux source-file ~/.tmux.conf` to load the
format changes into the running server.
