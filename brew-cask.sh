#!/bin/bash

# GUI applications via Homebrew Cask
# Last updated: 2026

CASKS=(
  # ─── Terminal & Dev ────────────────────────────────────────────────
  ghostty                     # terminal emulator (tmux-friendly)
  docker

  # ─── Productivity ──────────────────────────────────────────────────
  1password
  hazel                       # automated file organization
  slack

  # ─── Email ────────────────────────────────────────────────────────
  mailmate

  # ─── Dev Tools ────────────────────────────────────────────────────
  datagrip                    # JetBrains database IDE
  balsamiq-wireframes         # mockups / wireframing
  macdown                     # Markdown editor (note: cask sunsets Sep 2026)

  # ─── VPN ──────────────────────────────────────────────────────────
  protonvpn

  # ─── Media ─────────────────────────────────────────────────────────
  spotify
  vlc

  # ─── Keyboard ──────────────────────────────────────────────────────
  karabiner-elements

  # ─── Fonts ─────────────────────────────────────────────────────────
  font-jetbrains-mono-nerd-font
  font-inconsolata-nerd-font
)

brew install --cask "${CASKS[@]}"


# ─── Mac App Store apps (via mas) ───────────────────────────────────
# install mas first: brew install mas
# you must be signed into the App Store for this to work
brew install mas

MAS_APPS=(
  1474335294   # GoodLinks
  1091189122   # Bear
)

echo "Installing Mac App Store apps..."
for app in "${MAS_APPS[@]}"; do
  mas install "$app"
done


# ─── Manual installs ────────────────────────────────────────────────
# OmniGraffle 6 — no cask available (cask installs v7)
#   Install from saved DMG or https://www.omnigroup.com/download/latest/omnigraffle/6
echo ""
echo "Manual installs needed:"
echo "  • OmniGraffle 6 — download from omnigroup.com/download/latest/omnigraffle/6"

echo ""
echo "Done. GUI apps installed."
