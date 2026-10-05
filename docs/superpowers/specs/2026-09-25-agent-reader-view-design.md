# Agent reader view — design

Date: 2026-09-25. Started as "clipboard → pandoc → browser" for terminal
selections; reworked around the agents' own transcripts once it was clear
those hold the original Markdown (verified in a Claude Code transcript here
and by Codex on the other machine).

## Goal

One keystroke turns an AI agent's reply — long, wrapped, glyph-prefixed,
box-drawn tables — into a clean, readable HTML page in the browser.

## Why not parse the terminal

Both TUIs render Markdown destructively. Claude Code draws tables as
`┌─┬─┐` grids and prefixes every block with `⏺`; Codex draws tables as
space-aligned columns under a `━━━` rule and stacks them into key/value
records at narrow widths, which is unrecoverable. Meanwhile both write every
assistant message to a JSONL transcript as the raw Markdown they generated:

| tool        | transcript                                            | reply record |
|-------------|-------------------------------------------------------|--------------|
| Claude Code | `~/.claude/projects/<slug>/<session>.jsonl`           | `type: assistant`, `message.content[].type == text` |
| Codex       | `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl` | `type: response_item`, `payload.role == assistant`, `payload.phase == final_answer` |

So the primary path reads the transcript and never cleans anything.

## Pieces (`bin/`)

- `reader-render` — Markdown on stdin → standalone HTML5 via pandoc
  (`gfm-raw_html` so stray `<tags>` stay visible; `pagetitle` so no heading is
  injected), reader CSS included in the head (46rem column, 19px Georgia at
  1.7, sans headings, mono code with scroll, bordered tables, dark mode via
  `prefers-color-scheme`), written to `/tmp/reader-<timestamp>.html` and
  `open`ed. Sets its own PATH: it runs from Automator and tmux, not a shell rc.
- `reader-last TRANSCRIPT [-n N] [--all]` — prints the last turn's final
  reply as Markdown. Detects the format from the records, not the path. For
  Claude Code a turn's reply is the last text block before the next real user
  prompt (tool_result records are not prompts; sidechain/meta/API-error
  records are skipped). For Codex it is the last `final_answer` message, with
  commentary as the fallback when no final has landed yet.
- `reader-clean` — the clipboard fallback: ANSI/trailing whitespace, shared
  indent and the `⏺` hanging indent removed; box tables (Claude) and rule
  tables (Codex, column spans taken from the `━` runs) rewritten as pipe
  tables; single-column boxes treated as banners, not tables; `⏺` dropped,
  `•`/`⎿` → `- ` (except a column-0 `•` whose hanging block spans several
  paragraphs, which is Codex's message marker and is dropped like `⏺`),
  `❯` → `> `; edge bars stripped; all of it outside fences only.
- `clip-reader` — `pbpaste | reader-clean | reader-render`, with a
  notification when the clipboard is empty or pandoc is missing.
- `codex-tmux-hook` — Codex Stop hook, wired by `codex/hooks.json`, which
  `symlink-setup.sh` links to `~/.codex/hooks.json` (live-synced, like
  `.tmux.conf`; `config.toml` stays per-machine and untouched).

## Wiring

- **Transcript on the window.** Every Claude Code hook payload carries
  `transcript_path`; `claude-tmux-state` now reads stdin on SessionStart,
  UserPromptSubmit and Stop and stores it as `@agent_transcript` on the
  window. It is deliberately not cleared on SessionEnd or by gc: the file
  outlives the session, so the last reply stays readable after `/exit`; the
  next SessionStart on that window overwrites it.
  `codex-tmux-hook` does the same from the Codex Stop payload, falling back to
  `CODEX_THREAD_ID` to locate the rollout file. Codex's `notify` setting is
  deliberately not used: it is single-slot and already taken on the other
  machine by the Computer Use app.
- **`prefix R`** — `reader-last "#{@agent_transcript}" | reader-render`,
  with a status-line message when the window has no transcript. A tmux
  binding fires in any terminal; nothing depends on macOS Services.
- **Quick Action "Open in Reader"** (`services/`, symlinked by
  `symlink-setup.sh`) — no-input service running `~/bin/clip-reader`, for
  selections and non-agent output. Shortcut: System Settings → Keyboard →
  Keyboard Shortcuts… → Services → General → Open in Reader. `⌃⌥⌘R` collides
  with nothing in Ghostty, Claude Code, Codex or the karabiner rules.

## Not done / verify on the Codex machine

- Codex reported hooks.json Stop support from documentation, not execution.
  Confirm a Stop hook fires on 0.157 (it may need `[features] codex_hooks =
  true` in `config.toml`), that `TMUX_PANE` is in its environment, and that
  `transcript_path` is non-null (else the env-var fallback runs).
- `reader-clean` is heuristic by nature. Known losses: a titled box
  (`┌── title ──┐`) drops its title; a cell row copied with side-panel text
  after the closing `│` gains a stray cell; Codex's narrow-width stacked
  tables pass through as-is.
- `reader-clean`'s Codex rule-table branch is built from Codex's renderer
  constants (`TABLE_HEADER_SEPARATOR_CHAR = '━'`, gap 2, padding 1), not from
  a live copy. Check one real table.

## Page styling and the Style panel (2026-10-05)

The rendered page now mimics the Clearly Reader extension: a white article
card (`max-width` 1200px) on a grey page, monospace body at 25px / 1.6, bold
monospace headings, a grey meta line (source · reading time · word count ·
render time), an outline in the left gutter, and a right rail with an `Aa`
button that opens a Style panel, a fullscreen button and a reading-time dial
that fills as you scroll. The pieces live in `bin/reader-view/`:

- `template.html` — the pandoc template (page skeleton; `$body$` goes into
  `#content`, a leading `<h1>` is promoted to the document title).
- `style.css` — layout and the three themes (`default`, `dark`, `sepia`),
  driven by CSS custom properties the panel sets.
- `app.js` — the panel, outline, dial, reading position, bionic reading and
  highlights. Included at the end of `<body>` via pandoc `-A`.

`reader-render` passes the content hash (`-V dochash`), the `-t` title as the
source (`-M source`) and the render time; `-t` now also feeds the meta line,
so the tmux binding passes `-t "Agent reply"` and `clip-reader` `-t Clipboard`.

### Settings (persisted in `localStorage`, key `reader.settings`)

Every file:// page shares one origin in Chrome and Safari, so a change made on
one rendered reply applies to the next. Mirrors Clearly's panel: Font Size,
Line Height, Letter Spacing, Max Width (steppers); Text Align; Outline, Show
Video, Show Photo, Bionic Reading (toggles); Font Family (monospace /
sans-serif / serif / system); Follow System Theme; Theme (Default / Dark /
Sepia); Inline Code (subtle grey / tinted red / bordered grey / outlined red
/ accent blue / inverted pill, via `[data-code]` with per-theme tint colours);
Remember reading position; Show reading time dial; Enable
Highlighting; Show highlights on page; Show highlight page marks. Keyboard:
`s` toggles the panel, `f` fullscreen, `Esc` closes.

Per-machine defaults: `~/.config/reader/settings.json` (or `$READER_SETTINGS`)
is validated and embedded as `window.READER_DEFAULTS`; the panel's "Show
settings JSON" button prints the current settings to save there. Precedence:
built-in defaults < seed file < localStorage. "Reset to defaults" resets to
the seed.

Reading position (`reader.pos.<hash>`) and highlights (`reader.hl.<hash>`) are
keyed by the SHA-1 of the Markdown, so re-rendering the same reply finds them.
Highlights are stored as character offsets into `#content`'s text, which is
stable across bionic on/off; page marks are one tick per highlight in a fixed
track at the right edge. Select text to get a "Highlight" popover; click a
highlight for "Remove highlight".

Not mirrored: Clearly's Layout dropdown (locked in the screenshot; Max Width
covers it), Auto Spacing (CJK/Latin spacing, no use here), AI/speech/translate.

