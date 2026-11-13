@echo off
rem dvm - .NET SDK and runtime version manager for Windows.
rem Starts dvm.ps1 with Windows PowerShell (built into Windows), so `dvm` works
rem from PowerShell and cmd alike without changing the script execution policy.
rem PowerShell and the exit are on one line on purpose: `dvm update` replaces
rem this file while it runs, and cmd.exe reads batch files line by line.
setlocal
set "DVM_PS1=%~dp0lib\dvm.ps1"
if not exist "%DVM_PS1%" set "DVM_PS1=%~dp0dvm.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DVM_PS1%" %* & exit /b
