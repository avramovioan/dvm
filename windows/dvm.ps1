# dvm - .NET SDK and runtime version manager for Windows.
#
# Manages the standard .NET folder (C:\Program Files\dotnet), the same one
# Visual Studio and the official installers use, so SDKs and runtimes already
# installed there are picked up as they are. Installs Microsoft's builds side by side
# with Microsoft's dotnet-install.ps1; the dotnet host then picks the right
# SDK/runtime per project.
#
# Runs on Windows PowerShell 5.1 (built into Windows) and PowerShell 7.
# Start it through dvm.cmd. It asks for administrator rights (UAC) only for
# the steps that write to C:\Program Files\dotnet.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$DvmVersion = '1.1.0'

function EnvOr([string]$Name, [string]$Fallback) {
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v) { $v } else { $Fallback }
}

$IsWin = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$MetaUrl = EnvOr 'DVM_META_URL' 'https://builds.dotnet.microsoft.com/dotnet/release-metadata'
$InstallScriptUrl = 'https://dot.net/v1/dotnet-install.ps1'
$MetaTtl = [TimeSpan]::FromMinutes(60)
$ScriptTtl = [TimeSpan]::FromDays(1)
$DefaultRoot = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'dotnet' } else { '' }
$Root = (EnvOr 'DVM_ROOT' $DefaultRoot).TrimEnd('\', '/')
$Integrate = $IsWin -and ($Root -eq $DefaultRoot)   # PATH/registry only for the standard folder
$LocalData = EnvOr 'LOCALAPPDATA' ([IO.Path]::GetTempPath())
$Cache = EnvOr 'DVM_CACHE' (Join-Path $LocalData 'dvm\cache')
$State = EnvOr 'DVM_STATE' (Join-Path (EnvOr 'APPDATA' $LocalData) 'dvm')
$Offline = [bool]$env:DVM_OFFLINE
$NoDetect = [bool]$env:DVM_NO_DETECT
$DotnetExe = if ($IsWin) { 'dotnet.exe' } else { 'dotnet' }
$StableRe = '^\d+\.\d+\.\d+$'
# What 'dvm install runtime' installs, and what every SDK brings.
$RuntimeFrameworks = if ($IsWin) { @('Microsoft.NETCore.App', 'Microsoft.AspNetCore.App', 'Microsoft.WindowsDesktop.App') }
                     else { @('Microsoft.NETCore.App', 'Microsoft.AspNetCore.App') }
$ChannelRe = '^\d+\.\d+$'

$script:AssumeYes = $false
$script:ElevatedLog = $null
$script:PathChecked = $false
$script:Index = @()
$script:Remind = @()

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$UseColor = (-not $env:NO_COLOR) -and (-not [Console]::IsOutputRedirected)
$Check = [string][char]0x2714
$Dot = [string][char]0x00B7

# ------------------------------------------------------------------ helpers

function Out-Line([string]$Text = '', [string]$Color = '') {
    if ($UseColor -and $Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

# "    <check mark> text" / "      text"
function Out-Mark([bool]$Ok, [string]$Rest) {
    Write-Host '    ' -NoNewline
    if ($Ok -and $UseColor) { Write-Host $Check -ForegroundColor Green -NoNewline }
    elseif ($Ok) { Write-Host $Check -NoNewline }
    else { Write-Host ' ' -NoNewline }
    Write-Host (' ' + $Rest.TrimEnd())
}

function Fail([string]$Message) {
    if ($script:ElevatedLog) {
        Add-Content -LiteralPath $script:ElevatedLog -Value "dvm: $Message" -Encoding UTF8
        Set-Content -LiteralPath "$($script:ElevatedLog).rc" -Value 1
    } else {
        [Console]::Error.WriteLine("dvm: $Message")
    }
    exit 1
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Format-Value($Value) {
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd') }   # PowerShell 7 turns ISO dates into DateTime
    if ($null -eq $Value -or "$Value" -eq '') { return '-' }
    "$Value"
}

function Get-Band([string]$Version) { [int][math]::Floor([int]($Version.Split('.')[2]) / 100) }

function Get-ManifestBand([string]$Version) {
    $p = $Version.Split('.')
    '{0}.{1}.{2}' -f $p[0], $p[1], ((Get-Band $Version) * 100)
}

function Test-Interactive {
    [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
}

function Confirm-Step([string]$Question) {
    if ($script:AssumeYes) { return $true }
    if (-not (Test-Interactive)) { return $false }
    Write-Host "$Question [Y/n] " -NoNewline
    $a = [Console]::ReadLine()
    return ($null -ne $a) -and ($a -match '^(|y|yes)$')
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    try {
        $A = [IO.Path]::GetFullPath($A).TrimEnd('\', '/')
        $B = [IO.Path]::GetFullPath($B).TrimEnd('\', '/')
    } catch { return $false }
    if ($IsWin) { return [string]::Equals($A, $B, [StringComparison]::OrdinalIgnoreCase) }
    return $A -eq $B
}

# ------------------------------------------------------------- downloading

function Save-Url([string]$Url, [string]$Dest) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $saved = $global:ProgressPreference
    $global:ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads slow on PowerShell 5.1
    try { Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing }
    finally { $global:ProgressPreference = $saved }
}

# Keep a cached copy; fall back to it when offline.
function Get-Cached([string]$Url, [string]$Dest, [TimeSpan]$Ttl) {
    if (Test-Path -LiteralPath $Dest) {
        if ($Offline) { return }
        if (((Get-Date) - (Get-Item -LiteralPath $Dest).LastWriteTime) -lt $Ttl) { return }
    }
    if ($Offline) { Fail "offline and no cached copy of $(Split-Path -Leaf $Dest)" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    $tmp = "$Dest.tmp"
    try {
        Save-Url $Url $tmp
        Move-Item -LiteralPath $tmp -Destination $Dest -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $Dest) { Out-Line "(offline? using cached $(Split-Path -Leaf $Dest))" DarkGray }
        else { Fail "could not download $Url" }
    }
}

# ------------------------------------------------------------ release data

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }

# releases-index.json -> channel, type, phase, eol, latest sdk, latest runtime, releases.json url
function ConvertFrom-IndexJson([string]$Path) {
    $rows = foreach ($r in @(Get-Prop (Read-Json $Path) 'releases-index')) {
        $cv = Get-Prop $r 'channel-version'
        if (-not $cv) { continue }
        $fields = @($cv) + @('release-type', 'support-phase', 'eol-date', 'latest-sdk', 'latest-runtime', 'releases.json' |
            ForEach-Object { Format-Value (Get-Prop $r $_) })
        [pscustomobject]@{ Key = [version]"$cv"; Line = ($fields -join "`t") }
    }
    @($rows | Sort-Object Key -Descending | ForEach-Object { $_.Line })
}

# <channel>/releases.json -> two kinds of lines, newest first:
#   S<TAB>sdk version<TAB>its runtime<TAB>release date
#   R<TAB>runtime version<TAB>release date
function ConvertFrom-ChannelJson([string]$Path, [string]$Cv) {
    $best = @{}
    $rts = @{}
    $i = 0
    foreach ($rel in @(Get-Prop (Read-Json $Path) 'releases')) {
        $date = Get-Prop $rel 'release-date'
        $rv = "$(Get-Prop (Get-Prop $rel 'runtime') 'version')"
        if ($rv -match $StableRe -and $rv.StartsWith("$Cv.") -and -not $rts.ContainsKey($rv)) { $rts[$rv] = $date }
        $entries = @()
        $many = Get-Prop $rel 'sdks'
        if ($many) { $entries += @($many) }
        $one = Get-Prop $rel 'sdk'
        if ($one) { $entries += $one }
        foreach ($e in $entries) {
            $v = "$(Get-Prop $e 'version')"
            if ($v -notmatch $StableRe -or -not $v.StartsWith("$Cv.")) { continue }
            if ($best.ContainsKey($v) -and $best[$v][0] -le $i) { continue }
            $best[$v] = @($i, (Get-Prop $e 'runtime-version'), $date)
        }
        $i++
    }
    @($best.Keys | Sort-Object { [version]$_ } -Descending | ForEach-Object {
        "S`t{0}`t{1}`t{2}" -f $_, (Format-Value $best[$_][1]), (Format-Value $best[$_][2])
    }) + @($rts.Keys | Sort-Object { [version]$_ } -Descending | ForEach-Object {
        "R`t{0}`t{1}" -f $_, (Format-Value $rts[$_])
    })
}

function Update-Tsv([string]$Json, [string]$Tsv, [scriptblock]$Parse, [string]$What) {
    if ((Test-Path -LiteralPath $Tsv) -and
        (Get-Item -LiteralPath $Tsv).LastWriteTime -ge (Get-Item -LiteralPath $Json).LastWriteTime) { return }
    try { $lines = @(& $Parse) } catch { Fail "could not read $What" }
    [IO.File]::WriteAllText($Tsv, (($lines -join "`n") + "`n"))
}

function Read-Tsv([string]$Path) { @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { , ($_ -split "`t") }) }

function Initialize-Index {
    $json = Join-Path $Cache 'releases-index.json'
    $tsv = Join-Path $Cache 'releases-index.tsv'
    Get-Cached "$MetaUrl/releases-index.json" $json $MetaTtl
    Update-Tsv $json $tsv { ConvertFrom-IndexJson $json } 'the .NET release index'
    $script:Index = @(Read-Tsv $tsv | ForEach-Object {
        [pscustomobject]@{ Channel = $_[0]; Type = $_[1]; Phase = $_[2]; Eol = $_[3]; LatestSdk = $_[4]; LatestRuntime = $_[5]; Url = $_[6] }
    })
    if ($script:Index.Count -eq 0) { Fail 'could not read the .NET release index' }
}

function Get-Channel([string]$Cv) {
    foreach ($c in $script:Index) { if ($c.Channel -eq $Cv) { return $c } }
    return $null
}

function Get-KnownChannel([string]$Cv) {
    $c = Get-Channel $Cv
    if (-not $c) { Fail "unknown .NET channel '$Cv' (see: dvm list --all)" }
    $c
}

function Get-ChannelRows([string]$Cv) {
    $c = Get-KnownChannel $Cv
    $json = Join-Path $Cache "$Cv.json"
    $tsv = Join-Path $Cache "$Cv.releases.tsv"
    Get-Cached $c.Url $json $MetaTtl
    Update-Tsv $json $tsv { ConvertFrom-ChannelJson $json $Cv } "releases of $Cv"
    @(Read-Tsv $tsv)
}

function Get-ChannelSdks([string]$Cv) {
    @(Get-ChannelRows $Cv | Where-Object { $_[0] -eq 'S' } | ForEach-Object { [pscustomobject]@{ Version = $_[1]; Runtime = $_[2]; Date = $_[3] } })
}

function Get-ChannelRuntimes([string]$Cv) {
    @(Get-ChannelRows $Cv | Where-Object { $_[0] -eq 'R' } | ForEach-Object { [pscustomobject]@{ Version = $_[1]; Date = $_[2] } })
}

function Get-InstallScript {
    $path = Join-Path $Cache 'dotnet-install.ps1'
    Get-Cached $InstallScriptUrl $path $ScriptTtl
    $path
}

# --------------------------------------------------------- installed state

function Get-StableDirs([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object { $_.Name -match $StableRe } |
        Sort-Object { [version]$_.Name } -Descending | ForEach-Object { $_.Name })
}

function Get-InstalledSdks { @(Get-StableDirs (Join-Path $Root 'sdk')) }
function Get-InstalledRuntimes { @(Get-StableDirs (Join-Path $Root 'shared\Microsoft.NETCore.App')) }

# Windows' list of installed programs (only for the standard folder).
function Get-UninstallEntries {
    if (-not $Integrate) { return @() }
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | ForEach-Object {
        $name = "$(Get-Prop $_ 'DisplayName')"
        if (-not $name -or $name -match '\(x86\)') { return }   # x86 .NET lives in Program Files (x86)
        $quiet = $false
        $cmd = "$(Get-Prop $_ 'QuietUninstallString')"
        if ($cmd) { $quiet = $true } else { $cmd = "$(Get-Prop $_ 'UninstallString')" }
        # Bundles (the installers people run) have their own uninstaller; the
        # MSI packages inside them only have msiexec and are hidden.
        $bundle = [bool]$cmd -and ($cmd -notmatch '^\s*"?msiexec')
        [pscustomobject]@{ Name = $name; Command = $cmd; Quiet = $quiet; Bundle = $bundle }
    })
}

# Who installed each SDK in the standard folder.
function Get-SdkOwners {
    $map = @{}
    foreach ($e in (Get-UninstallEntries)) {
        if ($e.Name -notmatch '^Microsoft \.NET (Core )?SDK (\d+\.\d+\.\d+)') { continue }
        $v = $Matches[2]
        $label = if ($e.Name -match 'Visual Studio') { 'Visual Studio' } else { 'Windows installer' }
        $cur = $map[$v]
        if ($cur -and $cur.Label -eq 'Visual Studio') { continue }
        if (-not $cur -or $label -eq 'Visual Studio' -or ($e.Bundle -and -not $cur.Bundle)) {
            $map[$v] = [pscustomobject]@{ Label = $label; Command = $e.Command; Quiet = $e.Quiet; Bundle = $e.Bundle }
        }
    }
    $map
}

# Who installed each runtime in the standard folder. Bundles lists the
# runtime installers that can be run to remove it; it is empty when the
# runtime came inside another installer (an SDK or Visual Studio).
function Get-RuntimeOwners {
    $map = @{}
    foreach ($e in (Get-UninstallEntries)) {
        $v = $null
        if ($e.Name -match '^Microsoft \.NET (Core )?Runtime - (\d+\.\d+\.\d+)') { $v = $Matches[2] }
        elseif ($e.Name -match '^Microsoft ASP\.NET Core (\d+\.\d+\.\d+) - Shared Framework') { $v = $Matches[1] }
        elseif ($e.Name -match '^Microsoft Windows Desktop Runtime - (\d+\.\d+\.\d+)') { $v = $Matches[1] }
        elseif ($e.Name -match '^Microsoft \.NET (\d+\.\d+\.\d+) - Windows Server Hosting') { $v = $Matches[1] }
        if (-not $v) { continue }
        if (-not $map.ContainsKey($v)) {
            $map[$v] = [pscustomobject]@{ Label = 'Windows installer'; Bundles = (New-Object System.Collections.ArrayList) }
        }
        if ($e.Bundle) { [void]$map[$v].Bundles.Add($e) }
    }
    $map
}

function Get-OwnerLabel($Owners, [string]$Version) {
    $o = $Owners[$Version]
    if ($o) { $o.Label } else { '' }
}

# Runtime an installed SDK runs on, from its dotnet.runtimeconfig.json.
function Get-SdkRuntime([string]$Version) {
    $file = Join-Path (Join-Path (Join-Path $Root 'sdk') $Version) 'dotnet.runtimeconfig.json'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    try { "$(Get-Prop (Get-Prop (Get-Prop (Read-Json $file) 'runtimeOptions') 'framework') 'version')" } catch { '' }
}

function Test-RuntimeComplete([string]$Version) {
    foreach ($f in $RuntimeFrameworks) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $Root 'shared') $f) $Version) -PathType Container)) { return $false }
    }
    $true
}

