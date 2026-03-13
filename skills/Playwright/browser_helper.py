import sys
import random
import time
import json
import os
from playwright.sync_api import sync_playwright
from playwright_stealth import Stealth

def human_browser_task(action, url_arg, output_path=None):
    with sync_playwright() as p:
        project_root = os.environ.get("BOT_PROJECT_ROOT", os.getcwd())
        user_data_dir = os.environ.get("PLAYWRIGHT_PROFILE_DIR", os.path.join(project_root, "profiles", "playwright"))
        chrome_profile_dir = os.environ.get("CHROME_PROFILE_DIR", user_data_dir)
        chrome_executable = os.environ.get("CHROME_EXECUTABLE", r"C:\Program Files\Google\Chrome\Application\chrome.exe")
        browser_locale = os.environ.get("BROWSER_LOCALE", "en-US")
        browser_timezone = os.environ.get("BROWSER_TIMEZONE", "UTC")
        
        # Launch with persistent context and original Chrome executable
        context = p.chromium.launch_persistent_context(
            user_data_dir=chrome_profile_dir if chrome_profile_dir else user_data_dir,
            executable_path=chrome_executable,
            headless=False,
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            viewport={'width': 1920, 'height': 1080},
            device_scale_factor=1,
            has_touch=False,
            is_mobile=False,
            locale=browser_locale,
            timezone_id=browser_timezone,
            ignore_default_args=["--password-store=basic", "--use-mock-keychain", "--enable-automation"],
            args=[
                "--disable-blink-features=AutomationControlled",
                "--disable-infobars",
                "--no-default-browser-check",
                "--disable-dev-shm-usage",
                "--disable-web-security",
                "--allow-running-insecure-content"
            ],
            extra_http_headers={
                "Accept-Language": f"{browser_locale},en;q=0.8",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
                "Sec-Ch-Ua": '"Google Chrome";v="133", "Not(A:Brand";v="99", "Chromium";v="133"',
                "Sec-Ch-Ua-Mobile": "?0",
                "Sec-Ch-Ua-Platform": '"Windows"',
                "Upgrade-Insecure-Requests": "1"
            }
        )
        
        page = context.pages[0] if context.pages else context.new_page()
        stealth = Stealth()
        stealth.apply_stealth_sync(page) # Apply stealth evasions
        
        def human_jitter():
            for _ in range(random.randint(3, 7)):
                page.mouse.move(random.randint(0, 500), random.randint(0, 500))
                time.sleep(random.uniform(0.1, 0.3))

        try:
            if action == 'SearchGoogle':
                human_jitter()
                # Go to home first
                page.goto("https://www.google.com", wait_until="networkidle")
                time.sleep(random.uniform(3, 5))
                
                # Handle cookie consent if visible
                try:
                    cookie_button = page.get_by_role("button", name="Accept all")
                    if not cookie_button.is_visible():
                         cookie_button = page.get_by_role("button", name="Aceptar todo")
                    
                    if cookie_button.is_visible():
                        cookie_button.click()
                        time.sleep(random.uniform(1, 2))
                except:
                    pass
                
                # Look for search box
                search_box = page.locator("textarea[name='q']").first
                search_box.wait_for(state="visible", timeout=15000)
                search_box.click(force=True)
                time.sleep(random.uniform(0.5, 1.2))
                search_box.fill("")

                query = url_arg
                for char in query:
                    search_box.type(char, delay=random.uniform(50, 180))
                
                time.sleep(random.uniform(0.5, 1))
                page.keyboard.press("Enter")
                
                # Wait for results
                page.wait_for_load_state("networkidle")
                time.sleep(random.uniform(5, 8))
                
                if output_path:
                    page.screenshot(path=output_path, full_page=True)
                    print(f"Search completed. Screenshot saved at: {output_path}")
                else:
                    content = page.evaluate("document.body.innerText")
                    print(content)
                
            else:
                # Actions requiring direct URL (Screenshot, GetContent, Download)
                url = url_arg
                referer = "https://www.google.com/" if "google.com" not in url else "https://duckduckgo.com/"
                time.sleep(random.uniform(2, 4))
                page.goto(url, wait_until="domcontentloaded", timeout=60000, referer=referer)
                time.sleep(random.uniform(3, 7))
                
                # Human-like behavior
                for _ in range(random.randint(2, 4)):
                    page.mouse.move(random.randint(200, 1000), random.randint(200, 800))
                    time.sleep(random.uniform(0.5, 1.5))
                page.evaluate("window.scrollBy({top: " + str(random.randint(300, 700)) + ", behavior: 'smooth'})")
                time.sleep(random.uniform(2, 5))

                if action == 'Screenshot':
                    if not output_path:
                        output_path = f"screenshot_{int(time.time())}.png"
                    page.screenshot(path=output_path, full_page=False)
                    print(f"Screenshot saved at: {output_path}")
                    
                elif action == 'GetContent':
                    content = page.evaluate("""() => {
                        const scripts = document.querySelectorAll('script, style, iframe, nav, footer, header');
                        scripts.forEach(s => s.remove());
                        return document.body.innerText;
                    }""")
                    print(content)

        except Exception as e:
            print(f"Error in Playwright Stealth: {str(e)}", file=sys.stderr)
            sys.exit(1)
        finally:
            time.sleep(random.uniform(2, 4))
            context.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python browser_helper.py <action> <url/query> [output_path]")
        sys.exit(1)
        
    action_arg = sys.argv[1]
    url_arg = sys.argv[2]
    out_arg = sys.argv[3] if len(sys.argv) > 3 else None
    
    human_browser_task(action_arg, url_arg, out_arg)
