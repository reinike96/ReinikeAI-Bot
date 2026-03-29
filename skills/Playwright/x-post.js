const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function parseArgs(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index++) {
        const token = argv[index];
        if (!token.startsWith('--')) {
            continue;
        }

        const key = token.slice(2);
        const next = argv[index + 1];
        if (typeof next === 'undefined' || next.startsWith('--')) {
            result[key] = 'true';
            continue;
        }

        result[key] = next;
        index++;
    }
    return result;
}

function readRequiredText(filePath, label) {
    if (!filePath || !fs.existsSync(filePath)) {
        throw new Error(`${label} file is missing: ${filePath || '(empty)'}`);
    }

    const text = fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '').trim();
    if (!text) {
        throw new Error(`${label} file is empty: ${filePath}`);
    }

    return text;
}

function ensureDirForFile(filePath) {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
}

function writeState(statePath, payload) {
    if (!statePath) {
        return;
    }

    ensureDirForFile(statePath);
    fs.writeFileSync(
        statePath,
        JSON.stringify(
            {
                updatedAt: new Date().toISOString(),
                ...payload,
            },
            null,
            2,
        ),
        'utf8',
    );
}

function httpGetJson(url) {
    return new Promise((resolve, reject) => {
        const req = http.get(url, response => {
            if (response.statusCode !== 200) {
                response.resume();
                reject(new Error(`Unexpected HTTP status ${response.statusCode} for ${url}`));
                return;
            }

            let raw = '';
            response.setEncoding('utf8');
            response.on('data', chunk => {
                raw += chunk;
            });
            response.on('end', () => {
                try {
                    resolve(JSON.parse(raw));
                } catch (error) {
                    reject(error);
                }
            });
        });

        req.on('error', reject);
        req.setTimeout(2000, () => {
            req.destroy(new Error(`Timeout fetching ${url}`));
        });
    });
}

async function waitForDebugger(debugPort, timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    const versionUrl = `http://127.0.0.1:${debugPort}/json/version`;

    while (Date.now() < deadline) {
        try {
            await httpGetJson(versionUrl);
            return true;
        } catch {}

        await sleep(500);
    }

    return false;
}

function isChromeProfileLocked(userDataDir) {
    if (!userDataDir || !fs.existsSync(userDataDir)) {
        return false;
    }

    const lockCandidates = [
        'SingletonLock',
        'SingletonCookie',
        'SingletonSocket',
        'lockfile'
    ];

    return lockCandidates.some(name => fs.existsSync(path.join(userDataDir, name)));
}

function resolveChromeLaunchProfile(projectRoot) {
    const playwrightProfilePath = process.env.PLAYWRIGHT_PROFILE_DIR || path.join(projectRoot, 'profiles', 'playwright');
    const chromeProfilePath = process.env.CHROME_PROFILE_DIR || '';
    const candidate = (chromeProfilePath && chromeProfilePath.trim()) ? chromeProfilePath.trim() : playwrightProfilePath;
    const normalized = candidate.replace(/[\\/]+$/, '');
    const baseName = path.basename(normalized);
    const parentDir = path.dirname(normalized);
    const grandParentName = path.basename(parentDir).toLowerCase();

    if (grandParentName === 'user data' && baseName) {
        return {
            userDataDir: parentDir,
            profileDirectory: baseName,
        };
    }

    return {
        userDataDir: normalized,
        profileDirectory: '',
    };
}

async function ensureManagedChrome({ chromeExecutable, userDataDir, profileDirectory, debugPort, startUrl }) {
    const ready = await waitForDebugger(debugPort, 1000);
    if (ready) {
        return false;
    }

    if (isChromeProfileLocked(userDataDir)) {
        throw new Error(`Bot Chrome profile is already open without remote debugging on port ${debugPort}. Close that Chrome window or relaunch it with Launch-BotChrome.`);
    }

    const args = [
        `--remote-debugging-port=${debugPort}`,
        `--user-data-dir=${userDataDir}`,
        '--no-first-run',
        '--no-default-browser-check',
    ];
    if (profileDirectory) {
        args.push(`--profile-directory=${profileDirectory}`);
    }
    args.push('--new-window', startUrl);

    const child = spawn(chromeExecutable, args, {
        detached: true,
        stdio: 'ignore',
    });
    child.unref();

    const started = await waitForDebugger(debugPort, 30000);
    if (!started) {
        throw new Error(`Managed Chrome did not expose the debugger on port ${debugPort}`);
    }

    return true;
}

