# Auto-notice from a Claude session's first prompt

**Date:** 2026-06-03
**Status:** Approved — ready for implementation plan

## Problem

`tmux-worktree-notice` draws a boxed notice at the top of tmux worktree windows.
Today a window only gets a notice if it was created from a GitHub issue via
`cwork`/`cpull`, which stamp the window-level options `@wt_num`, `@wt_title`, and
`@wt_branch`. Any other window — a hand-opened tmux pane where you just run
`claude` — has no notice, and `prefix b` reports *"not a worktree window"*.

We want those windows to get a useful one-line notice too: wait for a Claude
session's first prompt, summarize the ask with a cheap/fast model, and stamp the
window so the existing box renders it.

## Goals

- Auto-generate a one-line notice for **any unstamped tmux window** running
  Claude, derived from the session's **first prompt**.
- Cover both hand-opened windows **and** issue-less `cwork -B` worktrees (which
  currently show the placeholder *"(issue-less worktree)"*).
- Never block the first prompt; never error the window on failure.
- Keep the change small and respect existing boundaries: the renderer stays a
  renderer.

## Non-goals

- Re-summarizing on later prompts (single attempt per window).
- Touching windows that already have a notice, including real GitHub-issue
  windows (`@wt_num` set).
- A polling/transcript-scraping detector (rejected in favor of a hook).

## Architecture

Two cooperating pieces, with a clean seam between **data** and **display**:

1. **New hook script — `bin/claude-tmux-notice`** (tracked, symlinked to `$HOME`
   by `symlink-setup.sh` along with the rest of `bin/`). This is the data
   source. Claude runs it on `UserPromptSubmit`; it decides whether to act,
   obtains the summary, and writes the window's `@wt_*` options.

2. **Existing `bin/tmux-worktree-notice`** stays the pure box renderer. Its
   `render()` needs **no change** — the current logic already produces the right
   box:
   - `heading = "#$num"` when `@wt_num` is set, else `@wt_branch`
   - `body = @wt_title` when set
   So stamping `@wt_branch` + `@wt_title` is all that's required to render the
   desired box. We add only one small subcommand, `refresh`, so an asynchronous
   title update can repaint an already-visible box.

3. **`~/.claude/settings.json`** gets a one-time `UserPromptSubmit` hook entry
   pointing at `claude-tmux-notice`. This is the user's *global* Claude config —
   separate from the `.claude/` directory this repo git-excludes — so it is not
   version-controlled here. The install step is documented in
   `setup-a-new-machine.sh`.

## Data flow (happy path)

1. User opens a plain tmux window, runs `claude`, types the first prompt.
2. Claude fires `UserPromptSubmit`, running `claude-tmux-notice` with hook JSON
   on **stdin** (includes `prompt` and `cwd`) and `$TMUX_PANE` inherited from the
   pane Claude runs in.
3. **Guard** — proceed only if all hold:
   - `$TMUX` is set (we are inside tmux), and
   - the target window has **no** `@wt_num`, and
   - the target window has **no** `@wt_title`.

   Effect: real issue windows (`@wt_num` set) are skipped; already-summarized
   windows (`@wt_title` set) are skipped; manual windows **and** issue-less
   `cwork -B` worktrees (neither set) proceed.
4. Resolve the window id from `$TMUX_PANE`
   (`tmux display-message -p -t "$TMUX_PANE" '#{window_id}'`). Resolve the branch
   with `git -C "$cwd" rev-parse --abbrev-ref HEAD`; if `cwd` is not a git repo,
   fall back to the `cwd` basename. Set `@wt_branch` (if empty) and a placeholder
   `@wt_title="summarizing…"`, then call `tmux-worktree-notice show "$win"` so the
   box appears **immediately**.
5. **Fork a detached background job** with stdout/stderr redirected to
   `/dev/null` (nothing must reach Claude's prompt context — see Constraints).
   The job `curl`s the Anthropic Messages API:
   - model `claude-haiku-4-5`
   - a system prompt requesting a ≤6-word, imperative, no-trailing-period phrase
   - `max_tokens` ~24
   - the user prompt truncated to ~4000 chars (bounds cost on huge pastes)
   - `jq` extracts the response text.
6. The background job sets `@wt_title` to the summary and calls
   `tmux-worktree-notice refresh "$win"`.
7. The foreground hook **exits immediately and prints nothing** — the user's
   prompt is never blocked.

## The `refresh` subcommand (new, in `tmux-worktree-notice`)

`refresh [target]`:
- Resolve the window (active window if no target).
- Find the banner pane via the existing `_banner_pane` helper (`@wt_banner == 1`).
- Read its `pane_pid` (`tmux display-message -p -t "$bp" '#{pane_pid}'`) and send
  it `SIGWINCH` (`kill -WINCH "$pid"`). The pane command *is* the `render` bash
  process, so its existing `WINCH` trap fires and repaints from the now-updated
  `@wt_*` options.
- No-op (return 0) if there is no banner pane.

Event-driven; introduces no new polling. The keep-alive loop in `render()` is
unchanged.

## Failure handling (never errors the window)

- **No `ANTHROPIC_API_KEY`, curl failure, non-2xx, empty/malformed response, or
  offline** → the background job sets `@wt_title` to a graceful fallback (first
  ~40 chars of the prompt) and calls `refresh`. The window still gets a useful
  box and is never errored.
- **Single attempt per window** — once `@wt_title` is non-empty the step-3 guard
  blocks any re-run, so later prompts never re-summarize and failures are not
  retried.

## Constraints / gotchas

- **`UserPromptSubmit` stdout is injected into the prompt context.** The hook
  script must print **nothing** to stdout, and the backgrounded curl job must
  have its stdout/stderr fully detached (`>/dev/null 2>&1`, disowned) so no API
  output leaks into the conversation.
- The hook runs in Claude's environment, which inherits `$TMUX` / `$TMUX_PANE`
  and a `PATH` that includes `~/bin`, so `tmux` and `tmux-worktree-notice`
  resolve.
- Multiple Claude panes in one window share the window-level `@wt_*`; the first
  prompt to arrive wins and the guard prevents later overwrites. Acceptable.

## Dependencies & touch points

- Tools: `jq` (already a `brew.sh` dependency), `curl` (system),
  `ANTHROPIC_API_KEY` (from git-ignored `~/.extra`).
- New file: `bin/claude-tmux-notice`.
- Change: add `refresh` subcommand to `bin/tmux-worktree-notice` (incl. its
  usage string and the top-of-file subcommand list comment).
- One-time hook entry in `~/.claude/settings.json` (`UserPromptSubmit` →
  `claude-tmux-notice`).
- Doc: a note/section in `setup-a-new-machine.sh` for installing the hook.
- Doc: a `bin/` bullet for `claude-tmux-notice` in `CLAUDE.md`.

## Defaults (approved)

- Summary style: ≤6 words, imperative, no trailing period
  (e.g. *"Fix flaky worktree render test"*).
- Placeholder `"summarizing…"` shown during the ~1–2s call.
- Fallback body on API failure: truncated first prompt.
- Script name: `bin/claude-tmux-notice`.
