param(
    [Parameter(Mandatory=$true)]
    [string]$TaskName,
    
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Once", "Daily", "Weekly", "Monthly", "AtStartup", "AtLogOn")]
    [string]$Schedule = "Daily",
    
    [Parameter(Mandatory=$false)]
    [string]$Time = "09:00",
    
    [Parameter(Mandatory=$false)]
    [string]$Description = "Tarea programada de Reinike Bot",
    
    [Parameter(Mandatory=$false)]
    [string]$WorkingDirectory = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $ScriptPath
if ([string]::IsNullOrEmpty($WorkingDirectory)) {
    $WorkingDirectory = $scriptDir
}

$taskPath = "\ReinikeBot\"

Write-Host "Registrando tarea: $TaskName" -ForegroundColor Cyan
Write-Host "Script: $ScriptPath" -ForegroundColor Cyan
Write-Host "Horario: $Schedule a las $Time" -ForegroundColor Cyan

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "La tarea '$TaskName' ya existe. Eliminando..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WorkingDirectory $WorkingDirectory

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false

switch ($Schedule) {
    "Once" {
        $trigger = New-ScheduledTaskTrigger -Once -At "$Time"
    }
    "Daily" {
        $trigger = New-ScheduledTaskTrigger -Daily -At $Time
    }
    "Weekly" {
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $Time
    }
    "Monthly" {
        $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At $Time
    }
    "AtStartup" {
        $trigger = New-ScheduledTaskTrigger -AtStartup
    }
    "AtLogOn" {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
    }
}

Register-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -Action $action -Trigger $trigger -Description $Description -Principal $principal -Settings $settings -Force

Write-Host "`nTarea registrada exitosamente!" -ForegroundColor Green
Write-Host "Nombre: $TaskName" -ForegroundColor Green
Write-Host "Ruta: $taskPath$TaskName" -ForegroundColor Green
Write-Host "`nPara ver todas las tareas de Reinike Bot:" -ForegroundColor Yellow
Write-Host "Get-ScheduledTask | Where-Object {`$_.TaskPath -like '*Reinike*'}" -ForegroundColor Gray
Write-Host "`nPara ejecutar manualmente:" -ForegroundColor Yellow
Write-Host "Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
