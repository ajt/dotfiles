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
  `•`/`⎿` → `- `, `❯` → `> `; edge bars stripped; all of it outside fences only.
- `clip-reader` — `pbpaste | reader-clean | reader-render`, with a
  notification when the clipboard is empty or pandoc is missing.
- `codex-tmux-hook` — Codex Stop hook (template in `codex/hooks.example.json`).

## Wiring

- **Transcript on the window.** Every Claude Code hook payload carries
  `transcript_path`; `claude-tmux-state` now reads stdin on SessionStart,
  UserPromptSubmit and Stop and stores it as `@agent_transcript` on the
  window (cleared with the other `@claude_*` options on SessionEnd and by gc).
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
  Confirm a Stop hook fires on 0.157, that `TMUX_PANE` is in its environment,
  and that `transcript_path` is non-null (else the env-var fallback runs).
- `reader-clean`'s Codex rule-table branch is built from Codex's renderer
  constants (`TABLE_HEADER_SEPARATOR_CHAR = '━'`, gap 2, padding 1), not from
  a live copy. Check one real table.
