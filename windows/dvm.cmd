@echo off
rem dvm - .NET SDK and runtime version manager for Windows.
rem Starts dvm.ps1 with Windows PowerShell (built into Windows), so `dvm` works
rem from PowerShell and cmd alike without changing the script execution policy.
rem PowerShell and the exit are on one line on purpose: `dvm update` replaces
rem this file while it runs, and cmd.exe reads batch files line by line.
rem `if errorlevel N` (N or higher) is checked when it runs, so dvm's exit
rem code (0, 1 or 2) is passed on; %ERRORLEVEL% would be read before
rem PowerShell starts.
setlocal
set "DVM_PS1=%~dp0lib\dvm.ps1"
if not exist "%DVM_PS1%" set "DVM_PS1=%~dp0dvm.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DVM_PS1%" %* & if errorlevel 2 (exit /b 2) else if errorlevel 1 (exit /b 1) else exit /b 0
