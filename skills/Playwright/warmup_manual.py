import os
import sys
from playwright.sync_api import sync_playwright
import time

def manual_warmup():
    print("--- MANUAL SESSION WARMUP ---")
    print("Instructions:")
    print("1. A browser window will open.")
    print("2. Navigate to Google and LOG IN with your account.")
    print("3. Ensure the login is successful and you see your avatar.")
    print("4. WAIT 10 SECONDS after logging in so cookies are saved.")
    print("5. CLOSE the browser manually (the red X) when done.")
    print("------------------------------")
    
    with sync_playwright() as p:
        user_data_dir = os.environ.get("PLAYWRIGHT_PROFILE_DIR", os.path.join(os.getcwd(), "profiles", "playwright"))
        chrome_executable = os.environ.get("CHROME_EXECUTABLE", r"C:\Program Files\Google\Chrome\Application\chrome.exe")
        browser_locale = os.environ.get("BROWSER_LOCALE", "en-US")
        browser_timezone = os.environ.get("BROWSER_TIMEZONE", "UTC")
        
        # Use exact same launch config as browser_helper.py
        context = p.chromium.launch_persistent_context(
            user_data_dir=user_data_dir,
            executable_path=chrome_executable,
            headless=False,
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            viewport={'width': 1920, 'height': 1080},
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
            ]
        )
        
        page = context.pages[0] if context.pages else context.new_page()
        page.goto("https://www.google.com")
        
        print("Browser is open. Waiting for you to log in and CLOSE the window...")
        
        # Keep process alive until context is closed (manually by user or after long time)
        try:
            while len(context.pages) > 0:
                time.sleep(1)
        except:
            pass
            
        print("Warmup session closed. Profile updated.")

if __name__ == "__main__":
    manual_warmup()
