# Per-tab Claude state indicator — design

**Date:** 2026-06-03
**Status:** Approved (design), pending implementation
**Related:** issue #2 (optional focus-clear enhancement, deferred)

## Goal

Make tmux window tabs report what Claude Code is doing in each window at a
glance, so background sessions are legible from the status bar: which are
working, which are running subagents, which are compacting, which **need you**,
and which have **finished**.

## Background — what exists today

`~/.claude/settings.json` already drives a single binary signal via tmux window
options:

- Hooks `UserPromptSubmit`, `PreToolUse`, `Stop`, `SessionEnd` set
  `@claude_waiting 0`; `Notification` sets `@claude_waiting 1`.
- `.tmux.conf` `window-status-format` floods the whole tab orange when
  `@claude_waiting` is set.

This distinguishes only "Claude is asking me something" vs. everything else.
"Busy working" and "done, ready for review" look identical.

### Key mechanism (confirmed working)

`$TMUX_PANE` **is** inherited by hook subprocesses: tmux exports it into the
pane shell, `claude` inherits it, and hook commands inherit it from `claude`.
`tmux set-option -w -t "$TMUX_PANE" …` resolves the pane to its current window,
so a hook always targets the right tab. (Verified by the existing
`@claude_waiting` wiring.) Falls back gracefully — outside tmux the option set
is a no-op.

Installed version at design time: `claude 2.1.161`, which supports all hook
events used here (`SubagentStart`, `SubagentStop`, `PreCompact` confirmed in the
changelog alongside the core events).

## States

| State | Meaning | Trigger |
|------|---------|---------|
| `working` | actively processing a turn | `UserPromptSubmit`; `PreToolUse` (no subagents active) |
| `subagent` | one or more subagents running | `SubagentStart` / `SubagentStop` while depth > 0 |
| `compacting` | context compaction in progress | `PreCompact` |
| `waiting` | **needs you** — question / permission / idle nudge | `Notification` |
| `done` | finished a turn, ready for review | `Stop` |
| `idle` | session alive, nothing happening | `SessionStart` (or unset) |

State is stored in tmux **window options** (no temp files):

- `@claude_state` — current state string (unset ≡ `idle`)
- `@claude_subagents` — integer subagent-depth counter

## Architecture

A single helper script `bin/claude-tmux-state <HookEventName>` is the brain.
Every relevant Claude hook calls it; it maps the event to a state, maintains the
subagent counter, writes `@claude_state` on the window owning `$TMUX_PANE`, and
runs `tmux refresh-client -S`. Rationale: the subagent counter + precedence
rules are too much for inline one-liners, and a `bin/` script matches the repo
convention (`tmux-worktree-notice`, `tmux-status.sh`).

### Helper contract

- Input: hook event name as `$1`. (Does not need to read stdin JSON.)
- Reads `$TMUX` / `$TMUX_PANE`; if either is empty, exits 0 immediately.
- Every `tmux` call is suffixed `2>/dev/null` and the script always exits 0, so
  a hook can never block or fail Claude.
- Sanitizes the counter (non-numeric → 0).

### Event → action

| Hook event ($1) | Action |
|---|---|
| `SessionStart` | counter = 0; state = `idle` |
| `UserPromptSubmit` | counter = 0; state = `working` |
| `PreToolUse` | counter > 0 → `subagent`, else `working` (also clears `waiting` the instant a permission is approved) |
| `Notification` | state = `waiting` |
| `SubagentStart` | counter++; state = `subagent` |
| `SubagentStop` | counter-- (floor 0); counter > 0 → `subagent`, else `working` |
| `PreCompact` | state = `compacting` |
| `Stop` | counter = 0; state = `done` |
| `SessionEnd` | unset both options |
| anything else | exit 0 |

After any state change, `tmux refresh-client -S` so the bar repaints
immediately (`status-interval 10` remains the fallback).

### Deliberately dropped hooks

- **`PostToolUse`** — `PreToolUse` already fires on every tool and sets
  `working`/`subagent`; adding `PostToolUse` would roughly double hook overhead
  for no new information.
- **`PostCompact`** — `compacting` is cleared by the next `PreToolUse`/`Stop`.
  Known edge: a manual `/compact` while idle leaves the tab grey until the next
  prompt. Accepted.

`UserPromptSubmit` and `Stop` reset the counter to 0, which self-heals any
leaked count from a missed `SubagentStop`.

## Subagent detection — limits (accepted)

