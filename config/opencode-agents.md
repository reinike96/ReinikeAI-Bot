# OpenCode Agent Profiles

This project ships a project-level OpenCode agent layout so users can keep specialized profiles under version control and let the installer copy the template into the active user config.

## Agent map

- `build`
  - default low-overhead agent
  - use for coding, file edits, and general tasks
  - keeps heavy MCPs disabled

- `browser`
  - use for general browsing, page extraction, downloads, screenshots, and multi-step site navigation
  - intended MCP/skill set:
    - Playwright tools
    - stateful browser helpers

- `docs`
  - use for PDF and Word work
  - intended MCP/skill set:
    - PDF form filling
    - OCR / PDF extraction
    - Word document generation or editing

- `sheets`
  - use for Excel and CSV-heavy workflows
  - intended MCP/skill set:
    - Excel MCP
    - structured spreadsheet generation

- `computer`
  - use for local mouse, keyboard, window, and desktop control
  - intended MCP/skill set:
    - computer-control MCP
    - screenshots and focus/window actions

- `social`
  - use for complex logged-in website workflows such as LinkedIn or X
  - intended MCP/skill set:
    - Playwright
    - stealth/stateful browser helpers

## Important note

The repository only ships the agent structure and tool toggles. Third-party MCP servers still need to be installed locally by the user before those tools become real capabilities.

The installer can now do that interactively for supported packs and then write the matching MCP server definitions into the user's OpenCode config.

This split is intentional:

- GitHub repo contains the architecture and routing
- local machine contains credentials and installed MCP servers

## Suggested mapping for third-party capability packs

- `docs`
  - PDF toolkit / form filler MCP
  - Word MCP

- `sheets`
  - Excel MCP

- `computer`
  - computer control MCP

- `browser`
  - Playwright or stateful browser MCP

- `social`
  - stealth browser MCP or hardened social-site browser stack
