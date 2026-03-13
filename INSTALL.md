# Installation and Configuration

This guide takes a fresh Windows machine from zero to a working Telegram + OpenCode setup.

## 1. Prerequisites

- Windows 10 or 11
- PowerShell 5.1 or PowerShell 7
- Node.js 20+ and `npm`
- Google Chrome
- Telegram account
- OpenRouter API key
- OpenCode account or provider/API access

## 2. Install OpenCode

According to the current official OpenCode docs, Windows supports installation with `npm`, `scoop`, `choco`, and `mise`, and the docs recommend WSL for the best Windows experience.

Recommended on Windows:

```powershell
npm install -g opencode-ai
```

Alternative options are documented here:

- https://opencode.ai/docs/
- https://opencode.ai/docs/config/
- https://opencode.ai/docs/server/

Verify installation:

```powershell
opencode --version
```

If you use the bundled installer, it can try to install OpenCode automatically with `npm install -g opencode-ai` when the command is missing.

## 3. Install project dependencies

From the project root:

```powershell
npm install
```

If you plan to use the Python Playwright helper fallback, also install:

```powershell
pip install playwright playwright-stealth
python -m playwright install
```

If you use `Install.ps1`, it now attempts this automatically:

- installs `opencode` globally if missing and `npm` is available
- installs local Node dependencies from `package.json`
- validates that the Playwright Node package is available
- attempts to install the optional Python Playwright fallback when `python` and `pip` are available

## 4. Create your Telegram bot

1. Open Telegram and message `@BotFather`.
2. Run `/newbot`.
3. Set a bot name and username.
4. Copy the bot token.
5. Start a chat with your new bot at least once.
6. Get your numeric chat ID.

Common ways to get the chat ID:

- Call `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates` after messaging the bot.
- Read the `message.chat.id` value from the response.

## 5. Create your local bot config

Copy the example config:

```powershell
Copy-Item .\config\settings.example.json .\config\settings.json
```

Edit `config/settings.json` and fill in:

- `telegram.botToken`
- `telegram.defaultChatId`
- `telegram.startupChatId`
- `llm.openRouterApiKey`
- `opencode.apiKey`
- `opencode.serverPassword`

You can also override any of those with environment variables later.

## 6. Prepare OpenCode config

This repository includes a project-level [`opencode.json`](./opencode.json) and a user-level template at [`config/opencode.example.json`](./config/opencode.example.json).

To create your user config:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.config\opencode" | Out-Null
Copy-Item .\config\opencode.example.json "$HOME\.config\opencode\config.json"
```

Then edit the copied file and set the values you actually use.

Important:

- OpenCode merges global and project config.
- Project `opencode.json` is safe to commit.
- User `~/.config/opencode/config.json` should stay local.

## 7. Optional browser profile setup

If you want persistent Chrome sessions for the Playwright helpers:

1. Set `browser.chromeExecutable` if Chrome is not installed in the default location.
2. Set `browser.chromeProfileDir` to the Chrome profile you want to reuse.
3. Set `browser.playwrightProfileDir` to a writable folder for Playwright.

The installer creates `profiles/playwright/` by default.

## 8. Run the setup helper

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

This script:

- creates `archives/`
- creates `profiles/playwright/`
- asks for your local values directly in the terminal
- asks whether OpenCode should be installed automatically if it is missing
- asks whether Playwright dependencies should be installed automatically
- writes `config/settings.json` for you
- updates the local `PERSONAL DATA.md` file
- copies the OpenCode user config template for you
- runs Telegram and OpenRouter checks unless you use `-SkipNetworkChecks`

If you want to skip Telegram/OpenRouter network checks during initial setup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -SkipNetworkChecks
```

The installer is now the recommended setup path. You usually do not need to edit `config/settings.json` manually unless you want to fine-tune paths or models later.

## 9. Start the bot

```powershell
.\RunBot.bat
```

## 10. Validate the setup

Check these items:

1. `opencode --version` works.
2. The bot starts without missing-config errors.
3. Sending `/start` to the bot produces a Telegram response.
4. An OpenCode-backed task can complete successfully.

## Environment variable overrides

You can use environment variables instead of storing secrets in `config/settings.json`:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_DEFAULT_CHAT_ID`
- `TELEGRAM_STARTUP_CHAT_ID`
- `OPENROUTER_API_KEY`
- `OPENCODE_API_KEY`
- `OPENCODE_SERVER_PASSWORD`
- `OPENCODE_HOST`
- `OPENCODE_PORT`
- `OPENCODE_COMMAND`
- `CHROME_EXECUTABLE`
- `CHROME_PROFILE_DIR`
- `PLAYWRIGHT_PROFILE_DIR`

## Notes

- Keep `config/settings.json` out of Git.
- Rotate any credentials that were previously stored in source control.
- If you want to publish the repo, make sure your old secrets are also removed from commit history.
