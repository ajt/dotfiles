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
for t in git awk basename cksum tr sed cut; do ln -s "$(command -v "$t")" "$tooldir/$t"; done

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

# case 2: valvonta not installed -> hint, tmux never invoked
: >"$rec"
out=$(run "$sandbox" "$PATH_WITHOUT")
assert_contains "$out" "not installed" "missing valvonta -> hint"
assert_empty "$(cat "$rec")" "missing valvonta -> tmux not invoked"

# case 3: configured repo -> exec tmux new-session running valvonta --no-title
: >"$rec"
mkrepo "$sandbox/configured"
: >"$sandbox/configured/valvonta.toml"
run "$sandbox/configured" "$PATH_WITH" >/dev/null
got=$(cat "$rec")
assert_contains "$got" "new-session -A -s vlv-configured-" "configured repo -> persistent session"
assert_contains "$got" "valvonta --no-title --repo \"$sandbox/configured\"" "session runs valvonta --no-title scoped to repo"

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
assert_contains "$(cat "$rec")" "valvonta --no-title --repo \"$sandbox/main\"" "worktree -> main repo resolution"
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
assert_contains "$(cat "$rec")" "valvonta --no-title --repo \"$sandbox/xdgconf\"" "XDG config -> launches valvonta session"

# case 7: a repo path with a space must be quoted in the session command, so
# valvonta receives it as one --repo argument (regression guard for the inner
# quoting; the unquoted form would split the path).
: >"$rec"
mkrepo "$sandbox/has space"
: >"$sandbox/has space/valvonta.toml"
run "$sandbox/has space" "$PATH_WITH" >/dev/null
assert_contains "$(cat "$rec")" "valvonta --no-title --repo \"$sandbox/has space\"" "path with spaces stays one --repo argument"

pass
