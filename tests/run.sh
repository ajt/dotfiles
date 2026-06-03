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
