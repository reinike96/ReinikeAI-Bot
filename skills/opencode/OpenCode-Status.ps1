$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

$workDir = $botConfig.Paths.WorkDir
$jobsFile = "$workDir\jobs.json"
$logFile = "$workDir\subagent_events.log"
$serverUrl = "http://$($botConfig.OpenCode.Host):$($botConfig.OpenCode.Port)"
$cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:$($botConfig.OpenCode.ServerPassword)"))

if (-not (Test-Path $jobsFile)) {
    try {
        $h = Invoke-RestMethod -Uri "$serverUrl/global/health" -Headers @{ Authorization = "Basic $cred" } -TimeoutSec 2
        Write-Output "No active tasks. OpenCode server is ONLINE (v$($h.version))."
    }
    catch {
        Write-Output "No active tasks. OpenCode server appears to be OFFLINE."
    }
    exit
}

$jobs = Get-Content $jobsFile | ConvertFrom-Json
if (-not $jobs) {
    Write-Output "No active tasks right now."
    exit
}

$statusReport = "ACTIVE TASK STATUS:`n`n"
foreach ($j in $jobs) {
    $startTime = [DateTime]::Parse($j.startTime)
    $elapsed = New-TimeSpan -Start $startTime -End (Get-Date)
    $elapsedStr = "$($elapsed.Minutes)m $($elapsed.Seconds)s"
    
    $statusReport += "- [Job $($j.jobId)] ($($j.type)): $($j.task.Substring(0, [Math]::Min(100, $j.task.Length)))`n"
    $statusReport += "  * Elapsed: $elapsedStr`n"
    $statusReport += "  * State: $($j.state)`n"
    
    if ($j.type -eq "OpenCode") {
        try {
            $headers = @{ Authorization = "Basic $cred" }
            $logLines = Get-Content $logFile -Tail 100 | Where-Object { $_ -match "Session created:" -and $_ -match $j.type }
            if ($logLines) {
                $lastSessionLog = $logLines | Select-Object -Last 1
                if ($lastSessionLog -match 'Session created: (ses_[a-zA-Z0-9]+)') {
                    $sid = $Matches[1]
                    $statusReport += "  * Session ID: $sid`n"
                    $events = Invoke-RestMethod -Uri "$serverUrl/session/$sid/event" -Headers $headers -TimeoutSec 2
                    if ($events -and $events.Count -gt 0) {
                        $lastEvent = $events | Select-Object -Last 1
                        $statusReport += "  * OpenCode internal status: $($lastEvent.type) in progress...`n"
                    }
                }
            }
        }
        catch {}
    }

    if (Test-Path $logFile) {
        $lastLog = Get-Content $logFile -Tail 5 | Where-Object { $_ -match $j.type } | Select-Object -Last 1
        if ($lastLog) {
            $statusReport += "  * Orchestrator log: $($lastLog.Trim())`n"
        }
    }
    $statusReport += "`n"
}

Write-Output $statusReport
