# Runs the shared test cases (tests/cases.txt) against windows/dvm.ps1.
#   powershell -ExecutionPolicy Bypass -File tests\run-windows.ps1
#   pwsh -File tests/run-windows.ps1            (PowerShell 7, any OS)
# Uses Windows PowerShell 5.1 for dvm when it exists, otherwise pwsh.
# Works offline: release data comes from tests/fixtures/cache.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dvm = Join-Path (Join-Path (Split-Path -Parent $here) 'windows') 'dvm.ps1'
$shell = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { 'powershell.exe' } else { 'pwsh' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('dvm-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

function New-FakeRoot([string]$Root) {
    foreach ($line in Get-Content -LiteralPath (Join-Path (Join-Path $here 'fixtures') 'root.txt')) {
        $f = @($line -split '\s+' | Where-Object { $_ })
        if ($f.Count -lt 2 -or $f[0].StartsWith('#')) { continue }
        if ($f[0] -eq 'sdk') {
            $dir = Join-Path (Join-Path $Root 'sdk') $f[1]
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $json = "{`n  `"runtimeOptions`": {`n    `"framework`": {`n      `"name`": `"Microsoft.NETCore.App`",`n      `"version`": `"$($f[2])`"`n    }`n  }`n}`n"
            [IO.File]::WriteAllText((Join-Path $dir 'dotnet.runtimeconfig.json'), $json)
        } elseif ($f[0] -eq 'dir') {
            New-Item -ItemType Directory -Force -Path (Join-Path $Root $f[1]) | Out-Null
        }
    }
}

$pass = 0
$fail = 0
try {
    foreach ($line in Get-Content -LiteralPath (Join-Path $here 'cases.txt')) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $name, $argText = $line -split '\|', 2
        $caseDir = Join-Path $tmp $name
        $root = Join-Path $caseDir 'root'
        $cache = Join-Path $caseDir 'cache'
        $state = Join-Path $caseDir 'state'
        New-Item -ItemType Directory -Force -Path $root, $cache, $state | Out-Null
        Copy-Item -Path (Join-Path (Join-Path (Join-Path $here 'fixtures') 'cache') '*.json') -Destination $cache
        Copy-Item -Path (Join-Path (Join-Path (Join-Path $here 'fixtures') 'state') '*') -Destination $state
        New-FakeRoot $root

        $env:DVM_ROOT = $root; $env:DVM_CACHE = $cache; $env:DVM_STATE = $state
        $env:DVM_OFFLINE = '1'; $env:DVM_NO_DETECT = '1'; $env:NO_COLOR = '1'
        $argList = @($argText -split ' ' | Where-Object { $_ })
        $ErrorActionPreference = 'Continue'
        $output = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $dvm @argList 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $output += "exit=$code"
        if ($name.StartsWith('uninstall-')) {
            $output += '--- folders left:'
            $prefix = $root.Length + 1
            [string[]]$left = @(Get-ChildItem -LiteralPath $root -Recurse -Directory |
                ForEach-Object { $_.FullName.Substring($prefix).Replace('\', '/') })
            [Array]::Sort($left, [StringComparer]::Ordinal)   # same order as LC_ALL=C sort
            $output += $left
        }
        if ($name -like '*-runtime-*') {
            $output += '--- kept runtimes:'
            $kept = Join-Path $state 'runtimes'
            if (Test-Path -LiteralPath $kept) { $output += @(Get-Content -LiteralPath $kept | Where-Object { $_ }) }
        }
        # Paths below the fake root are compared with / on every OS.
        $actual = (($output | ForEach-Object {
            $l = $_.Replace($root, '<ROOT>')
            if ($l.Contains('<ROOT>')) { $l = $l.Replace('\', '/') }
            $l
        }) -join "`n").TrimEnd()

        $expectedFile = Join-Path (Join-Path $here 'expected') "$name.txt"
        $expected = if (Test-Path -LiteralPath $expectedFile) { ([IO.File]::ReadAllText($expectedFile) -replace "`r`n", "`n").TrimEnd() } else { $null }
        if ($actual -ceq $expected) {
            $pass++; Write-Host "ok       $name"
        } else {
            $fail++; Write-Host "FAILED   $name"
            $exp = if ($null -eq $expected) { @() } else { @($expected -split "`n") }
            $act = @($actual -split "`n")
            $n = [math]::Max($exp.Count, $act.Count)
            for ($i = 0; $i -lt $n; $i++) {
                $e = if ($i -lt $exp.Count) { $exp[$i] } else { '<missing>' }
                $a = if ($i -lt $act.Count) { $act[$i] } else { '<missing>' }
                if ($e -cne $a) { Write-Host "    line $($i + 1)"; Write-Host "      expected: $e"; Write-Host "      actual:   $a" }
            }
        }
    }
} finally {
    foreach ($v in 'DVM_ROOT', 'DVM_CACHE', 'DVM_STATE', 'DVM_OFFLINE', 'DVM_NO_DETECT', 'NO_COLOR') { Remove-Item "env:$v" -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "$pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
