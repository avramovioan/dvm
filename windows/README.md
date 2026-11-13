# dvm on Windows

On Windows, dvm is the PowerShell script **`windows\dvm.ps1`**, started
through a small **`windows\dvm.cmd`**, and **`windows\install.ps1`** puts both
on your PATH. It runs on **Windows PowerShell 5.1**, which comes with every
Windows 10 and 11, so there's nothing to install first. PowerShell 7 works
too. The `dvm` command works in PowerShell, cmd and Windows Terminal.

| | Windows |
|---|---|
| dotnet folder dvm manages | `C:\Program Files\dotnet` |
| Where `install.ps1` puts `dvm` | `%LOCALAPPDATA%\Programs\dvm\dvm.cmd` and `...\lib\dvm.ps1` |
| Downloads and release data | `%LOCALAPPDATA%\dvm\cache` |
| What dvm remembers | `%APPDATA%\dvm` |

## Install

In PowerShell (no administrator rights needed):

```powershell
git clone <your-repo-url> dvm
powershell -ExecutionPolicy Bypass -File .\dvm\windows\install.ps1
```

Or download the repository as a ZIP, extract it, and run the same
`install.ps1` line from the extracted folder.

`install.ps1`:

1. copies `dvm.cmd` and `lib\dvm.ps1` to **`%LOCALAPPDATA%\Programs\dvm`**,
2. adds that folder to your **user PATH**,
3. runs `dvm init`.

Then **open a new terminal**. Use `-NoInit` to skip step 3.

### Why `dvm.cmd`

Windows blocks `.ps1` scripts by default (execution policy). `dvm.cmd` starts
`dvm.ps1` with `-ExecutionPolicy Bypass` for that one process, so `dvm` works
without changing any system setting. `dvm.ps1` sits in the `lib` subfolder
because, when both are in the same PATH folder, PowerShell prefers
`dvm.ps1` over `dvm.cmd` and runs into the policy.

## Making the `dvm` command work in your terminal

There are three ways to get a `dvm` command. They all run the same script.

| Way | Updates with `git pull` | PowerShell | cmd | Scripts and other programs |
|---|---|---|---|---|
| **`install.ps1`** (recommended) | no, run `install.ps1` again | yes | yes | yes |
| **PowerShell alias** to the clone | yes | yes | no | no |
| **cmd macro** (`doskey`) to the clone | yes | no | yes | no |

`install.ps1` keeps working if you move or delete the clone. The alias and
the macro run the scripts inside your clone, so they always run the version
you last pulled. Both point at **`dvm.cmd`**, not `dvm.ps1`, so the execution
policy never gets in the way. In the clone, `dvm.cmd` finds `dvm.ps1` right
next to it.

The examples use a clone in `C:\src\dvm`.

### PowerShell alias

1. Windows doesn't run any `.ps1` file by default, and that includes your
   PowerShell profile. Allow your own scripts once (this needs no
   administrator rights):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
   Skip this if `Get-ExecutionPolicy` already shows `RemoteSigned` or
   `Unrestricted`.
2. Create your profile if it doesn't exist yet, and open it:
   ```powershell
   if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
   notepad $PROFILE
   ```
3. Add this line, save, and open a new PowerShell window:
   ```powershell
   Set-Alias dvm 'C:\src\dvm\windows\dvm.cmd'
   ```

Windows PowerShell 5.1 and PowerShell 7 have separate profiles
(`Documents\WindowsPowerShell\...` and `Documents\PowerShell\...`). If you
use both, repeat steps 2 and 3 in each. Check the result with
`Get-Command dvm`.

### cmd macro

For the current cmd window:
```bat
doskey dvm=C:\src\dvm\windows\dvm.cmd $*
```

For every new cmd window, register it as cmd's AutoRun command:
```bat
reg add "HKCU\Software\Microsoft\Command Processor" /v AutoRun /t REG_SZ /d "doskey dvm=C:\src\dvm\windows\dvm.cmd $*" /f
```