# Runtimes installed with 'dvm install runtime': they stay when SDKs are removed.
function Get-KeptRuntimes {
    $f = Join-Path $State 'runtimes'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    @(Get-Content -LiteralPath $f -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Add-KeptRuntime([string]$Version) {
    if ((Get-KeptRuntimes) -contains $Version) { return }
    New-Item -ItemType Directory -Force -Path $State | Out-Null
    Add-Content -LiteralPath (Join-Path $State 'runtimes') -Value $Version -Encoding UTF8
}

function Remove-KeptRuntime([string]$Version) {
    $f = Join-Path $State 'runtimes'
    if (-not (Test-Path -LiteralPath $f)) { return }
    $rest = @(Get-KeptRuntimes | Where-Object { $_ -ne $Version })
    $text = ''
    if ($rest.Count -gt 0) { $text = ($rest -join "`n") + "`n" }
    [IO.File]::WriteAllText($f, $text)
}

# Every installed SDK with the runtime it came with, newest SDK first.
function Get-SdkRuntimeMap {
    @(Get-InstalledSdks | ForEach-Object { [pscustomobject]@{ Sdk = $_; Runtime = (Get-SdkRuntime $_) } })
}

function Get-SdksWithRuntime([string]$Version, $Map) {
    @($Map | Where-Object { $_.Runtime -eq $Version } | ForEach-Object { $_.Sdk }) -join ', '
}

function Get-Channel2([string]$Version) { $p = $Version.Split('.'); "$($p[0]).$($p[1])" }

# An SDK runs on the runtime it came with or any newer patch of the same
# channel (that is what its dotnet.runtimeconfig.json asks for). Returns the
# SDKs (except $Skip) that no installed runtime other than $Version is new
# enough for.
function Get-NeedingSdks([string]$Version, [string]$Skip = '') {
    $others = @(Get-InstalledRuntimes | Where-Object { $_ -ne $Version })
    $cv = Get-Channel2 $Version
    $patch = [int]$Version.Split('.')[2]
    foreach ($e in (Get-SdkRuntimeMap)) {
        if ($e.Sdk -eq $Skip -or $e.Runtime -notmatch $StableRe) { continue }
        $need = [int]$e.Runtime.Split('.')[2]
        if ((Get-Channel2 $e.Runtime) -ne $cv -or $patch -lt $need) { continue }
        $ok = $false
        foreach ($o in $others) { if ((Get-Channel2 $o) -eq $cv -and [int]$o.Split('.')[2] -ge $need) { $ok = $true } }
        if (-not $ok) { [pscustomobject]@{ Sdk = $e.Sdk; Needs = $e.Runtime } }
    }
}

# Folders of a runtime: shared\<framework>\<version>, and host\fxr\<version>
# unless it is the newest host (the dotnet command always uses the newest).
function Get-RuntimePaths([string]$Version) {
    $paths = @()
    $shared = Join-Path $Root 'shared'
    if (Test-Path -LiteralPath $shared) {
        foreach ($d in @(Get-ChildItem -LiteralPath $shared -Directory | Sort-Object Name)) {
            $p = Join-Path $d.FullName $Version
            if (Test-Path -LiteralPath $p -PathType Container) { $paths += $p }
        }
    }
    $fxr = Join-Path (Join-Path $Root 'host') 'fxr'
    $p = Join-Path $fxr $Version
    $top = @(Get-StableDirs $fxr) | Select-Object -First 1
    if ((Test-Path -LiteralPath $p -PathType Container) -and $top -ne $Version) { $paths += $p }
    $paths
}

# --------------------------------------------------------------- printing

function Out-ChannelHeader($C, [string]$Suffix = '') {
    $type = $C.Type.ToUpperInvariant()
    if ($C.Phase -eq 'eol') { Out-Line "$($C.Channel)  $type $Dot end of life since $($C.Eol)$Suffix" Yellow }
    else { Out-Line "$($C.Channel)  $type $Dot $($C.Phase), supported until $($C.Eol)$Suffix" White }
}

function Out-Section([string]$Name) { Write-Host "  $Name" }

function Out-Row([string]$Version, [string]$Date, [bool]$Ok, [string]$Note, [string]$Label) {
    $rest = '{0,-10}  {1,-10}' -f $Version, $Date
    if ($Note) { $rest += "  $Note" }
    if ($Label) { $rest += "  ($Label)" }
    Out-Mark $Ok $rest
}

function Get-RuntimeLabel([string]$Version, $Map, $Kept, $Owners) {
    $with = Get-SdksWithRuntime $Version $Map
    $l = if ($with -and -not (@($Kept) -contains $Version)) { "comes with SDK $with" } else { 'runtime only' }
    $o = Get-OwnerLabel $Owners $Version
    if ($o) { $l += "; $o" }
    $l
}

# Runtime rows of a channel: all of them, or (Brief) only the latest one plus
# the installed ones.
function Out-RuntimeRows([string]$Cv, $Installed, [string]$Latest, $Map, $Kept, $Owners, [bool]$Brief) {
    $Installed = @($Installed)
    $printed = @{}
    foreach ($r in (Get-ChannelRuntimes $Cv)) {
        $ok = $Installed -contains $r.Version
        if ($Brief -and $r.Version -ne $Latest -and -not $ok) { continue }
        $note = if ($r.Version -eq $Latest) { 'latest' } else { '' }
        $label = if ($ok) { Get-RuntimeLabel $r.Version $Map $Kept $Owners } else { '' }
        Out-Row $r.Version $r.Date $ok $note $label
        $printed[$r.Version] = $true
    }
    if (-not $Brief) { return }
    foreach ($v in $Installed) {
        if ($printed.ContainsKey($v)) { continue }
        Out-Row $v '-' $true "not in Microsoft's release list" (Get-RuntimeLabel $v $Map $Kept $Owners)
    }
}

# ---------------------------------------------------------------- commands

function Invoke-List([string[]]$CmdArgs) {
    $all = $false
    $chan = ''
    foreach ($a in $CmdArgs) {
        if ($a -eq '--all') { $all = $true }
        elseif ($a.StartsWith('-')) { Fail "unknown option '$a'" }
        else { $chan = $a }
    }
    Initialize-Index
    if ($chan) { Show-Channel $chan; return }

    $sdks = Get-InstalledSdks
    $rts = Get-InstalledRuntimes
    $owners = Get-SdkOwners
    $rowners = Get-RuntimeOwners
    $map = Get-SdkRuntimeMap
    $kept = Get-KeptRuntimes
    $hidden = @()
    Out-Line ".NET LTS releases, newest first    $Check = installed in $Root"
    foreach ($c in $script:Index) {
        if ($c.Type -ne 'lts' -or $c.Phase -eq 'preview' -or $c.Phase -eq 'go-live') { continue }
        $mine = @($sdks | Where-Object { $_.StartsWith("$($c.Channel).") })
        $minert = @($rts | Where-Object { $_.StartsWith("$($c.Channel).") })
        if ($c.Phase -eq 'eol' -and -not $all -and $mine.Count -eq 0 -and $minert.Count -eq 0) { $hidden += $c.Channel; continue }
        Out-Line ''
        Out-ChannelHeader $c
        Out-Section 'Runtimes'
        Out-RuntimeRows $c.Channel $minert $c.LatestRuntime $map $kept $rowners $true
        Out-Section 'SDKs'
        $bands = @{}
        $printed = @{}
        foreach ($s in (Get-ChannelSdks $c.Channel)) {
            $b = Get-Band $s.Version
            $first = -not $bands.ContainsKey($b)
            $bands[$b] = $true
            $ok = $mine -contains $s.Version
            if (-not $first -and -not $ok) { continue }
            $note = ''
            if ($s.Version -eq $c.LatestSdk) { $note = 'latest' } elseif ($first) { $note = "latest $($c.Channel).${b}xx" }
            Out-Row $s.Version $s.Date $ok $note (Get-OwnerLabel $owners $s.Version)
            $printed[$s.Version] = $true
        }
        foreach ($v in $mine) {
            if ($printed.ContainsKey($v)) { continue }
            Out-Row $v '-' $true "not in Microsoft's release list" (Get-OwnerLabel $owners $v)
        }
    }
    Out-Line ''
    if ($hidden.Count -gt 0) {
        Out-Line "$($hidden.Count) end-of-life LTS channel(s) hidden: $($hidden -join ', ')  (dvm list --all)" DarkGray
    }
    Out-Line 'Everything in one channel: dvm list 10.0' DarkGray
    Out-Line 'Install an SDK: dvm install <lts | 10.0 | 10.0.404>    Only a runtime: dvm install runtime <lts | 10.0 | 10.0.15>' DarkGray
    Invoke-PostChecks
}

function Show-Channel([string]$Cv) {
    if ($Cv -notmatch $ChannelRe) { Fail "expected a channel like 10.0, got '$Cv'" }
    $c = Get-KnownChannel $Cv
    $sdks = Get-InstalledSdks
    $owners = Get-SdkOwners
    Out-ChannelHeader $c "    $Check = installed in $Root"
    Out-Section 'Runtimes'
    Out-RuntimeRows $Cv (Get-InstalledRuntimes) $c.LatestRuntime (Get-SdkRuntimeMap) (Get-KeptRuntimes) (Get-RuntimeOwners) $false
    Out-Section 'SDKs'
    foreach ($s in (Get-ChannelSdks $Cv)) {
        $note = if ($s.Version -eq $c.LatestSdk) { 'latest' } else { '' }
        Out-Row $s.Version $s.Date ($sdks -contains $s.Version) $note (Get-OwnerLabel $owners $s.Version)
    }
}

# lts | 10.0 | 10.0.404  ->  exact SDK version
function Resolve-SdkVersion([string]$Want) {
    if ($Want -eq 'lts') {
        foreach ($c in $script:Index) {
            if ($c.Type -eq 'lts' -and @('eol', 'preview', 'go-live') -notcontains $c.Phase) { return $c.LatestSdk }
        }
        Fail 'no supported LTS release found in the release index'
    }
    if ($Want -match $ChannelRe) { return (Get-KnownChannel $Want).LatestSdk }
    if ($Want -match $StableRe) {
        $cv = $Want.Substring(0, $Want.LastIndexOf('.'))
        $null = Get-KnownChannel $cv
        if (-not (@(Get-ChannelSdks $cv | ForEach-Object { $_.Version }) -contains $Want)) {
            if (@(Get-ChannelRuntimes $cv | ForEach-Object { $_.Version }) -contains $Want) {
                Fail "$Want is a runtime, not an SDK. Install it with: dvm install runtime $Want"
            }
            Fail "$Want is not a released .NET SDK (see: dvm list $cv)"
        }
        return $Want
    }
    Fail "don't know how to install '$Want'; use lts, a channel (10.0) or an SDK version (10.0.404)"
}

# lts | 10.0 | 10.0.15  ->  exact runtime version
function Resolve-RuntimeVersion([string]$Want) {
    $v = ''
    if ($Want -eq 'lts') {
        foreach ($c in $script:Index) {
            if ($c.Type -eq 'lts' -and @('eol', 'preview', 'go-live') -notcontains $c.Phase) { $v = $c.LatestRuntime; break }
        }
        if (-not $v) { Fail 'no supported LTS release found in the release index' }
    } elseif ($Want -match $ChannelRe) {
        $v = (Get-KnownChannel $Want).LatestRuntime
    } elseif ($Want -match $StableRe) {
        $cv = $Want.Substring(0, $Want.LastIndexOf('.'))
        $null = Get-KnownChannel $cv
        if (-not (@(Get-ChannelRuntimes $cv | ForEach-Object { $_.Version }) -contains $Want)) {
            if (@(Get-ChannelSdks $cv | ForEach-Object { $_.Version }) -contains $Want) {
                Fail "$Want is an SDK, not a runtime. Install it with: dvm install $Want"
            }
            Fail "$Want is not a released .NET runtime (see: dvm list $cv)"
        }
        $v = $Want
    } else {
        Fail "don't know how to install runtime '$Want'; use lts, a channel (10.0) or a runtime version (10.0.15)"
    }
    if ($v -notmatch $StableRe) { Fail "channel $Want has no released runtime" }
    $v
}

function Invoke-Install([string[]]$CmdArgs) {
    $kind = 'sdk'
    if ($CmdArgs.Count -gt 0 -and $CmdArgs[0] -eq 'runtime') { $kind = 'runtime'; $CmdArgs = @($CmdArgs | Select-Object -Skip 1) }
    if ($CmdArgs.Count -ne 1) { Fail 'usage: dvm install <lts | 10.0 | 10.0.404>  or  dvm install runtime <lts | 10.0 | 10.0.15>' }
    Initialize-Index
    $ops = @()
    if ($kind -eq 'runtime') {
        $v = Resolve-RuntimeVersion $CmdArgs[0].ToLowerInvariant()
        $what = "runtime $v"
        if (Test-RuntimeComplete $v) {
            Out-Line "$Check Runtime $v is already installed in $Root"
            $with = Get-SdksWithRuntime $v (Get-SdkRuntimeMap)
            if ($with -and -not ((Get-KeptRuntimes) -contains $v)) {
                Out-Line "  It came with SDK $with; from now on it stays when you remove that SDK."
            }
        } else {
            $ops += "runtime:$v"
        }
    } else {
        $v = Resolve-SdkVersion $CmdArgs[0].ToLowerInvariant()
        $what = "SDK $v"
        if ((Get-InstalledSdks) -contains $v) {
            Out-Line "$Check SDK $v is already installed in $Root"
        } else {
            $ops += "install:$v/$(Get-SdkRuntimeOf $v)"
        }
    }
    if ((Test-IntegrationNeeded) -or (($ops.Count -gt 0) -and $Integrate)) { $ops += 'integrate' }
    if ($ops.Count -gt 0) {
        $null = Get-InstallScript
        if (-not (Invoke-Privileged $ops)) { Fail "installing $what failed" }
    }
    if ($kind -eq 'runtime') { Add-KeptRuntime $v }
    Test-PathSetup
}

# Runtime a released SDK comes with, from the release data.
function Get-SdkRuntimeOf([string]$Version) {
    $cv = $Version.Substring(0, $Version.LastIndexOf('.'))
    foreach ($s in (Get-ChannelSdks $cv)) { if ($s.Version -eq $Version) { return $s.Runtime } }
    ''
}

# Folders that belong only to this SDK. Its packs and templates stay while
# another SDK came with the same runtime. Its runtime also stays when it was
# installed with 'dvm install runtime' or another SDK still needs it.
function Get-RemovalPaths([string]$Version) {
    $paths = @(Join-Path (Join-Path $Root 'sdk') $Version)
    $others = @(Get-InstalledSdks | Where-Object { $_ -ne $Version })
    $rt = Get-SdkRuntime $Version
    if ($rt) {
        $used = $false
        foreach ($o in $others) { if ((Get-SdkRuntime $o) -eq $rt) { $used = $true } }
        if (-not $used) {
            $rtdirs = @()
            if (-not ((Get-KeptRuntimes) -contains $rt) -and @(Get-NeedingSdks $rt $Version).Count -eq 0) {
                $rtdirs = @(Get-RuntimePaths $rt)
            }
            $shared = Join-Path $Root 'shared'
            $paths += @($rtdirs | Where-Object { $_.StartsWith($shared) })
            $dir = Join-Path $Root 'packs'
            if (Test-Path -LiteralPath $dir) {
                foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name)) {
                    $p = Join-Path $d.FullName $rt
                    if (Test-Path -LiteralPath $p -PathType Container) { $paths += $p }
                }
            }
            $p = Join-Path (Join-Path $Root 'templates') $rt
            if (Test-Path -LiteralPath $p -PathType Container) { $paths += $p }
            $paths += @($rtdirs | Where-Object { -not $_.StartsWith($shared) })
        }
    }
    $band = Get-ManifestBand $Version
    $used = $false
    foreach ($o in $others) { if ((Get-ManifestBand $o) -eq $band) { $used = $true } }
    $p = Join-Path (Join-Path $Root 'sdk-manifests') $band
    if (-not $used -and (Test-Path -LiteralPath $p -PathType Container)) { $paths += $p }
    $paths
}

