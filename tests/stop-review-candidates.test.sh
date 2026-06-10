#!/usr/bin/env bash
# stop-review.py candidate selection + block plumbing, end to end, no network:
# `uv` is stubbed to emulate review.py's contract (exit 0 if a .review.md sits
# next to the artifact, else exit 3 = no key), so no Gemini call can ever fire.
# Guards the regressions found in review: non-ASCII changed paths escaping the
# gate (-z), committed-in-same-turn artifacts being skipped (fresh window),
# old tracked-clean artifacts NOT being re-reviewed every stop, and the
# round limit that stops the autonomous edit/re-review ping-pong.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

SR="$here/../claude/review/stop-review.py"
sandbox=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$sandbox"' EXIT

# uv stub: emulates review.py -- exit 0 when a review file already exists for
# --file (the warm/content-hash path), else exit 3 (no API key).
stubdir="$sandbox/stub"; mkdir -p "$stubdir"
cat >"$stubdir/uv" <<'EOF'
#!/bin/sh
file=
while [ $# -gt 0 ]; do
  [ "$1" = "--file" ] && { file=$2; shift; }
  shift
done
[ -n "$file" ] && [ -f "$file.review.md" ] && exit 0
echo "[cross-review] SKIPPED -- no GEMINI_API_KEY" >&2
exit 3
EOF
chmod +x "$stubdir/uv"

repo="$sandbox/repo"
mkdir -p "$repo/docs/superpowers/plans"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name test

# B: tracked, clean, OLD -> must be skipped (not re-reviewed every stop)
# C: tracked, clean, FRESH -> committed-this-turn case, must still be reviewed
printf '# b\n' > "$repo/docs/superpowers/plans/b-plan.md"
printf '# c\n' > "$repo/docs/superpowers/plans/c-plan.md"
git -C "$repo" add -A
git -C "$repo" commit -qm artifacts
touch -t 202601010000 "$repo/docs/superpowers/plans/b-plan.md"

# A: untracked, with a CHANGES review on disk -> must block
printf '# a\n' > "$repo/docs/superpowers/plans/a-plan.md"
printf 'VERDICT: CHANGES\n\n## Verdict\nneeds work\n' \
  > "$repo/docs/superpowers/plans/a-plan.md.review.md"

# D: untracked with a non-ASCII name -> must still be detected (-z plumbing)
printf '# d\n' > "$repo/plän-plan.md"

out=$(printf '{"cwd":"%s"}' "$repo" \
  | env REVIEW_STATE_DIR="$sandbox/state" PATH="$stubdir:$PATH" python3 "$SR")

assert_contains "$out" '"decision": "block"' "gate blocks"
assert_contains "$out" "a-plan.md\` -> CHANGES" "untracked artifact with CHANGES review blocks"
assert_contains "$out" "c-plan.md" "fresh tracked-clean artifact still reviewed (committed-in-turn)"
assert_contains "$out" "n-plan.md" "non-ASCII changed path detected (-z)"
assert_eq "$(printf '%s' "$out" | grep -c 'b-plan.md')" "0" "old tracked-clean artifact skipped"

# second run, same content: block_once markers recorded -> silence (exit 0,
# no output) so the gate can never trap a session
out2=$(printf '{"cwd":"%s"}' "$repo" \
  | env REVIEW_STATE_DIR="$sandbox/state" PATH="$stubdir:$PATH" python3 "$SR")
rc=$?
assert_eq "$rc" "0" "repeat stop on unchanged content allows"
assert_empty "$out2" "repeat stop is silent"

# round limit: each new content version blocks again; the third consecutive
# blocked version must tell Claude to stop editing and defer to the human
rerun() {
  printf '# a v%s\n' "$1" > "$repo/docs/superpowers/plans/a-plan.md"
  printf '{"cwd":"%s"}' "$repo" \
    | env REVIEW_STATE_DIR="$sandbox/state" PATH="$stubdir:$PATH" python3 "$SR"
}
out3=$(rerun 2)
assert_contains "$out3" '"decision": "block"' "new version blocks again (round 2)"
assert_eq "$(printf '%s' "$out3" | grep -c 'ROUND LIMIT')" "0" "round 2 has no limit warning"
out4=$(rerun 3)
assert_contains "$out4" "ROUND LIMIT" "round 3 defers to the human"

pass
