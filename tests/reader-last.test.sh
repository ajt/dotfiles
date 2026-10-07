#!/usr/bin/env bash
# Tests for `reader-last --meta` and the tab title / meta attributes
# reader-render -T builds from it.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

tmp=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/.git" "$tmp/repo/sub" "$tmp/wt/feature" "$tmp/plain"
: > "$tmp/wt/feature/.git"   # a worktree: .git is a file

t="$tmp/claude.jsonl"
python3 - "$t" "$tmp/repo/sub" <<'PY'
import json, sys
path, cwd = sys.argv[1:]
with open(path, "w") as fh:
    fh.write(json.dumps({"type": "mode", "sessionId": "s1"}) + "\n")
    fh.write(json.dumps({"type": "user", "sessionId": "s1", "cwd": cwd, "gitBranch": "main",
                         "message": {"content": "hi"}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "sessionId": "s1", "cwd": cwd, "gitBranch": "main",
                         "message": {"content": [{"type": "text", "text": "# Reply\n\nhello"}]}}) + "\n")
    fh.write(json.dumps({"type": "ai-title", "aiTitle": "Reader tab titles", "sessionId": "s1"}) + "\n")
    fh.write(json.dumps({"type": "user", "sessionId": "s1", "cwd": cwd, "gitBranch": "feature/x",
                         "message": {"content": "again"}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "sessionId": "s1", "cwd": cwd, "gitBranch": "feature/x",
                         "isSidechain": True, "message": {"content": [{"type": "text", "text": "sub"}]}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "sessionId": "s1", "cwd": cwd, "gitBranch": "feature/x",
                         "message": {"content": [{"type": "text", "text": "second"}]}}) + "\n")
PY

field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
meta=$("$here/../bin/reader-last" --meta "$t")
assert_eq "$?" 0 "--meta succeeds"
assert_eq "$(printf '%s' "$meta" | field kind)" "claude" "kind"
assert_eq "$(printf '%s' "$meta" | field label)" "Claude Code" "label"
assert_eq "$(printf '%s' "$meta" | field path)" "$t" "path"
assert_eq "$(printf '%s' "$meta" | field session_id)" "s1" "session id"
assert_eq "$(printf '%s' "$meta" | field title)" "Reader tab titles" "ai title"
assert_eq "$(printf '%s' "$meta" | field cwd)" "$tmp/repo/sub" "cwd of the last turn"
assert_eq "$(printf '%s' "$meta" | field project)" "repo" "project is the checkout, not the subdirectory"
assert_eq "$(printf '%s' "$meta" | field branch)" "feature/x" "branch of the last turn"

# --- a renamed session wins over the generated title ------------------------
printf '%s\n' '{"type":"custom-title","customTitle":"My name","sessionId":"s1"}' >> "$t"
assert_eq "$("$here/../bin/reader-last" --meta "$t" | field title)" "My name" "custom title"

# --- a worktree is named after itself; outside git, the directory -----------
w="$tmp/wt.jsonl"
printf '%s\n' "{\"type\":\"user\",\"cwd\":\"$tmp/wt/feature\",\"message\":{\"content\":\"x\"}}" > "$w"
assert_eq "$("$here/../bin/reader-last" --meta "$w" | field project)" "feature" "worktree name"
printf '%s\n' "{\"type\":\"user\",\"cwd\":\"$tmp/plain\",\"message\":{\"content\":\"x\"}}" > "$w"
assert_eq "$("$here/../bin/reader-last" --meta "$w" | field project)" "plain" "plain directory"
assert_eq "$("$here/../bin/reader-last" --meta "$w" | field title)" "" "no title on a new session"

# --- Codex: cwd from session_meta, nothing else -----------------------------
c="$tmp/codex.jsonl"
printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"id\":\"c1\",\"cwd\":\"$tmp/repo\"}}" \
  '{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"hi"}]}}' > "$c"
meta=$("$here/../bin/reader-last" --meta "$c")
assert_eq "$(printf '%s' "$meta" | field label)" "Codex" "codex label"
assert_eq "$(printf '%s' "$meta" | field project)" "repo" "codex project"
assert_eq "$(printf '%s' "$meta" | field session_id)" "c1" "codex session id"
assert_eq "$(printf '%s' "$meta" | field title)" "" "codex has no title"

# --- a missing transcript fails ---------------------------------------------
assert_fail "$here/../bin/reader-last" --meta "$tmp/nope.jsonl" 2>/dev/null

# --- reader-render -T: tab title and body attributes ------------------------
if command -v pandoc >/dev/null 2>&1; then
  html=$(printf '# Reply\n\nhello\n' | "$here/../bin/reader-render" -n -T "$t" -o "$tmp/a.html" >/dev/null && cat "$tmp/a.html")
  assert_contains "$html" "<title>My name · repo</title>" "tab: session title, then project"
  assert_contains "$html" 'data-source="Claude Code"' "source is the agent"
  assert_contains "$html" 'data-session="My name"' "session attribute"
  assert_contains "$html" 'data-project="repo"' "project attribute"
  assert_contains "$html" 'data-branch="feature/x"' "branch attribute"

  html=$(printf '# Reply\n\nhello\n' | "$here/../bin/reader-render" -n -T "$c" -o "$tmp/b.html" >/dev/null && cat "$tmp/b.html")
  assert_contains "$html" "<title>Reply · repo</title>" "tab: heading when the session has no title"
  html=$(printf 'hello\n' | "$here/../bin/reader-render" -n -T "$c" -o "$tmp/c.html" >/dev/null && cat "$tmp/c.html")
  assert_contains "$html" "<title>Codex · repo</title>" "tab: the agent when there is no heading either"

  html=$(printf '# Notes\n\nhello\n' | "$here/../bin/reader-render" -n -t Clipboard -o "$tmp/d.html" >/dev/null && cat "$tmp/d.html")
  assert_contains "$html" "<title>Notes</title>" "no transcript: the heading"
  assert_contains "$html" 'data-session="" data-project="" data-branch="" data-cwd=""' "no transcript: empty attributes"
  html=$(printf 'hello\n' | "$here/../bin/reader-render" -n -o "$tmp/e.html" >/dev/null && cat "$tmp/e.html")
  assert_contains "$html" "<title>Terminal output</title>" "no transcript, no heading: -t default"

  html=$(printf 'hello\n' | "$here/../bin/reader-render" -n -t Clipboard -T "$tmp/nope.jsonl" -o "$tmp/f.html" 2>/dev/null >/dev/null && cat "$tmp/f.html")
  assert_contains "$html" "<title>Clipboard</title>" "unreadable transcript: falls back to -t"
else
  echo "skip: pandoc not installed, reader-render not tested" >&2
fi

pass
