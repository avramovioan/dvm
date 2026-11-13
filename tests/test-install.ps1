# Tests windows/install.ps1 in all the ways people run it: from a clone with
# -File, piped into Invoke-Expression like `irm ... | iex` (latest release,
# no release yet, $env:DVM_REF), and its errors. GitHub is replaced by
# file:// URLs, so this runs offline.
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
$installer = Join-Path (Join-Path $repoRoot 'windows') 'install.ps1'
$dvmPs1 = Join-Path (Join-Path $repoRoot 'windows') 'dvm.ps1'
$wantVersion = 'dvm ' + ([regex]::Match((Get-Content -LiteralPath $dvmPs1 -Raw), "\`$DvmVersion = '([^']+)'").Groups[1].Value)
$shell = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { 'powershell.exe' } else { (Get-Process -Id $PID).Path }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvm-install-tests-' + [guid]::NewGuid().ToString('N'))

function FileUrl([string]$Path) {   # [Uri]'/tmp/x' is a relative URI on Linux
    if ($isWin) { ([Uri]$Path).AbsoluteUri } else { 'file://' + ($Path -replace ' ', '%20') }
}

# A fake GitHub: <base>/<ref>/windows/{dvm.ps1,dvm.cmd} with LF line endings
# (what GitHub serves), and the "latest release" API answer.
$base = Join-Path $tmp 'github'
foreach ($ref in 'v9.9.9', 'master', 'feature/x', 'broken') {
    $dir = Join-Path (Join-Path $base $ref) 'windows'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($f in 'dvm.ps1', 'dvm.cmd') {
        $text = [IO.File]::ReadAllText((Join-Path (Join-Path $repoRoot 'windows') $f)) -replace "`r`n", "`n"
        if ($ref -eq 'broken') { $text = "<html>404</html>`n" }
        [IO.File]::WriteAllText((Join-Path $dir $f), $text)
    }
}
$latest = Join-Path $tmp 'latest.json'
[IO.File]::WriteAllText($latest, "{`n  `"url`": `"x`",`n  `"tag_name`": `"v9.9.9`"`n}`n")

$script:pass = 0
$script:fail = 0
$script:out = ''
$script:code = 0
$script:dest = ''

# How: 'file' runs install.ps1 -File; 'iex' pipes its text into Invoke-Expression.
function Invoke-Case([string]$Name, [string]$How, [hashtable]$Env = @{}, [string[]]$InstallerArgs = @()) {
    $local = Join-Path (Join-Path $tmp $Name) 'localappdata'
    New-Item -ItemType Directory -Force -Path $local | Out-Null
    $vars = @{ LOCALAPPDATA = $local; DVM_BASE_URL = (FileUrl $base); DVM_API_URL = (FileUrl $latest); DVM_REF = $null }
    foreach ($k in $Env.Keys) { $vars[$k] = $Env[$k] }
    $saved = @{}
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    try {
        $ErrorActionPreference = 'Continue'
        if ($How -eq 'file') {
            $o = & $shell -NoProfile -ExecutionPolicy Bypass -File $installer @InstallerArgs 2>&1
        } else {
            $cmd = "Get-Content -Raw -LiteralPath '$installer' | Invoke-Expression"
            $o = & $shell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
        }
        $script:code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $script:out = (@($o) | ForEach-Object { "$_" }) -join "`n"
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    $script:dest = Join-Path (Join-Path $local 'Programs') 'dvm'
}

function Test-Case([string]$Name, [scriptblock]$Condition) {
    if (& $Condition) { $script:pass++; Write-Host "ok       $Name" }
    else { $script:fail++; Write-Host "FAILED   $Name"; $script:out -split "`n" | ForEach-Object { Write-Host "    $_" } }
}

function Has([string]$Text) { $script:out.Contains($Text) }
function Installed-Ps1 { Join-Path (Join-Path $script:dest 'lib') 'dvm.ps1' }
function Works {
    if ($script:code -ne 0) { return $false }
    if (-not (Test-Path -LiteralPath (Installed-Ps1)) -or -not (Test-Path -LiteralPath (Join-Path $script:dest 'dvm.cmd'))) { return $false }
    # Installed, and nothing else done: no `dvm init`, no dvm cache.
    (Has "$wantVersion installed to") -and (Has "run 'dvm list'") -and -not (Has 'dvm manages') -and
        -not (Has 'No other .NET installs') -and -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $script:dest)) 'dvm'))
}
# Downloaded files: CRLF everywhere, a BOM on dvm.ps1 only.
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
    Invoke-Case 'from-clone' 'file'
    Test-Case 'from-clone' { (Works) -and (Has "(from $(Join-Path $repoRoot 'windows'))") }

    Invoke-Case 'iex-latest-release' 'iex'
    Test-Case 'iex-latest-release' { (Works) -and (Has 'Downloading dvm (v9.9.9)') -and (Has '(from avramovioan/dvm@v9.9.9)') -and (Converted) }

    Invoke-Case 'iex-no-release-yet' 'iex' @{ DVM_API_URL = (FileUrl (Join-Path $tmp 'missing.json')) }
    Test-Case 'iex-no-release-yet' { (Works) -and (Has 'Downloading dvm (master)') }

    Invoke-Case 'iex-ref-variable' 'iex' @{ DVM_REF = 'feature/x' }
    Test-Case 'iex-ref-variable' { (Works) -and (Has '(from avramovioan/dvm@feature/x)') }

    $copyDir = Join-Path $tmp 'downloads'
    New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
    Copy-Item -LiteralPath $installer -Destination $copyDir
    $installerSaved = $installer
    $installer = Join-Path $copyDir 'install.ps1'
    Invoke-Case 'downloaded-copy' 'file' @{} @('-Ref', 'master')
    $installer = $installerSaved
    Test-Case 'downloaded-copy' { (Works) -and (Has '(from avramovioan/dvm@master)') -and (Converted) }

    Invoke-Case 'iex-bad-ref' 'iex' @{ DVM_REF = 'v1;rm' }
    Test-Case 'iex-bad-ref' { (Has 'not a tag or branch name') -and (Nothing-Installed) }

    Invoke-Case 'iex-unknown-ref' 'iex' @{ DVM_REF = 'nope' }
    Test-Case 'iex-unknown-ref' { (Has 'could not download') -and (Nothing-Installed) }

    Invoke-Case 'iex-not-dvm' 'iex' @{ DVM_REF = 'broken' }
    Test-Case 'iex-not-dvm' { (Has 'is not part of dvm') -and (Nothing-Installed) }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
