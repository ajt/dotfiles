# Valvonta popup toggle + per-project persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Ctrl-b v` toggle a floating valvonta that persists per project (hidden, not killed, on toggle-off) and starts with the banner hidden.

**Architecture:** The `bind v` becomes an `if-shell` toggle — inside a `vlv-*` session it `detach-client`s (hides the float, session persists); elsewhere it opens the popup. The launcher's success path, instead of `exec valvonta`, derives a stable per-repo session name and `exec tmux new-session -A -s <name> "valvonta --no-title --repo <root>"`, so reopening attaches the still-running session.

**Tech Stack:** bash, tmux 3.6a (`display-popup`, `if-shell` brace blocks, `#{m:...}`), the dotfiles `tests/*.test.sh` harness. Work is on branch `fix/tmux-valvonta-popup-pane-path` (folded onto PR #7, which it extends); the dotfiles checkout is already on that branch.

Design spec: `docs/superpowers/specs/2026-06-05-tmux-valvonta-popup-toggle-design.md`.

The load-bearing tmux facts were verified empirically beforehand: `tmux new-session -A` works inside a `display-popup` despite `$TMUX` being set (no `env -u TMUX`); `#{m:vlv-*,#{session_name}}` is `1` inside a `vlv-*` session and `0` elsewhere; `if-shell -F` brace blocks parse on 3.6a.

---

## File Structure

- `bin/tmux-valvonta-popup` — **modify.** Only the final success step changes: derive a
  per-repo session name and `exec tmux new-session -A …` instead of `exec valvonta …`. All
  guards/hints unchanged.
- `.tmux.conf` — **modify.** Replace the single `bind v display-popup …` with the
  `if-shell` toggle (whose open branch is the same `display-popup …` invocation).
- `tests/tmux-valvonta-popup.test.sh` — **rewrite.** The launcher now execs `tmux`, so the
  test records `tmux` invocations (stub) instead of `valvonta`; `valvonta` becomes a
  presence-only stub. Asserts the `new-session` command, `--no-title`, and per-project
  session-name stability.
- `tests/tmux-valvonta-binding.test.sh` — **modify.** Assert the toggle shape (`if-shell`,
  `detach-client`) on top of the existing `-d`/no-`#{…}`-arg assertions.

Two tasks (launcher+its test; binding+its test), then a verification task.

---

## Task 1: Launcher persistent-session success path (TDD)

**Files:**
- Modify: `bin/tmux-valvonta-popup` (lines 49-51, the final `exec valvonta` step)
- Test: `tests/tmux-valvonta-popup.test.sh` (rewrite)

- [ ] **Step 1: Rewrite the test to expect the new behavior**

Replace the ENTIRE contents of `tests/tmux-valvonta-popup.test.sh` with:

```bash
#!/usr/bin/env bash
# Tests for bin/tmux-valvonta-popup. The launcher's success path execs
# `tmux new-session -A -s vlv-<slug>-<hash> "valvonta --no-title --repo <root>"`
# (a persistent per-project session); its failure paths print a stay-open hint.
# Strategy: real throwaway git repos (no git stubbing) + a `tmux` stub that
# records its args + a `valvonta` stub present only so `command -v valvonta`
# passes (valvonta is named inside the session command, never executed by the
# launcher). Each run gets a locked-down PATH and hermetic HOME, stdin from
# /dev/null so the hint's read returns instead of blocking.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

script="$here/../bin/tmux-valvonta-popup"
bash_bin=$(command -v bash)

sandbox=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$sandbox"' EXIT

# tooldir: the externals the launcher needs, via symlink, so a run's PATH can be
# locked to exactly these (plus optionally the valvonta stub).
tooldir="$sandbox/tools"; mkdir -p "$tooldir"
for t in git awk basename cksum tr sed; do ln -s "$(command -v "$t")" "$tooldir/$t"; done

# tmux stub: records the new-session command the launcher execs.
rec="$sandbox/tmux.args"
cat >"$tooldir/tmux" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$rec"
EOF
chmod +x "$tooldir/tmux"

# valvonta stub: present only so \`command -v valvonta\` succeeds; never executed.
valdir="$sandbox/val"; mkdir -p "$valdir"
cat >"$valdir/valvonta" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$valdir/valvonta"

PATH_WITH="$valdir:$tooldir"   # valvonta resolvable
PATH_WITHOUT="$tooldir"        # valvonta absent

mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name test
  git -C "$1" commit -q --allow-empty -m init
}

run() {
  env HOME="$sandbox/home" PATH="$2" "$bash_bin" "$script" "$1" </dev/null 2>&1
}

# case 1: not a git repo -> hint, tmux never invoked
: >"$rec"
mkdir -p "$sandbox/nogit"
out=$(run "$sandbox/nogit" "$PATH_WITH")
assert_contains "$out" "not inside a git repository" "non-git dir -> hint"
assert_empty "$(cat "$rec")" "non-git dir -> tmux not invoked"

# case 2: valvonta not installed -> hint
out=$(run "$sandbox" "$PATH_WITHOUT")
assert_contains "$out" "not installed" "missing valvonta -> hint"

# case 3: configured repo -> exec tmux new-session running valvonta --no-title
: >"$rec"
mkrepo "$sandbox/configured"
: >"$sandbox/configured/valvonta.toml"
run "$sandbox/configured" "$PATH_WITH" >/dev/null
got=$(cat "$rec")
assert_contains "$got" "new-session -A -s vlv-configured-" "configured repo -> persistent session"
assert_contains "$got" "valvonta --no-title --repo $sandbox/configured" "session runs valvonta --no-title scoped to repo"

# case 4: launched inside a worktree -> session scoped to the MAIN repo, and the
# session name matches launching from the main repo (per-project persistence).
mkrepo "$sandbox/main"
: >"$sandbox/main/valvonta.toml"
git -C "$sandbox/main" worktree add -q "$sandbox/linked-wt"
: >"$rec"
run "$sandbox/main" "$PATH_WITH" >/dev/null
sess_repo=$(awk '{print $4}' "$rec")
: >"$rec"
run "$sandbox/linked-wt" "$PATH_WITH" >/dev/null
sess_wt=$(awk '{print $4}' "$rec")
assert_contains "$(cat "$rec")" "valvonta --no-title --repo $sandbox/main" "worktree -> main repo resolution"
assert_eq "$sess_wt" "$sess_repo" "same session name from the repo and its worktree"

# case 5: git repo but no config -> hint, tmux never invoked
: >"$rec"
mkrepo "$sandbox/noconf"
out=$(run "$sandbox/noconf" "$PATH_WITH")
assert_contains "$out" "no config for" "missing config -> hint"
assert_empty "$(cat "$rec")" "missing config -> tmux not invoked"

# case 6: XDG user config -> exec tmux new-session
: >"$rec"
mkrepo "$sandbox/xdgconf"
mkdir -p "$sandbox/home/.config/valvonta"
: >"$sandbox/home/.config/valvonta/xdgconf.toml"
run "$sandbox/xdgconf" "$PATH_WITH" >/dev/null
assert_contains "$(cat "$rec")" "valvonta --no-title --repo $sandbox/xdgconf" "XDG config -> launches valvonta session"

pass
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `cd ~/Projects/dotfiles && bash tests/tmux-valvonta-popup.test.sh`
Expected: FAIL — the current launcher still `exec valvonta`, so the `tmux` stub records
nothing and case 3 fails, e.g.
`FAIL: configured repo -> persistent session: [] does not contain [new-session -A -s vlv-configured-]`

- [ ] **Step 3: Update the launcher success path**

In `bin/tmux-valvonta-popup`, replace these final lines (currently lines 49-51):

```bash
# exec so valvonta is the popup's foreground process; when the user quits (q),
# the command exits and display-popup -E tears the popup down.
exec valvonta --repo "$main_root"
```

with:

```bash
# Persistent per-project session: a stable name from the canonical root, so
# every worktree of a repo shares one instance. slug is human-readable; the
# cksum of the full path disambiguates same-named repos in different locations.
slug=$(printf '%s' "$repo_name" | tr -cs 'A-Za-z0-9_' '-' | sed 's/^-//; s/-$//')
hash=$(printf '%s' "$main_root" | cksum | cut -d' ' -f1)
session="vlv-${slug}-${hash}"

# -A attaches if the session exists (instant resume with preserved state), else
# creates it running valvonta with the banner hidden. Detaching (prefix v) hides
# it; `q` inside valvonta quits and ends the session. tmux new-session works
# inside a display-popup even though $TMUX is set, so no `env -u TMUX` is needed.
exec tmux new-session -A -s "$session" "valvonta --no-title --repo \"$main_root\""
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `cd ~/Projects/dotfiles && bash tests/tmux-valvonta-popup.test.sh`
Expected: PASS — ends with `ok (10 assertions)`.

- [ ] **Step 5: Run the whole suite**

Run: `cd ~/Projects/dotfiles && bash tests/run.sh`
Expected: ends with `ALL TESTS PASSED`, including `== tmux-valvonta-popup.test.sh` /
`ok (10 assertions)`. (The binding test still passes here — it's updated in Task 2.)

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/dotfiles && \
git add bin/tmux-valvonta-popup tests/tmux-valvonta-popup.test.sh && \
git commit -m "feat: launch valvonta in a persistent per-project tmux session (--no-title)"
```

---

## Task 2: Toggle binding (TDD)

**Files:**
- Modify: `.tmux.conf` (the `bind v` block)
- Test: `tests/tmux-valvonta-binding.test.sh`

- [ ] **Step 1: Update the binding test to expect the toggle**

In `tests/tmux-valvonta-binding.test.sh`, replace the assertions block (everything from the
first `assert_contains` down to and including the `case … esac` and its `assert_eq`) with:

```bash
assert_contains "$binding" "if-shell" "prefix-v is a toggle (if-shell)"
assert_contains "$binding" "session_name" "toggle keys off the session name"
assert_contains "$binding" "detach-client" "inside the float -> detach (hide)"
assert_contains "$binding" "display-popup" "outside the float -> open the popup"
assert_contains "$binding" "-d " "the popup sets its working dir via -d"
assert_contains "$binding" "pane_current_path" "the -d dir is #{pane_current_path}"

# The launcher must still NOT be handed a #{...} format (the original -d bug).
# tmux renders the shell-command last, so any "#{" appearing AFTER the script
# name would mean a format was wrongly passed as a launcher argument.
case "$binding" in
  *"tmux-valvonta-popup"*"#{"*) launcher_format="present" ;;
  *) launcher_format="absent" ;;
