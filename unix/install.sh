#!/bin/sh
# Installs dvm on Linux or macOS.
#
#   ./unix/install.sh            -> /usr/local/bin/dvm (asks for sudo if needed)
#   ./unix/install.sh --user     -> ~/.local/bin/dvm   (no sudo)
#   add --no-init to skip running `dvm init` afterwards
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dest=/usr/local/bin
init=1
for a in "$@"; do
  case "$a" in
    --user) dest="$HOME/.local/bin" ;;
    --no-init) init="" ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option '$a'" >&2; exit 2 ;;
  esac
done

as_needed() { # run directly if we may write to $dest, otherwise with sudo
  p=$dest
  while [ ! -e "$p" ]; do p=$(dirname "$p"); done
  if [ -w "$p" ] || [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

as_needed mkdir -p "$dest"
as_needed install -m 0755 "$here/dvm" "$dest/dvm"
echo "✔ dvm installed to $dest/dvm"

case ":$PATH:" in
  *":$dest:"*) ;;
  *)
    echo ""
    echo "$dest is not on your PATH. Add this line to ~/.bashrc (bash) or ~/.zshrc (zsh):"
    echo "  export PATH=\"$dest:\$PATH\""
    ;;
esac

found=$(command -v dvm 2>/dev/null || true)
if [ -n "$found" ] && [ "$found" != "$dest/dvm" ]; then
  echo ""
  echo "note: \`dvm\` in this shell resolves to $found, which comes earlier in PATH."
  echo "      Remove that file, or it will be used instead of $dest/dvm."
fi

if [ -n "$init" ]; then
  echo ""
  "$dest/dvm" init
fi
