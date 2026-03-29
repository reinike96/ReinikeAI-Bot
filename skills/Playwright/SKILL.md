# Skill: Playwright CLI

**Purpose:** Browser automation for cases where a real browser is required, not a default tool for public-site research.

## Core Commands

### 1. SEARCH GOOGLE (MOST RECOMMENDED)
Use this for **ANY** Google search. It is human-like and bypasses CAPTCHAs.
- **URL:** Pass ONLY the search query text (e.g., "zapatillas"), NOT a Google URL
- **Example:** `powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action SearchGoogle -Url "zapatillas" -Out "C:\path\to\repo\archives\results.png"`

### 2. TAKE SCREENSHOT (FOR SPECIFIC SITES)
`powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action Screenshot -Url "https://example.com" -Out "C:\path\to\repo\archives\capture.png"`

### 3. EXTRACT CONTENT (TEXT ONLY)
`powershell -File ".\skills\Playwright\playwright-nav.ps1" -Action GetContent -Url "https://example.com" -Stealth`

### 4. INTERACTIVE SOCIAL DRAFTS
Use these local wrappers for logged-in social composition workflows that must leave the browser open with the draft ready:
- LinkedIn: `powershell -File ".\skills\Playwright\Invoke-LinkedInDraft.ps1" -TaskFile "C:\path\to\task.txt"`
- X.com: `powershell -File ".\skills\Playwright\Invoke-XDraft.ps1" -TaskFile "C:\path\to\task.txt"`
- Generic website workflow: `powershell -File ".\skills\Playwright\Invoke-WebInteractive.ps1" -TaskFile "C:\path\to\task.txt"`

---

## 🚨 MANDATORY RULES FOR REINIKEAI (ORCHESTRATOR) 🚨

1. **Prefer the configured profile directories:** the skill reads browser paths from the shared config layer.
2. **USE SEARCHGOOGLE ACTION:** Never navigate to search URLs directly. Use `-Action SearchGoogle`.
3. **ABSOLUTE PATHS:** Always provide full paths for `-Out` (for example, `C:\path\to\repo\archives\screenshot.png`).
4. **NO "GETSCREENSHOT":** The correct action is `Screenshot` (though we now handle "GetScreenshot" as an alias, try to be precise).
5. **BE PATIENT:** Persistent browser startup can take time. Do not use aggressive timeouts.
6. **NO CONFLICT:** This works even if you have Chrome open. Feel free to use it.
7. **DO NOT RESET PROFILES:** Never delete or manually reset the configured persistent Playwright profile directory.
8. **SESSION REUSE:** The local browser session is expected to stay open and be reused across related actions unless `browser.keepOpen` is explicitly disabled in config.
9. **DO NOT CLAIM SUCCESS WITHOUT VERIFICATION:** For interactive UI workflows, only report success after verifying the modal/editor is visible and the expected text is actually present.
10. **RESEARCH FIRST:** If the task is to discover the latest post, inspect a public site, or find data hidden in scripts/feeds/assets, do not jump to Playwright. Prefer fetch/HTML/JS/RSS/JSON inspection first, then use Playwright only for the final interaction step if still needed.
11. **DO NOT GUESS ROUTES:** Before trying `/blog`, `/insights`, language paths, or other guessed URLs, inspect the root page and its raw HTML first.
12. **SPA RULE:** If the site behaves like a shell page or dynamic app, look for referenced JS/data assets and fetch targets before opening a browser.
13. **WEBFETCH IS FINE:** For discovery work, `WebFetch` is acceptable when it is the simplest reliable way to inspect the page or asset before moving to Playwright.
14. **DO NOT KEEP HUGE ASSETS IN CONTEXT:** If a JS/JSON asset is large or truncated, do not keep reading it linearly inside model context. Save it to a temporary file and search/filter that file for the needed titles, dates, slugs, keys, or URLs.

---

### Troubleshooting Common LLM Errors:
- If you forget `-Out`, the script will save to a default location in `archives\`.
- If you use a Google Search URL instead of an action, the script will automatically redirect it to `SearchGoogle`.
- **IMPORTANT:** If you already have a Google search URL (like `https://google.com/search?q=zapatillas`), use `Screenshot` action instead of `SearchGoogle` to avoid conflicts.
- If you use `GetScreenshot`, the script will automatically alias it to `Screenshot`.

---

## ⚠️ CRITICAL: Chrome Connection Pattern (Custom Scripts)

When writing **custom Playwright scripts** (outside the standard skill commands), follow this pattern to avoid breaking browser state:

### ❌ WRONG - Launches new Chrome (loses dark mode, cookies, session):
```javascript
const browser = await chromium.launchPersistentContext(profileDir, {
    headless: false,
    executablePath: chromeExecutable,
    args: ['--no-first-run'],
});
```

### ✅ CORRECT - Connects to existing Chrome via CDP:
```javascript
// Step 1: Ensure Chrome is running with remote debugging
await ensureManagedChrome({
    chromeExecutable,
    userDataDir: launchProfile.userDataDir,
    profileDirectory: launchProfile.profileDirectory,
    debugPort: 9333,
    startUrl: videoUrl,
});

// Step 2: Connect via CDP
const browser = await chromium.connectOverCDP('http://127.0.0.1:9333');
const context = browser.contexts()[0];
```

### Why this matters:
- `launchPersistentContext` creates a **new Chrome instance** without your real profile state
- `connectOverCDP` connects to Chrome **with your profile** (dark mode, cookies, logged-in sessions)
- YouTube, Google, and other sites behave differently without proper cookies/session

### Reference:
- See `archives/extract-transcript.js` for a working example
- The `browser-helper.js` already implements this correctly via `ensureManagedChrome()` + `connectToManagedBrowser()`
