function Add-PendingChat {
    param(
        [string]$ChatId
    )

    Add-PendingChatId -ChatId $ChatId
}

function Get-BotConfigFromQueueScope {
    try {
        return (Get-Variable -Name botConfig -Scope Script -ValueOnly -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Get-LatestUserMessageText {
    param([array]$History)

    if ($null -eq $History) {
        return ""
    }

    for ($index = $History.Count - 1; $index -ge 0; $index--) {
        $item = $History[$index]
        if ($null -eq $item) {
            continue
        }

        if ("$($item.role)" -ne "user") {
            continue
        }

        $content = "$($item.content)"
        if ($content -match '^\[SYSTEM\]') {
            continue
        }

        return $content.Trim()
    }

    return ""
}

function Get-ResumeDirectiveForChat {
    param(
        [string]$ChatId,
        [array]$History
    )

    $lastUserText = Get-LatestUserMessageText -History $History
    if ([string]::IsNullOrWhiteSpace($lastUserText) -or $lastUserText -notmatch '(?i)^\s*(continua|continue|resume|reanuda|retoma|seguir|sigue)\s*[.!]*\s*$') {
        return ""
    }

    $cfg = Get-BotConfigFromQueueScope
    if ($null -eq $cfg) {
        return ""
    }

    $root = Get-TaskCheckpointRoot -BotConfig $cfg -ChatId $ChatId
    $candidateFiles = @(Get-ChildItem -Path $root -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($candidate in $candidateFiles) {
        $checkpoint = Read-TaskCheckpoint -CheckpointPath $candidate.FullName
        if ($null -eq $checkpoint) {
            continue
        }

        if ("$($checkpoint.status)" -ne "waiting_for_login") {
            continue
        }

        $subject = "$($checkpoint.subject)".Trim()
        if ([string]::IsNullOrWhiteSpace($subject)) {
            continue
        }

        return "[SYSTEM]: The user asked to continue. Resume this exact paused task from the saved checkpoint instead of starting a new workflow:`n$subject"
    }

    return ""
}

function Get-SystemStatusReport {
    param(
        [string]$WorkDir
    )

    $statusMsg = "*System Status:*`n"
    $activeJobs = Get-ActiveJobs
    $pendingConfirmations = Get-PendingConfirmations

    if ($activeJobs.Count -eq 0) {
        $statusMsg += "No active background tasks.`n"
    }
    else {
        $statusMsg += "Active tasks: $($activeJobs.Count)`n"
        foreach ($j in $activeJobs) {
            $elapsed = New-TimeSpan -Start $j.StartTime -End (Get-Date)
            $statusMsg += "- *Type:* $($j.Type) | *Task:* $($j.Task) | *Time:* $($elapsed.Minutes)m $($elapsed.Seconds)s`n"
            if ($j.SessionId) {
                $statusMsg += "  (Session: ``$($j.SessionId)``)`n"
            }
            if ($j.Capability) {
                $statusMsg += "  (Capability: ``$($j.Capability)`` | Risk: ``$($j.CapabilityRisk)`` | Mode: ``$($j.ExecutionMode)``)`n"
            }
        }
    }

    if ($pendingConfirmations.Count -gt 0) {
        $statusMsg += "`nPending confirmations: $($pendingConfirmations.Count)`n"
    }

    $logPath = Join-Path $WorkDir "subagent_events.log"
    if (Test-Path $logPath) {
        $lastEvents = Get-Content $logPath -Tail 3
        if ($lastEvents) {
            $statusMsg += "`n*Latest OpenCode events:*`n"
            foreach ($e in $lastEvents) {
                $statusMsg += "``$e```n"
            }
        }
    }

    return $statusMsg
}

function Invoke-ModelTurnWithTyping {
    param(
        [string]$ChatId,
        [array]$Messages,
        [string]$ApiUrl
    )

    Send-TelegramTyping -chatId $ChatId
    $typingJob = Start-Job -ScriptBlock {
        param($chatId, $apiUrl)
        while ($true) {
            Start-Sleep -Seconds 4
            try {
                Invoke-RestMethod -Uri "$apiUrl/sendChatAction" -Method Post -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes((@{ chat_id = $chatId; action = "typing" } | ConvertTo-Json -Compress))) -ErrorAction SilentlyContinue | Out-Null
            }
            catch {}
        }
    } -ArgumentList $ChatId, $ApiUrl

    try {
        return Invoke-ModelResponseWithFallback -ChatId $ChatId -Messages $Messages
    }
    finally {
        Stop-Job -Job $typingJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $typingJob -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Invoke-PendingChatProcessing {
    param(
        [string]$FullSystemPrompt,
        [string]$ApiUrl,
        [string]$WorkDir
    )

    $chatId = Pop-PendingChat
    if ([string]::IsNullOrWhiteSpace($chatId)) {
        return
    }

    $loopCount = 0
    $requiresLoop = $true

    while ($requiresLoop -and $loopCount -lt 5) {
        $requiresLoop = $false
        $loopCount++

        $history = Get-ChatMemory -chatId $chatId
        $msgs = @(@{ role = "system"; content = $FullSystemPrompt })
        $resumeDirective = Get-ResumeDirectiveForChat -ChatId $chatId -History $history
        if (-not [string]::IsNullOrWhiteSpace($resumeDirective)) {
            $msgs += @{ role = "system"; content = $resumeDirective }
        }
        $msgs += $history

        $modelTurn = Invoke-ModelTurnWithTyping -ChatId $chatId -Messages $msgs -ApiUrl $ApiUrl
        Optimize-ChatMemory -chatId $chatId

        if ($modelTurn.AbortTurn) {
            $requiresLoop = $false
            break
        }

        $aiResp = $modelTurn.Response
        $turnState = Initialize-ConversationTurn -ChatId $chatId -AiResponse $aiResp

        foreach ($item in $turnState.ParsedItems) {
            if ($item.Kind -eq "text") {
                $turnState = Update-ConversationTurnState -TurnState $turnState -TextChunk $item.Content
                continue
            }

            $validation = Test-ActionAgainstSchema -Item $item
            if (-not $validation.IsValid) {
                Invoke-ActionValidationGuard -ChatId $chatId -Item $item -Error $validation.Error
                $requiresLoop = $true
                $turnState = Update-ConversationTurnState -TurnState $turnState -BlockedTag $item.Raw
                continue
            }

            $tag = $item.Raw
            $alreadyExecuted = Test-ActionAlreadyExecuted -Tag $tag -History $turnState.History -LastUserIndex $turnState.LastUserIndex -CurrentTurnTags $turnState.CurrentTurnTags

            if ($alreadyExecuted) {
                Invoke-RepeatedActionGuard -ChatId $chatId -Tag $tag
                $requiresLoop = $true
                $turnState = Update-ConversationTurnState -TurnState $turnState -BlockedTag $tag
                continue
            }

            $turnState = Update-ConversationTurnState -TurnState $turnState -ExecutedTag $tag
            $actionResult = Invoke-ParsedAction -Item $item -ChatId $chatId -LastUserIndex $turnState.LastUserIndex -UserId $chatId
            if ($actionResult.RequiresLoop) {
                $requiresLoop = $true
            }
            if ($null -ne $actionResult.PendingButtons) {
                $turnState = Update-ConversationTurnState -TurnState $turnState -PendingButtons $actionResult.PendingButtons
            }
            if (-not [string]::IsNullOrWhiteSpace("$($actionResult.BlockedTag)")) {
                $turnState = Update-ConversationTurnState -TurnState $turnState -BlockedTag $actionResult.BlockedTag
            }
            if ($actionResult.SuppressFinalReply) {
                $turnState = Update-ConversationTurnState -TurnState $turnState -SuppressFinalReply $true
            }
        }

        Finalize-ConversationTurn -ChatId $chatId -AiResponse $aiResp -TurnState $turnState -WorkDir $WorkDir -RequiresLoop $requiresLoop
    }
}
