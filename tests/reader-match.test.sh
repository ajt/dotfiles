#!/usr/bin/env bash
# Tests for bin/reader-match: a copy of a box table finds its Markdown in the
# transcript, intact or with a strip of columns missing from every line.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

tmp=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects/p"

md='Tanium building blocks (reusable by every future Tanium workflow)

| Sub-workflow | Input → output |
|---|---|
| Tanium: Run Gateway query | Query and variables → all pages of results; handles paging and errors |
| Tanium: List endpoints | Optional partner → endpoint ID, name, partner tag, NAT IP, OS, last seen |
| Tanium: Read sensors | Endpoint ID, sensor names → readings |
| Tanium: Run package on endpoint | Endpoint ID, package, parameters → action ID. Refuses unless exactly one endpoint; the only user of the write token |
| Tanium: Get action status | Action ID → completed, failed or expired |
| Tanium: List Discover interfaces | NAT IP, profile, since → interfaces with managed status |'

MD="$md" python3 - "$HOME/.claude/projects/p/s.jsonl" <<'PY'
import json, os, sys
with open(sys.argv[1], "w") as fh:
    fh.write(json.dumps({"type": "user", "message": {"content": "show me the blocks"}}) + "\n")
    fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": os.environ["MD"]}]}}) + "\n")
PY

# what the TUI shows and the mouse copies
clip='Tanium building blocks (reusable by every future Tanium workflow)

┌──────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│           Sub-workflow           │                                                   Input → output                                                    │
├──────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Tanium: Run Gateway query        │ Query and variables → all pages of results; handles paging and errors                                               │
├──────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Tanium: List endpoints           │ Optional partner → endpoint ID, name, partner tag, NAT IP, OS, last seen                                            │
├──────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Tanium: Read sensors             │ Endpoint ID, sensor names → readings                                                                                │
├──────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Tanium: Run package on endpoint  │ Endpoint ID, package, parameters → action ID. Refuses unless exactly one endpoint; the only user of the write token │
├──────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Tanium: Get action status        │ Action ID → completed, failed or expired                                                                            │
├──────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Tanium: List Discover interfaces │ NAT IP, profile, since → interfaces with managed status                                                             │
└──────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘'

# --- an intact copy matches ------------------------------------------------
out=$(printf '%s\n' "$clip" | "$here/../bin/reader-match" --label)
assert_eq "$?" 0 "intact copy matches"
assert_eq "$(printf '%s\n' "$out" | head -1)" "Claude Code" "label line"
assert_contains "$out" "| Tanium: Read sensors | Endpoint ID, sensor names → readings |" "original row"

# --- a copy missing columns 67-92 of every line still matches ---------------
damaged=$(printf '%s\n' "$clip" | python3 -c 'import sys
for ln in sys.stdin.read().split("\n"): print(ln[:67] + ln[93:])')
assert_contains "$damaged" "all pageng and errors" "fixture is damaged as the terminal damaged it"
out=$(printf '%s\n' "$damaged" | "$here/../bin/reader-match")
assert_eq "$?" 0 "damaged copy matches"
assert_contains "$out" "all pages of results; handles paging and errors" "full cell text recovered"

# --- unrelated text does not match, even with many lines --------------------
other=$(printf 'Unrelated line number %d with enough characters to count\n' 1 2 3 4 5 6)
assert_fail bash -c 'printf "%s\n" "$1" | "$2" 2>/dev/null' _ "$other" "$here/../bin/reader-match"

# --- a few shared lines are not enough (60 % of lines must hit) -------------
mixed="$other
Tanium: Run Gateway query  Query and variables
Tanium: List endpoints  Optional partner"
assert_fail bash -c 'printf "%s\n" "$1" | "$2" 2>/dev/null' _ "$mixed" "$here/../bin/reader-match"

pass
