# dvm on Linux and macOS

On Linux and macOS, dvm is one bash script, **`unix/dvm`**, and
**`unix/install.sh`** puts it on your PATH. The script runs on bash 3.2+ (the
version macOS ships), so it works in bash, zsh and fish terminals alike. It
needs nothing beyond what every Linux distribution and macOS already has:
`curl` or `wget`, `grep`, `awk`, `sed`, `tar`.

| | Linux | macOS |
|---|---|---|
| dotnet folder dvm manages | `/usr/share/dotnet` | `/usr/local/share/dotnet` |
| Where `install.sh` puts `dvm` | `/usr/local/bin/dvm` (or `~/.local/bin/dvm` with `--user`) | same |
| Downloads and release data | `~/.cache/dvm` | same |
| What dvm remembers | `~/.config/dvm` | same |

## Install

**One command, no git clone needed:**

```bash
curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash
```

Without sudo, into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash -s -- --user
```

No `curl`? Use `wget -qO- https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash`.

**To read the installer before running it**, download it first:

```bash
curl -fsSLO https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh
less install.sh
sh install.sh            # or: sh install.sh --user
```

**From a clone:**

```bash
git clone https://github.com/avramovioan/dvm.git
./dvm/unix/install.sh
```

### What `install.sh` does

| Step | Detail |
|---|---|
| 1. Get `dvm` | **Run from a clone:** it uses the clone's `unix/dvm`. **Anywhere else** (piped, or a downloaded copy of `install.sh`): it downloads `unix/dvm` from GitHub, from the **latest release**, or from `master` while there is no release yet. It checks that what arrived really is the dvm script. |
| 2. Write the version | Writes the version from the repository's `VERSION` file into the copy, so `dvm version` reports it. |
| 3. Install it | Copies it to **`/usr/local/bin/dvm`**, asking for your sudo password if that folder isn't writable (`~/.local/bin/dvm` with `--user`, no sudo). |
| 4. Check your PATH | Tells you if the folder isn't on your PATH, or if another `dvm` comes first. |

That's all it does: you end up with the `dvm` command, and .NET isn't
touched. Then run `dvm list` to see the versions, `dvm install lts` to
install the newest SDK, or `dvm init` to take over a .NET install you
already have.

### Updating dvm

```bash
dvm update
```

It checks the latest release on GitHub. If that's newer than your dvm, it
runs that release's `install.sh` into the folder your dvm is in (asking for
sudo if that's `/usr/local/bin`):

```
$ dvm update
Checking for a newer dvm ...
Updating dvm 1.1.0 to 1.2.0 ...
Downloading dvm (v1.2.0) from https://raw.githubusercontent.com/avramovioan/dvm ...
✔ dvm 1.2.0 installed to /usr/local/bin/dvm (was 1.1.0, from avramovioan/dvm@v1.2.0)
```

If you run dvm from a git clone (alias or symlink), `dvm update` tells you to
`git pull` instead. Running the install command again does the same as
`dvm update`.

| Option | Environment variable | Effect |
|---|---|---|
| `--user` | | Install to `~/.local/bin/dvm` instead, without sudo. |
| `--dir <folder>` | | Install to `<folder>/dvm`. `dvm update` uses this to replace itself. |
| `--ref <tag or branch>` | `DVM_REF=<tag or branch>` | Install that version instead of the latest release, e.g. `--ref v1.1.0`. |

With the one-liner, options go after `bash -s --`, for example
`curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash -s -- --user --ref v1.1.0`.

`/usr/local/bin` is on the PATH by default on Linux and on macOS (through
`/etc/paths`), so the default install needs no setup. Run `hash -r` or open a
new terminal and `dvm` works.

## Making the `dvm` command work in your terminal

There are three ways to get a `dvm` command. They all run the same script.

| Way | Command | Updates with `git pull` | Works in scripts and other programs | Needs sudo |
|---|---|---|---|---|
| **Copy** (recommended) | the one-liner above, or `./dvm/unix/install.sh` | no: `dvm update` | yes | only for `/usr/local/bin` |
| **Symlink** to the clone | `ln -s "$PWD/dvm/unix/dvm" ~/.local/bin/dvm` | yes | yes | no |
| **Alias** in your shell profile | see below | yes | no, only in your interactive terminal | no |

The copy doesn't need a clone at all. The symlink and the
alias run the script inside your clone, so they always run the version you
last pulled.

### Alias

Use the full path to `unix/dvm` in your clone (here `~/src/dvm`).

**bash** (the Linux default): add this line to `~/.bashrc`:
```bash
alias dvm="$HOME/src/dvm/unix/dvm"
```

**zsh** (the macOS default since Catalina): add the same line to `~/.zshrc`:
```zsh
alias dvm="$HOME/src/dvm/unix/dvm"
```

**fish**: run once, and fish saves it for you:
```fish
alias --save dvm ~/src/dvm/unix/dvm
```

Then `source ~/.bashrc` / `source ~/.zshrc`, or open a new terminal, and check
with `type dvm`. The script must be executable (`chmod +x unix/dvm`); git
keeps that bit, but a ZIP download may not.

### `~/.local/bin` on your PATH

The symlink and `install.sh --user` use `~/.local/bin`. Ubuntu, Debian and
Fedora put it on the PATH automatically once the folder exists (after a new
login). Otherwise add this line to `~/.bashrc` or `~/.zshrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

