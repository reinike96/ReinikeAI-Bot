function Add-PendingChat {
    param(
        [string]$ChatId
    )

    Add-PendingChatId -ChatId $ChatId
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
        $msgs = @(@{ role = "system"; content = $FullSystemPrompt }) + $history

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
        }

        Finalize-ConversationTurn -ChatId $chatId -AiResponse $aiResp -TurnState $turnState -WorkDir $WorkDir -RequiresLoop $requiresLoop
    }
}
