#!/usr/bin/env bash
# review-pick --json: structured findings extraction for the in-session handling
# protocol (stop-review.py). Pure parsing — no gum, no network, no tmux.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

PICK="$here/../claude/review/review-pick.py"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/review-pick-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

jget() { # <file> <python-expr over doc>
  python3 - "$1" "$2" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"doc": doc}))
PY
}

# --- 1. canonical review: VERDICT prefix, ## sections, bold finding blocks ---
cat > "$tmp/a.plan.md" <<'EOF'
# a plan
EOF
cat > "$tmp/a.plan.md.review.md" <<'EOF'
<!-- gemini · plan cross-review · 2026-06-10T00:00:00 -->

VERDICT: CHANGES

## Verdict
One paragraph of summary.

## Step-by-step critique

**Task 3: Add `show`**
* **What's wrong:** split-window lacks -d.
* **The fix:** add -d to split-window.

**Task 5: Wire toggle**
* **What's wrong:** toggle races the banner pane.

## Cross-cutting risks
- Risk one spans steps.
- Risk two spans steps.

## Blocking issues
None.
EOF

out="$tmp/a.json"
python3 "$PICK" --json "$tmp/a.plan.md" > "$out" || fail "--json run failed"
assert_eq "$(jget "$out" 'doc["verdict"]')" "CHANGES" "verdict parsed"
assert_contains "$(jget "$out" 'doc["artifact"]')" "a.plan.md" "artifact path"
assert_eq "$(jget "$out" 'doc["sections"][0]["kind"]')" "verdict" "verdict section kind"
assert_eq "$(jget "$out" 'doc["sections"][1]["kind"]')" "pick" "critique section kind"
# bold heading + its bullets collapse into ONE finding per task
assert_eq "$(jget "$out" 'len(doc["sections"][1]["items"])')" "2" "one item per finding block"
item1=$(jget "$out" 'doc["sections"][1]["items"][0]')
assert_contains "$item1" "Task 3" "block keeps its heading"
assert_contains "$item1" "What's wrong" "block keeps problem"
assert_contains "$item1" "The fix" "block keeps fix"
# plain-bullet section: one item per bullet
assert_eq "$(jget "$out" 'len(doc["sections"][2]["items"])')" "2" "bullets split per item"
# placeholder body ("None.") must not become a pickable finding
assert_eq "$(jget "$out" 'len(doc["sections"][3]["items"])')" "0" "None. body yields no items"

# --- 2. format drift: bare verdict token, no ## sections ---
cat > "$tmp/b.spec.md" <<'EOF'
# a spec
EOF
cat > "$tmp/b.spec.md.review.md" <<'EOF'
<!-- gemini · spec cross-review · 2026-06-10T00:00:00 -->

BLOCK

The spec is missing an error model.

It also never defines the persistence story.
EOF

out="$tmp/b.json"
python3 "$PICK" --json "$tmp/b.spec.md" > "$out" || fail "--json drift run failed"
assert_eq "$(jget "$out" 'doc["verdict"]')" "BLOCK" "bare verdict token parsed"
assert_eq "$(jget "$out" 'doc["sections"][0]["title"]')" "Findings" "fallback section synthesized"
assert_eq "$(jget "$out" 'len(doc["sections"][0]["items"])')" "2" "paragraphs become items"

pass
