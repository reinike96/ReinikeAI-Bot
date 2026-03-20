import os
import sys
import time
import traceback
from playwright.sync_api import sync_playwright

MIN_OPEN_SECONDS = 180


def context_still_open(context):
    try:
        _ = context.pages
        return True
    except Exception:
        return False

def resolve_profile_dir():
    project_root = os.environ.get("BOT_PROJECT_ROOT", os.getcwd())
    playwright_profile_dir = os.environ.get(
        "PLAYWRIGHT_PROFILE_DIR",
        os.path.join(project_root, "profiles", "playwright"),
    )
    chrome_profile_dir = os.environ.get("CHROME_PROFILE_DIR", playwright_profile_dir)
    return chrome_profile_dir if chrome_profile_dir.strip() else playwright_profile_dir


def manual_warmup():
    print("--- MANUAL SESSION WARMUP ---")
    print("Instructions:")
    print("1. A browser window will open with the same profile priority used by the Playwright helper.")
    print("2. Navigate to Google and log in with your account.")
    print("3. Ensure the login is successful and you see your avatar.")
    print(f"4. Keep it open for at least {MIN_OPEN_SECONDS} seconds while the profile settles.")
    print("5. Close the browser manually when done.")
    print("------------------------------")

    user_data_dir = resolve_profile_dir()
    chrome_executable = os.environ.get(
        "CHROME_EXECUTABLE",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    )
    browser_locale = os.environ.get("BROWSER_LOCALE", "en-US")
    browser_timezone = os.environ.get("BROWSER_TIMEZONE", "UTC")

    print(f"Profile dir: {user_data_dir}")
    print(f"Chrome executable: {chrome_executable}")
    print(f"Locale/Timezone: {browser_locale} / {browser_timezone}")

    try:
        with sync_playwright() as p:
            context = p.chromium.launch_persistent_context(
                user_data_dir=user_data_dir,
                executable_path=chrome_executable,
                headless=False,
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                viewport={"width": 1920, "height": 1080},
                locale=browser_locale,
                timezone_id=browser_timezone,
                ignore_default_args=["--password-store=basic", "--use-mock-keychain", "--enable-automation"],
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--disable-infobars",
                    "--no-default-browser-check",
                    "--disable-dev-shm-usage",
                    "--disable-web-security",
                    "--allow-running-insecure-content",
                ],
            )

            page = context.pages[0] if context.pages else context.new_page()
            page.goto("https://www.google.com", wait_until="domcontentloaded", timeout=60000)

            print(f"Browser is open. Waiting at least {MIN_OPEN_SECONDS} seconds for manual login...")
            started_at = time.time()
            disconnected_early = False

            while (time.time() - started_at) < MIN_OPEN_SECONDS:
                if not context_still_open(context):
                    disconnected_early = True
                    break
                time.sleep(1)

            if disconnected_early:
                raise RuntimeError(
                    "The browser disconnected before the warmup finished. "
                    "This usually means the profile is locked by another Chrome instance "
                    "or Chrome exited immediately."
                )

            print("Minimum warmup time reached. Browser will remain open until you close it manually.")
            while context_still_open(context):
                time.sleep(1)

            print("Warmup session closed. Profile updated.")
    except Exception as exc:
        print(f"[warmup_manual] ERROR: {exc}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    manual_warmup()
