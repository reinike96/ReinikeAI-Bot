# ReinikeAI Bot

```text
  ██████  ███████  ██  ██    ██  ██  ██  ██  ███████      █████   ██
  ██   ██ ██       ██  ███   ██  ██  ██ ██   ██          ██   ██  ██
  ██████  █████    ██  ██ ██ ██  ██  ████    █████       ███████  ██
  ██   ██ ██       ██  ██  ████  ██  ██ ██   ██          ██   ██  ██
  ██   ██ ███████  ██  ██   ███  ██  ██  ██  ███████     ██   ██  ██
```

Telegram-native PC orchestration for Windows, powered by PowerShell, OpenCode, and local automation skills.

ReinikeAI Bot turns Telegram into an operations console for your machine: run controlled local commands, delegate complex tasks to OpenCode, browse the web, generate files, return results to chat, and keep everything routed through a structured orchestration layer instead of ad-hoc scripts.

## Why this project

- Telegram-first control surface for real machine orchestration
- OpenCode delegation for coding, browsing, and multi-step tasks
- Local PowerShell skills for search, messaging, Outlook, and browser automation
- Structured action parsing with validation, guards, confirmations, and diagnostics
- Public-release-safe configuration model with local secrets kept out of Git

## Core Features

- Telegram bot control for commands, files, screenshots, and follow-up actions
- OpenCode integration with capability routing, timeout policy, and background job handling
- Native button flows for confirmations and user decisions
- Local file delivery back to Telegram when reports, screenshots, or exports are generated
- `/doctor` diagnostics for Telegram, OpenCode, browser, and local runtime checks
- Action validation and risk-aware confirmation for sensitive commands
- Modular runtime architecture instead of a single monolithic script

## Architecture

The bot is split into focused runtime modules:

- [`TelegramBot.ps1`](./TelegramBot.ps1): bootstrap, startup, polling loop, and runtime wiring
- [`runtime/ConversationEngine.ps1`](./runtime/ConversationEngine.ps1): turn lifecycle and model fallback
- [`runtime/TagParser.ps1`](./runtime/TagParser.ps1): JSON-first action parsing with legacy fallback
- [`runtime/ActionValidator.ps1`](./runtime/ActionValidator.ps1): schema validation before execution
- [`runtime/ActionExecutor.ps1`](./runtime/ActionExecutor.ps1): command, browser, screenshot, and OpenCode execution
- [`runtime/CapabilitiesRegistry.ps1`](./runtime/CapabilitiesRegistry.ps1): OpenCode routing, risk, and default model policy
- [`runtime/JobManager.ps1`](./runtime/JobManager.ps1): async job lifecycle and status tracking
- [`runtime/TelegramApi.ps1`](./runtime/TelegramApi.ps1): Telegram send/edit/callback helpers

## Quick Start

1. Read the full setup guide in [`INSTALL.md`](./INSTALL.md).
2. Run the interactive installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

3. Start the bot:

```powershell
.\RunBot.bat
```

4. Open Telegram and send:

```text
/start
```

5. Validate the environment:

```text
/doctor
```

## Example Uses

- "Search Google for running shoes in Chile and send me the best-priced options."
- "Take a screenshot of my desktop and send it back."
- "Run a local command and summarize the result."
- "Delegate a coding task to OpenCode and send me the generated file."
- "Open a page, extract the visible content, and return a short answer."

## Skills

This project separates local orchestrator skills from OpenCode-side capabilities.

Local orchestrator skill registry:

- [`skills/index.md`](./skills/index.md)

Examples:

- DuckSearch
- Outlook helpers
- Telegram sender
- Local Playwright wrapper

OpenCode-side skills are separate from the local orchestrator registry and should only be treated as local skills if the orchestrator can execute them directly from this repository.

## Configuration

Public-safe defaults live in:

- [`config/settings.example.json`](./config/settings.example.json)
- [`config/opencode.example.json`](./config/opencode.example.json)

Local machine configuration is created by the installer and should stay out of Git:

- `config/settings.json`
- `~/.config/opencode/config.json`

## Tech Stack

- PowerShell
- Telegram Bot API
- OpenRouter
- OpenCode
- Playwright
- Windows automation

## Repository Notes

- Secrets, runtime memory, generated artifacts, and local profiles are excluded from version control
- The repository has been sanitized for public release
- If credentials were ever committed in older history, rotate them and clean Git history before broad sharing

## Documentation

- [`INSTALL.md`](./INSTALL.md): installation and setup
- [`SYSTEM.md`](./SYSTEM.md): orchestrator operating rules
- [`MEMORY.md`](./MEMORY.md): deployment memory and operating assumptions
- [`LLM_README.md`](./LLM_README.md): LLM-oriented project notes

## License

Add your preferred license before public distribution if you want explicit reuse terms.
