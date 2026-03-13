# DuckSearch PowerShell Wrapper
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Query
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir "duck_search.py"

$env:PYTHONIOENCODING = "utf-8"

try {
    # Suppress stderr to avoid NativeCommandError noise in the AI orchestrator
    $result = python $pythonScript $Query 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: El script de búsqueda falló con código $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Output $result
}
catch {
    Write-Output "Error al ejecutar la búsqueda: $_"
    exit 1
}
