function Get-WindowsUseEscalationRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[WINDOWS_USE_FALLBACK_REQUIRED\]\s*Task:\s*(?<task>[^\r\n]+)\s*Reason:\s*(?<reason>[^\r\n]+)') {
        return $null
    }

    $taskText = $Matches['task'].Trim()
    $reasonText = $Matches['reason'].Trim()
    if ([string]::IsNullOrWhiteSpace($taskText)) {
        return $null
    }

    return [PSCustomObject]@{
        Task = $taskText
        Reason = $reasonText
    }
}

function Offer-WindowsUseEscalation {
    param(
        [object]$JobRecord,
        [string]$TaskText,
        [string]$ReasonText = ""
    )

    if ([string]::IsNullOrWhiteSpace($TaskText)) {
        return $false
    }

    if (-not (Get-Command Test-WindowsUseFallbackAvailable -ErrorAction SilentlyContinue)) {
        return $false
    }
    if (-not (Test-WindowsUseFallbackAvailable)) {
        return $false
    }

    $windowsUseWrapper = Join-Path $workDir "skills\Windows_Use\Invoke-WindowsUse.ps1"
    if (-not (Test-Path $windowsUseWrapper)) {
        return $false
    }

    $quotedWrapper = if (Get-Command Convert-ToPowerShellSingleQuotedLiteral -ErrorAction SilentlyContinue) {
        Convert-ToPowerShellSingleQuotedLiteral -Value $windowsUseWrapper
    }
    else {
        "'" + $windowsUseWrapper.Replace("'", "''") + "'"
    }
    $quotedTask = if (Get-Command Convert-ToPowerShellSingleQuotedLiteral -ErrorAction SilentlyContinue) {
        Convert-ToPowerShellSingleQuotedLiteral -Value $TaskText
    }
    else {
        "'" + $TaskText.Replace("'", "''") + "'"
    }

    $cmd = "powershell -File $quotedWrapper -Task $quotedTask"
    $confirmationId = [guid]::NewGuid().ToString("N")
    Add-PendingConfirmation -ConfirmationId $confirmationId -Payload @{
        Command    = $cmd
        ChatId     = $JobRecord.ChatId
        UserId     = ""
        UserScoped = $false
        CreatedAt  = Get-Date
    }

    $buttons = New-ConfirmationButtons -ConfirmData "confirm_cmd:$confirmationId" -CancelData "cancel_cmd:$confirmationId"
    $safeReason = if ([string]::IsNullOrWhiteSpace($ReasonText)) { "OpenCode reported that local live desktop control is required." } else { $ReasonText.Trim() }
    if ($safeReason.Length -gt 400) {
        $safeReason = $safeReason.Substring(0, 400) + "..."
    }

    $message = @"
*OpenCode requested Windows-Use escalation.*

Original task:
``$($JobRecord.Task)``

Reason:
``$safeReason``

Proposed Windows-Use task:
``$TaskText``

Approve if you want the orchestrator to run this through the local Windows desktop.
"@.Trim()

    Send-TelegramText -chatId $JobRecord.ChatId -text $message -buttons $buttons
    Add-ChatMemory -chatId $JobRecord.ChatId -role "user" -content "[SYSTEM]: OpenCode requested a Windows-Use escalation for task '$($JobRecord.Task)'. Reason: $safeReason Proposed Windows-Use task: $TaskText"
    Write-DailyLog -message "Windows-Use escalation offered for job $($JobRecord.Job.Id). Reason='$safeReason' task='$TaskText'" -type "WARN"
    return $true
}