# Shows the folders, asks, and deletes them. False when the user said no.
function Remove-Folders([string]$What, [string[]]$Paths) {
    Out-Line "Removing ${What}:"
    foreach ($p in $Paths) { Out-Line "  $p" }
    if (-not (Confirm-Step 'Delete these folders?')) { return $false }
    if (-not (Invoke-Privileged @($Paths | ForEach-Object { "delete:$_" }))) { Fail "removing $What failed" }
    $true
}

function Invoke-Uninstall([string[]]$CmdArgs) {
    if ($CmdArgs.Count -gt 0 -and $CmdArgs[0] -eq 'runtime') { Invoke-UninstallRuntime @($CmdArgs | Select-Object -Skip 1); return }
    if ($CmdArgs.Count -ne 1) { Fail 'usage: dvm uninstall <10.0.404>  or  dvm uninstall runtime <10.0.15>' }
    $v = $CmdArgs[0]
    if (-not ((Get-InstalledSdks) -contains $v)) {
        if ((Get-InstalledRuntimes) -contains $v) { Fail "$v is a runtime, not an SDK. Remove it with: dvm uninstall runtime $v" }
        Fail "SDK $v is not installed in $Root (see: dvm list)"
    }
    $owner = (Get-SdkOwners)[$v]
    if ($owner -and $owner.Label -eq 'Visual Studio') {
        Out-Line "SDK $v was installed by Visual Studio. Remove it with the Visual Studio Installer"
        Out-Line '(Modify > Individual components); otherwise Visual Studio puts it back.'
        return
    }
    if ($owner) {
        Out-Line "SDK $v was installed with the Windows installer."
        if (-not (Confirm-Step 'Run its uninstaller?')) { Out-Line 'Nothing removed.'; return }
        if (-not (Invoke-Privileged @("uninstaller:$v"))) { Fail "removing SDK $v failed" }
    } else {
        if (-not (Remove-Folders "SDK $v" @(Get-RemovalPaths $v))) { Out-Line 'Nothing removed.'; return }
    }
    Out-Line "$Check SDK $v removed"
}

