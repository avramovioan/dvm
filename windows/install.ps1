# Installs dvm for the current user and puts it on the user PATH.
#
# Straight from GitHub, no clone needed (PowerShell):
#   irm https://raw.githubusercontent.com/avramovioan/dvm/master/windows/install.ps1 | iex
# From a clone, or a downloaded copy of this file:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 [-Ref <tag or branch>]
#
#   -Ref <ref>    install that release tag or branch  ($env:DVM_REF = 'v1.1.0' with irm | iex)
#
# It only installs the dvm command; it doesn't touch .NET.
# Next to a clone's dvm.ps1 and dvm.cmd it installs those files. Anywhere else
# it downloads them from GitHub: the latest release, or master while there is
# none. Either way it writes the version from the VERSION file into the copy.
# `dvm update` runs this script too.
#
# Files go to %LOCALAPPDATA%\Programs\dvm:
#   dvm.cmd        the global `dvm` command (works in PowerShell and cmd)
#   lib\dvm.ps1    the script itself; kept in a subfolder so PowerShell runs
#                  dvm.cmd and is never blocked by the execution policy
#
# With `irm | iex` this runs inside your PowerShell session, so it never calls
# `exit` and keeps its settings inside the function below.

param([string]$Ref = '')

function Install-Dvm([string]$Here, [string]$Ref) {
    $ErrorActionPreference = 'Stop'
    $isWin = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $repo = if ($env:DVM_REPO) { $env:DVM_REPO } else { 'avramovioan/dvm' }
    $baseUrl = if ($env:DVM_BASE_URL) { $env:DVM_BASE_URL } else { "https://raw.githubusercontent.com/$repo" }
    $latestUrl = if ($env:DVM_LATEST_URL) { $env:DVM_LATEST_URL } else { "https://github.com/$repo/releases/latest/download/VERSION" }
    $localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { throw 'LOCALAPPDATA is not set' }
    $dest = Join-Path (Join-Path $localData 'Programs') 'dvm'
    $lib = Join-Path $dest 'lib'
    $check = [string][char]0x2714
    $versionRe = '^\d+\.\d+\.\d+$'

    # file:// URLs are only used by the tests.
    function Save-Url([string]$Url, [string]$File) {
        if ($Url.StartsWith('file://')) { Copy-Item -LiteralPath ([Uri]$Url).LocalPath -Destination $File; return }
        $saved = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads slow on PowerShell 5.1
        try { Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing } finally { $global:ProgressPreference = $saved }
    }

    function Read-Version([string]$File) {
        if (-not (Test-Path -LiteralPath $File)) { return '' }
        "$(Get-Content -LiteralPath $File -TotalCount 1)".Trim()
    }

    function Get-InstalledVersion {
        if (-not (Test-Path -LiteralPath (Join-Path $lib 'dvm.ps1'))) { return '' }
        try {
            if ($isWin) { "$(& (Join-Path $dest 'dvm.cmd') version)" }
            else { "$(& (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $lib 'dvm.ps1') version)" }   # only the tests get here
        } catch { '' }
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvm-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $src = Join-Path $tmp 'src'
        New-Item -ItemType Directory -Path $src | Out-Null
        if ($Here -and (Test-Path -LiteralPath (Join-Path $Here 'dvm.ps1')) -and (Test-Path -LiteralPath (Join-Path $Here 'dvm.cmd'))) {
            foreach ($f in 'dvm.ps1', 'dvm.cmd') { Copy-Item -LiteralPath (Join-Path $Here $f) -Destination $src }
            $version = Read-Version (Join-Path (Split-Path -Parent $Here) 'VERSION')
            $from = $Here
        } else {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            } catch { }
            if (-not $Ref) {
                # The latest release carries the VERSION file; without a release, use master.
                $latest = ''
                try { Save-Url $latestUrl (Join-Path $tmp 'latest'); $latest = Read-Version (Join-Path $tmp 'latest') } catch { }
                $Ref = if ($latest -match $versionRe) { "v$latest" } else { 'master' }
            }
            if ($Ref -notmatch '^[A-Za-z0-9._/-]+$') { throw "not a tag or branch name: '$Ref'" }
            Write-Host "Downloading dvm ($Ref) from $baseUrl ..."
            foreach ($f in 'dvm.ps1', 'dvm.cmd') {
                try { Save-Url "$baseUrl/$Ref/windows/$f" (Join-Path $src $f) } catch { throw "could not download $baseUrl/$Ref/windows/$f" }
            }
            $version = ''
            try { Save-Url "$baseUrl/$Ref/VERSION" (Join-Path $tmp 'VERSION'); $version = Read-Version (Join-Path $tmp 'VERSION') } catch { }
            $from = "$repo@$Ref"
        }

        # Check the files, write the version into dvm.ps1 (older versions of dvm
        # already contain it), and give Windows what it expects: CRLF line
        # endings for cmd.exe, and a BOM so Windows PowerShell 5.1 reads the
        # script as UTF-8. Files from GitHub arrive with LF line endings.
        $out = Join-Path $tmp 'out'
        New-Item -ItemType Directory -Path $out | Out-Null
        foreach ($f in 'dvm.ps1', 'dvm.cmd') {
            $text = [IO.File]::ReadAllText((Join-Path $src $f), [Text.Encoding]::UTF8) -replace "`r?`n", "`r`n"
            $marker = if ($f -eq 'dvm.ps1') { '$DvmVersion =' } else { 'powershell.exe' }
            if (-not $text.Contains($marker)) { throw "$from/$f is not part of dvm" }
            $placeholder = "`$DvmVersion = '0.0.0-dev'"
            if ($f -eq 'dvm.ps1' -and $text.Contains($placeholder)) {
                if ($version -notmatch $versionRe) { throw "could not read the version from the VERSION file of $from" }
                $text = $text.Replace($placeholder, "`$DvmVersion = '$version'")
            }
            [IO.File]::WriteAllText((Join-Path $out $f), $text, (New-Object Text.UTF8Encoding ($f -eq 'dvm.ps1')))
        }

        $before = Get-InstalledVersion
        New-Item -ItemType Directory -Force -Path $lib | Out-Null
        Copy-Item -LiteralPath (Join-Path $out 'dvm.ps1') -Destination (Join-Path $lib 'dvm.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $out 'dvm.cmd') -Destination (Join-Path $dest 'dvm.cmd') -Force
        if ($isWin) {
            Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File   # drop the "downloaded from the internet" mark

            # Add the folder to the user PATH, editing the registry value directly so
            # entries such as %USERPROFILE%\... stay unexpanded.
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            try {
                $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $entries = @($raw -split ';' | Where-Object { $_ } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
                if ($entries -notcontains $dest.TrimEnd('\')) {
                    $new = if ($raw) { $raw.TrimEnd(';') + ";$dest" } else { $dest }
                    $key.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
                    [Environment]::SetEnvironmentVariable('DVM_PATH_REFRESH', '1', 'User')    # setting and clearing a variable
                    [Environment]::SetEnvironmentVariable('DVM_PATH_REFRESH', $null, 'User')  # broadcasts the change
                    Write-Host "Added $dest to your user PATH."
                }
            } finally { $key.Close() }
            if (@($env:Path -split ';') -notcontains $dest) { $env:Path = "$dest;$env:Path" }
        }
        $now = Get-InstalledVersion
        if (-not $now) { throw "the installed dvm in $dest doesn't start" }

        if ($before -and $before -ne $now) {
            Write-Host "$check $now installed to $dest (was $($before -replace '^dvm ', ''), from $from)"
        } else {
            Write-Host "$check $now installed to $dest (from $from)"
        }
        if (-not $before) {
            Write-Host ''
            Write-Host "Open a new terminal and run 'dvm list' to see the .NET versions, or 'dvm help' for all commands."
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$dvmRef = if ($Ref) { $Ref } else { "$env:DVM_REF" }
Install-Dvm -Here $PSScriptRoot -Ref $dvmRef
Remove-Item -Path Function:\Install-Dvm -ErrorAction SilentlyContinue