function Get-StuckJobs {
    param(
        [array]$ActiveJobs,
        [string]$WorkDir
    )

    $stuckThreshold = 20.0
    $stuckJobs = @()
    $currentTime = Get-Date

    foreach ($j in $ActiveJobs) {
        $elapsedMinutes = ($currentTime - $j.StartTime).TotalMinutes
        $isCriticallyStuck = $elapsedMinutes -ge $stuckThreshold

        if ($j.Type -eq "OpenCode") {
            $heartbeatFile = "$WorkDir\heartbeat_$($j.Job.Id).json"
            if (Test-Path $heartbeatFile) {
                try {
                    $hb = Get-Content $heartbeatFile -Raw | ConvertFrom-Json
                    $lastHeartbeat = [DateTime]::Parse($hb.timestamp)
                    $heartbeatAgeSeconds = ($currentTime - $lastHeartbeat).TotalSeconds
                    if ($heartbeatAgeSeconds -lt 300) {
                        $isCriticallyStuck = $false
                    }
                }
                catch {}
            }
        }

        if ($isCriticallyStuck -and $j.Job.State -eq "Running") {
            $j | Add-Member -MemberType NoteProperty -Name "ElapsedMinutes" -Value ([int]$elapsedMinutes) -Force -ErrorAction SilentlyContinue
            $stuckJobs += $j
        }
    }

    return $stuckJobs
}

function Update-ActiveJobTelemetry {
    param(
        [string]$WorkDir
    )

    $currentTime = Get-Date
    foreach ($j in (Get-ActiveJobs)) {
        if ($null -eq $j.LastTyping -or ($currentTime - $j.LastTyping).TotalSeconds -ge 4) {
            Send-TelegramTyping -chatId $j.ChatId
            $j.LastTyping = $currentTime
            $elapsedDisplay = [int]($currentTime - $j.StartTime).TotalMinutes
            Write-Host "[JOB $($j.Job.Id) - $($j.Type) - ${elapsedDisplay}min - $($j.Job.State)]: $($j.Task.Substring(0, [Math]::Min(60, $j.Task.Length)))..." -ForegroundColor DarkGray
        }

        if ($null -ne $j.LastReport) {
            $minutesSinceReport = ($currentTime - $j.LastReport).TotalMinutes
            if ($minutesSinceReport -ge 4.0) {
                $j.LastReport = $currentTime
                $totalElapsed = [int]($currentTime - $j.StartTime).TotalMinutes
                $lastLog = Get-Content "$WorkDir\subagent_events.log" -Tail 5 | Where-Object { $_ -match $j.Type } | Select-Object -Last 1
                $emojiDoc = [char]::ConvertFromUtf32(0x1F4DC)
                $logContext = if ($lastLog) { "$emojiDoc *Latest logged event:*`n``$($lastLog.Trim())``" } else { "Waiting for process output..." }
                $emojiWait = [char]::ConvertFromUtf32(0x231B)
                $statusMsg = "$emojiWait *Task in progress ($($j.Type))*`n" +
                    "*$totalElapsed minutes* have passed since the start.`n`n" +
                    "Capability: $($j.Capability)`n" +
                    "Execution mode: $($j.ExecutionMode)`n" +
                    "$logContext`n`n" +
                    "Still working on it. I will send the final result as soon as it is ready."
                Update-TelegramStatus -job $j -text $statusMsg
            }
        }
    }
}

