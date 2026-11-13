# dvm — .NET SDK and runtime version manager

`dvm` lists the .NET **LTS** releases with their runtimes and SDKs, puts a ✔
next to what you have installed, and installs or removes them side by side.
It behaves the same on Linux, macOS and Windows.

```
$ dvm list
.NET LTS releases, newest first    ✔ = installed in /usr/share/dotnet

10.0  LTS · active, supported until 2028-11-14
  Runtimes
    ✔ 10.0.15     2026-11-10  latest  (comes with SDK 10.0.404)
  SDKs
    ✔ 10.0.404    2026-11-10  latest
      10.0.303    2026-08-11  latest 10.0.3xx
      10.0.204    2026-05-12  latest 10.0.2xx
      10.0.115    2026-11-10  latest 10.0.1xx

8.0  LTS · end of life since 2026-11-10
  Runtimes
    ✔ 8.0.34      2026-11-10  latest  (runtime only)
  SDKs
      8.0.428     2026-11-10  latest
      ...
```

## Install

Pick your system. Each guide takes you from installing to a working `dvm`
command, then covers updating, using dvm with .NET versions, and removing
it again.

- **[Linux and macOS →](unix/README.md)**
- **[Windows →](windows/README.md)**

## What dvm does

| Command | What it does |
|---|---|
| `dvm list` | LTS channels, newest first: their latest runtime and SDKs, plus everything you have installed |
| `dvm install lts` / `10.0` / `10.0.404` | install an SDK |
| `dvm install runtime 8.0` | install only a runtime, e.g. to run `net8.0` apps that you build with SDK 10 |
| `dvm uninstall 10.0.404`, `dvm uninstall runtime 10.0.11` | remove an SDK or a runtime, never one that something still needs |
| `dvm init` | take over .NET installed elsewhere, and make dvm's folder the system default `dotnet` |
| `dvm update` | update dvm itself |

The full list, and what works with which SDKs and runtimes, is in the guide
for your system.

### Why no version switching (unlike nvm)

nvm has to switch the active Node version in your shell. .NET doesn't need
that: every SDK and runtime lives side by side in **one folder**, and the
`dotnet` command picks the right one for each project:

- **Running an app**: the runtime comes from the app's target framework
  (`net8.0` runs on the newest installed 8.0.x runtime).
- **Building**: the newest SDK is used, unless a `global.json` pins one:
  ```json
  { "sdk": { "version": "10.0.404", "rollForward": "latestPatch" } }
  ```

So dvm only has to install and remove things in that folder, and keep that
folder the system default.

### How it works, in short

- **Which folder.** dvm manages the standard .NET folder of each OS, the same
  one Microsoft's installers and Visual Studio use. Anything already
  installed there shows up with ✔ straight away:

  | OS | Folder |
  |---|---|
  | Linux | `/usr/share/dotnet` |
  | macOS | `/usr/local/share/dotnet` |
  | Windows | `C:\Program Files\dotnet` |

- **Microsoft's builds only.** The release list comes from Microsoft's
  release metadata, and installs are done by Microsoft's own
  `dotnet-install.sh` / `dotnet-install.ps1`.
- **Admin rights only when needed.** You run `dvm` as yourself; it asks for
  `sudo` or shows a UAC prompt only for the step that writes to that folder.
- **Other installs.** dvm finds .NET installed somewhere else (apt packages,
  Homebrew, `~/.dotnet`, ...), offers to install the same versions, and tells
  you the exact command that removes the old install. It never deletes
  anything outside its folder itself.
- **Removing** goes through whoever installed it: dvm's own folders, `apt` /
  `dnf`, the Windows installer, or the Visual Studio Installer.

## Development

The rest of this page is for changing and releasing dvm.
[AGENTS.md](AGENTS.md) has the design rules and gotchas.

### Repository layout

```
VERSION               dvm's version: the only place it is written down
unix/dvm              the command for Linux and macOS (bash 3.2+)
unix/install.sh       installs it to /usr/local/bin (or ~/.local/bin), from a clone or from GitHub
windows/dvm.ps1       the command for Windows (Windows PowerShell 5.1+)
windows/dvm.cmd       the global `dvm` command that starts dvm.ps1
windows/install.ps1   installs both to %LOCALAPPDATA%\Programs\dvm, from a clone or from GitHub
tests/                shared test cases, run against both versions, and installer tests
.github/workflows/    tests on every push; a release for every version tag
AGENTS.md             notes for anyone (or any agent) changing dvm
```

