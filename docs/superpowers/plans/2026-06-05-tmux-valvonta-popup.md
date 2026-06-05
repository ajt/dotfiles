# Floating valvonta tmux popup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind `Ctrl-b v` to a centered tmux `display-popup` that runs valvonta scoped to the canonical main repo of the current window, with a friendly stay-open hint when there's no config.

**Architecture:** A thin keybinding in `.tmux.conf` calls a dedicated, unit-tested launcher `bin/tmux-valvonta-popup`. The launcher resolves the main worktree (first entry of `git worktree list --porcelain`), mirrors valvonta's own config resolution to decide between launching and hinting, and `exec`s `valvonta --repo <root>`. valvonta is unchanged.

**Tech Stack:** bash, tmux 3.6a `display-popup`, the dotfiles `tests/*.test.sh` harness (`tests/lib.sh` assert helpers, `tests/run.sh` runner). All work is in the dotfiles worktree at `~/Projects/dotfiles/.worktrees/tmux-valvonta-popup` (branch `feature/tmux-valvonta-popup`).

Design spec: `docs/superpowers/specs/2026-06-05-tmux-valvonta-popup-design.md`.

---

## File Structure

- `bin/tmux-valvonta-popup` — **new.** The launcher. One responsibility: from a start
  directory, resolve the canonical main repo and either `exec valvonta --repo <root>` or
  print a friendly hint and wait for a keypress. Extensionless, matching `bin/tmux-*`.
- `tests/tmux-valvonta-popup.test.sh` — **new.** Drives the launcher as a subprocess with a
  hermetic `PATH`/`HOME` and a recording `valvonta` stub; uses real throwaway git repos.
  Auto-discovered by `tests/run.sh`.
- `.tmux.conf` — **modified.** One `bind v display-popup …` line in the key-bindings block.

Two tasks. Task 1 (launcher + test, TDD) is the substance; Task 2 (keybinding) is a
one-liner with a parse check.

---

## Task 1: Launcher script `bin/tmux-valvonta-popup` (TDD)

**Files:**
- Create: `bin/tmux-valvonta-popup`
- Test: `tests/tmux-valvonta-popup.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/tmux-valvonta-popup.test.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Tests for bin/tmux-valvonta-popup — the prefix-v floating valvonta launcher.
# Strategy: real throwaway git repos (no git stubbing) + one `valvonta` stub that
# records its args. Each launcher run gets a fully controlled PATH (only the
# git/awk/basename it needs, plus optionally the valvonta stub) and a hermetic
# HOME, with stdin from /dev/null so the hint's `read` returns instead of blocking.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

script="$here/../bin/tmux-valvonta-popup"
bash_bin=$(command -v bash)

# Sandbox, canonicalised so its path matches what git reports (macOS /var vs
# /private/var).
sandbox=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$sandbox"' EXIT

# tooldir: the only externals the launcher needs, exposed via symlink so a run's
# PATH can be locked down to exactly these (plus optionally valvonta).
tooldir="$sandbox/tools"; mkdir -p "$tooldir"
for t in git awk basename; do ln -s "$(command -v "$t")" "$tooldir/$t"; done

# valdir: a `valvonta` stub recording its args, kept in its own dir so a PATH can
# be built with or without it.
valdir="$sandbox/val"; mkdir -p "$valdir"
rec="$sandbox/valvonta.args"
cat >"$valdir/valvonta" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$rec"
EOF
chmod +x "$valdir/valvonta"

PATH_WITH="$valdir:$tooldir"   # valvonta resolvable
PATH_WITHOUT="$tooldir"        # valvonta absent

# mkrepo <dir>: a git repo with one empty commit so `worktree add` has a HEAD.
mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name test
  git -C "$1" commit -q --allow-empty -m init
}

# run <start-dir> <path>: invoke the launcher hermetically; capture stdout+stderr.
# bash is given by absolute path so the locked-down PATH can't hide the interpreter.
run() {
  env HOME="$sandbox/home" PATH="$2" "$bash_bin" "$script" "$1" </dev/null 2>&1
}

# case 1: not a git repo -> hint, valvonta never runs
: >"$rec"
mkdir -p "$sandbox/nogit"
out=$(run "$sandbox/nogit" "$PATH_WITH")
assert_contains "$out" "not inside a git repository" "non-git dir -> hint"
assert_empty "$(cat "$rec")" "non-git dir -> valvonta not launched"

# case 2: valvonta not installed -> hint
out=$(run "$sandbox" "$PATH_WITHOUT")
assert_contains "$out" "not installed" "missing valvonta -> hint"

# case 3: configured repo -> exec valvonta --repo <repo>
: >"$rec"
mkrepo "$sandbox/configured"
: >"$sandbox/configured/valvonta.toml"
run "$sandbox/configured" "$PATH_WITH" >/dev/null
assert_eq "$(cat "$rec")" "--repo $sandbox/configured" "configured repo -> launches valvonta"

# case 4: launched inside a worktree -> scopes to the MAIN repo
: >"$rec"
mkrepo "$sandbox/main"
: >"$sandbox/main/valvonta.toml"
git -C "$sandbox/main" worktree add -q "$sandbox/linked-wt"
run "$sandbox/linked-wt" "$PATH_WITH" >/dev/null
assert_eq "$(cat "$rec")" "--repo $sandbox/main" "worktree -> main repo resolution"

# case 5: git repo but no config -> hint, valvonta never runs
: >"$rec"
mkrepo "$sandbox/noconf"
out=$(run "$sandbox/noconf" "$PATH_WITH")
assert_contains "$out" "no config for" "missing config -> hint"
assert_empty "$(cat "$rec")" "missing config -> valvonta not launched"

pass
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/Projects/dotfiles/.worktrees/tmux-valvonta-popup && bash tests/tmux-valvonta-popup.test.sh`
Expected: FAIL — the first assertion fails because `bin/tmux-valvonta-popup` does not exist
yet, so `run` prints something like `…/bin/tmux-valvonta-popup: No such file or directory`
instead of the "not inside a git repository" hint:
`FAIL: non-git dir -> hint: […] does not contain [not inside a git repository]`

