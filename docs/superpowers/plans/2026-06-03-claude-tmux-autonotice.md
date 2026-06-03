# Claude First-Prompt tmux Auto-Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-generate a one-line tmux window notice for any unstamped tmux window running Claude, summarizing the session's first prompt via a cheap/fast model.

**Architecture:** A new `UserPromptSubmit` hook script (`bin/claude-tmux-notice`) is the data source: on the first prompt of an unstamped tmux window it stamps `@wt_branch` + a `summarizing…` `@wt_title`, shows the box, and forks a detached background job that calls the Anthropic Messages API (`claude-haiku-4-5`) and updates `@wt_title`. The existing `bin/tmux-worktree-notice` stays the pure renderer — its `render()` is unchanged; we add only a small `refresh` subcommand so an async title update repaints the box by `SIGWINCH`-ing the render process.

**Tech Stack:** bash, tmux user options (`@wt_*`), `jq`, `curl`, Anthropic Messages API. Tests are a dependency-free pure-bash harness using function overrides for `tmux`/`curl`/`git`/`kill`.

---

## File Structure

- **Create `bin/claude-tmux-notice`** — the hook script. Reads hook JSON on stdin; guard + stamp + show + fork; `summarize` subcommand does the API call and title update. Functions are factored (`_should_act`, `_branch_for`, `_normalize_title`, `_extract_summary`, `_fallback_title`, `_api_summary`, `_dispatch_summary`, `summarize`, `hook`) so unit tests can drive them in isolation. Ends with a source-guard so tests can load it as a library.
- **Modify `bin/tmux-worktree-notice`** — add a `refresh` subcommand, register it in `main`/usage, update the header comment, and replace the final `main "$@"` with a source-guard.
- **Create `tests/lib.sh`** — minimal assert helpers (`assert_eq`, `assert_empty`, `assert_contains`, `assert_ok`, `assert_fail`, `fail`, `pass`).
- **Create `tests/run.sh`** — runs every `tests/*.test.sh`, exits nonzero if any fail.
- **Create `tests/tmux-worktree-notice.test.sh`** — tests for `refresh`.
- **Create `tests/claude-tmux-notice.test.sh`** — tests for the guard, summary extraction/normalization, fallback, hook stdout silence, and stamping.
- **Modify `setup-a-new-machine.sh`** — add a "Claude Code hooks" section documenting the `~/.claude/settings.json` entry + `ANTHROPIC_API_KEY`, and a reminder line in the closing box.
- **Modify `CLAUDE.md`** — add a `bin/` bullet for `claude-tmux-notice`.

**Conventions to match** (from `bin/tmux-worktree-notice`): `#!/usr/bin/env bash`, `set -u`, the `case "$0"` block that resolves an absolute `SELF`, helper functions prefixed `_`, a `main()` dispatching subcommands, and a usage string on unknown subcommands.

---

## Task 1: Test harness scaffolding

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/run.sh`

- [ ] **Step 1: Create `tests/lib.sh`**

```bash
# Minimal test helpers for the dotfiles bin/ scripts.
# Source from a *.test.sh file, then call the assert_* helpers. A failed
# assertion prints to stderr and exits 1 (so the test file fails fast).

_tests_run=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

assert_eq() { # <actual> <expected> [msg]
  _tests_run=$((_tests_run + 1))
  [ "$1" = "$2" ] || fail "${3:-assert_eq}: expected [$2], got [$1]"
}

assert_empty() { # <actual> [msg]
  _tests_run=$((_tests_run + 1))
  [ -z "$1" ] || fail "${2:-assert_empty}: expected empty, got [$1]"
}

assert_contains() { # <haystack> <needle> [msg]
  _tests_run=$((_tests_run + 1))
  case "$1" in
    *"$2"*) : ;;
    *) fail "${3:-assert_contains}: [$1] does not contain [$2]" ;;
  esac
}

assert_ok() { # <cmd...>  — command must succeed
  _tests_run=$((_tests_run + 1))
  "$@" || fail "assert_ok: command failed: $*"
}

assert_fail() { # <cmd...>  — command must fail (nonzero)
  _tests_run=$((_tests_run + 1))
  if "$@"; then fail "assert_fail: command unexpectedly succeeded: $*"; fi
}