esac
assert_eq "$launcher_format" "absent" "launcher receives no #{...} argument"
```

Also change the line that extracts the binding so it reliably grabs the (now `if-shell`)
line. Replace:

```bash
binding=$(tmux -L "$sock" list-keys -T prefix 2>/dev/null | grep -- 'display-popup' || true)
```

with:

```bash
binding=$(tmux -L "$sock" list-keys -T prefix 2>/dev/null | grep -- 'tmux-valvonta-popup' || true)
```

- [ ] **Step 2: Run the binding test to verify it FAILS**

Run: `cd ~/Projects/dotfiles && bash tests/tmux-valvonta-binding.test.sh`
Expected: FAIL — the current binding has no `if-shell`, e.g.
`FAIL: prefix-v is a toggle (if-shell): [bind-key … display-popup …] does not contain [if-shell]`

- [ ] **Step 3: Replace the binding in `.tmux.conf`**

Replace this block:

```tmux
# floating valvonta dashboard for the current window's repo (prefix + v).
# The pane path goes through -d (tmux format-expands -d at run time); it must
# NOT be passed as a launcher argument, since tmux does not expand the
# display-popup shell-command (that sends the literal "#{pane_current_path}").
# The launcher reads its start dir from $PWD, which -d has set to the pane path.
bind v display-popup -E -b rounded -T ' valvonta ' -w 70% -h 40% \
  -d '#{pane_current_path}' "$HOME/bin/tmux-valvonta-popup"
