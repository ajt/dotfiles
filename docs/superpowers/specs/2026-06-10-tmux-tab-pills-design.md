# tmux tab pills — design

Date: 2026-06-10. Choices made interactively via live tmux demos (placement,
subagent spinner, dressing, pill shade ladder).

## Goal

Make window tabs more beautiful: pill-shaped tabs, leading status glyph, an
animated subagent indicator, and a distinct error state.

## Tab anatomy

Every background tab is a rounded pill drawn with Nerd Font half-circle caps
(U+E0B6 left, U+E0B4 right):

    (<glyph> <#I> <title>)        glyph leads; pill caps shown as parens

- Pill background `#343434` (chosen from a live shade ladder; `#1c1c1c` was
  not distinct enough against the `#080808` bar), text `#9e9e9e`.
- Title is Claude's live `pane_title` (spinner prefix stripped, =20) while a
  Claude state is set, else `window_name` (=14). Unchanged from today.
- Windows with no state render the pill with a single leading space, no glyph.
- `window-status-separator` is one space on the bar background; the dim `│`
  goes away.
- Current window: the same pill in `#00afff` with black bold text and the
  glyph keeping its state color, replacing the pointed powerline arrows.
- The worktree `⧉` marker stays, after the glyph.

Mechanism note: `window-status-style` becomes `fg=#9e9e9e,bg=#343434` so the
`#[default]` resets inside `@claude_tab` fragments resolve to pill colors; the
caps and separator set explicit `bg` so the bar background shows between
pills. The loud states (waiting, error) override with explicit fills.

## State → visual map

| state      | glyph                                   | pill            |
|------------|-----------------------------------------|-----------------|
| working    | cyan `#00d7d7` braille spinner (animated) | dark `#343434` |
| subagent   | purple `#af5fff` pie spinner, NF circle slices U+F0A9E–U+F0AA5 (animated) | dark |
| compacting | grey refresh icon U+F021 (static)        | dark            |
| done       | green check U+F00C (static)              | dark            |
| waiting    | question icon U+F128, black bold text    | orange `#ff8700` fill |
| error      | times icon U+F00D, `#e4e4e4` bold text   | red `#d70000` fill |
| idle/none  | none                                     | dark            |

`error` is new: `StopFailure` (turn ended on an API error) maps to it instead
of folding into `done`. Like `done`, it is acknowledged back to idle by the
pane-focus hooks (condition extends to `done` OR `error`); the `Idle` event
still leaves it alone.

## Animator

The single self-terminating animator loop additionally cycles
`@claude_spinner2` through the 8 pie frames each tick (one tmux call sets both
spinner options plus the refresh), and runs while any window is `working` OR
`subagent` (previously working-only). Ownership claim, 0.25 s tick, and
exit-when-quiet behavior unchanged.

## Out of scope

State machine events, gc liveness logic, status-left/right segments, colors of
the left/right bar segments.

## Testing

- TDD in `tests/claude-tmux-state.test.sh`: subagent fragment references
  `@claude_spinner2`; `StopFailure` → `error`; error fragment; animator runs
  for subagent-only state and exits when neither busy state remains.
- Pill formats are tmux config: verified live (source, render expansion,
  visual check), as established in this repo.
