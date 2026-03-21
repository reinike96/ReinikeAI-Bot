---
name: playwright
description: Browser-required interaction and screenshots using Playwright when fetch, HTML, JSON, RSS, or static asset inspection is not enough.
---

## How to use

## When NOT to use this skill

Do not use this skill just because a task mentions a website.

Use fetch-style inspection or direct HTTP retrieval first when the task is about:
- finding the latest post/article/item on a site
- discovering feeds, scripts, JSON, RSS, sitemap, or hidden endpoints
- extracting text from a public page that does not require interaction
- researching a site before later doing a browser action

For public-site discovery:
- never guess multiple likely routes before inspecting the root page
- when using fetch or WebFetch, inspect the current page structure before deriving more URLs
- fetch raw HTML before markdown/text summaries when scripts or asset references may matter
- if the site is an SPA or looks dynamically rendered, inspect referenced JS/JSON/data files before using Playwright

If a task mixes research and browser interaction, do the research first without this skill. Only switch to Playwright after the needed URL, text, or target page is known and a real browser action is still required.

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

## Interactive Workflows

The generic `playwright-nav.ps1` wrapper is for content extraction, screenshots, downloads, and simple searches.

For logged-in or multi-step UI workflows that require clicking, typing, leaving a draft open, or waiting for manual login, the repository also includes Playwright-based local helpers under `.\skills\Playwright\`.

Examples:
- `.\skills\Playwright\Invoke-LinkedInDraft.ps1`
- `.\skills\Playwright\Invoke-XDraft.ps1`
- `.\skills\Playwright\Invoke-WebInteractive.ps1`

Do not assume Playwright in this repo is read-only. If a task truly needs interaction on a website, prefer a Playwright-based workflow before Windows desktop control. But do not treat Playwright as the default tool for website research or latest-item discovery.

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
- Do not use this skill for public-site research/discovery if fetch/WebFetch/HTML/JS/RSS/JSON inspection can answer the question.
- Use `GetContent` for quick information extraction.
- Use `Screenshot` for visual validation or sites with dynamic content.
- For interactive website tasks, prefer local Playwright scripts/helpers before Windows-Use.
- Do not report success for an interactive UI task until the expected editor, text, or page state is visibly verified.
- If an error occurs with the browser profile, never delete the profile data.