```

with:

```tmux
# floating valvonta dashboard for the current window's repo (prefix + v).
# Toggle: inside the float (a vlv-* session) -> detach-client (hide; the session
# and valvonta keep running); anywhere else -> open the popup. The pane path goes
# through -d (tmux format-expands -d at run time, NOT the display-popup
# shell-command, which would send the literal "#{pane_current_path}"); the
# launcher reads $PWD. The launcher attaches/creates a persistent per-project
# `vlv-*` session running `valvonta --no-title`; `q` quits it, prefix-v hides it.
bind v if-shell -F '#{m:vlv-*,#{session_name}}' {
  detach-client
} {
  display-popup -E -b rounded -T ' valvonta ' -w 70% -h 40% \
    -d '#{pane_current_path}' "$HOME/bin/tmux-valvonta-popup"
}
```

- [ ] **Step 4: Run the binding test to verify it PASSES**

Run: `cd ~/Projects/dotfiles && bash tests/tmux-valvonta-binding.test.sh`
Expected: PASS — `ok (7 assertions)`.

- [ ] **Step 5: Run the whole suite**

Run: `cd ~/Projects/dotfiles && bash tests/run.sh`
Expected: `ALL TESTS PASSED`, including `tmux-valvonta-binding.test.sh` / `ok (7 assertions)`
and `tmux-valvonta-popup.test.sh` / `ok (10 assertions)`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/dotfiles && \
git add .tmux.conf tests/tmux-valvonta-binding.test.sh && \
git commit -m "feat: make prefix-v a toggle (hide/show the persistent valvonta float)"
```

