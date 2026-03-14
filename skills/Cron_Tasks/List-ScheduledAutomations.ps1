param(
    [string]$TaskName = ""
)

$ErrorActionPreference = "Stop"
$taskPath = "\ReinikeBot\"

$tasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
if (-not [string]::IsNullOrWhiteSpace($TaskName)) {
    $tasks = @($tasks | Where-Object { $_.TaskName -like "*$TaskName*" })
}

$results = @($tasks | ForEach-Object {
    $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        TaskName = $_.TaskName
        TaskPath = $_.TaskPath
        State = "$($_.State)"
        LastRunTime = if ($info) { $info.LastRunTime.ToString("o") } else { $null }
        NextRunTime = if ($info) { $info.NextRunTime.ToString("o") } else { $null }
        Author = $_.Author
        Description = $_.Description
    }
})

[PSCustomObject]@{
    Count = $results.Count
    Tasks = $results
} | ConvertTo-Json -Depth 5
