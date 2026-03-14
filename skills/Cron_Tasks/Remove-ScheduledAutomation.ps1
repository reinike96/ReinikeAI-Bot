param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName
)

$ErrorActionPreference = "Stop"
$taskPath = "\ReinikeBot\"
Unregister-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -Confirm:$false

[PSCustomObject]@{
    TaskName = $TaskName
    TaskPath = $taskPath
    Status = "Removed"
} | ConvertTo-Json -Depth 4
