# Windows-Use Skill

Python-powered Windows desktop automation through the `windows-use` package.

## Purpose

Use this skill when the orchestrator needs bounded GUI control on the local Windows desktop: opening apps, clicking, typing, switching windows, or completing short interactive tasks.

## Classification

- `hybrid`
- Use directly for explicit, bounded desktop actions.
- Prefer OpenCode for broader workflows that also need planning, file work, or browser-heavy recovery logic.

## Requirements

- Windows
- Python 3.10+
- `pip install windows-use`
- A supported LLM provider configured for `windows-use`

This repository defaults to `OpenRouter` through the existing `OPENROUTER_API_KEY` / `llm.openRouterApiKey`.
The default Windows-Use model is `z-ai/glm-5-turbo` with `reasoningEffort` set to `low`.

## Script

- `.\skills\Windows_Use\Invoke-WindowsUse.ps1`

## Usage

```powershell
[CMD: powershell -File ".\skills\Windows_Use\Invoke-WindowsUse.ps1" -Task "Open Notepad and type a short note saying hello from ReinikeAI"]
```

Optional parameters:

- `-Provider openrouter|openai|anthropic|google|groq|ollama`
- `-Model "model-name"`
- `-Browser edge|chrome|firefox`
- `-MaxSteps 25`
- `-UseVision`
- `-Experimental`
- `-RunnerDebug`

## Safety

- This skill can control the live desktop and applications.
- It should require confirmation before execution.
- Keep tasks bounded and explicit.
- Prefer a VM or test machine for risky automations.
