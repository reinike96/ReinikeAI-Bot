/**
 * CDP CLI - Interactive browser control via CDP
 * Connects to Chrome launched by Launch-BotChrome.ps1 (port 9333)
 * 
 * Usage:
 *   node cdp-cli.js open https://example.com
 *   node cdp-cli.js snapshot
 *   node cdp-cli.js click e3
 *   node cdp-cli.js type "hello world"
 *   node cdp-cli.js press Enter
 *   node cdp-cli.js fill e5 "text"
 *   node cdp-cli.js goto https://google.com
 *   node cdp-cli.js screenshot output.png
 *   node cdp-cli.js eval "document.title"
 *   node cdp-cli.js wait 2000
 *   node cdp-cli.js scroll 500
 */

const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const DEBUG_PORT = 9333;
const STATE_FILE = path.join(__dirname, '.cdp-state.json');

// Helper functions
function httpGet(url) {
    return new Promise((resolve, reject) => {
        http.get(url, { timeout: 5000 }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
        }).on('error', reject);
    });
}

async function waitForDebugger(port, timeoutMs = 5000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            await httpGet(`http://127.0.0.1:${port}/json/version`);
            return true;
        } catch {}
        await new Promise(r => setTimeout(r, 500));
    }
    return false;
}

function loadState() {
    try {
        if (fs.existsSync(STATE_FILE)) {
            return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        }
    } catch {}
    return { elements: [] };
}

function saveState(state) {
    try {
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    } catch {}
}

// Launch Chrome without blocking
function launchChrome(url) {
    return new Promise((resolve, reject) => {
        const ps = spawn('powershell', [
            '-File', './Launch-BotChrome.ps1',
            url || 'about:blank'
        ], {
            cwd: process.cwd(),
            stdio: ['ignore', 'pipe', 'pipe']
        });
        
        let output = '';
        ps.stdout.on('data', data => {
            output += data.toString();
            // Print output for visibility
            process.stdout.write(data);
        });
        ps.stderr.on('data', data => process.stderr.write(data));
        
        ps.on('close', (code) => {
            if (code === 0) {
                resolve(output);
            } else {
                reject(new Error(`PowerShell exited with code ${code}`));
            }
        });
        
        // Timeout after 10 seconds (Chrome should launch quickly)
        setTimeout(() => {
            if (!ps.killed) {
                ps.kill();
                resolve(output); // Chrome might already be running
            }
        }, 10000);
    });
}

