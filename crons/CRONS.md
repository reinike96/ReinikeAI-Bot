# Scheduled Task System

This directory contains Windows Task Scheduler scripts used by ReinikeAI.

## Structure

```text
crons/
├── CRONS.md
├── registrar-tarea.ps1
├── ejemplos/
│   └── ejemplo-basico/
│       └── ejemplo-basico.ps1
└── logs/
```

## Adding a new scheduled script

1. Create a script inside `crons/`, for example `crons/my-task/my-task.ps1`.
2. Register it with the scheduler helper or the `Cron_Tasks` skill.

Example script:

```powershell
param(
    [string]$LogPath = "$PSScriptRoot\..\logs"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] Running scheduled task..."

# Your logic here

Write-Host "[$timestamp] Finished"
```

## Register a task manually

```powershell
.\registrar-tarea.ps1 -TaskName "MyTask" -ScriptPath "C:\path\to\my-task.ps1" -Schedule "Daily" -Time "09:00"
```

## Supported schedules

- `Once`
- `Daily`
- `Weekly`
- `Monthly`
- `AtStartup`
- `AtLogOn`

## List scheduled tasks

```powershell
Get-ScheduledTask | Where-Object { $_.TaskPath -like "*Reinike*" }
```

## Remove a scheduled task

```powershell
Unregister-ScheduledTask -TaskName "MyTask" -Confirm:$false
```

## Logs

Task logs can be written to `crons/logs/` if your scheduled scripts choose to use that folder.
