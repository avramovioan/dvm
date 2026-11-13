#!/usr/bin/env bash
# Tests unix/install.sh in all the ways people run it: from a clone, piped
# from the web (latest release, no release yet, --ref), and its errors.
# GitHub is replaced by file:// URLs, so this runs offline. Needs curl.
#   tests/test-install.sh
# shellcheck disable=SC2016  # the check conditions are single-quoted on purpose: eval runs them later
set -u

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
installer="$repo_root/unix/install.sh"
want_version=$(sed -n 's/^DVM_VERSION="\(.*\)"$/dvm \1/p' "$repo_root/unix/dvm")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fake GitHub: <base>/<ref>/unix/dvm, and the "latest release" API answer.
base="$tmp/github"
for ref in v9.9.9 master feature/x; do
  mkdir -p "$base/$ref/unix" && cp "$repo_root/unix/dvm" "$base/$ref/unix/dvm"
done
mkdir -p "$base/broken/unix" && printf '<html>404</html>\n' > "$base/broken/unix/dvm"
printf '{\n  "url": "x",\n  "tag_name": "v9.9.9",\n  "name": "dvm v9.9.9"\n}\n' > "$tmp/latest.json"

pass=0; fail=0
check() { # <name> <condition...>
  local name=$1; shift
  if "$@"; then pass=$((pass + 1)); echo "ok       $name"
  else fail=$((fail + 1)); echo "FAILED   $name"; printf '%s\n' "$out" | sed 's/^/    /'; fi
}

# run <case> <how: file|pipe> [env assignments...] -- [installer args...]
run() {
  local name=$1 how=$2; shift 2
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  home="$tmp/$name/home"; mkdir -p "$home"
  local -a common=(HOME="$home" PATH="$home/.local/bin:$PATH"
                   DVM_BASE_URL="file://$base" DVM_API_URL="file://$tmp/latest.json")
  if [ "$how" = file ]; then
    out=$(env "${common[@]}" ${envs[@]+"${envs[@]}"} sh "$installer" "$@" 2>&1 </dev/null); code=$?
  else
    out=$(env "${common[@]}" ${envs[@]+"${envs[@]}"} sh -s -- "$@" <"$installer" 2>&1); code=$?
  fi
  installed="$home/.local/bin/dvm"
}

has() { printf '%s\n' "$out" | grep -qF -- "$1"; }
# Installed, and nothing else done: no `dvm init`, no dvm state or cache.
works() {
  [ "$code" -eq 0 ] && [ -x "$installed" ] && [ "$("$installed" version)" = "$want_version" ] &&
    has "Run 'dvm list'" && ! has "dvm manages" && ! has "No other .NET installs" &&
    [ ! -e "$home/.config/dvm" ] && [ ! -e "$home/.cache/dvm" ]
}

run from-clone file -- --user
check from-clone eval 'works && has "(from $repo_root/unix)" && cmp -s "$installed" "$repo_root/unix/dvm"'

run latest-release pipe -- --user
check latest-release eval 'works && has "Downloading dvm (v9.9.9)" && has "(from avramovioan/dvm@v9.9.9)"'

run no-release-yet pipe DVM_API_URL="file://$tmp/missing.json" -- --user
check no-release-yet eval 'works && has "Downloading dvm (master)"'

run ref-option pipe -- --user --ref feature/x
check ref-option eval 'works && has "(from avramovioan/dvm@feature/x)"'

run ref-variable pipe DVM_REF=master -- --user
check ref-variable eval 'works && has "(from avramovioan/dvm@master)"'

run downloaded-copy file -- --user   # install.sh alone in a folder: downloads
cp "$installer" "$tmp/install.sh"
out=$(cd "$tmp" && env HOME="$home" PATH="$home/.local/bin:$PATH" DVM_BASE_URL="file://$base" \
      DVM_API_URL="file://$tmp/latest.json" sh ./install.sh --user 2>&1 </dev/null); code=$?
check downloaded-copy eval 'works && has "Downloading dvm (v9.9.9)"'

run bad-ref pipe DVM_REF='v1;rm' -- --user
check bad-ref eval '[ "$code" -ne 0 ] && has "not a tag or branch name" && [ ! -e "$installed" ]'

run unknown-ref pipe -- --user --ref nope
check unknown-ref eval '[ "$code" -ne 0 ] && has "could not download" && [ ! -e "$installed" ]'

run not-dvm pipe -- --user --ref broken
check not-dvm eval '[ "$code" -ne 0 ] && has "is not the dvm script" && [ ! -e "$installed" ]'

run unknown-option pipe -- --bogus
check unknown-option eval '[ "$code" -eq 2 ] && has "unknown option"'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
