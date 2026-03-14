const { chromium } = require('playwright');
const path = require('path');

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

async function run() {
    const action = process.argv[2];
    const url = process.argv[3];
    const outputPath = process.argv[4];

    if (!action || !url) {
        console.error("Usage: node browser-helper.js <action> <url> [outputPath]");
        process.exit(1);
    }

    const projectRoot = process.env.BOT_PROJECT_ROOT || process.cwd();
    const chromeProfilePath = process.env.CHROME_PROFILE_DIR || path.join(projectRoot, 'profiles', 'playwright');
    const chromeExecutable = process.env.CHROME_EXECUTABLE || "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
    const playwrightProfilePath = process.env.PLAYWRIGHT_PROFILE_DIR || path.join(projectRoot, 'profiles', 'playwright');
    const persistentProfilePath = chromeProfilePath && chromeProfilePath.trim() ? chromeProfilePath : playwrightProfilePath;
    
    const browser = await chromium.launchPersistentContext(
        persistentProfilePath,
        { 
            headless: false,
            executablePath: chromeExecutable,
            args: ['--disable-blink-features=AutomationControlled']
        }
    );
    
    const page = browser.pages[0] || await browser.newPage();

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

    try {
        if (action === 'SearchGoogle') {
            await googleSearch(page, url);
            if (outputPath) {
                await page.screenshot({ path: outputPath, fullPage: true });
                console.log(`Search completed. Screenshot saved at: ${outputPath}`);
            } else {
                const content = await page.evaluate(() => document.body.innerText);
                console.log(content);
            }
        } else if (action === 'GoogleTopResultsScreenshots') {
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
                const targetPage = await browser.newPage();
                try {
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
                    await targetPage.close();
                }
            }

            console.log(`Top Google results processed for query: ${url}`);
            for (const item of savedFiles) {
                console.log(`${item.title} | ${item.url} | ${item.path}`);
            }
        } else if (action === 'KeepOpen') {
            console.log(`Browser will stay open. Close it manually when ready.`);
            await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
            await new Promise(() => {});
        } else {
            await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });

            if (action === 'Screenshot') {
                await page.screenshot({ path: outputPath, fullPage: true });
                console.log(`Screenshot saved at: ${outputPath}`);
            } else if (action === 'GetContent') {
                const content = await page.evaluate(() => {
                    const scripts = document.querySelectorAll('script, style, iframe, nav, footer, header');
                    scripts.forEach(s => s.remove());
                    return document.body.innerText;
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
        if (action !== 'KeepOpen') {
            await browser.close();
        }
    }
}

run();
