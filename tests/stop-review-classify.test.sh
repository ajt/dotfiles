#!/usr/bin/env bash
# stop-review.py classify(): word-boundary artifact detection. Guards against
# the substring false-positives ("explanation.md" -> plan) that burned Gemini
# calls and spuriously blocked turns.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
. "$here/lib.sh"

SR="$here/../claude/review/stop-review.py"

classify() {
  python3 - "$SR" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sr", sys.argv[1])
sr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sr)
print(sr.classify(sys.argv[2]) or "none")
PY
}

# positives
assert_eq "$(classify docs/superpowers/plans/2026-06-05-foo.md)" "plan" "plans/ dir"
assert_eq "$(classify docs/superpowers/specs/foo-design.md)" "spec" "specs/ dir"
assert_eq "$(classify notes/implementation-plan.md)" "plan" "plan in filename"
assert_eq "$(classify foo.spec.md)" "spec" "dotted spec filename"
assert_eq "$(classify PLAN.md)" "plan" "case-insensitive"
assert_eq "$(classify migration-specs.md)" "spec" "plural in filename"

# negatives
assert_eq "$(classify docs/explanation.md)" "none" "plan inside a word"
assert_eq "$(classify inspect-results.md)" "none" "spec inside a word"
assert_eq "$(classify planning/notes.md)" "none" "planning dir is not plans"
assert_eq "$(classify docs/plans/foo.md.review.md)" "none" "review files excluded"
assert_eq "$(classify plans/foo.txt)" "none" "non-md excluded"

pass
