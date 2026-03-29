---
name: youtube-transcript
description: Extract transcripts from YouTube videos. Use when user provides a YouTube URL and wants the transcript or summary of a video.
allowed-tools: Bash(node ./skills/Playwright/cdp-cli.js:*)
---

# YouTube Transcript Extractor

## When to Use

Use this skill when:
- User provides a YouTube URL and wants a transcript
- User asks to "summarize this video" or "extract content from YouTube"
- User wants to analyze video content

## Quick Method (Single Command)

Use the browser agent to extract transcripts:

```
Use the @browser agent to extract the transcript from this YouTube video: [URL]
```

## Manual Method (Step by Step)

If you need to do it manually, follow these exact steps:

### Step 1: Open the video
```bash
node ./skills/Playwright/cdp-cli.js open "YOUTUBE_URL"
```

### Step 2: Pause the video (IMPORTANT - prevents audio)
```bash
node ./skills/Playwright/cdp-cli.js eval "document.querySelector('#movie_player')?.pauseVideo?.() || document.querySelector('video')?.pause()"
```

### Step 3: Click transcript button
```bash
node ./skills/Playwright/cdp-cli.js eval "(() => { const btns = document.querySelectorAll('button'); for (const b of btns) { const t = (b.innerText || '').toLowerCase(); if (t.includes('transcrip')) { b.click(); return 'Clicked'; }} return 'Not found'; })()"
```

### Step 4: Wait for panel
```bash
node ./skills/Playwright/cdp-cli.js wait 2000
```

### Step 5: Extract transcript
```bash
node ./skills/Playwright/cdp-cli.js eval "(() => { const segs = document.querySelectorAll('ytd-transcript-segment-renderer'); if (segs.length > 0) { return Array.from(segs).map(s => s.innerText).join(' '); } const panel = document.querySelector('ytd-engagement-panel-section-list-renderer'); return panel ? panel.innerText : 'No transcript'; })()"
```

### Step 6: Close browser
```bash
node ./skills/Playwright/cdp-cli.js close
```

## Important Notes

- **Always pause the video first** to prevent audio playback
- **Always close the browser** when done with `cdp-cli.js close`
- The video must have captions/transcript enabled
- Works with auto-generated and manual transcripts
