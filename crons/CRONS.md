# Sistema de Cron Jobs

Este directorio contiene scripts de tareas programadas (cron jobs) para Windows utilizando **Windows Task Scheduler**.

## Estructura

```
crons/
├── CRONS.md                    # Este archivo
├── registrar-tarea.ps1         # Script para registrar tareas
├── ejemplos/                   # Scripts de ejemplo
│   └── ejemplo-basico/
│       └── ejemplo-basico.ps1
└── logs/                       # Logs de las tareas
```

## Agregar un nuevo Cron

### 1. Crear el script

Crea tu script en una carpeta dentro de `crons/`. Ejemplo: `mi-cron/mi-cron.ps1`

```powershell
# mi-cron.ps1
param(
    [string]$LogPath = "$PSScriptRoot\..\logs"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$timestamp] Ejecutando mi-cron..."

# Tu lógica aquí

Write-Host "[$timestamp] Finalizado"
```

### 2. Registrar la tarea

Ejecuta el script de registro desde PowerShell (como Administrador):

```powershell
.\registrar-tarea.ps1 -TaskName "MiCron" -ScriptPath "C:\ruta\a\mi-cron.ps1" -Schedule "Daily" -Time "09:00"
```

### 3. Parámetros de Schedule

| Valor | Descripción |
|-------|-------------|
| Once | Una vez |
| Daily | Diario |
| Weekly | Semanal |
| Monthly | Mensual |
| AtStartup | Al iniciar Windows |
| AtLogOn | Al iniciar sesión |

### 4. Ver tareas programadas

```powershell
Get-ScheduledTask | Where-Object {$_.TaskPath -like "*Reinike*"}
```

### 5. Eliminar una tarea

```powershell
Unregister-ScheduledTask -TaskName "MiCron" -Confirm:$false
```

## Logs

Los logs de las tareas se almacenan en: `crons/logs/`