function Complete-ActiveJobs {
    param(
        [string]$WorkDir
    )

    $completedJobs = Get-ActiveJobs | Where-Object { $_.Job.State -ne "Running" }
    foreach ($j in $completedJobs) {
        Write-DailyLog -message "Job finished: Id=$($j.Job.Id) Type=$($j.Type) State=$($j.Job.State) ChatId=$($j.ChatId)" -type "JOB"

        $rawOutput = Receive-Job -Job $j.Job -ErrorAction SilentlyContinue
        $subRes = if ($null -ne $rawOutput) {
            ($rawOutput | ForEach-Object { "$_" }) -join "`n"
        }
        else { "" }
        $subRes = (Repair-JobEncoding -text $subRes).Trim()

        $jobErrors = $j.Job.ChildJobs | ForEach-Object { $_.Error } | Where-Object { $null -ne $_ }
        if ($jobErrors) {
            $errStr = ($jobErrors | ForEach-Object { "$_" }) -join "; "
            Write-DailyLog -message "Job $($j.Job.Id) tuvo errores: $errStr" -type "ERROR"
            if ([string]::IsNullOrWhiteSpace($subRes)) {
                $subRes = "[ERROR en el job]: $errStr"
            }
        }

        if ([string]::IsNullOrWhiteSpace($subRes)) {
            $subRes = "The task finished but returned no text. State: $($j.Job.State)"
        }
        Write-DailyLog -message "Job $($j.Job.Id) result captured: len=$($subRes.Length) chars" -type "JOB"

        if ($j.CheckpointPath) {
            $checkpointStatus = if ($subRes -match '\[WINDOWS_USE_FALLBACK_REQUIRED\]') {
                "needs_desktop_control"
            }
            elseif ($subRes -match '^\[ERROR_') {
                "failed"
            }
            else {
                "completed"
            }
            $checkpointAction = switch ($checkpointStatus) {
                "completed" { "Task completed" }
                "needs_desktop_control" { "Task paused pending Windows-Use escalation" }
                default { "Task finished with error" }
            }
            try {
                Update-TaskCheckpointState -CheckpointPath $j.CheckpointPath -TaskText $j.Task -Status $checkpointStatus -ResultText $subRes -LastAction $checkpointAction -LastError $(if ($checkpointStatus -eq "failed") { $subRes } elseif ($checkpointStatus -eq "needs_desktop_control") { "OpenCode requested Windows-Use escalation." } else { "" })
            }
            catch {
                Write-DailyLog -message "Checkpoint update failed for job $($j.Job.Id): $_" -type "WARN"
            }
        }

        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue

        if ($j.Type -eq "Subagent" -or $j.Type -eq "OpenCode" -or $j.Type -eq "Script") {
            if (($subRes -match "\[ERROR_OPENCODE_CREDITS\]") -or ($subRes -match "\[OpenCode termino sin output\]")) {
                    Write-DailyLog -message "Detected credit error or silent completion in Job $($j.Job.Id). Retrying through the HTTP API." -type "WARN"

                if ($j.Label -notmatch "Fallback") {
                    $emojiRefresh = [char]::ConvertFromUtf32(0x1F504)
                    Update-TelegramStatus -job $j -text "$emojiRefresh *Insufficient credits.* Retrying with the paid model..."

                    [array]$fallbackMcps = @()
                    if ($j.Label -match "MCP:\s*([^\)]+)") {
                        $fallbackMcps = $Matches[1].Split(',') | ForEach-Object { $_.Trim() }
                    }

                    $fallbackAgent = $null
                    $fallbackJob = Start-OpenCodeJob -TaskDescription $j.Task -ChatId $j.ChatId -EnableMCPs $fallbackMcps -Model "opencode/minimax-m2.5" -Agent $fallbackAgent
                    $fallbackJob.Label = "OpenCode (Fallback Paid)"
                    Add-ActiveJob -JobRecord $fallbackJob
                    Write-JobsFile

                    Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
                    Remove-ActiveJobById -JobId $j.Job.Id
                    continue
                }
            }

            $windowsUseEscalation = Get-WindowsUseEscalationRequest -ResultText $subRes
            if ($j.Type -eq "OpenCode" -and $null -ne $windowsUseEscalation) {
                $offered = Offer-WindowsUseEscalation -JobRecord $j -TaskText $windowsUseEscalation.Task -ReasonText $windowsUseEscalation.Reason
                if ($offered) {
                    Remove-ActiveJobById -JobId $j.Job.Id
                    Write-JobsFile
                    continue
                }
            }

            $emojiCheck = [char]::ConvertFromUtf32(0x2705)
            Update-TelegramStatus -job $j -text "$emojiCheck *Task completed* ($($j.Type)). Analyzing results..."

            $numFilesSent = Send-DetectedFiles -chatId $j.ChatId -text $subRes
            $fileNotice = if ($numFilesSent -gt 0) { "`n`n[SYSTEM]: $numFilesSent file(s) were detected and automatically sent to the user. Do not try to send them again with 'Telegram_Sender' or 'CMD'." } else { "" }

            $sanitizedRes = $subRes -replace '(?i)</?(minimax:)?tool_call.*?>', '' -replace '(?i)</?invoke.*?>', ''
            $sysMsg = "[System - Task '$($j.Task)' completed by $($j.Type)]. Result:`n$sanitizedRes$fileNotice`n`nYou must now analyze this result and reply to the user with a clear English summary. Do not delegate again. Respond directly."
            try {
                Add-ChatMemory -chatId $j.ChatId -role "user" -content $sysMsg
            }
            catch {
                Write-DailyLog -message "Error saving job memory for $($j.Job.Id): $_" -type "ERROR"
                $truncated = if ($subRes.Length -gt 3800) { $subRes.Substring(0, 3800) + "`n`n[...result truncated due to length]" } else { $subRes }
                Send-TelegramText -chatId $j.ChatId -text "*Direct result:*`n$truncated"
            }

            Add-PendingChatId -ChatId $j.ChatId
        }

        Remove-ActiveJobById -JobId $j.Job.Id
        Write-JobsFile
    }
}

