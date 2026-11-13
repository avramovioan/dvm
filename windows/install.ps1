# Installs dvm for the current user and puts it on the user PATH.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\install.ps1 [-NoInit]
#
# Files go to %LOCALAPPDATA%\Programs\dvm:
#   dvm.cmd        the global `dvm` command (works in PowerShell and cmd)
#   lib\dvm.ps1    the script itself; kept in a subfolder so PowerShell runs
#                  dvm.cmd and is never blocked by the execution policy
# Afterwards it runs `dvm init` unless -NoInit is given.

param([switch]$NoInit)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'Programs\dvm'

New-Item -ItemType Directory -Force -Path (Join-Path $dest 'lib') | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'dvm.ps1') -Destination (Join-Path $dest 'lib\dvm.ps1') -Force
Copy-Item -LiteralPath (Join-Path $src 'dvm.cmd') -Destination (Join-Path $dest 'dvm.cmd') -Force
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

Write-Host "$([char]0x2714) dvm installed to $dest"
Write-Host 'Open a new terminal to use `dvm` there.'

if (-not $NoInit) {
    Write-Host ''
    & (Join-Path $dest 'dvm.cmd') init
}
