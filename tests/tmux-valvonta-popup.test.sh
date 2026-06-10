#!/usr/bin/env bash
# Tests for bin/tmux-valvonta-popup. The launcher's success path is
# attach-or-create: `tmux has-session -t =vlv-<slug>-<hash>`; if absent,
# `new-session -d -s <name> -c $HOME "valvonta --no-title --tmux-popup --repo
# <root>"` + `set-option <name> status off`; then always `attach-session`.
# Its failure paths print a stay-open hint.
# Strategy: real throwaway git repos (no git stubbing) + a `tmux` stub that
# records its args (has-session exits TMUX_STUB_HAS_SESSION, default 1 = "no
# such session", so the create path runs) + a `valvonta` stub present only so
# `command -v valvonta` passes (valvonta is named inside the session command,
# never executed by the launcher). Each run gets a locked-down PATH and
# hermetic HOME, stdin from /dev/null so the hint's read returns instead of
# blocking.
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

# tmux stub: records every invocation; has-session reports "no such session"
# unless TMUX_STUB_HAS_SESSION=0 (an existing session).
rec="$sandbox/tmux.args"
cat >"$tooldir/tmux" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$rec"
case "\$1" in
  has-session) exit "\${TMUX_STUB_HAS_SESSION:-1}" ;;
esac
exit 0
EOF
chmod +x "$tooldir/tmux"

# valvonta stub: present only so `command -v valvonta` succeeds; never executed.
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

run() { # <start-dir> <path> [has-session-exit]
  env HOME="$sandbox/home" PATH="$2" TMUX_STUB_HAS_SESSION="${3:-1}" \
    "$bash_bin" "$script" "$1" </dev/null 2>&1
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

# case 3: configured repo, no existing session -> create detached, configure,
# then attach
: >"$rec"
mkrepo "$sandbox/configured"
: >"$sandbox/configured/valvonta.toml"
run "$sandbox/configured" "$PATH_WITH" >/dev/null
got=$(cat "$rec")
assert_contains "$got" "has-session -t =vlv-configured-" "existence probed with exact-match (=) target"
assert_contains "$got" "new-session -d -s vlv-configured-" "no session yet -> created detached"
assert_contains "$got" "-c $sandbox/home" "session pane starts in \$HOME, not the repo"
assert_contains "$got" "valvonta --no-title --tmux-popup --repo \"$sandbox/configured\"" "session runs valvonta in popup mode scoped to repo"
assert_ok grep -Eq 'set-option -t vlv-configured-.* status off' "$rec"
assert_contains "$got" "attach-session -t vlv-configured-" "launcher attaches to the session"

# case 3b: session already exists -> attach only, never re-create
: >"$rec"
run "$sandbox/configured" "$PATH_WITH" 0 >/dev/null
assert_eq "$(grep -c '^new-session' "$rec")" "0" "existing session -> not re-created"
assert_contains "$(cat "$rec")" "attach-session -t vlv-configured-" "existing session -> attach only"

# case 4: launched inside a worktree -> session scoped to the MAIN repo, and the
# session name matches launching from the main repo (per-project persistence).
mkrepo "$sandbox/main"
: >"$sandbox/main/valvonta.toml"
git -C "$sandbox/main" worktree add -q "$sandbox/linked-wt"
: >"$rec"
run "$sandbox/main" "$PATH_WITH" >/dev/null
sess_repo=$(awk '/^new-session/{print $4}' "$rec")
assert_ok test -n "$sess_repo"
: >"$rec"
run "$sandbox/linked-wt" "$PATH_WITH" >/dev/null
sess_wt=$(awk '/^new-session/{print $4}' "$rec")
assert_contains "$(cat "$rec")" "valvonta --no-title --tmux-popup --repo \"$sandbox/main\"" "worktree -> main repo resolution"
assert_eq "$sess_wt" "$sess_repo" "same session name from the repo and its worktree"

# case 5: git repo but no config -> hint, tmux never invoked
: >"$rec"
mkrepo "$sandbox/noconf"
out=$(run "$sandbox/noconf" "$PATH_WITH")
assert_contains "$out" "no config for" "missing config -> hint"
assert_empty "$(cat "$rec")" "missing config -> tmux not invoked"

# case 6: XDG user config -> launches the session
: >"$rec"
mkrepo "$sandbox/xdgconf"
mkdir -p "$sandbox/home/.config/valvonta"
: >"$sandbox/home/.config/valvonta/xdgconf.toml"
run "$sandbox/xdgconf" "$PATH_WITH" >/dev/null
assert_contains "$(cat "$rec")" "valvonta --no-title --tmux-popup --repo \"$sandbox/xdgconf\"" "XDG config -> launches valvonta session"

# case 7: a repo path with a space must be quoted in the session command, so
# valvonta receives it as one --repo argument (regression guard for the inner
# quoting; the unquoted form would split the path).
: >"$rec"
mkrepo "$sandbox/has space"
: >"$sandbox/has space/valvonta.toml"
run "$sandbox/has space" "$PATH_WITH" >/dev/null
assert_contains "$(cat "$rec")" "valvonta --no-title --tmux-popup --repo \"$sandbox/has space\"" "path with spaces stays one --repo argument"

pass
