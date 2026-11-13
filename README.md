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

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/avramovioan/dvm/master/windows/install.ps1 | iex
```

Both download dvm from the latest GitHub release and put the `dvm` command
on your PATH. Nothing else: .NET isn't touched until you run a `dvm`
command, e.g. `dvm list`, `dvm install lts`, or `dvm init` to take over a
.NET install you already have. Run them again to update dvm. The guides below cover options,
installing from a clone, and reading the installer before running it.

| Guide | Covers |
|---|---|
| [unix/README.md](unix/README.md) | Linux and macOS (`unix/dvm`, a bash script): install, alias for bash/zsh/fish, what works with which SDKs and runtimes, and how every command works there |
| [windows/README.md](windows/README.md) | Windows (`windows/dvm.ps1`): install, alias for PowerShell and cmd, what works with which SDKs and runtimes, and how every command works there |
| [AGENTS.md](AGENTS.md) | Notes for coding agents (and people) changing dvm: design rules, gotchas, how to test |

## Commands

| Command | What it does |
|---|---|
| `dvm list` | LTS channels, newest first. For each: the latest runtime and the latest SDK of each feature band, plus everything you have installed. End-of-life channels are hidden unless you have something installed from them. |
| `dvm list --all` | Also shows the end-of-life LTS channels. |
| `dvm list 10.0` | Every runtime and SDK of one channel (also works for non-LTS channels such as `9.0`). |
| `dvm install lts` | Newest SDK of the newest supported LTS. |
| `dvm install 10.0` | Newest SDK of that channel. |
| `dvm install 10.0.404` | That exact SDK. |
| `dvm install runtime 8.0` | Only the newest runtime of a channel, without its SDK. Also `runtime lts` and `runtime 8.0.34`. |
| `dvm uninstall 10.0.404` | Removes an SDK, and its runtime unless something still needs it (see [SDKs and runtimes](#sdks-and-runtimes)). |
| `dvm uninstall runtime 10.0.11` | Removes a runtime, unless an installed SDK needs it. |
| `dvm init` | Looks for .NET installed elsewhere, offers to install the same versions with dvm, and makes dvm's folder the system default `dotnet`. |
| `dvm version` | Prints dvm's version. |

`-y` / `--yes` answers yes to every question, for scripts.

## Why no version switching (unlike nvm)

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

## SDKs and runtimes

- **The SDK builds, the runtime runs.** Every SDK comes with the runtime of
  its own version (SDK 10.0.404 brings runtime 10.0.15). `dvm list` shows the
  runtimes and SDKs of each channel in separate sections.
- **One SDK builds every target.** SDK 10 builds `net8.0` projects too; it
  downloads the 8.0 reference packs from NuGet. You only need another SDK
  when a `global.json` pins one.
- **Running needs the app's runtime.** A `net8.0` app runs on the newest
  installed 8.0.x runtime, never on 10.0. With only SDK 10 installed,
  `dotnet build` of a `net8.0` project works, but `dotnet run` and
  `dotnet test` fail with *"Framework 'Microsoft.NETCore.App', version '8.0.0'
  was not found"*. `dvm install runtime 8.0` fixes that without installing
  SDK 8. There's nothing to configure afterwards: `dotnet` picks the right
  runtime per app.
- **Several patches of one channel are rarely useful.** Apps always use the
  newest patch (10.0.15 over 10.0.11), so older patches that came with older
  SDKs can go.

`dvm list` labels every installed runtime:

| Label | Meaning |
|---|---|
| `comes with SDK 10.0.404` | Installed with that SDK. |
| `runtime only` | Installed with `dvm install runtime`, or no installed SDK came with it. |
| `apt: …`, `macOS installer`, `Windows installer` | Installed by that installer; `dvm uninstall` goes through it. |

What gets removed:

- **`dvm uninstall runtime <version>`** removes that runtime, unless an
  installed SDK needs it. An SDK runs on the runtime it came with or any newer
  patch of the same channel, so SDK 10.0.303 (which came with 10.0.11) is fine
  with 10.0.15. If no other installed runtime is new enough, dvm refuses and
  names the SDKs:
  ```
  dvm: runtime 10.0.15 can't be removed: no other installed runtime is new enough for
    SDK 10.0.404 (needs 10.0.15 or newer)
  Remove those SDKs first with: dvm uninstall <version>
  ```
- **`dvm uninstall <sdk>`** removes the SDK and the runtime it came with. The
  runtime stays if another SDK came with it too, if you installed it with
  `dvm install runtime` (running that for a runtime you already have marks it
  to keep), or if another SDK still needs it.
- The newest `host/fxr` folder always stays, because the `dotnet` command
  uses it.

## How it works

- **Which folder.** dvm manages the standard .NET folder of each OS, the same
  one Microsoft's installers and Visual Studio use, so anything already
  installed there shows up with ✔ straight away:

  | OS | Folder |
  |---|---|
  | Linux | `/usr/share/dotnet` |
  | macOS | `/usr/local/share/dotnet` |
  | Windows | `C:\Program Files\dotnet` |

- **Downloads.** The release list comes from Microsoft's release metadata
  (`builds.dotnet.microsoft.com/dotnet/release-metadata`). It is cached for an
  hour and used offline when there's no network. Installs are done by
  Microsoft's own `dotnet-install.sh` / `dotnet-install.ps1`, so you always
  get Microsoft's builds. A runtime install is Microsoft's ASP.NET Core
  runtime package, which contains the base .NET runtime too; on Windows dvm
  also installs the Windows Desktop runtime (WPF and Windows Forms), like the
  Windows SDKs do. When you install an older version than you already have,
  dvm passes `--skip-non-versioned-files`, so the `dotnet` command isn't
  replaced by the older one.
- **Admin rights.** The standard folder is a system folder. You always run
  `dvm` as yourself; it asks for `sudo` (Linux/macOS) or a UAC prompt
  (Windows) only for the step that writes there. `dvm list` never needs
  them.
- **Other installs.** On the first run, dvm looks for .NET installed somewhere
  else (Ubuntu's apt packages, Homebrew's `dotnet` formula, `~/.dotnet`,
  `%LOCALAPPDATA%\Microsoft\dotnet`, ...). It offers to install the same
  versions with dvm (SDKs, plus the runtimes those SDKs don't bring),
  updates the system links/PATH, and then tells you the exact command that
  removes the old install. It never deletes anything
  itself. After that it reminds you on `dvm list` until the old install is
  gone.
- **Removing SDKs and runtimes** goes through whoever installed them: dvm
  deletes its own folders, runs `apt`/`dnf` for package-owned ones, runs the
  registered uninstaller for the Windows installer, and sends you to the
  Visual Studio Installer for SDKs that Visual Studio owns.

## Dependencies

None to install:

- **Linux / macOS:** bash 3.2+ plus `curl` (or `wget`), `grep`, `awk`, `sed`
  and `tar`, all preinstalled. It doesn't use jq: dvm has a small JSON reader
  built from `grep` and `awk`.
- **Windows:** Windows PowerShell 5.1, which ships with Windows 10 and 11.
  PowerShell 7 works too.

## Repository layout

```
unix/dvm              the command for Linux and macOS (bash)
unix/install.sh       installs it to /usr/local/bin (or ~/.local/bin), from a clone or from GitHub
windows/dvm.ps1       the command for Windows (PowerShell)
windows/dvm.cmd       the global `dvm` command that starts dvm.ps1
windows/install.ps1   installs both to %LOCALAPPDATA%\Programs\dvm, from a clone or from GitHub
tests/                shared test cases, run against both versions, and installer tests
.github/workflows/    tests on every push; a release for every version tag
AGENTS.md             notes for anyone (or any agent) changing dvm
```

## Tests

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

The installers have their own tests, which use a fake GitHub made of local
files:

```bash
tests/test-install.sh                 # unix/install.sh
pwsh -File tests/test-install.ps1     # windows/install.ps1 (in CI only, on Windows)
```

`.github/workflows/test.yml` runs all of them on Ubuntu, macOS (`/bin/bash`
3.2) and Windows PowerShell 5.1, and then installs dvm with the one-liners
from the pushed commit.

## Releasing

The installers download the **latest GitHub release** (or `master` while
there is none). To publish a version:

1. Set the same version in `unix/dvm` (`DVM_VERSION`), `windows/dvm.ps1`
   (`$DvmVersion`) and `tests/expected/version.txt`, and commit.
2. Tag and push:
   ```bash
   git tag v1.2.0 && git push origin v1.2.0
   ```

`.github/workflows/release.yml` checks that the tag matches both scripts,
runs the tests, and creates the release with the scripts attached.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `DVM_ROOT` | the standard folder | Manage another folder. System links/PATH are then left alone and dvm prints the lines to add yourself. |
| `DVM_CACHE` | `~/.cache/dvm`, `%LOCALAPPDATA%\dvm\cache` | Downloaded release data and install scripts. |
| `DVM_STATE` | `~/.config/dvm`, `%APPDATA%\dvm` | Remembers which other installs it already asked about (`seen`) and which runtimes you installed on their own (`runtimes`). |
| `DVM_OFFLINE` | unset | Use only cached data. |
| `DVM_NO_DETECT` | unset | Skip looking for other .NET installs. |
| `NO_COLOR` | unset | Plain output. |