## Clipboard lookup in the transcripts (2026-10-05)

Text copied out of the TUI has lost its Markdown, and `reader-clean` can only
recover structure, not bold or code spans. `clip-reader` now tries
`bin/reader-match` first: it normalises the copied text and every assistant
text block in the transcripts modified in the last 30 days (newest first;
markup, glyphs, box characters and whitespace dropped, lowercase) and prints
the original Markdown of the newest block containing the copy — or the whole
turn when the copy spans several blocks. A ragged first/last line is tolerated
by also trying the copy with 60 characters trimmed at each end. `--label`
prefixes the output with "Claude Code" or "Codex", which `clip-reader` passes
to `reader-render -t` so the meta line names the source. No match → exit 1 →
the `reader-clean` fallback as before (source "Clipboard"). It imports
`reader-last` for the JSONL reader and format detection.

## Speed reading (2026-10-05)

An RSVP overlay after SwiftRead (rapid serial visual presentation: one chunk
at a time at a fixed point). The rail's bolt button or `r` opens it starting
at the first block in view; `Esc` (or `r`) closes it and jumps the page to the
block you stopped in, outlined for a moment, so the normal reading-position
memory resumes there next time.

- **Display.** Serif word centred on a dark field; the focus letter (optimal
  recognition point: index 0/1/2/3/4 for lengths 1/2-5/6-9/10-13/14+) is
  tinted red with a tick above and below. Inline code is shown whole, in mono.
  A multi-line code block or table becomes a *slide*: the reader pauses and
  shows it until you press space or Continue ("Pause and show code blocks";
  off = skipped). Progress bar, "n / total · m:ss left" and the wpm label.
- **Controls.** −10 / previous sentence / play-pause / next sentence / +10,
  as in SwiftRead; keys space, ←/→, ↑/↓ (or +/−), Esc; click the stage to
  pause.
- **Timing.** Base dwell 60000/wpm per word (a chunk of N words dwells N×),
  then micro-pauses: long words (≥9 chars) ×1.3, numbers ×1.4, clause
  punctuation ×1.5, sentence end ×2, paragraph end ×2 / heading ×2.5, inline
  code + min(len,48)/16 words. Chunks never cross a sentence or clause end, an
  inline code span, or a block boundary.
- **Settings** (panel section "Speed reading", persisted like the rest):
  Speed 100–1200 wpm step 10 (default 320), Words at a time 1–3, Font size,
  Font (serif / sans-serif / monospace / same as page), Theme (Dark / Light /
  Same as page), Focus marks, Focus letter, Pause on long words / numbers /
  punctuation / paragraphs, Pause and show code blocks. Changing a setting
  mid-read rebuilds the chunks at the same block; the panel sits above the
  overlay.

Left out on purpose: text-to-speech, SwiftRead's Warm/Calm/Matrix themes and
the pixel-based Focus Span.
