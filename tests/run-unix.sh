#!/usr/bin/env bash
# Runs the shared test cases (tests/cases.txt) against unix/dvm.
#   tests/run-unix.sh            compare with tests/expected/
#   tests/run-unix.sh --update   rewrite tests/expected/ from the current output
# Works offline: release data comes from tests/fixtures/cache.
set -u

here=$(cd "$(dirname "$0")" && pwd)
dvm="$here/../unix/dvm"
update=""; [ "${1:-}" = --update ] && update=1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_root() { # <folder>: lay out the fake dotnet folder from fixtures/root.txt
  local root=$1 kind a b
  while read -r kind a b; do
    case "$kind" in
      sdk) mkdir -p "$root/sdk/$a"
           printf '{\n  "runtimeOptions": {\n    "framework": {\n      "name": "Microsoft.NETCore.App",\n      "version": "%s"\n    }\n  }\n}\n' "$b" \
             > "$root/sdk/$a/dotnet.runtimeconfig.json" ;;
      dir) mkdir -p "$root/$a" ;;
    esac
  done < "$here/fixtures/root.txt"
}

version=$(tr -d '[:space:]' < "$here/../VERSION")
pass=0; fail=0
while IFS='|' read -r name args; do
  case "$name" in ""|\#*) continue ;; esac
  case_dir="$tmp/$name"
  mkdir -p "$case_dir/root" "$case_dir/cache" "$case_dir/state"
  cp "$here"/fixtures/cache/*.json "$case_dir/cache/"
  cp "$here"/fixtures/state/* "$case_dir/state/"
  build_root "$case_dir/root"

  # shellcheck disable=SC2086  # args are split on purpose
  actual=$(cd "$case_dir" && DVM_ROOT="$case_dir/root" DVM_CACHE="$case_dir/cache" DVM_STATE="$case_dir/state" \
           DVM_OFFLINE=1 DVM_NO_DETECT=1 NO_COLOR=1 "${DVM_TEST_BASH:-bash}" "$dvm" $args 2>&1 </dev/null; echo "exit=$?")
  case "$name" in uninstall-*)
    actual="$actual
--- folders left:
$(cd "$case_dir/root" && find . -mindepth 1 -type d | sed 's|^\./||' | LC_ALL=C sort)" ;;
  esac
  case "$name" in *-runtime-*)
    actual="$actual
--- kept runtimes:
$(cat "$case_dir/state/runtimes" 2>/dev/null)" ;;
  esac
  # dvm prints its version from the VERSION file; the expected output says <VERSION>.
  actual=$(printf '%s\n' "$actual" | sed -e "s|$case_dir/root|<ROOT>|g" -e "s|^dvm $version\$|dvm <VERSION>|")

  expected_file="$here/expected/$name.txt"
  if [ -n "$update" ]; then
    printf '%s\n' "$actual" > "$expected_file"
    echo "updated  $name"
  elif [ -f "$expected_file" ] && [ "$actual" = "$(cat "$expected_file")" ]; then
    pass=$((pass + 1)); echo "ok       $name"
  else
    fail=$((fail + 1)); echo "FAILED   $name"
    diff -u "$expected_file" <(printf '%s\n' "$actual") | sed 's/^/    /'
  fi
done < "$here/cases.txt"

[ -n "$update" ] && exit 0
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
