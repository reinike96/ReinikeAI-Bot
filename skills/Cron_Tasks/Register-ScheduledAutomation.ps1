param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName,

    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [ValidateSet("Once", "Daily", "Weekly", "Monthly", "AtStartup", "AtLogOn")]
    [string]$Schedule = "Daily",

    [string]$Time = "09:00",
    [string]$Description = "ReinikeAI scheduled automation",
    [string]$WorkingDirectory = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$registrarPath = Join-Path $projectRoot "crons\registrar-tarea.ps1"

if (-not (Test-Path $registrarPath)) {
    throw "Task registration helper not found: $registrarPath"
}

if (-not [System.IO.Path]::IsPathRooted($ScriptPath)) {
    $ScriptPath = Join-Path $projectRoot $ScriptPath
}

$ScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
if (-not (Test-Path $ScriptPath)) {
    throw "Script path not found: $ScriptPath"
}

if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $WorkingDirectory = Split-Path -Parent $ScriptPath
}
elseif (-not [System.IO.Path]::IsPathRooted($WorkingDirectory)) {
    $WorkingDirectory = Join-Path $projectRoot $WorkingDirectory
}

$WorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)

$output = & $registrarPath `
    -TaskName $TaskName `
    -ScriptPath $ScriptPath `
    -Schedule $Schedule `
    -Time $Time `
    -Description $Description `
    -WorkingDirectory $WorkingDirectory 2>&1 | Out-String

[PSCustomObject]@{
    TaskName = $TaskName
    ScriptPath = $ScriptPath
    Schedule = $Schedule
    Time = $Time
    WorkingDirectory = $WorkingDirectory
    Output = $output.Trim()
} | ConvertTo-Json -Depth 5
