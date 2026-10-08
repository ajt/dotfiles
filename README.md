# dotfiles

My macOS dotfiles. Originally forked from [paulirish/dotfiles](https://github.com/paulirish/dotfiles), now rewritten from scratch for 2026.

## What's in here

- **zsh** config (no plugin managers — just Homebrew-installed plugins)
- **tmux** config (minimal, vim-style navigation)
- **vim** config (carried forward)
- **git** config (with [delta](https://github.com/dandavison/delta) for diffs)
- **Homebrew** formulae and casks
- **macOS** defaults (curated, not the 500-line kitchen sink)
- **Finder Quick Actions** (`services/`) — e.g. right-click → Copy Path, Open in Reader
- **Agent reader view** — `prefix R` in tmux (or the *Open in Reader* Quick Action on copied text) opens Claude Code's or Codex's last reply as a Clearly-style HTML page with a persistent Style panel, highlights and a SwiftRead-style speed reader (`bin/reader-*`; guide: [`docs/reader-view.md`](docs/reader-view.md))
- Shell **aliases**, **exports**, and **functions**

## New machine setup

```bash
# 1. Clone this repo
git clone https://github.com/ajt/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Walk through the setup script (don't run it all at once)
cat setup-a-new-machine.sh  # read it first

# 3. Install Homebrew packages
chmod +x brew.sh brew-cask.sh
./brew.sh
./brew-cask.sh

# 4. Create symlinks
chmod +x symlink-setup.sh
./symlink-setup.sh

# 5. Apply macOS defaults
sh .macos

# 6. Restart terminal
```

## Updating an existing machine

One command:

```bash
dotfiles update            # pull, then run only the steps the pull needs
dotfiles update --dry-run  # show what it would run
dotfiles update --all      # force every step (a machine that missed many pulls)
dotfiles update --since main   # already pulled by hand: act on changes since main
```

`dotfiles update` (`bin/dotfiles-update`) fast-forwards the repo, syncs
submodules, diffs the old and new commit, and runs the matching steps below.
`dotfiles cd` jumps into the repo. Most of the repo is symlinked into
`$HOME`, so for many pulls there is nothing to run at all.

What each kind of change needs (this is what the command decides for you):

| Changed in the pull | What to do |
|---|---|
| `.zshrc`, `.aliases`, `.exports`, `.functions`, `.vimrc`, `.gitconfig` | nothing — open a new shell |
| `.tmux.conf` | `prefix r` (reload), or restart the tmux server |
| `~/.extra` (yours, not in the repo) | open a new shell; restart tmux for `TMUX_NEW_WINDOW_DIR`, or apply `TMUX_SHOW_UTC` as described below |
| a script in `bin/` | nothing — `~/bin` is a link to the directory |
| a new `services/*.workflow` Quick Action | `./symlink-setup.sh` (links it and refreshes the Services menu) |
| `codex/hooks.json` | nothing — it is a link; a new file there needs `./symlink-setup.sh` |
| `claude/settings.example.json` | `./symlink-setup.sh` merges only the missing `claude-tmux-state` hook entries into `~/.claude/settings.json` (nothing else added or removed; jq rewrites the file, so indentation may change) |
| `brew.sh` / `brew-cask.sh` | re-run the script |
| `.macos` | `sh .macos` (the updater runs it; asks for your password once, restarts Finder/Dock) |

`symlink-setup.sh` is idempotent and never prompts: existing links print
`OK`; a real file or directory in the way is moved to
`~/.dotfiles-backup/<timestamp>/` (never deleted) and replaced by the link;
`~/.claude/settings.json` only ever gains the `claude-tmux-state` hook
entries it is missing (previous copy backed up first). `~/.extra`,
`~/.gitconfig.local`, `~/.ssh/config` and `~/.codex/config.toml` are
per-machine and never touched.

## Zsh plugins

Plugins are sourced explicitly in `.zshrc` — no plugin manager.

- **zsh-autosuggestions** — inline command suggestions (Homebrew)
- **zsh-syntax-highlighting** — command syntax coloring (Homebrew)
- **zsh-history-substring-search** — filtered history navigation (Homebrew)
- **[zsh-claude-code-shell](https://github.com/ArielTM/zsh-claude-code-shell)** — type `# natural language` and press Enter to generate a shell command via Claude Code CLI (git submodule in `zsh-plugins/`)

## Key tools

| Old | New |
|---|---|
| `ack` / `ag` | `ripgrep` (`rg`) |
| `find` | `fd` |
| `ls` | `eza` |
| `cat` | `bat` |
| `htop` | `btop` |
| `diff` (git) | `delta` |
| `pip` / `virtualenvwrapper` | `uv` |
| Antigen + oh-my-zsh | Homebrew zsh plugins |
| gpakosz/.tmux (58KB) | ~80 lines of tmux.conf |

## Private stuff

Machine-specific config goes in these files (gitignored):

- `~/.extra` — secret env vars, PATH additions, and per-machine knobs:
  - `export TMUX_NEW_WINDOW_DIR="$HOME/Projects"` — where `prefix c` opens a new tmux window (default: `$HOME`; splits always keep the current pane's directory). tmux reads it when the server starts, so restart tmux after changing it. Use `$HOME`, not a quoted `~`; a directory that does not exist falls back to `$HOME`.
  - `export TMUX_SHOW_UTC=1` — add a UTC date/time section to the tmux status bar. Only `1` enables it; unset or `0` keeps the existing local-only clock. See below for examples and applying changes.

New shells and tmux windows never start inside a Python virtualenv, even when
tmux was launched from one: `.tmux.conf` removes `VIRTUAL_ENV` from the
server's environment and `.zshrc` drops an inherited one. Activate a venv in
the shell that needs it, or use `uv run`. (Only `VIRTUAL_ENV`-style venvs are
covered; conda's `CONDA_PREFIX` is left alone.)
- `~/.gitconfig.local` — git credentials, signing key
- `~/.ssh/config` — SSH hosts

## Optional UTC clock in tmux

UTC is hidden by default. To enable it, add this to your **local** `~/.extra`
(this file is gitignored and is never committed):

```sh
export TMUX_SHOW_UTC=1
```

The clock portion changes from `06:27 | 08 Oct` to two labeled sections:

```text
EDT 08 Oct 06:27 | UTC 08 Oct 10:27
```

There is no separator between the date and time within a timezone. The local
zone label follows the system timezone (including daylight saving), and UTC
has its own date so midnight rollover stays clear:

```text
EDT 08 Oct 21:30 | UTC 09 Oct 01:30
```

After editing `~/.extra`, open a new shell to load it. New tmux servers inherit
the setting. To apply it to an **existing** server without ending any sessions,
run these commands from the new shell:

```sh
tmux set-environment -g TMUX_SHOW_UTC "${TMUX_SHOW_UTC:-0}"
tmux source-file ~/.tmux.conf
```

Set `TMUX_SHOW_UTC=0` in `~/.extra` and repeat those steps to disable it. Merely
reloading `.tmux.conf` does not load changes from `.extra`. The clock uses the
existing 10-second status refresh interval.
