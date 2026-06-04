#!/usr/bin/env bash
# git post-commit hook: review spec/plan artifacts changed in the latest commit
# with the second model. Opt-in, per repo -- symlink it into a repo's hooks:
#   ln -sf ~/.claude/review/review-on-commit.sh /repo/.git/hooks/post-commit
set -euo pipefail

# Resolve this script's real directory, even when called through the symlink.
SRC="${BASH_SOURCE[0]}"
while [ -h "$SRC" ]; do
  DIR="$(cd -P "$(dirname "$SRC")" && pwd)"
  SRC="$(readlink "$SRC")"
  [[ "$SRC" != /* ]] && SRC="$DIR/$SRC"
done
KIT="$(cd -P "$(dirname "$SRC")" && pwd)"

cd "$(git rev-parse --show-toplevel)"
mapfile -t changed < <(git diff-tree --no-commit-id --name-only -r HEAD)
for f in "${changed[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.review.md) continue ;;
    *plan*.md|*/plans/*.md) t=plan ;;
    *spec*.md|*/specs/*.md) t=spec ;;
    *) continue ;;
  esac
  uv run "$KIT/review.py" --type "$t" --file "$f" || true
done
