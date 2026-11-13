# Tests windows/install.ps1 in all the ways people run it (from a clone with
# -File, piped into Invoke-Expression like `irm ... | iex`, a downloaded copy,
# -Ref / $env:DVM_REF), its errors, and `dvm update`, which runs the installer
# of the latest release. GitHub is replaced by file:// URLs, so this runs
# offline.
#   pwsh -File tests/test-install.ps1                 (any OS)
#   powershell -ExecutionPolicy Bypass -File tests\test-install.ps1
# On Windows the installer really adds its folder to your user PATH, so there
# it only runs in CI (when $env:CI is set).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$isWin = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if ($isWin -and -not $env:CI) { Write-Host 'skipped: on Windows this test changes your user PATH; it runs in CI'; exit 0 }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
$windowsDir = Join-Path $repoRoot 'windows'
$installer = Join-Path $windowsDir 'install.ps1'
$repoVersion = "$(Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -TotalCount 1)".Trim()
$shell = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { 'powershell.exe' } else { (Get-Process -Id $PID).Path }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvm-install-tests-' + [guid]::NewGuid().ToString('N'))

function FileUrl([string]$Path) {   # [Uri]'/tmp/x' is a relative URI on Linux
    if ($isWin) { ([Uri]$Path).AbsoluteUri } else { 'file://' + ($Path -replace ' ', '%20') }
}

# A fake GitHub: <base>/<ref>/{VERSION,windows/dvm.ps1,windows/dvm.cmd,windows/install.ps1}
# with LF line endings (what GitHub serves), and the VERSION file the latest
# release carries.
$base = Join-Path $tmp 'github'
function New-FakeRef([string]$Ref, [string]$Version) {
    $dir = Join-Path (Join-Path $base $Ref) 'windows'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($f in 'dvm.ps1', 'dvm.cmd', 'install.ps1') {
        $text = [IO.File]::ReadAllText((Join-Path $windowsDir $f)) -replace "`r`n", "`n"
        if ($Version -eq 'broken') { $text = "<html>404</html>`n" }
        [IO.File]::WriteAllText((Join-Path $dir $f), $text)
    }
    [IO.File]::WriteAllText((Join-Path (Join-Path $base $Ref) 'VERSION'), "$Version`n")
}
New-FakeRef 'v9.9.9' '9.9.9'
New-FakeRef 'v9.9.8' '9.9.8'
New-FakeRef 'master' '9.10.0'
New-FakeRef 'feature/x' '9.11.0'
New-FakeRef 'broken' 'broken'
$latest = Join-Path $tmp 'latest'
New-Item -ItemType Directory -Force -Path $latest | Out-Null
[IO.File]::WriteAllText((Join-Path $latest 'VERSION'), "9.9.9`n")

$script:pass = 0
$script:fail = 0
$script:out = ''
$script:code = 0
$script:local = ''
$script:dest = ''

function New-Case([string]$Name) {
    $script:local = Join-Path (Join-Path $tmp $Name) 'localappdata'
    New-Item -ItemType Directory -Force -Path $script:local | Out-Null
    $script:dest = Join-Path (Join-Path $script:local 'Programs') 'dvm'
}

# Runs one PowerShell command line in the case's environment.
#   How: 'file'   install.ps1 -File (with Arguments)
#        'iex'    install.ps1's text piped into Invoke-Expression
#        'dvm'    the installed lib\dvm.ps1 (with Arguments)
#        'clone'  the clone's windows\dvm.ps1 (with Arguments)
function Invoke-Run([string]$How, [hashtable]$Env = @{}, [string[]]$Arguments = @(), [string]$Script = $installer) {
    $vars = @{ LOCALAPPDATA = $script:local; DVM_BASE_URL = (FileUrl $base); DVM_LATEST_URL = (FileUrl (Join-Path $latest 'VERSION')); DVM_REF = $null }
    foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }
    $saved = @{}
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    try {
        $ErrorActionPreference = 'Continue'
        switch ($How) {
            'file'  { $o = & $shell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 }
            'iex'   { $o = & $shell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Raw -LiteralPath '$Script' | Invoke-Expression" 2>&1 }
            'dvm'   { $o = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Join-Path $script:dest 'lib') 'dvm.ps1') @Arguments 2>&1 }
            'clone' { $o = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $windowsDir 'dvm.ps1') @Arguments 2>&1 }
        }
        $script:code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $script:out = (@($o) | ForEach-Object { "$_" }) -join "`n"
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

function Test-Case([string]$Name, [scriptblock]$Condition) {
    if (& $Condition) { $script:pass++; Write-Host "ok       $Name" }
    else { $script:fail++; Write-Host "FAILED   $Name"; $script:out -split "`n" | ForEach-Object { Write-Host "    $_" } }
}

