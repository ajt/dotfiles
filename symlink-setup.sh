#!/bin/bash

# Symlink dotfiles into ~/
# Run from the dotfiles directory

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Files/dirs to symlink
FILES=(
  .zshrc
  .aliases
  .exports
  .functions
  .gitconfig
  .gitignore
  .inputrc
  .tmux
  .tmux.conf
  .vimrc
  .dircolors
  bin
)

echo "Symlinking dotfiles from $DOTFILES_DIR to $HOME"
echo ""

for item in "${FILES[@]}"; do
  source="$DOTFILES_DIR/$item"
  target="$HOME/$item"

  if [ ! -e "$source" ]; then
    echo "  SKIP  $item (not found in dotfiles)"
    continue
  fi

  if [ -e "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "  OK    $item"
    continue
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    read -p "  '$target' exists. Overwrite? (y/n) " -n 1 reply
    echo
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "  SKIP  $item"
      continue
    fi
    rm -rf "$target"
  fi

  ln -s "$source" "$target"
  echo "  LINK  $target → $source"
done

# ─── .config subdirectories (symlink individually, not the whole .config) ────
mkdir -p "$HOME/.config"

CONFIG_DIRS=(
  karabiner
)

for dir in "${CONFIG_DIRS[@]}"; do
  source="$DOTFILES_DIR/.config/$dir"
  target="$HOME/.config/$dir"

  if [ ! -e "$source" ]; then
    echo "  SKIP  .config/$dir (not found in dotfiles)"
    continue
  fi

  if [ -e "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "  OK    .config/$dir"
    continue
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    read -p "  '$target' exists. Overwrite? (y/n) " -n 1 reply
    echo
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "  SKIP  .config/$dir"
      continue
    fi
    rm -rf "$target"
  fi

  ln -s "$source" "$target"
  echo "  LINK  $target → $source"
done

echo ""
echo "Done. Remember to also symlink manually if needed:"
echo "  ~/.ssh/config"
echo "  ~/.tmuxinator/"
