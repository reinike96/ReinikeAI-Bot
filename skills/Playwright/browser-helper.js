const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function slugify(value) {
    return (value || 'result')
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '')
        .slice(0, 50) || 'result';
}

function envBool(name, defaultValue) {
    const raw = process.env[name];
    if (typeof raw === 'undefined' || raw === null || raw === '') {
        return defaultValue;
    }

    return ['1', 'true', 'yes', 'on'].includes(String(raw).trim().toLowerCase());
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

async function ensureManagedChrome({ chromeExecutable, userDataDir, profileDirectory, debugPort, startUrl, headless }) {
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
    if (headless) {
        args.push('--headless=new');
    }
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

async function connectToManagedBrowser(debugPort) {
    const browser = await chromium.connectOverCDP(`http://127.0.0.1:${debugPort}`);
    const context = browser.contexts()[0];
    if (!context) {
        throw new Error('No browser context is available after connecting to managed Chrome.');
    }
    return { browser, context };
}

function getComparableHostname(value) {
    if (!value) {
        return '';
    }

    try {
        return new URL(value).hostname.toLowerCase();
    } catch {
        return '';
    }
}

const FAST_NAV_TIMEOUT_MS = 15000;
const FAST_RENDER_SETTLE_MS = 1000;

function pickReusablePage(context, targetUrl) {
    const pages = context.pages().filter(page => {
        const pageUrl = page.url();
        return pageUrl && pageUrl !== 'about:blank';
    });

    if (pages.length === 0) {
        return null;
    }

    const targetHostname = getComparableHostname(targetUrl);
    if (targetHostname) {
        const sameHostPages = pages.filter(page => getComparableHostname(page.url()) === targetHostname);
        if (sameHostPages.length > 0) {
            return sameHostPages[sameHostPages.length - 1];
        }
    }

    return pages[pages.length - 1];
}

async function acceptGoogleConsent(targetPage) {
    const consentSelectors = [
        'button:has-text("Accept all")',
        'button:has-text("Aceptar todo")',
        'button:has-text("Alle akzeptieren")',
        '#L2AGLb'
    ];
    for (const selector of consentSelectors) {
        const button = targetPage.locator(selector).first();
        if (await button.count()) {
            try {
                await button.click({ timeout: 1500 });
                await targetPage.waitForTimeout(1000);
                break;
            } catch {}
        }
    }
}

async function googleSearch(targetPage, query) {
    await targetPage.goto('https://www.google.com', { waitUntil: 'networkidle', timeout: 60000 });
    await targetPage.waitForTimeout(2000);
    await acceptGoogleConsent(targetPage);

    const searchBox = targetPage.locator('textarea[name="q"]').first();
    await searchBox.waitFor({ state: 'visible', timeout: 15000 });
    await searchBox.click({ force: true });
    await searchBox.fill('');
    await searchBox.type(query, { delay: 100 });
    await targetPage.keyboard.press('Enter');
    await targetPage.waitForLoadState('networkidle');
    await targetPage.waitForTimeout(2000);
}

async function run() {
    const action = process.argv[2];
    const url = process.argv[3];
    const outputPath = process.argv[4];
    const headlessArg = process.argv[5];

    if (!action || !url) {
        console.error('Usage: node browser-helper.js <action> <url> [outputPath] [headless]');
        process.exit(1);
    }

    const headless = headlessArg === 'true' || headlessArg === '1';
    const projectRoot = process.env.BOT_PROJECT_ROOT || process.cwd();
    const chromeExecutable = process.env.CHROME_EXECUTABLE || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    const launchProfile = resolveChromeLaunchProfile(projectRoot);
    const debugPort = Number.parseInt(process.env.BROWSER_DEBUG_PORT || '9333', 10);
    // In headless mode, always close the browser after the task
    const keepOpen = headless ? false : envBool('BROWSER_KEEP_OPEN', true);

    await ensureManagedChrome({
        chromeExecutable,
        userDataDir: launchProfile.userDataDir,
        profileDirectory: launchProfile.profileDirectory,
        debugPort,
        startUrl: action === 'SearchGoogle' || action === 'GoogleTopResultsScreenshots' ? 'https://www.google.com' : url,
        headless,
    });

    const { browser, context } = await connectToManagedBrowser(debugPort);
    let page = null;

    try {
        if (action === 'SearchGoogle') {
            page = await context.newPage();
            await page.bringToFront().catch(() => {});
            await googleSearch(page, url);
            if (outputPath) {
                await page.screenshot({ path: outputPath, fullPage: true });
                console.log(`Search completed. Screenshot saved at: ${outputPath}`);
            } else {
                const content = await page.evaluate(() => document.body.innerText);
                console.log(content);
            }
        } else if (action === 'GoogleTopResultsScreenshots') {
            page = await context.newPage();
            await page.bringToFront().catch(() => {});
            const outputDir = outputPath || path.join(projectRoot, 'archives');
            await googleSearch(page, url);

            const rawResults = await page.locator('a:has(h3)').evaluateAll(anchors =>
                anchors.map(anchor => {
                    const href = anchor.href || '';
                    const titleNode = anchor.querySelector('h3');
                    const title = titleNode ? titleNode.textContent.trim() : '';
                    return { href, title };
                })
            );

            const topResults = [];
            const seen = new Set();
            for (const item of rawResults) {
                const href = item.href || '';
                if (!href || seen.has(href)) {
                    continue;
                }
                if (href.includes('/search?') || href.includes('google.com/preferences') || href.startsWith('javascript:')) {
                    continue;
                }
                seen.add(href);
                topResults.push(item);
                if (topResults.length === 3) {
                    break;
                }
            }

            if (topResults.length === 0) {
                throw new Error('No Google result links were detected.');
            }

            const savedFiles = [];
            for (let index = 0; index < topResults.length; index++) {
                const result = topResults[index];
                const targetPage = await context.newPage();
                try {
                    await targetPage.bringToFront().catch(() => {});
                    await targetPage.goto(result.href, { waitUntil: 'domcontentloaded', timeout: 60000 });
                    try {
                        await targetPage.waitForLoadState('networkidle', { timeout: 10000 });
                    } catch {}
                    await sleep(2000);
                    const fileName = `${String(index + 1).padStart(2, '0')}_${slugify(result.title)}.png`;
                    const screenshotPath = path.join(outputDir, fileName);
                    await targetPage.screenshot({ path: screenshotPath, fullPage: true });
                    savedFiles.push({ title: result.title, url: result.href, path: screenshotPath });
                } finally {
                    await targetPage.close().catch(() => {});
                }
            }

            console.log(`Top Google results processed for query: ${url}`);
            for (const item of savedFiles) {
                console.log(`${item.title} | ${item.url} | ${item.path}`);
            }
        } else if (action === 'KeepOpen') {
            page = pickReusablePage(context, url) || await context.newPage();
            await page.bringToFront().catch(() => {});
            if (!page.url() || page.url() === 'about:blank' || getComparableHostname(page.url()) !== getComparableHostname(url)) {
                await page.goto(url, { waitUntil: 'domcontentloaded', timeout: FAST_NAV_TIMEOUT_MS });
                await sleep(FAST_RENDER_SETTLE_MS);
            }
            console.log('Browser is open and will remain available for reuse.');
        } else {
            page = pickReusablePage(context, url) || await context.newPage();
            await page.bringToFront().catch(() => {});
            const currentUrl = page.url();
            const sameHost = getComparableHostname(currentUrl) && getComparableHostname(currentUrl) === getComparableHostname(url);
            if (!sameHost) {
                const waitUntil = action === 'GetContent' ? 'domcontentloaded' : 'networkidle';
                const timeout = action === 'GetContent' ? FAST_NAV_TIMEOUT_MS : 60000;
                await page.goto(url, { waitUntil, timeout });
                if (action === 'GetContent') {
                    await sleep(FAST_RENDER_SETTLE_MS);
                }
            }

            if (action === 'Screenshot') {
                await page.screenshot({ path: outputPath, fullPage: true });
                console.log(`Screenshot saved at: ${outputPath}`);
            } else if (action === 'GetContent') {
                const content = await page.evaluate(() => {
                    const root = document.body ? document.body.cloneNode(true) : null;
                    if (!root) {
                        return '';
                    }
                    const ignored = root.querySelectorAll('script, style, iframe, nav, footer, header');
                    ignored.forEach(node => node.remove());
                    return root.innerText;
                });
                console.log(content);
            } else if (action === 'Download') {
                const [download] = await Promise.all([
                    page.waitForEvent('download'),
                    page.goto(url)
                ]);
                const finalPath = path.join(outputPath, download.suggestedFilename());
                await download.saveAs(finalPath);
                console.log(`File downloaded at: ${finalPath}`);
            }
        }
    } catch (err) {
        console.error(`Error in Playwright: ${err.message}`);
        process.exit(1);
    } finally {
        if (!keepOpen) {
            await browser.close().catch(() => {});
        }
    }
}

run();