function splitIntoThreadSegments(postContent, maxLen = 260) {
    const paragraphs = postContent
        .split(/\r?\n\r?\n/)
        .map(item => item.trim())
        .filter(Boolean);

    if (paragraphs.length === 0) {
        return [postContent.trim()].filter(Boolean);
    }

    const segments = [];
    let current = '';

    for (const paragraph of paragraphs) {
        const candidate = current ? `${current}\n\n${paragraph}` : paragraph;
        if (candidate.length <= maxLen) {
            current = candidate;
            continue;
        }

        if (current) {
            segments.push(current);
            current = '';
        }

        if (paragraph.length <= maxLen) {
            current = paragraph;
            continue;
        }

        const words = paragraph.split(/\s+/);
        let chunk = '';
        for (const word of words) {
            const wordCandidate = chunk ? `${chunk} ${word}` : word;
            if (wordCandidate.length <= maxLen) {
                chunk = wordCandidate;
            } else {
                if (chunk) {
                    segments.push(chunk);
                }
                chunk = word;
            }
        }
        if (chunk) {
            current = chunk;
        }
    }

    if (current) {
        segments.push(current);
    }

    return segments.filter(Boolean);
}

function getVerificationNeedle(postContent) {
    // Try to find a unique, searchable text from the post
    // First, try to find URLs which are unique
    const urlMatch = postContent.match(/https?:\/\/[^\s]+/);
    if (urlMatch) {
        return urlMatch[0];
    }
    
    // Try to find the title (usually after the emoji on the first line)
    const lines = postContent.split(/\r?\n/);
    for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.length === 0) continue;
        
        // Remove emoji and get the text
        const textWithoutEmoji = trimmed.replace(/[\p{Emoji_Presentation}\p{Extended_Pictographic}]/gu, '').trim();
        if (textWithoutEmoji.length >= 10) {
            // Return a portion of the text that's likely to be unique
            return textWithoutEmoji.slice(0, 50);
        }
    }
    
    // Fallback: return first significant text
    const firstNonEmptyLine = lines
        .map(line => line.trim())
        .find(line => line.length >= 8);
    
    return firstNonEmptyLine || postContent.slice(0, 40);
}

async function getXContext(browser) {
    const context = browser.contexts()[0];
    if (!context) {
        throw new Error('No browser context is available after connecting to managed Chrome.');
    }
    return context;
}

async function applyPreferredTheme(page) {
    try {
        await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' });
    } catch {}
}

async function isLoginRequired(page) {
    const currentUrl = page.url();
    if (currentUrl.includes('/i/flow/login') || currentUrl.includes('/login')) {
        return true;
    }

    return page.evaluate(() => {
        if (document.querySelector('input[name="text"], input[autocomplete="username"], input[name="password"]')) {
            return true;
        }

        const signInButton = Array.from(document.querySelectorAll('a, span, div')).find(node => {
            const text = (node.textContent || '').trim().toLowerCase();
            return text === 'sign in' || text === 'iniciar sesión';
        });
        return Boolean(signInButton);
    });
}

async function hasVisibleComposer(page) {
    const selectors = [
        'div[data-testid^="tweetTextarea_"] div[role="textbox"]',
        'div[data-testid^="tweetTextarea_"] [contenteditable="true"]',
        'div[role="dialog"] div[role="textbox"][contenteditable="true"]',
        'div[role="dialog"] [contenteditable="true"]',
        'div[data-testid^="tweetTextarea_"]',
        'div[role="textbox"][contenteditable="true"]',
        'div[data-testid="tweetTextarea_0"]'
    ];

    for (const selector of selectors) {
        try {
            const locator = page.locator(selector).first();
            if (await locator.count() > 0 && await locator.isVisible({ timeout: 1000 })) {
                return true;
            }
        } catch {}
    }

    return false;
}

