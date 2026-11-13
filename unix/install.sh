#!/bin/sh
# Installs dvm on Linux or macOS.
#
# Straight from GitHub, no clone needed:
#   curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash -s -- --user
# From a clone, or a downloaded copy of this file:
#   sh install.sh [--user | --dir <folder>] [--ref <tag or branch>]
#
#   (default)       install to /usr/local/bin/dvm (asks for sudo if needed)
#   --user          install to ~/.local/bin/dvm (no sudo)
#   --dir <folder>  install to <folder>/dvm (`dvm update` uses this)
#   --ref <ref>     install that release tag or branch (same as DVM_REF=<ref>)
#
# It only installs the dvm command; it doesn't touch .NET.
# Next to a clone's unix/dvm it installs that file. Anywhere else it downloads
# unix/dvm from GitHub: the latest release, or master while there is none.
# Either way it writes the version from the VERSION file into the copy.
set -eu

repo=${DVM_REPO:-avramovioan/dvm}
base_url=${DVM_BASE_URL:-https://raw.githubusercontent.com/$repo}
latest_url=${DVM_LATEST_URL:-https://github.com/$repo/releases/latest/download/VERSION}

dest=/usr/local/bin
ref=${DVM_REF:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --user) dest="$HOME/.local/bin" ;;
    --dir) [ $# -ge 2 ] || { echo "install.sh: --dir needs a folder" >&2; exit 2; }; dest=${2%/}; shift ;;
    --ref) [ $# -ge 2 ] || { echo "install.sh: --ref needs a tag or branch" >&2; exit 2; }; ref=$2; shift ;;
    -h|--help) sed -n '2,18p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
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

is_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Run from a clone (or with dvm next to this file): use that dvm.
here=""
case "$0" in
  install.sh|*/install.sh) here=$(cd "$(dirname "$0")" && pwd) ;;
esac
if [ -n "$here" ] && [ -f "$here/dvm" ]; then
  cp "$here/dvm" "$tmp/dvm"
  version=$(tr -d '[:space:]' < "$here/../VERSION" 2>/dev/null || true)
  from=$here
else
  if [ -z "$ref" ]; then
    # The latest release carries the VERSION file; without a release, use master.
    latest=$(fetch "$latest_url" - 2>/dev/null | tr -d '[:space:]') || latest=""
    if is_version "$latest"; then ref="v$latest"; else ref=master; fi
  fi
  case "$ref" in ""|*[!A-Za-z0-9._/-]*) die "not a tag or branch name: '$ref'" ;; esac
  echo "Downloading dvm ($ref) from $base_url ..."
  fetch "$base_url/$ref/unix/dvm" "$tmp/dvm" || die "could not download $base_url/$ref/unix/dvm"
  { head -n1 "$tmp/dvm" | grep -q '^#!.*bash' && grep -q '^DVM_VERSION=' "$tmp/dvm"; } \
    || die "$base_url/$ref/unix/dvm is not the dvm script"
  version=$(fetch "$base_url/$ref/VERSION" - 2>/dev/null | tr -d '[:space:]') || version=""
  from="$repo@$ref"
fi

# Write the version into the copy (older versions of dvm already contain it).
if grep -q '^DVM_VERSION="0\.0\.0-dev"$' "$tmp/dvm"; then
  is_version "$version" || die "could not read the version from the VERSION file of $from"
  sed "s/^DVM_VERSION=\"0\.0\.0-dev\"\$/DVM_VERSION=\"$version\"/" "$tmp/dvm" > "$tmp/dvm.new"
  mv "$tmp/dvm.new" "$tmp/dvm"
fi

as_needed() { # run directly if we may write to $dest, otherwise with sudo
  p=$dest
  while [ ! -e "$p" ]; do p=$(dirname "$p"); done
  if [ -w "$p" ] || [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

before=""
[ -x "$dest/dvm" ] && before=$("$dest/dvm" version 2>/dev/null || true)
as_needed mkdir -p "$dest"
as_needed install -m 0755 "$tmp/dvm" "$dest/dvm"
now=$("$dest/dvm" version)
if [ -n "$before" ] && [ "$before" != "$now" ]; then
  echo "✔ $now installed to $dest/dvm (was ${before#dvm }, from $from)"
else
  echo "✔ $now installed to $dest/dvm (from $from)"
fi

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

if [ -z "$before" ]; then
  echo ""
  echo "Run 'dvm list' to see the .NET versions, or 'dvm help' for all commands."
fi