function Invoke-UninstallRuntime([string[]]$CmdArgs) {
    if ($CmdArgs.Count -ne 1) { Fail 'usage: dvm uninstall runtime <10.0.15>' }
    $v = $CmdArgs[0]
    if (-not ((Get-InstalledRuntimes) -contains $v)) {
        if ((Get-InstalledSdks) -contains $v) { Fail "$v is an SDK, not a runtime. Remove it with: dvm uninstall $v" }
        Fail "runtime $v is not installed in $Root (see: dvm list)"
    }
    $need = @(Get-NeedingSdks $v)
    if ($need.Count -gt 0) {
        $lines = @("runtime $v can't be removed: no other installed runtime is new enough for") +
                 @($need | ForEach-Object { "  SDK $($_.Sdk) (needs $($_.Needs) or newer)" }) +
                 @('Remove those SDKs first with: dvm uninstall <version>')
        Fail ($lines -join "`n")
    }
    $owner = (Get-RuntimeOwners)[$v]
    if ($owner -and $owner.Bundles.Count -eq 0) {
        Out-Line "Runtime $v was installed as part of another program (an SDK installer or Visual Studio)."
        Out-Line 'It goes when you remove that program (Settings > Apps, or the Visual Studio Installer).'
        return
    }
    if ($owner) {
        Out-Line "Runtime $v was installed with the Windows installer."
        if (-not (Confirm-Step 'Run its uninstaller?')) { Out-Line 'Nothing removed.'; return }
        if (-not (Invoke-Privileged @("rtuninstaller:$v"))) { Fail "removing runtime $v failed" }
    } else {
        if (-not (Remove-Folders "runtime $v" @(Get-RuntimePaths $v))) { Out-Line 'Nothing removed.'; return }
    }
    Remove-KeptRuntime $v
    Out-Line "$Check Runtime $v removed"
}