- [ ] **Step 3: Write the launcher**

Create `bin/tmux-valvonta-popup` with exactly this content:

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

- [ ] **Step 4: Make it executable**

Run: `chmod +x bin/tmux-valvonta-popup`

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/tmux-valvonta-popup.test.sh`
Expected: PASS — ends with `ok (7 assertions)`.

- [ ] **Step 6: Run the whole suite (no regressions)**

Run: `bash tests/run.sh`
Expected: ends with `ALL TESTS PASSED`, including
`== tmux-valvonta-popup.test.sh` / `ok (7 assertions)`.

- [ ] **Step 7: Commit**

```bash
git add bin/tmux-valvonta-popup tests/tmux-valvonta-popup.test.sh
git commit -m "feat: tmux-valvonta-popup launcher for the prefix-v floating dashboard"
```

---

## Task 2: Keybinding in `.tmux.conf`

**Files:**
- Modify: `.tmux.conf` (key-bindings section, after the `bind b … tmux-worktree-notice` line)

- [ ] **Step 1: Add the binding**

In `.tmux.conf`, find:

```tmux
# toggle the worktree issue notice box (worktree windows only)
bind b run-shell '~/bin/tmux-worktree-notice toggle'
```

Insert immediately after it:

```tmux
# floating valvonta dashboard for the current window's repo (prefix + v)
bind v display-popup -E -b rounded -T ' valvonta ' -w 70% -h 40% \
  "$HOME/bin/tmux-valvonta-popup '#{pane_current_path}'"
```

- [ ] **Step 2: Verify the config parses and the binding registers**

Load the edited config into a throwaway tmux server on a private socket (this does NOT
touch your live session) and confirm the prefix-`v` binding is present:

Run:
```bash
sock="valvonta-lint-$$"
tmux -L "$sock" -f .tmux.conf new-session -d -x 200 -y 50 2>/tmp/valvonta-lint.err
tmux -L "$sock" list-keys -T prefix | grep -- 'display-popup'
tmux -L "$sock" kill-server 2>/dev/null || true
cat /tmp/valvonta-lint.err
```
Expected: the `grep` prints a line like `bind-key -T prefix v display-popup -E -b rounded …`,
and `/tmp/valvonta-lint.err` is empty (no config parse errors).

- [ ] **Step 3: Commit**

```bash
git add .tmux.conf
git commit -m "feat: bind prefix-v to the floating valvonta popup"
```

---

## Task 3: Manual end-to-end verification (notes, not committed)

The committed `bind v` calls `$HOME/bin/tmux-valvonta-popup`, and `~/bin` is a symlink to
the **main** checkout's `bin/` — *not* this worktree's `bin/`. So a live `Ctrl-b v` in your
real session only exercises the new launcher **after this branch lands on `main`**. Before
that, verify these from the worktree:

- [ ] **Launcher against a configured repo** (replace the path with a repo that has a
  `valvonta.toml` or a `~/.config/valvonta/<name>.toml`):

  Run: `bin/tmux-valvonta-popup /path/to/a/configured/repo`
  Expected: the valvonta TUI opens; `q` exits cleanly.

- [ ] **Launcher hint paths:**

  Run: `bin/tmux-valvonta-popup /tmp`
  Expected: prints "not inside a git repository" then "Press any key to close…" and waits.

- [ ] **The popup itself, against this worktree's launcher** (private socket, does not
  disturb your session; point the binding at the worktree copy just for the smoke test):

  Run:
  ```bash
  sock="valvonta-smoke-$$"
  tmux -L "$sock" new-session -d -x 200 -y 50
  tmux -L "$sock" bind-key v display-popup -E -b rounded -T ' valvonta ' -w 70% -h 40% \
    "$PWD/bin/tmux-valvonta-popup '#{pane_current_path}'"
  tmux -L "$sock" attach    # press Ctrl-b v over a configured repo; q to close; Ctrl-b d to detach
  tmux -L "$sock" kill-server
  ```
  Expected: the centered rounded ` valvonta ` popup opens with the dashboard (or the hint
  for an unconfigured directory).

- [ ] **After merge to `main`:** reload your real config (`tmux source-file ~/.tmux.conf`),
  then `Ctrl-b v` from a configured repo window, a window inside one of its worktrees (same
  dashboard), an unconfigured repo window (hint), and a non-git dir (hint). Confirm
  truecolor with `valvonta doctor` inside the popup; if it reports no truecolor, switching
  `.tmux.conf`'s `default-terminal` to `tmux-256color` is a follow-up.

(Merging the branch is handled separately via the finishing-a-development-branch skill.)
