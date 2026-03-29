---
name: x-post
description: Publish posts to X (Twitter) with automatic character validation, emoji guidelines, and hashtag formatting. Use when user wants to post content to X.
allowed-tools: Bash(node:*), Bash(powershell:*), Read(*), Write(*), Edit(*)
category: social
---

# X (Twitter) Post Publisher

## When to Use

Use this skill when:
- User wants to publish content to X (Twitter)
- User asks to "post on X", "tweet", or "publish to Twitter"
- User provides content and wants it shared on X

## ⚠️ CRITICAL: "Do Not Publish" Mode

When the task includes constraints like:
- "No publiques todavía" (Don't publish yet)
- "Do not publish"
- "Solo devuelve el texto listo para revisión" (Just return the text ready for review)
- "Leave the draft ready with the Post button visible"

**YOU MUST:**
1. Put the content in the X compose box
2. Leave the Post button visible
3. **NOT click the Post button**
4. Return the `[PUBLISH_CONFIRMATION_REQUIRED]` marker
5. **STOP and wait for user confirmation**

Use the `-DraftOnly` switch:
```powershell
powershell -File "skills/Playwright/Invoke-XDraft.ps1" -TaskFile "archives/x-post-content.txt" -DraftOnly
```

This will output:
```
[PUBLISH_CONFIRMATION_REQUIRED]
Site: X (Twitter)
Task: powershell -File "skills/Playwright/Invoke-XDraft.ps1" -PublishOnly
Reason: Draft is ready and verified, awaiting user confirmation to publish
Screenshot: archives/x-post-draft.png
Content: <the draft content>
```

**⚠️ IMPORTANT: After returning this marker, the orchestrator MUST ask the user for confirmation before publishing. DO NOT automatically proceed to publish.**

### Publishing an Existing Draft

When you have a draft ready in the X compose box and need to click the Post button, use the `-PublishOnly` switch:

```powershell
powershell -File "skills/Playwright/Invoke-XDraft.ps1" -PublishOnly
```

This will:
1. Connect to the existing browser
2. Try multiple strategies to find and click the Post button:
   - Playwright click with multiple selectors
   - JavaScript click in page context
   - Keyboard shortcut (Ctrl+Enter, Enter)
3. Output `[POSTED]` on success
4. Generate debug files if it fails

**Use this instead of Windows-Use for clicking the Post button.**

### Debugging Failed Posts

If `[POST_FAILED]` appears, check these debug files:
- `archives/x-post-draft-debug.png` - Screenshot of page state
- `archives/x-post-draft-debug.html` - Full HTML of page

These files help diagnose why the Post button wasn't found.

## Post Requirements

### Language
- **Default language: English** unless user explicitly specifies another language
- Posts must be in the requested language

### Character Limit
- **Maximum: 280 characters** for single posts
- **Always validate character count** before publishing
- Use the validation script to check

### Emoji Guidelines
- **Use emojis moderately** (1-3 emojis per post)
- Place emojis at the beginning or end of sentences
- Common emojis: 🚀, ✨, 💡, 📢, 🔥, 📖, 🎯, ⚡, 🤖, 📊
- Avoid excessive emoji use (more than 4 looks spammy)

### Hashtag Guidelines
- **Include 2-4 relevant hashtags** per post
- Place hashtags at the end of the post
- Use specific, relevant hashtags (not generic ones like #follow)
- Common hashtags: #AI, #MachineLearning, #Automation, #Tech, #Innovation, #RPA

## Workflow

### Step 1: Prepare Post Content

Create the post content following the guidelines above. Example structure:
```
[Emoji] [Hook/Title]

[Main message - 1-2 sentences max]

[Call to action or link]

[Hashtags]
```

### Step 2: Validate Character Count

Create a temporary validation script:

```bash
node -e "
const post = \`YOUR_POST_CONTENT_HERE\`;
console.log('Post:', post);
console.log('Characters:', post.length, '/ 280');
console.log('Status:', post.length <= 280 ? 'VALID' : 'TOO LONG');
"
```

Or use a file:
```bash
node .opencode/skills/x-post/validate-chars.js "YOUR_POST_CONTENT_HERE"
```

### Step 3: Save Post Content

Save the validated content to a file:
```bash
# The content file should contain ONLY the post text
echo "YOUR_POST_CONTENT" > archives/x-post-content.txt
```

### Step 4: Execute Publishing Script

```powershell
powershell -File "skills/Playwright/Invoke-XDraft.ps1" -TaskFile "archives/x-post-content.txt"
```

### Step 5: Verify Publication

After the script outputs `[POSTED]`, verify the post was actually published:

**Option A: Screenshot Verification**
```bash
node ./skills/Playwright/cdp-cli.js screenshot archives/x-post-verification.png
```

**Option B: Navigate to Profile and Check**
```bash
# Navigate to the user's profile to see the latest post
node ./skills/Playwright/cdp-cli.js goto "https://x.com/YOUR_USERNAME"
node ./skills/Playwright/cdp-cli.js wait 2000
node ./skills/Playwright/cdp-cli.js screenshot archives/x-post-verification.png
```

**Option C: Check State File**
```bash
# Read the state file for publication status
cat archives/x-draft-state.json
```

### Step 6: Report Results

Report to the user:
- Post content (with character count)
- Publication status
- Verification method used
- Screenshot location (if applicable)

## Error Handling

### Login Required
If the script outputs `[LOGIN_REQUIRED]`:
1. The browser will stay open
2. User must log in manually
3. After login, re-run the publishing script

### Character Limit Exceeded
If validation shows > 280 characters:
1. Shorten the post
2. Remove unnecessary words
3. Use abbreviations if appropriate
4. Consider splitting into a thread (request user confirmation first)

### Post Button Not Found
If `[POST_FAILED]` appears:
1. Take a screenshot to diagnose
2. Check for overlay/popups blocking the button
3. Try dismissing cookie consent
4. Re-attempt the post

## Example Posts

### Research Paper Announcement
```
🚀 New Research: PixelSmile revolutionizes facial expression editing!

Breakthrough diffusion framework for fine-grained control while preserving identity. Perfect for marketing, gaming & film.

Read: https://reinikeai.com/#blog/paper-2603-25728

#AI #ComputerVision #DiffusionModels
```
(Characters: 280/280)

### Product Update
```
✨ New feature alert!

Our AI Translator now supports 50+ languages with context-aware translation.

Try it free: https://reinikeai.com/ai-translator/

#AI #Translation #Localization #Tech
```
(Characters: 156/280)

### Industry Insight
```
💡 RPA Tip: Automate before you optimize.

Start with the most repetitive tasks. Save 10+ hours/week with simple automation.

Book a consultation: https://reinikeai.com

#RPA #Automation #Productivity
```
(Characters: 168/280)

## Important Notes

- **Always validate character count** before publishing
- **Always verify publication** after the script completes
- **Keep the browser open** if user needs to make manual edits
- **Default to English** unless user specifies another language
- **Use emojis moderately** - quality over quantity
- **Include relevant hashtags** - 2-4 is optimal
- **Report the exact character count** to the user

## Files Reference

| File | Purpose |
|------|---------|
| `archives/x-post-content.txt` | Post content to publish |
| `archives/x-draft-state.json` | Publication state/status |
| `archives/x-post-draft.png` | Screenshot of draft |
| `archives/x-post-verification.png` | Screenshot after posting |
| `skills/Playwright/Invoke-XDraft.ps1` | Main publishing script |
| `skills/Playwright/x-post.js` | Node.js automation script |
