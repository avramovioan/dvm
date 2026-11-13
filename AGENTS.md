# AGENTS.md

Notes for coding agents (and people) working on this repository. Read this
first. The README files describe dvm for users; this file covers what you
need in order to change it without breaking it.

## What this is

`dvm` is a small .NET SDK **and runtime** version manager, similar in spirit
to nvm but without version switching. It:

- lists the .NET LTS channels, each with a Runtimes and an SDKs section,
  with a ✔ for what's installed;
- installs and removes Microsoft's builds side by side in the **OS's standard
  dotnet folder**;
- makes that folder the system default `dotnet`.

It doesn't switch versions: the `dotnet` host already picks the runtime per
app (target framework) and the SDK per project (`global.json`, else the
newest).

There are two implementations that must behave identically:

| File | Platform | Language constraints |
|---|---|---|
| `unix/dvm` | Linux and macOS | bash **3.2** (macOS `/bin/bash`), POSIX `awk`/`sed`/`grep`, no jq, BSD and GNU tools |
| `windows/dvm.ps1` (started by `windows/dvm.cmd`) | Windows | **Windows PowerShell 5.1**, `Set-StrictMode -Version 2.0`; must also run on PowerShell 7 |

| Other files | Role |
|---|---|
| `unix/install.sh` | POSIX sh; installs `unix/dvm` to `/usr/local/bin` (or `~/.local/bin` with `--user`), and nothing else. Uses the clone's `unix/dvm` when it sits next to it, otherwise downloads it from GitHub (`curl \| bash` one-liner) |
| `windows/install.ps1` | installs `dvm.cmd` + `lib\dvm.ps1` to `%LOCALAPPDATA%\Programs\dvm`, adds it to the user PATH, and nothing else. Uses the clone's files when they sit next to it, otherwise downloads them (`irm \| iex` one-liner) |
| `windows/dvm.cmd` | runs `powershell.exe -ExecutionPolicy Bypass -File lib\dvm.ps1` (falls back to `dvm.ps1` next to it, as in the clone) |
| `tests/cases.txt`, `tests/fixtures/`, `tests/expected/` | shared test cases, fake release data, fake dotnet folder layout, expected output |
| `tests/run-unix.sh`, `tests/run-windows.ps1` | run every case against one implementation and compare the output byte for byte |
| `tests/test-install.sh`, `tests/test-install.ps1` | installer tests against a fake GitHub made of `file://` URLs |
| `.github/workflows/test.yml` | CI: all tests on Ubuntu, macOS (`/bin/bash` 3.2) and Windows PowerShell 5.1, then a real one-liner install from the pushed commit |
| `.github/workflows/release.yml` | a tag `vX.Y.Z` creates the GitHub release the installers download from |
| `README.md`, `unix/README.md`, `windows/README.md` | user docs; the OS READMEs hold the explanatory tables and must match behavior |

The repository is `https://github.com/avramovioan/dvm` (default branch
`master`).

## Rules you must keep

1. **Same behavior and output on both implementations.** Every user-visible
   change goes into `unix/dvm` **and** `windows/dvm.ps1` in the same change,
   with the same wording, column widths and order. The shared tests enforce
   it. The only allowed differences are real OS differences: paths, sudo vs
   UAC, the Windows Desktop runtime, and owner labels (apt/rpm/macOS
   installer vs Windows installer/Visual Studio).
2. **No dependencies.** Nothing beyond what the OS ships: no jq, no Python,
   no PowerShell modules. JSON on Unix is read by `json_flat` (a grep
   tokenizer plus an awk walker that prints `path<TAB>value`, with `/` as the
   path separator because the key `releases.json` contains a dot).
