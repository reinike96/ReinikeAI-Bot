param(
    [string]$LogPath = "$PSScriptRoot\..\..\logs"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logFile = Join-Path $LogPath "ejemplo-basico_$(Get-Date -Format 'yyyyMMdd').log"

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

Write-Log "Iniciando ejemplo-basico"

try {
    
    Write-Log "Tarea ejecutada correctamente"
    
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}

Write-Log "Finalizado"
