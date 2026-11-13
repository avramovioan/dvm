#!/usr/bin/env bash
# Tests unix/install.sh in all the ways people run it (from a clone, piped
# from the web, a downloaded copy, --ref, --dir), its errors, and
# `dvm update`, which runs the installer of the latest release.
# GitHub is replaced by file:// URLs, so this runs offline. Needs curl.
#   tests/test-install.sh
# shellcheck disable=SC2016  # the check conditions are single-quoted on purpose: eval runs them later
set -u

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
installer="$repo_root/unix/install.sh"
# shellcheck disable=SC2034  # used in an eval'd check below
repo_version=$(tr -d '[:space:]' < "$repo_root/VERSION")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fake GitHub: <base>/<ref>/{VERSION,unix/dvm,unix/install.sh}, and the
# VERSION file the latest release carries.
base="$tmp/github"
fake_ref() { # <ref> <version>
  mkdir -p "$base/$1/unix"
  cp "$repo_root/unix/dvm" "$repo_root/unix/install.sh" "$base/$1/unix/"
  printf '%s\n' "$2" > "$base/$1/VERSION"
}
fake_ref v9.9.9 9.9.9
fake_ref v9.9.8 9.9.8
fake_ref master 9.10.0
fake_ref feature/x 9.11.0
mkdir -p "$base/broken/unix" && printf '<html>404</html>\n' > "$base/broken/unix/dvm"
mkdir -p "$tmp/latest" && printf '9.9.9\n' > "$tmp/latest/VERSION"

pass=0; fail=0
check() { # <name> <condition...>
  local name=$1; shift
  if "$@"; then pass=$((pass + 1)); echo "ok       $name"
  else fail=$((fail + 1)); echo "FAILED   $name"; printf '%s\n' "$out" | sed 's/^/    /'; fi
}

# new_case <name>: a fresh home folder; the installed dvm goes to ~/.local/bin.
new_case() {
  home="$tmp/$1/home"; mkdir -p "$home"
  installed="$home/.local/bin/dvm"
}
# The environment of every command: the fake home and the fake GitHub.
in_case() {
  env HOME="$home" PATH="$home/.local/bin:$PATH" DVM_BASE_URL="file://$base" \
      DVM_LATEST_URL="file://$tmp/latest/VERSION" "$@"
}
# run <how: file|pipe> [env assignments...] -- [installer args...]
run() {
  local how=$1; shift
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  if [ "$how" = file ]; then
    out=$(in_case ${envs[@]+"${envs[@]}"} sh "$installer" "$@" 2>&1 </dev/null); code=$?
  else
    out=$(in_case ${envs[@]+"${envs[@]}"} sh -s -- "$@" <"$installer" 2>&1); code=$?
  fi
}
dvm() { out=$(in_case "$installed" "$@" 2>&1 </dev/null); code=$?; }

has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
# works <version>: installed with that version, and nothing else done: no
# `dvm init`, no dvm state or cache.
works() {
  [ "$code" -eq 0 ] && [ -x "$installed" ] && [ "$(in_case "$installed" version)" = "dvm $1" ] &&
    grep -qx "DVM_VERSION=\"$1\"" "$installed" &&
    ! has "dvm manages" && ! has "No other .NET installs" &&
    [ ! -e "$home/.config/dvm" ] && [ ! -e "$home/.cache/dvm" ]
}

new_case from-clone; run file -- --user
check from-clone eval 'works "$repo_version" && has "(from $repo_root/unix)" && has "Run '\''dvm list'\''"'

new_case latest-release; run pipe -- --user
check latest-release eval 'works 9.9.9 && has "Downloading dvm (v9.9.9)" && has "(from avramovioan/dvm@v9.9.9)"'

new_case no-release-yet; run pipe DVM_LATEST_URL="file://$tmp/missing" -- --user
check no-release-yet eval 'works 9.10.0 && has "Downloading dvm (master)"'

new_case ref-option; run pipe -- --user --ref feature/x
check ref-option eval 'works 9.11.0 && has "(from avramovioan/dvm@feature/x)"'

new_case ref-variable; run pipe DVM_REF=v9.9.8 -- --user
check ref-variable eval 'works 9.9.8'

new_case dir-option; run pipe -- --dir "$home/.local/bin/"
check dir-option eval 'works 9.9.9 && has "installed to $home/.local/bin/dvm"'

new_case downloaded-copy
cp "$installer" "$tmp/install.sh"
out=$(cd "$tmp" && in_case sh ./install.sh --user 2>&1 </dev/null); code=$?
check downloaded-copy eval 'works 9.9.9 && has "Downloading dvm (v9.9.9)"'

new_case reinstall; run pipe -- --user --ref v9.9.8; run pipe -- --user
check reinstall eval 'works 9.9.9 && has "(was 9.9.8, from avramovioan/dvm@v9.9.9)" && ! has "Run '\''dvm list'\''"'

new_case bad-ref; run pipe DVM_REF='v1;rm' -- --user
check bad-ref eval '[ "$code" -ne 0 ] && has "not a tag or branch name" && [ ! -e "$installed" ]'

new_case unknown-ref; run pipe -- --user --ref nope
check unknown-ref eval '[ "$code" -ne 0 ] && has "could not download" && [ ! -e "$installed" ]'

new_case not-dvm; run pipe -- --user --ref broken
check not-dvm eval '[ "$code" -ne 0 ] && has "is not the dvm script" && [ ! -e "$installed" ]'

new_case unknown-option; run pipe -- --bogus
check unknown-option eval '[ "$code" -eq 2 ] && has "unknown option"'

# dvm update
new_case update-to-latest; run pipe -- --user --ref v9.9.8; dvm update
check update-to-latest eval 'works 9.9.9 && has "Updating dvm 9.9.8 to 9.9.9" && has "(was 9.9.8, from avramovioan/dvm@v9.9.9)"'

new_case update-already-latest; run pipe -- --user; dvm update
check update-already-latest eval 'works 9.9.9 && has "dvm 9.9.9 is the latest version"'

new_case update-newer-than-release; run pipe -- --user --ref master; dvm update
check update-newer-than-release eval 'works 9.10.0 && has "dvm 9.10.0 is newer than the latest release (9.9.9)"'

new_case update-no-release; run pipe -- --user --ref v9.9.8
out=$(in_case env DVM_LATEST_URL="file://$tmp/missing" "$installed" update 2>&1 </dev/null); code=$?
check update-no-release eval '[ "$code" -eq 1 ] && has "could not find the latest dvm release" && [ "$(in_case "$installed" version)" = "dvm 9.9.8" ]'

new_case update-from-clone
out=$(in_case bash "$repo_root/unix/dvm" update 2>&1 </dev/null); code=$?
check update-from-clone eval '[ "$code" -eq 0 ] && has "runs from the git clone in $repo_root" && has "git -C"'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
