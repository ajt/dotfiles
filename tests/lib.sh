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
