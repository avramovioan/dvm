# dvm on Linux and macOS

dvm is one bash script. It works in bash, zsh and fish terminals, and needs
nothing beyond what every Linux distribution and macOS already has (`curl`
or `wget`, `grep`, `awk`, `sed`, `tar`).

1. [Install](#install), either with [one command](#a-one-command-recommended) or [from a git clone](#b-from-a-git-clone)
2. [Update dvm](#updating-dvm)
3. [Use dvm with .NET versions](#using-dvm)
4. [Remove dvm entirely](#removing-dvm-entirely)
5. [How it works](#how-it-works): what the installer does, and where things are stored

## Install

Pick **one** of the two ways.

### A. One command (recommended)

**Step 1.** Install dvm:

```bash
curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash
```

This downloads the latest release of dvm and puts it in `/usr/local/bin`. If
that folder isn't writable for you, it asks for your sudo password. Without
`curl`, use `wget -qO- <the same URL> | bash`.

**Step 2.** Check that it works, in the same terminal:

```bash
dvm --version
```

It prints `dvm` and the version, e.g. `dvm 1.1.1`. You don't need an alias
or any change to your shell profile: `/usr/local/bin` is already on the PATH
on Linux and macOS.

That's it: you have the `dvm` command. Go on with [Using dvm](#using-dvm).

> **No sudo?** Install into your home folder instead:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash -s -- --user
> ```
> This puts dvm in `~/.local/bin`. If `dvm --version` then says
> `command not found`, that folder isn't on your PATH yet; the installer
> prints a warning in that case. Add this line to `~/.bashrc` (bash) or
> `~/.zshrc` (zsh), then open a new terminal:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

### B. From a git clone

Use this to run dvm straight from the source code, e.g. to read or change
it. You make the `dvm` command yourself, with an alias.

**Step 1.** Clone the repository. The examples below use `~/src/dvm`:

```bash
git clone https://github.com/avramovioan/dvm.git ~/src/dvm
```

**Step 2.** Add a `dvm` alias for your shell. If you cloned to another
folder, change the path.

| Shell | Run once |
|---|---|
| bash (the Linux default) | `echo 'alias dvm="$HOME/src/dvm/unix/dvm"' >> ~/.bashrc && source ~/.bashrc` |
| zsh (the macOS default) | `echo 'alias dvm="$HOME/src/dvm/unix/dvm"' >> ~/.zshrc && source ~/.zshrc` |
| fish | `alias --save dvm ~/src/dvm/unix/dvm` |

**Step 3.** Check that it works:

```bash
dvm --version
```

It prints `dvm` and the version from the clone's `VERSION` file.
`type dvm` shows that `dvm` is an alias for `~/src/dvm/unix/dvm`.

That's it. Go on with [Using dvm](#using-dvm).

> An alias only exists in your interactive terminal. If scripts or other
> programs need to call `dvm` too, use a symlink instead of the alias:
> `ln -s ~/src/dvm/unix/dvm ~/.local/bin/dvm` (with `~/.local/bin` on your
> PATH, see the note under A).

## Updating dvm

**If you installed with the one command (A):**

```bash
dvm update
```

It checks the latest release on GitHub. If that's newer than your dvm, it
installs it in place (asking for sudo if dvm is in `/usr/local/bin`):

```
$ dvm update
Checking for a newer dvm ...
Updating dvm 1.1.0 to 1.1.1 ...
Downloading dvm (v1.1.1) from https://raw.githubusercontent.com/avramovioan/dvm ...
✔ dvm 1.1.1 installed to /usr/local/bin/dvm (was 1.1.0, from avramovioan/dvm@v1.1.1)
```

If you're already up to date, it says so and changes nothing.

**If you use a git clone (B):** pull the latest code. The alias then runs
the new version right away:

```bash
git -C ~/src/dvm pull
```

(`dvm update` notices that it runs from a clone and tells you the same.)

## Using dvm

### First steps

```bash
dvm list            # the .NET versions, with a ✔ for what you have
dvm install lts     # install the newest SDK
```

If .NET is already installed somewhere else on this machine (for example
Ubuntu's `apt` packages), run `dvm init` once. dvm offers to install the
same versions as Microsoft's builds and tells you how to remove the old
install ([details](#taking-over-an-existing-net-install)).

dvm asks for your sudo password when it writes to the .NET folder
(`/usr/share/dotnet` on Linux, `/usr/local/share/dotnet` on macOS). Run it as
yourself, not with `sudo dvm`.

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
| `dvm init` | take over .NET installed elsewhere, and make dvm's folder the system default `dotnet` |
| `dvm update` | update dvm itself |
| `dvm --version` | print dvm's version |

`-y` / `--yes` answers yes to every question, for scripts.

### SDKs and runtimes

The SDK builds your code. The runtime runs it. Every SDK comes with exactly
one runtime, the one of its own version, so SDK 10.0.404 brings
runtime 10.0.15. A `net8.0` app needs an 8.0.x runtime and runs on the newest
8.0.x you have. It never runs on 10.0. You don't switch versions: the
`dotnet` command picks the right runtime per app, and the newest SDK unless
a `global.json` pins one.

**What works with what you have**, for a `net8.0` project and a `net10.0`
project:

| Installed | `dotnet build` net8.0 | `dotnet run` / `test` net8.0 | `dotnet MyApp.dll` (built net8.0 app) | anything with net10.0 |
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
dvm. To remove single versions:

```bash
dvm list                          # see what's installed
dvm uninstall 10.0.404            # an SDK
dvm uninstall runtime 8.0.34      # a runtime
```

Or remove the whole .NET folder and the system links dvm created. This also
removes .NET that other installers put there:

```bash
sudo rm -rf /usr/share/dotnet /usr/local/bin/dotnet /etc/dotnet                          # Linux
sudo rm -rf /usr/local/share/dotnet /usr/local/bin/dotnet /etc/dotnet /etc/paths.d/dotnet # macOS
```

**Step 2: remove the `dvm` command.**

| You installed with | Run |
|---|---|
| the one command (A) | `sudo rm /usr/local/bin/dvm` (or `rm ~/.local/bin/dvm` if you used `--user`) |
| a git clone (B) | delete the `alias dvm=...` line from `~/.bashrc` or `~/.zshrc` (fish: `rm ~/.config/fish/functions/dvm.fish`), remove a symlink if you made one (`rm ~/.local/bin/dvm`), then delete the clone: `rm -rf ~/src/dvm` |

**Step 3: remove dvm's own files** (cached downloads, and what it
remembers):

```bash
rm -rf ~/.cache/dvm ~/.config/dvm
```

Open a new terminal. `dvm --version` now says `command not found`.

## How it works

### Where everything is

| What | Linux | macOS |
|---|---|---|
| The `dvm` command (A) | `/usr/local/bin/dvm`, or `~/.local/bin/dvm` with `--user` | same |
| The .NET folder dvm manages | `/usr/share/dotnet` | `/usr/local/share/dotnet` |
| System links to that folder | `/usr/local/bin/dotnet`, `/etc/dotnet/install_location*` | the same, plus `/etc/paths.d/dotnet` |
| Downloads and release data | `~/.cache/dvm` | same |
| What dvm remembers | `~/.config/dvm` | same |

### What `install.sh` does

| Step | Detail |
|---|---|
| 1. Get `dvm` | **Run from a clone:** it uses the clone's `unix/dvm`. **Anywhere else** (piped, or a downloaded copy of `install.sh`): it downloads `unix/dvm` from GitHub, from the **latest release**, or from `master` while there is no release yet. It checks that what arrived really is the dvm script. |
| 2. Write the version | Writes the version from the repository's `VERSION` file into the copy, so `dvm --version` reports it. |
| 3. Install it | Copies it to **`/usr/local/bin/dvm`**, asking for your sudo password if that folder isn't writable (`~/.local/bin/dvm` with `--user`, no sudo). |
| 4. Check your PATH | Warns you if the folder isn't on your PATH, or if another `dvm` comes first. |

That's all it does. It doesn't touch .NET. `dvm update` runs the installer
of the newest release in the same way.

| Option | Environment variable | Effect |
|---|---|---|
| `--user` | | Install to `~/.local/bin/dvm` instead, without sudo. |
| `--dir <folder>` | | Install to `<folder>/dvm`. `dvm update` uses this to replace itself. |
| `--ref <tag or branch>` | `DVM_REF=<tag or branch>` | Install that version instead of the latest release, e.g. `--ref v1.1.0`. |

With the one-liner, options go after `bash -s --`, for example
`curl -fsSL https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh | bash -s -- --user --ref v1.1.0`.

To read the installer before you run it, download it first:

```bash
curl -fsSLO https://raw.githubusercontent.com/avramovioan/dvm/master/unix/install.sh
less install.sh
sh install.sh            # or: sh install.sh --user
```

### What's in the .NET folder

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
| `dvm list` | 1. Looks for .NET outside the .NET folder (asks once per folder, see [Taking over](#taking-over-an-existing-net-install)). 2. Reads Microsoft's release list (from the cache if it's less than an hour old). 3. Reads what's in the .NET folder and who installed it (`dpkg -S`, `rpm -qf`, or `pkgutil` on macOS). 4. Prints the table. 5. Reminds you of anything left to do (old installs, system default, PATH). | never |
| `dvm install 10.0.404` | 1. Checks the version against the release list. 2. Downloads Microsoft's `dotnet-install.sh` (refreshed daily). 3. Runs `bash dotnet-install.sh --version 10.0.404 --install-dir /usr/share/dotnet --no-path`. 4. Makes the folder the system default if it isn't yet. 5. Checks that your shell finds dvm's `dotnet`. | for steps 3 and 4 |
| `dvm install runtime 8.0` | The same, with `--runtime aspnetcore --version 8.0.34`. Then adds `8.0.34` to `~/.config/dvm/runtimes`. | for steps 3 and 4 |
| `dvm uninstall 10.0.404` | 1. Works out which folders belong only to that SDK (see [What `dvm uninstall` removes](#what-dvm-uninstall-removes)). 2. Shows them and asks. 3. Runs `rm -rf` on exactly those folders, or `apt remove` / `dnf remove` if a package installed the SDK. | for step 3 |
| `dvm uninstall runtime 10.0.11` | 1. Refuses if an installed SDK needs that runtime. 2. Shows the runtime's folders and asks. 3. Deletes them (or removes the package), and removes the version from `~/.config/dvm/runtimes`. | for step 3 |
| `dvm init` | Asks about every .NET install outside the .NET folder again, makes the folder the system default, and checks your PATH. | for the system default |
| `dvm update` | Downloads the `VERSION` file of the latest release. If that's newer, downloads that release's `install.sh` and runs it with `--ref v<version> --dir <folder of your dvm>`. | if dvm is in `/usr/local/bin` |

sudo is used only when the target isn't writable for you. dvm runs as you
and calls sudo for exactly the steps above. If sudo is missing or you
decline, it prints the command for you to run.

When you install a version that is older than what you already have, dvm
adds `--skip-non-versioned-files`. Without it, Microsoft's script would
replace the `dotnet` command with the older one.

### What `dvm install` adds

Microsoft ships every SDK as one package that contains its runtime, so dvm
always downloads the whole package. Microsoft's script then only adds the
versioned folders that aren't there yet. Nothing that's already installed is
overwritten.

| You run | Downloads | Adds to the .NET folder |
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

`dvm list` labels every installed runtime: `comes with SDK 10.0.404`,
`runtime only` (installed with `dvm install runtime`, or no installed SDK
came with it), or the installer that owns it (`apt: ...`,
`macOS installer`).

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

### Making dvm's dotnet the default

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

### Taking over an existing .NET install

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
| dvm, or `dotnet-install.sh` into this folder | `✔ 10.0.404` | deletes the folders (see [What `dvm uninstall` removes](#what-dvm-uninstall-removes)) |
| macOS installer (`.pkg`) or Homebrew cask `dotnet-sdk` | `✔ ... (macOS installer)` | deletes the folders and forgets the installer receipts (`pkgutil --forget`) |
| Microsoft's apt/dnf feed | `✔ ... (apt: <package>)` | `apt remove` / `dnf remove` of the package. Removing a runtime package also removes the SDK packages that depend on it; apt lists them and asks first. |

### Troubleshooting

- **The one-liner says `could not download`.** Check that
  `https://github.com/avramovioan/dvm` opens in a browser. Behind a proxy, set
  `https_proxy`; `curl` uses it.
- **`dvm: command not found`.** Check `type dvm`. After `--user` or a
  symlink, `~/.local/bin` has to be on your PATH (see the note under
  [A](#a-one-command-recommended)). After adding an alias, run
  `source ~/.bashrc` / `source ~/.zshrc` or open a new terminal.
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
  passes on bash 3.2, and CI runs it on macOS. Detecting what Microsoft's
  `.pkg` installer installed relies on assumed receipt names:
  `com.microsoft.dotnet.dev.<version>...` for SDKs, and names containing
  `.<version>.` for runtimes (`pkgutil --pkgs | grep dotnet` shows them). If
  such SDKs or runtimes show up without `(macOS installer)`, adjust the
  names in `sdk_owner_map` and `runtime_receipts`.
