# ReinikeAI Bot

ReinikeAI Bot is a Telegram-driven Windows orchestrator built around PowerShell and OpenCode. It can execute local automation, delegate complex coding tasks to OpenCode, send files back through Telegram, and use reusable skills for browsing, Outlook, and notifications.

This repository has been sanitized for public release:

- No personal tokens or chat IDs are stored in code.
- All machine-specific paths were moved to configuration.
- Runtime state, logs, memory, and generated artifacts are excluded from Git.

## What it does

- Runs a Telegram bot from Windows PowerShell
- Delegates coding and browser-heavy tasks to OpenCode
- Sends files, screenshots, and reports back to Telegram
- Supports local skills for Telegram sending, Playwright, Outlook, and search
- Includes `/doctor` diagnostics and confirmation gates for sensitive local commands
- Prefers structured JSON `reply/actions` model output, with legacy tag parsing kept as fallback

## Quick start

1. Follow the full setup guide in [`INSTALL.md`](./INSTALL.md).
2. Copy [`config/settings.example.json`](./config/settings.example.json) to `config/settings.json`.
3. Fill in your Telegram, OpenRouter, and OpenCode credentials.
4. Run [`Install.ps1`](./Install.ps1) once.
5. Start the bot with [`RunBot.bat`](./RunBot.bat).

## Main files

- [`TelegramBot.ps1`](./TelegramBot.ps1): main orchestrator
- [`SYSTEM.md`](./SYSTEM.md): orchestrator instruction set
- [`MEMORY.md`](./MEMORY.md): persistent operating rules
- [`config/Load-BotConfig.ps1`](./config/Load-BotConfig.ps1): shared config loader
- [`runtime/ActionPolicy.ps1`](./runtime/ActionPolicy.ps1): sensitive-command policy
- [`runtime/ActionValidator.ps1`](./runtime/ActionValidator.ps1): schema validation for parsed actions before execution
- [`runtime/CapabilitiesRegistry.ps1`](./runtime/CapabilitiesRegistry.ps1): capability-based routing, risk, and timeout policy for OpenCode delegation
- [`runtime/ActionGuards.ps1`](./runtime/ActionGuards.ps1): repeated-action and task guard rules
- [`runtime/ActionExecutor.ps1`](./runtime/ActionExecutor.ps1): execution layer for parsed actions
- [`runtime/ConversationEngine.ps1`](./runtime/ConversationEngine.ps1): turn lifecycle, model fallback, and final response handling
- [`runtime/Doctor.ps1`](./runtime/Doctor.ps1): local diagnostics
- [`runtime/JobManager.ps1`](./runtime/JobManager.ps1): background job lifecycle, status updates, completion handling, and stuck-job cleanup
- [`runtime/MediaHandlers.ps1`](./runtime/MediaHandlers.ps1): screenshots, Telegram file download, local command execution, and generated-file detection
- [`runtime/MemoryStore.ps1`](./runtime/MemoryStore.ps1): chat memory persistence and multimedia compaction
- [`runtime/OpenCodeClient.ps1`](./runtime/OpenCodeClient.ps1): OpenRouter calls and OpenCode async job creation
- [`runtime/QueueManager.ps1`](./runtime/QueueManager.ps1): pending-chat queue, `/status` report generation, and typed turn processing
- [`runtime/RuntimeState.ps1`](./runtime/RuntimeState.ps1): shared runtime state initialization
- [`runtime/TagParser.ps1`](./runtime/TagParser.ps1): structured action parsing from model output
- [`runtime/TelegramApi.ps1`](./runtime/TelegramApi.ps1): Telegram send/edit/callback/typing helpers
- [`runtime/TelegramUpdateRouter.ps1`](./runtime/TelegramUpdateRouter.ps1): callback, command, media, and document routing for Telegram updates
- [`skills/index.md`](./skills/index.md): skill registry

## Publishing note

If any secret was committed before these changes, remove it from Git history before publishing. Rotating the old credentials is also recommended.
# ReinikeAI-Bot
