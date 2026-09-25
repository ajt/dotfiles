#!/bin/bash

# Symlink dotfiles into ~/
# Run from the dotfiles directory, or via `dotfiles update`. Idempotent and
# non-interactive: an existing file or directory in the way is moved to
# ~/.dotfiles-backup/<timestamp>/ (never deleted) and replaced by the link.

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
moved=0

# link_into <source> <target> <label> — make $target a symlink to $source.
#   OK     already the right link
#   MOVED  something else was there; it went to $BACKUP_DIR, then linked
#   LINK   nothing was there
link_into() {
  local source=$1 target=$2 label=$3 rel
  if [ ! -e "$source" ]; then
    echo "  SKIP  $label (not found in dotfiles)"
    return 0
  fi
  if [ -e "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "  OK    $label"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    rel=${target#"$HOME"/}
    if ! mkdir -p "$BACKUP_DIR/$(dirname "$rel")" || ! mv "$target" "$BACKUP_DIR/$rel"; then
      echo "  FAIL  $label (could not move the existing one aside; left as is)"
      return 1
    fi
    moved=$((moved + 1))
    echo "  MOVED $label (was not our link — kept at ~/.dotfiles-backup/${BACKUP_DIR##*/}/$rel)"
  else
    echo "  LINK  $label"
  fi
  if ! mkdir -p "$(dirname "$target")" || ! ln -s "$source" "$target"; then
    echo "  FAIL  $label (could not create the link)"
    return 1
  fi
}

echo "Symlinking dotfiles from $DOTFILES_DIR to $HOME"
echo ""

# ─── files/dirs straight into $HOME ─────────────────────────────────────────
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
for item in "${FILES[@]}"; do
  link_into "$DOTFILES_DIR/$item" "$HOME/$item" "$item"
done

# ─── .config subdirectories (individually, not the whole .config) ───────────
CONFIG_DIRS=(
  ghostty
  karabiner
)
for dir in "${CONFIG_DIRS[@]}"; do
  link_into "$DOTFILES_DIR/.config/$dir" "$HOME/.config/$dir" ".config/$dir"
done

# ─── macOS Services / Finder Quick Actions ──────────────────────────────────
# The Services registry handles symlinked bundles fine; pbs -flush makes new
# ones appear without a re-login.
for source in "$DOTFILES_DIR"/services/*.workflow; do
  [ -e "$source" ] || continue
  item="$(basename "$source")"
  link_into "$source" "$HOME/Library/Services/$item" "services/$item"
done
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

# ─── Claude Code ─────────────────────────────────────────────────────────────
# Pure renderers/skills are live-synced. settings.json is per-machine (private
# marketplaces, security flags, …): seeded from the public template only when
# missing; afterwards only the claude-tmux-state hook entries are kept in sync,
# by merging in whatever events the template has that the file lacks.
CLAUDE_SYMLINK_FILES=(
  statusline-command.sh
  skills/prototype
)
for f in "${CLAUDE_SYMLINK_FILES[@]}"; do
  link_into "$DOTFILES_DIR/claude/$f" "$HOME/.claude/$f" "claude/$f"
done

example="$DOTFILES_DIR/claude/settings.example.json"
target="$HOME/.claude/settings.json"
if [ -e "$example" ] && [ ! -e "$target" ]; then
  mkdir -p "$HOME/.claude"
  cp "$example" "$target"
  echo "  COPY  ~/.claude/settings.json ← claude/settings.example.json (template — edit per machine)"
elif [ -e "$target" ]; then
  if command -v jq >/dev/null 2>&1; then
    events() { jq -r '.hooks // {} | to_entries[] | select(any(.value[].hooks[]?.command; test("claude-tmux-state"))) | .key' "$1" 2>/dev/null; }
    missing=""
    for ev in $(events "$example"); do
      events "$target" | grep -qx "$ev" || missing="$missing $ev"
    done
    if [ -n "$missing" ]; then
      rel=${target#"$HOME"/}
      mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      cp "$target" "$BACKUP_DIR/$rel"
      # For each missing event append only the template entries whose commands
      # are claude-tmux-state ones (the template also carries other hooks that
      # are not this script's business), skipping any command already present.
      # Everything else in the file (permissions, env, other hooks) is kept;
      # jq re-serialises it, so indentation may change.
      if merged=$(jq --slurpfile t "$example" --arg evs "$missing" '
            ($evs | split(" ") | map(select(. != ""))) as $missing
            | .hooks = ((.hooks // {}) as $h
                | reduce $missing[] as $ev ($h;
                    ([.[$ev][]?.hooks[]?.command]) as $have
                    | ($t[0].hooks[$ev] // [] | map(
                        .hooks |= map(select((.command | test("claude-tmux-state")) and (.command as $c | $have | index($c) | not)))
                      ) | map(select(.hooks | length > 0))) as $add
                    | .[$ev] = ((.[$ev] // []) + $add)))' "$target") \
         && [ -n "$merged" ] && printf '%s\n' "$merged" > "$target"; then
        echo "  MERGE ~/.claude/settings.json ← claude-tmux-state hooks for:$missing (previous copy in ~/.dotfiles-backup/${BACKUP_DIR##*/}/)"
      else
        echo "  KEEP  ~/.claude/settings.json (could not merge hooks for:$missing — copy them from claude/settings.example.json)"
      fi
    else
      echo "  OK    ~/.claude/settings.json (hooks match claude/settings.example.json)"
    fi
  else
    echo "  KEEP  ~/.claude/settings.json (jq not installed; hooks not checked)"
  fi
fi

# ─── Codex CLI ───────────────────────────────────────────────────────────────
# hooks.json is live-synced (nothing machine-specific in it). config.toml is
# per-machine (notify integrations, model, trust) and never touched.
link_into "$DOTFILES_DIR/codex/hooks.json" "$HOME/.codex/hooks.json" "codex/hooks.json"

echo ""
if [ "$moved" -gt 0 ]; then
  echo "Done. $moved pre-existing file(s) were moved aside, not deleted: ~/.dotfiles-backup/${BACKUP_DIR##*/}/"
else
  echo "Done."
fi
echo "Per-machine, never touched by this script: ~/.extra  ~/.gitconfig.local  ~/.ssh/config  ~/.claude/settings.json (beyond hook sync)  ~/.codex/config.toml"
