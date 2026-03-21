import json
import os
import random
import subprocess
import sys
import time
import urllib.request
from playwright.sync_api import sync_playwright
from playwright_stealth import Stealth


def slugify(value):
    cleaned = ''.join(ch.lower() if ch.isalnum() else '_' for ch in (value or 'result'))
    while '__' in cleaned:
        cleaned = cleaned.replace('__', '_')
    cleaned = cleaned.strip('_')
    return (cleaned[:50] or 'result')


def env_bool(name, default_value):
    raw = os.environ.get(name)
    if raw is None or str(raw).strip() == '':
        return default_value
    return str(raw).strip().lower() in ('1', 'true', 'yes', 'on')


def http_get_json(url):
    with urllib.request.urlopen(url, timeout=2) as response:
        return json.loads(response.read().decode('utf-8'))


def wait_for_debugger(debug_port, timeout_seconds):
    deadline = time.time() + timeout_seconds
    version_url = f'http://127.0.0.1:{debug_port}/json/version'
    while time.time() < deadline:
        try:
            http_get_json(version_url)
            return True
        except Exception:
            time.sleep(0.5)
    return False


def is_chrome_profile_locked(user_data_dir):
    if not user_data_dir or not os.path.exists(user_data_dir):
        return False

    lock_candidates = (
        'SingletonLock',
        'SingletonCookie',
        'SingletonSocket',
        'lockfile',
    )
    return any(os.path.exists(os.path.join(user_data_dir, name)) for name in lock_candidates)


def resolve_chrome_launch_profile(project_root):
    playwright_profile_dir = os.environ.get('PLAYWRIGHT_PROFILE_DIR', os.path.join(project_root, 'profiles', 'playwright'))
    chrome_profile_dir = os.environ.get('CHROME_PROFILE_DIR', '').strip()
    candidate = chrome_profile_dir if chrome_profile_dir else playwright_profile_dir
    normalized = candidate.rstrip('\\/')
    base_name = os.path.basename(normalized)
    parent_dir = os.path.dirname(normalized)

    if os.path.basename(parent_dir).lower() == 'user data' and base_name:
        return parent_dir, base_name

    return normalized, ''


def comparable_hostname(value):
    if not value:
        return ''
    try:
        from urllib.parse import urlparse
        return (urlparse(value).hostname or '').lower()
    except Exception:
        return ''


FAST_NAV_TIMEOUT_MS = 15000
FAST_RENDER_SETTLE_SECONDS = 1.0


def pick_reusable_page(context, target_url):
    pages = [page for page in context.pages if page.url and page.url != 'about:blank']
    if not pages:
        return None

    target_hostname = comparable_hostname(target_url)
    if target_hostname:
        same_host_pages = [page for page in pages if comparable_hostname(page.url) == target_hostname]
        if same_host_pages:
            return same_host_pages[-1]

    return pages[-1]


def ensure_managed_chrome(chrome_executable, user_data_dir, profile_directory, debug_port, start_url):
    if wait_for_debugger(debug_port, 1):
        return

    if is_chrome_profile_locked(user_data_dir):
        raise RuntimeError(
            f'Bot Chrome profile is already open without remote debugging on port {debug_port}. '
            'Close that Chrome window or relaunch it with Launch-BotChrome.'
        )

    creation_flags = getattr(subprocess, 'DETACHED_PROCESS', 0) | getattr(subprocess, 'CREATE_NEW_PROCESS_GROUP', 0)
    args = [
        chrome_executable,
        f'--remote-debugging-port={debug_port}',
        f'--user-data-dir={user_data_dir}',
        '--no-first-run',
        '--no-default-browser-check',
    ]
    if profile_directory:
        args.append(f'--profile-directory={profile_directory}')
    args.extend(['--new-window', start_url])
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=creation_flags)

    if not wait_for_debugger(debug_port, 30):
        raise RuntimeError(f'Managed Chrome did not expose the debugger on port {debug_port}')


