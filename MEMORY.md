- **User:** Repository owner / deployment-specific operator.
- **Base Communication Language:** Use the configured response language from `config/settings.json` unless the user explicitly asks for another language.
- **Telegram:** Use numeric `chatId`; do not use raw JSON button structures in plain text. Prefer native Telegram buttons for decisions.
- **ORCHESTRATOR SKILLS:** Scripts in the `skills/` folder listed below must be executed directly by the orchestrator via `[CMD: ...]` and must not be delegated to OpenCode:
	1. DuckSearch
	2. Outlook
	3. Telegram_Sender
- **OPENCODE SKILLS:** Skills that exist only inside OpenCode are separate. Do not list them as orchestrator skills unless the orchestrator can execute them directly from this repository. The Playwright skill belongs to OpenCode unless the orchestrator is explicitly using the local `skills\Playwright\playwright-nav.ps1` wrapper.
- **OpenCode:** Always tell it to delete unnecessary temporary scripts upon completion; if there is a timeout, delete them yourself. If a delegation needs more information, ask the user for it.
- **Configuration:** If there is an error in your system, it must be corrected in `TelegramBot.ps1` or `OpenCode-Task.ps1`.
- **Logs:** If you need to see what has been done in the last 24 hours, you can check `subagent_events.log`, which is timestamped (use only if necessary).

[Future learnings and automatic corrections can be stored here. Ask the repository owner before adding deployment-specific memory.]
