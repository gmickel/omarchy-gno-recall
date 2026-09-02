#!/usr/bin/env bash
# Run a command in a new session/process group so TERM/INT kills descendants.
# Used as the Process wrapper for every gno invocation.
set -euo pipefail

if [[ -z ${GNO_RECALL_SESSION:-} ]]; then
  export GNO_RECALL_SESSION=1
  exec setsid -- "$0" "$@"
fi

cleanup() {
  trap - EXIT TERM INT HUP
  local pgid
  pgid=$(ps -o pgid= -p $$ | tr -d ' ')
  if [[ -n $pgid ]]; then
    kill -TERM -- "-$pgid" 2>/dev/null || true
  fi
}

trap cleanup TERM INT HUP
"$@" &
child=$!
wait "$child"
status=$?
trap - EXIT TERM INT HUP
exit "$status"
