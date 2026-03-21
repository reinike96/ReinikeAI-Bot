function Invoke-ModelResponseWithFallback {
    param(
        [string]$ChatId,
        [array]$Messages
    )

    $result = [ordered]@{
        Success = $false
        Response = ""
        AbortTurn = $false
    }

    $aiResp = Invoke-OpenRouter -model (Get-CurrentMainModel) -messages $Messages -reasoningEffort (Get-CurrentReasoningEffort)

    if ([string]::IsNullOrWhiteSpace($aiResp)) {
        Write-DailyLog -message "Primary AI returned empty output. Trying fallback with $(Get-SecondaryMainModel)..." -type "WARN"
        $aiResp = Invoke-OpenRouter -model (Get-SecondaryMainModel) -messages $Messages -reasoningEffort "none"

        if ([string]::IsNullOrWhiteSpace($aiResp)) {
            Write-DailyLog -message "Empty output persisted even with fallback. Aborting turn." -type "WARN"
            Send-TelegramText -chatId $ChatId -text "⚠️ Error: both the primary AI and the fallback returned empty responses. I cannot continue this task."
            $result.AbortTurn = $true
            return [PSCustomObject]$result
        }

        Write-Host "ReinikeAI (FALLBACK): $aiResp" -ForegroundColor Magenta
    }
    else {
        Write-Host "ReinikeAI: $aiResp" -ForegroundColor Cyan
    }

    $result.Success = $true
    $result.Response = $aiResp
    return [PSCustomObject]$result
}

function Initialize-ConversationTurn {
    param(
        [string]$ChatId,
        [string]$AiResponse
    )

    $responseToSave = $AiResponse.Trim()
    if (-not [string]::IsNullOrWhiteSpace($responseToSave)) {
        Add-ChatMemory -chatId $ChatId -role "assistant" -content $responseToSave
    }

    $parsedItems = Convert-AIResponseToActions -Response $AiResponse
    $history = Get-ChatMemory -chatId $ChatId
    $lastUserIndex = Get-LastUserActionBoundary -History $history

    return [PSCustomObject]@{
        ParsedItems = $parsedItems
        History = $history
        LastUserIndex = $lastUserIndex
        ResponseText = ""
        PendingButtons = $null
        BlockedTags = @()
        CurrentTurnTags = @()
        SuppressFinalReply = $false
    }
}

function Update-ConversationTurnState {
    param(
        [object]$TurnState,
        [string]$TextChunk = "",
        [object]$PendingButtons = $null,
        [string]$BlockedTag = $null,
        [string]$ExecutedTag = $null,
        [bool]$SuppressFinalReply = $false
    )

    $safeTextChunk = if ($null -eq $TextChunk) { "" } else { "$TextChunk" }
    if (-not [string]::IsNullOrWhiteSpace($safeTextChunk)) {
        $TurnState.ResponseText += $safeTextChunk
    }
    if ($null -ne $PendingButtons) {
        $TurnState.PendingButtons = $PendingButtons
    }
    if (-not [string]::IsNullOrWhiteSpace($BlockedTag)) {
        $TurnState.BlockedTags += $BlockedTag
    }
    if (-not [string]::IsNullOrWhiteSpace($ExecutedTag)) {
        $TurnState.CurrentTurnTags += $ExecutedTag
    }
    if ($SuppressFinalReply) {
        $TurnState.SuppressFinalReply = $true
    }

    return $TurnState
}

function Finalize-ConversationTurn {
    param(
        [string]$ChatId,
        [string]$AiResponse,
        [object]$TurnState,
        [string]$WorkDir,
        [bool]$RequiresLoop
    )

    $respText = $TurnState.ResponseText.Trim()

    if ($TurnState.BlockedTags.Count -gt 0) {
        $responseToSave = $AiResponse.Trim()
        foreach ($blockedTag in $TurnState.BlockedTags) {
            $responseToSave = $responseToSave -replace [regex]::Escape($blockedTag), ""
        }
        $responseToSave = $responseToSave.Trim()
        Write-Host "[GUARD] Cleaned repeated tags before storing assistant history" -ForegroundColor Gray
        $memAfterLoop = Get-ChatMemory -chatId $ChatId
        if ($memAfterLoop.Count -gt 0 -and $memAfterLoop[-1].role -eq "assistant") {
            $memAfterLoop[-1].content = $responseToSave
            $memAfterLoop | ConvertTo-Json -Depth 10 -Compress | Set-Content "$WorkDir\mem_$ChatId.json" -Encoding UTF8
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($respText) -and -not $RequiresLoop -and -not $TurnState.SuppressFinalReply) {
        if ($null -ne $TurnState.PendingButtons) {
            if ($TurnState.PendingButtons.ContainsKey("buttons")) {
                Send-TelegramText -chatId $ChatId -text $respText -buttons $TurnState.PendingButtons.buttons
            }
            else {
                Send-TelegramButtons -chatId $ChatId -text $respText -buttonsJson $TurnState.PendingButtons.json
            }
        }
        else {
            Send-TelegramText -chatId $ChatId -text $respText
        }
    }
}
