@echo off
rem dvm - .NET SDK version manager for Windows.
rem Starts dvm.ps1 with Windows PowerShell (built into Windows), so `dvm` works
rem from PowerShell and cmd alike without changing the script execution policy.
setlocal
set "DVM_PS1=%~dp0lib\dvm.ps1"
if not exist "%DVM_PS1%" set "DVM_PS1=%~dp0dvm.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DVM_PS1%" %*
exit /b %ERRORLEVEL%