function Expire-PendingConfirmations {
    $pendingConfirmations = Get-PendingConfirmations
    foreach ($confirmationId in @($pendingConfirmations.Keys)) {
        $pending = $pendingConfirmations[$confirmationId]
        if ($null -ne $pending -and ((Get-Date) - $pending.CreatedAt).TotalMinutes -ge 10) {
            $pendingConfirmations.Remove($confirmationId)
        }
    }
}

function Remove-StuckJobs {
    param(
        [string]$WorkDir
    )

    $stuckJobs = Get-StuckJobs -ActiveJobs (Get-ActiveJobs) -WorkDir $WorkDir
    foreach ($j in $stuckJobs) {
        $elapsed = [int]((Get-Date) - $j.StartTime).TotalMinutes
        Write-DailyLog -message "Stuck job detected: Id=$($j.Job.Id) Type=$($j.Type) ChatId=$($j.ChatId) Elapsed=${elapsed}min" -type "WARN"

        $possibleCause = ""
        if ($j.Task -match "imagen|foto|ver|analizar.*imagen|image|photo") {
            $possibleCause = "`n`n*Possible cause:* OpenCode/Minimax does not have reliable vision support for this task. The orchestrator can already analyze images directly."
        }
        elseif ($j.Task -match "pdf|document|binary file") {
            $possibleCause = "`n`n*Possible cause:* The model may struggle with binary files."
        }
        else {
            $possibleCause = "`n`n*Possible cause:* The task may require capabilities the model does not have."
        }

        $emojiWarn = [char]::ConvertFromUtf32(0x26A0)
        $errMsg = "$emojiWarn *Stuck task detected* ($($j.Type))`n"
        $errMsg += "The task has been unresponsive for *$elapsed minutes*.`n"
        $errMsg += "_Task:_ $($j.Task.Substring(0, [Math]::Min(100, $j.Task.Length)))..."
        $errMsg += $possibleCause
        $errMsg += "`n`n_The orchestrator cancelled this task._"
        Send-TelegramText -chatId $j.ChatId -text $errMsg

        if ($j.CheckpointPath) {
            try {
                Update-TaskCheckpointState -CheckpointPath $j.CheckpointPath -TaskText $j.Task -Status "stuck" -LastAction "Task cancelled by stuck-job guard" -LastError "OpenCode task became unresponsive after $elapsed minutes."
            }
            catch {
                Write-DailyLog -message "Checkpoint update failed for stuck job $($j.Job.Id): $_" -type "WARN"
            }
        }

        Stop-Job -Job $j.Job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
        Remove-ActiveJobById -JobId $j.Job.Id
        Write-JobsFile
    }
}

function Invoke-JobMaintenanceCycle {
    param(
        [string]$WorkDir
    )

    Update-ActiveJobTelemetry -WorkDir $WorkDir
    Complete-ActiveJobs -WorkDir $WorkDir
    Expire-PendingConfirmations
    Remove-StuckJobs -WorkDir $WorkDir
}