function Has([string]$Text) { $script:out.Contains($Text) }
function Installed-Ps1 { Join-Path (Join-Path $script:dest 'lib') 'dvm.ps1' }
function Installed-Version {
    $saved = $script:out, $script:code
    Invoke-Run 'dvm' @{} @('version')
    $v = $script:out.Trim()
    $script:out, $script:code = $saved
    $v
}
# Works <version>: installed with that version written into dvm.ps1, and
# nothing else done: no `dvm init`, no dvm cache.
function Works([string]$Version) {
    if ($script:code -ne 0) { return $false }
    if (-not (Test-Path -LiteralPath (Installed-Ps1)) -or -not (Test-Path -LiteralPath (Join-Path $script:dest 'dvm.cmd'))) { return $false }
    if (-not ([IO.File]::ReadAllText((Installed-Ps1)).Contains("`$DvmVersion = '$Version'"))) { return $false }
    ((Installed-Version) -eq "dvm $Version") -and -not (Has 'dvm manages') -and -not (Has 'No other .NET installs') -and
        -not (Test-Path -LiteralPath (Join-Path $script:local 'dvm'))
}
# Installed files: CRLF everywhere, a BOM on dvm.ps1 only.
function Converted {
    $ps1 = [IO.File]::ReadAllBytes((Installed-Ps1))
    $cmd = [IO.File]::ReadAllBytes((Join-Path $script:dest 'dvm.cmd'))
    $bom = ($ps1.Length -gt 3) -and $ps1[0] -eq 0xEF -and $ps1[1] -eq 0xBB -and $ps1[2] -eq 0xBF
    $cmdBom = ($cmd.Length -gt 3) -and $cmd[0] -eq 0xEF
    $lf = [regex]::IsMatch([Text.Encoding]::UTF8.GetString($cmd) + [Text.Encoding]::UTF8.GetString($ps1), "(?<!`r)`n")
    $bom -and -not $cmdBom -and -not $lf
}
function Nothing-Installed { -not (Test-Path -LiteralPath $script:dest) }

try {
    New-Case 'from-clone'; Invoke-Run 'file'
    Test-Case 'from-clone' { (Works $repoVersion) -and (Has "(from $windowsDir)") -and (Has "run 'dvm list'") -and (Converted) }

    New-Case 'iex-latest-release'; Invoke-Run 'iex'
    Test-Case 'iex-latest-release' { (Works '9.9.9') -and (Has 'Downloading dvm (v9.9.9)') -and (Has '(from avramovioan/dvm@v9.9.9)') -and (Converted) }

    New-Case 'iex-no-release-yet'; Invoke-Run 'iex' @{ DVM_LATEST_URL = (FileUrl (Join-Path $tmp 'missing')) }
    Test-Case 'iex-no-release-yet' { (Works '9.10.0') -and (Has 'Downloading dvm (master)') }

    New-Case 'iex-ref-variable'; Invoke-Run 'iex' @{ DVM_REF = 'feature/x' }
    Test-Case 'iex-ref-variable' { (Works '9.11.0') -and (Has '(from avramovioan/dvm@feature/x)') }

    $copyDir = Join-Path $tmp 'downloads'
    New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
    Copy-Item -LiteralPath $installer -Destination $copyDir
    New-Case 'downloaded-copy'; Invoke-Run 'file' @{} @('-Ref', 'v9.9.8') (Join-Path $copyDir 'install.ps1')
    Test-Case 'downloaded-copy' { (Works '9.9.8') -and (Has '(from avramovioan/dvm@v9.9.8)') -and (Converted) }

    New-Case 'reinstall'; Invoke-Run 'iex' @{ DVM_REF = 'v9.9.8' }; Invoke-Run 'iex'
    Test-Case 'reinstall' { (Works '9.9.9') -and (Has '(was 9.9.8, from avramovioan/dvm@v9.9.9)') -and -not (Has "run 'dvm list'") }

    New-Case 'iex-bad-ref'; Invoke-Run 'iex' @{ DVM_REF = 'v1;rm' }
    Test-Case 'iex-bad-ref' { (Has 'not a tag or branch name') -and (Nothing-Installed) }

    New-Case 'iex-unknown-ref'; Invoke-Run 'iex' @{ DVM_REF = 'nope' }
    Test-Case 'iex-unknown-ref' { (Has 'could not download') -and (Nothing-Installed) }

    New-Case 'iex-not-dvm'; Invoke-Run 'iex' @{ DVM_REF = 'broken' }
    Test-Case 'iex-not-dvm' { (Has 'is not part of dvm') -and (Nothing-Installed) }

    # dvm update
    New-Case 'update-to-latest'; Invoke-Run 'iex' @{ DVM_REF = 'v9.9.8' }; Invoke-Run 'dvm' @{} @('update')
    Test-Case 'update-to-latest' { (Works '9.9.9') -and (Has 'Updating dvm 9.9.8 to 9.9.9') -and (Has '(was 9.9.8, from avramovioan/dvm@v9.9.9)') -and (Converted) }

    New-Case 'update-already-latest'; Invoke-Run 'iex'; Invoke-Run 'dvm' @{} @('update')
    Test-Case 'update-already-latest' { (Works '9.9.9') -and (Has 'dvm 9.9.9 is the latest version') }

    New-Case 'update-newer-than-release'; Invoke-Run 'iex' @{ DVM_REF = 'master' }; Invoke-Run 'dvm' @{} @('update')
    Test-Case 'update-newer-than-release' { (Works '9.10.0') -and (Has 'dvm 9.10.0 is newer than the latest release (9.9.9)') }

    New-Case 'update-no-release'; Invoke-Run 'iex' @{ DVM_REF = 'v9.9.8' }
    Invoke-Run 'dvm' @{ DVM_LATEST_URL = (FileUrl (Join-Path $tmp 'missing')) } @('update')
    Test-Case 'update-no-release' { ($script:code -eq 1) -and (Has 'could not find the latest dvm release') -and ((Installed-Version) -eq 'dvm 9.9.8') }

    New-Case 'update-from-clone'; Invoke-Run 'clone' @{} @('update')
    Test-Case 'update-from-clone' { ($script:code -eq 0) -and (Has "runs from the git clone in $repoRoot") -and (Has 'git -C') }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
