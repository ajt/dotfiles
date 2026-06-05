# Floating valvonta dashboard in a tmux popup — design

Date: 2026-06-05
Status: approved, pre-implementation
Branch: `feature/tmux-valvonta-popup`

## Problem

`valvonta` is a Textual TUI that monitors a worktree-based repo (issues, activity,
worktrees) and is normally run in a dedicated tmux pane as `valvonta --repo <dir>`.
There is no quick way to summon it. We want a single keystroke — **`Ctrl-b v`**
(tmux prefix + `v`) — that, from *any* tmux window, pops valvonta up as a centered
floating window (tmux `display-popup`) scoped to the project that window belongs to,
then disappears when dismissed. This mirrors the floating-window pattern from the
reference video.

### Constraints discovered

- **valvonta requires a config.** With no `valvonta.toml` it prints a one-line error
  and exits 1. Config resolution (in valvonta): `<repo>/valvonta.toml`, else
  `~/.config/valvonta/<repo-name>.toml`. A naive popup would therefore flash an error
  and vanish in any unconfigured project.
- **valvonta resolves the repo itself.** `valvonta --repo <dir>` is explicit; with no
  `--repo` it runs `git rev-parse --show-toplevel` from its cwd. We will always pass
  `--repo` explicitly.
- **tmux is 3.6a**, so `display-popup` (with `-E`, `-b border-lines`, `-T title`) is
  fully supported.
- **`~/bin` is a whole-directory symlink to `dotfiles/bin`**, so a new `bin/` script is
  on `PATH` immediately — no `symlink-setup.sh` change. `bin/` scripts are extensionless
  by convention (`tmux-worktree-notice`, `claude-tmux-notice`).
- **The keybinding must live in `.tmux.conf`** — the only tmux config. valvonta needs no
  code changes; the `perfect` Makefile cockpit/worktree scripts are prior art only.

## Decisions

Two design forks were confirmed with the user:

1. **No-config behavior: friendly hint that stays open.** When triggered in a project
   with no valvonta config (or a non-git directory), the popup prints a short, specific
   message and waits for a keypress instead of flash-closing. The launcher detects this
   itself rather than relying on valvonta's exit code.
2. **Repo scope: canonical main repo.** Triggered from inside a linked worktree, the
   popup resolves to the **main** worktree (not the worktree you happen to be in). This
   gives the same dashboard from any worktree window, and makes a user-level
   `~/.config/valvonta/<repo>.toml` resolve by the real repo name.

Structural decision (Approach A, confirmed): a **thin keybinding** in `.tmux.conf` that
calls a **dedicated launcher script** `bin/tmux-valvonta-popup`, which owns all logic and
is unit-testable like the other `bin/tmux-*` scripts. (Rejected: inlining all logic in
`.tmux.conf` — untestable, miserable quoting; and pushing the behavior into valvonta —
needlessly invasive for launcher glue.)

## Design

### Keybinding (`.tmux.conf`)

Added to the key-bindings section, next to the worktree-related `bind b`:

```tmux
# floating valvonta dashboard for the current window's repo (prefix + v)
bind v display-popup -E -b rounded -T ' valvonta ' -w 70% -h 40% \
  "$HOME/bin/tmux-valvonta-popup '#{pane_current_path}'"
```

- `-E` closes the popup when the command exits (valvonta quit via `q`, or after the
  hint's keypress).
- `-b rounded -T ' valvonta '` draws the rounded, titled frame seen in the reference.
- `-w 70% -h 40%` is 70% of the client's width × 40% of its height (tmux reads a trailing
  `%` as a fraction of the client, a bare number as an absolute cell count), centered
  (default position). A one-line tweak to resize.
- `'#{pane_current_path}'` is expanded by tmux and passed as the launcher's `$1` (the
  originating directory). Passing it as an argument is more reliable than `-d` and lets
  the launcher own resolution. `v` does not collide with any existing prefix-table
  binding (the copy-mode `v` is in a different key table).

### Launcher (`bin/tmux-valvonta-popup`)

