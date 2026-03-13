# Telegram Sender Skill

This skill sends text messages and files through the Telegram Bot API.

## Files

- `SendMessage.ps1`
- `SendFile.ps1`

## Requirements

1. PowerShell 5.1 or newer
2. Internet access
3. A valid Telegram bot token configured in `config/settings.json` or environment variables

## Configuration

The scripts read their settings from:

- `config/settings.json`
- or environment variables such as `TELEGRAM_BOT_TOKEN` and `TELEGRAM_DEFAULT_CHAT_ID`

## Commands

Send a message:

```powershell
.\SendMessage.ps1 -Message "Your message"
```

Send a file:

```powershell
.\SendFile.ps1 -FilePath "C:\path\to\file.pdf"
```

## Parameters

### SendMessage.ps1

- `Message`: required text to send
- `Caption`: optional switch if the message should also be reused as a caption in a larger workflow
- `ChatId`: optional target chat ID; falls back to configured default chat ID
- `Buttons`: optional inline keyboard data

### SendFile.ps1

- `FilePath`: required file path
- `Caption`: optional file caption
- `ChatId`: optional target chat ID; falls back to configured default chat ID

## Notes

- Telegram text messages are split automatically when they exceed the API size limit.
- File sending is limited by Telegram's size rules.
- Use absolute paths for file delivery.
