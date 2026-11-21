#!/usr/bin/env bash
# SC1091: assert.sh resolves relative to $0.
# shellcheck disable=SC1091
source "$(dirname "$0")/assert.sh"
ADAPTER="$(dirname "$0")/../adapters/codex.sh"

T="$(mktemp -d)"
STUB_DIR="$T/stub"
export STUB_DIR
mkdir -p "$STUB_DIR"
trap 'rm -rf "$T"' EXIT

cat >"$STUB_DIR/codex" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_DIR/argv"
cat >"$STUB_DIR/stdin"
prev=
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then echo "stub final message" >"$arg"; fi
  prev="$arg"
done
if [ -n "${STUB_SLEEP:-}" ]; then sleep "$STUB_SLEEP"; fi
if [ "${STUB_NO_THREAD:-0}" != 1 ]; then echo '{"type":"thread.started","thread_id":"stub-thread-1"}'; fi
exit "${STUB_EXIT:-0}"
STUBEOF
chmod +x "$STUB_DIR/codex"
PATH="$STUB_DIR:$PATH"

assert_eq stub_shadows_real_codex "$STUB_DIR/codex" "$(command -v codex)"

"$ADAPTER" run "$T/out" "hello"; assert_eq run_exit 0 "$?"
assert_eq run_builds_exec_argv "$(printf 'exec\n--json\n-o\n%s\nhello' "$T/out.last")" "$(cat "$STUB_DIR/argv")"

"$ADAPTER" resume stub-thread-1 "$T/out2" "fix it"
assert_eq resume_builds_resume_argv "$(printf 'exec\nresume\nstub-thread-1\n--json\n-o\n%s\nfix it' "$T/out2.last")" "$(cat "$STUB_DIR/argv")"

assert_eq session_id_reads_thread_started stub-thread-1 "$("$ADAPTER" session_id "$T/out")"
assert_eq last_message_reads_last_file "stub final message" "$("$ADAPTER" last_message "$T/out")"

# SC2016: single-quoted $HOME is the literal prompt under test.
# shellcheck disable=SC2016
p=$'line1\nsay "hi" $HOME it\'s'
"$ADAPTER" run "$T/out3" "$p"
assert_eq prompt_is_passed_verbatim "$p" "$(tail -n 2 "$STUB_DIR/argv")"

mkdir -p "$T/with space"
"$ADAPTER" run "$T/with space/out" x
assert_eq out_path_with_spaces stub-thread-1 "$("$ADAPTER" session_id "$T/with space/out")"

echo SHOULD-NOT-ARRIVE | "$ADAPTER" run "$T/out4" x
assert_eq stdin_is_detached "" "$(cat "$STUB_DIR/stdin")"
[ -e "$STUB_DIR/stdin" ]; assert_eq stub_read_stdin_to_eof 0 "$?"

STUB_EXIT=3 "$ADAPTER" run "$T/out5" x; assert_eq failure_exit_is_propagated 3 "$?"

STUB_SLEEP=30 WAIT_BUDGET=1 "$ADAPTER" run "$T/out6" x; assert_eq timeout_returns_142 142 "$?"

# Stopping the adapter (the controller's abort path) must take the stub's descendants down with it.
sleep_marker="301.$$"
STUB_SLEEP="$sleep_marker" "$ADAPTER" run "$T/out9" x &
adapter_pid=$!
sleep 1
kill -TERM "$adapter_pid"
wait "$adapter_pid"; adapter_status=$?
sleep 1
! pgrep -f "sleep $sleep_marker" >/dev/null; survivors_gone=$?
assert_eq abort_kills_descendants "143 0" "$adapter_status $survivors_gone"

STUB_NO_THREAD=1 "$ADAPTER" run "$T/out7" x
"$ADAPTER" session_id "$T/out7" >/dev/null; assert_eq session_id_missing_fails 1 "$?"

"$ADAPTER" last_message "$T/nonexistent"; assert_eq last_message_missing_fails 1 "$?"

"$ADAPTER" detect; assert_eq detect_finds_codex 0 "$?"
PATH=/usr/bin:/bin "$ADAPTER" detect; assert_eq detect_without_codex 1 "$?"

"$ADAPTER" run "$T/out8" 2>/dev/null; assert_eq run_missing_prompt 2 "$?"
"$ADAPTER" bogus 2>/dev/null; assert_eq unknown_subcommand 2 "$?"

finish
