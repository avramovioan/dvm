# dvm on Windows

dvm is a PowerShell script with a small `dvm.cmd` launcher, so the `dvm`
command works in PowerShell, cmd and Windows Terminal. It runs on
**Windows PowerShell 5.1**, which comes with every Windows 10 and 11, so
there's nothing to install first. PowerShell 7 works too.

1. [Install](#install), either with [one command](#a-one-command-recommended) or [from a git clone](#b-from-a-git-clone)
2. [Update dvm](#updating-dvm)
3. [Use dvm with .NET versions](#using-dvm)
4. [Remove dvm entirely](#removing-dvm-entirely)
5. [How it works](#how-it-works): what the installer does, and where things are stored

## Install

Pick **one** of the two ways. Neither needs administrator rights.

### A. One command (recommended)

**Step 1.** Open PowerShell (a normal window, not "Run as administrator")
and install dvm:

```powershell
irm https://raw.githubusercontent.com/avramovioan/dvm/master/windows/install.ps1 | iex
```

This downloads the latest release of dvm to `%LOCALAPPDATA%\Programs\dvm`
and adds that folder to your user PATH. `irm` downloads the installer and
`iex` runs it. This is the usual way to install command-line tools on
Windows (Scoop, Bun, Deno and uv do the same), and the execution policy
doesn't block it.

From cmd instead of PowerShell:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/avramovioan/dvm/master/windows/install.ps1 | iex"
```

**Step 2.** Check that it works:

```powershell
dvm --version
```

It prints `dvm` and the version, e.g. `dvm 1.1.1`. You don't need an alias.

- **The PowerShell window you installed from** works right away.
- **Other windows, cmd, and the cmd install command** need a new terminal
  first, because running terminals keep the PATH they started with.

That's it: you have the `dvm` command. Go on with [Using dvm](#using-dvm).

### B. From a git clone

Use this to run dvm straight from the source code, e.g. to read or change
it. You make the `dvm` command yourself, with a PowerShell alias. The
examples use `C:\src\dvm`.

**Step 1.** Clone the repository:

```powershell
git clone https://github.com/avramovioan/dvm.git C:\src\dvm
```

**Step 2.** Allow your PowerShell profile to run. Windows doesn't run any
`.ps1` file by default, and that includes your profile, where the alias will
live. This needs no administrator rights. Skip it if `Get-ExecutionPolicy`
already shows `RemoteSigned` or `Unrestricted`.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**Step 3.** Add the alias to your profile. It points at `dvm.cmd`, not
`dvm.ps1`, so the execution policy never gets in the way of dvm itself.

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
Add-Content -Path $PROFILE -Value "Set-Alias dvm 'C:\src\dvm\windows\dvm.cmd'"
```

Windows PowerShell 5.1 and PowerShell 7 have separate profiles. If you use
both, run step 3 in each.

**Step 4.** Open a new PowerShell window and check that it works:

```powershell
dvm --version
```

It prints `dvm` and the version from the clone's `VERSION` file.
`Get-Command dvm` shows that `dvm` is an alias for `C:\src\dvm\windows\dvm.cmd`.

That's it. Go on with [Using dvm](#using-dvm).

> The alias only exists in PowerShell. To also have `dvm` in cmd, add a
> macro for every new cmd window. This replaces any AutoRun command you
> already have, so check first with
> `reg query "HKCU\Software\Microsoft\Command Processor" /v AutoRun`.
> ```bat
> reg add "HKCU\Software\Microsoft\Command Processor" /v AutoRun /t REG_SZ /d "doskey dvm=C:\src\dvm\windows\dvm.cmd $*" /f
> ```

## Updating dvm

**If you installed with the one command (A):**

```powershell
dvm update
```

It checks the latest release on GitHub. If that's newer than your dvm, it
installs it in place. No administrator rights are needed:

```
PS> dvm update
Checking for a newer dvm ...
Updating dvm 1.1.0 to 1.1.1 ...
Downloading dvm (v1.1.1) from https://raw.githubusercontent.com/avramovioan/dvm ...
✔ dvm 1.1.1 installed to C:\Users\you\AppData\Local\Programs\dvm (was 1.1.0, from avramovioan/dvm@v1.1.1)
```

If you're already up to date, it says so and changes nothing.

**If you use a git clone (B):** pull the latest code. The alias then runs
the new version right away:

```powershell
git -C C:\src\dvm pull
```

(`dvm update` notices that it runs from a clone and tells you the same.)

## Using dvm

### First steps

```powershell
dvm list            # the .NET versions, with a check mark for what you have
dvm install lts     # install the newest SDK
```

dvm installs into `C:\Program Files\dotnet`, the folder the official
installers and Visual Studio use. Anything already installed there shows up
right away. When dvm needs to write there, it shows **one UAC prompt** per
command. Run it in a normal terminal.

If .NET is also installed in another folder (for example
`%LOCALAPPDATA%\Microsoft\dotnet`), run `dvm init` once. dvm offers to
install the same versions into `C:\Program Files\dotnet` and tells you how to
remove the old folder ([details](#taking-over-net-in-other-folders)).

### Commands

| Command | What it does |
|---|---|
| `dvm list` | LTS channels, newest first: their latest runtime and SDKs, plus everything you have installed |
| `dvm list --all` | also shows the end-of-life LTS channels |
| `dvm list 10.0` | every runtime and SDK of one channel (also `9.0` and other non-LTS channels) |
| `dvm install lts` / `10.0` / `10.0.404` | the newest SDK of the newest LTS / of a channel / that exact SDK |
| `dvm install runtime 8.0` | only a runtime, without its SDK (also `runtime lts`, `runtime 8.0.34`) |
| `dvm uninstall 10.0.404` | remove an SDK (its runtime goes too, unless something still needs it) |
| `dvm uninstall runtime 10.0.11` | remove a runtime, unless an installed SDK needs it |
| `dvm init` | take over .NET installed elsewhere, and make `C:\Program Files\dotnet` the system default |
| `dvm update` | update dvm itself |
| `dvm --version` | print dvm's version |

`-y` / `--yes` answers yes to every question, for scripts.

### SDKs and runtimes

The SDK builds your code. The runtime runs it. Every SDK comes with exactly
one runtime, the one of its own version, so SDK 10.0.404 brings
runtime 10.0.15. On Windows a runtime has three parts: the base .NET runtime,
ASP.NET Core and Windows Desktop (WPF and Windows Forms). A `net8.0` app needs
an 8.0.x runtime and runs on the newest 8.0.x you have. It never runs on 10.0.
You don't switch versions: `dotnet` picks the right runtime per app, and the
newest SDK unless a `global.json` pins one.

**What works with what you have**, for a `net8.0` project and a `net10.0`
project:

| Installed | `dotnet build` net8.0 | `dotnet run` / `test` net8.0 | `dotnet MyApp.dll` or `MyApp.exe` (built net8.0 app) | anything with net10.0 |
|---|---|---|---|---|
| SDK 10 only | yes | **no**: *Framework 'Microsoft.NETCore.App', version '8.0.0' was not found* | **no**, same error | yes |
| SDK 10 + `dvm install runtime 8.0` | yes | yes | yes | yes |
| SDK 8 only | yes | yes | yes | **no**: SDK 8 can't build net10.0 |
| runtime 8 only, no SDK at all | **no**: *No .NET SDKs were found* | **no**, same error | yes | no |

A `global.json` that pins an 8.0.x SDK is the one case where SDK 10 isn't
allowed to build. That repository then needs SDK 8: `dvm install 8.0`.

**Which command for which need:**

| You want to | Run |
|---|---|
| Build and run net10.0 projects | `dvm install 10.0` (newest SDK, with its runtime) |
| Also run and test net8.0 projects | `dvm install runtime 8.0` (newest 8.0 runtime, no SDK) |
| Build a repository whose `global.json` pins SDK 8 | `dvm install 8.0` or the exact version, e.g. `dvm install 8.0.428` |
| Use one exact older runtime (to reproduce a bug, or match a server) | `dvm list 8.0` shows them all, then `dvm install runtime 8.0.22` |
| Only run apps that are already built (like a server) | `dvm install runtime 10.0`, no SDK |

## Removing dvm entirely

**Step 1 (optional): remove the .NET versions.** Removing dvm leaves .NET
installed. If you want .NET gone too, do it first, while you still have
dvm:

```powershell
dvm list                          # see what's installed
dvm uninstall 10.0.404            # an SDK
dvm uninstall runtime 8.0.34      # a runtime
```

SDKs and runtimes from the official installers go through their own
uninstaller, and dvm points you to the Visual Studio Installer for the ones
Visual Studio needs.

**Step 2: remove the `dvm` command.**

| You installed with | Do this |
|---|---|
| the one command (A) | Delete the folder: `Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\dvm"`. Then remove it from your user PATH: **Settings → System → About → Advanced system settings → Environment Variables → User variables → Path → select `...\Programs\dvm` → Delete**. |
| a git clone (B) | Delete the `Set-Alias dvm ...` line from your profile (`notepad $PROFILE`). If you added the cmd macro, remove it with `reg delete "HKCU\Software\Microsoft\Command Processor" /v AutoRun /f`. Then delete the clone: `Remove-Item -Recurse -Force C:\src\dvm` |

**Step 3: remove dvm's own files** (cached downloads, and what it
remembers):

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\dvm", "$env:APPDATA\dvm" -ErrorAction SilentlyContinue
```

Open a new terminal. `dvm --version` now says that `dvm` is not recognized.

## How it works

### Where everything is

| What | Where |
|---|---|
| The `dvm` command (A) | `%LOCALAPPDATA%\Programs\dvm\dvm.cmd`, which starts `...\lib\dvm.ps1` |
| The .NET folder dvm manages | `C:\Program Files\dotnet` |
| System settings for that folder | the system PATH, and `HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\<arch>\InstallLocation` |
| Downloads and release data | `%LOCALAPPDATA%\dvm\cache` |
| What dvm remembers | `%APPDATA%\dvm` |

### What `install.ps1` does

| Step | Detail |
|---|---|
| 1. Get dvm | **Run from a clone:** it uses the clone's `dvm.ps1` and `dvm.cmd`. **Anywhere else** (`irm \| iex`, or a downloaded copy of `install.ps1`): it downloads both from GitHub, from the **latest release**, or from `master` while there is no release yet. It checks that the files really are dvm's, and converts them to what Windows expects (CRLF line endings, and a BOM so Windows PowerShell 5.1 reads `dvm.ps1` as UTF-8). |
| 2. Write the version | Writes the version from the repository's `VERSION` file into `dvm.ps1`, so `dvm --version` reports it. |
| 3. Install it | Copies `dvm.cmd` and `lib\dvm.ps1` to **`%LOCALAPPDATA%\Programs\dvm`** and removes the "downloaded from the internet" mark. |
| 4. PATH | Adds that folder to your **user PATH** (not the system PATH), and to the PATH of the PowerShell window it runs in. |

That's all it does. It doesn't touch .NET. `dvm update` runs the installer
of the newest release in the same way.

| Parameter (`-File`) | With `irm \| iex`, set first | Effect |
|---|---|---|
| `-Ref <tag or branch>` | `$env:DVM_REF = 'v1.1.0'` | Install that version instead of the latest release. |

`irm | iex` can't pass parameters, which is why it reads an environment
variable instead:

```powershell
$env:DVM_REF = 'v1.1.0'; irm https://raw.githubusercontent.com/avramovioan/dvm/master/windows/install.ps1 | iex
```

To read the installer before you run it, download it first:

```powershell
irm https://raw.githubusercontent.com/avramovioan/dvm/master/windows/install.ps1 -OutFile install.ps1
notepad install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### Why `dvm.cmd`

Windows blocks `.ps1` scripts by default (execution policy). `dvm.cmd` starts
`dvm.ps1` with `-ExecutionPolicy Bypass` for that one process, so `dvm` works
without changing any system setting. `dvm.ps1` sits in the `lib` subfolder
because, when both are in the same PATH folder, PowerShell prefers
`dvm.ps1` over `dvm.cmd` and runs into the policy.

`dvm.cmd` runs PowerShell and exits on one line on purpose. cmd.exe reads
batch files line by line, and `dvm update` replaces `dvm.cmd` while it runs.

To put dvm on your PATH by hand instead of with `install.ps1`, keep the same
layout:

```powershell
$dir = "$env:LOCALAPPDATA\Programs\dvm"
New-Item -ItemType Directory -Force -Path "$dir\lib" | Out-Null
Copy-Item C:\src\dvm\windows\dvm.cmd $dir
Copy-Item C:\src\dvm\windows\dvm.ps1 "$dir\lib"
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ";$dir", 'User')
```

### What's in the .NET folder

Everything lives side by side in `C:\Program Files\dotnet`. `dotnet.exe`
picks the SDK and runtime per project from there.

| Folder | What it is | Comes with |
|---|---|---|
| `dotnet.exe` | the `dotnet` command | every package; dvm keeps the newest one |
| `sdk\10.0.404` | an SDK | the SDK package |
| `shared\Microsoft.NETCore.App\10.0.15` | the base .NET runtime | an SDK package or a runtime package |
| `shared\Microsoft.AspNetCore.App\10.0.15` | the ASP.NET Core runtime | an SDK package or a runtime package |
| `shared\Microsoft.WindowsDesktop.App\10.0.15` | the WPF and Windows Forms runtime | an SDK package or a runtime package |
| `host\fxr\10.0.15` | the part of `dotnet` that picks SDKs and runtimes; the newest one is used | an SDK package or a runtime package |
| `packs\Microsoft.NETCore.App.Ref\10.0.15`, ... | reference packs to build against | the SDK package |
| `templates\10.0.15` | the `dotnet new` templates | the SDK package |
| `sdk-manifests\10.0.400` | workload manifests of one feature band | the SDK package |

### What each command does

| Command | Steps | Admin (UAC) |
|---|---|---|
| `dvm list` | 1. Looks for .NET outside the .NET folder (asks once per folder, see [Taking over](#taking-over-net-in-other-folders)). 2. Reads Microsoft's release list (from the cache if it's less than an hour old). 3. Reads what's in the .NET folder, and Windows' list of installed programs to see who installed each SDK and runtime. 4. Prints the table. 5. Reminds you of anything left to do (old installs, system PATH, `DOTNET_ROOT`). | never |
| `dvm install 10.0.404` | 1. Checks the version against the release list. 2. Downloads Microsoft's `dotnet-install.ps1` (refreshed daily). 3. Shows one UAC prompt and runs `dotnet-install.ps1 -Version 10.0.404 -InstallDir "C:\Program Files\dotnet" -NoPath` in a hidden elevated copy of dvm; its output appears in your window. 4. In the same elevated step, sets the system PATH and the install location in the registry if they're missing. 5. Checks what `dotnet` new terminals will find. | one prompt, for steps 3 and 4 |
| `dvm install runtime 8.0` | The same, but step 3 runs `-Runtime aspnetcore -Version 8.0.34` and then `-Runtime windowsdesktop -Version 8.0.34`. Then adds `8.0.34` to `%APPDATA%\dvm\runtimes`. | one prompt |
| `dvm uninstall 10.0.404` | 1. Finds out who installed the SDK. 2. dvm's own SDK: works out which folders belong only to it (see [What `dvm uninstall` removes](#what-dvm-uninstall-removes)), shows them, asks, and deletes exactly those in the elevated copy (it refuses anything outside the .NET folder). Windows installer: runs the registered uninstaller. Visual Studio: removes nothing and points you to the Visual Studio Installer. | one prompt |
| `dvm uninstall runtime 10.0.11` | 1. Refuses if an installed SDK needs that runtime. 2. Runs the runtime installer's uninstaller, or tells you which program it came with, or shows the folders, asks and deletes them. 3. Removes the version from `%APPDATA%\dvm\runtimes`. | one prompt |
| `dvm init` | Asks about every .NET install outside the .NET folder again, sets the system PATH and install location, and checks your PATH. | one prompt, if something is missing |
| `dvm update` | Downloads the `VERSION` file of the latest release. If that's newer, downloads that release's `install.ps1` and runs it with `-Ref v<version>`. Only works for a dvm in `%LOCALAPPDATA%\Programs\dvm`. | never |

If you decline the UAC prompt, dvm says so. You can then run the same
command in a terminal opened with **Run as administrator**, where no prompt
is needed.

When you install a version that is older than what you already have, dvm
adds `-SkipNonVersionedFiles`. Without it, Microsoft's script would replace
`dotnet.exe` with the older one.

### What `dvm install` adds

Microsoft ships every SDK as one package that contains its runtime, so dvm
always downloads the whole package. Microsoft's script then only adds the
versioned folders that aren't there yet. Nothing that's already installed is
overwritten.

| You run | Downloads | Adds to `C:\Program Files\dotnet` |
|---|---|---|
| `dvm install 10.0.404` (nothing installed yet) | SDK package 10.0.404 | `sdk\10.0.404` and runtime 10.0.15 (`shared\*\10.0.15`, `host\fxr\10.0.15`), packs, templates, manifests |
| `dvm install 10.0.404` when runtime 10.0.15 is already there | SDK package 10.0.404 | only the SDK's own folders; 10.0.15 is already there |
| `dvm install 10.0.303` when runtime 10.0.15 is already there | SDK package 10.0.303 | the SDK **and runtime 10.0.11**: that's the exact version it comes with. `dvm uninstall runtime 10.0.11` can remove it afterwards. |
| `dvm install 10.0.404` again | nothing | nothing: *SDK 10.0.404 is already installed* |
| `dvm install runtime 8.0` | ASP.NET Core and Windows Desktop runtime packages 8.0.34 (much smaller than an SDK) | `shared\Microsoft.NETCore.App\8.0.34`, `shared\Microsoft.AspNetCore.App\8.0.34`, `shared\Microsoft.WindowsDesktop.App\8.0.34`, `host\fxr\8.0.34`; no SDK |
| `dvm install runtime 10.0.15` when SDK 10.0.404 brought it | nothing | nothing. It is marked to keep: from now on it stays when you remove that SDK. |

### What `dvm uninstall` removes

An SDK runs on the runtime it came with **or any newer patch of the same
channel**. SDK 10.0.303 came with 10.0.11 but runs fine on 10.0.15. dvm uses
that rule so it never removes a runtime that an installed SDK needs.

Examples, with SDKs 10.0.404 (came with 10.0.15), 10.0.303 (came with 10.0.11,
which was removed) and 10.0.110 (came with 10.0.10) installed by dvm:

| You run | Removes | Keeps, and why |
|---|---|---|
| `dvm uninstall 10.0.110` | `sdk\10.0.110`, runtime 10.0.10 (`shared\*\10.0.10`, `host\fxr\10.0.10`), `packs\*\10.0.10`, `templates\10.0.10`, `sdk-manifests\10.0.100` | nothing else uses them |
| `dvm uninstall 10.0.404` | `sdk\10.0.404`, `packs\*\10.0.15`, `templates\10.0.15`, `sdk-manifests\10.0.400` | runtime 10.0.15: SDK 10.0.303 needs 10.0.11 or newer, and 10.0.15 is the only one |
| `dvm uninstall 8.0.428` after `dvm install runtime 8.0.34` | the SDK, its packs, templates and manifests | runtime 8.0.34: you installed it on its own |
| `dvm uninstall runtime 10.0.10` | `shared\*\10.0.10`, `host\fxr\10.0.10` | packs and templates belong to SDK 10.0.110, which now runs on 10.0.15 |
| `dvm uninstall runtime 10.0.15` | nothing; it stops with an error that names SDK 10.0.404 and 10.0.303 | no other installed runtime is new enough for them |

Two more rules:

- `packs`, `templates` and `sdk-manifests` stay while another SDK uses the
  same version.
- The newest `host\fxr` folder always stays, because `dotnet.exe` uses it.

### Files dvm keeps for itself

| File | Content |
|---|---|
| `%LOCALAPPDATA%\dvm\cache\releases-index.json` | Microsoft's list of .NET channels (refreshed hourly) |
| `%LOCALAPPDATA%\dvm\cache\10.0.json` | all releases of one channel (refreshed hourly) |
| `%LOCALAPPDATA%\dvm\cache\10.0.releases.tsv`, `releases-index.tsv` | the same data in a form dvm reads quickly |
| `%LOCALAPPDATA%\dvm\cache\dotnet-install.ps1` | Microsoft's install script (refreshed daily) |
| `%APPDATA%\dvm\seen` | other .NET folders you already answered about |
| `%APPDATA%\dvm\runtimes` | runtimes you installed with `dvm install runtime` |

Without a network, dvm uses the cached copies. `DVM_CACHE`, `DVM_STATE` and
the other variables in the [main README](../README.md#environment-variables)
change these places.

### Making dvm's dotnet the default

`C:\Program Files\dotnet` is the folder the official installers and Visual
Studio use, and the one Windows and built apps look in by default. If
`dotnet.exe` exists there and something is missing, dvm also:

| Setting | Why |
|---|---|
| puts `C:\Program Files\dotnet\` first in the **system PATH** | the `dotnet` command in every terminal |
| sets `HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\<arch>\InstallLocation` | where built apps and IDEs look for .NET |

The installers normally set both already. dvm edits the PATH in the
registry directly, so entries like `%SystemRoot%\system32` stay as they are.

### SDKs and runtimes that are already installed

Everything already in `C:\Program Files\dotnet` shows up with ✔ right away.
dvm checks Windows' list of installed programs to see who installed each SDK
and runtime:

| Installed by | Shown as | `dvm uninstall` |
|---|---|---|
| dvm | `✔ 10.0.404` | deletes its folders (see [What `dvm uninstall` removes](#what-dvm-uninstall-removes)) |
| Official installer / winget | `✔ 10.0.404 ... (Windows installer)` | runs its registered uninstaller, so it also leaves *Apps & features* |
| Visual Studio | `✔ 8.0.416 ... (Visual Studio)` | removes nothing and points you to the **Visual Studio Installer** (*Modify → Individual components*), because Visual Studio puts back SDKs it needs |

Runtimes from an installer show `(... Windows installer)` too, and there are
two cases:

| The runtime came from | `dvm uninstall runtime` |
|---|---|
| the standalone runtime installer or the Hosting Bundle | runs its uninstaller(s) |
| inside an SDK installer or Visual Studio | removes nothing and tells you to remove that program instead, because the runtime has no uninstaller of its own |

`dvm list` labels every installed runtime: `comes with SDK 10.0.404`,
`runtime only` (installed with `dvm install runtime`, or no installed SDK
came with it), or `Windows installer`.

### Taking over .NET in other folders

On the first run dvm also looks outside `C:\Program Files\dotnet`: everything
on the user and system PATH, `DOTNET_ROOT`, `%LOCALAPPDATA%\Microsoft\dotnet`
(the default of `dotnet-install.ps1`) and `%USERPROFILE%\.dotnet`. If it
finds SDKs or runtimes there, it asks once:

```
Found .NET outside dvm: C:\Users\you\AppData\Local\Microsoft\dotnet (folder)
  SDK 8.0.428, 10.0.404
  runtime 8.0.34, 10.0.15
Install the same version(s) with dvm into C:\Program Files\dotnet? [Y/n]
```

If you say yes:

- **Install:** it installs the same SDKs, plus the newest runtime of each
  channel that those SDKs don't bring. One UAC prompt covers all of them.
- **System PATH:** it sets it up.
- **Old folder:** it prints the command that deletes it. For
  `%USERPROFILE%\.dotnet` that command keeps `.dotnet\tools`, your global
  tools.
- **Variables:** if the old folder is also in your PATH or in `DOTNET_ROOT`,
  dvm tells you which variable to edit.

`dvm init` asks again at any time.

`C:\Program Files (x86)\dotnet` (32-bit .NET) is left alone.

### Troubleshooting

- **`irm` fails with "Could not create SSL/TLS secure channel".** Older
  Windows 10 builds don't enable TLS 1.2 for PowerShell 5.1 by default. Run
  this first, in the same window:
  `[Net.ServicePointManager]::SecurityProtocol = 'Tls12'`
- **The one-liner says `could not download`.** Check that
  `https://github.com/avramovioan/dvm` opens in a browser. A company proxy may
  block `raw.githubusercontent.com`.
- **`dvm` is not recognized.** Open a new terminal after installing; running
  terminals keep the PATH they started with. For the alias, check that your
  profile runs (`Get-ExecutionPolicy` must not be `Restricted`) and that
  `Get-Command dvm` points to `dvm.cmd`.
- **`dvm.ps1 cannot be loaded because running scripts is disabled`.**
  PowerShell found `dvm.ps1` instead of `dvm.cmd`. Keep `dvm.ps1` in the `lib`
  subfolder, or point your alias at `dvm.cmd`.
- **✔ shows up as `?` or a box.** The old console window (conhost) with a
  raster font can't draw it. Use Windows Terminal (the default on Windows 11)
  or pick a TrueType font such as Cascadia Mono or Consolas.
- **`dotnet` still runs another version.** Open a new terminal; running
  terminals keep the PATH they started with. `dvm list` tells you if a PATH
  entry or `DOTNET_ROOT` still points somewhere else.
- **Which SDK does a project use?** Run `dotnet --version` in the project
  folder. Pin it with `global.json` if needed.
- **"Framework 'Microsoft.NETCore.App', version '8.0.0' was not found".**
  The app targets a .NET version whose runtime isn't installed. Run
  `dvm install runtime 8.0` (with the version from the message).
- **"No .NET SDKs were found".** Only runtimes are installed. Install an SDK
  with `dvm install lts`.

### Checklist for the first test on a real Windows machine

Microsoft's release data and the listing logic are covered by the shared
tests. These Windows-only parts can only be checked on Windows:

1. Install A (`irm ... | iex`) → `dvm --version` works in the same
   PowerShell window, and in cmd after opening a new one.
2. `dvm list` shows Visual Studio / installer SDKs with the right label.
3. `dvm install 10.0` in a normal terminal → one UAC prompt → the install
   progress appears in your own window → `dotnet --list-sdks` shows it.
4. Declining the UAC prompt gives the "not granted" message and no error
   trace.
5. `dvm uninstall` on an installer-owned SDK runs its uninstaller and the
   entry disappears from *Apps & features*.
6. The system PATH still contains `%SystemRoot%`-style entries unexpanded
   after dvm changed it (`reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path`).
7. `dvm install runtime 8.0` → one UAC prompt → `dotnet --list-runtimes`
   shows `Microsoft.NETCore.App`, `Microsoft.AspNetCore.App` and
   `Microsoft.WindowsDesktop.App` 8.0.x, and `dotnet --version` still reports
   the newest SDK (dotnet.exe wasn't replaced by the 8.0 one).
8. `dvm list` labels runtimes from the official runtime installer and from
   SDK installers as `Windows installer`; `dvm uninstall runtime` runs the
   runtime installer's uninstaller, and refuses (with a message) for a runtime
   that came inside an SDK installer or Visual Studio.
9. Install B (the alias in `$PROFILE`, and the cmd macro) starts dvm from the
   clone, and `dvm install` from the alias still gets its UAC prompt.
10. The cmd install command (`powershell -Command "irm ... | iex"`) works,
    and the PowerShell window stays open when the installer fails (try
    `$env:DVM_REF = 'nope'` first).
11. `dvm update` from an older version replaces dvm in place, and
    `dvm no-such-command; $LASTEXITCODE` prints 2.