pass() { printf 'ok (%d assertions)\n' "$_tests_run"; }
```

- [ ] **Step 2: Create `tests/run.sh`**

```bash
#!/usr/bin/env bash
# Run every tests/*.test.sh. Exit nonzero if any test file fails.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)

fails=0
for t in "$here"/*.test.sh; do
  [ -e "$t" ] || continue
  printf '== %s\n' "$(basename "$t")"
  bash "$t" || fails=$((fails + 1))
done

if [ "$fails" -eq 0 ]; then
  printf 'ALL TESTS PASSED\n'
  exit 0
fi
printf '%d TEST FILE(S) FAILED\n' "$fails" >&2
exit 1
```

- [ ] **Step 3: Make the runner executable**

Run: `chmod +x tests/run.sh`

- [ ] **Step 4: Verify the runner works with no test files yet**

Run: `bash tests/run.sh`
Expected: prints `ALL TESTS PASSED` and exits 0 (the glob matches nothing, the loop is skipped).

- [ ] **Step 5: Commit**

```bash
git add tests/lib.sh tests/run.sh
git commit -m "Add minimal bash test harness for bin/ scripts"
```

---

## Task 2: `refresh` subcommand in `tmux-worktree-notice`

**Files:**
- Modify: `bin/tmux-worktree-notice` (header comment line 3; new `refresh()`; `main` case + usage; final `main "$@"`)
- Create/Test: `tests/tmux-worktree-notice.test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/tmux-worktree-notice.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for the `refresh` subcommand of bin/tmux-worktree-notice.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

# Source the script as a library (guard keeps main() from running).
TMUX_WORKTREE_NOTICE_SOURCED=1 . "$here/../bin/tmux-worktree-notice"

# --- refresh signals the banner pane's render pid with SIGWINCH -------------
KILLED=""
kill() { KILLED="$*"; }          # capture instead of really signalling
tmux() {                         # banner-present fake
  case "$*" in
    *"display-message -p"*window_id*) printf '@7\n' ;;
    *"display-message -p"*pane_pid*)  printf '4242\n' ;;
    *"list-panes"*)                   printf '%%9 1\n' ;;  # pane %9 has @wt_banner=1
  esac
}
refresh @7
assert_eq "$KILLED" "-WINCH 4242" "refresh signals render pid with WINCH"

# --- refresh is a no-op when there is no banner pane ------------------------
KILLED=""
tmux() {
  case "$*" in
    *"display-message -p"*window_id*) printf '@7\n' ;;
    *"list-panes"*)                   printf '%%9 0\n' ;;  # nothing flagged
  esac
}
assert_ok refresh @7
assert_empty "$KILLED" "refresh does not signal without a banner pane"

pass
```

- [ ] **Step 2: Run the test, expect failure**

Run: `bash tests/tmux-worktree-notice.test.sh`
Expected: FAIL — sourcing aborts or `refresh` is undefined (the source-guard and `refresh()` don't exist yet).

- [ ] **Step 3: Add the source-guard to `bin/tmux-worktree-notice`**

Replace the final line (currently `main "$@"`) at the bottom of the file with:

```bash
# Allow tests to source this file as a library without executing.
if [ "${TMUX_WORKTREE_NOTICE_SOURCED:-}" != 1 ]; then
  main "$@"
fi
```

- [ ] **Step 4: Add the `refresh()` function**

Insert after the `toggle()` function (before `main()`):

```bash
# refresh [target]
# Repaint the banner box from the current @wt_* options by signalling the render
# process (its WINCH trap redraws). No-op when the window has no banner pane.
refresh() {
  local win bp pid
  win=$(_win "${1:-}") || return 1
  bp=$(_banner_pane "$win")
  [ -n "$bp" ] || return 0
  pid=$(tmux display-message -p -t "$bp" '#{pane_pid}')
  [ -n "$pid" ] && kill -WINCH "$pid" 2>/dev/null
  return 0
}
```

- [ ] **Step 5: Register `refresh` in `main()` and the usage string**

In the `case` inside `main()`, add a line after the `toggle)` line:

```bash
    refresh) refresh "$@" ;;
```

And change the usage line to include `refresh`:

```bash
    *) printf 'usage: tmux-worktree-notice {show|hide|toggle|refresh|render|draw}\n' >&2; exit 2 ;;
```

- [ ] **Step 6: Update the header comment (line 3)**

Change:

```bash
# Subcommands: draw | render | show | hide | toggle
```

to:

```bash
# Subcommands: draw | render | show | hide | toggle | refresh
```

- [ ] **Step 7: Run the test, expect pass**

Run: `bash tests/tmux-worktree-notice.test.sh`
Expected: `ok (3 assertions)` and exit 0.

- [ ] **Step 8: Commit**

```bash
git add bin/tmux-worktree-notice tests/tmux-worktree-notice.test.sh
git commit -m "Add refresh subcommand to tmux-worktree-notice"
```

---

## Task 3: `claude-tmux-notice` skeleton + guard logic

**Files:**
- Create: `bin/claude-tmux-notice`
- Create/Test: `tests/claude-tmux-notice.test.sh`

- [ ] **Step 1: Write the failing test (guard + skeleton)**

Create `tests/claude-tmux-notice.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for bin/claude-tmux-notice.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

CLAUDE_TMUX_NOTICE_SOURCED=1 . "$here/../bin/claude-tmux-notice"

# ---- _should_act guard -----------------------------------------------------
export TMUX=/tmp/fake-tmux-socket
# manual window: no @wt_num, no @wt_title -> act
tmux() { case "$*" in *@wt_num*) printf '' ;; *@wt_title*) printf '' ;; esac; }
assert_ok _should_act @1 "manual window should act"
# issue window: @wt_num set -> skip
tmux() { case "$*" in *@wt_num*) printf '42\n' ;; *@wt_title*) printf '' ;; esac; }
assert_fail _should_act @1 "issue window (@wt_num) should skip"
# already labelled: @wt_title set -> skip
tmux() { case "$*" in *@wt_num*) printf '' ;; *@wt_title*) printf 'Do a thing\n' ;; esac; }
assert_fail _should_act @1 "labelled window (@wt_title) should skip"
# not in tmux -> skip
( unset TMUX; assert_fail _should_act @1 "no TMUX should skip" )

pass
```

- [ ] **Step 2: Run the test, expect failure**

Run: `bash tests/claude-tmux-notice.test.sh`
Expected: FAIL — `bin/claude-tmux-notice` does not exist, so sourcing fails.

- [ ] **Step 3: Create `bin/claude-tmux-notice` with the skeleton + guard**

```bash
#!/usr/bin/env bash
# claude-tmux-notice — Claude Code UserPromptSubmit hook that auto-labels the
# current tmux window from the session's FIRST prompt.
#
# Wiring (~/.claude/settings.json):
#   { "hooks": { "UserPromptSubmit": [ { "hooks": [
#       { "type": "command", "command": "~/bin/claude-tmux-notice" } ] } ] } }
#
# On the first prompt of an unstamped tmux window it stamps @wt_branch + a
# "summarizing…" @wt_title, shows the notice box (via tmux-worktree-notice), and
# forks a detached background job that asks claude-haiku-4-5 for a <=6-word label
# and updates @wt_title. Prints NOTHING to stdout (UserPromptSubmit stdout is
# injected into the prompt context). Never errors the window.
#
# Subcommands (internal): hook (default) | summarize <win> <cwd> <promptfile>
set -u

API_URL="https://api.anthropic.com/v1/messages"
API_MODEL="claude-haiku-4-5"
SYSTEM_PROMPT='You write terse tmux window labels. Summarize the user request as an imperative phrase of at most 6 words. No surrounding quotes, no trailing punctuation, no preamble. Output only the label.'

# Absolute path to self, so the background re-invocation works under any PATH.
case "$0" in
  /*)   SELF="$0" ;;
  */*)  SELF="$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")" ;;
  *)    SELF="$(command -v -- "$0" 2>/dev/null || printf '%s' "$0")" ;;
