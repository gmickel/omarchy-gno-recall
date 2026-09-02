#!/usr/bin/env bash
# Run gno search|query with the query on stdin, never on argv.
# Usage: search-via-query-file.sh <gno> <search|query> [gno flags...]
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: search-via-query-file.sh <gno> <search|query> [flags...]" >&2
  exit 2
fi

if [[ -z ${GNO_RECALL_SESSION:-} ]]; then
  export GNO_RECALL_SESSION=1
  exec setsid -- "$0" "$@"
fi

gno=$1
verb=$2
shift 2

case $verb in
  search | query) ;;
  *)
    echo "error: verb must be search or query" >&2
    exit 2
    ;;
esac

runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
dir=$runtime/gno-recall
if [[ -L $dir ]]; then
  echo "error: $dir is a symlink" >&2
  exit 1
fi
mkdir -m 700 -p "$dir"
if [[ -L $dir || ! -d $dir ]]; then
  echo "error: failed to create $dir as a directory" >&2
  exit 1
fi
owner=$(stat -c '%u' "$dir")
if [[ $owner != "$UID" ]]; then
  echo "error: $dir is not owned by the current user" >&2
  exit 1
fi

qfile=$(mktemp -p "$dir" q.XXXXXX)
chmod 600 "$qfile"
cleanup() {
  trap - EXIT TERM INT HUP
  rm -f -- "$qfile"
  local pgid
  pgid=$(ps -o pgid= -p $$ | tr -d ' ')
  if [[ -n $pgid ]]; then
    kill -TERM -- "-$pgid" 2>/dev/null || true
  fi
}
trap cleanup EXIT TERM INT HUP

IFS= read -r query || true
printf '%s' "$query" >"$qfile"

"$gno" "$verb" --query-file "$qfile" "$@" &
child=$!
wait "$child"
status=$?
trap - EXIT TERM INT HUP
rm -f -- "$qfile"
exit "$status"
