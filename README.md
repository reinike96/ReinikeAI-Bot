# ReinikeAI Bot

```text
  ██████  ███████  ██  ██    ██  ██  ██  ██  ███████      █████   ██
  ██   ██ ██       ██  ███   ██  ██  ██ ██   ██          ██   ██  ██
  ██████  █████    ██  ██ ██ ██  ██  ████    █████       ███████  ██
  ██   ██ ██       ██  ██  ████  ██  ██ ██   ██          ██   ██  ██
  ██   ██ ███████  ██  ██   ███  ██  ██  ██  ███████     ██   ██  ██
```

An open source Telegram extension for OpenCode on Windows, powered by PowerShell and local automation skills.

ReinikeAI Bot turns Telegram into an operations console for your machine: run controlled local commands, delegate complex tasks to OpenCode, browse the web, generate files, return results to chat, and keep everything routed through a structured orchestration layer instead of ad-hoc scripts.

It is designed as an OpenCode-powered alternative to OpenClawd: instead of replacing OpenCode, it extends it. The bot acts as a Telegram-facing orchestration layer that leverages OpenCode for coding, browsing, and multi-step execution while keeping local PowerShell automation, confirmations, file delivery, and runtime policy under your control.

## Why this project

- Open source alternative to OpenClawd for Telegram-driven OpenCode workflows
- Extension layer that leverages OpenCode instead of competing with it
- Telegram-first control surface for real machine orchestration
- OpenCode delegation for coding, browsing, and multi-step tasks
- Local PowerShell skills for search, messaging, Outlook, and browser automation
- Optional Windows-Use desktop control skill for bounded GUI automation
- Structured action parsing with validation, guards, confirmations, and diagnostics
- Public-release-safe configuration model with local secrets kept out of Git

## Core Features

- Telegram bot control for commands, files, screenshots, and follow-up actions
- OpenCode-first delegation model for coding, browsing, and complex execution
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

In practice, the architecture is:

- Telegram as the operator interface
- ReinikeAI Bot as the orchestration and policy layer
- OpenCode as the execution engine for complex tasks
- Local PowerShell skills as direct orchestrator tools when delegation is not necessary

### OpenCode agent profiles

The repository now ships project-defined OpenCode agent profiles so users can keep a specialized execution layout under version control instead of manually editing OpenCode every time.

- `build`: general coding and lightweight tasks
- `browser`: browsing and page workflows
- `docs`: PDF and Word workflows
- `sheets`: Excel and CSV workflows
- `computer`: mouse, keyboard, and desktop control
- `social`: hardened social-site browsing flows such as LinkedIn or X
- `research`: structured multi-step research workflows inside OpenCode

Reference:

- [`config/opencode.example.json`](./config/opencode.example.json)
- [`config/opencode-agents.md`](./config/opencode-agents.md)

The interactive installer lets users turn these capability packs on or off and writes both:

- `config/settings.json`
- `~/.config/opencode/config.json`

For optional third-party packs, the installer can also ask whether each selected pack should be installed immediately and then inject the corresponding MCP server definitions into the user's OpenCode config.

An optional Deep Research pack is also available for OpenCode. It is versioned in this repository and, when selected in `Install.ps1`, is copied into the real OpenCode runtime paths:

- `~/.claude/skills/research*`
- `~/.config/opencode/agents/web-search.md`
- `~/.config/opencode/agents/web-search-modules/`

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
- Windows-Use desktop automation

OpenCode-side skills are separate from the local orchestrator registry and should only be treated as local skills if the orchestrator can execute them directly from this repository.

The Deep Research pack follows that rule: the repository stores the source pack, but the actual runnable installation lives in the user's OpenCode paths after setup.

This separation is intentional: orchestrator skills are local repo tools, while OpenCode skills belong to the OpenCode execution environment.

## Configuration

Public-safe defaults live in:

- [`config/settings.example.json`](./config/settings.example.json)
- [`config/opencode.example.json`](./config/opencode.example.json)
- [`config/opencode-agents.md`](./config/opencode-agents.md)

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

This project is open source and released under the MIT License.

See [`LICENSE`](./LICENSE) for details.
