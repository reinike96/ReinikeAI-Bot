---
name: Windows_Use
user-invocable: true
allowed-tools: Bash, Read
description: Automatización de escritorio Windows - abrir apps, clic, escribir, controlar ventanas.
requires-confirmation: true
---

# Windows-Use Skill

Automatización de escritorio Windows mediante el paquete `windows-use`.

## ⚠️ CONFIRMACIÓN REQUERIDA

**Este skill requiere confirmación del usuario ANTES de ejecutarse.**

El agente @computer debe:
1. Explicar qué acción va a realizar
2. Pedir permiso explícito
3. Esperar confirmación antes de ejecutar

El agente debe retornar:
```
[WINDOWS_USE_CONFIRMATION_REQUIRED]
Task: <descripción de la acción>
Reason: <por qué es necesaria>
Risk: <riesgos potenciales>
```

## Propósito

Usa este skill cuando el subagente @computer necesite control de GUI en el escritorio local de Windows: abrir aplicaciones, hacer clic, escribir, cambiar ventanas, o completar tareas interactivas cortas.

## Requisitos

- Windows
- Python 3.10+
- `pip install windows-use`
- Un proveedor LLM configurado (por defecto OpenRouter)

## Script

- `.\.opencode\skills\Windows_Use\scripts\Invoke-WindowsUse.ps1`

## Uso

### Desde OpenCode (subagente @computer)

```powershell
[CMD: powershell -File ".\.opencode\skills\Windows_Use\scripts\Invoke-WindowsUse.ps1" -Task "Open Notepad and type a short note" -Provider "openrouter" -Model "minimax/minimax-m2.7" -ReasoningEffort "medium"]
```

**Importante:** Desde OpenCode, siempre usar `-Provider "openrouter" -Model "minimax/minimax-m2.7" -ReasoningEffort "medium"`.

### Desde el orquestador (Telegram)

```powershell
[CMD: powershell -File ".\.opencode\skills\Windows_Use\scripts\Invoke-WindowsUse.ps1" -Task "Open Notepad and type a short note"]
```

Usa la configuración por defecto de `config/settings.json` (minimax/minimax-m2.7 con reasoning medium).

## Parámetros opcionales

- `-Provider openrouter|openai|anthropic|google|groq|ollama`
- `-Model "model-name"`
- `-Browser edge|chrome|firefox`
- `-MaxSteps 25`
- `-UseVision`
- `-Experimental`
- `-RunnerDebug`

## Capacidades

Este skill permite al subagente @computer:

- **Abrir aplicaciones**: Notepad, Calculator, Outlook, navegadores, etc.
- **Control de mouse**: Clic, doble clic, arrastrar, scroll
- **Control de teclado**: Escribir texto, presionar teclas, atajos
- **Gestión de ventanas**: Cambiar, minimizar, maximizar, cerrar
- **Interacción con GUI**: Botones, campos de texto, menús, diálogos
- **Capturas de pantalla**: Para tareas con visión habilitada

## Seguridad

- Este skill puede controlar el escritorio y aplicaciones en vivo.
- Requiere confirmación antes de la ejecución.
- Mantener las tareas acotadas y explícitas.
- Preferir una VM o máquina de prueba para automatizaciones riesgosas.

## Configuración

El skill lee su configuración desde `config/settings.json` bajo la sección `windowsUse`:

```json
{
  "windowsUse": {
    "enabled": true,
    "provider": "openrouter",
    "model": "minimax/minimax-m2.7",
    "reasoningEffort": "medium",
    "browser": "edge",
    "maxSteps": 30,
    "useVision": false,
    "experimental": true
  }
}
```