Subagent tool calls fire `PreToolUse` in the same pane with the same
`$TMUX_PANE`, so without a counter every subagent tool would flip the tab back
to `working`. The counter keeps `subagent` shown while depth > 0.

Accepted imperfections (status glyph, not mission-critical):

1. **Parallel-start race.** Concurrent `SubagentStart` hooks do a
   read-modify-write on the counter option and can undercount, ending the
   `subagent` state slightly early (shows `working`). Self-heals at next
   `UserPromptSubmit`/`Stop`. No `flock` — not worth it for a tab glyph.
2. **Brief cyan flash** when the main agent spawns a subagent:
   `PreToolUse(Task)` (counter 0 → `working`) fires a beat before
   `SubagentStart` (→ `subagent`). Sub-second.

## Visual design

Background tabs only. The **focused** tab keeps its clean blue powerline
(`window-status-current-format`, line ~150, unchanged) — you can see Claude
directly there, and this avoids `working`/`done` churning on the tab you are
watching.

**Tiered loudness:** `waiting` keeps the loud full-tab orange fill (the only
action-required state); the informational states are quiet — a colored left bar
`▎` + glyph on the normal dark background. The worktree marker `⧉` is preserved.

| State | Glyph | Color | Treatment |
|---|---|---|---|
| working | `◐` | `#00d7d7` cyan | quiet (bar + glyph) |
| subagent | `⊕` | `#af5fff` purple | quiet |
| compacting | `⟳` | `#8a8a8a` grey | quiet |
| **waiting** | `?` | `#ff8700` orange | **loud (full-tab fill)** |
| done | `✓` | `#00d700` green | quiet |
| idle / unset | — | default | normal dark tab |

`working` is cyan `#00d7d7`, chosen distinct from the active-tab / worktree blue
`#00afff` so "working" never reads as "selected". `waiting` keeps the exact
current orange so it looks unchanged.

Representative background-tab row:

```
▎◐ 2 web   ▎⊕ ⧉ 4 infra   ▎⟳ 5 lib   [ ? 3 docs ]   ▎✓ ⧉ 1 api   ▎ 6 notes
 working    subagent+wt     compacting  needs you       done+wt       idle
```

### tmux render (window-status-format)

Replace the `@claude_waiting` ternary on `.tmux.conf` line 142 with a nested
conditional on `@claude_state` using `#{==:#{@claude_state},<state>}`. One loud
branch (`waiting`, full orange fill, as today but with a `?` glyph), four quiet
branches (`working`/`subagent`/`compacting`/`done` — colored `▎`+glyph then the
default `#{?@wt_branch,⧉ ,}#I name`), and a default branch identical to today's
non-waiting render (`idle`/unset). Exact string finalized during implementation
and verified live.

## Behavioral notes

- **Escalation:** a finished-but-ignored session shows `done` (green) on `Stop`,
  then ~60s later `Notification` (idle nudge) flips it to `waiting` (orange).
  Desirable.
- **Permission approval:** `Notification` → `waiting`; approving runs the tool →
  `PreToolUse` → `working`, clearing the orange.

## Files changed

- `bin/claude-tmux-state` — new helper (symlinked to `$HOME` by existing `bin/`
  symlinking in `symlink-setup.sh`).
- `~/.claude/settings.json` — replace the five inline `@claude_waiting` commands
  with `claude-tmux-state <Event>` calls; add `SessionStart`, `SubagentStart`,
  `SubagentStop`, `PreCompact`. (Outside the dotfiles repo / git-excluded — a
  live edit, not committed here.)
- `.tmux.conf` — swap line 142 (`window-status-format`) to the `@claude_state`
  tiered render. Line ~150 (`window-status-current-format`) unchanged.
- `CLAUDE.md` — one line documenting `claude-tmux-state` under "Utility Scripts".

## Out of scope

- **Focus-clear** (`done` → `idle` on tab focus via `pane-focus-in`): deferred to
  issue #2. The helper does **not** include a `focus` verb in this work.
- Animated/spinner glyphs: the status bar only repaints on hook events /
  `status-interval`, so `working` is a static glyph by design.
- Statusline integration: per-session, in-pane, post-message only — wrong tool
  for cross-window tab state.

## Testing

- `claude-tmux-state` outside tmux: exits 0, no error.
- Each event sets the expected `@claude_state` (assert via `tmux show-options
  -wqv`), counter arithmetic floors at 0, `SessionEnd` unsets both.
- Live: drive a real Claude session and confirm tab transitions
  working → (subagent) → done, a `Notification` shows orange, and the focused
  tab stays blue.
