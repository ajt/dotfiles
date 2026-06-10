# tmux tab pills — design

Date: 2026-06-10. Choices made interactively via live tmux demos (placement,
subagent spinner, dressing, pill shade ladder; corner shape revisited the same
day — square won over round/slant/trapezoid in a live four-way demo).

## Goal

Make window tabs more beautiful: pill-shaped tabs, leading status glyph, an
animated subagent indicator, and a distinct error state.

## Tab anatomy

Every background tab is a flat color block with square corners — no cap
glyphs (the NF half-circle caps U+E0B6/U+E0B4 were tried first and dropped):

    [<glyph> <#I> <title>]        glyph leads; block edge shown as brackets

- Pill background `#343434` (chosen from a live shade ladder; `#1c1c1c` was
  not distinct enough against the `#080808` bar), text `#9e9e9e`.
- Title is Claude's live `pane_title` (spinner prefix stripped, =20) while a
  Claude state is set, else `window_name` (=14). Unchanged from today.
- Windows with no state render the pill with a single leading space, no glyph.
- `window-status-separator` is one space on the bar background; the dim `│`
  goes away.
- Current window: the same pill filled with the state's indicator color
  (cyan working, purple subagent, grey compacting, green done, orange waiting,
  red error) and `#00afff` blue when no Claude state. Content is black bold
  (near-white on red); the glyph comes from `@claude_glyph`, an unstyled twin
  of `@claude_tab`, since a pre-colored glyph would vanish into its own fill.
  `@claude_color` carries the fill; the format falls back to blue when unset.
- The worktree `⧉` marker stays, after the glyph.

Mechanism note: `window-status-style` becomes `fg=#9e9e9e,bg=#343434` so the
`#[default]` resets inside `@claude_tab` fragments resolve to pill colors; the
separator sets explicit default `bg` so one bar-colored space shows between
blocks. The loud states
(waiting, error) override with explicit fills. `=20`/`=14` are tmux truncation
modifiers (no padding). Spinner options are tmux-server-global: every session
shares the same frame, so concurrent spinners animate in lockstep by design.

Precedence: the current-window pill takes the state color, so waiting/error
fills show on the current tab too (same hue, black/near-white content instead
of the background tab's colored-glyph-on-dark). Acknowledgment moved to
focus-out only: focusing a done/error window no longer clears it — the green
or red pill stays while you look at it and clears when you move on. Clearing
on focus-in would snap the pill to blue before the color was ever visible.

## State → visual map

| state      | glyph                                   | pill            |
|------------|-----------------------------------------|-----------------|
| working    | cyan `#00d7d7` braille spinner (animated) | dark `#343434` |
| subagent   | purple `#af5fff` pie spinner, NF circle slices U+F0A9E–U+F0AA5 (animated) | dark |
| compacting | grey braille orbit spinner, two dots circling the cell (animated) | dark |
| done       | green check U+F00C (static)              | dark            |
| waiting    | question icon U+F128, black bold text    | orange `#ff8700` fill |
| error      | times icon U+F00D, `#e4e4e4` bold text   | red `#d70000` fill |
| idle/none  | none                                     | dark            |

`error` is new: `StopFailure` (turn ended on an API error) maps to it instead
of folding into `done`. Like `done`, it is acknowledged back to idle by the
pane-focus hooks (condition extends to `done` OR `error`); the `Idle` event
still leaves it alone. Acknowledgment semantics: a red pill on a background
tab persists until you visit that window; an error in the window you are
already watching is visible in the pane itself and its state clears when you
leave. This mirrors `done` and is deliberate.

## Animator

The single self-terminating animator loop cycles `@claude_spinner2` through
the 8 pie frames and `@claude_spinner3` through an 8-frame braille orbit (two
adjacent dots circling the cell — the animated replacement for the static
U+F021 refresh icon) each tick; one tmux call sets all spinner options plus
the refresh. It runs while any window is `working`, `subagent` OR
`compacting`. Ownership claim, 0.25 s tick, and exit-when-quiet behavior
unchanged. Braille was chosen over rotated-icon glyph sets because the orbit
frames are plain Unicode (no PUA lookup risk) and sit centered in the cell.

## Out of scope

State machine events, gc liveness logic, status-left/right segments, colors of
the left/right bar segments.

## Testing

- TDD in `tests/claude-tmux-state.test.sh`: subagent fragment references
  `@claude_spinner2`; `StopFailure` → `error`; error fragment; animator runs
  for subagent-only state and exits when neither busy state remains.
- Pill formats are tmux config: verified live (source, render expansion,
  visual check), as established in this repo.