3. **Only Microsoft's builds.** Installs go through Microsoft's
   `dotnet-install.sh` / `dotnet-install.ps1`. Versions come from
   `https://builds.dotnet.microsoft.com/dotnet/release-metadata`
   (`releases-index.json` and each channel's `releases.json`).
4. **Never delete outside the managed folder, and never delete a foreign
   install.** For .NET found elsewhere (apt's `/usr/lib/dotnet`, `~/.dotnet`,
   Homebrew, ...), dvm installs the same versions into its folder and
   **prints** the removal command; it never runs it. The elevated Windows
   copy only deletes the exact paths it's given (`delete:<path>`) and refuses
   anything outside the dotnet folder.
5. **Run as the user, elevate per step.** Never require `sudo dvm`.
   - Unix: `run_priv <target> <cmd...>` runs a command directly if the target
     is writable, else through `sudo`, else prints it.
   - Windows: `Invoke-Privileged` runs all steps of one command in **one**
     hidden elevated copy (one UAC prompt) and streams that copy's log into
     the user's window. The steps are passed as arguments:
     `install:<sdk>/<its runtime>`, `runtime:<version>`, `delete:<path>`,
     `uninstaller:<sdk>`, `rtuninstaller:<runtime>`, `integrate`.
   - The elevated copy may run as another account, so **state files
     (`%APPDATA%\dvm`) are only written by the non-elevated parent.**
6. **Removing goes through the installer that owns it.**
   - apt/dnf for package-owned SDKs and runtimes.
   - The registered uninstaller for Windows installer bundles.
   - The Visual Studio Installer for SDKs that Visual Studio owns: dvm only
     prints this.
   - A refusal, with a message, for a Windows runtime that came inside an
     SDK installer or Visual Studio (it has no uninstaller of its own).
7. **Don't overwrite user data without being asked.** Every delete shows the
   folders and asks (`-y/--yes` skips the question).

## The .NET model the code relies on

- An SDK comes with exactly one runtime: the `framework.version` in
  `sdk/<v>/dotnet.runtimeconfig.json`. It runs on that runtime **or any newer
  patch of the same major.minor**. Functions: `needing_sdks` /
  `Get-NeedingSdks`.
- **Runtime install.** `dotnet-install --runtime aspnetcore` installs
  `Microsoft.NETCore.App` + `Microsoft.AspNetCore.App` + `host/fxr`. On
  Windows dvm also runs `--runtime windowsdesktop`.
  - "Installed": `shared/Microsoft.NETCore.App/<v>` exists.
  - "Complete": every framework of `$RuntimeFrameworks` / `runtime_complete`
    exists.
- **`dvm uninstall <sdk>`** removes:
  - `sdk/<v>`;
  - its runtime's `packs/*/<rt>` and `templates/<rt>`, unless another SDK
    came with the same runtime;
  - its runtime's `shared/*/<rt>` and `host/fxr/<rt>`, unless:
    - another SDK came with the same runtime,
    - `<rt>` is in the kept-runtimes file, or
    - another SDK needs it;
  - `sdk-manifests/<band>` (band = `x.y.N00`), unless another SDK is in the
    same band.
- **`dvm uninstall runtime <v>`** refuses when `needing_sdks` isn't empty.
  Otherwise it removes `shared/*/<v>` and `host/fxr/<v>`, never
  packs/templates (those belong to SDKs).
- **The newest `host/fxr` is never removed:** the `dotnet` muxer uses it.
- **`--skip-non-versioned-files`** (`-SkipNonVersionedFiles`) is passed when
  the newest installed `host/fxr` is at least the runtime being installed.
  Microsoft's script otherwise overwrites `dotnet`/`dotnet.exe` with the
  installed version's, which would downgrade it.
- **Kept runtimes.** `dvm install runtime <v>` records `<v>` in
  `$DVM_STATE/runtimes`, even if `<v>` was already there because an SDK
  brought it. Kept runtimes survive SDK removal and are labelled
  `runtime only`. `dvm uninstall runtime` removes the entry.
- **List labels for runtimes.** `comes with SDK a, b` (SDK runtimeconfig
  match, not kept) or `runtime only`, plus `; <owner>` when an installer owns
  the runtime.
- **Who installed what.**
  - Linux: `dpkg -S` / `rpm -qf` on the folders.
  - macOS: `pkgutil --pkgs` receipts. The names are **assumed and
    untested**: `com.microsoft.dotnet.dev.<sdk>.*` for SDKs; non-`dev`
    receipts containing `.<version>.` for runtimes.
  - Windows: `HKLM\...\Uninstall\*` DisplayNames:
    - `Microsoft .NET SDK x.y.z`, with "Visual Studio" in the name meaning
      Visual Studio owns it;
    - `Microsoft .NET Runtime - x.y.z`;
    - `Microsoft ASP.NET Core x.y.z - Shared Framework`;
    - `Microsoft Windows Desktop Runtime - x.y.z`;
    - `Microsoft .NET x.y.z - Windows Server Hosting`.

    Bundles have their own uninstaller; hidden MSI entries only have msiexec.
- **System default.**
  - Unix: `/usr/local/bin/dotnet` symlink, `/etc/dotnet/install_location`
    and `install_location_<arch>`, and on macOS `/etc/paths.d/dotnet`.
  - Windows: `C:\Program Files\dotnet\` first in the machine PATH (the
    registry value is edited directly as `REG_EXPAND_SZ`, so `%SystemRoot%`
    entries stay unexpanded) and
    `HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\<arch>\InstallLocation`.
  - Only for the standard folder (`DVM_ROOT` unset), or when `DVM_SYSROOT`
    is set (tests).
- **Taking over other installs** (`foreign_roots` / `Get-ForeignRoots`, then
  `offer_adoption` / `Invoke-Adoption`).
  - Each folder is asked about once; the folder is then recorded in
    `$DVM_STATE/seen`. `dvm init` asks again.
  - SDKs are matched to Microsoft's build of the same version, else the
    newest of the same feature band.
  - Runtimes the SDKs don't bring are installed as kept runtimes.

## Gotchas

**bash 3.2:**

- No `declare -A`, `mapfile`, `${x,,}`, `|&` or `;&`.
- Empty arrays need `${a[@]+"${a[@]}"}`.
- No `readlink -f` on macOS (use `realpath_`), no `sed -i` (it differs
  between BSD and GNU), no `grep -P`.
- Version sort: `sort -t. -k1,1nr -k2,2nr -k3,3nr` (`vsort`).

**Inside the bash script:**

- `set -u` is on, `set -e` is off. Functions return explicitly
  (`return 0`) where a failing last test would leak a non-zero status.
- Heredocs inside functions use `<<EOF`. If you write patches with heredocs
  in the shell, pick another terminator.

**PowerShell 5.1:**

- No `?:`, `??`, `&&`, `||`.
- StrictMode forbids reading missing properties; use `Get-Prop`.
- PowerShell 7 turns ISO dates in JSON into `DateTime`; use `Format-Value`.
- A function that returns nothing gives `$null`, so wrap the result with
  `@(...)` before `.Count`.
- `Fail` exits the process and, in the elevated copy, writes to its log.

**Files on disk:**

- The cache file names differ per OS and that's fine: Unix uses
  `<ch>.sdks.tsv` and `<ch>.runtimes.tsv`, Windows `<ch>.releases.tsv`.
  Changing the format means changing the file name, so old caches are
  ignored instead of misread.
- Line endings: `.gitattributes` keeps LF everywhere, except CRLF for `*.cmd`
  and `*.ps1`. That only applies to checkouts: `raw.githubusercontent.com`
  serves the files as stored (LF). That's why `install.ps1` converts what it
  downloads.
- Keep `windows/*.ps1` pure ASCII (use `[char]0x2714` for ✔). Windows
  PowerShell 5.1 reads a UTF-8 file without a BOM as ANSI.

## The installers

Both installers work in two modes:

- **Clone mode.** They are run from a clone, so the dvm files sit next to
  them, and they install those.
- **Download mode.** Everything else: piped from the web, or a lone
  downloaded copy. They download the files from
  `https://raw.githubusercontent.com/<repo>/<ref>/...`.

How download mode picks and checks the files:

- `<ref>` is `--ref` / `-Ref` / `DVM_REF` if given. Otherwise it's
  `v<version>` from the `VERSION` file attached to the latest release
  (`github.com/<repo>/releases/latest/download/VERSION`, a plain download
  with no API rate limit), or `master` when there is no release yet.
- Refs are restricted to `[A-Za-z0-9._/-]`, and what arrives is checked: a
  bash shebang plus `DVM_VERSION=`, or `$DvmVersion =` / `powershell.exe`.
  That catches HTML error pages.
- `DVM_REPO`, `DVM_BASE_URL` and `DVM_LATEST_URL` override where it
  downloads from (CI, forks, tests); dvm itself reads them too, for
  `dvm update`. The tests use `file://` URLs; `install.ps1` copies
  those itself, because PowerShell 7's web cmdlets can't read them.

The version:

- It is written **only** in `VERSION`. The scripts hold the placeholder
  `DVM_VERSION="0.0.0-dev"` / `$DvmVersion = '0.0.0-dev'`, and these lines
  must stay exactly like that.
- The installers replace the placeholder in the copy they install with
  `VERSION` from the same ref, or from `../VERSION` in clone mode. They
  refuse to install a placeholder copy without a valid `VERSION`, but
  accept old files that already have a version.
- The release workflow does the same for the files it attaches.
- A script that still has the placeholder knows it runs from a clone
  (`SOURCE_DIR` / `$SourceDir`). It reads `../VERSION` for `dvm version`, and
  `dvm update` tells the user to `git pull`.
- The test runners replace `dvm <VERSION file>` with `dvm <VERSION>`, so a
  version bump changes no expected output.

`dvm update`:

- It downloads the latest release's `VERSION` and compares it with its own
  version. If the release is newer, it downloads **that release's**
  installer (`<raw>/v<latest>/...`) and runs it.
  - Unix: `--ref v<latest> --dir <folder of the running dvm>`; the
    installer's `sudo` handles `/usr/local/bin`.
  - Windows: `-Ref v<latest>`; Windows only updates
    `%LOCALAPPDATA%\Programs\dvm`, so an install anywhere else is refused.
- Without a release, or without a network, it fails with a message. It
  never falls back to `master`.
- `windows/dvm.cmd` keeps `powershell.exe ... %* & exit /b !ERRORLEVEL!` on
  **one line**.
  - Why one line: the installer replaces `dvm.cmd` while it runs, and cmd.exe
    reads batch files line by line, so anything after that line could come
    from the new file.
  - Why `!ERRORLEVEL!`: with delayed expansion it is read when `exit` runs.
    A bare `exit /b` returned 0 under `cmd /c`, and `%ERRORLEVEL%` is read
    before PowerShell starts.
  - The cost: delayed expansion drops `!` from arguments, which dvm never
    takes. The script path uses `!DVM_PS1!` so a `!` in a folder name
    survives.
  - CI checks that exit codes 0 and 2 come through.

Constraints that come from `curl | bash`:

- Options arrive after `bash -s --`.
- The installers only install the `dvm` command. They must **not** run
  `dvm init` or any other dvm command that touches .NET: the owner wants
  users to end up with just the CLI. The installer tests check that no dvm
  cache or state appears.

Constraints that come from `irm | iex`:

- The installer runs **inside the user's session**. Never call `exit`, which
  would close their window; `throw` instead.
- Keep everything inside the `Install-Dvm` function, so
  `$ErrorActionPreference` etc. don't leak, and remove the function at the
  end.
- `iex` can't pass parameters, so every parameter also has an environment
  variable (`-Ref` → `DVM_REF`).
- `$PSScriptRoot` is empty, which is how download mode is detected.

Converting downloaded files:

- `install.ps1` rewrites downloaded files with CRLF line endings, because
  cmd.exe misparses LF-only batch files.
- `dvm.ps1` gets a UTF-8 BOM, and `dvm.cmd` gets no BOM (a BOM breaks
  cmd).

The one-liner URLs in the READMEs point at `master`, so `master` must always
hold working installers. The installers then fetch dvm itself from the
latest release.

## Testing

Run all of these after any change (Docker is enough on Linux):

```bash
tests/run-unix.sh                                    # bash 5
docker run --rm -v "$PWD":/dvm -w /dvm bash:3.2 bash -c \
  'apk add --no-cache coreutils findutils diffutils >/dev/null; DVM_TEST_BASH=/usr/local/bin/bash bash tests/run-unix.sh'
docker run --rm -v "$PWD":/dvm -w /dvm mcr.microsoft.com/powershell pwsh -NoProfile -File tests/run-windows.ps1
docker run --rm -v "$PWD":/mnt koalaman/shellcheck:stable unix/dvm unix/install.sh tests/run-unix.sh tests/test-install.sh
tests/test-install.sh                                # unix/install.sh, needs curl
docker run --rm -v "$PWD":/dvm -w /dvm mcr.microsoft.com/powershell pwsh -NoProfile -File tests/test-install.ps1
```

`tests/test-install.ps1` refuses to run on Windows unless `CI` is set,
because there the installer really edits the user PATH.

How the tests work:

- **Cases.** Each line of `tests/cases.txt` is `name|arguments`.
- **Isolation.** Every case runs offline (`DVM_OFFLINE=1`, `DVM_NO_DETECT=1`,
  `NO_COLOR=1`) against a fresh copy of `fixtures/cache` (trimmed release
  JSON), `fixtures/state` and a fake dotnet folder built from
  `fixtures/root.txt`.
- **Extra output.** For `uninstall-*` cases the runners also print the
  folders left; for `*-runtime-*` cases, the kept-runtimes file.
- **Intended output change:**
  1. Run `tests/run-unix.sh --update`.
  2. Review the diff in `tests/expected/`.
  3. Run the PowerShell runner. It must pass **without** changes to
     expected.
- **The fixture describes a deliberate scenario** (see the comment in
  `root.txt`):
  - SDK 10.0.303 whose own runtime 10.0.11 was removed;
  - a runtime-only 8.0.22;
  - 8.0.34 in the kept list;
  - WindowsDesktop folders.

  Changing it changes many expected files.

The tests can't cover real downloads, sudo/UAC, the registry or installer
detection. Check installs by hand in a scratch folder, which skips all
system integration:

```bash
DVM_ROOT=/tmp/x DVM_STATE=/tmp/x-state DVM_NO_DETECT=1 unix/dvm install runtime 8.0
```

## Status

- Linux: used for real on Ubuntu 24.04.
- Windows: not yet run on a real machine. The checklist is at the end of
  `windows/README.md`; keep it current when you change Windows-only code.
- macOS: never run on a real Mac; only bash 3.2 compatibility is tested.
- Version bump: edit `VERSION` only.
- Releasing:
  1. Push the bump to `master` and wait for green CI.
  2. Run `git tag "v$(cat VERSION)" && git push origin "v$(cat VERSION)"`.

  `release.yml` refuses a tag that isn't `v` plus `VERSION`. Until the
  first release exists, the installers install from `master` and
  `dvm update` reports that there's no release.
- There are no build steps on purpose: each OS's dvm is one source file that
  runs as it is from a clone. Only the version is written in at install and
  release time.

## Style

- **Messages:**
  - Errors are `dvm: <message>` on stderr, with exit code 1. Unknown
    commands print the usage text with exit code 2.
  - Start sentences with a capital letter (`✔ Runtime 8.0.34 installed`),
    but write `dvm: runtime ...` lowercase after the prefix.
  - When something is refused, say what to run instead.
- **Docs:** short sentences, tables for comparisons. When behavior changes,
  update the matching tables in both OS READMEs.