This replaces any AutoRun command you already have. Check first with
`reg query "HKCU\Software\Microsoft\Command Processor" /v AutoRun`.

### Putting dvm on your PATH by hand

This is the same as what `install.ps1` does. Keep `dvm.ps1` in a `lib`
subfolder, as explained above:

```powershell
$dir = "$env:LOCALAPPDATA\Programs\dvm"
New-Item -ItemType Directory -Force -Path "$dir\lib" | Out-Null
Copy-Item .\dvm\windows\dvm.cmd $dir
Copy-Item .\dvm\windows\dvm.ps1 "$dir\lib"
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ";$dir", 'User')
```

Or add the folder in **Settings → System → About → Advanced system settings →
Environment Variables → User variables → Path → New**. Open a new terminal
afterwards.

## SDKs and runtimes, in practice

The SDK builds your code. The runtime runs it. Every SDK comes with exactly
one runtime, the one of its own version, so SDK 10.0.404 brings
runtime 10.0.15. On Windows a runtime has three parts: the base .NET runtime,
ASP.NET Core and Windows Desktop (WPF and Windows Forms). A `net8.0` app needs
an 8.0.x runtime and runs on the newest 8.0.x you have. It never runs on 10.0.

### What works with what you have

For a `net8.0` project and a `net10.0` project:

| Installed in `C:\Program Files\dotnet` | `dotnet build` net8.0 | `dotnet run` / `test` net8.0 | `dotnet MyApp.dll` or `MyApp.exe` (built net8.0 app) | anything with net10.0 |
|---|---|---|---|---|
| SDK 10 only | yes | **no**: *Framework 'Microsoft.NETCore.App', version '8.0.0' was not found* | **no**, same error | yes |
| SDK 10 + `dvm install runtime 8.0` | yes | yes | yes | yes |
| SDK 8 only | yes | yes | yes | **no**: SDK 8 can't build net10.0 |
| runtime 8 only, no SDK at all | **no**: *No .NET SDKs were found* | **no**, same error | yes | no |

A `global.json` that pins an 8.0.x SDK is the one case where SDK 10 isn't
allowed to build. That repository then needs SDK 8: `dvm install 8.0`.

### Which command for which need

| You want to | Run |
|---|---|
| Build and run net10.0 projects | `dvm install 10.0` (newest SDK, with its runtime) |
| Also run and test net8.0 projects | `dvm install runtime 8.0` (newest 8.0 runtime, no SDK) |
| Build a repository whose `global.json` pins SDK 8 | `dvm install 8.0` or the exact version, e.g. `dvm install 8.0.428` |
| Use one exact older runtime (to reproduce a bug, or match a server) | `dvm list 8.0` shows them all, then `dvm install runtime 8.0.22` |
| Only run apps that are already built (like a server) | `dvm install runtime 10.0`, no SDK |

## How it works

