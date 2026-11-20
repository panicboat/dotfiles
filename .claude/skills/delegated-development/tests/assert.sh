#!/usr/bin/env bash
# Source this file; call finish last.

ASSERT_FAILURES=0
ASSERT_TOTAL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo "PASS $name"
  else
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
    echo "FAIL $name (expected: $expected, actual: $actual)"
  fi
}

finish() {
  echo "$((ASSERT_TOTAL - ASSERT_FAILURES))/$ASSERT_TOTAL passed"
  [ "$ASSERT_FAILURES" -eq 0 ]
}