# --------------------------------------------- privileged steps (elevated)

function Test-Admin {
    if (-not $IsWin) { return $true }
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Writable([string]$Path) {
    $p = $Path
    while ($p -and -not (Test-Path -LiteralPath $p)) { $p = Split-Path -Parent $p }
    if (-not $p) { return $false }
    $probe = Join-Path $p ('.dvm-write-test-' + [guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe, ''); Remove-Item -LiteralPath $probe -Force; $true } catch { $false }
}

function Get-Arch {
    $a = "$env:PROCESSOR_ARCHITEW6432"
    if (-not $a) { $a = "$env:PROCESSOR_ARCHITECTURE" }
    switch ($a) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'x64' } }
}

$InstallLocationKey = 'HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\' + (Get-Arch)

function Get-PathEntries([string]$Scope) {
    @(("$([Environment]::GetEnvironmentVariable('Path', $Scope))" -split ';') | Where-Object { $_ } |
        ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
}

# What is still missing for the standard folder to be the system default.
function Test-IntegrationNeeded {
    if (-not $Integrate -or -not (Test-Path -LiteralPath (Join-Path $Root $DotnetExe))) { return $false }
    $inPath = @(Get-PathEntries 'Machine' | Where-Object { Test-SamePath $_ $Root }).Count -gt 0
    $loc = Get-Prop (Get-ItemProperty -Path $InstallLocationKey -ErrorAction SilentlyContinue) 'InstallLocation'
    return (-not $inPath) -or -not (Test-SamePath "$loc" $Root)
}

# Puts a folder first in the system PATH. Edits the registry value directly so
# entries such as %SystemRoot%\system32 stay unexpanded, then tells running
# programs (Explorer, new terminals) that the environment changed.
function Add-MachinePathEntry([string]$Dir) {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    try {
        $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $new = if ($raw) { "$Dir;" + $raw.TrimStart(';') } else { $Dir }
        $key.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $key.Close() }
    [Environment]::SetEnvironmentVariable('DVM_PATH_REFRESH', '1', 'Machine')   # setting and clearing a variable
    [Environment]::SetEnvironmentVariable('DVM_PATH_REFRESH', $null, 'Machine') # broadcasts the change
}

function Set-Integration {
    if (-not $Integrate) { return }
    if (@(Get-PathEntries 'Machine' | Where-Object { Test-SamePath $_ $Root }).Count -eq 0) {
        Add-MachinePathEntry "$Root\"
        Write-Host "Added $Root to the system PATH."
    }
    $loc = Get-Prop (Get-ItemProperty -Path $InstallLocationKey -ErrorAction SilentlyContinue) 'InstallLocation'
    if (-not (Test-SamePath "$loc" $Root)) {
        New-Item -Path $InstallLocationKey -Force | Out-Null
        Set-ItemProperty -Path $InstallLocationKey -Name 'InstallLocation' -Value "$Root\"
        Write-Host "Registered $Root as the .NET install location."
    }
}

# dotnet-install.ps1 replaces dotnet.exe and other unversioned files with the
# ones of the version it installs. Keep them when a newer (or the same) host
# is already there, so installing an older version can't downgrade dotnet.exe.
function Test-SkipNonVersioned([string]$RuntimeVersion) {
    $top = @(Get-StableDirs (Join-Path (Join-Path $Root 'host') 'fxr')) | Select-Object -First 1
    if (-not $top) { return $false }
    if ($RuntimeVersion -notmatch $StableRe) { return $true }
    [version]$top -ge [version]$RuntimeVersion
}

function Install-SdkFiles([string]$Spec) {   # <sdk version>/<runtime it comes with>
    $Version, $rt = $Spec -split '/', 2
    $script = Get-InstallScript
    $skip = Test-SkipNonVersioned "$rt"
    Write-Host "Installing .NET SDK $Version into $Root ..."
    & $script -Version $Version -InstallDir $Root -NoPath -SkipNonVersionedFiles:$skip
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $Root 'sdk') $Version))) { Fail "installing SDK $Version failed" }
    Write-Host "$Check SDK $Version installed"
}

