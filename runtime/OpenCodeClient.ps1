function Invoke-OpenRouter {
    param([string]$model, [array]$messages, [string]$reasoningEffort = "minimal")
    $uri = "https://openrouter.ai/api/v1/chat/completions"
    $headers = @{
        "Authorization" = "Bearer $openRouterKey"
        "Content-Type"  = "application/json; charset=utf-8"
        "HTTP-Referer"  = "https://reinikeai.com"
        "X-Title"       = "ReinikeBot"
    }

    $processedMessages = @()
    foreach ($msg in $messages) {
        $msgRole = $msg.role
        $msgContent = $msg.content

        if ($processedMessages.Count -gt 0 -and $processedMessages[-1].role -eq $msgRole) {
            $prev = $processedMessages[-1]
            $prevText = if ($prev.content -is [array]) { ($prev.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join " " } else { "$($prev.content)" }
            $prevNonText = if ($prev.content -is [array]) { @($prev.content | Where-Object { $_.type -ne "text" }) } else { @() }
            $currText = if ($msgContent -is [array]) { ($msgContent | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join " " } else { "$msgContent" }
            $currNonText = if ($msgContent -is [array]) { @($msgContent | Where-Object { $_.type -ne "text" }) } else { @() }

            $mergedParts = @()
            if ($prevNonText.Count -gt 0) { $mergedParts += $prevNonText }
            if ($currNonText.Count -gt 0) { $mergedParts += $currNonText }
            $combinedText = "$prevText`n$currText".Trim()
            if (-not [string]::IsNullOrWhiteSpace($combinedText)) {
                $mergedParts += @{ type = "text"; text = $combinedText }
            }

            if ($mergedParts.Count -eq 1 -and $mergedParts[0].type -eq "text") {
                $processedMessages[-1] = @{ role = $msgRole; content = $mergedParts[0].text }
            }
            else {
                $processedMessages[-1] = @{ role = $msgRole; content = $mergedParts }
            }
        }
        else {
            $processedMessages += @{ role = $msgRole; content = $msgContent }
        }
    }

    $bodyObj = @{
        "model"    = $model
        "messages" = $processedMessages
    }
    if (-not [string]::IsNullOrWhiteSpace($reasoningEffort) -and $reasoningEffort -ne "none") {
        $bodyObj.Add("reasoning", @{ "effort" = $reasoningEffort })
    }

    $bodyJson = $bodyObj | ConvertTo-Json -Depth 10 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $maxAttempts = 3
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $bodyBytes -TimeoutSec 60
            if ($null -eq $response.choices -or $response.choices.Count -eq 0) {
                $errStr = if ($response.error) { $response.error.message } else { "OpenRouter returned neither choices nor an explicit error." }
                Write-DailyLog -message "Fallo en OpenRouter (intento $attempt): $errStr" -type "ERROR"
                if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
                return "[ERROR_API] OpenRouter failed after multiple attempts: $errStr"
            }

            $rawContent = $response.choices[0].message.content
            if ([string]::IsNullOrWhiteSpace($rawContent)) {
                Write-DailyLog -message "OpenRouter returned empty content (attempt $attempt). $model" -type "WARN"
                if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
                return ""
            }
            return $rawContent
        }
        catch {
            $errDetails = if ($_.Exception) { $_.Exception.Message } else { $_.ToString() }
            if ($_.Exception -and $_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errBody = $reader.ReadToEnd()
                    if ($errBody) { $errDetails += " | Response: $errBody" }
                }
                catch {}
            }

            Write-DailyLog -message "Error in Invoke-OpenRouter ($model) attempt ${attempt}: $errDetails" -type "ERROR"
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
            return "[ERROR_API] $errDetails"
        }
    }
}

