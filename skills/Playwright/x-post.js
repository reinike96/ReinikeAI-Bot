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

async function ensureManagedChrome({ chromeExecutable, profileDir, debugPort, startUrl }) {
    const ready = await waitForDebugger(debugPort, 1000);
    if (ready) {
        return false;
    }

    const args = [
        `--remote-debugging-port=${debugPort}`,
        `--user-data-dir=${profileDir}`,
        '--no-first-run',
        '--no-default-browser-check',
        '--new-window',
        startUrl,
    ];

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
    const preferredSnippets = [
        'InCoder-32B',
        'AI Meets Heavy Industry',
        'Chip design (Verilog)',
        'https://reinikeai.com/#blog/paper-2603-16790'
    ];

    for (const snippet of preferredSnippets) {
        if (postContent.includes(snippet)) {
            return snippet;
        }
    }

    const firstNonEmptyLine = postContent
        .split(/\r?\n/)
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
        'div[data-testid="tweetTextarea_0"]',
        'div[data-testid^="tweetTextarea_"]',
        'div[role="textbox"][contenteditable="true"]'
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

async function openComposer(page) {
    try {
        await page.goto('https://x.com/compose/post', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await sleep(2500);
        if (await hasVisibleComposer(page)) {
            return true;
        }
    } catch {}

    const selectors = [
        'a[data-testid="SideNav_NewTweet_Button"]',
        'button[data-testid="SideNav_NewTweet_Button"]',
        '[aria-label="Post"]',
        '[aria-label="Tweet"]'
    ];

    for (const selector of selectors) {
        try {
            const button = page.locator(selector).first();
            if (await button.count() > 0) {
                await button.click({ timeout: 5000 });
                await sleep(1500);
                if (await hasVisibleComposer(page)) {
                    return true;
                }
            }
        } catch {}
    }

    return false;
}

async function getThreadEditors(page) {
    const primary = page.locator('div[data-testid^="tweetTextarea_"]').filter({ has: page.locator('div[role="textbox"], div[contenteditable="true"]') });
    if (await primary.count() > 0) {
        const editors = [];
        const count = await primary.count();
        for (let index = 0; index < count; index++) {
            const editor = primary.nth(index).locator('div[role="textbox"], div[contenteditable="true"]').first();
            if (await editor.count() > 0) {
                editors.push(editor);
            } else {
                editors.push(primary.nth(index));
            }
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
    await editor.click({ timeout: 5000 });
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

async function run() {
    const args = parseArgs(process.argv.slice(2));
    const projectRoot = process.env.BOT_PROJECT_ROOT || process.cwd();
    const chromeExecutable = process.env.CHROME_EXECUTABLE || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    const profilePath = process.env.PLAYWRIGHT_PROFILE_DIR || path.join(projectRoot, 'profiles', 'playwright');
    const outputScreenshot = args.screenshot || path.join(projectRoot, 'archives', 'x-post-draft.png');
    const statePath = args.state || path.join(projectRoot, 'archives', 'x-draft-state.json');
    const contentPath = args.content;
    const debugPort = Number.parseInt(args.port || process.env.BROWSER_DEBUG_PORT || '9222', 10);
    const postContent = readRequiredText(contentPath, 'Post content');
    const segments = splitIntoThreadSegments(postContent);

    ensureDirForFile(outputScreenshot);
    ensureDirForFile(statePath);
    fs.mkdirSync(profilePath, { recursive: true });

    writeState(statePath, {
        status: 'starting',
        site: 'X.com',
        screenshot: outputScreenshot,
        segments: segments.length,
    });

    await ensureManagedChrome({
        chromeExecutable,
        profileDir: profilePath,
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
            segments: segments.length,
        });

        await page.goto('https://x.com/home', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await applyPreferredTheme(page);
        await sleep(2500);

        if (await isLoginRequired(page)) {
            writeState(statePath, {
                status: 'waiting_for_login',
                site: 'X.com',
                reason: 'X requires authentication before the composer can be opened.',
                screenshot: outputScreenshot,
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
            segments: segments.length,
        });

        console.log('[DRAFT_READY]');
        console.log('Site: X.com');
        console.log(`Screenshot: ${outputScreenshot}`);
        console.log('The browser remains open with the draft ready. Do not publish automatically.');
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

run();
