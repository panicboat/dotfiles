#!/usr/bin/env bash
# SC2016: single-quoted $ is the literal argv under test; SC1091: assert.sh resolves relative to $0.
# shellcheck disable=SC1091,SC2016
source "$(dirname "$0")/assert.sh"
BOUND="$(dirname "$0")/../bound.pl"

"$BOUND" 5 sh -c 'exit 7'; assert_eq exit_code_is_propagated 7 "$?"

"$BOUND" 5 true; assert_eq success_returns_zero 0 "$?"

out="$("$BOUND" 5 printf '%s|' 'a b' '$HOME' "it's")"
assert_eq argv_is_passed_verbatim 'a b|$HOME|it'"'"'s|' "$out"

"$BOUND" 1 sleep 30; assert_eq timeout_returns_142 142 "$?"

# A grandchild in its own process group must not survive the timeout.
marker="bound-test-$$-$RANDOM"
"$BOUND" 1 perl -e 'if (!fork) { setpgrp(0,0); exec "perl", "-e", "sleep 300", $ARGV[0] } sleep 300' "$marker"
bound_status=$?
sleep 3
! pgrep -f "$marker" >/dev/null; survivors_gone=$?
assert_eq timeout_kills_detached_descendants "142 0" "$bound_status $survivors_gone"

# Stopping the wrapper (the adapter's abort path) must take the detached grandchild down with it.
marker="bound-test-signal-$$-$RANDOM"
"$BOUND" 60 perl -e 'if (!fork) { setpgrp(0,0); exec "perl", "-e", "sleep 300", $ARGV[0] } sleep 300' "$marker" &
bound_pid=$!
sleep 1
kill -TERM "$bound_pid"
wait "$bound_pid"; bound_status=$?
sleep 1
! pgrep -f "$marker" >/dev/null; survivors_gone=$?
assert_eq signal_kills_descendants "143 0" "$bound_status $survivors_gone"

"$BOUND" abc true 2>/dev/null; assert_eq usage_error_returns_2 2 "$?"
"$BOUND" 5 2>/dev/null; assert_eq usage_error_without_command 2 "$?"

finish