esac

# _window_for_pane <pane> -> window id containing <pane>
_window_for_pane() {
  tmux display-message -p -t "$1" '#{window_id}' 2>/dev/null
}

# _should_act <window-id> -> success if we should auto-label: inside tmux, and
# the window has neither @wt_num nor @wt_title yet.
_should_act() {
  [ -n "${TMUX:-}" ] || return 1
  local num title
  num=$(tmux show-options -wqv -t "$1" @wt_num 2>/dev/null)
  title=$(tmux show-options -wqv -t "$1" @wt_title 2>/dev/null)
  [ -z "$num" ] && [ -z "$title" ]
}

main() {
  case "${1:-hook}" in
    hook)      : ;;   # filled in Task 5
    summarize) : ;;   # filled in Task 5
    *) printf 'usage: claude-tmux-notice [hook|summarize <win> <cwd> <promptfile>]\n' >&2; exit 2 ;;
  esac
}

# Allow tests to source this file as a library without executing.
if [ "${CLAUDE_TMUX_NOTICE_SOURCED:-}" != 1 ]; then
  main "$@"
fi
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x bin/claude-tmux-notice`

- [ ] **Step 5: Run the test, expect pass**

Run: `bash tests/claude-tmux-notice.test.sh`
Expected: prints `ok (...)` and exits 0 (the exact assertion count is cosmetic; assertions inside `( … )` subshells don't increment the parent counter).

- [ ] **Step 6: Commit**

```bash
git add bin/claude-tmux-notice tests/claude-tmux-notice.test.sh
git commit -m "Add claude-tmux-notice skeleton with should-act guard"
```

---

## Task 4: Summary extraction, normalization, fallback, and API call

**Files:**
- Modify: `bin/claude-tmux-notice` (add helper functions before `main()`)
- Modify: `tests/claude-tmux-notice.test.sh` (append assertions before `pass`)

- [ ] **Step 1: Add the failing tests**

In `tests/claude-tmux-notice.test.sh`, insert the following **before** the final `pass` line:

```bash
# ---- _normalize_title ------------------------------------------------------
assert_eq "$(_normalize_title '  Fix the bug  ')" "Fix the bug" "trims whitespace"
assert_eq "$(_normalize_title $'Line one\nLine two')" "Line one Line two" "flattens newlines"
assert_eq "$(_normalize_title '"Quoted label"')" "Quoted label" "strips surrounding quotes"
assert_eq "$(_normalize_title 'short label')" "short label" "short titles unchanged"
long_out=$(_normalize_title "$(printf 'a%.0s' {1..60})")
assert_contains "$long_out" "…" "long titles get an ellipsis"

