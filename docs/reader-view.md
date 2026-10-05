# Reader view

Open an AI agent's reply (or anything you copied) as a clean, readable page
in the browser, styled after the Clearly Reader extension, with a persistent
Style panel, highlights, and a SwiftRead-style speed reader.

Design notes: [`superpowers/specs/2026-09-25-agent-reader-view-design.md`](superpowers/specs/2026-09-25-agent-reader-view-design.md).

## Opening a page

| From | Do this | What is rendered |
|---|---|---|
| tmux, in a Claude Code or Codex window | `prefix R` | the last reply, from the agent's transcript (lossless) |
| tmux, after copying text | `prefix C-r` | the copy, looked up in the transcripts so the original Markdown is used; otherwise cleaned up as well as possible |
| anywhere, after copying text | the **Open in Reader** Quick Action (give it a global shortcut, see below) | same as `prefix C-r` |
| a shell | `reader-render < notes.md`, `pbpaste \| reader-clean \| reader-render`, `reader-last TRANSCRIPT \| reader-render` | the Markdown on stdin |

Every route ends in `reader-render`, which writes `/tmp/reader-<timestamp>.html`
and opens it in the default browser. `-t TITLE` sets the tab title and the
source shown in the meta line; `-n` prints the path without opening; `-o FILE`
chooses the output path.

**Shortcut for the Quick Action:** System Settings → Keyboard → Keyboard
Shortcuts… → Services → General → *Open in Reader*. `⌃⌥⌘R` is free in Ghostty,
Claude Code, Codex and the karabiner rules. Nothing about the Quick Action
needs a right-click: copy by any means (tmux copy mode, Option-drag, `⌘C`;
Ghostty copies a selection to the clipboard as you make it), then press the
shortcut. **Apps learn Services shortcuts when they launch**, so after
assigning or changing one, quit and reopen the app you press it in (tmux
sessions survive a Ghostty restart: reattach with `tmux a`). Until then the
key just reaches the app, which in a terminal clears the selection and does
nothing else. Inside tmux, `prefix C-r` does the same job with no Services
involvement.

### Copied text keeps its formatting

Text copied out of the Claude Code or Codex terminal UI has lost its Markdown:
bold is just bold, code spans are plain, tables are box drawings. `clip-reader`
therefore runs `reader-match` first, which normalises the copy and searches the
transcripts modified in the last 30 days (newest first) for the assistant
message that contains it, and renders that message's original Markdown. A
partial copy, or one with a stray first or last line, still matches. The meta
line then says *Claude Code* or *Codex*; when nothing matches it falls back to
`reader-clean` and says *Clipboard*.

## The page

A white article card on a grey page, monospace at 25px by default. A leading
`# Heading` becomes the document title. The meta line shows source, reading
time, word count and render time. Headings are listed in an outline in the
left gutter (the current one is tracked while you scroll). The right rail has:

| Button | Key | Does |
|---|---|---|
| `Aa` | `s` | opens the Style panel |
| ⛶ | `f` | fullscreen |
| ⚡ | `r` | speed reader (below) |
| dial | | reading progress and minutes left; click to go to the top |

`Esc` closes the panel. Select text to get a **Highlight** popover; click a
highlight to remove it. Highlights also appear as small ticks at the right
edge of the window.

## Style panel

Everything in the panel is saved in the browser's `localStorage` (one origin
for all file:// pages in Chrome and Safari), so a change made on one rendered
reply applies to every page after it.

| Setting | Options |
|---|---|
| Font Size / Line Height / Letter Spacing / Max Width | steppers |
| Text Align | left, centre, right, justify |
| Outline | show the heading outline |
| Show Video / Show Photo | show embedded media |
| Bionic Reading | bold the first part of each word |
| Font Family | monospace, sans-serif, serif, system |
| Inline Code | subtle grey, tinted red, bordered grey, outlined red, accent blue, inverted pill |
| Wrap code blocks | wrap long lines in code blocks to the column instead of scrolling sideways; every code block also has a small *wrap* / *unwrap* button in its bottom-right corner that overrides this for that block (for long text output that is not really code) |
| Follow System Theme | dark when macOS is dark |
| Theme | Default, Dark, Sepia |
| Remember reading position | return to where you were on the same document |
| Show reading time dial | the dial in the rail |
| Enable Highlighting / Show highlights on page / Show highlight page marks | highlights |
| Speed reading section | see below |

**Reset to defaults** and **Show settings JSON** are at the bottom.

### Defaults on every machine

The browser store is per machine and per browser. To seed the same defaults
everywhere, save the JSON the panel shows as `~/.config/reader/settings.json`
(or point `READER_SETTINGS` at a file). `reader-render` validates it and
embeds it; precedence is built-in defaults, then that file, then what you
changed in the panel. *Reset to defaults* resets to the file.

Reading position and highlights are keyed by a hash of the Markdown, so
re-rendering the same reply finds them again.

## Speed reader

Press `r`, or the ⚡ button. The page is replaced by a dark field showing one
word at a time at a fixed point, SwiftRead-style: the focus letter is red,
with a mark above and below it, so your eyes never move. It starts at the
first paragraph in view.

| Control | Key | Does |
|---|---|---|
| −10 / +10 | ↓ / ↑ (or − / +) | speed, in words per minute |
| ↺ / ↻ | ← / → | previous / next sentence |
| ▶ ⏸ | space | play / pause (clicking the word also pauses) |
| × | `Esc` or `r` | exit; the page jumps to the block you stopped in |

A multi-line code block or table **pauses the reader and shows the block**
until you press space or *Continue* (the *Pause and show code blocks* setting;
off skips them). Inline code is shown whole, in monospace, and held longer the
longer it is. The top line shows chunk *n / total*, time left and the speed.

Settings, in the panel's **Speed reading** section, persisted like the rest:

| Setting | Default |
|---|---|
| Speed | 320 wpm, steps of 10, 100–1200 |
| Words at a time | 1 (up to 3) |
| Font size / Font / Theme | 64px, serif, dark (light or same-as-page available) |
| Focus marks / Focus letter | on |
| Pause on long words / numbers / punctuation / paragraphs | on |
| Pause and show code blocks | on |

Changing a setting mid-read rebuilds the sequence at the same place; the
panel opens above the reader.

## Files

| | |
|---|---|
| `bin/reader-render` | Markdown on stdin → styled HTML → browser |
| `bin/reader-view/` | the page: pandoc `template.html`, `style.css`, `app.js` |
| `bin/reader-last` | last reply from a Claude Code or Codex transcript |
| `bin/reader-match` | find copied text in the transcripts, print its Markdown |
| `bin/reader-clean` | lossy clean-up of copied terminal text |
| `bin/clip-reader` | clipboard → `reader-match` or `reader-clean` → `reader-render` |
| `bin/claude-tmux-state`, `bin/codex-tmux-hook` | stamp the transcript path on the tmux window for `prefix R` |
| `services/Open in Reader.workflow` | the Quick Action, linked by `symlink-setup.sh` |

Needs `pandoc` (in `brew.sh`) and the system `python3`. Nothing to install
after a pull: `~/bin` is a link to the directory, and `dotfiles update`
reloads tmux when `.tmux.conf` changes.