function Start-OpenCodeJob {
    param(
        [string]$TaskDescription,
        [string]$ChatId,
        [string[]]$EnableMCPs = @(),
        [string]$Model = "",
        [string]$Agent = $null,
        [int]$TimeoutSec = 1200
    )
    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = $botConfig.OpenCode.DefaultModel
    }
    $jobScript = {
        param($taskDescription, $workDir, $archivesDir, $jobId, $enableMCPs, $modelStr, $agentStr, $timeoutSeconds, $openCodeHost, $openCodePort, $openCodePassword)
        Add-Type -AssemblyName System.Net.Http
        function Write-DailyLog {
            param([string]$message, [string]$type = "INFO")
            $logFile = "$workDir\subagent_events.log"
            $currentDate = Get-Date -Format "yyyy-MM-dd"
            $timestamp = Get-Date -Format "HH:mm:ss"
            if (Test-Path $logFile) {
                $lastWrite = (Get-Item $logFile).LastWriteTime.ToString("yyyy-MM-dd")
                if ($lastWrite -ne $currentDate) { Clear-Content $logFile -ErrorAction SilentlyContinue }
            }
            "[$currentDate $timestamp] [$type] $message" | Out-File -FilePath $logFile -Append -Encoding UTF8
        }

        function Write-Heartbeat {
            param($jobId, $status)
            $heartbeatFile = "$workDir\heartbeat_$jobId.json"
            @{ jobId = $jobId; timestamp = (Get-Date).ToString("o"); status = $status } | ConvertTo-Json -Compress | Set-Content $heartbeatFile -Encoding UTF8
        }

        Write-DailyLog -message "OpenCode starting task: $taskDescription" -type "OPENCODE"
        Write-Heartbeat -jobId $jobId -status "starting"

        $openCodeUrl = "http://${openCodeHost}:${openCodePort}"
        $maxTimeout = $timeoutSeconds
        $authBytes = [System.Text.Encoding]::ASCII.GetBytes("opencode:$openCodePassword")
        $authBase64 = [System.Convert]::ToBase64String($authBytes)
        $headers = @{
            Authorization  = "Basic $authBase64"
            "Content-Type" = "application/json; charset=utf-8"
        }

        try {
            Write-Heartbeat -jobId $jobId -status "creating_session"
            Write-DailyLog -message "OpenCode job configuration: agent='$agentStr' model='$modelStr' timeout='${timeoutSeconds}s'" -type "OPENCODE"
            $sessionBody = @{ title = "Telegram" }
            if (-not $agentStr -and -not [string]::IsNullOrWhiteSpace($modelStr)) {
                $sessionBody["model"] = $modelStr
            }
            $sessionBytes = [System.Text.Encoding]::UTF8.GetBytes(($sessionBody | ConvertTo-Json -Compress))

            try {
                $sessionResp = Invoke-RestMethod -Uri "$openCodeUrl/session" -Method Post -Headers $headers -Body $sessionBytes -TimeoutSec 30
                $sessionId = $sessionResp.id
            }
            catch {
                $errContent = ""
                if ($_.Exception -and $_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errContent = $reader.ReadToEnd()
                }
                $errMsg = $_.Exception.Message + " " + $errContent

                if ($errMsg -match "insufficient credits|balance|402|Payment Required") {
                    Write-DailyLog -message "OpenCode insufficient credits: $errMsg" -type "ERROR"
                    return "[ERROR_OPENCODE_CREDITS] OpenCode has insufficient credits. Please check your balance."
                }

                Write-DailyLog -message "Error creating OpenCode session: $errMsg" -type "ERROR"
                return "[ERROR_OPENCODE] Could not create the session: $($_.Exception.Message)"
            }

            if ([string]::IsNullOrWhiteSpace($sessionId)) {
                return "[ERROR_OPENCODE] Could not create the session (empty ID)."
            }
            Write-DailyLog -message "Session created: $sessionId" -type "OPENCODE"
            Write-Heartbeat -jobId $jobId -status "session_ready"

            $msgHash = @{
                parts = @(@{ type = "text"; text = "Working directory: $workDir`nOutput directory for created files: $archivesDir`nTask: $taskDescription`n`nIMPORTANT: Any file you create must be saved in the output directory ($archivesDir). Do not create generated files in the project root ($workDir)." })
            }
            if ($agentStr) { $msgHash.Add("agent", $agentStr) }
            $msgBody = $msgHash | ConvertTo-Json -Depth 5 -Compress
            $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($msgBody)

            Write-Heartbeat -jobId $jobId -status "sending_message"
            Write-DailyLog -message "Sending task to OpenCode session $sessionId" -type "OPENCODE"

            try {
                $responseObj = Invoke-RestMethod -Uri "$openCodeUrl/session/$sessionId/message" -Method Post -Headers $headers -Body $msgBytes -TimeoutSec $maxTimeout
            }
            catch {
                $errContent = ""
                if ($_.Exception -and $_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errContent = $reader.ReadToEnd()
                }
                $errMsg = $_.Exception.Message + " " + $errContent

                if ($errMsg -match "insufficient credits|balance|402|Payment Required") {
                    Write-DailyLog -message "OpenCode insufficient credits during execution: $errMsg" -type "ERROR"
                    return "[ERROR_OPENCODE_CREDITS] OpenCode ran out of credits. The task could not continue."
                }

                Write-DailyLog -message "Error in Invoke-RestMethod (message): $errMsg" -type "ERROR"
                return "[ERROR_OPENCODE] Failed to send the message: $($_.Exception.Message)"
            }

            $resultText = ""
            if ($null -ne $responseObj.parts) {
                $textParts = $responseObj.parts | Where-Object { $_.type -eq "text" -and $null -ne $_.text }
                $resultText = ($textParts | ForEach-Object { $_.text }) -join "`n"
            }

            if ($resultText -match '\[CANNOT_COMPLETE:\s*(.+?)\]') {
                $reason = $matches[1]
                Write-DailyLog -message "OpenCode cannot complete task: $reason" -type "WARN"
                return "[ERROR_OPENCODE] The model reported it cannot complete this task: $reason"
            }

            if (-not [string]::IsNullOrWhiteSpace($resultText)) {
                $preview = $resultText.Substring(0, [Math]::Min(180, $resultText.Length)).Replace("`r", " ").Replace("`n", " ")
                Write-DailyLog -message "OpenCode response OK: len=$($resultText.Length) preview='$preview'" -type "OPENCODE"
                Write-Heartbeat -jobId $jobId -status "completed"
                return $resultText
            }
            else {
                $rawDebug = $responseObj | ConvertTo-Json -Depth 10 -Compress
                Write-DailyLog -message "OpenCode returned an empty response. Raw: $rawDebug" -type "WARN"
                return "[ERROR_OPENCODE] Empty response"
            }
        }
        catch {
            Write-DailyLog -message "Error in OpenCode: $_" -type "ERROR"
            return "[ERROR_OPENCODE] $($_.Exception.Message)"
        }
        finally {
            $heartbeatFile = "$workDir\heartbeat_$jobId.json"
            if (Test-Path $heartbeatFile) { Remove-Item $heartbeatFile -Force -ErrorAction SilentlyContinue }
        }
    }

    $jobId = [Guid]::NewGuid().ToString()
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $TaskDescription, $workDir, $archivesDir, $jobId, $EnableMCPs, $Model, $Agent, $TimeoutSec, $botConfig.OpenCode.Host, $botConfig.OpenCode.Port, $botConfig.OpenCode.ServerPassword
    $labelSuffix = if ($EnableMCPs.Count -gt 0) { " (MCP: $($EnableMCPs -join ','))" } else { "" }
    if ($Agent) { $labelSuffix += " [Agent: $Agent]" }
    return @{
        Job          = $job
        ChatId       = $ChatId
        Task         = $TaskDescription
        Label        = "OpenCode HTTP$labelSuffix"
        Type         = "OpenCode"
        StartTime    = Get-Date
        LastTyping   = $null
        LastReport   = Get-Date
        LastStatusId = $null
        OutputBuffer = @()
        TimeoutSec   = $TimeoutSec
    }
}