# ---- _extract_summary ------------------------------------------------------
assert_eq "$(_extract_summary '{"content":[{"type":"text","text":"Fix flaky test"}]}')" "Fix flaky test" "extracts content text"
assert_empty "$(_extract_summary '{"error":{"type":"overloaded"}}')" "no text on error response"
assert_empty "$(_extract_summary 'not json at all')" "no text on garbage"

# ---- _fallback_title -------------------------------------------------------
assert_eq "$(_fallback_title $'Please refactor the parser\nand add tests')" "Please refactor the parser" "fallback uses first line"

# ---- _api_summary ----------------------------------------------------------
( unset ANTHROPIC_API_KEY; assert_fail _api_summary "do something" "no key short-circuits" )
export ANTHROPIC_API_KEY=test-key
curl() { printf '{"content":[{"type":"text","text":" Add refresh subcommand "}]}'; }
assert_eq "$(_api_summary 'add the refresh subcommand')" "Add refresh subcommand" "api summary normalized"
curl() { return 7; }
assert_fail _api_summary "anything" "curl failure propagates"
```

- [ ] **Step 2: Run the test, expect failure**

Run: `bash tests/claude-tmux-notice.test.sh`
Expected: FAIL — `_normalize_title` (and the other helpers) are undefined.

- [ ] **Step 3: Add the helper functions to `bin/claude-tmux-notice`**

Insert these functions immediately **before** `main()`:

```bash
# _branch_for <cwd> -> current git branch, or the cwd basename if not a repo.
_branch_for() {
  local b
  b=$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$b" ] && [ "$b" != HEAD ]; then printf '%s' "$b"; else printf '%s' "${1##*/}"; fi
}

# _normalize_title <raw> -> single line, no surrounding quotes, trimmed to 48 chars.
_normalize_title() {
  local t=$1
  t=${t//$'\n'/ }                              # newlines -> spaces
  t="$(printf '%s' "$t" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  t=${t#\"}; t=${t%\"}                          # strip one layer of surrounding quotes
  t=${t#\'}; t=${t%\'}
  [ "${#t}" -gt 48 ] && t="${t:0:47}…"
  printf '%s' "$t"
}

# _extract_summary <api-json> -> the model's text (.content[0].text), else empty.
_extract_summary() {
  printf '%s' "$1" | jq -r '.content[0].text // empty' 2>/dev/null
}

# _fallback_title <prompt> -> first line of the prompt, normalized.
_fallback_title() {
  _normalize_title "$(printf '%s' "$1" | head -n1)"
}

# _api_summary <prompt> -> prints a normalized label on success; empty + nonzero
# on any failure (no key, curl error, non-text response).
_api_summary() {
  [ -n "${ANTHROPIC_API_KEY:-}" ] || return 1
  local prompt=$1 payload resp text
  prompt=${prompt:0:4000}
  payload=$(jq -n --arg p "$prompt" --arg sys "$SYSTEM_PROMPT" --arg m "$API_MODEL" \
    '{model:$m, max_tokens:24, system:$sys, messages:[{role:"user", content:$p}]}') || return 1
  resp=$(curl -sS --max-time 10 "$API_URL" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload" 2>/dev/null) || return 1
  text=$(_extract_summary "$resp")
  [ -n "$text" ] || return 1
  _normalize_title "$text"
}
```

- [ ] **Step 4: Run the test, expect pass**

Run: `bash tests/claude-tmux-notice.test.sh`
Expected: prints `ok (...)` and exits 0.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-tmux-notice tests/claude-tmux-notice.test.sh
git commit -m "Add summary, normalization, and API helpers to claude-tmux-notice"
```

---

## Task 5: Hook entrypoint + summarize dispatch

**Files:**
- Modify: `bin/claude-tmux-notice` (add `_dispatch_summary`, `summarize`, `hook`; fill `main` cases)
- Modify: `tests/claude-tmux-notice.test.sh` (append assertions before `pass`)

- [ ] **Step 1: Add the failing tests**

In `tests/claude-tmux-notice.test.sh`, insert the following **before** the final `pass` line:

```bash
# ---- hook prints NOTHING to stdout and stamps placeholder + branch ---------
export TMUX_PANE=%3
_window_for_pane() { printf '@5\n'; }
_should_act() { return 0; }
_dispatch_summary() { :; }                   # don't really fork/API in the test
git() { printf 'feature/x\n'; }
tmux-worktree-notice() { :; }                # stub the renderer call
TMUX_SETOPTS=""
tmux() {
  case "$*" in
    *set-option*) TMUX_SETOPTS="$TMUX_SETOPTS|$*" ;;
    *) : ;;
  esac
}
out=$(printf '{"prompt":"fix the thing","cwd":"/repo"}' | hook)
assert_empty "$out" "hook must print nothing to stdout"
assert_contains "$TMUX_SETOPTS" "@wt_title summarizing…" "hook stamps the placeholder title"
assert_contains "$TMUX_SETOPTS" "@wt_branch feature/x" "hook stamps the branch"

# ---- hook is silent and stamps nothing when the guard says no --------------
_should_act() { return 1; }
TMUX_SETOPTS=""
out=$(printf '{"prompt":"fix the thing","cwd":"/repo"}' | hook)
assert_empty "$out" "skipped hook prints nothing"
assert_empty "$TMUX_SETOPTS" "skipped hook stamps nothing"

# ---- summarize sets @wt_title and refreshes --------------------------------
export ANTHROPIC_API_KEY=test-key
curl() { printf '{"content":[{"type":"text","text":"Wire up the hook"}]}'; }
REFRESHED=""
tmux-worktree-notice() { REFRESHED="$*"; }
TMUX_SETOPTS=""
tmux() { case "$*" in *set-option*) TMUX_SETOPTS="$*" ;; *) : ;; esac; }
pf=$(mktemp); printf 'wire up the user prompt hook' > "$pf"
summarize @5 /repo "$pf"
assert_contains "$TMUX_SETOPTS" "@wt_title Wire up the hook" "summarize sets the title"
assert_eq "$REFRESHED" "refresh @5" "summarize refreshes the window"
assert_fail test -e "$pf"
```

- [ ] **Step 2: Run the test, expect failure**

Run: `bash tests/claude-tmux-notice.test.sh`
Expected: FAIL — `hook` and `summarize` are still stubs (`: ;`), so `@wt_title`/`@wt_branch` are never set.

- [ ] **Step 3: Add `_dispatch_summary`, `summarize`, and `hook`**

Insert these functions immediately **before** `main()` (after `_api_summary`):

```bash
# _dispatch_summary <win> <cwd> <prompt> -> fork the detached background labeler.
# Isolated so tests can stub it. The prompt goes via a temp file (multiline /
# large prompts dodge arg-length issues); the child unlinks it. All fds detached
# so nothing leaks into Claude's stdout/prompt context.
_dispatch_summary() {
  local win=$1 cwd=$2 prompt=$3 pf
  pf=$(mktemp "${TMPDIR:-/tmp}/claude-tmux-notice.XXXXXX") || return 0
  printf '%s' "$prompt" > "$pf"
  nohup "$SELF" summarize "$win" "$cwd" "$pf" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# summarize <win> <cwd> <promptfile> -> compute the label, update @wt_title, and
# repaint the box. Runs detached in the background; the temp file is consumed.
summarize() {
  local win=$1 cwd=$2 pf=$3 prompt title
  prompt=$(cat "$pf" 2>/dev/null); rm -f "$pf"
  title=$(_api_summary "$prompt") || title=""
  [ -n "$title" ] || title=$(_fallback_title "$prompt")
  [ -n "$title" ] || title="(claude session)"
  tmux set-option -w -t "$win" @wt_title "$title" 2>/dev/null
  tmux-worktree-notice refresh "$win" 2>/dev/null || true
}

# hook -> the UserPromptSubmit entrypoint. Reads hook JSON on stdin. Stamps the
# window, shows the box, and forks the background labeler. Prints nothing.
hook() {
  local json prompt cwd win
  json=$(cat)
  [ -n "${TMUX_PANE:-}" ] || return 0
  win=$(_window_for_pane "$TMUX_PANE")
  [ -n "$win" ] || return 0
  _should_act "$win" || return 0
  prompt=$(printf '%s' "$json" | jq -r '.prompt // empty' 2>/dev/null)
  [ -n "$prompt" ] || return 0
  cwd=$(printf '%s' "$json" | jq -r '.cwd // empty' 2>/dev/null)
  [ -n "$cwd" ] || cwd=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null)
  tmux set-option -w -t "$win" @wt_branch "$(_branch_for "$cwd")" 2>/dev/null
  tmux set-option -w -t "$win" @wt_title "summarizing…" 2>/dev/null
  tmux-worktree-notice show "$win" >/dev/null 2>&1 || true
  _dispatch_summary "$win" "$cwd" "$prompt"
  return 0
}
```

- [ ] **Step 4: Fill in the `main()` cases**

Replace the two stub lines in `main()`:

```bash
    hook)      : ;;   # filled in Task 5
    summarize) : ;;   # filled in Task 5
```

with:

```bash
    hook)      hook ;;
    summarize) shift; summarize "$@" ;;
```

- [ ] **Step 5: Run the test, expect pass**

Run: `bash tests/claude-tmux-notice.test.sh`
Expected: prints `ok (...)` and exits 0.

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh`
Expected: both test files print `ok (...)`, then `ALL TESTS PASSED`, exit 0.

- [ ] **Step 7: Lint both scripts with shellcheck (if installed)**

Run: `command -v shellcheck >/dev/null && shellcheck bin/claude-tmux-notice bin/tmux-worktree-notice || echo "shellcheck not installed — skipping"`
Expected: no errors. Fix any genuine warnings in `bin/claude-tmux-notice`; pre-existing warnings in `bin/tmux-worktree-notice` unrelated to `refresh` may be left as-is.

- [ ] **Step 8: Commit**

```bash
git add bin/claude-tmux-notice tests/claude-tmux-notice.test.sh
git commit -m "Wire up claude-tmux-notice hook and summarize dispatch"
```

---

## Task 6: Install docs

**Files:**
- Modify: `setup-a-new-machine.sh` (new section + reminder line)
- Modify: `CLAUDE.md` (bin/ bullet)

- [ ] **Step 1: Add a "Claude Code hooks" section to `setup-a-new-machine.sh`**

Insert this block immediately **before** the `### Symlinks` section near the end of the file:

```bash
##############################################################################################################
### Claude Code hooks (tmux window auto-notice)

# bin/claude-tmux-notice auto-labels an unstamped tmux window from a Claude
# session's first prompt. Wire it into your *global* Claude config (this file is
# NOT tracked by the dotfiles repo) by adding a UserPromptSubmit hook to
# ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "UserPromptSubmit": [
#         { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-notice" } ] }
#       ]
#     }
#   }
#
# It also needs ANTHROPIC_API_KEY exported (put it in ~/.extra). Without a key it
# falls back to the first line of your prompt — it never errors the window.
```

- [ ] **Step 2: Add a reminder line to the closing box**

In the final `echo "┌─...─┐"` block, add a line before the closing border (matching the existing `│  • ...  │` style and width):

```bash
echo "│  • Add claude-tmux-notice hook       │"
```

- [ ] **Step 3: Add the `bin/` bullet to `CLAUDE.md`**

After the `tmux-worktree-notice` bullet in the `## Utility Scripts (\`bin/\`)` section, add:

```markdown
- `claude-tmux-notice` — Claude Code `UserPromptSubmit` hook that auto-labels an unstamped tmux window from the session's first prompt: it stamps `@wt_branch`/`@wt_title` and asks `claude-haiku-4-5` (via `ANTHROPIC_API_KEY`) for a short label, falling back to the prompt's first line. Wire it into `~/.claude/settings.json`; pairs with `tmux-worktree-notice` (which renders the box)
```

- [ ] **Step 4: Sanity-check the shell script still parses**

Run: `bash -n setup-a-new-machine.sh`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add setup-a-new-machine.sh CLAUDE.md
git commit -m "Document claude-tmux-notice hook install"
```

---

## Task 7: Final verification + manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run.sh`
Expected: `ALL TESTS PASSED`, exit 0.

- [ ] **Step 2: Symlink the new script (so `~/bin/claude-tmux-notice` exists)**

Run: `./symlink-setup.sh` (re-running is safe — it re-links `bin/`), then `command -v claude-tmux-notice`
Expected: prints a path (e.g. `~/bin/claude-tmux-notice`).

- [ ] **Step 3: Wire the hook locally**

Add the `UserPromptSubmit` hook from Task 6 Step 1 to `~/.claude/settings.json`, and confirm `echo "${ANTHROPIC_API_KEY:0:7}"` prints a key prefix (set it in `~/.extra` if not).

- [ ] **Step 4: Manual smoke test — happy path**

In a fresh tmux window (not created by `cwork`/`cpull`), run `claude` and submit a first prompt like "help me rename a function across the repo". Expected: the boxed notice appears showing the branch as heading and `summarizing…`, then within ~1–2s updates to a ≤6-word label (e.g. *"Rename function across repo"*).

- [ ] **Step 5: Manual smoke test — fallback**

In another fresh window, `unset ANTHROPIC_API_KEY` before launching `claude`, submit a prompt. Expected: the box shows the first line of your prompt (truncated), and the window is never errored.

- [ ] **Step 6: Manual smoke test — guards**

(a) In a window already created by `cwork <issue>` (so `@wt_num` is set), submit a Claude prompt — expected: the issue `#num` + title notice is unchanged. (b) Submit a second prompt in a window already auto-labelled — expected: the label does not change. (c) `prefix b` still toggles the box in all cases.

- [ ] **Step 7: Confirm clean tree and summarize**

Run: `git status --short` (only the intended files committed; unrelated `.gitconfig`/`claude/` still untouched) and `git log --oneline -7`.

---

## Self-Review Notes

- **Spec coverage:** new hook script (Tasks 3–5), `refresh` subcommand with `render()` unchanged (Task 2), guard skipping `@wt_num`/`@wt_title` windows (Task 3), branch-or-basename heading (Task 4), API call with `claude-haiku-4-5`/`max_tokens 24`/4000-char truncation (Task 4), `summarizing…` placeholder + immediate `show` (Task 5), detached fork printing nothing to stdout (Task 5), graceful fallback to first prompt line (Tasks 4–5), single-attempt guard (covered by `_should_act` + placeholder), install docs in `setup-a-new-machine.sh` + `CLAUDE.md` (Task 6). All spec sections map to a task.
- **Type/name consistency:** function names used in tests match definitions (`_should_act`, `_branch_for`, `_normalize_title`, `_extract_summary`, `_fallback_title`, `_api_summary`, `_dispatch_summary`, `summarize`, `hook`, `refresh`); the source-guard vars are `TMUX_WORKTREE_NOTICE_SOURCED` and `CLAUDE_TMUX_NOTICE_SOURCED`; renderer is invoked as `tmux-worktree-notice {show,refresh}` consistently.
- **Assertion counts** printed by `pass` are cosmetic and intentionally not pinned: assertions inside `( … )` subshells (the `unset TMUX` / `unset ANTHROPIC_API_KEY` cases) don't increment the parent counter, so the printed number is lower than the literal assertion count. The test still passes whenever `pass` is reached.
