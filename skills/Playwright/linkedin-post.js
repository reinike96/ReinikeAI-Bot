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

function readOptionalText(filePath) {
    if (!filePath || !fs.existsSync(filePath)) {
        return '';
    }

    return fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '').trim();
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

async function getLinkedInContext(browser) {
    const context = browser.contexts()[0];
    if (!context) {
        throw new Error('No browser context is available after connecting to managed Chrome.');
    }

    return context;
}

async function isLoginRequired(page) {
    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/checkpoint') || currentUrl.includes('/authwall')) {
        return true;
    }

    return page.evaluate(() => {
        const loginForm = document.querySelector('form[action*="login"]');
        if (loginForm) {
            return true;
        }

        const signInLink = document.querySelector('a[href*="/login"], a[href*="/checkpoint"]');
        if (signInLink) {
            return true;
        }

        return false;
    });
}

async function clickComposer(page) {
    const composerSelectors = [
        'button[aria-label="Start a post"]',
        '.share-box-feed-entry__trigger',
        '[data-test-id="post-composer"] button',
        '.share-box-feed-entry button',
        'div[role="button"]',
        'button',
    ];

    for (const selector of composerSelectors) {
        try {
            const locator = page.locator(selector).filter({ hasText: /start a post|create a post/i }).first();
            if (await locator.count() > 0) {
                await locator.click({ timeout: 5000 });
                await sleep(1200);
                if (await hasVisibleComposer(page)) {
                    return true;
                }
            }
        } catch {}
    }

    const fallbackTexts = ['Start a post', 'Create a post'];
    for (const text of fallbackTexts) {
        try {
            const locator = page.getByText(text, { exact: false }).first();
            if (await locator.count() > 0) {
                await locator.click({ timeout: 5000 });
                await sleep(1200);
                if (await hasVisibleComposer(page)) {
                    return true;
                }
            }
        } catch {}
    }

    try {
        await page.goto('https://www.linkedin.com/feed/?shareActive=true', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await sleep(2000);
        if (await hasVisibleComposer(page)) {
            return true;
        }
    } catch {}

    return false;
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

async function verifyEditorContainsExpectedText(editor, postContent) {
    const needle = getVerificationNeedle(postContent);
    if (!needle) {
        return false;
    }

    for (let attempt = 0; attempt < 10; attempt++) {
        try {
            const editorText = await editor.evaluate(node => {
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

async function fillEditor(page, postContent) {
    const editorSelectors = [
        'div[role="textbox"][contenteditable="true"]',
        'div[contenteditable="true"][data-placeholder]',
        '.ql-editor',
        '.share-box__open div[contenteditable="true"]',
        '.share-creation-state__editor div[contenteditable="true"]',
        'div[contenteditable="true"]',
    ];

    for (const selector of editorSelectors) {
        try {
            const editor = page.locator(selector).first();
            if (await editor.count() > 0 && await editor.isVisible({ timeout: 2000 })) {
                await editor.click({ timeout: 5000 });
                await sleep(400);

                try {
                    await editor.fill('');
                } catch {}

                await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A').catch(() => {});
                await page.keyboard.press('Backspace').catch(() => {});
                await page.keyboard.insertText(postContent);
                if (await verifyEditorContainsExpectedText(editor, postContent)) {
                    return true;
                }
            }
        } catch {}
    }

    return false;
}

async function hasVisibleComposer(page) {
    const composerSelectors = [
        'div[role="dialog"] div[contenteditable="true"]',
        'div[role="textbox"][contenteditable="true"]',
        '.share-box__open div[contenteditable="true"]',
        '.share-creation-state__editor div[contenteditable="true"]',
    ];

    for (const selector of composerSelectors) {
        try {
            const editor = page.locator(selector).first();
            if (await editor.count() > 0 && await editor.isVisible({ timeout: 1000 })) {
                return true;
            }
        } catch {}
    }

    return false;
}

async function findPageWithVisibleComposer(browser) {
    for (const context of browser.contexts()) {
        for (const page of context.pages()) {
            try {
                if (page.url().includes('linkedin.com') && await hasVisibleComposer(page)) {
                    return { context, page };
                }
            } catch {}
        }
    }

    return null;
}

async function prepareWorkingPage(browser, mode) {
    if (mode === 'capture') {
        const existingComposerPage = await findPageWithVisibleComposer(browser);
        if (existingComposerPage) {
            await existingComposerPage.page.bringToFront().catch(() => {});
            return existingComposerPage;
        }
    }

    const context = await getLinkedInContext(browser);
    const existingLinkedInPages = context.pages().filter(page => {
        try {
            return (page.url() || '').includes('linkedin.com');
        } catch {
            return false;
        }
    });
    const page = existingLinkedInPages.length > 0
        ? existingLinkedInPages[existingLinkedInPages.length - 1]
        : await context.newPage();
    await page.bringToFront().catch(() => {});
    return { context, page };
}

async function run() {
    const args = parseArgs(process.argv.slice(2));
    const projectRoot = process.env.BOT_PROJECT_ROOT || process.cwd();
    const chromeExecutable = process.env.CHROME_EXECUTABLE || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    const playwrightProfilePath = process.env.PLAYWRIGHT_PROFILE_DIR || path.join(projectRoot, 'profiles', 'playwright');
    const outputScreenshot = args.screenshot || path.join(projectRoot, 'archives', 'linkedin-post-draft.png');
    const statePath = args.state || path.join(projectRoot, 'archives', 'linkedin-draft-state.json');
    const mode = (args.mode || 'compose').trim().toLowerCase();
    const contentPath = args.content;
    const debugPort = Number.parseInt(args.port || process.env.BROWSER_DEBUG_PORT || '9222', 10);
    const postContent = mode === 'compose' ? readRequiredText(contentPath, 'Post content') : readOptionalText(contentPath);

    ensureDirForFile(outputScreenshot);
    ensureDirForFile(statePath);
    fs.mkdirSync(playwrightProfilePath, { recursive: true });

    writeState(statePath, {
        status: 'starting',
        site: 'LinkedIn',
        screenshot: outputScreenshot,
    });

    await ensureManagedChrome({
        chromeExecutable,
        profileDir: playwrightProfilePath,
        debugPort,
        startUrl: 'https://www.linkedin.com/feed/',
    });

    let browser = null;
    try {
        writeState(statePath, {
            status: 'connecting',
            site: 'LinkedIn',
            screenshot: outputScreenshot,
            mode,
        });
        console.log(`[LinkedIn] Connecting over CDP on port ${debugPort}...`);
        browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
        const pageRef = await prepareWorkingPage(browser, mode);
        const { page } = pageRef;

        console.log(`[LinkedIn] Using mode: ${mode}`);
        await page.bringToFront().catch(() => {});
        writeState(statePath, {
            status: 'navigating',
            site: 'LinkedIn',
            screenshot: outputScreenshot,
            mode,
        });
        console.log('[LinkedIn] Navigating to feed...');
        await page.goto('https://www.linkedin.com/feed/', { waitUntil: 'domcontentloaded', timeout: 60000 });
        await sleep(2500);

        if (await isLoginRequired(page)) {
            writeState(statePath, {
                status: 'waiting_for_login',
                site: 'LinkedIn',
                reason: 'LinkedIn requires authentication before the post editor can be opened.',
                screenshot: outputScreenshot,
                currentUrl: page.url(),
            });
            console.log('[LOGIN_REQUIRED]');
            console.log('Site: LinkedIn');
            console.log('Reason: LinkedIn requires authentication before the post editor can be opened.');
            process.exit(0);
        }

        if (mode === 'capture') {
            await page.bringToFront().catch(() => {});
            writeState(statePath, {
                status: 'capturing',
                site: 'LinkedIn',
                screenshot: outputScreenshot,
                mode,
            });
            if (!(await hasVisibleComposer(page))) {
                await page.screenshot({ path: outputScreenshot, fullPage: true });
                writeState(statePath, {
                    status: 'error',
                    site: 'LinkedIn',
                    reason: 'Could not find an open LinkedIn post draft/composer to capture.',
                    screenshot: outputScreenshot,
                });
                throw new Error('Could not find an open LinkedIn post draft/composer to capture.');
            }
        } else {
            console.log('[LinkedIn] Opening post composer...');
            writeState(statePath, {
                status: 'opening_composer',
                site: 'LinkedIn',
                screenshot: outputScreenshot,
                mode,
            });
            const composerOpened = await clickComposer(page);
            if (!composerOpened) {
                await page.screenshot({ path: outputScreenshot, fullPage: true });
                writeState(statePath, {
                    status: 'error',
                    site: 'LinkedIn',
                    reason: 'Could not find or open the post composer.',
                    screenshot: outputScreenshot,
                });
                throw new Error('Could not find or open the LinkedIn post composer.');
            }

            await sleep(2500);

            await page.bringToFront().catch(() => {});
            console.log('[LinkedIn] Filling post editor...');
            writeState(statePath, {
                status: 'filling_editor',
                site: 'LinkedIn',
                screenshot: outputScreenshot,
                mode,
            });
            const editorFilled = await fillEditor(page, postContent);
            if (!editorFilled) {
                await page.screenshot({ path: outputScreenshot, fullPage: true });
                writeState(statePath, {
                    status: 'error',
                    site: 'LinkedIn',
                    reason: 'Could not find the LinkedIn post editor.',
                    screenshot: outputScreenshot,
                });
                throw new Error('Could not find the LinkedIn post editor.');
            }
        }

        await sleep(1000);
        await page.bringToFront().catch(() => {});
        await page.screenshot({ path: outputScreenshot, fullPage: false });

        writeState(statePath, {
            status: 'draft_ready',
            site: 'LinkedIn',
            screenshot: outputScreenshot,
            currentUrl: page.url(),
            mode,
        });

        console.log('[DRAFT_READY]');
        console.log('Site: LinkedIn');
        console.log(`Screenshot: ${outputScreenshot}`);
        console.log('The browser remains open with the draft ready. Do not publish automatically.');
        process.exit(0);
    } catch (error) {
        writeState(statePath, {
            status: 'error',
            site: 'LinkedIn',
            reason: error.message,
            screenshot: outputScreenshot,
        });
        console.error(`[ERROR] ${error.message}`);
        process.exit(1);
    }
}

run();
