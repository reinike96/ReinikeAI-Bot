# Skill: Playwright CLI

**Purpose:** Browser automation using a configurable Chrome profile and a reusable Playwright profile.

## Core Commands

### 1. SEARCH GOOGLE (MOST RECOMMENDED)
Use this for **ANY** Google search. It is human-like and bypasses CAPTCHAs.
`powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action SearchGoogle -Url "search query" -Out "C:\path\to\repo\archives\results.png"`

### 2. TAKE SCREENSHOT (FOR SPECIFIC SITES)
`powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action Screenshot -Url "https://example.com" -Out "C:\path\to\repo\archives\capture.png"`

### 3. EXTRACT CONTENT (TEXT ONLY)
`powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action GetContent -Url "https://example.com" -Stealth`

---

## 🚨 MANDATORY RULES FOR REINIKEAI (ORCHESTRATOR) 🚨

1. **Prefer the configured profile directories:** the skill reads browser paths from the shared config layer.
2. **USE SEARCHGOOGLE ACTION:** Never navigate to search URLs directly. Use `-Action SearchGoogle`.
3. **ABSOLUTE PATHS:** Always provide full paths for `-Out` (for example, `C:\path\to\repo\archives\screenshot.png`).
4. **NO "GETSCREENSHOT":** The correct action is `Screenshot` (though we now handle "GetScreenshot" as an alias, try to be precise).
5. **BE PATIENT:** Persistent browser startup can take time. Do not use aggressive timeouts.
6. **NO CONFLICT:** This works even if you have Chrome open. Feel free to use it.
7. **DO NOT RESET PROFILES:** Never delete or manually reset the configured persistent Playwright profile directory.

---

### Troubleshooting Common LLM Errors:
- If you forget `-Out`, the script will save to a default location in `archives\`.
- If you use a Google Search URL instead of an action, the script will automatically redirect it to `SearchGoogle`.
- If you use `GetScreenshot`, the script will automatically alias it to `Screenshot`.