function Install-RuntimeFiles([string]$Version) {
    $script = Get-InstallScript
    $skip = Test-SkipNonVersioned $Version
    if ($IsWin) {
        Write-Host "Installing .NET runtime $Version (with ASP.NET Core and Windows Desktop) into $Root ..."
    } else {
        Write-Host "Installing .NET runtime $Version (with ASP.NET Core) into $Root ..."
    }
    & $script -Runtime aspnetcore -Version $Version -InstallDir $Root -NoPath -SkipNonVersionedFiles:$skip
    if ($IsWin) { & $script -Runtime windowsdesktop -Version $Version -InstallDir $Root -NoPath -SkipNonVersionedFiles }
    if (-not (Test-RuntimeComplete $Version)) { Fail "installing runtime $Version failed" }
    Write-Host "$Check Runtime $Version installed"
}

# Deletes a folder that Remove-Folders showed; never anything outside the dotnet folder.
function Remove-DvmFolder([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { Fail "refusing to delete $Path, which is outside $Root" }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}

function Invoke-UninstallCommand([string]$Command, [bool]$Quiet) {
    $cmd = $Command
    if (-not $Quiet) { $cmd += ' /passive /norestart' }
    Write-Host "Running: $cmd"
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$cmd`"" -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Fail "the uninstaller exited with code $($p.ExitCode)" }
}

function Invoke-Uninstaller([string]$Version) {
    $o = (Get-SdkOwners)[$Version]
    if (-not $o -or -not $o.Command) { Fail "no uninstaller registered for SDK $Version" }
    Invoke-UninstallCommand $o.Command $o.Quiet
}

function Invoke-RuntimeUninstallers([string]$Version) {
    $o = (Get-RuntimeOwners)[$Version]
    if (-not $o -or $o.Bundles.Count -eq 0) { Fail "no uninstaller registered for runtime $Version" }
    foreach ($b in $o.Bundles) { Invoke-UninstallCommand $b.Command $b.Quiet }
}

function Invoke-Op([string]$Op) {
    $verb, $value = $Op -split ':', 2
    switch ($verb) {
        'install'       { Install-SdkFiles $value }
        'runtime'       { Install-RuntimeFiles $value }
        'delete'        { Remove-DvmFolder $value }
        'uninstaller'   { Invoke-Uninstaller $value }
        'rtuninstaller' { Invoke-RuntimeUninstallers $value }
        'integrate'     { Set-Integration }
        default         { Fail "unknown step '$Op'" }
    }
}

function Show-LogFrom([string]$Log, [int]$From, [bool]$Final) {
    if (-not (Test-Path -LiteralPath $Log)) { return $From }
    try { $lines = @(Get-Content -LiteralPath $Log -Encoding UTF8 -ErrorAction Stop) } catch { return $From }
    $upTo = if ($Final) { $lines.Count } else { $lines.Count - 1 }   # the last line may still be written
    for ($i = $From; $i -lt $upTo; $i++) { Write-Host $lines[$i] }
    [math]::Max($From, $upTo)
}

# Runs the steps here when we may write to the dotnet folder, otherwise in an
# elevated copy of dvm (one UAC prompt) whose output is shown here.
function Invoke-Privileged([string[]]$Ops) {
    if ((Test-Admin) -or (-not $Integrate -and (Test-Writable $Root))) {
        foreach ($op in $Ops) { Invoke-Op $op }
        return $true
    }
    $log = Join-Path ([IO.Path]::GetTempPath()) ('dvm-' + [guid]::NewGuid().ToString('N') + '.log')
    $exe = (Get-Process -Id $PID).Path
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '__elevated', $log, $Root, $Cache) + $Ops
    $argLine = ($argv | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    Out-Line 'dvm needs administrator rights for this step; confirm the Windows prompt ...' DarkGray
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -PassThru
    } catch {
        Out-Line 'Administrator rights were not granted. Run the same dvm command in a PowerShell window' Yellow
        Out-Line 'opened with "Run as administrator".' Yellow
        return $false
    }
    $null = $p.Handle
    $shown = 0
    while (-not $p.HasExited) { Start-Sleep -Milliseconds 400; $shown = Show-LogFrom $log $shown $false }
    $null = Show-LogFrom $log $shown $true
    $rc = 1
    if (Test-Path -LiteralPath "$log.rc") { $rc = [int]"$(Get-Content -LiteralPath "$log.rc" | Select-Object -First 1)" }
    Remove-Item -LiteralPath $log, "$log.rc" -Force -ErrorAction SilentlyContinue
    $rc -eq 0
}

# ------------------------------------------------- PATH in new terminals

function Find-DotnetIn([string[]]$Entries) {
    foreach ($e in $Entries) {
        if ($e -and (Test-Path -LiteralPath (Join-Path $e $DotnetExe) -PathType Leaf)) { return $e }
    }
    return $null
}

function Test-PathSetup {
    if ($script:PathChecked) { return }
    $mine = Join-Path $Root $DotnetExe
    if (-not (Test-Path -LiteralPath $mine)) { return }
    $script:PathChecked = $true
    if ($IsWin) {
        # What a new terminal will see: system PATH first, then the user PATH.
        $entries = @(Get-PathEntries 'Machine') + @(Get-PathEntries 'User')
    } else {
        $entries = @("$env:PATH" -split ':' | Where-Object { $_ })
    }
    $found = Find-DotnetIn $entries
    $dotnetRoots = @('Process', 'User', 'Machine' | ForEach-Object {
        $d = [Environment]::GetEnvironmentVariable('DOTNET_ROOT', $_)
        if ($d -and -not (Test-SamePath $d $Root)) { "$_ DOTNET_ROOT is $d" }
    } | Select-Object -Unique)
    if ($found -and (Test-SamePath $found $Root)) {
        if ($dotnetRoots.Count -gt 0) {
            Out-Line ''
            Out-Line 'DOTNET_ROOT points to another folder, so apps may still use it. Remove the variable' Yellow
            Out-Line '(System Properties > Environment Variables):' Yellow
            foreach ($d in $dotnetRoots) { Out-Line "      $d" }
        }
        $current = Find-DotnetIn @("$env:PATH" -split ';' | Where-Object { $_ })
        if ($IsWin -and -not (Test-SamePath $current $Root)) { Out-Line 'Open a new terminal to start using it.' DarkGray }
        return
    }
    Out-Line ''
    if (-not $found) { Out-Line '`dotnet` is not on your PATH yet.' Yellow }
    else { Out-Line "``dotnet`` in new terminals is $(Join-Path $found $DotnetExe), not dvm's $mine." Yellow }
    if ($Integrate) {
        foreach ($scope in 'User', 'Machine') {
            foreach ($e in (Get-PathEntries $scope)) {
                if (-not (Test-SamePath $e $Root) -and (Test-Path -LiteralPath (Join-Path $e $DotnetExe) -PathType Leaf)) {
                    Out-Line "  The $($scope.ToLower()) PATH contains $e; remove it (System Properties > Environment Variables)."
                }
            }
        }
        foreach ($d in $dotnetRoots) { Out-Line "  $d; remove that variable too." }
        Out-Line '  Then open a new terminal.'
    } else {
        Out-Line '  Add this to your PowerShell profile to use dvm''s folder:'
        Out-Line "    `$env:DOTNET_ROOT = '$Root'"
        Out-Line "    `$env:PATH = `"$Root;`$env:PATH`""
    }
}

