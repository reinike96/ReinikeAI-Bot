const { chromium } = require('playwright');
const path = require('path');

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

    try {
        if (action === 'SearchGoogle') {
            await page.goto('https://www.google.com', { waitUntil: 'networkidle', timeout: 60000 });
            await page.waitForTimeout(2000);
            const consentSelectors = [
                'button:has-text("Accept all")',
                'button:has-text("Aceptar todo")',
                'button:has-text("Alle akzeptieren")',
                '#L2AGLb'
            ];
            for (const selector of consentSelectors) {
                const button = page.locator(selector).first();
                if (await button.count()) {
                    try {
                        await button.click({ timeout: 1500 });
                        await page.waitForTimeout(1000);
                        break;
                    } catch {}
                }
            }

            const searchBox = page.locator('textarea[name="q"]').first();
            await searchBox.waitFor({ state: 'visible', timeout: 15000 });
            await searchBox.click({ force: true });
            await searchBox.fill('');
            await searchBox.type(url, { delay: 100 });
            await page.keyboard.press('Enter');
            await page.waitForLoadState('networkidle');
            await page.waitForTimeout(2000);
            if (outputPath) {
                await page.screenshot({ path: outputPath, fullPage: true });
                console.log(`Search completed. Screenshot saved at: ${outputPath}`);
            } else {
                const content = await page.evaluate(() => document.body.innerText);
                console.log(content);
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