def human_browser_task(action, url_arg, output_path=None):
    project_root = os.environ.get('BOT_PROJECT_ROOT', os.getcwd())
    chrome_executable = os.environ.get('CHROME_EXECUTABLE', r'C:\Program Files\Google\Chrome\Application\chrome.exe')
    browser_locale = os.environ.get('BROWSER_LOCALE', 'en-US')
    browser_timezone = os.environ.get('BROWSER_TIMEZONE', 'UTC')
    debug_port = int(os.environ.get('BROWSER_DEBUG_PORT', '9333'))
    keep_open = env_bool('BROWSER_KEEP_OPEN', True)
    user_data_dir, profile_directory = resolve_chrome_launch_profile(project_root)
    start_url = 'https://www.google.com' if action in ('SearchGoogle', 'GoogleTopResultsScreenshots') else url_arg

    ensure_managed_chrome(chrome_executable, user_data_dir, profile_directory, debug_port, start_url)

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(f'http://127.0.0.1:{debug_port}')
        if not browser.contexts:
            raise RuntimeError('No browser context is available after connecting to managed Chrome.')
        context = browser.contexts[0]
        page = None
        stealth = Stealth()

        def human_jitter():
            for _ in range(random.randint(3, 7)):
                page.mouse.move(random.randint(0, 500), random.randint(0, 500))
                time.sleep(random.uniform(0.1, 0.3))

        try:
            def accept_google_consent():
                button_names = ['Accept all', 'Aceptar todo', 'Alle akzeptieren']
                for button_name in button_names:
                    try:
                        cookie_button = page.get_by_role('button', name=button_name).first
                        if cookie_button.is_visible():
                            cookie_button.click()
                            time.sleep(random.uniform(1, 2))
                            return
                    except Exception:
                        pass

                try:
                    fallback_button = page.locator('#L2AGLb').first
                    if fallback_button.is_visible():
                        fallback_button.click()
                        time.sleep(random.uniform(1, 2))
                except Exception:
                    pass

            def google_search(query):
                human_jitter()
                page.goto('https://www.google.com', wait_until='networkidle')
                time.sleep(random.uniform(3, 5))
                accept_google_consent()

                search_box = page.locator("textarea[name='q']").first
                search_box.wait_for(state='visible', timeout=15000)
                search_box.click(force=True)
                time.sleep(random.uniform(0.5, 1.2))
                search_box.fill('')

                for char in query:
                    search_box.type(char, delay=random.uniform(50, 180))

                time.sleep(random.uniform(0.5, 1))
                page.keyboard.press('Enter')
                page.wait_for_load_state('networkidle')
                time.sleep(random.uniform(3, 5))

            if action == 'SearchGoogle':
                page = context.new_page()
                stealth.apply_stealth_sync(page)
                page.bring_to_front()
                google_search(url_arg)
                if output_path:
                    page.screenshot(path=output_path, full_page=True)
                    print(f'Search completed. Screenshot saved at: {output_path}')
                else:
                    content = page.evaluate('document.body.innerText')
                    print(content)
            elif action == 'GoogleTopResultsScreenshots':
                page = context.new_page()
                stealth.apply_stealth_sync(page)
                page.bring_to_front()
                output_dir = output_path or os.path.join(project_root, 'archives')
                os.makedirs(output_dir, exist_ok=True)
                google_search(url_arg)

                raw_results = page.locator("a:has(h3)").evaluate_all("""(anchors) => anchors.map(anchor => {
                    const href = anchor.href || '';
                    const titleNode = anchor.querySelector('h3');
                    const title = titleNode ? titleNode.textContent.trim() : '';
                    return { href, title };
                })""")

                top_results = []
                seen = set()
                for item in raw_results:
                    href = item.get('href', '')
                    if (not href) or href in seen:
                        continue
                    if '/search?' in href or 'google.com/preferences' in href or href.startswith('javascript:'):
                        continue
                    seen.add(href)
                    top_results.append(item)
                    if len(top_results) == 3:
                        break

                if not top_results:
                    raise Exception('No Google result links were detected.')

                saved_files = []
                for index, item in enumerate(top_results, start=1):
                    result_page = context.new_page()
                    try:
                        result_page.bring_to_front()
                        result_page.goto(item['href'], wait_until='domcontentloaded', timeout=60000)
                        try:
                            result_page.wait_for_load_state('networkidle', timeout=10000)
                        except Exception:
                            pass
                        time.sleep(random.uniform(2, 3))
                        file_name = f"{index:02d}_{slugify(item.get('title', 'result'))}.png"
                        file_path = os.path.join(output_dir, file_name)
                        result_page.screenshot(path=file_path, full_page=True)
                        saved_files.append((item.get('title', ''), item['href'], file_path))
                    finally:
                        result_page.close()

                print(f'Top Google results processed for query: {url_arg}')
                for title, href, file_path in saved_files:
                    print(f'{title} | {href} | {file_path}')
            elif action == 'KeepOpen':
                page = pick_reusable_page(context, url_arg) or context.new_page()
                stealth.apply_stealth_sync(page)
                page.bring_to_front()
                if (not page.url) or page.url == 'about:blank' or comparable_hostname(page.url) != comparable_hostname(url_arg):
                    page.goto(url_arg, wait_until='domcontentloaded', timeout=FAST_NAV_TIMEOUT_MS)
                    time.sleep(FAST_RENDER_SETTLE_SECONDS)
                print('Browser is open and will remain available for reuse.')
            else:
                page = pick_reusable_page(context, url_arg) or context.new_page()
                stealth.apply_stealth_sync(page)
                page.bring_to_front()
                referer = 'https://www.google.com/' if 'google.com' not in url_arg else 'https://duckduckgo.com/'
                same_host = comparable_hostname(page.url) and comparable_hostname(page.url) == comparable_hostname(url_arg)
                if not same_host:
                    time.sleep(random.uniform(2, 4))
                    wait_until = 'domcontentloaded' if action == 'GetContent' else 'domcontentloaded'
                    timeout = FAST_NAV_TIMEOUT_MS if action == 'GetContent' else 60000
                    page.goto(url_arg, wait_until=wait_until, timeout=timeout, referer=referer)
                    if action == 'GetContent':
                        time.sleep(FAST_RENDER_SETTLE_SECONDS)
                    else:
                        time.sleep(random.uniform(3, 7))

                for _ in range(random.randint(2, 4)):
                    page.mouse.move(random.randint(200, 1000), random.randint(200, 800))
                    time.sleep(random.uniform(0.5, 1.5))
                page.evaluate("window.scrollBy({top: " + str(random.randint(300, 700)) + ", behavior: 'smooth'})")
                time.sleep(random.uniform(2, 5))

                if action == 'Screenshot':
                    if not output_path:
                        output_path = f'screenshot_{int(time.time())}.png'
                    page.screenshot(path=output_path, full_page=False)
                    print(f'Screenshot saved at: {output_path}')
                elif action == 'GetContent':
                    content = page.evaluate("""() => {
                        const root = document.body ? document.body.cloneNode(true) : null;
                        if (!root) {
                            return '';
                        }
                        const ignored = root.querySelectorAll('script, style, iframe, nav, footer, header');
                        ignored.forEach(node => node.remove());
                        return root.innerText;
                    }""")
                    print(content)
                elif action == 'Download':
                    with page.expect_download() as download_info:
                        page.goto(url_arg)
                    download = download_info.value
                    final_path = os.path.join(output_path, download.suggested_filename)
                    download.save_as(final_path)
                    print(f'File downloaded at: {final_path}')

        except Exception as exc:
            print(f'Error in Playwright Stealth: {str(exc)}', file=sys.stderr)
            sys.exit(1)
        finally:
            if not keep_open:
                browser.close()


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: python browser_helper.py <action> <url/query> [output_path]')
        sys.exit(1)

    action_arg = sys.argv[1]
    url_arg = sys.argv[2]
    out_arg = sys.argv[3] if len(sys.argv) > 3 else None

    human_browser_task(action_arg, url_arg, out_arg)