// Main CDP CLI
async function main() {
    const action = process.argv[2];
    const param1 = process.argv[3];
    const param2 = process.argv[4];
    
    if (!action) {
        console.log(`
CDP CLI - Interactive browser control via CDP

Usage:
  node cdp-cli.js open <url>          Open URL (launches Chrome if needed)
  node cdp-cli.js snapshot            Get page elements with refs
  node cdp-cli.js click <ref>         Click element by ref (e1, e2, etc.)
  node cdp-cli.js click-text <text>   Click element containing text
  node cdp-cli.js js-click <selector> Click element by CSS selector
  node cdp-cli.js force-click <text>  Force click element by text (Playwright)
  node cdp-cli.js type <text>         Type text
  node cdp-cli.js press <key>         Press key (Enter, Tab, Escape, etc.)
  node cdp-cli.js fill <ref> <text>   Fill input field
  node cdp-cli.js goto <url>          Navigate to URL
  node cdp-cli.js screenshot <file>   Take screenshot
  node cdp-cli.js eval <code>         Evaluate JavaScript
  node cdp-cli.js wait <ms>           Wait milliseconds
  node cdp-cli.js scroll <pixels>     Scroll down
  node cdp-cli.js back                Go back
  node cdp-cli.js forward             Go forward
  node cdp-cli.js reload              Reload page
  node cdp-cli.js url                Get current URL
  node cdp-cli.js title              Get page title
  node cdp-cli.js text               Get page text content
  node cdp-cli.js close               Close Chrome browser
`);
        process.exit(0);
    }
    
    // Check if Chrome is running (except for 'open' which can launch it)
    let browser, context, page;
    const ready = await waitForDebugger(DEBUG_PORT, 2000);
    
    if (!ready && action !== 'open' && action !== 'close') {
        console.error('Chrome is not running on port 9333.');
        console.error('Run: powershell -File ".\\Launch-BotChrome.ps1"');
        process.exit(1);
    }
    
    if (ready) {
        browser = await chromium.connectOverCDP(`http://127.0.0.1:${DEBUG_PORT}`);
        context = browser.contexts()[0];
        const pages = context.pages();
        page = pages.find(p => p.url() && p.url() !== 'about:blank') || pages[0];
    }
    
    const state = loadState();
    
    try {
        switch (action) {
            case 'open': {
                const url = param1 || 'about:blank';
                
                if (!ready) {
                    // Launch Chrome via PowerShell (non-blocking)
                    console.log('Launching Chrome with CDP...');
                    try {
                        await launchChrome(url);
                    } catch (err) {
                        console.error('Failed to launch Chrome:', err.message);
                        process.exit(1);
                    }
                    
                    // Wait for Chrome to be ready
                    const launched = await waitForDebugger(DEBUG_PORT, 15000);
                    if (!launched) {
                        console.error('Chrome did not start in time');
                        process.exit(1);
                    }
                    console.log('Chrome is ready on port', DEBUG_PORT);
                }
                
                // Connect to Chrome
                browser = await chromium.connectOverCDP(`http://127.0.0.1:${DEBUG_PORT}`);
                context = browser.contexts()[0];
                const pages = context.pages();
                page = pages.find(p => p.url() && !p.url().includes('chrome://')) || pages[0];
                
                if (page && ready) {
                    // Chrome was already running, navigate to URL
                    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
                }
                
                console.log('Opened:', url);
                break;
            }
            
            case 'snapshot': {
                if (!page) {
                    console.error('No page available');
                    process.exit(1);
                }
                
                const elements = await page.evaluate(() => {
                    // Broader selectors to capture menus, popups, custom elements
                    const selectors = [
                        'button', 'a', 'input', 'textarea', 'select',
                        '[role="button"]', '[role="menuitem"]', '[role="option"]', '[role="tab"]',
                        '[onclick]', '[href]', '[data-testid]',
                        // YouTube custom elements
                        'ytd-button-renderer', 'ytd-menu-item', 'ytd-menu-navigation-item-renderer',
                        'tp-yt-paper-item', 'tp-yt-paper-button', 'ytd-toggle-button-renderer',
                        // Generic clickable elements
                        '[class*="menu"]', '[class*="dropdown"]', '[class*="popup"]',
                        '[class*="button"]', '[class*="click"]'
                    ].join(', ');
                    
                    const allItems = document.querySelectorAll(selectors);
                    const results = [];
                    let visibleIndex = 0;
                    
                    allItems.forEach((el) => {
                        const rect = el.getBoundingClientRect();
                        if (rect.width > 0 && rect.height > 0) {
                            const tag = el.tagName.toLowerCase();
                            const text = (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim().slice(0, 80);
                            const type = el.type || '';
                            const name = el.name || el.id || el.getAttribute('data-testid') || '';
                            
                            // Skip empty or very short text unless it's an input
                            if (text.length > 0 || tag === 'input' || tag === 'textarea') {
                                results.push({
                                    ref: `e${visibleIndex}`,
                                    tag,
                                    type,
                                    text,
                                    name
                                });
                                visibleIndex++;
                            }
                        }
                    });
                    
                    return results.slice(0, 150);
                });
                
                state.elements = elements;
                saveState(state);
                
                console.log('\n=== SNAPSHOT ===');
                console.log('Page:', page.url());
                console.log('Title:', await page.title());
                console.log('\n### Elements:');
                elements.forEach(el => {
                    const tagInfo = el.type ? `${el.tag}[${el.type}]` : el.tag;
                    console.log(`- ${el.ref}: [${tagInfo}] "${el.text}"${el.name ? ` (${el.name})` : ''}`);
                });
                break;
            }
            
            case 'click': {
                const ref = param1;
                if (!ref) {
                    console.error('Usage: cdp-cli click <ref>');
                    process.exit(1);
                }
                
                const el = state.elements.find(e => e.ref === ref);
                if (!el) {
                    console.error(`Element ${ref} not found. Run 'snapshot' first.`);
                    process.exit(1);
                }
                
                // Click by index (most precise) - use same selectors as snapshot
                const index = parseInt(ref.replace('e', ''));
                const clicked = await page.evaluate((targetIndex) => {
                    const selectors = [
                        'button', 'a', 'input', 'textarea', 'select',
                        '[role="button"]', '[role="menuitem"]', '[role="option"]', '[role="tab"]',
                        '[onclick]', '[href]', '[data-testid]',
                        'ytd-button-renderer', 'ytd-menu-item', 'ytd-menu-navigation-item-renderer',
                        'tp-yt-paper-item', 'tp-yt-paper-button', 'ytd-toggle-button-renderer',
                        '[class*="menu"]', '[class*="dropdown"]', '[class*="popup"]',
                        '[class*="button"]', '[class*="click"]'
                    ].join(', ');
                    
                    const allItems = document.querySelectorAll(selectors);
                    // Filter to only visible elements with text
                    const visibleItems = Array.from(allItems).filter(el => {
                        const rect = el.getBoundingClientRect();
                        const text = (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || '').trim();
                        return rect.width > 0 && rect.height > 0 && (text.length > 0 || el.tagName.toLowerCase() === 'input');
                    });
                    
                    if (visibleItems[targetIndex]) {
                        visibleItems[targetIndex].click();
                        return true;
                    }
                    return false;
                }, index);
                
                if (clicked) {
                    console.log(`Clicked: ${ref} "${el.text}"`);
                } else {
                    console.error(`Could not click ${ref} - element may have changed`);
                }
                break;
            }
            
            case 'click-text': {
                const searchText = param1;
                if (!searchText) {
                    console.error('Usage: cdp-cli click-text <text>');
                    process.exit(1);
                }
                
                const clicked = await page.evaluate((search) => {
                    const selectors = [
                        'button', 'a', 'input', 'textarea', 'select',
                        '[role="button"]', '[role="menuitem"]', '[role="option"]', '[role="tab"]',
                        '[onclick]', '[href]', '[data-testid]',
                        'ytd-button-renderer', 'ytd-menu-item', 'ytd-menu-navigation-item-renderer',
                        'tp-yt-paper-item', 'tp-yt-paper-button', 'ytd-toggle-button-renderer',
                        '[class*="menu"]', '[class*="dropdown"]', '[class*="popup"]',
                        '[class*="button"]', '[class*="click"]'
                    ].join(', ');
                    
                    const items = document.querySelectorAll(selectors);
                    for (const el of items) {
                        const rect = el.getBoundingClientRect();
                        if (rect.width === 0 || rect.height === 0) continue;
                        
                        const text = (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim();
                        if (text.toLowerCase().includes(search.toLowerCase())) {
                            el.click();
                            return text;
                        }
                    }
                    return null;
                }, searchText);
                
                if (clicked) {
                    console.log(`Clicked element with text: "${clicked}"`);
                } else {
                    console.error(`No element found with text: "${searchText}"`);
                }
                break;
            }
            
            case 'js-click': {
                const selector = param1;
                if (!selector) {
                    console.error('Usage: cdp-cli js-click <selector>');
                    process.exit(1);
                }
                
                const clicked = await page.evaluate((sel) => {
                    const el = document.querySelector(sel);
                    if (el) {
                        el.click();
                        return true;
                    }
                    // Try querySelectorAll for multiple matches
                    const els = document.querySelectorAll(sel);
                    if (els.length > 0) {
                        els[0].click();
                        return true;
                    }
                    return false;
                }, selector);
                
                if (clicked) {
                    console.log(`Clicked: ${selector}`);
                } else {
                    console.error(`Element not found: ${selector}`);
                }
                break;
            }
            
            case 'force-click': {
                const searchText = param1;
                if (!searchText) {
                    console.error('Usage: cdp-cli force-click <text>');
                    process.exit(1);
                }
                
                // Use Playwright's locator with force click
                try {
                    const locator = page.getByText(searchText, { exact: false });
                    await locator.first().click({ force: true, timeout: 5000 });
                    console.log(`Force clicked: "${searchText}"`);
                } catch (e) {
                    console.error(`Could not force click "${searchText}": ${e.message}`);
                }
                break;
            }
            
            case 'type': {
                const text = param1;
                if (!text) {
                    console.error('Usage: cdp-cli type <text>');
                    process.exit(1);
                }
                await page.keyboard.type(text, { delay: 50 });
                console.log('Typed:', text);
                break;
            }
            
            case 'press': {
                const key = param1 || 'Enter';
                await page.keyboard.press(key);
                console.log('Pressed:', key);
                break;
            }
            
            case 'fill': {
                const ref = param1;
                const text = param2;
                if (!ref || text === undefined) {
                    console.error('Usage: cdp-cli fill <ref> <text>');
                    process.exit(1);
                }
                
                const el = state.elements.find(e => e.ref === ref);
                if (!el) {
                    console.error(`Element ${ref} not found. Run 'snapshot' first.`);
                    process.exit(1);
                }
                
                // Find and fill the input
                const filled = await page.evaluate((fillData) => {
                    const inputs = document.querySelectorAll('input, textarea');
                    for (const input of inputs) {
                        const text = (input.value || input.placeholder || input.name || '').trim();
                        if (text.includes(fillData.search) || input.name === fillData.search || input.id === fillData.search) {
                            input.value = '';
                            input.focus();
                            return true;
                        }
                    }
                    return false;
                }, { search: el.text || el.name, value: text });
                
                if (filled) {
                    await page.keyboard.type(text, { delay: 50 });
                    console.log(`Filled ${ref}: "${text}"`);
                } else {
                    console.error(`Could not fill ${ref}`);
                }
                break;
            }
            
            case 'goto': {
                const url = param1;
                if (!url) {
                    console.error('Usage: cdp-cli goto <url>');
                    process.exit(1);
                }
                await page.goto(url, { waitUntil: 'domcontentloaded' });
                console.log('Navigated to:', url);
                break;
            }
            
            case 'screenshot': {
                const outputPath = param1 || './archives/screenshot.png';
                const dir = path.dirname(outputPath);
                if (!fs.existsSync(dir)) {
                    fs.mkdirSync(dir, { recursive: true });
                }
                await page.screenshot({ path: outputPath, fullPage: true });
                console.log('Screenshot saved:', outputPath);
                break;
            }
            
            case 'eval': {
                const code = param1;
                if (!code) {
                    console.error('Usage: cdp-cli eval <code>');
                    process.exit(1);
                }
                const result = await page.evaluate(code);
                console.log('Result:', result);
                break;
            }
            
            case 'wait': {
                const ms = parseInt(param1) || 1000;
                await page.waitForTimeout(ms);
                console.log('Waited:', ms, 'ms');
                break;
            }
            
            case 'scroll': {
                const pixels = parseInt(param1) || 500;
                await page.evaluate((p) => window.scrollBy(0, p), pixels);
                console.log('Scrolled:', pixels, 'px');
                break;
            }
            
            case 'back': {
                await page.goBack();
                console.log('Went back');
                break;
            }
            
            case 'forward': {
                await page.goForward();
                console.log('Went forward');
                break;
            }
            
            case 'reload': {
                await page.reload();
                console.log('Page reloaded');
                break;
            }
            
            case 'url': {
                console.log(page.url());
                break;
            }
            
            case 'title': {
                console.log(await page.title());
                break;
            }
            
            case 'text': {
                const text = await page.evaluate(() => document.body.innerText);
                console.log(text);
                break;
            }
            
            case 'close': {
                if (!ready) {
                    console.log('Chrome is not running');
                    process.exit(0);
                }
                
                try {
                    // Close all pages and contexts
                    if (browser) {
                        const contexts = browser.contexts();
                        for (const ctx of contexts) {
                            const pages = ctx.pages();
                            for (const p of pages) {
                                await p.close().catch(() => {});
                            }
                        }
                        await browser.close().catch(() => {});
                    }
                    
                    // Kill Chrome process on debug port
                    const { execSync } = require('child_process');
                    try {
                        execSync(`powershell -Command "Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*remote-debugging-port=${DEBUG_PORT}*'} | Stop-Process -Force"`, { timeout: 5000 });
                    } catch {}
                    
                    // Clean up state file
                    try {
                        if (fs.existsSync(STATE_FILE)) {
                            fs.unlinkSync(STATE_FILE);
                        }
                    } catch {}
                    
                    console.log('Chrome browser closed');
                } catch (err) {
                    console.error('Error closing browser:', err.message);
                }
                process.exit(0);
            }
            
            default:
                console.error('Unknown action:', action);
                console.log('Run "node cdp-cli.js" for help');
                process.exit(1);
        }
    } catch (err) {
        console.error('Error:', err.message);
        process.exit(1);
    }
    
    // Clean disconnect
    if (browser) {
        await browser.close().catch(() => {});
    }
    
    process.exit(0);
}

main();