## SDKs and runtimes, in practice

The SDK builds your code. The runtime runs it. Every SDK comes with exactly
one runtime, the one of its own version, so SDK 10.0.404 brings
runtime 10.0.15. A `net8.0` app needs an 8.0.x runtime and runs on the newest
8.0.x you have. It never runs on 10.0.

### What works with what you have

For a `net8.0` project and a `net10.0` project:

| Installed in `/usr/share/dotnet` | `dotnet build` net8.0 | `dotnet run` / `test` net8.0 | `dotnet MyApp.dll` (built net8.0 app) | anything with net10.0 |
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

Everything lives side by side in one folder, `/usr/share/dotnet` on Linux
(`/usr/local/share/dotnet` on macOS). The `dotnet` command picks the SDK and
runtime per project from there.

| Folder | What it is | Comes with |
|---|---|---|
| `dotnet` | the `dotnet` command | every package; dvm keeps the newest one |
| `sdk/10.0.404` | an SDK | the SDK package |
| `shared/Microsoft.NETCore.App/10.0.15` | the base .NET runtime | an SDK package or a runtime package |
| `shared/Microsoft.AspNetCore.App/10.0.15` | the ASP.NET Core runtime | an SDK package or a runtime package |
| `host/fxr/10.0.15` | the part of `dotnet` that picks SDKs and runtimes; the newest one is used | an SDK package or a runtime package |
| `packs/Microsoft.NETCore.App.Ref/10.0.15`, ... | reference packs to build against | the SDK package |
| `templates/10.0.15` | the `dotnet new` templates | the SDK package |
| `sdk-manifests/10.0.400` | workload manifests of one feature band | the SDK package |

### What each command does