### What's in the dotnet folder

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
| `dvm list` | 1. Looks for .NET outside the dotnet folder (asks once per folder, see [Taking over](#taking-over-net-in-other-folders)). 2. Reads Microsoft's release list (from the cache if it's less than an hour old). 3. Reads what's in the dotnet folder, and Windows' list of installed programs to see who installed each SDK and runtime. 4. Prints the table. 5. Reminds you of anything left to do (old installs, system PATH, `DOTNET_ROOT`). | never |
| `dvm install 10.0.404` | 1. Checks the version against the release list. 2. Downloads Microsoft's `dotnet-install.ps1` (refreshed daily). 3. Shows one UAC prompt and runs `dotnet-install.ps1 -Version 10.0.404 -InstallDir "C:\Program Files\dotnet" -NoPath` in a hidden elevated copy of dvm; its output appears in your window. 4. In the same elevated step, sets the system PATH and the install location in the registry if they're missing. 5. Checks what `dotnet` new terminals will find. | one prompt, for steps 3 and 4 |
| `dvm install runtime 8.0` | The same, but step 3 runs `-Runtime aspnetcore -Version 8.0.34` and then `-Runtime windowsdesktop -Version 8.0.34`. Then adds `8.0.34` to `%APPDATA%\dvm\runtimes`. | one prompt |
| `dvm uninstall 10.0.404` | 1. Finds out who installed the SDK. 2. dvm's own SDK: works out which folders belong only to it (next section), shows them, asks, and deletes exactly those in the elevated copy (it refuses anything outside the dotnet folder). Windows installer: runs the registered uninstaller. Visual Studio: removes nothing and points you to the Visual Studio Installer. | one prompt |
| `dvm uninstall runtime 10.0.11` | 1. Refuses if an installed SDK needs that runtime. 2. Runs the runtime installer's uninstaller, or tells you which program it came with, or shows the folders, asks and deletes them. 3. Removes the version from `%APPDATA%\dvm\runtimes`. | one prompt |
| `dvm init` | Asks about every .NET install outside the dotnet folder again, sets the system PATH and install location, and checks your PATH. | one prompt, if something is missing |

Run `dvm` in a normal terminal. If you decline the UAC prompt, dvm says so;
you can then run the same command in a terminal opened with **Run as
administrator**, where no prompt is needed.

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

## Making dvm's dotnet the default

`C:\Program Files\dotnet` is the folder the official installers and Visual
Studio use, and the one Windows and built apps look in by default. If
`dotnet.exe` exists there and something is missing, dvm also:

| Setting | Why |
|---|---|
| puts `C:\Program Files\dotnet\` first in the **system PATH** | the `dotnet` command in every terminal |
| sets `HKLM\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\<arch>\InstallLocation` | where built apps and IDEs look for .NET |

The installers normally set both already. dvm edits the PATH in the
registry directly, so entries like `%SystemRoot%\system32` stay as they are.

## SDKs and runtimes that are already installed

Everything already in `C:\Program Files\dotnet` shows up with ✔ right away.
dvm checks Windows' list of installed programs to see who installed each SDK
and runtime:

| Installed by | Shown as | `dvm uninstall` |
|---|---|---|
| dvm | `✔ 10.0.404` | deletes its folders (previous section) |
| Official installer / winget | `✔ 10.0.404 ... (Windows installer)` | runs its registered uninstaller, so it also leaves *Apps & features* |
| Visual Studio | `✔ 8.0.416 ... (Visual Studio)` | removes nothing and points you to the **Visual Studio Installer** (*Modify → Individual components*), because Visual Studio puts back SDKs it needs |

Runtimes from an installer show `(... Windows installer)` too, and there are
two cases:

| The runtime came from | `dvm uninstall runtime` |
|---|---|
| the standalone runtime installer or the Hosting Bundle | runs its uninstaller(s) |
| inside an SDK installer or Visual Studio | removes nothing and tells you to remove that program instead, because the runtime has no uninstaller of its own |

## Taking over .NET in other folders

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

## Uninstalling dvm

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\dvm", "$env:LOCALAPPDATA\dvm", "$env:APPDATA\dvm"
```

Then remove `%LOCALAPPDATA%\Programs\dvm` from your user PATH (or the alias
from your profile, or the AutoRun value). The installed SDKs and runtimes
stay where they are.

## Troubleshooting

- **`dvm` is not recognized.** Open a new terminal after `install.ps1`;
  running terminals keep the PATH they started with. For the alias, check
  that your profile runs (`Get-ExecutionPolicy` must not be `Restricted`) and
  that `Get-Command dvm` points to `dvm.cmd`.
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

## Checklist for the first test on a real Windows machine

Microsoft's release data and the listing logic are covered by the shared
tests. These Windows-only parts can only be checked on Windows:

1. `install.ps1` → new terminal → `dvm version` works in PowerShell **and**
   cmd.
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
9. The PowerShell alias (`Set-Alias dvm C:\...\windows\dvm.cmd` in
   `$PROFILE`) and the cmd macro both start dvm from the clone, and
   `dvm install` from the alias still gets its UAC prompt.
