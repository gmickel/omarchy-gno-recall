#!/usr/bin/env bash
# Open a gno-provided path only after realpath containment.
# Usage: open-contained.sh <collection-root-or-empty> <path> -- <opener...>
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: open-contained.sh <root-or-empty> <path> -- <opener...>" >&2
  exit 2
fi

root_arg=$1
path_arg=$2
shift 2
if [[ $1 != "--" ]]; then
  echo "error: expected -- before opener argv" >&2
  exit 2
fi
shift

if [[ $path_arg == *[$'\n\0']* ]]; then
  echo "error: path contains a forbidden character" >&2
  exit 1
fi

if ! resolved=$(realpath -e -- "$path_arg" 2>/dev/null); then
  echo "error: path does not exist" >&2
  exit 1
fi

if [[ ! -f $resolved || -L $resolved ]]; then
  # After realpath -e, -L is false for the final target; require a regular file.
  if [[ ! -f $resolved ]]; then
    echo "error: path is not a regular file" >&2
    exit 1
  fi
fi

if [[ -n $root_arg ]]; then
  if ! root=$(realpath -e -- "$root_arg" 2>/dev/null); then
    echo "error: collection root does not exist" >&2
    exit 1
  fi
  if [[ $resolved != "$root" && $resolved != "$root"/* ]]; then
    echo "error: path escapes collection root" >&2
    exit 1
  fi
fi

exec "$@" "$resolved"