| Command | Steps | sudo |
|---|---|---|
| `dvm list` | 1. Looks for .NET outside the dotnet folder (asks once per folder, see [Taking over](#taking-over-an-existing-net-install)). 2. Reads Microsoft's release list (from the cache if it's less than an hour old). 3. Reads what's in the dotnet folder and who installed it (`dpkg -S`, `rpm -qf`, or `pkgutil` on macOS). 4. Prints the table. 5. Reminds you of anything left to do (old installs, system default, PATH). | never |
| `dvm install 10.0.404` | 1. Checks the version against the release list. 2. Downloads Microsoft's `dotnet-install.sh` (refreshed daily). 3. Runs `bash dotnet-install.sh --version 10.0.404 --install-dir /usr/share/dotnet --no-path`. 4. Makes the folder the system default if it isn't yet. 5. Checks that your shell finds dvm's `dotnet`. | for steps 3 and 4 |
| `dvm install runtime 8.0` | The same, with `--runtime aspnetcore --version 8.0.34`. Then adds `8.0.34` to `~/.config/dvm/runtimes`. | for steps 3 and 4 |
| `dvm uninstall 10.0.404` | 1. Works out which folders belong only to that SDK (next section). 2. Shows them and asks. 3. Runs `rm -rf` on exactly those folders, or `apt remove` / `dnf remove` if a package installed the SDK. | for step 3 |
| `dvm uninstall runtime 10.0.11` | 1. Refuses if an installed SDK needs that runtime. 2. Shows the runtime's folders and asks. 3. Deletes them (or removes the package), and removes the version from `~/.config/dvm/runtimes`. | for step 3 |
| `dvm init` | Asks about every .NET install outside the dotnet folder again, makes the folder the system default, and checks your PATH. | for the system default |

sudo is used only when the target isn't writable for you. Don't run
`sudo dvm ...` yourself: dvm runs as you and calls sudo for exactly the
steps above. If sudo is missing or you decline, it prints the command for
you to run.

When you install a version that is older than what you already have, dvm
adds `--skip-non-versioned-files`. Without it, Microsoft's script would
replace the `dotnet` command with the older one.

### What `dvm install` adds

Microsoft ships every SDK as one package that contains its runtime, so dvm
always downloads the whole package. Microsoft's script then only adds the
versioned folders that aren't there yet. Nothing that's already installed is
overwritten.

| You run | Downloads | Adds to the dotnet folder |
|---|---|---|
| `dvm install 10.0.404` (nothing installed yet) | SDK package 10.0.404 | `sdk/10.0.404` and runtime 10.0.15 (`shared/*/10.0.15`, `host/fxr/10.0.15`), packs, templates, manifests |
| `dvm install 10.0.404` when runtime 10.0.15 is already there | SDK package 10.0.404 | only the SDK's own folders; 10.0.15 is already there |
| `dvm install 10.0.303` when runtime 10.0.15 is already there | SDK package 10.0.303 | the SDK **and runtime 10.0.11**: that's the exact version it comes with. `dvm uninstall runtime 10.0.11` can remove it afterwards. |
| `dvm install 10.0.404` again | nothing | nothing: *SDK 10.0.404 is already installed* |
| `dvm install runtime 8.0` | runtime package 8.0.34 (much smaller than an SDK) | `shared/Microsoft.NETCore.App/8.0.34`, `shared/Microsoft.AspNetCore.App/8.0.34`, `host/fxr/8.0.34`; no SDK |
| `dvm install runtime 10.0.15` when SDK 10.0.404 brought it | nothing | nothing. It is marked to keep: from now on it stays when you remove that SDK. |

### What `dvm uninstall` removes

An SDK runs on the runtime it came with **or any newer patch of the same
channel**. SDK 10.0.303 came with 10.0.11 but runs fine on 10.0.15. dvm uses
that rule so it never removes a runtime that an installed SDK needs.

Examples, with SDKs 10.0.404 (came with 10.0.15), 10.0.303 (came with 10.0.11,
which was removed) and 10.0.110 (came with 10.0.10) installed:

| You run | Removes | Keeps, and why |
|---|---|---|
| `dvm uninstall 10.0.110` | `sdk/10.0.110`, runtime 10.0.10 (`shared/*/10.0.10`, `host/fxr/10.0.10`), `packs/*/10.0.10`, `templates/10.0.10`, `sdk-manifests/10.0.100` | nothing else uses them |
| `dvm uninstall 10.0.404` | `sdk/10.0.404`, `packs/*/10.0.15`, `templates/10.0.15`, `sdk-manifests/10.0.400` | runtime 10.0.15: SDK 10.0.303 needs 10.0.11 or newer, and 10.0.15 is the only one |
| `dvm uninstall 8.0.428` after `dvm install runtime 8.0.34` | the SDK, its packs, templates and manifests | runtime 8.0.34: you installed it on its own |
| `dvm uninstall runtime 10.0.10` | `shared/*/10.0.10`, `host/fxr/10.0.10` | packs and templates belong to SDK 10.0.110, which now runs on 10.0.15 |
| `dvm uninstall runtime 10.0.15` | nothing; it stops with an error that names SDK 10.0.404 and 10.0.303 | no other installed runtime is new enough for them |

Two more rules:

- `packs`, `templates` and `sdk-manifests` stay while another SDK uses the
  same version.
- The newest `host/fxr` folder always stays, because the `dotnet` command
  uses it.

### Files dvm keeps for itself

| File | Content |
|---|---|
| `~/.cache/dvm/releases-index.json` | Microsoft's list of .NET channels (refreshed hourly) |
| `~/.cache/dvm/10.0.json` | all releases of one channel (refreshed hourly) |
| `~/.cache/dvm/10.0.sdks.tsv`, `10.0.runtimes.tsv`, `releases-index.tsv` | the same data in a form dvm reads quickly |
| `~/.cache/dvm/dotnet-install.sh` | Microsoft's install script (refreshed daily) |
| `~/.config/dvm/seen` | other .NET folders you already answered about |
| `~/.config/dvm/runtimes` | runtimes you installed with `dvm install runtime` |

Without a network, dvm uses the cached copies. `DVM_CACHE`, `DVM_STATE` and
the other variables in the [main README](../README.md#environment-variables)
change these places.

## Making dvm's dotnet the default

After the first install (and on `dvm init`), dvm makes its folder the system
default by creating:

| File | Why |
|---|---|
| `/usr/local/bin/dotnet` → `<folder>/dotnet` | The `dotnet` command in every shell. `/usr/local/bin` comes before `/usr/bin`, so this also wins over a distro `dotnet`. |
| `/etc/dotnet/install_location` and `install_location_<arch>` | Where built apps (apphost) and IDEs look for .NET. |
| `/etc/paths.d/dotnet` (macOS only) | The same entry Microsoft's macOS installer creates. |

You don't need `DOTNET_ROOT` or any line in your shell profile. If something
in your profile still points at another `dotnet`, dvm shows you the file and
line to delete.

## Taking over an existing .NET install

On the first run dvm looks for .NET outside its folder: everything on your
PATH, `DOTNET_ROOT`, `/etc/dotnet/install_location` and the usual places. If
it finds one, it asks once:

```
Found .NET outside dvm: /usr/lib/dotnet (installed with apt)
  SDK 10.0.115
  runtime 10.0.15
Install the same version(s) with dvm into /usr/share/dotnet? [Y/n]
```

If you say yes:

- **SDKs:** dvm installs Microsoft's build of each one. If Microsoft never
  released that exact version, it uses the newest build of the same feature
  band (e.g. `10.0.1xx`).
- **Runtimes:** for runtimes that none of those SDKs bring, such as an 8.0
  runtime next to SDK 10, it installs the newest one of each channel as a
  runtime on its own.
- **Afterwards:** it sets up the system links and prints the command that
  removes the old install.

Nothing is deleted for you. `dvm init` asks again at any time.

| Found | Typical folder | Removal command dvm prints |
|---|---|---|
| Ubuntu / Debian packages ¹ | `/usr/lib/dotnet` | `sudo apt remove <the exact packages>` |
| Fedora / RHEL packages ¹ | `/usr/lib64/dotnet` | `sudo dnf remove <packages>` |
| Snap | `/snap/dotnet-sdk/current` | `sudo snap remove dotnet-sdk` |
| Homebrew formula `dotnet` ¹ | `/opt/homebrew/opt/dotnet/libexec` | `brew uninstall dotnet` |
| `dotnet-install.sh` default | `~/.dotnet` | removes everything except `~/.dotnet/tools` (your global tools) |
| Any other folder | — | `rm -rf <folder>` |

¹ These are built from source by the distribution or Homebrew, not by
Microsoft. Some parts that Microsoft ships are only stubs in them. For
example, Ubuntu's `Microsoft.AspNetCore.Server.IIS.dll` is 9 KB instead of
127 KB and has no `IISServerOptions`, so ASP.NET Core code that compiles in
CI fails locally. Moving to Microsoft's build fixes that.

Some of these packages own `/etc/dotnet`, so removing them can remove dvm's
`install_location` files too. Run `dvm init` once more after the removal; it
puts them back.

SDKs and runtimes that are already in the standard folder are taken over as
they are:

| Installed by | Shown as | `dvm uninstall` |
|---|---|---|
| dvm, or `dotnet-install.sh` into this folder | `✔ 10.0.404` | deletes the folders (previous section) |
| macOS installer (`.pkg`) or Homebrew cask `dotnet-sdk` | `✔ ... (macOS installer)` | deletes the folders and forgets the installer receipts (`pkgutil --forget`) |
| Microsoft's apt/dnf feed | `✔ ... (apt: <package>)` | `apt remove` / `dnf remove` of the package. Removing a runtime package also removes the SDK packages that depend on it; apt lists them and asks first. |

## Uninstalling dvm

```bash
sudo rm /usr/local/bin/dvm        # or: rm ~/.local/bin/dvm, or remove your alias
rm -rf ~/.cache/dvm ~/.config/dvm
```

The installed SDKs and runtimes stay where they are. If you want them gone
too, remove them first with `dvm uninstall <version>` and
`dvm uninstall runtime <version>`.

## Troubleshooting

- **The one-liner says `could not download`.** Check that
  `https://github.com/avramovioan/dvm` opens in a browser. Behind a proxy, set
  `https_proxy`; `curl` uses it.
- **`dvm: command not found`.** Check `type dvm`. After `install.sh --user`
  or the symlink, `~/.local/bin` has to be on your PATH (see above). After
  adding an alias, open a new terminal.
- **`dotnet` still runs the old version.** Run `hash -r` or open a new
  terminal; your shell remembers where it found `dotnet` before. `dvm list`
  shows which `dotnet` your shell uses, and why, if it isn't dvm's.
- **The IDE uses another SDK.** IDEs started from the desktop don't read your
  shell profile, but they do read `/etc/dotnet/install_location`. Restart the
  IDE after `dvm init`.
- **Which SDK does a project use?** Run `dotnet --version` in the project
  folder. Pin it with `global.json` if needed.
- **"Framework 'Microsoft.NETCore.App', version '8.0.0' was not found".**
  The app targets a .NET version whose runtime isn't installed. Run
  `dvm install runtime 8.0` (with the version from the message).
- **"No .NET SDKs were found".** Only runtimes are installed. Install an SDK
  with `dvm install lts`.
- **macOS status.** dvm hasn't been tried on a real Mac yet. The test suite
  passes on bash 3.2, and CI runs it on macOS when the repository is on
  GitHub. Detecting what Microsoft's `.pkg` installer installed relies on
  assumed receipt names: `com.microsoft.dotnet.dev.<version>...` for SDKs,
  and names containing `.<version>.` for runtimes (`pkgutil --pkgs | grep dotnet`
  shows them). If such SDKs or runtimes show up without `(macOS installer)`,
  adjust the names in `sdk_owner_map` and `runtime_receipts`.
