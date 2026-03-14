param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName
)

$ErrorActionPreference = "Stop"
$taskPath = "\ReinikeBot\"
Start-ScheduledTask -TaskName $TaskName -TaskPath $taskPath

[PSCustomObject]@{
    TaskName = $TaskName
    TaskPath = $taskPath
    Status = "Started"
} | ConvertTo-Json -Depth 4
