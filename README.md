# dotfiles

My macOS dotfiles. Originally forked from [paulirish/dotfiles](https://github.com/paulirish/dotfiles), now rewritten from scratch for 2026.

## What's in here

- **zsh** config (no plugin managers — just Homebrew-installed plugins)
- **tmux** config (minimal, vim-style navigation)
- **vim** config (carried forward)
- **git** config (with [delta](https://github.com/dandavison/delta) for diffs)
- **Homebrew** formulae and casks
- **macOS** defaults (curated, not the 500-line kitchen sink)
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

- `~/.extra` — secret env vars, PATH additions
- `~/.gitconfig.local` — git credentials, signing key
- `~/.ssh/config` — SSH hosts
