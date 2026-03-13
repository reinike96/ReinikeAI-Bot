@echo off
chcp 65001 > nul
title ReinikeAI Bot v5 - Orchestrator

set PWSH=
if exist "C:\Program Files\PowerShell\7\pwsh.exe" set PWSH=C:\Program Files\PowerShell\7\pwsh.exe
if exist "C:\Program Files\PowerShell\7-preview\pwsh.exe" if not defined PWSH set PWSH=C:\Program Files\PowerShell\7-preview\pwsh.exe
if not defined PWSH set PWSH=powershell.exe

"%PWSH%" -ExecutionPolicy Bypass -Command "& '.\Logo.ps1'; & '.\TelegramBot.ps1'"

:loop
echo [+] The bot stopped. Restarting in 3 seconds... (Press Ctrl+C to cancel)
timeout /t 3
echo [+] Starting Telegram bot...
"%PWSH%" -ExecutionPolicy Bypass -Command "& '.\Logo.ps1'; & '.\TelegramBot.ps1'"
goto loop
