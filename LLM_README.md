# ReinikeAI Bot: LLM Handover

This file is a compact technical handover for future agents working on this repository.

## Project Summary

ReinikeAI Bot is a Telegram-driven orchestrator for Windows. It is implemented mainly in PowerShell and delegates complex tasks to OpenCode over HTTP.

## Architecture

- `TelegramBot.ps1`: main loop, Telegram I/O, memory, OpenCode job orchestration
- `SYSTEM.md`: behavior contract for the orchestrator model
- `MEMORY.md`: persistent operational rules
- `skills/`: local skills executed directly by the orchestrator
- `config/Load-BotConfig.ps1`: shared configuration loader for all public-safe scripts

## Important Behavior

### Automatic file sending

If an OpenCode result contains an absolute file path under the allowed directories, the orchestrator sends it automatically.

Do not manually re-send those files from a follow-up command.

### Skill routing

- Use direct local skills for small deterministic actions.
- Use OpenCode for coding, browser automation, and complex workflows.

### Loop prevention

The orchestrator tries to prevent command repetition within the same turn. If a system message says the action was already attempted, do not repeat it.

### Public-safe configuration

Secrets, chat IDs, passwords, and machine-specific paths must come from:

- `config/settings.json`
- or environment variables

Do not hardcode them in scripts.

## Best Practices

1. Read `SYSTEM.md` before changing orchestrator behavior.
2. Read `skills/index.md` before invoking a local skill.
3. Keep Telegram responses concise and in English unless a deployment intentionally changes that.
4. Treat `config/settings.json`, logs, memory files, and generated outputs as local-only runtime state.
