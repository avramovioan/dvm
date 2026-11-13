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
# none. Run it again to update dvm.
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
    $apiUrl = if ($env:DVM_API_URL) { $env:DVM_API_URL } else { "https://api.github.com/repos/$repo/releases/latest" }
    $localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { throw 'LOCALAPPDATA is not set' }
    $dest = Join-Path (Join-Path $localData 'Programs') 'dvm'
    $check = [string][char]0x2714

    # file:// URLs are only used by the tests.
    function Save-Url([string]$Url, [string]$File) {
        if ($Url.StartsWith('file://')) { Copy-Item -LiteralPath ([Uri]$Url).LocalPath -Destination $File; return }
        $saved = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads slow on PowerShell 5.1
        try { Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing } finally { $global:ProgressPreference = $saved }
    }

    $tmp = $null
    try {
        if ($Here -and (Test-Path -LiteralPath (Join-Path $Here 'dvm.ps1')) -and (Test-Path -LiteralPath (Join-Path $Here 'dvm.cmd'))) {
            $src = $Here
            $from = $Here
        } else {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            } catch { }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvm-install-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp | Out-Null
            if (-not $Ref) {
                try {
                    Save-Url $apiUrl (Join-Path $tmp 'latest.json')
                    $Ref = "$((Get-Content -LiteralPath (Join-Path $tmp 'latest.json') -Raw | ConvertFrom-Json).tag_name)"
                } catch { $Ref = '' }   # no release yet, or GitHub's API is not reachable
                if (-not $Ref) { $Ref = 'master' }
            }
            if ($Ref -notmatch '^[A-Za-z0-9._/-]+$') { throw "not a tag or branch name: '$Ref'" }
            Write-Host "Downloading dvm ($Ref) from $baseUrl ..."
            foreach ($f in 'dvm.ps1', 'dvm.cmd') {
                $file = Join-Path $tmp $f
                try { Save-Url "$baseUrl/$Ref/windows/$f" $file } catch { throw "could not download $baseUrl/$Ref/windows/$f" }
                # GitHub serves the files with LF line endings: cmd.exe wants CRLF,
                # and Windows PowerShell 5.1 needs a BOM to read the script as UTF-8.
                $text = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) -replace "`r?`n", "`r`n"
                $marker = if ($f -eq 'dvm.ps1') { '$DvmVersion =' } else { 'powershell.exe' }
                if (-not $text.Contains($marker)) { throw "$baseUrl/$Ref/windows/$f is not part of dvm" }
                [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding ($f -eq 'dvm.ps1')))
            }
            $src = $tmp
            $from = "$repo@$Ref"
        }

        $lib = Join-Path $dest 'lib'
        New-Item -ItemType Directory -Force -Path $lib | Out-Null
        Copy-Item -LiteralPath (Join-Path $src 'dvm.ps1') -Destination (Join-Path $lib 'dvm.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $src 'dvm.cmd') -Destination (Join-Path $dest 'dvm.cmd') -Force
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
            $version = & (Join-Path $dest 'dvm.cmd') version
        } else {
            # Not Windows: only the tests get here. Check the installed script runs.
            $version = & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $lib 'dvm.ps1') version
        }

        Write-Host "$check $version installed to $dest (from $from)"
        Write-Host ''
        Write-Host "Open a new terminal and run 'dvm list' to see the .NET versions, or 'dvm help' for all commands."
    } finally {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

$dvmRef = if ($Ref) { $Ref } else { "$env:DVM_REF" }
Install-Dvm -Here $PSScriptRoot -Ref $dvmRef
Remove-Item -Path Function:\Install-Dvm -ErrorAction SilentlyContinue
