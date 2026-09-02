#!/usr/bin/env bash
# Install SUPER+R for GNO Recall when that chord is free.
#
# This is a documented post-add script. `omarchy plugin add` never runs plugin
# code and will not install this bind for you.
#
# Exit codes:
#   0  bind written, or already present (idempotent)
#   1  SUPER+R is taken, bindings file missing, or write failed
#      (nothing is written on conflict; this script never calls hl.unbind)

set -euo pipefail

PLUGIN_ID="gmickel.gno-recall"
BIND_KEYS="SUPER + R"
BIND_DESC="GNO Recall"
BIND_CMD="omarchy-shell shell toggle ${PLUGIN_ID}"
BINDINGS_FILE="${HOME}/.config/hypr/bindings.lua"
MARKER="-- GNO Recall overlay (scripts/install-keybind.sh)"
BIND_LINE="o.bind(\"${BIND_KEYS}\", \"${BIND_DESC}\", \"${BIND_CMD}\")"

usage() {
  cat <<'EOF'
Usage: scripts/install-keybind.sh

Appends SUPER+R → omarchy-shell shell toggle gmickel.gno-recall to
~/.config/hypr/bindings.lua when that chord is free.

If SUPER+R is already bound to GNO Recall, exits 0 without writing.
If SUPER+R is bound to anything else, prints the conflict and exits 1
without writing. Never calls hl.unbind.

The bindings path must be a regular file owned by the current user. The
script refuses symlinks, writes a same-directory temp file, locks with
flock, and installs with an atomic rename.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

assert_regular_owned_file() {
  local path=$1
  local label=$2
  if [[ -L $path ]]; then
    echo "error: ${label} is a symlink: ${path}" >&2
    exit 1
  fi
  if [[ ! -f $path ]]; then
    echo "error: ${label} is not a regular file: ${path}" >&2
    exit 1
  fi
  local owner
  owner=$(stat -c '%u' "$path")
  if [[ $owner != "$UID" ]]; then
    echo "error: ${label} is not owned by the current user: ${path}" >&2
    exit 1
  fi
}

if [[ ! -e $BINDINGS_FILE ]]; then
  echo "error: missing ${BINDINGS_FILE}" >&2
  echo "Create the Omarchy Hyprland bindings file first, then re-run." >&2
  exit 1
fi

assert_regular_owned_file "$BINDINGS_FILE" "bindings file"

already_installed() {
  grep -Eq 'o\.bind\(\s*"SUPER \+ R".*gmickel\.gno-recall' "$BINDINGS_FILE" \
    || grep -Eq 'o\.bind\(\s*"SUPER \+ R".*"GNO Recall"' "$BINDINGS_FILE"
}

is_our_bind() {
  local text=$1
  [[ $text == *gmickel.gno-recall* || $text == *"GNO Recall"* ]]
}

collect_menu_conflicts() {
  local line
  if ! command -v omarchy >/dev/null 2>&1; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if [[ $line =~ ^SUPER[[:space:]]+\+[[:space:]]+R[[:space:]]+(→|->) ]]; then
      printf '%s\n' "$line"
    fi
  done < <(omarchy menu keybindings --print 2>/dev/null || true)
}

collect_hyprctl_conflicts() {
  if ! command -v hyprctl >/dev/null 2>&1; then
    return 0
  fi
  hyprctl binds 2>/dev/null | awk '
    function emit() {
      if (!seen) return
      seen = 0
      key = f["key"]
      sub(/^.* \+ /, "", key)
      if (f["modmask"] == "64" && (key == "R" || key == "r" || f["key"] == "SUPER + R")) {
        desc = f["description"]
        if (desc == "") desc = f["dispatcher"]
        if (f["arg"] != "") desc = desc " (" f["arg"] ")"
        printf "hyprctl: SUPER + R → %s\n", desc
      }
    }
    /^bind/ { emit(); seen = 1; delete f; next }
    seen && match($0, /^\t[a-z]+: /) {
      f[substr($0, 2, RLENGTH - 3)] = substr($0, RLENGTH + 1)
    }
    END { emit() }
  '
}

if already_installed; then
  echo "GNO Recall SUPER+R is already installed in ${BINDINGS_FILE}"
  echo "Idempotent: no changes written."
  exit 0
fi

conflicts=()
while IFS= read -r line; do
  [[ -z $line ]] && continue
  if is_our_bind "$line"; then
    continue
  fi
  conflicts+=("$line")
done < <({
  collect_menu_conflicts
  collect_hyprctl_conflicts
} | awk 'NF && !seen[$0]++')

if ((${#conflicts[@]} > 0)); then
  echo "SUPER+R is already bound. Writing nothing; summon stays unbound." >&2
  echo "Conflicting bind(s):" >&2
  for line in "${conflicts[@]}"; do
    echo "  ${line}" >&2
  done
  echo >&2
  echo "Summon remains available via:" >&2
  echo "  omarchy-shell shell toggle ${PLUGIN_ID}" >&2
  echo "This script never calls hl.unbind. Bind a free chord yourself if you want one." >&2
  exit 1
fi

block=$'\n'"${MARKER}"$'\n'"${BIND_LINE}"$'\n'
bindings_dir=$(dirname -- "$BINDINGS_FILE")
assert_regular_owned_file "$BINDINGS_FILE" "bindings file"

exec 9<"$BINDINGS_FILE"
if ! flock -x 9; then
  echo "error: failed to lock ${BINDINGS_FILE}" >&2
  exit 1
fi

# Recheck under the lock so a raced installer cannot double-write.
if already_installed; then
  echo "GNO Recall SUPER+R is already installed in ${BINDINGS_FILE}"
  echo "Idempotent: no changes written."
  exit 0
fi

tmp=$(mktemp -p "$bindings_dir" .gno-recall-bindings.XXXXXX)
if [[ -L $tmp ]]; then
  echo "error: temp path is a symlink: ${tmp}" >&2
  rm -f -- "$tmp"
  exit 1
fi
trap 'rm -f -- "$tmp"' EXIT

if grep -Fq -- '-- omarchy-which-key:begin' "$BINDINGS_FILE"; then
  awk -v block="$block" '
    !inserted && $0 == "-- omarchy-which-key:begin" {
      printf "%s", block
      inserted = 1
    }
    { print }
    END {
      if (!inserted) printf "%s", block
    }
  ' "$BINDINGS_FILE" >"$tmp"
else
  cat "$BINDINGS_FILE" >"$tmp"
  printf '%s' "$block" >>"$tmp"
fi

chmod --reference="$BINDINGS_FILE" "$tmp"
if ! mv -f -- "$tmp" "$BINDINGS_FILE"; then
  echo "error: failed to write ${BINDINGS_FILE}" >&2
  exit 1
fi
trap - EXIT

echo "Installed SUPER+R → ${BIND_CMD}"
echo "Wrote ${BINDINGS_FILE}"
echo "Reload Hyprland if it does not pick the bind up automatically: hyprctl reload"
