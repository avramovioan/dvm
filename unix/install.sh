#!/bin/sh
# Installs dvm on Linux or macOS.
#
# Straight from GitHub, no clone needed:
#   curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash -s -- --user
# From a clone, or a downloaded copy of this file:
#   sh install.sh [--user] [--ref <tag or branch>]
#
#   (default)      install to /usr/local/bin/dvm (asks for sudo if needed)
#   --user         install to ~/.local/bin/dvm (no sudo)
#   --ref <ref>    install that release tag or branch (same as DVM_REF=<ref>)
#
# It only installs the dvm command; it doesn't touch .NET.
# Next to a clone's unix/dvm it installs that file. Anywhere else it downloads
# unix/dvm from GitHub: the latest release, or master while there is none.
# Run it again to update dvm.
set -eu

repo=${DVM_REPO:-avramovioan/dvm}
base_url=${DVM_BASE_URL:-https://raw.githubusercontent.com/$repo}
api_url=${DVM_API_URL:-https://api.github.com/repos/$repo/releases/latest}

dest=/usr/local/bin
ref=${DVM_REF:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --user) dest="$HOME/.local/bin" ;;
    --ref) [ $# -ge 2 ] || { echo "install.sh: --ref needs a tag or branch" >&2; exit 2; }; ref=$2; shift ;;
    -h|--help) sed -n '2,17p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "install.sh: $*" >&2; exit 1; }

fetch() { # <url> <file, or - for stdout>
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 2 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else die "needs curl or wget to download dvm"
  fi
}

# Run from a clone (or with dvm next to this file): use that dvm.
src=""; from=""
case "$0" in
  install.sh|*/install.sh)
    here=$(cd "$(dirname "$0")" && pwd)
    if [ -f "$here/dvm" ]; then src="$here/dvm"; from="$here"; fi
    ;;
esac

tmp=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
if [ -z "$src" ]; then
  if [ -z "$ref" ]; then
    ref=$(fetch "$api_url" - 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1) || ref=""
    [ -n "$ref" ] || ref=master
  fi
  case "$ref" in ""|*[!A-Za-z0-9._/-]*) die "not a tag or branch name: '$ref'" ;; esac
  tmp=$(mktemp -d)
  echo "Downloading dvm ($ref) from $base_url ..."
  fetch "$base_url/$ref/unix/dvm" "$tmp/dvm" || die "could not download $base_url/$ref/unix/dvm"
  { head -n1 "$tmp/dvm" | grep -q '^#!.*bash' && grep -q '^DVM_VERSION=' "$tmp/dvm"; } \
    || die "$base_url/$ref/unix/dvm is not the dvm script"
  src="$tmp/dvm"
  from="$repo@$ref"
fi

as_needed() { # run directly if we may write to $dest, otherwise with sudo
  p=$dest
  while [ ! -e "$p" ]; do p=$(dirname "$p"); done
  if [ -w "$p" ] || [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

as_needed mkdir -p "$dest"
as_needed install -m 0755 "$src" "$dest/dvm"
echo "✔ $("$dest/dvm" version) installed to $dest/dvm (from $from)"

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

echo ""
echo "Run 'dvm list' to see the .NET versions, or 'dvm help' for all commands."
