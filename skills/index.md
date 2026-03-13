# ReinikeAI Bot - Skills Index

Use this file whenever you need the exact script path for a local skill.

Always invoke skills with:

`[CMD: powershell -File "path\to\script.ps1" -Arguments]`

## DuckSearch

- Purpose: lightweight web search with DuckDuckGo
- Script: `.\skills\DuckSearch\duck_search.ps1`
- Usage: `powershell -File ".\skills\DuckSearch\duck_search.ps1" -Query "search terms"`

## Outlook

- Purpose: Outlook mailbox automation
- Restricted: the orchestrator should not use this skill directly unless the workflow explicitly requires it
- Main scripts:
  - `.\skills\Outlook\check-outlook-emails.ps1`
  - `.\skills\Outlook\search-outlook-emails.ps1`
  - `.\skills\Outlook\send-outlook-email.ps1`
  - `.\skills\Outlook\delete-emails.ps1`
  - `.\skills\Outlook\list-folders.ps1`

## Telegram Sender

- Purpose: send Telegram messages and files
- Scripts:
  - `.\skills\Telegram_Sender\SendMessage.ps1`
  - `.\skills\Telegram_Sender\SendFile.ps1`

## OpenCode Tools

- Purpose: inspect OpenCode runtime state
- Script: `.\skills\opencode\OpenCode-Status.ps1`

## Playwright CLI

- Purpose: browser navigation, screenshots, downloads, and text extraction
- Classification: local orchestrator wrapper around browser automation
- Mandatory rule: use this wrapper only when the orchestrator itself needs a direct local browser helper
- Script: `.\skills\Playwright\playwright-nav.ps1`
- Usage: `powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action [Screenshot|GetContent|SearchGoogle|Download] -Url "URL" [-Out "PATH"]`
- OpenCode note: the OpenCode-side Playwright skill is separate from this local wrapper