No dependencies: on Linux and macOS dvm uses only bash, `curl` or `wget`,
`grep`, `awk`, `sed` and `tar` (it has a small JSON reader, no jq); on
Windows only Windows PowerShell 5.1.

### Tests

Both versions run the same cases (`tests/cases.txt`) against the same fixed
release data (`tests/fixtures/`) and have to produce exactly the output in
`tests/expected/`. That keeps the two versions identical.

```bash
tests/run-unix.sh                                             # Linux / macOS
powershell -ExecutionPolicy Bypass -File tests\run-windows.ps1  # Windows
pwsh -File tests/run-windows.ps1                              # PowerShell 7, any OS
```

After an intended output change, run `tests/run-unix.sh --update`, review the
diff in `tests/expected/`, and check that the Windows runner still passes.

The installers and `dvm update` have their own tests, which use a fake
GitHub made of local files:

```bash
tests/test-install.sh                 # unix/install.sh
pwsh -File tests/test-install.ps1     # windows/install.ps1 (in CI only, on Windows)
```

`.github/workflows/test.yml` runs all of them on Ubuntu, macOS (`/bin/bash`
3.2) and Windows PowerShell 5.1, and then installs dvm with the one-line
installers from the pushed commit.

### Versions and releases

dvm's version is written in **one place: the `VERSION` file** (one line,
e.g. `1.2.0`). The scripts only contain a placeholder, `0.0.0-dev`:

| Where dvm runs | Where its version comes from |
|---|---|
| Installed by an installer or `dvm update` | The installer writes `VERSION` into the installed copy. |
| Downloaded from a release page | The release workflow wrote `VERSION` into the attached files. |
| Straight from a git clone (alias, symlink, tests) | dvm reads `VERSION` from the clone. |

The installers and `dvm update` install the **latest GitHub release**, or
`master` while there is none. They find the latest release through the
`VERSION` file attached to it
(`github.com/avramovioan/dvm/releases/latest/download/VERSION`).

**To publish a version:**

1. Raise the version in `VERSION`, commit, and push to `master`.
2. Wait until the `test` workflow for that commit is green.
3. Tag the commit with the same version and push the tag:
   ```bash
   git tag "v$(cat VERSION)" && git push origin "v$(cat VERSION)"
   ```

`.github/workflows/release.yml` then checks that the tag is `v` plus the
`VERSION` file, runs the tests, and creates the release. The release has
the scripts (with the version written in) and the `VERSION` file attached.
Until you tag, nobody gets the new version, so `master` can move ahead of
the latest release.

| Change | Raise | Example |
|---|---|---|
| Bug fixes only | the last number | 1.1.0 → 1.1.1 |
| New features; everything that worked still works | the middle number, last one to 0 | 1.1.3 → 1.2.0 |
| Something that worked now works differently | the first number | 1.4.2 → 2.0.0 |

If a release workflow fails, nothing is published: delete the tag
(`git tag -d v1.2.0 && git push origin :refs/tags/v1.2.0`), fix the
problem, and tag again. Never move the tag of a release that was published;
release a new version instead.

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `DVM_ROOT` | the standard folder | Manage another folder. System links/PATH are then left alone and dvm prints the lines to add yourself. |
| `DVM_CACHE` | `~/.cache/dvm`, `%LOCALAPPDATA%\dvm\cache` | Downloaded release data and install scripts. |
| `DVM_STATE` | `~/.config/dvm`, `%APPDATA%\dvm` | Remembers which other installs it already asked about (`seen`) and which runtimes you installed on their own (`runtimes`). |
| `DVM_OFFLINE` | unset | Use only cached data. |
| `DVM_NO_DETECT` | unset | Skip looking for other .NET installs. |
| `DVM_REPO`, `DVM_BASE_URL`, `DVM_LATEST_URL` | `avramovioan/dvm` on GitHub | Where the installers and `dvm update` download dvm from (for forks and tests). |
| `NO_COLOR` | unset | Plain output. |
