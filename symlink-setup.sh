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
  .tmux.conf
  .vimrc
  .dircolors
  .cwork
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
  ghostty
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

# ─── macOS Services / Finder Quick Actions (symlink into ~/Library/Services) ─
mkdir -p "$HOME/Library/Services"

for source in "$DOTFILES_DIR"/services/*.workflow; do
  [ -e "$source" ] || continue
  item="$(basename "$source")"
  target="$HOME/Library/Services/$item"

  if [ -e "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "  OK    services/$item"
    continue
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    read -p "  '$target' exists. Overwrite? (y/n) " -n 1 reply
    echo
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "  SKIP  services/$item"
      continue
    fi
    rm -rf "$target"
  fi

  ln -s "$source" "$target"
  echo "  LINK  $target → $source"
done

# Nudge the Services registry so new Quick Actions appear without a re-login.
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

# Statusline is a pure renderer — safe to share publicly, live-synced.
# settings.json is COPIED from a public template only when missing, so each
# machine's real settings (private marketplaces, security flags, etc.) stay
# out of this public repo. Same private-overlay spirit as ~/.extra.
mkdir -p "$HOME/.claude/skills"

CLAUDE_SYMLINK_FILES=(
statusline-command.sh
skills/prototype
)

for f in "${CLAUDE_SYMLINK_FILES[@]}"; do
source="$DOTFILES_DIR/claude/$f"
target="$HOME/.claude/$f"

if [ ! -e "$source" ]; then
  echo "  SKIP  claude/$f (not found in dotfiles)"
  continue
fi

if [ -e "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
  echo "  OK    claude/$f"
  continue
fi

if [ -e "$target" ] || [ -L "$target" ]; then
  read -p "  '$target' exists. Overwrite? (y/n) " -n 1 reply
  echo
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
	echo "  SKIP  claude/$f"
	continue
  fi
  rm -rf "$target"
fi

ln -s "$source" "$target"
echo "  LINK  $target → $source"
done

# Codex CLI: hooks.json is live-synced (a symlink, like the tmux/zsh configs)
# because it holds nothing machine-specific. config.toml is NOT touched: it is
# per-machine (notify integrations, model, trust) — same rule as ~/.claude/settings.json.
mkdir -p "$HOME/.codex"

for f in hooks.json; do
source="$DOTFILES_DIR/codex/$f"
target="$HOME/.codex/$f"

if [ ! -e "$source" ]; then
  echo "  SKIP  codex/$f (not found in dotfiles)"
  continue
fi

if [ -e "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
  echo "  OK    codex/$f"
  continue
fi

if [ -e "$target" ] || [ -L "$target" ]; then
  read -p "  '$target' exists. Overwrite? (y/n) " -n 1 reply
  echo
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
	echo "  SKIP  codex/$f"
	continue
  fi
  rm -rf "$target"
fi

ln -s "$source" "$target"
echo "  LINK  $target → $source"
done

# One-shot copy: template → real file, only if real file is missing.
example="$DOTFILES_DIR/claude/settings.example.json"
target="$HOME/.claude/settings.json"
if [ -e "$example" ] && [ ! -e "$target" ]; then
cp "$example" "$target"
echo "  COPY  $target ← claude/settings.example.json (template — edit per machine)"
elif [ -e "$target" ]; then
# Left alone (per-machine), but the tmux-state/reader hooks live in it, so say
# which claude-tmux-state hook events the template has that this file lacks.
missing=""
if command -v jq >/dev/null 2>&1; then
  events() { jq -r '.hooks // {} | to_entries[] | select(any(.value[].hooks[]?.command; test("claude-tmux-state"))) | .key' "$1" 2>/dev/null; }
  for ev in $(events "$example"); do
    events "$target" | grep -qx "$ev" || missing="$missing $ev"
  done
fi
if [ -n "$missing" ]; then
  echo "  KEEP  ~/.claude/settings.json — missing claude-tmux-state hooks for:$missing (copy those entries from claude/settings.example.json)"
else
  echo "  KEEP  ~/.claude/settings.json (exists; hooks match claude/settings.example.json)"
fi
fi

echo ""
echo "Done. Remember to also symlink manually if needed:"
echo "  ~/.ssh/config"
echo "  ~/.tmuxinator/"