```bash
#!/usr/bin/env bash
# Summon valvonta in a tmux display-popup, scoped to the canonical main repo
# of the window it was launched from. Invoked by `bind v` in ~/.tmux.conf.
#
# Usage: tmux-valvonta-popup [start-dir]   (start-dir defaults to $PWD)
set -euo pipefail

start_dir="${1:-$PWD}"

# Print a message, wait for a single keypress, then exit 0 so display-popup -E
# closes cleanly. In a popup the command's stdin is the pane's tty, so the read
# waits for a real key. In tests we redirect stdin from /dev/null: read hits EOF
# and returns immediately (|| true), so the hint text still prints but nothing
# blocks.
hint() {
  printf '%s\n\n' "$*"
  printf 'Press any key to close… '
  read -rsn1 _ || true
  exit 0
}

cd "$start_dir" 2>/dev/null || hint "valvonta: cannot enter $start_dir"

command -v valvonta >/dev/null 2>&1 \
  || hint "valvonta: not installed — 'uv tool install valvonta' (or pipx install valvonta)."

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || hint "valvonta: $start_dir is not inside a git repository."

# Canonical main repo root: the first line of `git worktree list --porcelain` is
# always the main worktree (`worktree <path>`), regardless of which worktree we
# were launched from. NR==1 + sub (not $2) keeps paths with spaces intact; no
# `head` after the pipe, so awk consumes all input and git is never SIGPIPE'd
# (which set -o pipefail would otherwise turn into a fatal exit). BSD-awk safe.
main_root="$(git worktree list --porcelain | awk 'NR==1{sub(/^worktree /,""); print}')"
[ -n "$main_root" ] || hint "valvonta: could not resolve the repo root for $start_dir."

# Mirror valvonta's own config resolution so we show the hint (not a content-less
# dashboard) exactly when valvonta would have errored.
repo_name="$(basename "$main_root")"
if [ ! -f "$main_root/valvonta.toml" ] \
   && [ ! -f "$HOME/.config/valvonta/$repo_name.toml" ]; then
  hint "valvonta: no config for '$repo_name'.
Create  $main_root/valvonta.toml
   or    ~/.config/valvonta/$repo_name.toml
(see valvonta.example.toml in the valvonta repo)."
fi

# exec so valvonta is the popup's foreground process; when the user quits (q),
# the command exits and display-popup -E tears the popup down.
exec valvonta --repo "$main_root"
```

### Resolution flow (summary)

1. `cd` into the triggering window's `pane_current_path`.
2. `valvonta` on PATH? no → hint.
3. inside a git work tree? no → hint.
4. resolve `main_root` = first `git worktree list` entry (the main worktree).
5. config present for `main_root` (local file or `~/.config/valvonta/<name>.toml`)?
   no → hint.
6. `exec valvonta --repo "$main_root"`.

## Files touched (all in the dotfiles worktree)

| File | Change |
|---|---|
| `.tmux.conf` | add the `bind v display-popup …` line |
| `bin/tmux-valvonta-popup` | new launcher script (`chmod +x`) |
| `tests/tmux-valvonta-popup.test.sh` | new test, run by `tests/run.sh` |
| `docs/superpowers/specs/2026-06-05-tmux-valvonta-popup-design.md` | this spec |

valvonta is **not** modified. The `.gitignore` `.worktrees/` entry was already committed
to `main` as worktree-setup prerequisite (separate from this branch).

## Testing

A `tests/tmux-valvonta-popup.test.sh` sourcing `tests/lib.sh`. To keep cases deterministic
regardless of the host: use **real throwaway git repos** (`git init` + `git worktree add`
under a `mktemp -d`) rather than stubbing git's several calls, and stub **only** `valvonta`
as a script that appends its args to a recording file and exits 0. Each case runs the
launcher with a fully controlled `PATH` (a stub dir containing the `valvonta` stub plus the
real `git`, e.g. via a symlink) and with stdin from `/dev/null` so the hint never blocks.
Cases:

1. **non-git dir** (`mktemp -d`, no repo) → output contains "not inside a git repository";
   the `valvonta` recording file is empty.
2. **valvonta missing** (`PATH` excludes the `valvonta` stub) → output contains "not
   installed".
3. **configured repo** (`git init` + a `valvonta.toml`) → recording file contains
   `--repo <root>` where `<root>` is that repo.
4. **worktree → main resolution** (`git init` main + `valvonta.toml`, then `git worktree
   add` a linked worktree; launch from the linked path) → recorded `--repo` is the **main**
   root, not the linked worktree.
5. **missing config** (`git init`, no `valvonta.toml`, and no
   `~/.config/valvonta/<name>.toml`) → output contains "no config for"; recording file
   empty.

To make case 5 hermetic, point config lookup at a temp `HOME` (the script reads
`$HOME/.config/valvonta/...`), so the test never depends on the real `~/.config`.

Whole suite green via `bash tests/run.sh`.

## Manual verification

Source the config (`tmux source-file ~/.tmux.conf`), then `Ctrl-b v` from:
a configured repo window (dashboard appears, `q` closes it); a window inside one of that
repo's worktrees (same dashboard); an unconfigured repo window (hint, any key closes);
a non-git dir (hint). Confirm truecolor with `valvonta doctor` inside the popup; if it
reports no truecolor, flipping `.tmux.conf`'s `default-terminal` to `tmux-256color` is a
follow-up (the existing `terminal-features ',*:RGB'` line should already suffice).

## Out of scope / notes

- **Per-project enablement.** A project only shows the dashboard once it has a
  `valvonta.toml` (committed in the repo) or a `~/.config/valvonta/<name>.toml`. Creating
  those configs is per-project work, not part of this change; until then the popup shows
  the friendly hint. (`perfect` has no valvonta.toml today.)
- **No toggle-to-close.** While a popup is open it captures the prefix key, so `Ctrl-b v`
  can't reach tmux to close it. Dismissal is valvonta's `q` (or any key on the hint).
  Open-only is the natural model.
- **Popup geometry** is fixed at 70% × 40% of the client; configurability is YAGNI.