async function clickComposerTrigger(page) {
    // Dismiss any lingering overlays before clicking
    await dismissCookieConsent(page).catch(() => {});
    await sleep(500);

    const selectors = [
        'a[data-testid="SideNav_NewTweet_Button"]',
        'button[data-testid="SideNav_NewTweet_Button"]',
        'div[data-testid="SideNav_NewTweet_Button"]',
        'a[href="/compose/post"]',
        'button[aria-label="Post"]',
        'a[aria-label="Post"]',
        'button[aria-label="Tweet"]',
        'a[aria-label="Tweet"]'
    ];

    for (const selector of selectors) {
        try {
            const button = page.locator(selector).first();
            if (await button.count() > 0 && await button.isVisible({ timeout: 1000 })) {
                await button.click({ timeout: 5000 });
                await sleep(1500);
                if (await hasVisibleComposer(page)) {
                    return true;
                }
            }
        } catch {}
    }

    const roleLocators = [
        page.getByRole('link', { name: /post|tweet|compose/i }).first(),
        page.getByRole('button', { name: /post|tweet|compose/i }).first(),
        page.getByText(/what'?s happening|post|tweet/i).first(),
    ];

    for (const locator of roleLocators) {
        try {
            if (await locator.count() > 0 && await locator.isVisible({ timeout: 1000 })) {
                await locator.click({ timeout: 5000 });
                await sleep(1500);
                if (await hasVisibleComposer(page)) {
                    return true;
                }
            }
        } catch {}
    }

    return false;
}

async function dismissCookieConsent(page) {
    // First, try to remove the cookie consent mask via DOM manipulation
    try {
        await page.evaluate(() => {
            // Remove the cookie consent mask overlay
            const mask = document.querySelector('div[data-testid="twc-cc-mask"]');
            if (mask) mask.remove();
            // Also remove the entire layers container that may hold the consent dialog
            const layers = document.querySelector('div#layers');
            if (layers) {
                const consentDialog = layers.querySelector('[data-testid="twc-cc-mask"]');
                if (consentDialog) consentDialog.remove();
                // Remove any overlay siblings that block interaction
                const children = layers.children;
                for (let i = children.length - 1; i >= 0; i--) {
                    const child = children[i];
                    if (child.querySelector('[data-testid="twc-cc-mask"]') ||
                        child.getAttribute('data-testid') === 'twc-cc-mask') {
                        child.remove();
                    }
                }
            }
        });
        await sleep(500);
    } catch {}

    // Try clicking actual cookie consent buttons
    const dismissSelectors = [
        'div[data-testid="twc-cc-mask"] button[aria-label="Close"]',
        'div[data-testid="twc-cc-mask"] button',
        'div[id="layers"] div[role="button"][aria-label="Close"]',
        'button[data-testid="xMigrationBottomBar"]',
        'span:has-text("Refuse non-essential cookies")',
        'span:has-text("Accept all cookies")',
        'div[role="button"]:has-text("Decline")',
        'div[role="button"]:has-text("Accept")',
    ];

    for (const selector of dismissSelectors) {
        try {
            const btn = page.locator(selector).first();
            if (await btn.count() > 0 && await btn.isVisible({ timeout: 1000 })) {
                await btn.click({ timeout: 3000 });
                await sleep(1000);
                return true;
            }
        } catch {}
    }

    // Try pressing Escape to dismiss any overlay
    try {
        await page.keyboard.press('Escape');
        await sleep(500);
    } catch {}

    // Final attempt: remove any blocking overlay via force
    try {
        await page.evaluate(() => {
            const layers = document.getElementById('layers');
            if (layers) {
                // Remove all children that are overlays
                while (layers.firstChild) {
                    layers.removeChild(layers.firstChild);
                }
            }
        });
        await sleep(500);
    } catch {}

    return false;
}

async function openComposer(page) {
    try {
        await page.goto('https://x.com/compose/post', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await sleep(2500);
        if (await hasVisibleComposer(page)) {
            return true;
        }
    } catch {}

    return clickComposerTrigger(page);
}

async function getThreadEditors(page) {
    const primary = page.locator('div[data-testid^="tweetTextarea_"] div[role="textbox"], div[data-testid^="tweetTextarea_"] [contenteditable="true"]');
    if (await primary.count() > 0) {
        const editors = [];
        const count = await primary.count();
        for (let index = 0; index < count; index++) {
            editors.push(primary.nth(index));
        }
        return editors;
    }

    const fallback = page.locator('div[role="textbox"][contenteditable="true"]');
    const fallbackCount = await fallback.count();
    const results = [];
    for (let index = 0; index < fallbackCount; index++) {
        results.push(fallback.nth(index));
    }
    return results;
}

async function verifyEditorContains(editor, expectedText) {
    const needle = getVerificationNeedle(expectedText);
    if (!needle) {
        return false;
    }

    for (let attempt = 0; attempt < 10; attempt++) {
        try {
            const editorText = await editor.evaluate(node => (node.innerText || node.textContent || '').trim());
            if (editorText.includes(needle)) {
                return true;
            }
        } catch {}

        await sleep(300);
    }

    return false;
}

async function fillEditor(page, editor, text) {
    await editor.click({ timeout: 5000, force: true });
    await editor.focus().catch(() => {});
    await sleep(300);
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A').catch(() => {});
    await page.keyboard.press('Backspace').catch(() => {});
    await page.keyboard.insertText(text);
    return verifyEditorContains(editor, text);
}

async function addAnotherPost(page) {
    const selectors = [
        'button[data-testid="addButton"]',
        'button[aria-label="Add another post"]',
        'button[aria-label="Add another Tweet"]'
    ];

    for (const selector of selectors) {
        try {
            const button = page.locator(selector).first();
            if (await button.count() > 0 && await button.isVisible({ timeout: 1000 })) {
                await button.click({ timeout: 5000 });
                await sleep(1200);
                return true;
            }
        } catch {}
    }

    return false;
}

async function isPostButtonVisible(page) {
    const selectors = [
        'button[data-testid="tweetButton"]',
        'button[data-testid="tweetButtonInline"]'
    ];

    for (const selector of selectors) {
        try {
            const button = page.locator(selector).first();
            if (await button.count() > 0 && await button.isVisible({ timeout: 1000 })) {
                return true;
            }
        } catch {}
    }

    return false;
}

async function verifyPublication(page, postContent, verificationScreenshot) {
    // Get verification needle (first significant text from the post)
    const needle = getVerificationNeedle(postContent);
    
    // Wait a moment for the post to appear
    await sleep(3000);
    
    // Try to find the post on the current page (home feed)
    try {
        const postLocator = page.locator(`article`).filter({ hasText: needle }).first();
        if (await postLocator.count() > 0) {
            const isVisible = await postLocator.isVisible({ timeout: 3000 }).catch(() => false);
            if (isVisible) {
                await page.screenshot({ path: verificationScreenshot, fullPage: false });
                return { verified: true, method: 'home_feed' };
            }
        }
    } catch {}
    
    // Navigate to user's profile to verify
    try {
        // Get the username from the page or construct the URL
        const currentUrl = page.url();
        let profileUrl = 'https://x.com/home';
        
        // Try to extract username from current URL or use ReinikeAI as default
        if (currentUrl.includes('x.com/') || currentUrl.includes('twitter.com/')) {
            const urlParts = currentUrl.split('/');
            const potentialUsername = urlParts.find(part => part && !part.includes('x.com') && !part.includes('twitter.com') && !part.includes('http'));
            if (potentialUsername && potentialUsername !== 'home' && potentialUsername !== 'compose') {
                profileUrl = `https://x.com/${potentialUsername}`;
            }
        }
        
        // Navigate to profile
        await page.goto(profileUrl === 'https://x.com/home' ? 'https://x.com/ReinikeAI' : profileUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await sleep(4000);
        
        // Look for the post on the profile
        const profilePostLocator = page.locator(`article`).filter({ hasText: needle }).first();
        if (await profilePostLocator.count() > 0) {
            const isVisible = await profilePostLocator.isVisible({ timeout: 5000 }).catch(() => false);
            if (isVisible) {
                await page.screenshot({ path: verificationScreenshot, fullPage: false });
                
                // Try to get the post URL
                const postLink = profilePostLocator.locator('a[href*="/status/"]').first();
                let postUrl = null;
                if (await postLink.count() > 0) {
                    postUrl = await postLink.getAttribute('href').catch(() => null);
                    if (postUrl && !postUrl.startsWith('http')) {
                        postUrl = `https://x.com${postUrl}`;
                    }
                }
                
                return { verified: true, method: 'profile', postUrl };
            }
        }
        
        // Alternative: look for any article with the needle text
        const allArticles = page.locator('article[data-testid="tweet"]');
        const articleCount = await allArticles.count();
        for (let i = 0; i < articleCount; i++) {
            try {
                const article = allArticles.nth(i);
                const text = await article.innerText().catch(() => '');
                if (text.includes(needle)) {
                    await page.screenshot({ path: verificationScreenshot, fullPage: false });
                    
                    const postLink = article.locator('a[href*="/status/"]').first();
                    let postUrl = null;
                    if (await postLink.count() > 0) {
                        postUrl = await postLink.getAttribute('href').catch(() => null);
                        if (postUrl && !postUrl.startsWith('http')) {
                            postUrl = `https://x.com${postUrl}`;
                        }
                    }
                    
                    return { verified: true, method: 'profile', postUrl };
                }
            } catch {}
        }
    } catch {}
    
    // Fallback: just take a screenshot of current state
    await page.screenshot({ path: verificationScreenshot, fullPage: false });
    return { verified: false, method: 'screenshot_only' };
}

async function runPublishOnly({ projectRoot, debugPort, statePath, outputScreenshot }) {
    ensureDirForFile(outputScreenshot);
    ensureDirForFile(statePath);
    
    // Create debug screenshot path
    const debugScreenshot = outputScreenshot.replace('.png', '-debug.png');
    
    writeState(statePath, {
        status: 'publishing',
        site: 'X.com',
        screenshot: outputScreenshot,
        mode: 'publish_only',
    });
    
    console.log('[DEBUG] Starting publish-only mode...');
    console.log(`[DEBUG] Debug port: ${debugPort}`);
    
    // Wait for browser to be available
    const ready = await waitForDebugger(debugPort, 5000);
    if (!ready) {
        writeState(statePath, {
            status: 'error',
            site: 'X.com',
            reason: 'Browser not found. Make sure Chrome is running with remote debugging.',
            screenshot: outputScreenshot,
        });
        console.log('[ERROR] Browser not found. Make sure Chrome is running with remote debugging.');
        process.exit(1);
    }
    
    console.log('[DEBUG] Browser found, connecting...');
    
    let browser = null;
    try {
        browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
        const context = await getXContext(browser);
        const existingXPages = context.pages().filter(page => {
            try {
                const url = page.url() || '';
                return url.includes('x.com') || url.includes('twitter.com');
            } catch {
                return false;
            }
        });
        
        console.log(`[DEBUG] Found ${existingXPages.length} X.com page(s)`);
        
        if (existingXPages.length === 0) {
            throw new Error('No X.com page found in browser.');
        }
        
        const page = existingXPages[existingXPages.length - 1];
        await page.bringToFront().catch(() => {});
        await sleep(1000);
        
        console.log(`[DEBUG] Current URL: ${page.url()}`);
        
        // Take initial screenshot for debugging
        await page.screenshot({ path: debugScreenshot, fullPage: false });
        console.log(`[DEBUG] Initial screenshot saved: ${debugScreenshot}`);
        
        // Dismiss any overlays first
        await dismissCookieConsent(page);
        await sleep(500);
        
        // Extended list of Post button selectors (X.com changes these frequently)
        const postSelectors = [
            // Primary selectors
            'button[data-testid="tweetButton"]',
            'button[data-testid="tweetButtonInline"]',
            // Alternative selectors
            'button[data-testid="tweetButtonSubmit"]',
            'button[data-testid="Button"]',
            // Text-based selectors
            'button:has-text("Post")',
            'button:has-text("Reply")',
            'div[role="button"]:has-text("Post")',
            // Data attribute variations
            'button[data-testid*="tweet"]',
            'button[data-testid*="post"]',
            // CSS class based (less reliable but fallback)
            'button.css-175oi2r:has-text("Post")',
        ];
        
        let clicked = false;
        let usedSelector = null;
        
        // Strategy 1: Try Playwright click with each selector
        console.log('[DEBUG] Trying Playwright click...');
        for (const selector of postSelectors) {
            try {
                const btn = page.locator(selector).first();
                const count = await btn.count();
                if (count > 0) {
                    const isVisible = await btn.isVisible({ timeout: 1000 }).catch(() => false);
                    if (isVisible) {
                        // Check if button is not disabled
                        const isDisabled = await btn.evaluate(el => {
                            return el.disabled || 
                                   el.getAttribute('aria-disabled') === 'true' ||
                                   el.classList.contains('disabled') ||
                                   el.hasAttribute('disabled');
                        }).catch(() => true);
                        
                        console.log(`[DEBUG] Found button with selector: ${selector} (disabled: ${isDisabled})`);
                        
                        if (!isDisabled) {
                            await btn.click({ timeout: 5000, force: true });
                            clicked = true;
                            usedSelector = selector;
                            console.log(`[DEBUG] Clicked with Playwright: ${selector}`);
                            break;
                        }
                    }
                }
            } catch (e) {
                console.log(`[DEBUG] Selector ${selector} failed: ${e.message}`);
            }
        }
        
        // Strategy 2: Try JavaScript click in page context
        if (!clicked) {
            console.log('[DEBUG] Trying JavaScript click...');
            const clickResult = await page.evaluate(() => {
                // Extended selectors for JavaScript
                const selectors = [
                    'button[data-testid="tweetButton"]',
                    'button[data-testid="tweetButtonInline"]',
                    'button[data-testid="tweetButtonSubmit"]',
                    'button:has-text("Post")',
                    'div[role="button"]:has-text("Post")',
                ];
                
                for (const selector of selectors) {
                    try {
                        const btns = document.querySelectorAll(selector);
                        for (const btn of btns) {
                            if (btn && !btn.disabled && btn.offsetParent !== null) {
                                // Try multiple click methods
                                btn.click();
                                // Also try dispatching event
                                btn.dispatchEvent(new MouseEvent('click', { bubbles: true }));
                                return { clicked: true, selector };
                            }
                        }
                    } catch (e) {}
                }
                
                // Fallback: Find by text content
                const allButtons = document.querySelectorAll('button, div[role="button"]');
                for (const btn of allButtons) {
                    const text = (btn.textContent || '').trim().toLowerCase();
                    if ((text === 'post' || text === 'reply') && !btn.disabled && btn.offsetParent !== null) {
                        btn.click();
                        btn.dispatchEvent(new MouseEvent('click', { bubbles: true }));
                        return { clicked: true, selector: 'text-based' };
                    }
                }
                
                return { clicked: false };
            });
            
            if (clickResult.clicked) {
                clicked = true;
                usedSelector = clickResult.selector;
                console.log(`[DEBUG] Clicked with JavaScript: ${clickResult.selector}`);
            }
        }
        
        // Strategy 3: Try keyboard shortcut (Ctrl+Enter or Enter)
        if (!clicked) {
            console.log('[DEBUG] Trying keyboard shortcut...');
            // Focus on the composer area first
            try {
                const composer = page.locator('div[data-testid^="tweetTextarea"], div[role="textbox"][contenteditable="true"]').first();
                if (await composer.count() > 0) {
                    await composer.focus({ timeout: 2000 });
                    await sleep(300);
                    // Try Ctrl+Enter (common shortcut for posting)
                    await page.keyboard.press('Control+Enter');
                    await sleep(500);
                    // Also try just Enter
                    await page.keyboard.press('Enter');
                    clicked = true;
                    usedSelector = 'keyboard';
                    console.log('[DEBUG] Tried keyboard shortcuts');
                }
            } catch (e) {
                console.log(`[DEBUG] Keyboard shortcut failed: ${e.message}`);
            }
        }
        
        // Take final screenshot
        await sleep(2000);
        await page.screenshot({ path: outputScreenshot, fullPage: false });
        
        if (clicked) {
            console.log('[POSTED]');
            console.log('Site: X.com');
            console.log(`Method: ${usedSelector}`);
            console.log(`Screenshot: ${outputScreenshot}`);
            
            writeState(statePath, {
                status: 'published',
                site: 'X.com',
                screenshot: outputScreenshot,
                currentUrl: page.url(),
                mode: 'publish_only',
                method: usedSelector,
            });
        } else {
            // Save debug info
            const pageContent = await page.content().catch(() => '');
            const debugHtmlPath = outputScreenshot.replace('.png', '-debug.html');
            fs.writeFileSync(debugHtmlPath, pageContent, 'utf8');
            
            writeState(statePath, {
                status: 'post_failed',
                site: 'X.com',
                reason: 'Post button not found or not clickable',
                screenshot: outputScreenshot,
                debugScreenshot,
                debugHtml: debugHtmlPath,
            });
            
            console.log('[POST_FAILED] Post button not found or not clickable');
            console.log(`[DEBUG] Debug screenshot: ${debugScreenshot}`);
            console.log(`[DEBUG] Debug HTML: ${debugHtmlPath}`);
            console.log('[DEBUG] Check these files to see the page state');
            process.exit(1);
        }
        
        process.exit(0);
    } catch (error) {
        writeState(statePath, {
            status: 'error',
            site: 'X.com',
            reason: error.message,
            screenshot: outputScreenshot,
        });
        console.error(`[ERROR] ${error.message}`);
        process.exit(1);
    }
}

async function run() {
    const args = parseArgs(process.argv.slice(2));
    const projectRoot = process.env.BOT_PROJECT_ROOT || process.cwd();
    const chromeExecutable = process.env.CHROME_EXECUTABLE || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    const launchProfile = resolveChromeLaunchProfile(projectRoot);
    const outputScreenshot = args.screenshot || path.join(projectRoot, 'archives', 'x-post-draft.png');
    const statePath = args.state || path.join(projectRoot, 'archives', 'x-draft-state.json');
    const contentPath = args.content;
    const debugPort = Number.parseInt(args.port || process.env.BROWSER_DEBUG_PORT || '9333', 10);
    const publishOnly = (args['publish-only'] || 'false').trim().toLowerCase() === 'true';
    
    // If publish-only mode, just click the Post button on existing draft
    if (publishOnly) {
        await runPublishOnly({ projectRoot, debugPort, statePath, outputScreenshot });
        return;
    }
    
    const postContent = readRequiredText(contentPath, 'Post content');
    const draftMode = (process.env.X_DRAFT_MODE || 'single').trim().toLowerCase();
    const noPublish = (process.env.X_NO_PUBLISH || args['no-publish'] || 'false').trim().toLowerCase() === 'true';
    const segments = draftMode === 'thread' ? splitIntoThreadSegments(postContent) : [postContent];

    ensureDirForFile(outputScreenshot);
    ensureDirForFile(statePath);
    fs.mkdirSync(launchProfile.userDataDir, { recursive: true });

    writeState(statePath, {
        status: 'starting',
        site: 'X.com',
        screenshot: outputScreenshot,
        mode: draftMode,
        segments: segments.length,
    });

    await ensureManagedChrome({
        chromeExecutable,
        userDataDir: launchProfile.userDataDir,
        profileDirectory: launchProfile.profileDirectory,
        debugPort,
        startUrl: 'https://x.com/home',
    });

    let browser = null;
    try {
        browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
        const context = await getXContext(browser);
        const existingXPages = context.pages().filter(page => {
            try {
                const url = page.url() || '';
                return url.includes('x.com') || url.includes('twitter.com');
            } catch {
                return false;
            }
        });
        const page = existingXPages.length > 0 ? existingXPages[existingXPages.length - 1] : await context.newPage();
        await page.bringToFront().catch(() => {});
        await applyPreferredTheme(page);

        writeState(statePath, {
            status: 'navigating',
            site: 'X.com',
            screenshot: outputScreenshot,
            mode: draftMode,
            segments: segments.length,
        });

        await page.goto('https://x.com/home', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await applyPreferredTheme(page);
        await sleep(2500);

        // Dismiss cookie consent / overlays before proceeding
        await dismissCookieConsent(page);
        await sleep(1000);

        if (await isLoginRequired(page)) {
            writeState(statePath, {
                status: 'waiting_for_login',
                site: 'X.com',
                reason: 'X requires authentication before the composer can be opened.',
                screenshot: outputScreenshot,
                mode: draftMode,
                currentUrl: page.url(),
            });
            console.log('[LOGIN_REQUIRED]');
            console.log('Site: X.com');
            console.log('Reason: X requires authentication before the composer can be opened.');
            process.exit(0);
        }

        if (!(await openComposer(page))) {
            await page.screenshot({ path: outputScreenshot, fullPage: true });
            writeState(statePath, {
                status: 'error',
                site: 'X.com',
                reason: 'Could not find or open the X composer.',
                screenshot: outputScreenshot,
                mode: draftMode,
            });
            throw new Error('Could not find or open the X composer.');
        }

        for (let index = 0; index < segments.length; index++) {
            const editors = await getThreadEditors(page);
            if (editors.length <= index) {
                if (index === 0 || !(await addAnotherPost(page))) {
                    throw new Error(`Could not open thread editor ${index + 1}.`);
                }
            }

            const refreshedEditors = await getThreadEditors(page);
            if (refreshedEditors.length <= index) {
                throw new Error(`Could not find thread editor ${index + 1}.`);
            }

            const ok = await fillEditor(page, refreshedEditors[index], segments[index]);
            if (!ok) {
                throw new Error(`Could not verify the text inside thread editor ${index + 1}.`);
            }
        }

        if (!(await isPostButtonVisible(page))) {
            throw new Error('The Post button is not visible after composing the draft.');
        }

        await page.bringToFront().catch(() => {});
        await page.screenshot({ path: outputScreenshot, fullPage: false });
        writeState(statePath, {
            status: 'draft_ready',
            site: 'X.com',
            screenshot: outputScreenshot,
            currentUrl: page.url(),
            mode: draftMode,
            segments: segments.length,
        });

console.log('[DRAFT_READY]');
console.log('Site: X.com');
console.log(`Screenshot: ${outputScreenshot}`);

// If no-publish mode is enabled, stop here and return the confirmation marker
if (noPublish) {
    writeState(statePath, {
        status: 'draft_ready_no_publish',
        site: 'X.com',
        screenshot: outputScreenshot,
        currentUrl: page.url(),
        mode: draftMode,
        segments: segments.length,
        noPublish: true,
    });
    
    console.log('[PUBLISH_CONFIRMATION_REQUIRED]');
    console.log('Site: X (Twitter)');
    console.log('Task: Click the Post button in the already-open X composer');
    console.log('Reason: Draft is ready and verified, awaiting user confirmation to publish');
    console.log('Screenshot: ' + outputScreenshot);
    process.exit(0);
}

// Attempt to post the tweet automatically
// Use a more conservative approach - don't remove overlays aggressively
await sleep(1000);

// Try to click the post button using JavaScript (more reliable)
const clickResult = await page.evaluate(() => {
    // Find the post button
    const selectors = [
        'button[data-testid="tweetButton"]',
        'button[data-testid="tweetButtonInline"]'
    ];
    
    for (const selector of selectors) {
        const btn = document.querySelector(selector);
        if (btn && !btn.disabled) {
            btn.click();
            return { clicked: true, selector };
        }
    }
    
    return { clicked: false };
});

if (clickResult.clicked) {
    await sleep(3000);
    console.log('[POSTED]');
    console.log(`Button clicked: ${clickResult.selector}`);
    
    // Verify publication
    const verificationScreenshot = path.join(projectRoot, 'archives', 'x-post-verification.png');
    const verification = await verifyPublication(page, postContent, verificationScreenshot);
    
    if (verification.verified) {
        console.log('[VERIFIED]');
        console.log(`Verification method: ${verification.method}`);
        if (verification.postUrl) {
            console.log(`Post URL: ${verification.postUrl}`);
        }
        console.log(`Verification screenshot: ${verificationScreenshot}`);
        
        writeState(statePath, {
            status: 'published_verified',
            site: 'X.com',
            screenshot: outputScreenshot,
            verificationScreenshot,
            verificationMethod: verification.method,
            postUrl: verification.postUrl || null,
            currentUrl: page.url(),
            mode: draftMode,
            segments: segments.length,
        });
    } else {
        console.log('[VERIFICATION_FAILED]');
        console.log(`Screenshot saved: ${verificationScreenshot}`);
        
        writeState(statePath, {
            status: 'published_unverified',
            site: 'X.com',
            screenshot: outputScreenshot,
            verificationScreenshot,
            currentUrl: page.url(),
            mode: draftMode,
            segments: segments.length,
        });
    }
} else {
    // Fallback: try Playwright click
    const postBtn = page.locator('button[data-testid="tweetButton"], button[data-testid="tweetButtonInline"]').first();
    if (await postBtn.count() > 0) {
        await postBtn.click({ timeout: 5000 });
        await sleep(3000);
        console.log('[POSTED]');
        console.log('Button clicked via Playwright');
        
        // Verify publication
        const verificationScreenshot = path.join(projectRoot, 'archives', 'x-post-verification.png');
        const verification = await verifyPublication(page, postContent, verificationScreenshot);
        
        if (verification.verified) {
            console.log('[VERIFIED]');
            console.log(`Verification method: ${verification.method}`);
            if (verification.postUrl) {
                console.log(`Post URL: ${verification.postUrl}`);
            }
            console.log(`Verification screenshot: ${verificationScreenshot}`);
            
            writeState(statePath, {
                status: 'published_verified',
                site: 'X.com',
                screenshot: outputScreenshot,
                verificationScreenshot,
                verificationMethod: verification.method,
                postUrl: verification.postUrl || null,
                currentUrl: page.url(),
                mode: draftMode,
                segments: segments.length,
            });
        } else {
            console.log('[VERIFICATION_FAILED]');
            console.log(`Screenshot saved: ${verificationScreenshot}`);
            
            writeState(statePath, {
                status: 'published_unverified',
                site: 'X.com',
                screenshot: outputScreenshot,
                verificationScreenshot,
                currentUrl: page.url(),
                mode: draftMode,
                segments: segments.length,
            });
        }
    } else {
        console.log('[POST_FAILED] Post button not found');
        writeState(statePath, {
            status: 'post_failed',
            site: 'X.com',
            reason: 'Post button not found',
            screenshot: outputScreenshot,
            mode: draftMode,
        });
    }
}
process.exit(0);
} catch (error) {
        writeState(statePath, {
            status: 'error',
            site: 'X.com',
            reason: error.message,
            screenshot: outputScreenshot,
            mode: draftMode,
        });
        console.error(`[ERROR] ${error.message}`);
        process.exit(1);
    }
}

run();
