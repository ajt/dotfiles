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

# case 6: XDG user config (~/.config/valvonta/<name>.toml) -> exec valvonta
: >"$rec"
mkrepo "$sandbox/xdgconf"
mkdir -p "$sandbox/home/.config/valvonta"
: >"$sandbox/home/.config/valvonta/xdgconf.toml"
run "$sandbox/xdgconf" "$PATH_WITH" >/dev/null
assert_eq "$(cat "$rec")" "--repo $sandbox/xdgconf" "XDG user config -> launches valvonta"

pass