---

## Task 3: Live verification + update PR

The unit tests cover the launcher command and the binding shape; the session lifecycle and
the interactive toggle can only be confirmed by running tmux for real.

- [ ] **Step 1: Source the updated config live**

Run: `cd ~/Projects/dotfiles && tmux source-file ~/.tmux.conf && tmux list-keys -T prefix | grep -- 'tmux-valvonta-popup'`
Expected: the binding prints as an `if-shell … { detach-client } { display-popup … }` line.

- [ ] **Step 2: Semi-automated session-lifecycle check (no popup needed)**

This proves the tmux mechanics the toggle's persistence relies on — a `vlv-*` session
persists while detached and `new-session -A` re-attaches without duplicating. (A benign
`sleep` stands in for valvonta so the check doesn't depend on valvonta starting cleanly on a
bare repo; valvonta actually rendering in the session is the manual checklist below.)

Run:
```bash
sess="vlv-livecheck-$$"
tmux new-session -d -s "$sess" 'sleep 30'
sleep 1
tmux has-session -t "$sess" 2>/dev/null && echo "OK: session persists while detached"
tmux list-sessions -F '#{session_name}' | grep -q "$sess" && echo "OK: appears in tmux ls (expected tradeoff)"
# -A on the existing session must attach, not duplicate:
n1=$(tmux list-sessions | wc -l | tr -d ' ')
tmux new-session -d -A -s "$sess" 'true' 2>/dev/null || true
n2=$(tmux list-sessions | wc -l | tr -d ' ')
[ "$n1" = "$n2" ] && echo "OK: new-session -A attaches, no duplicate"
tmux kill-session -t "$sess" 2>/dev/null
```
Expected: three `OK:` lines.

- [ ] **Step 3: Manual interactive toggle checklist (controller + user)**

In a window whose repo has a `valvonta.toml` (create one if needed, or use Step 2's
`valvonta.example.toml` as a base):
- `Ctrl-b v` → the float opens with **no VALVONTA banner**.
- `Ctrl-b v` again (inside the float) → it **hides**; `tmux ls` still shows the `vlv-*`
  session.
- `Ctrl-b v` again → the **same** instance reappears (state preserved).
- In a different project's window, `Ctrl-b v` → a **separate** `vlv-*` session.
- Inside the float, `q` → valvonta quits and the session ends (`tmux ls` no longer lists it).

- [ ] **Step 4: Update PR #7 to reflect the expanded scope**

Run:
```bash
cd ~/Projects/dotfiles && \
gh pr edit 7 --title "feat: floating valvonta popup — toggle, per-project persistence, hidden banner (+ -d path fix)"
```
Then push the new commits (the branch already tracks origin):
```bash
cd ~/Projects/dotfiles && git push
```
(If the user prefers the bare `-d` fix as its own PR, split instead — but the toggle
rewrites the same binding, so folding avoids a conflicting parallel PR.)
