---
name: Windows_Use
user-invocable: true
allowed-tools: Bash, Read
description: Automatización de escritorio Windows - abrir apps, clic, escribir, controlar ventanas.
---

# Windows-Use Skill

Automatización de escritorio Windows mediante el paquete `windows-use`.

## Propósito

Usa este skill cuando el subagente @computer necesite control de GUI en el escritorio local de Windows: abrir aplicaciones, hacer clic, escribir, cambiar ventanas, o completar tareas interactivas cortas.

## Requisitos

- Windows
- Python 3.10+
- `pip install windows-use`
- Un proveedor LLM configurado (por defecto OpenRouter)

## Script

- `.\.agents\skills\Windows_Use\scripts\Invoke-WindowsUse.ps1`

## Uso

```powershell
[CMD: powershell -File ".\.agents\skills\Windows_Use\scripts\Invoke-WindowsUse.ps1" -Task "Open Notepad and type a short note saying hello from ReinikeAI"]
```

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
    "model": "z-ai/glm-5-turbo",
    "reasoningEffort": "low",
    "browser": "edge",
    "maxSteps": 30,
    "useVision": false,
    "experimental": false
  }
}
```
