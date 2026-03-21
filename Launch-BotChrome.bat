@echo off
set PWSH=
if exist "C:\Program Files\PowerShell\7\pwsh.exe" set PWSH=C:\Program Files\PowerShell\7\pwsh.exe
if exist "C:\Program Files\PowerShell\7-preview\pwsh.exe" if not defined PWSH set PWSH=C:\Program Files\PowerShell\7-preview\pwsh.exe
if not defined PWSH set PWSH=powershell.exe

"%PWSH%" -ExecutionPolicy Bypass -File ".\Launch-BotChrome.ps1"
