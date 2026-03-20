# ReinikeAI Bot - Skills Index

Use this file whenever you need the exact script path for a local skill.

Always invoke skills with:

`[CMD: powershell -File "path\to\script.ps1" -Arguments]`

## Classification Rules

- `orchestrator-only`: use directly from the orchestrator when the skill is short, deterministic, and has a clear input/output contract
- `OpenCode-preferred`: delegate through OpenCode when the skill requires multiple steps, intermediate validation, retries, branching, or complex navigation
- `hybrid`: the orchestrator may call a local wrapper for simple cases, but complex workflows should still be delegated to OpenCode

When adding a new skill, classify it before documenting it here.

## DuckSearch

- Purpose: lightweight web search with DuckDuckGo
- Classification: `orchestrator-only`
- Script: `.\skills\DuckSearch\duck_search.ps1`
- Usage: `powershell -File ".\skills\DuckSearch\duck_search.ps1" -Query "search terms"`

## Outlook

- Purpose: Outlook mailbox automation
- Classification: `OpenCode-preferred`
- Restricted: prefer delegating through OpenCode when the workflow involves multiple checks, selections, or side effects
- Main scripts:
  - `.\skills\Outlook\check-outlook-emails.ps1`
  - `.\skills\Outlook\search-outlook-emails.ps1`
  - `.\skills\Outlook\send-outlook-email.ps1`
  - `.\skills\Outlook\delete-emails.ps1`
  - `.\skills\Outlook\list-folders.ps1`

## Windows-Use

- Purpose: bounded Windows GUI automation with the Python `windows-use` agent
- Classification: `hybrid`
- Restricted: prefer explicit, bounded desktop tasks and require confirmation before execution
- Script: `.\skills\Windows_Use\Invoke-WindowsUse.ps1`
- Usage: `powershell -File ".\skills\Windows_Use\Invoke-WindowsUse.ps1" -Task "Open Notepad and type hello"`

## Telegram Sender

- Purpose: send Telegram messages and files
- Classification: `orchestrator-only`
- Scripts:
  - `.\skills\Telegram_Sender\SendMessage.ps1`
  - `.\skills\Telegram_Sender\SendFile.ps1`

## OpenCode Tools

- Purpose: inspect OpenCode runtime state
- Classification: `orchestrator-only`
- Script: `.\skills\opencode\OpenCode-Status.ps1`

## System Diagnostics

- Purpose: collect a quick local Windows health snapshot
- Classification: `orchestrator-only`
- Script: `.\skills\System_Diagnostics\Get-SystemSnapshot.ps1`
- Usage: `powershell -File ".\skills\System_Diagnostics\Get-SystemSnapshot.ps1" [-IncludeProcesses] [-IncludePorts]`

## File Tools

- Purpose: package files into a zip archive or list recent generated files
- Classification: `orchestrator-only`
- Scripts:
  - `.\skills\File_Tools\Pack-Files.ps1`
  - `.\skills\File_Tools\List-RecentFiles.ps1`

## CSV Tools

- Purpose: inspect CSV schema, row counts, missing values, and sample rows
- Classification: `orchestrator-only`
- Script: `.\skills\Csv_Tools\Inspect-Csv.ps1`
- Usage: `powershell -File ".\skills\Csv_Tools\Inspect-Csv.ps1" -Path ".\archives\data.csv"`

## Cron Tasks

- Purpose: register, list, run, and remove Windows Task Scheduler automations
- Classification: `hybrid`
- Scripts:
  - `.\skills\Cron_Tasks\Register-ScheduledAutomation.ps1`
  - `.\skills\Cron_Tasks\List-ScheduledAutomations.ps1`
  - `.\skills\Cron_Tasks\Start-ScheduledAutomation.ps1`
  - `.\skills\Cron_Tasks\Remove-ScheduledAutomation.ps1`
- Routing rule: use directly for deterministic scheduler operations, but ask OpenCode to create the automation script first when the workflow itself is complex

## Playwright CLI

- Purpose: browser navigation, screenshots, downloads, and text extraction
- Classification: `hybrid`
- Mandatory rule: use this wrapper only when the orchestrator itself needs a direct local browser helper for a simple action
- Script: `.\skills\Playwright\playwright-nav.ps1`
- Usage: `powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action [Screenshot|GetContent|SearchGoogle|Download] -Url "URL" [-Out "PATH"]`
- OpenCode note: the OpenCode-side Playwright skill is separate from this local wrapper and should be preferred for multi-step browser workflows
