#!/bin/bash

# Install command-line tools using Homebrew
# Last updated: 2026

brew update
brew upgrade

PACKAGES=(
  # ─── GNU core utilities ────────────────────────────────────────────
  coreutils findutils gnu-sed gnu-tar grep gawk

  # ─── Shell & prompt ────────────────────────────────────────────────
  zsh
  zsh-autosuggestions
  zsh-syntax-highlighting
  pure                        # minimal zsh prompt

  # ─── Modern CLI replacements ───────────────────────────────────────
  ripgrep                     # rg > grep/ag/ack
  fd                          # fd > find
  fzf                         # fuzzy finder
  bat                         # bat > cat
  eza                         # eza > ls
  delta                       # better git diffs
  btop                        # btop > htop
  ncdu                        # disk usage
  gdu                         # fast disk usage (Go)
  tree
  jq                          # JSON processor

  # ─── Git ───────────────────────────────────────────────────────────
  git
  gh                          # GitHub CLI
  git-lfs

  # ─── Python ────────────────────────────────────────────────────────
  python
  uv                          # fast Python package manager

  # ─── Node ──────────────────────────────────────────────────────────
  # node managed via nvm, but install nvm:
  nvm

  # ─── Editors & tmux ────────────────────────────────────────────────
  vim
  tmux
  tmuxinator

  # ─── Networking & Security ─────────────────────────────────────────
  wget
  curl
  ssh-copy-id
  tailscale
  nmap
  gnupg

  # ─── Files & Media ────────────────────────────────────────────────
  imagemagick
  ffmpeg
  p7zip
  rename
  pv                          # pipe viewer (progress)
  zstd

  # ─── Database ──────────────────────────────────────────────────────
  sqlite
  libpq                       # PostgreSQL client libs (psycopg2 builds — no local server)

  # ─── Build tools ──────────────────────────────────────────────────
  cmake

  # ─── Directory jumping ────────────────────────────────────────────
  z

  # ─── Misc ─────────────────────────────────────────────────────────
  grc                         # generic coloriser
  entr                        # run commands on file changes
  watch
  shellcheck                  # shell script linter
  stats
)

brew install "${PACKAGES[@]}"

# fzf post-install (keybindings and completion)
$(brew --prefix)/opt/fzf/install --all --no-bash --no-fish

echo "Done. Don't forget to run brew-cask.sh for GUI apps."