# ------------------------------------------------ other .NET installations

function Get-ForeignRoots {
    $cands = New-Object System.Collections.Generic.List[string]
    $sep = if ($IsWin) { ';' } else { ':' }
    $pathText = "$env:PATH"
    if ($IsWin) { $pathText = (@(Get-PathEntries 'Machine') + @(Get-PathEntries 'User') + @($pathText -split ';')) -join ';' }
    foreach ($e in ($pathText -split $sep)) {
        if ($e -and (Test-Path -LiteralPath (Join-Path $e $DotnetExe) -PathType Leaf)) { $cands.Add($e) }
    }
    foreach ($scope in 'Process', 'User', 'Machine') {
        $d = [Environment]::GetEnvironmentVariable('DOTNET_ROOT', $scope)
        if ($d) { $cands.Add($d) }
    }
    if ($env:LOCALAPPDATA) { $cands.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet')) }
    if ($env:USERPROFILE) {
        $cands.Add((Join-Path $env:USERPROFILE '.dotnet'))
        $cands.Add((Join-Path $env:USERPROFILE '.dotnetup'))
    }
    $x86 = if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'dotnet' } else { '' }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($c in $cands) {
        try { $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($c)).TrimEnd('\', '/') } catch { continue }
        if ((Test-SamePath $full $Root) -or (Test-SamePath $full $x86)) { continue }
        if (@(Get-StableDirs (Join-Path $full 'sdk')).Count + @(Get-StableDirs (Join-Path $full 'shared\Microsoft.NETCore.App')).Count -eq 0) { continue }
        if (@($result | Where-Object { Test-SamePath $_ $full }).Count -gt 0) { continue }
        $result.Add($full)
    }
    @($result)
}

function Get-RemoveCommand([string]$Dir) {
    if ($env:USERPROFILE -and (Test-SamePath $Dir (Join-Path $env:USERPROFILE '.dotnet'))) {
        # .dotnet also holds global tools (.dotnet\tools): keep those.
        return "Get-ChildItem '$Dir' -Exclude tools | Remove-Item -Recurse -Force   (keeps .dotnet\tools)"
    }
    "Remove-Item -Recurse -Force '$Dir'"
}

function Test-Seen([string]$Dir) {
    $f = Join-Path $State 'seen'
    (Test-Path -LiteralPath $f) -and (@(Get-Content -LiteralPath $f | Where-Object { Test-SamePath $_ $Dir }).Count -gt 0)
}

function Set-Seen([string]$Dir) {
    if (Test-Seen $Dir) { return }
    New-Item -ItemType Directory -Force -Path $State | Out-Null
    Add-Content -LiteralPath (Join-Path $State 'seen') -Value $Dir -Encoding UTF8
}

# Microsoft build for an SDK version: the same one, or the newest of its feature band.
function Find-MicrosoftBuild([string]$Version) {
    $cv = $Version.Substring(0, $Version.LastIndexOf('.'))
    if (-not (Get-Channel $cv)) { return '' }
    $list = @(Get-ChannelSdks $cv | ForEach-Object { $_.Version })
    if ($list -contains $Version) { return $Version }
    $b = Get-Band $Version
    foreach ($s in $list) { if ((Get-Band $s) -eq $b) { return $s } }
    return ''
}

function Invoke-Adoption([string]$Dir) {
    $sdks = @(Get-StableDirs (Join-Path $Dir 'sdk'))
    $rts = @(Get-StableDirs (Join-Path $Dir 'shared\Microsoft.NETCore.App'))
    if ($sdks.Count + $rts.Count -eq 0) { return }
    $remove = Get-RemoveCommand $Dir
    Out-Line ''
    Out-Line "Found .NET outside dvm: $Dir (folder)" Yellow
    if ($sdks.Count -gt 0) { Out-Line "  SDK $($sdks -join ', ')" }
    if ($rts.Count -gt 0) { Out-Line "  runtime $($rts -join ', ')" }
    if (-not (Test-Interactive) -and -not $script:AssumeYes) {
        Out-Line "  Run 'dvm init' to install the same version(s) with dvm."
        return
    }
    if (-not (Confirm-Step "Install the same version(s) with dvm into ${Root}?")) {
        Set-Seen $Dir
        Out-Line "  Skipped. Run 'dvm init' to do this later."
        return
    }
    Initialize-Index
    $installed = Get-InstalledSdks
    $ops = @()
    $have = @(Get-InstalledRuntimes)
    foreach ($v in $sdks) {
        $m = Find-MicrosoftBuild $v
        if (-not $m) { Out-Line "  There is no Microsoft build of $v or of its feature band; skipped." Yellow; continue }
        if ($m -ne $v) { Out-Line "  $v is not a Microsoft release; using $m from the same feature band." }
        if ($installed -contains $m -or @($ops | Where-Object { $_.StartsWith("install:$m/") }).Count -gt 0) { Out-Line "$Check SDK $m is already installed" }
        else {
            $rt = Get-SdkRuntimeOf $m
            $ops += "install:$m/$rt"
            if ($rt -match $StableRe) { $have += $rt }
        }
    }
    # Runtimes the SDKs above don't bring: the newest one of each channel.
    $have = @($have | Sort-Object { [version]$_ } -Descending)
    $newRuntimes = @()
    $seenChannels = @{}
    foreach ($v in $rts) {
        $cv = Get-Channel2 $v
        if ($seenChannels.ContainsKey($cv)) { continue }
        $seenChannels[$cv] = $true
        $patch = [int]$v.Split('.')[2]
        $h = @($have | Where-Object { (Get-Channel2 $_) -eq $cv -and [int]$_.Split('.')[2] -ge $patch }) | Select-Object -First 1
        if ($h) { Out-Line "$Check Runtime $h is already installed"; continue }
        $c = Get-Channel $cv
        if (-not $c) { Out-Line "  There is no Microsoft build of runtime $v; skipped." Yellow; continue }
        $want = $v
        if (-not (@(Get-ChannelRuntimes $cv | ForEach-Object { $_.Version }) -contains $v)) {
            $want = $c.LatestRuntime
            Out-Line "  Runtime $v is not a Microsoft release; using $want."
        }
        $ops += "runtime:$want"
        $newRuntimes += $want
    }
    if ($Integrate) { $ops += 'integrate' }
    if ($ops.Count -gt 0) {
        $null = Get-InstallScript
        if (-not (Invoke-Privileged $ops)) { Fail 'installing failed' }
    }
    foreach ($v in $newRuntimes) { Add-KeptRuntime $v }
    Test-PathSetup
    Set-Seen $Dir
    Out-Line ''
    Out-Line "You can remove the old install now:   $remove"
    Out-Line 'See your versions with:               dvm list'
}

function Invoke-Detect([string]$Mode) {
    if ($NoDetect) { return }
    $script:Remind = @()
    foreach ($d in (Get-ForeignRoots)) {
        if ($Mode -eq 'init' -or -not (Test-Seen $d)) { Invoke-Adoption $d }
        else { $script:Remind += $d }
    }
}

function Invoke-PostChecks {
    if ($NoDetect) { return }
    foreach ($d in $script:Remind) {
        Out-Line ''
        Out-Line "note: .NET is also installed in $d (folder), outside dvm." Yellow
        Out-Line "      Remove it with: $(Get-RemoveCommand $d)"
    }
    if (Test-IntegrationNeeded) {
        Out-Line ''
        Out-Line "note: $Root is not the system default dotnet yet. Run 'dvm init'." Yellow
    }
    Test-PathSetup
}

function Invoke-Init {
    $roots = @()
    if (-not $NoDetect) { $roots = @(Get-ForeignRoots) }
    if ($roots.Count -eq 0) { Out-Line 'No other .NET installs found.' }
    Invoke-Detect 'init'
    if (Test-Path -LiteralPath (Join-Path $Root $DotnetExe)) {
        if (Test-IntegrationNeeded) { $null = Invoke-Privileged @('integrate') }
        Test-PathSetup
        Out-Line ''
        Out-Line "$Check dvm manages $Root ($((Get-InstalledSdks).Count) SDK(s), $((Get-InstalledRuntimes).Count) runtime(s) installed). See them with: dvm list"
    } else {
        Out-Line ''
        Out-Line "Nothing in $Root yet. Install the newest SDK with: dvm install lts"
    }
}

function Show-Usage {
    @"
dvm $DvmVersion - .NET SDK and runtime version manager (LTS releases)

  dvm list [--all]           LTS channels, newest first, with their runtimes and
                             SDKs; $Check marks what is installed
                             (--all also shows end-of-life LTS channels)
  dvm list <channel>         every runtime and SDK of a channel, e.g. dvm list 10.0
  dvm install <version>      lts       newest SDK of the newest supported LTS
                             10.0      newest SDK of that channel
                             10.0.404  that exact SDK
  dvm install runtime <v>    only a runtime: lts, 10.0 or 10.0.15 (e.g. to run
                             net8.0 apps that you build with a newer SDK)
  dvm uninstall <version>    remove an SDK, e.g. dvm uninstall 10.0.404
  dvm uninstall runtime <v>  remove a runtime, e.g. dvm uninstall runtime 10.0.10
  dvm init                   find other .NET installs, offer to take them over,
                             and make dvm's folder the system default dotnet
  dvm version                print dvm's version

Options: -y, --yes   answer yes to every question

dvm manages $Root and asks for administrator rights (UAC) only when it has to write there.
Pin an SDK per repository with global.json.
"@ -split "`r?`n" | ForEach-Object { Write-Host $_ }
}

# ------------------------------------------------------------------- main

if ($args.Count -ge 4 -and $args[0] -eq '__elevated') {
    # Elevated copy started by Invoke-Privileged: run the steps, log to a file.
    $script:ElevatedLog = $args[1]
    $Root = $args[2]
    $Cache = $args[3]
    $Integrate = $IsWin -and ($Root -eq $DefaultRoot)
    $ops = @($args | Select-Object -Skip 4)
    $rc = 0
    try {
        & { foreach ($op in $ops) { Invoke-Op $op } } *>&1 | ForEach-Object {
            Add-Content -LiteralPath $script:ElevatedLog -Value "$_" -Encoding UTF8
        }
    } catch {
        Add-Content -LiteralPath $script:ElevatedLog -Value "dvm: $($_.Exception.Message)" -Encoding UTF8
        $rc = 1
    }
    Set-Content -LiteralPath "$($script:ElevatedLog).rc" -Value $rc
    exit $rc
}

$rest = @()
foreach ($a in $args) {
    if ($a -eq '-y' -or $a -eq '--yes') { $script:AssumeYes = $true } else { $rest += "$a" }
}
$cmd = if ($rest.Count -gt 0) { $rest[0] } else { 'help' }
$cmdArgs = @($rest | Select-Object -Skip 1)

switch ($cmd) {
    { $_ -in 'list', 'ls' }                { Invoke-Detect 'auto'; Invoke-List $cmdArgs }
    { $_ -in 'install', 'i' }              { Invoke-Detect 'auto'; Invoke-Install $cmdArgs }
    { $_ -in 'uninstall', 'remove', 'rm' } { Invoke-Uninstall $cmdArgs }
    'init'                                 { Invoke-Init }
    { $_ -in 'version', '--version', '-v' } { Out-Line "dvm $DvmVersion" }
    { $_ -in 'help', '-h', '--help' }      { Show-Usage }
    default                                { Show-Usage; exit 2 }
}
exit 0
