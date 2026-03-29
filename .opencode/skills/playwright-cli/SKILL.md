---
name: playwright-cli
description: Interactive browser automation with step-by-step commands. Use for clicking, typing, form filling, and multi-step workflows.
allowed-tools: Bash(cdp-cli:*), Bash(playwright-cli:*), Bash(playwright-nav:*)
---

# CDP CLI — Interactive Browser Control

## Quick Start

```bash
# Open a page (launches Chrome with your profile if needed)
node ./skills/Playwright/cdp-cli.js open https://youtube.com

# Get page elements
node ./skills/Playwright/cdp-cli.js snapshot

# Click element by ref
node ./skills/Playwright/cdp-cli.js click e3

# Type text
node ./skills/Playwright/cdp-cli.js type "hello world"

# Press key
node ./skills/Playwright/cdp-cli.js press Enter

# Fill input
node ./skills/Playwright/cdp-cli.js fill e5 "search query"

# Navigate
node ./skills/Playwright/cdp-cli.js goto https://google.com

# Screenshot
node ./skills/Playwright/cdp-cli.js screenshot ./archives/shot.png

# Wait
node ./skills/Playwright/cdp-cli.js wait 2000

# Scroll
node ./skills/Playwright/cdp-cli.js scroll 500
```

---

## All Commands

| Command | Description |
|---------|-------------|
| `open <url>` | Open URL (launches Chrome with your profile) |
| `snapshot` | Get page elements with refs (e1, e2, e3...) |
| `click <ref>` | Click element by ref |
| `type <text>` | Type text into focused element |
| `press <key>` | Press key (Enter, Tab, Escape, etc.) |
| `fill <ref> <text>` | Fill input field |
| `goto <url>` | Navigate to URL |
| `screenshot <file>` | Take full page screenshot |
| `eval <code>` | Evaluate JavaScript |
| `wait <ms>` | Wait milliseconds |
| `scroll <px>` | Scroll down |
| `back` | Go back |
| `forward` | Go forward |
| `reload` | Reload page |
| `url` | Get current URL |
| `title` | Get page title |
| `text` | Get page text content |

---

## How It Works

1. **Connects to Chrome via CDP** (port 9333)
2. **Uses your real Chrome profile** (dark mode, cookies, sessions)
3. **Interactive commands** like playwright-cli but connected to your browser

---

## Typical Workflow

```bash
# 1. Open page
node ./skills/Playwright/cdp-cli.js open https://example.com/login

# 2. Get elements
node ./skills/Playwright/cdp-cli.js snapshot

# 3. Fill form
node ./skills/Playwright/cdp-cli.js fill e1 "user@email.com"
node ./skills/Playwright/cdp-cli.js fill e2 "password"
node ./skills/Playwright/cdp-cli.js click e3

# 4. Wait for result
node ./skills/Playwright/cdp-cli.js wait 2000

# 5. Verify
node ./skills/Playwright/cdp-cli.js snapshot
node ./skills/Playwright/cdp-cli.js screenshot result.png
```

---

## Why CDP CLI?

| | CDP CLI | playwright-cli |
|---|---|---|
| **Profile** | ✅ Your real Chrome profile | ❌ Fresh profile |
| **Dark mode** | ✅ Preserved | ❌ Not preserved |
| **Cookies** | ✅ Available | ❌ Not available |
| **Commands** | ✅ Interactive | ✅ Interactive |
| **Connection** | CDP (port 9333) | New browser |

---

## Fallback: playwright-cli

For isolated sessions (no profile access needed):

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli click e3
playwright-cli close
```

---

## Bot Scripts

For automated social media drafts, use the PowerShell wrappers:

```powershell
# LinkedIn
powershell -File ".\skills\Playwright\Invoke-LinkedInDraft.ps1" -TaskFile "task.txt"

# X.com
powershell -File ".\skills\Playwright\Invoke-XDraft.ps1" -TaskFile "task.txt"
```

---

## When to Use What

| Task Type | Tool |
|-----------|------|
| Screenshot, GetContent, Download | `playwright-nav.ps1` |
| Search Google | `playwright-nav.ps1` |
| Interactive form filling | `cdp-cli.js` |
| Social media drafts | `Invoke-XDraft.ps1` / `Invoke-LinkedInDraft.ps1` |
| Keep browser open for user | `playwright-nav.ps1 -Action KeepOpen` |
