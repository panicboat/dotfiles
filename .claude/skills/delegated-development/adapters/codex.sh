#!/usr/bin/env bash
BOUND="$(dirname "$0")/../bound.pl"
WAIT_BUDGET="${WAIT_BUDGET:-1800}"

usage() {
  echo "usage: ${0##*/} detect | run <out> <prompt> | resume <session_id> <out> <prompt> | session_id <out> | last_message <out>" >&2
  exit 2
}

[ $# -ge 1 ] || usage
subcommand="$1"
shift

case "$subcommand" in
  detect)
    command -v codex >/dev/null
    ;;
  run)
    [ $# -eq 2 ] || usage
    out="$1" prompt="$2"
    # exec keeps bound.pl as this process so a TERM to the adapter reaches its sweep; </dev/null avoids openai/codex#20919.
    exec "$BOUND" "$WAIT_BUDGET" codex exec --json -o "$out.last" "$prompt" </dev/null >"$out.jsonl"
    ;;
  resume)
    [ $# -eq 3 ] || usage
    session_id="$1" out="$2" prompt="$3"
    exec "$BOUND" "$WAIT_BUDGET" codex exec resume "$session_id" --json -o "$out.last" "$prompt" </dev/null >"$out.jsonl"
    ;;
  session_id)
    [ $# -eq 1 ] || usage
    thread_id="$(grep -m1 '"type" *: *"thread.started"' "$1.jsonl" 2>/dev/null |
      sed -n 's/.*"thread_id" *: *"\([^"]*\)".*/\1/p')"
    [ -n "$thread_id" ] || exit 1
    echo "$thread_id"
    ;;
  last_message)
    [ $# -eq 1 ] || usage
    [ -s "$1.last" ] || exit 1
    cat "$1.last"
    ;;
  *)
    usage
    ;;
esac
