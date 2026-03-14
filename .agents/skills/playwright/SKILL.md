---
name: playwright
description: Web navigation, text extraction and screenshots using Playwright CLI with browser profile support.
---

## How to use

For any navigation task, use the PowerShell script located in the project folder:

```bash
powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action [GetContent|Screenshot|Download|SearchGoogle|GoogleTopResultsScreenshots] -Url "URL" [-Out "OUTPUT_PATH"]
```

## Available Actions

1. **GetContent**: Extracts clean text from a page. No `-Out` required.
2. **Screenshot**: Captures full page screenshot. Requires `-Out` (e.g., `.\archives\screenshot.png`).
3. **Download**: Downloads a file. Requires `-Out` as destination folder (e.g., `.\archives`).
4. **SearchGoogle**: Navigates to Google and types a search query.
5. **GoogleTopResultsScreenshots**: Searches Google, opens the first 3 organic result links, and saves one screenshot per result into the output directory.
6. **Workplace**: Always use: `.\archives`

## Default Behavior

By default, the script uses **Chromium** with your **Chrome profile** (cookies, sessions, saved data).

If the action fails due to:
- Bot detection
- Cloudflare, Datadome, CAPTCHA protection
- Access denied

The script will automatically retry using the **Stealth mode** (Chrome with playwright-stealth evasions).

## Stealth Mode

The stealth mode activates:
- `playwright-stealth` evasions
- Random mouse movements and scrolls
- Variable delays between actions
- Visible browser (`headless: false`) for better reputation
- Uses the configured Chrome profile from the local bot settings

## Rules

- Always use absolute paths for `-Out`.
- Never use internal `playwright_*` tools. Always use the script above.
- Use `GetContent` for quick information extraction.
- Use `Screenshot` for visual validation or sites with dynamic content.
- If an error occurs with the browser profile, never delete the profile data.
