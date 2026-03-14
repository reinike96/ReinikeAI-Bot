---
name: cron-tasks
description: Register, list, run, and remove Windows Task Scheduler automations for ReinikeAI when the user wants recurring or startup-triggered local automations.
---

# Cron Tasks

Use this skill when the user wants a scheduled local automation through Windows Task Scheduler.

This skill is `hybrid`:

- use it directly for deterministic task registration, listing, running, or removal
- use OpenCode first if the user needs a new automation script to be authored before scheduling it

## Register a scheduled automation

```powershell
powershell -File ".\skills\Cron_Tasks\Register-ScheduledAutomation.ps1" -TaskName "DailyEmailReport" -ScriptPath ".\crons\reporte-emails\reporte-emails.ps1" -Schedule Daily -Time "09:00"
```

## List scheduled automations

```powershell
powershell -File ".\skills\Cron_Tasks\List-ScheduledAutomations.ps1"
```

## Run one now

```powershell
powershell -File ".\skills\Cron_Tasks\Start-ScheduledAutomation.ps1" -TaskName "DailyEmailReport"
```

## Remove one

```powershell
powershell -File ".\skills\Cron_Tasks\Remove-ScheduledAutomation.ps1" -TaskName "DailyEmailReport"
```

## Rules

- Keep scheduled scripts inside `crons/` when they are part of the project.
- If a new recurring automation requires multiple steps or custom logic, ask OpenCode to create the script first, then register it with this skill.
- Treat task creation and deletion as sensitive operations and require confirmation.
