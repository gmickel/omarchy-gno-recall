#!/usr/bin/bash -p
set -euo pipefail
export PATH=/usr/bin:/bin
exec /usr/bin/python3 -I "$(dirname -- "$(readlink -f -- "$0")")/runtime.py" run "$@"
