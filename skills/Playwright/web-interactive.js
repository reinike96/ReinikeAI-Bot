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

function cleanupUrlCandidate(value) {
    return (value || '').replace(/[)\].,;:!?]+$/g, '');
}

function escapeRegex(value) {
    return String(value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function extractStartUrl(taskText) {
    const directMatches = taskText.match(/https?:\/\/[^\s<>"')\]]+/gi);
    if (directMatches && directMatches.length > 0) {
        return cleanupUrlCandidate(directMatches[0]);
    }

    const domainMatch = taskText.match(/\b(?:www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:\/[^\s<>"')\]]*)?/i);
    if (domainMatch) {
        const candidate = cleanupUrlCandidate(domainMatch[0]);
        if (candidate && !candidate.includes('@')) {
            return candidate.startsWith('http') ? candidate : `https://${candidate}`;
        }
    }

    if (/linkedin/i.test(taskText)) {
        return 'https://www.linkedin.com/feed/';
    }

    if (/\bx\.com\b|twitter/i.test(taskText)) {
        return 'https://x.com/home';
    }

    return '';
}

function detectSiteProfile(taskText, startUrl) {
    const normalizedTask = taskText.toLowerCase();
    const normalizedUrl = (startUrl || '').toLowerCase();

    if (normalizedTask.includes('linkedin') || normalizedUrl.includes('linkedin.com')) {
        return {
            kind: 'linkedin',
            siteName: 'LinkedIn',
            startUrl: startUrl || 'https://www.linkedin.com/feed/',
        };
    }

    if (normalizedTask.includes('twitter') || normalizedTask.includes('x.com') || normalizedUrl.includes('x.com') || normalizedUrl.includes('twitter.com')) {
        return {
            kind: 'x',
            siteName: 'X.com',
            startUrl: startUrl || 'https://x.com/home',
        };
    }

    if (!startUrl) {
        return {
            kind: 'generic',
            siteName: 'website',
            startUrl: '',
        };
    }

    try {
        const parsed = new URL(startUrl);
        return {
            kind: 'generic',
            siteName: parsed.hostname,
            startUrl,
        };
    } catch {
        return {
            kind: 'generic',
            siteName: startUrl,
            startUrl,
        };
    }
}

function looksLikeMetaText(text) {
    if (!text) {
        return false;
    }

    const sample = text.trim().slice(0, 1000).toLowerCase();
    if (/^\s*1\.\s+/m.test(sample) && /^\s*2\.\s+/m.test(sample)) {
        return true;
    }

    const metaPatterns = [
        'use the',
        'usa el',
        '[login_required]',
        'do not publish',
        'no publiques',
        'haz clic',
        'click',
        'verifica',
        'verify',
        'instrucciones',
        'instructions',
        'pasos',
        'steps',
        'deja el botón',
        'leave the button'
    ];

    let hits = 0;
    for (const pattern of metaPatterns) {
        if (sample.includes(pattern)) {
            hits += 1;
        }
    }

    return hits >= 3;
}

function extractDesiredText(taskText) {
    const stopMarkers = String.raw`(?:instructions?:|instrucciones:|steps?:|pasos:|important:|importante:|\[login_required\]|if [^\n]{0,60}login|si [^\n]{0,60}login)`;
    const headers = String.raw`(?:exactly this:|this is the post:|este es el post:|body:|message(?:\s+content)?(?:\s*\([^)]*\))?:|comment(?:\s+content)?(?:\s*\([^)]*\))?:|reply(?:\s+content)?(?:\s*\([^)]*\))?:|tweet(?:\s+content)?(?:\s*\([^)]*\))?:|post(?:\s+content)?(?:\s*\([^)]*\))?:|(?:contenido|texto|mensaje|comentario|respuesta)(?:\s+del?\s+(?:post|mensaje|comentario|reply|tweet))?(?:\s*\([^)]*\))?(?:\s+es)?:)`;
    const patterns = [
        new RegExp(String.raw`${headers}\s*---\s*(?<body>[\s\S]+?)\s*---`, 'i'),
        /---\s*(?<body>[\s\S]+?)\s*---/i,
        new RegExp(String.raw`${headers}\s*(?<body>[\s\S]+?)(?:\n\s*${stopMarkers}|$)`, 'i')
    ];

    for (const pattern of patterns) {
        const match = taskText.match(pattern);
        if (!match || !match.groups || !match.groups.body) {
            continue;
        }

        const candidate = match.groups.body.trim();
        if (candidate && !looksLikeMetaText(candidate)) {
            return candidate;
        }
    }

    return '';
}

function extractButtonHints(taskText) {
    const hints = [];
    const patterns = [
        /(button|bot[oó]n|click|haz clic)[^"'“”\n]{0,40}["“'](?<label>[^"”'\n]{2,80})["”']/gi,
        /(start a post|create a post|write a post|new post|compose|tweet|post|reply|comment|message)/gi,
    ];

    for (const pattern of patterns) {
        for (const match of taskText.matchAll(pattern)) {
            const label = (match.groups && match.groups.label) ? match.groups.label : match[0];
            const cleaned = String(label || '').trim();
            if (cleaned.length >= 2 && cleaned.length <= 80) {
                hints.push(cleaned);
            }
        }
    }

    return [...new Set(hints)];
}

function wantsScreenshot(taskText) {
    return /screenshot|captura|capture|pantallazo|screen/i.test(taskText);
}

function needsTextEntry(taskText) {
    return /write|escribe|paste|pega|type|typing|fill|rellena|texto|contenido|message|mensaje|comment|comentario|reply|tweet|post/i.test(taskText);
}

function getVerificationNeedle(text) {
    const preferred = [
        'InCoder-32B',
        'AI Meets Heavy Industry',
        'Chip design',
        'https://',
    ];

    for (const snippet of preferred) {
        if (text.includes(snippet)) {
            return snippet;
        }
    }

    const firstNonEmptyLine = text
        .split(/\r?\n/)
        .map(line => line.trim())
        .find(line => line.length >= 8);

    return firstNonEmptyLine || text.slice(0, 40);
}

async function getVisibleEditorCandidates(page) {
    const selectors = [
        'div[role="dialog"] [contenteditable="true"]',
        'div[role="dialog"] [role="textbox"]',
        'textarea',
        '[contenteditable="true"]',
        '[role="textbox"]',
        'input[type="text"]',
    ];

    const candidates = [];
    const seen = new Set();
    for (const selector of selectors) {
        const locator = page.locator(selector);
        const count = Math.min(await locator.count(), 8);
        for (let index = 0; index < count; index++) {
            const candidate = locator.nth(index);
            try {
                if (!(await candidate.isVisible({ timeout: 500 }))) {
                    continue;
                }

                const box = await candidate.boundingBox();
                const meta = await candidate.evaluate(node => ({
                    tag: (node.tagName || '').toLowerCase(),
                    role: node.getAttribute('role') || '',
                    placeholder: node.getAttribute('placeholder') || '',
                    ariaLabel: node.getAttribute('aria-label') || '',
                    name: node.getAttribute('name') || '',
                    testId: node.getAttribute('data-testid') || '',
                    text: (node.innerText || node.textContent || '').trim().slice(0, 120),
                    value: typeof node.value === 'string' ? node.value : '',
                }));

                const identity = JSON.stringify([meta.tag, meta.role, meta.placeholder, meta.ariaLabel, meta.name, meta.testId, box ? Math.round(box.x) : -1, box ? Math.round(box.y) : -1]);
                if (seen.has(identity)) {
                    continue;
                }
                seen.add(identity);

                const haystack = `${meta.placeholder} ${meta.ariaLabel} ${meta.name} ${meta.testId} ${meta.text}`.toLowerCase();
                if (/search|buscar|filter|filtrar/.test(haystack)) {
                    continue;
                }

                let score = 0;
                if (meta.tag === 'textarea') {
                    score += 4;
                }
                if (selector.includes('contenteditable') || selector.includes('textbox')) {
                    score += 3;
                }
                if (/post|tweet|reply|comment|message|compose|write|mind|happening/.test(haystack)) {
                    score += 6;
                }
                if (box) {
                    if (box.height >= 80) {
                        score += 3;
                    }
                    if (box.width >= 250) {
                        score += 2;
                    }
                }

                candidates.push({ locator: candidate, score, meta });
            } catch {}
        }
    }

    candidates.sort((left, right) => right.score - left.score);
    return candidates;
}

async function hasVisibleEditor(page) {
    const candidates = await getVisibleEditorCandidates(page);
    return candidates.length > 0;
}

async function findBestEditor(page) {
    const candidates = await getVisibleEditorCandidates(page);
    if (candidates.length === 0) {
        return null;
    }
    return candidates[0].locator;
}

async function verifyEditorContains(editor, expectedText) {
    const needle = getVerificationNeedle(expectedText);
    if (!needle) {
        return false;
    }

    for (let attempt = 0; attempt < 12; attempt++) {
        try {
            const editorText = await editor.evaluate(node => {
                if (typeof node.value === 'string' && node.value.trim()) {
                    return node.value.trim();
                }
                return (node.innerText || node.textContent || '').trim();
            });

            if (editorText.includes(needle)) {
                return true;
            }
        } catch {}

        await sleep(300);
    }

    return false;
}

async function fillEditor(page, editor, text) {
    await editor.click({ timeout: 5000 }).catch(() => {});
    await editor.focus().catch(() => {});
    await sleep(250);
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A').catch(() => {});
    await page.keyboard.press('Backspace').catch(() => {});

    try {
        await editor.fill('');
    } catch {}

    await page.keyboard.insertText(text);
    return verifyEditorContains(editor, text);
}

async function isLoginRequired(page) {
    const currentUrl = (page.url() || '').toLowerCase();
    if (/(login|signin|sign-in|auth|checkpoint|session|oauth)/.test(currentUrl)) {
        return true;
    }

    return page.evaluate(() => {
        const password = document.querySelector('input[type="password"], input[name="password"], input[autocomplete="current-password"]');
        if (password) {
            return true;
        }

        const userInput = document.querySelector('input[type="email"], input[autocomplete="username"], input[name="username"], input[name="text"]');
        if (userInput && document.querySelector('form')) {
            return true;
        }

        return false;
    });
}

async function clickByText(page, text) {
    const safeText = escapeRegex(text);
    const locators = [
        page.getByRole('button', { name: new RegExp(safeText, 'i') }).first(),
        page.getByRole('link', { name: new RegExp(safeText, 'i') }).first(),
        page.getByText(new RegExp(safeText, 'i')).first(),
    ];

    for (const locator of locators) {
        try {
            if (await locator.count() > 0 && await locator.isVisible({ timeout: 500 })) {
                await locator.click({ timeout: 5000 });
                await sleep(1200);
                return true;
            }
        } catch {}
    }

    return false;
}

async function openLinkedInComposer(page) {
    try {
        await page.goto('https://www.linkedin.com/feed/?shareActive=true', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await sleep(2000);
        if (await hasVisibleEditor(page)) {
            return true;
        }
    } catch {}

    if (await clickByText(page, 'Start a post')) {
        return await hasVisibleEditor(page);
    }

    if (await clickByText(page, 'Create a post')) {
        return await hasVisibleEditor(page);
    }

    return false;
}

async function openXComposer(page) {
    try {
        await page.goto('https://x.com/compose/post', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await sleep(2500);
        if (await hasVisibleEditor(page)) {
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
            if (await button.count() > 0 && await button.isVisible({ timeout: 500 })) {
                await button.click({ timeout: 5000 });
                await sleep(1500);
                if (await hasVisibleEditor(page)) {
                    return true;
                }
            }
        } catch {}
    }

    return false;
}

async function openGenericComposer(page, taskText) {
    if (await hasVisibleEditor(page)) {
        return true;
    }

    const buttonHints = extractButtonHints(taskText);
    const defaultHints = [
        'Start a post',
        'Create a post',
        'Write a post',
        'New post',
        'Compose',
        'Write something',
        "What's happening",
        "What's on your mind",
        'Reply',
        'Comment',
        'Message'
    ];

    for (const hint of [...buttonHints, ...defaultHints]) {
        if (await clickByText(page, hint)) {
            if (await hasVisibleEditor(page)) {
                return true;
            }
        }
    }

    const selectors = [
        '[data-testid*="compose" i]',
        '[data-testid*="post" i]',
        '[data-testid*="comment" i]',
        '[data-testid*="reply" i]',
        '[aria-label*="compose" i]',
        '[aria-label*="post" i]',
        '[aria-label*="comment" i]',
        '[aria-label*="reply" i]',
        'button',
        'a[role="button"]',
        '[role="button"]'
    ];

    for (const selector of selectors) {
        const locator = page.locator(selector);
        const count = Math.min(await locator.count(), 12);
        for (let index = 0; index < count; index++) {
            const candidate = locator.nth(index);
            try {
                if (!(await candidate.isVisible({ timeout: 500 }))) {
                    continue;
                }
                const text = await candidate.evaluate(node => {
                    return `${node.getAttribute('aria-label') || ''} ${(node.innerText || node.textContent || '').trim()}`.trim().toLowerCase();
                });
                if (!/compose|post|reply|comment|message|write|mind|happening|tweet/.test(text)) {
                    continue;
                }
                await candidate.click({ timeout: 5000 });
                await sleep(1200);
                if (await hasVisibleEditor(page)) {
                    return true;
                }
            } catch {}
        }
    }

    return false;
}

async function openComposerForProfile(page, profile, taskText) {
    if (profile.kind === 'linkedin') {
        return openLinkedInComposer(page);
    }
    if (profile.kind === 'x') {
        return openXComposer(page);
    }
    return openGenericComposer(page, taskText);
}

async function getWorkingPage(context, profile) {
    const normalizedSite = profile.siteName.toLowerCase();
    const existingPages = context.pages().filter(page => {
        try {
            const url = (page.url() || '').toLowerCase();
            if (!url) {
                return false;
            }
            if (profile.kind === 'linkedin') {
                return url.includes('linkedin.com');
            }
            if (profile.kind === 'x') {
                return url.includes('x.com') || url.includes('twitter.com');
            }
            if (profile.startUrl) {
                try {
                    const hostname = new URL(profile.startUrl).hostname.toLowerCase();
                    return url.includes(hostname);
                } catch {}
            }
            return url.includes(normalizedSite);
        } catch {
            return false;
        }
    });

    const page = existingPages.length > 0 ? existingPages[existingPages.length - 1] : await context.newPage();
    await page.bringToFront().catch(() => {});
    return page;
}

async function applyPreferredTheme(page) {
    try {
        await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' });
    } catch {}
}

async function run() {
    const args = parseArgs(process.argv.slice(2));
    const projectRoot = process.env.BOT_PROJECT_ROOT || process.cwd();
    const chromeExecutable = process.env.CHROME_EXECUTABLE || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    const launchProfile = resolveChromeLaunchProfile(projectRoot);
    const outputScreenshot = args.screenshot || path.join(projectRoot, 'archives', 'web-interactive.png');
    const statePath = args.state || path.join(projectRoot, 'archives', 'web-interactive-state.json');
    const taskPath = args.task;
    const debugPort = Number.parseInt(args.port || process.env.BROWSER_DEBUG_PORT || '9333', 10);
    const taskText = readRequiredText(taskPath, 'Task');
    const startUrl = extractStartUrl(taskText);
    const profile = detectSiteProfile(taskText, startUrl);
    const desiredText = extractDesiredText(taskText);
    const mustType = needsTextEntry(taskText);

    if (!profile.startUrl) {
        throw new Error('Could not determine which website to open for the interactive task.');
    }

    if (mustType && !desiredText) {
        throw new Error('Could not extract the text/content that must be entered into the website.');
    }

    ensureDirForFile(outputScreenshot);
    ensureDirForFile(statePath);
    fs.mkdirSync(launchProfile.userDataDir, { recursive: true });

    writeState(statePath, {
        status: 'starting',
        site: profile.siteName,
        screenshot: outputScreenshot,
        startUrl: profile.startUrl,
    });

    await ensureManagedChrome({
        chromeExecutable,
        userDataDir: launchProfile.userDataDir,
        profileDirectory: launchProfile.profileDirectory,
        debugPort,
        startUrl: profile.startUrl,
    });

    let browser = null;
    try {
        browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
        const context = browser.contexts()[0];
        if (!context) {
            throw new Error('No browser context is available after connecting to managed Chrome.');
        }

        const page = await getWorkingPage(context, profile);
        await applyPreferredTheme(page);
        await page.goto(profile.startUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
        await applyPreferredTheme(page);
        await sleep(2000);

        if (await isLoginRequired(page)) {
            writeState(statePath, {
                status: 'waiting_for_login',
                site: profile.siteName,
                reason: `${profile.siteName} requires authentication before the workflow can continue.`,
                screenshot: outputScreenshot,
                currentUrl: page.url(),
            });
            console.log('[LOGIN_REQUIRED]');
            console.log(`Site: ${profile.siteName}`);
            console.log(`Reason: ${profile.siteName} requires authentication before the workflow can continue.`);
            process.exit(0);
        }

        writeState(statePath, {
            status: 'opening_editor',
            site: profile.siteName,
            screenshot: outputScreenshot,
            currentUrl: page.url(),
        });

        const opened = await openComposerForProfile(page, profile, taskText);
        if (!opened) {
            await page.screenshot({ path: outputScreenshot, fullPage: true }).catch(() => {});
            throw new Error(`Could not find or open a suitable editor/composer on ${profile.siteName}.`);
        }

        let editor = await findBestEditor(page);
        if (!editor) {
            await page.screenshot({ path: outputScreenshot, fullPage: true }).catch(() => {});
            throw new Error(`A composer/editor seemed to open on ${profile.siteName}, but no writable editor was detected.`);
        }

        if (desiredText) {
            writeState(statePath, {
                status: 'typing',
                site: profile.siteName,
                screenshot: outputScreenshot,
                currentUrl: page.url(),
            });

            const typed = await fillEditor(page, editor, desiredText);
            if (!typed) {
                await page.screenshot({ path: outputScreenshot, fullPage: true }).catch(() => {});
                throw new Error(`Could not verify that the expected text was written into the editor on ${profile.siteName}.`);
            }
        }

        await page.bringToFront().catch(() => {});
        await page.screenshot({ path: outputScreenshot, fullPage: false });

        writeState(statePath, {
            status: 'ready',
            site: profile.siteName,
            screenshot: outputScreenshot,
            currentUrl: page.url(),
        });

        console.log('[DRAFT_READY]');
        console.log(`Site: ${profile.siteName}`);
        console.log(`Screenshot: ${outputScreenshot}`);
        console.log('The browser remains open with the verified page state ready for manual review.');
        process.exit(0);
    } catch (error) {
        writeState(statePath, {
            status: 'error',
            site: profile.siteName,
            reason: error.message,
            screenshot: outputScreenshot,
        });
        console.error(`[ERROR] ${error.message}`);
        process.exit(1);
    }
}

run();
